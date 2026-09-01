#!/usr/bin/env node
// Legacy `knowledge/data` aggregate → 個別 `study_content/{id}` 文件的 migration。
//
// 硬性契約（見交接 spec 12）：
//  - **additive**（只新增 study_content 文件；**永不刪除或修改 knowledge/data**）。
//  - **dry-run capable**（預設 dry-run，只印計畫；--apply 才寫入）。
//  - **deterministic + idempotent + collision-aware**：id 由 FNV-1a-64 內容 hash 決定
//    （人物沿用 legacy stable id），重跑同資料 → 同 id；已存在則 skip（不覆蓋管理員後續編輯）。
//  - **任何 migrated item 一律 visibility='internal'**（絕不自動 student）。
//  - status：若 knowledge/data 可確認 status=='published' → items 亦 published(version 1)；
//    否則 **fail-closed** → draft(version 0)，寫入 study_content_workspace。
//  - fail-closed 前置：偵測 emulator 或缺 credentials 立即中止，不 fallback local。
//
// ⚠️ id 演算法必須與 lib/models/study_content.dart 的 StudyContentMigration **完全一致**。
//    兩邊同步修改，否則重跑會產生不同 id（破壞 idempotency）。有 Dart 測試守著跨語言向量。
//
// 用法（本 session 不對 production 執行；由使用者本人在可信環境）：
//   dry-run:  GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json node tools/migrate_knowledge.mjs
//   apply:    GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json node tools/migrate_knowledge.mjs --apply

import process from 'node:process';
import { readFileSync } from 'node:fs';

const APPLY = process.argv.includes('--apply');

function die(msg) {
  console.error(`[migrate] FAIL-CLOSED: ${msg}`);
  process.exit(1);
}

// ---- 確定性 id（與 Dart StudyContentMigration 對齊）----
export function fnv1a64(str) {
  const mask = (1n << 64n) - 1n;
  let hash = 0xcbf29ce484222325n;
  const prime = 0x100000001b3n;
  for (const b of Buffer.from(str, 'utf8')) {
    hash = (hash ^ BigInt(b)) & mask;
    hash = (hash * prime) & mask;
  }
  return hash.toString(16).padStart(16, '0');
}
const stableId = (typeWire, canonical) => `${typeWire}__${fnv1a64(canonical)}`;

// ---- 純映射：KnowledgeBase(JSON) → 計畫中的 study_content 文件 ----
export function planItems(knowledge, aggregatePublished) {
  const status = aggregatePublished ? 'published' : 'draft';
  const version = aggregatePublished ? 1 : 0;
  const items = [];
  const prov = (category, legacyIdentifier) => ({
    source: 'migrated_legacy',
    note: JSON.stringify({
      legacy_aggregate: 'knowledge/data',
      legacy_category: category,
      legacy_identifier: legacyIdentifier,
    }),
  });
  const base = (typeWire, id, provenance, { title = '', body = '', refs = [], data = {} }) => ({
    id,
    content_id: id,
    content_type: typeWire,
    status,
    version,
    visibility: 'internal', // ← 硬性：永遠 internal
    provenance,
    title,
    body,
    scripture_refs: refs,
    topic_ids: [],
    tags: [],
    data,
  });

  for (const p of knowledge.parallels ?? []) {
    const refs = (p.refs ?? []).map(String);
    const canonical = `parallel|${p.title ?? ''}|${refs.join(',')}`;
    items.push(base('parallel', stableId('parallel', canonical), prov('parallels', canonical),
      { title: p.title ?? '', refs, data: p }));
  }
  for (const t of knowledge.types ?? []) {
    const canonical = `type|${t.title ?? ''}|${t.otRef ?? ''}|${t.ntRef ?? ''}`;
    const refs = [t.otRef, t.ntRef].filter((x) => x);
    items.push(base('type', stableId('type', canonical), prov('types', canonical),
      { title: t.title ?? '', body: t.note ?? '', refs, data: t }));
  }
  for (const e of knowledge.timeline ?? []) {
    const canonical = `timeline|${e.era ?? ''}|${e.title ?? ''}|${e.when ?? ''}|${e.ref ?? ''}`;
    const refs = e.ref ? [e.ref] : [];
    items.push(base('timeline', stableId('timeline', canonical), prov('timeline', canonical),
      { title: e.title ?? '', body: e.when ?? '', refs, data: e }));
  }
  for (const person of knowledge.people ?? []) {
    const legacyId = person.id
      ? person.id
      : `anon__${fnv1a64(`person|${person.name ?? ''}|${person.bio ?? ''}`)}`;
    const id = `person__${legacyId}`;
    const refs = (person.events ?? []).map((ev) => ev.ref).filter((x) => x);
    items.push(base('person', id, prov('people', legacyId),
      { title: person.name ?? '', body: person.bio ?? '', refs, data: person }));
  }
  return items;
}

