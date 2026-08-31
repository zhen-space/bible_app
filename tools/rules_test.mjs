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
  collectionGroup,
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
  await setDoc(doc(db, 'annotations/book_1'), { status: 'published', version: 1, content_type: 'book_guide', content_id: 'book_1' });
  await setDoc(doc(db, 'annotations/book_2_draft'), { status: 'draft', version: 0 });
  await setDoc(doc(db, 'annotations/book_3_review'), { status: 'review', version: 0 });
  await setDoc(doc(db, 'annotations/book_4_rejected'), { status: 'rejected', version: 0 });
  await setDoc(doc(db, 'annotations/book_5_archived'), { status: 'archived', version: 1 });
  await setDoc(doc(db, 'annotations_workspace/book_1'), { status: 'draft' });
  await setDoc(doc(db, 'daily_verses/2026-01-01'), { status: 'published', book_id: 1, chapter: 1, verse: 1 });
  await setDoc(doc(db, 'daily_verses/2026-01-02'), { status: 'draft', book_id: 1, chapter: 1, verse: 2 });
  await setDoc(doc(db, 'daily_verses/2026-01-03'), { status: 'archived', book_id: 1, chapter: 1, verse: 3 });
  await setDoc(doc(db, 'knowledge/data'), { status: 'published', version: 1 });
  // reading_plans：Published v1 mirror + v2 workspace draft（驗證 v1 在 v2 草稿時仍服務）
  await setDoc(doc(db, 'reading_plans/plan1'), { status: 'published', version: 1, content_type: 'reading_plan' });
  await setDoc(doc(db, 'reading_plans/plan2_draft'), { status: 'draft', version: 0 });
  await setDoc(doc(db, 'reading_plans_workspace/plan1'), { status: 'draft', version: 1 });
  await setDoc(doc(db, 'questions/q_pub'), { uid: 'someone', status: 'approved', published: true, answer: { content: 'a' } });
  await setDoc(doc(db, 'questions/q_draft'), { uid: 'someone', status: 'approved', published: false });
});

const guest = env.unauthenticatedContext().firestore();
const student = env.authenticatedContext('student1', { email: 'student@example.com' }).firestore();
const admin = env.authenticatedContext('admin1', { email: ADMIN }).firestore();
// 以 custom claim admin==true 授權（email 非 legacy）——backward-compatible role path。
const claimAdmin = env.authenticatedContext('admin2', { email: 'other@example.com', admin: true }).firestore();

let passed = 0;
async function ok(label, p) {
  await p;
  passed++;
  console.log(`  ✓ ${label}`);
}

console.log('Firestore rules 測試：');

// 公開讀：只有 Published。Draft/Review/Rejected/Archived 全 deny。
await ok('guest 可讀 Published annotation', assertSucceeds(getDoc(doc(guest, 'annotations/book_1'))));
await ok('guest 不可讀 Draft annotation', assertFails(getDoc(doc(guest, 'annotations/book_2_draft'))));
await ok('guest 不可讀 Review annotation', assertFails(getDoc(doc(guest, 'annotations/book_3_review'))));
await ok('guest 不可讀 Rejected annotation', assertFails(getDoc(doc(guest, 'annotations/book_4_rejected'))));
await ok('guest 不可讀 Archived annotation', assertFails(getDoc(doc(guest, 'annotations/book_5_archived'))));
await ok('student 不可讀 Draft annotation', assertFails(getDoc(doc(student, 'annotations/book_2_draft'))));
await ok('student 不可讀 Review annotation', assertFails(getDoc(doc(student, 'annotations/book_3_review'))));
await ok('student 不可讀 Rejected annotation', assertFails(getDoc(doc(student, 'annotations/book_4_rejected'))));
await ok('student 不可讀 Archived annotation', assertFails(getDoc(doc(student, 'annotations/book_5_archived'))));

