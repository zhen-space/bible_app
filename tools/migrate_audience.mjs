#!/usr/bin/env node
// Legacy `visibility` → `audience` migration（Church/Teacher R1 §7/§19）。
//
// 對 study_content / study_topics（含各自 workspace）補 `audience`：
//   visibility==student  → audience=public       （原本即全學生可見＝公開）
//   visibility==internal → audience=internal
//   missing/unknown      → audience=internal      （**fail-closed**，不擴大 exposure）
// **絕不自動產生 audience=church**、**絕不自動填 allowed_church_ids**、不擴大未知 exposure。
//
// 硬性：additive、dry-run 預設、deterministic、idempotent（已有 audience 者 skip）、
// fail-closed（缺 creds / 偵測 emulator 立即中止）、不刪任何 legacy、visibility 保留不動。
// **本輪不對 production 執行。** rollback＝還原舊 rules（讀 visibility）或忽略 audience。
//
// 用法（使用者本人在可信環境）：
//   dry-run: GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json node tools/migrate_audience.mjs
//   apply:   GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json node tools/migrate_audience.mjs --apply

import process from 'node:process';
import { readFileSync } from 'node:fs';

const APPLY = process.argv.includes('--apply');
const COLLECTIONS = [
  'study_content', 'study_content_workspace',
  'study_topics', 'study_topics_workspace',
  // annotations：legacy 皆為公開內容 → audience=public（missing→internal fail-closed 亦適用）。
  'annotations', 'annotations_workspace',
];

function die(msg) { console.error(`[migrate-audience] FAIL-CLOSED: ${msg}`); process.exit(1); }

/** 純映射（可測）：legacy doc → 要補的 audience（若已有 audience 則回 null＝skip）。
 *  - study_content/topics：visibility==student→public、其餘→internal（fail-closed）。
 *  - annotations（無 visibility 欄；#8 起「published＝對全學生公開」）：published→public、
 *    其餘→internal。**不擴大 exposure**（published 註解本就 student-visible）。 */
export function audienceFor(doc, { isAnnotation = false } = {}) {
  if (typeof doc.audience === 'string') return null; // idempotent skip
  if (isAnnotation) return doc.status === 'published' ? 'public' : 'internal';
  if (doc.visibility === 'student') return 'public';
  return 'internal'; // internal / missing / unknown → fail-closed internal
}

/** Annotation identity 解耦（§5/§16）：legacy 節註解 doc id `verse_{b}_{c}_{v}` → 正式
 *  scripture lookup 欄位 `verse_key`="b_c_v"。**doc id 保持不變**（不新建 doc、不產生重複、
 *  不 double-render）——annotation_id＝既有 doc id，verse_key＝節位欄位，兩者正式解耦。
 *  非節註解（book_/chapter_/其他）回 null（不加 verse_key）。deterministic、idempotent。 */
export function verseKeyForAnnotationDoc(docId) {
  const m = /^verse_(\d+)_(\d+)_(\d+)$/.exec(docId);
  return m ? `${m[1]}_${m[2]}_${m[3]}` : null;
}

const isMain = import.meta.url === `file://${process.argv[1]}`;
if (isMain) await main();

async function main() {
  if (process.env.FIRESTORE_EMULATOR_HOST) die('偵測到 FIRESTORE_EMULATOR_HOST——禁止連 emulator/local。');
  const hasAdc = !!process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const hasInline = !!process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!hasAdc && !hasInline) die('缺少 production credentials。');

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
  console.error(`[migrate-audience] TARGET: ${projectId || '(SDK 推斷)'} — mode=${APPLY ? 'APPLY' : 'DRY-RUN'}`);

  admin.initializeApp(projectId ? { credential, projectId } : { credential });
  const db = admin.firestore();
  if (process.env.FIRESTORE_EMULATOR_HOST) die('emulator 環境變數在初始化後出現，中止。');

  const summary = { mode: APPLY ? 'apply' : 'dry-run', byCollection: {}, toPublic: 0, toInternal: 0, skipped: 0, churchCreated: 0 };
  for (const col of COLLECTIONS) {
    const snap = await db.collection(col).get(); // 只讀
    let toPublic = 0, toInternal = 0, skipped = 0;
    const isAnnotation = col.startsWith('annotations');
    for (const doc of snap.docs) {
      const data = doc.data();
      const target = audienceFor(data, { isAnnotation });
      if (target === null) { skipped++; continue; }
      if (target === 'public') toPublic++; else toInternal++;
      // annotation：同時補 verse_key（identity 解耦；deterministic，doc id 不變、不建新 doc）。
      const extra = {};
      if (isAnnotation && typeof data.verse_key !== 'string') {
        const vk = verseKeyForAnnotationDoc(doc.id);
        if (vk) extra.verse_key = vk;
      }
      if (APPLY) {
        // additive：補 audience（＋ allowed_church_ids 空陣列作為結構欄位）＋（註解）verse_key，
        // 不動 visibility、不改 doc id、不新建 doc。
        await doc.ref.set({ audience: target, allowed_church_ids: [], ...extra }, { merge: true });
      }
    }
    summary.byCollection[col] = { total: snap.size, toPublic, toInternal, skipped };
    summary.toPublic += toPublic; summary.toInternal += toInternal; summary.skipped += skipped;
  }
  // 不變量：本工具**永不**產生 church audience。
  console.log(JSON.stringify(summary, null, 2));
  console.error(`[migrate-audience] ${APPLY ? '已寫入' : 'DRY-RUN（未寫入）'}：→public=${summary.toPublic} →internal=${summary.toInternal} skip=${summary.skipped} churchCreated=${summary.churchCreated}（必為 0）。visibility 未動、無 church 自動產生。`);
  process.exit(0);
}
