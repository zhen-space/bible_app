#!/usr/bin/env node
// Strictly read-only reconciliation for a Daily Verse date window.
// It performs exact document reads only and contains no write API calls.

import admin from 'firebase-admin';
import {execFileSync} from 'node:child_process';

function die(message) {
  console.error(message);
  process.exit(2);
}

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : null;
}

const projectId = arg('project');
const start = arg('start');
const end = arg('end');
if (!projectId || !start || !end) {
  die('Usage: node audit_daily_verse_window.mjs --project PROJECT --start YYYY-MM-DD --end YYYY-MM-DD');
}
if (process.env.FIRESTORE_EMULATOR_HOST) {
  die('FIRESTORE_EMULATOR_HOST is set; refusing ambiguous production audit.');
}

const ymd = /^\d{4}-\d{2}-\d{2}$/;
if (!ymd.test(start) || !ymd.test(end) || start > end) die('Invalid date window.');

const useGcloudUser = process.argv.includes('--use-gcloud-user');
const credential = useGcloudUser
  ? {
      getAccessToken: async () => ({
        access_token: execFileSync('gcloud', ['auth', 'print-access-token'], {
          encoding: 'utf8',
          stdio: ['ignore', 'pipe', 'ignore'],
        }).trim(),
        expires_in: 3600,
      }),
    }
  : admin.credential.applicationDefault();
admin.initializeApp({credential, projectId});
const db = admin.firestore();

function addDay(value) {
  const d = new Date(`${value}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
}

const rows = [];
for (let date = start; date <= end; date = addDay(date)) {
  const [ws, pub] = await Promise.all([
    db.collection('daily_verses_workspace').doc(date).get(),
    db.collection('daily_verses').doc(date).get(),
  ]);
  const w = ws.data() ?? null;
  const p = pub.data() ?? null;
  const anomalies = [];
  if (w && w.content_id !== date) anomalies.push('workspace_content_id_mismatch');
  if (w && !['draft', 'review', 'rejected', 'published', 'archived'].includes(w.status)) {
    anomalies.push('workspace_status_missing_or_unknown');
  }
  if (p && p.status !== 'published') anomalies.push('mirror_not_published');
  if (p?.versions != null && !Array.isArray(p.versions)) anomalies.push('versions_not_array');
  rows.push({
    date,
    workspace_count: ws.exists ? 1 : 0,
    workspace_status: w?.status ?? null,
    published_count: pub.exists ? 1 : 0,
    published_status: p?.status ?? null,
    published_revision_count: pub.exists ? 1 + (Array.isArray(p.versions) ? p.versions.length : 0) : 0,
    anomalies,
  });
}

const status = {};
for (const row of rows) {
  if (row.workspace_count) status[row.workspace_status ?? 'missing'] = (status[row.workspace_status ?? 'missing'] ?? 0) + 1;
}
const summary = {
  project: projectId,
  start,
  end,
  dates: rows.length,
  workspaces: rows.reduce((n, r) => n + r.workspace_count, 0),
  workspace_status: status,
  published_docs: rows.reduce((n, r) => n + r.published_count, 0),
  published_revisions: rows.reduce((n, r) => n + r.published_revision_count, 0),
  anomaly_dates: rows.filter(r => r.anomalies.length).length,
  writes: 0,
};

console.log(JSON.stringify({summary, rows}, null, 2));
await admin.app().delete();