// workspace：學生端完全讀不到；admin（含 custom-claim admin）可讀。
await ok('guest 不可讀 annotations_workspace', assertFails(getDoc(doc(guest, 'annotations_workspace/book_1'))));
await ok('student 不可讀 annotations_workspace', assertFails(getDoc(doc(student, 'annotations_workspace/book_1'))));
await ok('admin(email) 可讀 annotations_workspace', assertSucceeds(getDoc(doc(admin, 'annotations_workspace/book_1'))));
await ok('admin(claim) 可讀 annotations_workspace', assertSucceeds(getDoc(doc(claimAdmin, 'annotations_workspace/book_1'))));
// collection-group 不能繞過（學生端對 workspace 的 group query 被拒）。
await ok('student collectionGroup(annotations_workspace) 被拒',
  assertFails(getDocs(collectionGroup(student, 'annotations_workspace'))));

// 寫入：只有 admin（email 或 custom claim）。
await ok('student 不可寫 annotations', assertFails(setDoc(doc(student, 'annotations/book_1'), { status: 'published' })));
await ok('admin(email) 可寫 annotations', assertSucceeds(setDoc(doc(admin, 'annotations/book_9'), { status: 'published', version: 1 })));
await ok('admin(claim) 可寫 annotations', assertSucceeds(setDoc(doc(claimAdmin, 'annotations/book_10'), { status: 'published', version: 1 })));
await ok('admin(claim) 可寫 workspace（review transition）',
  assertSucceeds(setDoc(doc(claimAdmin, 'annotations_workspace/book_10'), { status: 'review' })));

// daily_verses：Published 可讀、Draft/Archived 不可讀。
await ok('guest 可讀 Published daily verse', assertSucceeds(getDoc(doc(guest, 'daily_verses/2026-01-01'))));
await ok('guest 不可讀 Draft daily verse', assertFails(getDoc(doc(guest, 'daily_verses/2026-01-02'))));
await ok('guest 不可讀 Archived daily verse', assertFails(getDoc(doc(guest, 'daily_verses/2026-01-03'))));

// knowledge：Published 可讀。
await ok('guest 可讀 Published knowledge', assertSucceeds(getDoc(doc(guest, 'knowledge/data'))));

// reading_plans：Published 可讀、Draft 不可讀、workspace admin-only；
// **v1 在 v2 workspace draft 存在時仍服務**（student 讀得到 published mirror v1）。
await ok('guest 可讀 Published reading_plan v1', assertSucceeds(getDoc(doc(guest, 'reading_plans/plan1'))));
await ok('student 可讀 Published reading_plan v1（v2 草稿存在時仍服務）',
  assertSucceeds(getDoc(doc(student, 'reading_plans/plan1'))));
await ok('guest 不可讀 Draft reading_plan', assertFails(getDoc(doc(guest, 'reading_plans/plan2_draft'))));
await ok('student 不可讀 reading_plans_workspace（v2 草稿）',
  assertFails(getDoc(doc(student, 'reading_plans_workspace/plan1'))));
await ok('admin(claim) 可讀/寫 reading_plans_workspace（workflow）',
  assertSucceeds(setDoc(doc(claimAdmin, 'reading_plans_workspace/plan1'), { status: 'review' }, { merge: true })));

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
// student 不能 update 既有問題把它發佈/塞 answer（只有 admin 可 update）。
await ok('student 不可 update 既有問題（自我發佈）',
  assertFails(setDoc(doc(student, 'questions/q_draft'),
    { published: true }, { merge: true })));
await ok('admin 可發佈問題', assertSucceeds(setDoc(doc(admin, 'questions/q_draft'),
    { published: true }, { merge: true })));

// 私有資料：本人可讀寫、他人不可。
await ok('student 可寫自己的 users/{uid}',
  assertSucceeds(setDoc(doc(student, 'users/student1/bookmarks/b1'), { x: 1 })));
await ok('student 不可讀他人 users/{uid}',
  assertFails(getDoc(doc(student, 'users/other/bookmarks/b1'))));

await env.cleanup();
console.log(`\n全部 ${passed} 項 rules 測試通過。`);
