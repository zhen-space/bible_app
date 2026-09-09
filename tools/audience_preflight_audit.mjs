#!/usr/bin/env node
// Production audience-migration **read-only** preflight audit（Church/Teacher R1 rollout）。
//
// 掃描（**絕不寫入**）：annotations / study_content / study_topics / teacher_books /
// collectionGroup('chapters') / questions，統計每個 collection 的 audience 狀態，得出
// migration 是否 REQUIRED。此工具**沒有 --apply、沒有任何 write**；純 get/list。
//
// ⛔ 不寫、不刪、不 deploy、不碰 users/memberships/{uid}。只需 **read-only** credential。
//
// 用法（使用者本人在 Mac，read-only credential）：
//   EXPECTED_PROJECT=bible-app-c0eac \
//   GOOGLE_APPLICATION_CREDENTIALS=/path/readonly-sa.json \
//   node tools/audience_preflight_audit.mjs
// exit：0 = NOT REQUIRED（全部已就緒）、2 = REQUIRED（有 doc 需 migration/manual）、
//       1 = credential/project/emulator safety failure（＝本工具無法判定 → 視為 UNKNOWN）。

import process from 'node:process';
import { readFileSync } from 'node:fs';

const VALID = new Set(['public', 'church', 'internal']);

// ---- 純函式分類（可測、無 IO）----
/** data＝doc 內容；publishedFlag＝此 doc 是否為「已對學生服務」（questions: published==true；
 *  其餘: status=='published'）。回傳各旗標供聚合。 */
export function classifyDoc(data, { published }) {
  const aud = data.audience;
  const hasAud = typeof aud === 'string' && aud.length > 0;
  const valid = hasAud && VALID.has(aud);
  const invalid = hasAud && !valid; // 有值但不在枚舉內 → 不可 silent overwrite（manual）
  const missing = !hasAud; // 完全無 audience → 可由 migrate_audience 補（auto）
  const allowed = Array.isArray(data.allowed_church_ids) ? data.allowed_church_ids : null;
  const churchEmptyAllowed =
    aud === 'church' && (allowed === null || allowed.length === 0);
  const legacyVisibilityOnly =
    missing && typeof data.visibility === 'string' && data.visibility.length > 0;
  return {
    published: !!published,
    audPublic: aud === 'public',
    audChurch: aud === 'church',
    audInternal: aud === 'internal',
    missing,
    invalid,
    churchEmptyAllowed,
    legacyVisibilityOnly,
  };
}

function emptyStats() {
  return {
    total: 0, published: 0,
    audiencePublic: 0, audienceChurch: 0, audienceInternal: 0,
    missingAudience: 0, invalidAudience: 0,
    churchEmptyAllowed: 0, legacyVisibilityOnly: 0,
    // auto＝migrate_audience 會補（缺 audience）；manual＝需人工（invalid / church 空 allowed）。
    needsMigrationAuto: 0, needsManualReview: 0,
  };
}

function accumulate(stats, c) {
  stats.total++;
  if (c.published) stats.published++;
  if (c.audPublic) stats.audiencePublic++;
  if (c.audChurch) stats.audienceChurch++;
  if (c.audInternal) stats.audienceInternal++;
  if (c.missing) { stats.missingAudience++; stats.needsMigrationAuto++; }
  if (c.invalid) { stats.invalidAudience++; stats.needsManualReview++; }
  if (c.churchEmptyAllowed) { stats.churchEmptyAllowed++; stats.needsManualReview++; }
  if (c.legacyVisibilityOnly) stats.legacyVisibilityOnly++;
}

function die(msg) { console.error(`[audience-audit] FAIL: ${msg}`); process.exit(1); }

const isMain = import.meta.url === `file://${process.argv[1]}`;
if (isMain) await main();

async function main() {
  if (process.env.FIRESTORE_EMULATOR_HOST) die('偵測到 FIRESTORE_EMULATOR_HOST——禁止連 emulator/local。');
  const hasAdc = !!process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const hasInline = !!process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!hasAdc && !hasInline) die('缺少 production read credentials。');

  let admin;
  try { admin = (await import('firebase-admin')).default; }
  catch { die('未安裝 firebase-admin。請先在 tools/ 執行 `npm install`。'); }

  let credential, projectId;
  try {
    if (hasInline) {
      const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
      credential = admin.credential.cert(sa); projectId = sa.project_id;
    } else {
      try { projectId = JSON.parse(readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8')).project_id; } catch {}
      credential = admin.credential.applicationDefault();
    }
  } catch (e) { die(`無法載入 credentials：${e.message}`); }
  projectId = projectId || process.env.GOOGLE_CLOUD_PROJECT;
  if (process.env.EXPECTED_PROJECT && projectId && process.env.EXPECTED_PROJECT !== projectId) {
    die(`target '${projectId}' 與 EXPECTED_PROJECT '${process.env.EXPECTED_PROJECT}' 不符——中止。`);
  }
  console.error(`[audience-audit] TARGET: ${projectId || '(SDK 推斷)'} — READ-ONLY`);

  admin.initializeApp(projectId ? { credential, projectId } : { credential });
  const db = admin.firestore();
  if (process.env.FIRESTORE_EMULATOR_HOST) die('emulator 環境變數在初始化後出現，中止。');

  const report = {
    targetProject: projectId || '(SDK 推斷)',
    mode: 'read-only-audit',
    generatedAt: new Date().toISOString(),
    collections: {},
    usersReadCount: 0, usersWriteCount: 0, // 硬性 0：不觸碰 users
  };

  // (collectionName, isGroup, publishedField)
  const targets = [
    ['annotations', false, 'status'],
    ['study_content', false, 'status'],
    ['study_topics', false, 'status'],
    ['teacher_books', false, 'status'],
    ['chapters', true, 'status'], // teacher_books/{id}/chapters → collectionGroup
    ['questions', false, 'published'],
  ];

  for (const [name, isGroup, pubField] of targets) {
    const stats = emptyStats();
    const snap = isGroup
      ? await db.collectionGroup(name).get()
      : await db.collection(name).get();
    for (const doc of snap.docs) {
      const data = doc.data();
      const published = pubField === 'published'
        ? data.published === true
        : data.status === 'published';
      accumulate(stats, classifyDoc(data, { published }));
    }
    report.collections[name] = stats;
  }

  // 總結 verdict。
  let auto = 0, manual = 0;
  for (const s of Object.values(report.collections)) {
    auto += s.needsMigrationAuto; manual += s.needsManualReview;
  }
  report.totalNeedsMigrationAuto = auto;
  report.totalNeedsManualReview = manual;
  report.verdict = (auto === 0 && manual === 0) ? 'NOT_REQUIRED' : 'REQUIRED';

  console.log(JSON.stringify(report, null, 2));
  process.exit(report.verdict === 'NOT_REQUIRED' ? 0 : 2);
}
