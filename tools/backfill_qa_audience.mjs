#!/usr/bin/env node
// Legacy Q&A audience backfill（Church/Teacher R1 B18/B19 rollout stage）。
//
// TARGET：**`questions` collection only**（另讀 `study_content` 作 source authority）。
// 對「published==true 且有 answer 且 audience 缺失」的 question，**依 AnswerSource 推導**
// serving audience 並「只新增」`audience` / `allowed_church_ids`（additive）。
//
// ⛔ 絕不：改 answer/body/status/published/source、刪任何資料、覆蓋既有 audience、
//    讀或寫 users/memberships。audience 已存在（public/church/internal/invalid）一律 SKIP。
//
// 推導（與 lib/services/qa_service.dart 的 DerivedAnswerAudience 同語意）：
//  - 逐 AnswerSource(kind==study_content) **重讀 live published source doc**（content_id）：
//    不存在→BLOCK_SOURCE_NOT_FOUND；非 published→BLOCK_SOURCE_NOT_PUBLISHED；
//    version≠cited→BLOCK_VERSION_MISMATCH；audience 非 public/church/internal→
//    BLOCK_UNKNOWN_SOURCE_AUDIENCE；internal→BLOCK_INTERNAL_SOURCE。
//  - scripture source 一律 public，不縮小。
//  - 全 public/scripture → public；任一 church → church，allowed_church_ids＝所有 church
//    source 的**交集**（INTERSECTION，非 union）；交集空→BLOCK_EMPTY_CHURCH_INTERSECTION。
//  - 完全沒有 source → MANUAL_SOURCELESS（不自動 public，保持 audience 缺失）。
//  - 任一 block → 該 question 需人工處理（fail-closed，不寫入）。
// **不得用 LLM/Web/timestamp/contentType/category 猜 audience。** snapshot access 只作 evidence。
//
// 用法（使用者本人在可信環境；dry-run 只需 read-only credential）：
//   dry-run: EXPECTED_PROJECT=bible-app-c0eac GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json \
//            node tools/backfill_qa_audience.mjs
//   apply:   （同上）node tools/backfill_qa_audience.mjs --apply
// exit：0=clean plan、2=有 manual/blocking anomalies、1=credential/project/runtime safety failure。

import process from 'node:process';
import { readFileSync } from 'node:fs';

const APPLY = process.argv.includes('--apply');
const VALID_AUDIENCES = new Set(['public', 'church', 'internal']);

// ---- 純函式（可測；無 IO）----

/** 既有 audience 分類：missing / public / church / internal / invalid。 */
export function classifyExistingAudience(v) {
  if (v === undefined || v === null || v === '') return 'missing';
  if (VALID_AUDIENCES.has(v)) return v;
  return 'invalid';
}

/** 解析一個 study_content source 對 live published doc 的結果（authorization truth）。
 *  liveDoc==null 代表 source doc 不存在。回 {problem, audience, allowedChurchIds}。 */
export function resolveManagedSource(citedVersion, liveDoc) {
  if (!liveDoc) return { problem: 'BLOCK_SOURCE_NOT_FOUND' };
  if (liveDoc.status !== 'published') return { problem: 'BLOCK_SOURCE_NOT_PUBLISHED' };
  const liveVersion = typeof liveDoc.version === 'number' ? liveDoc.version : null;
  if (citedVersion === null || citedVersion === undefined || liveVersion !== citedVersion) {
    return { problem: 'BLOCK_VERSION_MISMATCH' };
  }
  const aud = liveDoc.audience;
  if (!VALID_AUDIENCES.has(aud)) return { problem: 'BLOCK_UNKNOWN_SOURCE_AUDIENCE' };
  if (aud === 'internal') return { problem: 'BLOCK_INTERNAL_SOURCE' };
  return {
    problem: null,
    audience: aud,
    allowedChurchIds: Array.isArray(liveDoc.allowed_church_ids)
      ? liveDoc.allowed_church_ids.map(String)
      : [],
  };
}

/** 由「已解析的 sources」推導 plan。resolved 每筆：
 *   {kind:'scripture'} 或 {kind:'study_content', problem, audience, allowedChurchIds}。
 *  回 {decision:'auto_public'|'auto_church'|'manual', audience, allowedChurchIds, reasonCodes}。 */
