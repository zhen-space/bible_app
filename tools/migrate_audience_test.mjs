#!/usr/bin/env node
// migrate_audience 純函式測試（無網路、無 emulator）：mapping / idempotency / 不自動產生
// church / annotation verse_key 解耦 / collision-safe determinism。
// 用法：node tools/migrate_audience_test.mjs

import assert from 'node:assert';
import { audienceFor, verseKeyForAnnotationDoc } from './migrate_audience.mjs';

let n = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); n++; };
const eq = (a, b, msg) => { assert.strictEqual(a, b, msg); n++; };

// ---- audienceFor：study_content/topics（visibility→audience）----
eq(audienceFor({ visibility: 'student' }), 'public', 'student→public');
eq(audienceFor({ visibility: 'internal' }), 'internal', 'internal→internal');
eq(audienceFor({}), 'internal', 'missing→internal (fail-closed)');
eq(audienceFor({ visibility: 'weird' }), 'internal', 'unknown→internal (fail-closed)');

// ---- audienceFor：annotations（published→public，其餘→internal）----
eq(audienceFor({ status: 'published' }, { isAnnotation: true }), 'public', 'annotation published→public');
eq(audienceFor({ status: 'draft' }, { isAnnotation: true }), 'internal', 'annotation draft→internal');
eq(audienceFor({}, { isAnnotation: true }), 'internal', 'annotation missing status→internal');

// ---- idempotency：已有 audience → null（skip）----
eq(audienceFor({ audience: 'public', visibility: 'student' }), null, 'idempotent skip (has audience)');
eq(audienceFor({ audience: 'church' }, { isAnnotation: true }), null, 'idempotent skip annotation');

// ---- 絕不自動產生 church：任何輸入都不會回 'church' ----
for (const doc of [{}, { visibility: 'student' }, { visibility: 'internal' }, { status: 'published' }, { allowed_church_ids: ['A'] }]) {
  ok(audienceFor(doc) !== 'church' && audienceFor(doc, { isAnnotation: true }) !== 'church', 'never church');
}

// ---- verse_key 解耦：legacy verse doc id → "b_c_v"；非節註解 → null ----
eq(verseKeyForAnnotationDoc('verse_1_1_1'), '1_1_1', 'verse id → key');
eq(verseKeyForAnnotationDoc('verse_43_3_16'), '43_3_16', 'verse id → key (約3:16)');
eq(verseKeyForAnnotationDoc('book_1'), null, 'book guide → no key');
eq(verseKeyForAnnotationDoc('chapter_1_1'), null, 'chapter guide → no key');
eq(verseKeyForAnnotationDoc('ann_1_1_1_public_abc'), null, '新 identity doc → 由 doc 內 verse_key 欄提供，不解析 id');

// ---- deterministic / collision-safe：同 id 重複解析結果一致 ----
eq(verseKeyForAnnotationDoc('verse_1_1_1'), verseKeyForAnnotationDoc('verse_1_1_1'), 'deterministic');

console.log(`migrate_audience 純函式測試通過（${n} 項）。`);
