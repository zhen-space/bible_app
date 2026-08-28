#!/usr/bin/env node
// Firestore security rules 測試（#8/#9）——證明「只有 Published 可外流」是**規則層**
// 真正阻擋，不是 UI 隱藏。用 @firebase/rules-unit-testing 對 emulator 執行。
//
// 執行方式（需要 Firebase emulator；無網路/emulator 環境無法跑）：
//   cd tools && npm install
//   firebase emulators:exec --only firestore "node rules_test.mjs"
// 或先手動起 emulator，設 FIRESTORE_EMULATOR_HOST=localhost:8080 再 `node rules_test.mjs`。

import assert from 'node:assert';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  collection,
  query,
  where,
  getDocs,
} from 'firebase/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(join(__dirname, '..', 'firestore.rules'), 'utf8');
const ADMIN = 'zhen20091212@gmail.com';

const env = await initializeTestEnvironment({
  projectId: 'bible-app-rules-test',
  firestore: { rules, host: '127.0.0.1', port: 8080 },
});

// 以繞過規則的方式植入種子資料。
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'annotations/book_1'), { status: 'published', version: 1, payload: 'x' });
  await setDoc(doc(db, 'annotations/book_2_draft'), { status: 'draft', version: 0 });
  await setDoc(doc(db, 'annotations_workspace/book_1'), { status: 'draft' });
  await setDoc(doc(db, 'daily_verses/2026-01-01'), { status: 'published', book_id: 1, chapter: 1, verse: 1 });
  await setDoc(doc(db, 'daily_verses/2026-01-02'), { status: 'draft', book_id: 1, chapter: 1, verse: 2 });
  await setDoc(doc(db, 'knowledge/data'), { status: 'published', version: 1 });
  await setDoc(doc(db, 'questions/q_pub'), { uid: 'someone', status: 'approved', published: true, answer: { content: 'a' } });
  await setDoc(doc(db, 'questions/q_draft'), { uid: 'someone', status: 'approved', published: false });
});

const guest = env.unauthenticatedContext().firestore();
const student = env.authenticatedContext('student1', { email: 'student@example.com' }).firestore();
const admin = env.authenticatedContext('admin1', { email: ADMIN }).firestore();

let passed = 0;
async function ok(label, p) {
  await p;
  passed++;
  console.log(`  ✓ ${label}`);
}

console.log('Firestore rules 測試：');

// 公開讀：只有 Published。
await ok('guest 可讀 Published annotation', assertSucceeds(getDoc(doc(guest, 'annotations/book_1'))));
await ok('guest 不可讀 Draft annotation', assertFails(getDoc(doc(guest, 'annotations/book_2_draft'))));
await ok('student 不可讀 Draft annotation', assertFails(getDoc(doc(student, 'annotations/book_2_draft'))));

// workspace：學生端完全讀不到；admin 可讀。
await ok('guest 不可讀 annotations_workspace', assertFails(getDoc(doc(guest, 'annotations_workspace/book_1'))));
await ok('student 不可讀 annotations_workspace', assertFails(getDoc(doc(student, 'annotations_workspace/book_1'))));
await ok('admin 可讀 annotations_workspace', assertSucceeds(getDoc(doc(admin, 'annotations_workspace/book_1'))));

// 寫入：只有 admin。
await ok('student 不可寫 annotations', assertFails(setDoc(doc(student, 'annotations/book_1'), { status: 'published' })));
await ok('admin 可寫 annotations', assertSucceeds(setDoc(doc(admin, 'annotations/book_9'), { status: 'published', version: 1 })));

// daily_verses：Published 可讀、Draft 不可讀。
await ok('guest 可讀 Published daily verse', assertSucceeds(getDoc(doc(guest, 'daily_verses/2026-01-01'))));
await ok('guest 不可讀 Draft daily verse', assertFails(getDoc(doc(guest, 'daily_verses/2026-01-02'))));

// knowledge：Published 可讀。
await ok('guest 可讀 Published knowledge', assertSucceeds(getDoc(doc(guest, 'knowledge/data'))));

// questions：Published 可讀、未發布不可讀（非本人）。
await ok('guest 可讀 published question', assertSucceeds(getDoc(doc(guest, 'questions/q_pub'))));
await ok('student 不可讀 未發布 question（非本人）', assertFails(getDoc(doc(student, 'questions/q_draft'))));

// 提問者不可自我發佈：create 必須 pending + published:false。
await ok('student 建立問題必須 pending+published:false',
  assertSucceeds(setDoc(doc(student, 'questions/q_new'),
    { uid: 'student1', status: 'pending', published: false })));
await ok('student 不可建立 published==true 的問題',
  assertFails(setDoc(doc(student, 'questions/q_bad'),
    { uid: 'student1', status: 'pending', published: true })));
await ok('student 不可自設 status=approved',
  assertFails(setDoc(doc(student, 'questions/q_bad2'),
    { uid: 'student1', status: 'approved', published: false })));

// 私有資料：本人可讀寫、他人不可。
await ok('student 可寫自己的 users/{uid}',
  assertSucceeds(setDoc(doc(student, 'users/student1/bookmarks/b1'), { x: 1 })));
await ok('student 不可讀他人 users/{uid}',
  assertFails(getDoc(doc(student, 'users/other/bookmarks/b1'))));

await env.cleanup();
console.log(`\n全部 ${passed} 項 rules 測試通過。`);