export function derivePlan(resolved) {
  if (resolved.length === 0) {
    return { decision: 'manual', audience: null, allowedChurchIds: [], reasonCodes: ['MANUAL_SOURCELESS'] };
  }
  const managed = resolved.filter((s) => s.kind === 'study_content');
  const blocks = [];
  for (const s of managed) if (s.problem) blocks.push(s.problem);
  if (blocks.length) {
    return { decision: 'manual', audience: null, allowedChurchIds: [], reasonCodes: dedupe(blocks) };
  }
  const church = managed.filter((s) => s.audience === 'church');
  if (church.length === 0) {
    const onlyScripture = managed.length === 0;
    return {
      decision: 'auto_public',
      audience: 'public',
      allowedChurchIds: [],
      reasonCodes: [onlyScripture ? 'AUTO_PUBLIC_SCRIPTURE_ONLY' : 'AUTO_PUBLIC_ALL_SOURCES_PUBLIC'],
    };
  }
  let inter = null;
  for (const s of church) {
    const ids = new Set(s.allowedChurchIds || []);
    inter = inter === null ? ids : new Set([...inter].filter((x) => ids.has(x)));
  }
  const list = [...(inter || new Set())].sort();
  if (list.length === 0) {
    return { decision: 'manual', audience: null, allowedChurchIds: [], reasonCodes: ['BLOCK_EMPTY_CHURCH_INTERSECTION'] };
  }
  return { decision: 'auto_church', audience: 'church', allowedChurchIds: list, reasonCodes: ['AUTO_CHURCH_SOURCE_INTERSECTION'] };
}

/** source snapshot fingerprint（concurrent-change 偵測用；deterministic）。 */
export function sourcesFingerprint(sources) {
  return JSON.stringify(
    (sources || []).map((s) => [s.content_id ?? '', s.version ?? '', s.kind ?? '']),
  );
}

function dedupe(a) { return [...new Set(a)]; }

// ---- IO：解析一筆 question 的 sources（重讀 study_content live doc）----

async function resolveQuestionSources(db, sources, sourceStats) {
  const resolved = [];
  for (const raw of sources || []) {
    const kind = raw && raw.kind;
    if (kind === 'scripture') { resolved.push({ kind: 'scripture' }); continue; }
    if (kind !== 'study_content') {
      // 未知 kind → 當作 malformed（fail-closed）。
      sourceStats.sourceMalformed++;
      resolved.push({ kind: 'study_content', problem: 'BLOCK_SOURCE_NOT_FOUND' });
      continue;
    }
    const contentId = raw.content_id;
    const citedVersion = typeof raw.version === 'number' ? raw.version : null;
    if (!contentId || citedVersion === null) {
      sourceStats.sourceMalformed++;
      resolved.push({ kind: 'study_content', problem: citedVersion === null ? 'BLOCK_VERSION_MISMATCH' : 'BLOCK_SOURCE_NOT_FOUND' });
      continue;
    }
    const snap = await db.collection('study_content').doc(contentId).get(); // read-only
    const live = snap.exists ? snap.data() : null;
    const r = resolveManagedSource(citedVersion, live);
    switch (r.problem) {
      case 'BLOCK_SOURCE_NOT_FOUND': sourceStats.sourceMissing++; break;
      case 'BLOCK_SOURCE_NOT_PUBLISHED': sourceStats.sourceNotPublished++; break;
      case 'BLOCK_VERSION_MISMATCH': sourceStats.sourceVersionMismatch++; break;
      case 'BLOCK_UNKNOWN_SOURCE_AUDIENCE': sourceStats.sourceUnknownAudience++; break;
      case 'BLOCK_INTERNAL_SOURCE': sourceStats.sourceInternal++; break;
      default: break;
    }
    resolved.push({ kind: 'study_content', ...r });
  }
  return resolved;
}