// module 被 import 當測試工具時，不連 Firestore。
const isMain = import.meta.url === `file://${process.argv[1]}`;
if (!isMain) {
  // exported for tests
} else {
  await main();
}

async function main() {
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    die('偵測到 FIRESTORE_EMULATOR_HOST——禁止連 emulator/local。');
  }
  const hasAdc = !!process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const hasInline = !!process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!hasAdc && !hasInline) {
    die('缺少 production credentials（GOOGLE_APPLICATION_CREDENTIALS 或 FIREBASE_SERVICE_ACCOUNT）。');
  }

  let admin;
  try {
    admin = (await import('firebase-admin')).default;
  } catch {
    die('未安裝 firebase-admin。請先在 tools/ 執行 `npm install`。');
  }

  let credential;
  let projectId;
  try {
    if (hasInline) {
      const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
      credential = admin.credential.cert(sa);
      projectId = sa.project_id;
    } else {
      try {
        const sa = JSON.parse(readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8'));
        projectId = sa.project_id;
      } catch { /* SDK 推斷 */ }
      credential = admin.credential.applicationDefault();
    }
  } catch (e) {
    die(`無法載入 credentials：${e.message}`);
  }
  projectId = projectId || process.env.GOOGLE_CLOUD_PROJECT;
  if (process.env.EXPECTED_PROJECT && projectId && process.env.EXPECTED_PROJECT !== projectId) {
    die(`target project '${projectId}' 與 EXPECTED_PROJECT '${process.env.EXPECTED_PROJECT}' 不符——中止。`);
  }
  console.error(`[migrate] TARGET PROJECT: ${projectId || '(SDK 推斷)'} — mode=${APPLY ? 'APPLY' : 'DRY-RUN'}`);

  admin.initializeApp(projectId ? { credential, projectId } : { credential });
  const db = admin.firestore();
  if (process.env.FIRESTORE_EMULATOR_HOST) die('emulator 環境變數在初始化後出現，中止。');

  const snap = await db.doc('knowledge/data').get(); // 只讀 legacy，絕不修改
  if (!snap.exists) {
    console.log(JSON.stringify({ knowledgeExists: false, planned: 0 }, null, 2));
    console.error('[migrate] knowledge/data 不存在，無可 migrate 項目。');
    process.exit(0);
  }
  const data = snap.data();
  const aggregatePublished = data.status === 'published';
  const now = Date.now();
  const items = planItems(data, aggregatePublished);

  const summary = { aggregatePublished, planned: items.length, byCategory: {}, created: 0, skipped: 0, targetOfDrafts: 'study_content_workspace', targetOfPublished: 'study_content' };
  for (const it of items) summary.byCategory[it.content_type] = (summary.byCategory[it.content_type] ?? 0) + 1;

  for (const it of items) {
    const targetCol = it.status === 'published' ? 'study_content' : 'study_content_workspace';
    const ref = db.collection(targetCol).doc(it.id);
    const existing = await ref.get();
    if (existing.exists) { summary.skipped++; continue; }
    if (APPLY) {
      const { id, ...doc } = it;
      await ref.set({
        ...doc,
        created_at: now, created_by: 'migration',
        updated_at: now, updated_by: 'migration',
        reviewed_by: '', reviewed_at: 0,
        published_by: aggregatePublished ? 'migration' : '', published_at: aggregatePublished ? now : 0,
        archived_at: 0,
      }); // additive create（skip-if-exists 已在上面擋掉覆蓋）
    }
    summary.created++;
  }

  console.log(JSON.stringify(summary, null, 2));
  console.error(`[migrate] ${APPLY ? '已寫入' : 'DRY-RUN（未寫入）'}：planned=${summary.planned} create=${summary.created} skip=${summary.skipped}；visibility 全為 internal；knowledge/data 未更動。`);
  process.exit(0);
}
