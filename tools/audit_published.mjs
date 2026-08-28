#!/usr/bin/env node
// 受管理內容「Published 授權」健檢（#8/#9）。**唯讀、fail-closed。**
//
// 硬性保證（對應需求「如果建立 production audit runner，必須 fail-closed」）：
//  - 缺 production credentials → 直接 fail（exit 1），不做任何連線。
//  - **絕不 fallback 到 local DB / emulator**：偵測到 FIRESTORE_EMULATOR_HOST 立即中止。
//  - 只讀（.get()），不執行任何 mutation。
//
// 用法（由使用者本人在可信環境執行；本 session 不對 production 執行）：
//   GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json node tools/audit_published.mjs
//   （或 FIREBASE_SERVICE_ACCOUNT=<json 內容>）
//
// 產出：各受管理 collection 的 published / 非 published / 缺 status / 缺 version /
// 缺 provenance 統計，以及「不該外流卻可能外流」的風險項；workspace collection
// 若含 published 文件也會標記。回傳非 0 exit code 代表發現需處理的問題。

import process from 'node:process';

const MANAGED = ['annotations', 'knowledge', 'daily_verses', 'public_notes', 'reading_plans'];
const WORKSPACES = MANAGED.map((c) => `${c}_workspace`);
const VALID_STATUS = new Set(['draft', 'review', 'published', 'rejected', 'archived']);

function die(msg) {
  console.error(`[audit] FAIL-CLOSED: ${msg}`);
  process.exit(1);
}

// ---- fail-closed 前置檢查 ----
if (process.env.FIRESTORE_EMULATOR_HOST) {
  die('偵測到 FIRESTORE_EMULATOR_HOST——本工具禁止連 emulator/local，只針對真正的 production。');
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
  die("未安裝 firebase-admin。請先在 tools/ 執行 `npm install`。");
}

let credential;
try {
  credential = hasInline
    ? admin.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT))
    : admin.credential.applicationDefault();
} catch (e) {
  die(`無法載入 credentials：${e.message}`);
}

admin.initializeApp({ credential });
const db = admin.firestore();
// 再次確保不是 emulator（firebase-admin 也會讀 FIRESTORE_EMULATOR_HOST）。
if (process.env.FIRESTORE_EMULATOR_HOST) die('emulator 環境變數在初始化後出現，中止。');

const report = { generatedAt: new Date().toISOString(), collections: {}, issues: [] };

function checkMeta(col, id, d) {
  const problems = [];
  if (!('status' in d)) problems.push('missing status');
  else if (!VALID_STATUS.has(d.status)) problems.push(`invalid status '${d.status}'`);
  if (d.status === 'published') {
    if (typeof d.version !== 'number') problems.push('published but missing/invalid version');
    if (!d.provenance) problems.push('published but missing provenance');
    if (!d.content_type) problems.push('published but missing content_type');
    if (!d.content_id) problems.push('published but missing content_id');
  }
  if (problems.length) report.issues.push({ collection: col, id, problems });
  return problems.length === 0;
}

for (const col of MANAGED) {
  const snap = await db.collection(col).get(); // 只讀
  let published = 0, nonPublished = 0, clean = 0;
  snap.forEach((doc) => {
    const d = doc.data();
    if (d.status === 'published' || d.published === true) published++;
    else nonPublished++;
    if (checkMeta(col, doc.id, d)) clean++;
  });
  report.collections[col] = { total: snap.size, published, nonPublished, clean };
}

// workspace 不該含 published（草稿不能是 live）——若有，標為風險。
for (const col of WORKSPACES) {
  const snap = await db.collection(col).where('status', '==', 'published').get();
  if (!snap.empty) {
    report.issues.push({
      collection: col,
      id: '(query)',
      problems: [`workspace 內有 ${snap.size} 筆 status=published（草稿集合不應含 live 內容）`],
    });
  }
}

// questions：published==true 但無 answer → 不該外流。
{
  const snap = await db.collection('questions').where('published', '==', true).get();
  let noAnswer = 0;
  snap.forEach((doc) => { if (!doc.data().answer) noAnswer++; });
  report.collections['questions'] = { publishedTotal: snap.size, publishedWithoutAnswer: noAnswer };
  if (noAnswer > 0) {
    report.issues.push({
      collection: 'questions',
      id: '(query)',
      problems: [`${noAnswer} 筆 published==true 但沒有 answer（不該對外可讀）`],
    });
  }
}

console.log(JSON.stringify(report, null, 2));
if (report.issues.length > 0) {
  console.error(`\n[audit] 發現 ${report.issues.length} 項問題（見上）。`);
  process.exit(2);
}
console.error('\n[audit] 通過：所有受管理內容皆有正確的 status/version/provenance。');
process.exit(0);