function die(msg) { console.error(`[backfill-qa] FAIL: ${msg}`); process.exit(1); }

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
  console.error(`[backfill-qa] TARGET: ${projectId || '(SDK 推斷)'} — mode=${APPLY ? 'APPLY' : 'DRY-RUN'}`);

  admin.initializeApp(projectId ? { credential, projectId } : { credential });
  const db = admin.firestore();
  if (process.env.FIRESTORE_EMULATOR_HOST) die('emulator 環境變數在初始化後出現，中止。');

  const report = newReport(projectId);
  const sourceStats = report; // 同物件累加 source* 欄位

  const snap = await db.collection('questions').get(); // read-only
  report.questionsTotal = snap.size;

  const plannedWrites = [];
  for (const doc of snap.docs) {
    const q = doc.data();
    const status = q.status || 'pending';
    const published = q.published === true;
    const hasAnswer = !!q.answer;

    if (status === 'pending') report.pendingCount++;
    if (status === 'rejected') report.rejectedCount++;
    if (!published) report.unpublishedCount++;

    if (!published) continue; // 非 published：只納入統計，不 migration
    report.publishedTotal++;
    if (hasAnswer) report.publishedAnswered++; else { report.publishedWithoutAnswer++; }

    const existing = classifyExistingAudience(q.audience);
    if (existing !== 'missing') {
      // 已有 audience：一律 SKIP（不覆蓋）。invalid 需 report anomaly。
      if (existing === 'public') report.existingPublic++;
      else if (existing === 'church') report.existingChurch++;
      else if (existing === 'internal') report.existingInternal++;
      else {
        report.invalidExistingAudience++;
        pushAnomaly(report, doc.id, q, 'skip', ['BLOCK_INVALID_EXISTING_AUDIENCE']);
      }
      report.publishedWithAudience++;
      continue;
    }
    report.publishedMissingAudience++;

    if (!hasAnswer) {
      // published、缺 audience、無 answer → sourceless 之外的異常（無回答不應 published）。
      pushAnomaly(report, doc.id, q, 'manual', ['MANUAL_SOURCELESS']);
      report.sourceLessPublished++;
      continue;
    }

    const sources = (q.answer && Array.isArray(q.answer.sources)) ? q.answer.sources : [];
    if (sources.length === 0) {
      report.sourceLessPublished++;
      pushAnomaly(report, doc.id, q, 'manual', ['MANUAL_SOURCELESS']);
      continue;
    }
    const resolved = await resolveQuestionSources(db, sources, sourceStats);
    const plan = derivePlan(resolved);

    if (plan.decision === 'manual') {
      report.manualReviewRequired++;
      if (plan.reasonCodes.includes('BLOCK_EMPTY_CHURCH_INTERSECTION')) report.emptyChurchIntersection++;
      pushAnomaly(report, doc.id, q, 'manual', plan.reasonCodes, plan, sources.length);
      continue;
    }

    // 可自動 migration。
    if (plan.decision === 'auto_public') { report.eligibleAutoPublic++; report.plannedPublic++; }
    else { report.eligibleAutoChurch++; report.plannedChurch++; }
    plannedWrites.push({ id: doc.id, plan, fingerprint: sourcesFingerprint(sources) });
  }

  report.plannedWrites = plannedWrites.length;

  // ---- APPLY：逐筆 re-read（concurrent-safe），只新增 audience/allowed_church_ids ----
  if (APPLY) {
    for (const w of plannedWrites) {
      const ref = db.collection('questions').doc(w.id);
      const fresh = await ref.get();
      if (!fresh.exists) { report.concurrentChange++; pushAnomaly(report, w.id, {}, 'skip', ['CONCURRENT_CHANGE']); continue; }
      const fq = fresh.data();
      if (classifyExistingAudience(fq.audience) !== 'missing') { report.concurrentChange++; continue; } // 已被寫入 → skip
      const freshSources = (fq.answer && Array.isArray(fq.answer.sources)) ? fq.answer.sources : [];
      if (sourcesFingerprint(freshSources) !== w.fingerprint) { report.concurrentChange++; pushAnomaly(report, w.id, fq, 'skip', ['CONCURRENT_CHANGE']); continue; }
      // additive：只補兩欄，不動其它。
      await ref.set({ audience: w.plan.audience, allowed_church_ids: w.plan.allowedChurchIds }, { merge: true });
      report.appliedWrites++;
    }
  }

  // 不變量：本工具不讀不寫 users/memberships。
  console.log(JSON.stringify(report, null, 2));
  const hasBlocking = report.manualReviewRequired > 0 || report.invalidExistingAudience > 0 || report.concurrentChange > 0;
  process.exit(hasBlocking ? 2 : 0);
}

function newReport(projectId) {
  return {
    targetProject: projectId || '(SDK 推斷)',
    mode: APPLY ? 'apply' : 'dry-run',
    generatedAt: new Date().toISOString(),
    questionsTotal: 0,
    publishedTotal: 0,
    publishedAnswered: 0,
    publishedWithoutAnswer: 0,
    publishedWithAudience: 0,
    publishedMissingAudience: 0,
    eligibleAutoPublic: 0,
    eligibleAutoChurch: 0,
    manualReviewRequired: 0,
    existingPublic: 0,
    existingChurch: 0,
    existingInternal: 0,
    invalidExistingAudience: 0,
    pendingCount: 0,
    rejectedCount: 0,
    unpublishedCount: 0,
    sourceLessPublished: 0,
    sourceMalformed: 0,
    sourceMissing: 0,
    sourceNotPublished: 0,
    sourceVersionMismatch: 0,
    sourceInternal: 0,
    sourceUnknownAudience: 0,
    emptyChurchIntersection: 0,
    concurrentChange: 0,
    plannedWrites: 0,
    plannedPublic: 0,
    plannedChurch: 0,
    appliedWrites: 0,
    usersReadCount: 0, // 硬性 0：本工具不觸碰 users
    usersWriteCount: 0, // 硬性 0
    anomalies: [],
  };
}

/** anomaly 列（**不含 answer body**）。 */
function pushAnomaly(report, id, q, decision, reasonCodes, plan, sourceCount) {
  if (report.anomalies.length >= 500) return; // 上限，避免 log 爆量
  report.anomalies.push({
    questionId: id,
    status: q.status ?? null,
    published: q.published === true,
    hasAnswer: !!q.answer,
    currentAudience: q.audience ?? null,
    sourceCount: sourceCount ?? ((q.answer && Array.isArray(q.answer.sources)) ? q.answer.sources.length : 0),
    derivedAudience: plan ? plan.audience : null,
    allowedChurchIds: plan ? plan.allowedChurchIds : [],
    decision,
    reasonCodes,
  });
}
