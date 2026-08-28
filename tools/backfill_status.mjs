#!/usr/bin/env node
// Legacy 受管理內容的 additive backfill：補上 status='published' + version +
// provenance + created/updated metadata（#8 需求：additive、backward-compatible、
// 舊資料先保留、不破壞 legacy production documents）。
//
// **預設 DRY-RUN**（只印計畫、不寫入）。加 --apply 才會寫入。
// 本 session 不對 production 執行；由使用者本人在可信環境跑。
//
// fail-closed（同 audit_published.mjs）：
//  - 缺 credentials → exit 1；偵測 emulator → 中止；不 fallback local/emulator。
//  - **只做 additive set(merge)**：僅在欄位缺失時補值；**絕不覆蓋既有 status/version**，
//    絕不刪任何資料，絕不改 payload。
//
// 部署順序：先跑本 backfill（--apply）把 legacy 補成 status='published'，
// **再**部署 firestore.rules；否則未補 status 的 legacy 內容會對學生端 fail-closed。
//
// 用法：
//   node tools/backfill_status.mjs                 # dry-run（印計畫）
//   GOOGLE_APPLICATION_CREDENTIALS=sa.json \
//     node tools/backfill_status.mjs --apply       # 實際寫入（使用者自行執行）

import process from 'node:process';

const APPLY = process.argv.includes('--apply');
// published mirror collections（legacy 直接發佈的內容都在這些）。
const MIRRORS = ['annotations', 'knowledge', 'daily_verses', 'public_notes', 'reading_plans'];

function die(msg) {
  console.error(`[backfill] FAIL-CLOSED: ${msg}`);
  process.exit(1);
}
if (process.env.FIRESTORE_EMULATOR_HOST) {
  die('偵測到 FIRESTORE_EMULATOR_HOST——禁止對 emulator/local 執行。');
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
const credential = hasInline
  ? admin.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT))
  : admin.credential.applicationDefault();
admin.initializeApp({ credential });
const db = admin.firestore();

const now = Date.now();
const plan = []; // {collection, id, adds:{...}}

// 決定某 legacy doc 需要補哪些 additive 欄位（**只補缺的，不覆蓋既有**）。
function additiveFields(d) {
  const adds = {};
  // legacy 直接發佈內容視為 published；daily_verses 舊資料以 published==true 判斷。
  if (!('status' in d)) {
    const looksPublished = d.published === true || d.published === undefined;
    adds.status = looksPublished ? 'published' : 'draft';
  }
  if (!('version' in d)) adds.version = 1;
  if (!('provenance' in d)) adds.provenance = { source: 'legacy-backfill', note: '' };
  if (!('created_at' in d)) adds.created_at = d.approved_at || d.updated_at || now;
  if (!('updated_at' in d)) adds.updated_at = d.updated_at || now;
  if (adds.status === 'published') {
    if (!('published_at' in d)) adds.published_at = d.approved_at || d.updated_at || now;
    if (!('publisher' in d)) adds.publisher = 'legacy-backfill';
  }
  return adds;
}

for (const col of MIRRORS) {
  const snap = await db.collection(col).get(); // 只讀
  snap.forEach((doc) => {
    const adds = additiveFields(doc.data());
    if (Object.keys(adds).length > 0) plan.push({ collection: col, id: doc.id, adds });
  });
}

console.log(`[backfill] ${APPLY ? 'APPLY' : 'DRY-RUN'} — 需補 ${plan.length} 筆（僅補缺欄位，不覆蓋既有）`);
for (const p of plan) {
  console.log(`  ${p.collection}/${p.id}: + ${JSON.stringify(p.adds)}`);
}

if (!APPLY) {
  console.log('\n[backfill] 這是 dry-run。確認無誤後，加 --apply 由你本人執行實際寫入。');
  process.exit(0);
}

let written = 0;
for (const p of plan) {
  // additive merge：只寫入缺的欄位，既有欄位（含 status/version/payload）原封不動。
  await db.collection(p.collection).doc(p.id).set(p.adds, { merge: true });
  written++;
}
console.log(`\n[backfill] 完成，additive 寫入 ${written} 筆。請接著（唯讀）跑 audit_published.mjs 驗證，再部署 firestore.rules。`);
process.exit(0);
