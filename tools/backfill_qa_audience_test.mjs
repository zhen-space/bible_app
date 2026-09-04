#!/usr/bin/env node
// backfill_qa_audience 純函式測試（無網路、無 emulator、無 credential）。
// 用法：node tools/backfill_qa_audience_test.mjs

import assert from 'node:assert';
import { readFileSync } from 'node:fs';
import {
  classifyExistingAudience,
  resolveManagedSource,
  derivePlan,
  sourcesFingerprint,
} from './backfill_qa_audience.mjs';

let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };
const eq = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++; };

const scripture = () => ({ kind: 'scripture' });
const pub = () => ({ kind: 'study_content', problem: null, audience: 'public', allowedChurchIds: [] });
const church = (ids) => ({ kind: 'study_content', problem: null, audience: 'church', allowedChurchIds: ids });
const blocked = (code) => ({ kind: 'study_content', problem: code });

// ---- classifyExistingAudience ----
eq(classifyExistingAudience(undefined), 'missing', 'undefined→missing');
eq(classifyExistingAudience(null), 'missing', 'null→missing');
eq(classifyExistingAudience(''), 'missing', 'empty→missing');
eq(classifyExistingAudience('public'), 'public', 'public');
eq(classifyExistingAudience('church'), 'church', 'church');
eq(classifyExistingAudience('internal'), 'internal', 'internal');
eq(classifyExistingAudience('weird'), 'invalid', 'unknown→invalid（不 silent overwrite）');

// ---- resolveManagedSource（重讀 live source doc）----
eq(resolveManagedSource(1, null).problem, 'BLOCK_SOURCE_NOT_FOUND', 'missing doc');
eq(resolveManagedSource(1, { status: 'draft', version: 1 }).problem, 'BLOCK_SOURCE_NOT_PUBLISHED', 'not published');
eq(resolveManagedSource(3, { status: 'published', version: 4, audience: 'public' }).problem, 'BLOCK_VERSION_MISMATCH', 'version drift');
eq(resolveManagedSource(1, { status: 'published', version: 1, audience: 'weird' }).problem, 'BLOCK_UNKNOWN_SOURCE_AUDIENCE', 'unknown source audience');
eq(resolveManagedSource(1, { status: 'published', version: 1, audience: 'internal' }).problem, 'BLOCK_INTERNAL_SOURCE', 'internal source');
const okPub = resolveManagedSource(2, { status: 'published', version: 2, audience: 'public' });
eq(okPub.problem, null, 'ok public'); eq(okPub.audience, 'public', 'ok public aud');
const okCh = resolveManagedSource(2, { status: 'published', version: 2, audience: 'church', allowed_church_ids: ['A', 'B'] });
eq(okCh.problem, null, 'ok church'); eq(okCh.allowedChurchIds, ['A', 'B'], 'church ids');

// ---- derivePlan ----
eq(derivePlan([pub(), pub()]).reasonCodes, ['AUTO_PUBLIC_ALL_SOURCES_PUBLIC'], 'all public→public');
eq(derivePlan([pub(), pub()]).audience, 'public', 'all public audience');
eq(derivePlan([scripture()]).reasonCodes, ['AUTO_PUBLIC_SCRIPTURE_ONLY'], 'scripture only→public');
{
  const p = derivePlan([pub(), church(['A'])]);
  eq(p.audience, 'church', 'public+church→church'); eq(p.allowedChurchIds, ['A'], 'church A');
  eq(p.reasonCodes, ['AUTO_CHURCH_SOURCE_INTERSECTION'], 'church reason');
}
{
  const p = derivePlan([church(['A', 'B']), church(['B', 'C']), pub()]);
  eq(p.allowedChurchIds, ['B'], 'intersection A,B ∩ B,C = B（public 不縮小）');
}
{
  const p = derivePlan([church(['A']), church(['B'])]);
  eq(p.decision, 'manual', 'empty intersection → manual');
  eq(p.reasonCodes, ['BLOCK_EMPTY_CHURCH_INTERSECTION'], 'empty intersection reason');
}
eq(derivePlan([blocked('BLOCK_INTERNAL_SOURCE')]).decision, 'manual', 'internal → manual');
eq(derivePlan([blocked('BLOCK_SOURCE_NOT_FOUND')]).reasonCodes, ['BLOCK_SOURCE_NOT_FOUND'], 'missing source → manual');
eq(derivePlan([blocked('BLOCK_VERSION_MISMATCH')]).reasonCodes, ['BLOCK_VERSION_MISMATCH'], 'version mismatch → manual');
eq(derivePlan([blocked('BLOCK_UNKNOWN_SOURCE_AUDIENCE')]).reasonCodes, ['BLOCK_UNKNOWN_SOURCE_AUDIENCE'], 'unknown audience → manual');
eq(derivePlan([]).reasonCodes, ['MANUAL_SOURCELESS'], 'source-less → manual');

// ---- allowed_church_ids deterministic order ----
eq(derivePlan([church(['C', 'A', 'B'])]).allowedChurchIds, ['A', 'B', 'C'], 'church ids sorted deterministic');

// ---- idempotent second pass：同輸入同輸出 ----
eq(JSON.stringify(derivePlan([church(['A', 'B']), church(['B', 'C'])])),
   JSON.stringify(derivePlan([church(['A', 'B']), church(['B', 'C'])])), 'derivePlan deterministic');

// ---- concurrent change fingerprint ----
const fpA = sourcesFingerprint([{ content_id: 'x', version: 1, kind: 'study_content' }]);
const fpB = sourcesFingerprint([{ content_id: 'x', version: 2, kind: 'study_content' }]);
ok(fpA !== fpB, 'version 變更 → fingerprint 不同（concurrent-change 可偵測）');
eq(sourcesFingerprint([{ content_id: 'x', version: 1, kind: 'study_content' }]), fpA, 'fingerprint deterministic');

// ---- 靜態安全：source 不得出現 users/memberships path、不得有 LLM/Web ----
const src = readFileSync(new URL('./backfill_qa_audience.mjs', import.meta.url), 'utf8');
ok(!/collection\(['"]users['"]\)/.test(src), '不得存取 users collection');
ok(!/collection\(['"]memberships['"]\)/.test(src), '不得存取 memberships collection');
ok(!/(openai|anthropic|fetch\(|https?:\/\/|WebSearch|langchain)/i.test(src), '不得有 LLM/Web code path');
ok(/collection\(['"]questions['"]\)/.test(src), 'TARGET＝questions（硬寫死）');
ok(/collection\(['"]study_content['"]\)/.test(src), 'source authority＝study_content');

console.log(`backfill_qa_audience 純函式測試通過（${n} 項）。`);
