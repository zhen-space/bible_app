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
  await setDoc(doc(db, 'annotations/book_1'), { status: 'published', audience: 'public', version: 1, content_type: 'book_guide', content_id: 'book_1' });
  await setDoc(doc(db, 'annotations/ann_chA'), { status: 'published', audience: 'church', allowed_church_ids: ['A'], version: 1 });
  await setDoc(doc(db, 'annotations/ann_noaud'), { status: 'published', version: 1 }); // 缺 audience → fail-closed
  // 同一節（verse_key 1_1_1）public + church A + church B 三筆共存（multi-doc identity）。
  await setDoc(doc(db, 'annotations/ann_v111_pub'), { status: 'published', audience: 'public', verse_key: '1_1_1', version: 1 });
  await setDoc(doc(db, 'annotations/ann_v111_chA'), { status: 'published', audience: 'church', allowed_church_ids: ['A'], verse_key: '1_1_1', version: 1 });
  await setDoc(doc(db, 'annotations/ann_v111_chB'), { status: 'published', audience: 'church', allowed_church_ids: ['B'], verse_key: '1_1_1', version: 1 });
  await setDoc(doc(db, 'annotations/ann_v111_chEmpty'), { status: 'published', audience: 'church', allowed_church_ids: [], verse_key: '1_1_1', version: 1 });
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
  await setDoc(doc(db, 'questions/q_pub'), { uid: 'someone', status: 'approved', published: true, audience: 'public', allowed_church_ids: [], answer: { content: 'a' } });
  await setDoc(doc(db, 'questions/q_draft'), { uid: 'someone', status: 'approved', published: false });
  // Q&A audience gate（B19）：church-sourced answer confidentiality。
  await setDoc(doc(db, 'questions/q_chA'), { uid: 'someone', status: 'approved', published: true, audience: 'church', allowed_church_ids: ['A'], answer: { content: 'a' } });
  await setDoc(doc(db, 'questions/q_noaud'), { uid: 'someone', status: 'approved', published: true, answer: { content: 'a' } }); // 缺 audience → fail-closed
  // Teacher Area capability gate（§B7）：required_capabilities 含 teacher_area。
  await setDoc(doc(db, 'questions/q_ta_A'), { uid: 'someone', status: 'approved', published: true, audience: 'church', allowed_church_ids: ['A'], required_capabilities: ['teacher_area'], answer: { content: 'a' } });
  await setDoc(doc(db, 'questions/q_ta_B'), { uid: 'someone', status: 'approved', published: true, audience: 'church', allowed_church_ids: ['B'], required_capabilities: ['teacher_area'], answer: { content: 'a' } });
  await setDoc(doc(db, 'questions/q_mine_unpub'), { uid: 'sNone', status: 'pending', published: false });
  // Study Content：學生可讀 ⇔ published && visibility==student（兩者缺一不可、fail-closed）。
  // Church/Teacher R1：audience 授權（study_content / study_topics / teacher / church / membership）。
  await setDoc(doc(db, 'churches/A'), { name: 'A教會', active: true });
  await setDoc(doc(db, 'churches/B'), { name: 'B教會', active: true });
  await setDoc(doc(db, 'churches/C'), { name: 'C教會', active: true });
  await setDoc(doc(db, 'churches/X'), { name: 'X停用', active: false });
  await setDoc(doc(db, 'churches/A/private/capabilities'), { teacher_area: true });
  await setDoc(doc(db, 'churches/B/private/capabilities'), { teacher_area: false });
  await setDoc(doc(db, 'churches/C/private/capabilities'), { future_capability: true });
  await setDoc(doc(db, 'churches/X/private/capabilities'), { teacher_area: true });
  await setDoc(doc(db, 'memberships/sA'), { uid: 'sA', church_id: 'A', status: 'active' });
  await setDoc(doc(db, 'memberships/sB'), { uid: 'sB', church_id: 'B', status: 'active' });
  await setDoc(doc(db, 'memberships/sC'), { uid: 'sC', church_id: 'C', status: 'active' });
  await setDoc(doc(db, 'memberships/sX'), { uid: 'sX', church_id: 'X', status: 'active' });
  await setDoc(doc(db, 'memberships/sP'), { uid: 'sP', church_id: 'A', status: 'pending' });
  await setDoc(doc(db, 'memberships/sR'), { uid: 'sR', church_id: 'A', status: 'revoked' });
  await setDoc(doc(db, 'memberships/sG'), { uid: 'sG', church_id: 'A', status: 'pending' });
  await setDoc(doc(db, 'memberships/sRej'), { uid: 'sRej', church_id: 'A', status: 'rejected' });
  await setDoc(doc(db, 'study_content/sc_pub'), { status: 'published', audience: 'public', content_type: 'parallel', version: 1 });
  await setDoc(doc(db, 'study_content/sc_draft_pub'), { status: 'draft', audience: 'public', version: 0 });
  await setDoc(doc(db, 'study_content/sc_internal'), { status: 'published', audience: 'internal', version: 1 });
  await setDoc(doc(db, 'study_content/sc_chA'), { status: 'published', audience: 'church', allowed_church_ids: ['A'], version: 1 });
  await setDoc(doc(db, 'study_content/sc_chA_empty'), { status: 'published', audience: 'church', allowed_church_ids: [], version: 1 });
  await setDoc(doc(db, 'study_content/sc_missing_aud'), { status: 'published', version: 1 }); // 缺 audience
  await setDoc(doc(db, 'study_content/sc_missing_status'), { audience: 'public', version: 1 }); // 缺 status
  await setDoc(doc(db, 'study_content/sc_pub/versions/1'), { status: 'published', audience: 'public', snapshot_at: 1 });
  await setDoc(doc(db, 'study_content_workspace/sc_ws'), { status: 'draft', audience: 'internal' });
  await setDoc(doc(db, 'study_topics/tp_pub'), { status: 'published', audience: 'public' });
  await setDoc(doc(db, 'study_topics/tp_chA'), { status: 'published', audience: 'church', allowed_church_ids: ['A'] });
  await setDoc(doc(db, 'study_topics/tp_draft'), { status: 'draft', audience: 'public' });
  await setDoc(doc(db, 'teacher_books/tb_chA'), { status: 'published', audience: 'church', allowed_church_ids: ['A'], title: '書' });
  await setDoc(doc(db, 'teacher_books/tb_chA/chapters/tc_chA'), { status: 'published', audience: 'church', allowed_church_ids: ['A'], book_id: 'tb_chA' });
});

const guest = env.unauthenticatedContext().firestore();
const student = env.authenticatedContext('student1', { email: 'student@example.com' }).firestore();
const admin = env.authenticatedContext('admin1', { email: ADMIN }).firestore();
// 以 custom claim admin==true 授權（email 非 legacy）——backward-compatible role path。
const claimAdmin = env.authenticatedContext('admin2', { email: 'other@example.com', admin: true }).firestore();
// Church/Teacher R1：不同 membership 狀態的學生（uid 對應 memberships/{uid} 種子）。
const sNone = env.authenticatedContext('sNone', { email: 'n@e.com' }).firestore();
const sA = env.authenticatedContext('sA', { email: 'a@e.com' }).firestore();
const sB = env.authenticatedContext('sB', { email: 'b@e.com' }).firestore();
const sC = env.authenticatedContext('sC', { email: 'c@e.com' }).firestore();
const sX = env.authenticatedContext('sX', { email: 'x@e.com' }).firestore();
const sP = env.authenticatedContext('sP', { email: 'p@e.com' }).firestore();
const sR = env.authenticatedContext('sR', { email: 'r@e.com' }).firestore();

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
await ok('guest 可讀 published public question', assertSucceeds(getDoc(doc(guest, 'questions/q_pub'))));
await ok('student 不可讀 未發布 question（非本人）', assertFails(getDoc(doc(student, 'questions/q_draft'))));
// Q&A audience gate（B19/B20）
await ok('Q&A church A → active A 可讀', assertSucceeds(getDoc(doc(sA, 'questions/q_chA'))));
await ok('Q&A church A → active B 不可讀', assertFails(getDoc(doc(sB, 'questions/q_chA'))));
await ok('Q&A church A → no membership 不可讀', assertFails(getDoc(doc(sNone, 'questions/q_chA'))));
await ok('Q&A church A → guest 不可讀', assertFails(getDoc(doc(guest, 'questions/q_chA'))));
await ok('Q&A published 缺 audience → 非本人 fail-closed', assertFails(getDoc(doc(sA, 'questions/q_noaud'))));
await ok('Q&A published 缺 audience → guest fail-closed', assertFails(getDoc(doc(guest, 'questions/q_noaud'))));
await ok('Q&A 本人可讀自己未發布問題', assertSucceeds(getDoc(doc(sNone, 'questions/q_mine_unpub'))));
await ok('Q&A admin 可讀缺 audience question', assertSucceeds(getDoc(doc(admin, 'questions/q_noaud'))));
// Teacher Area capability gate（§B7）
await ok('Q&A teacher_area church A → active A + capability 可讀', assertSucceeds(getDoc(doc(sA, 'questions/q_ta_A'))));
await ok('Q&A teacher_area church B → active B 但無 capability → 不可讀', assertFails(getDoc(doc(sB, 'questions/q_ta_B'))));
await ok('Q&A teacher_area church A → active B 不可讀（audience 先擋）', assertFails(getDoc(doc(sB, 'questions/q_ta_A'))));
await ok('Q&A teacher_area church A → no membership 不可讀', assertFails(getDoc(doc(sNone, 'questions/q_ta_A'))));

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

// ---- Church/Teacher R1：audience 授權（study_content）----
// Public：published+public 任何人可讀；draft/internal deny。
await ok('1 published public → student allow', assertSucceeds(getDoc(doc(sNone, 'study_content/sc_pub'))));
await ok('  published public → guest allow', assertSucceeds(getDoc(doc(guest, 'study_content/sc_pub'))));
await ok('2 draft public → deny', assertFails(getDoc(doc(sNone, 'study_content/sc_draft_pub'))));
await ok('3 published internal → deny', assertFails(getDoc(doc(sA, 'study_content/sc_internal'))));
// Church A：active A allow；no/pending/rejected/revoked/active-B deny。
await ok('4 church A + active A → allow', assertSucceeds(getDoc(doc(sA, 'study_content/sc_chA'))));
await ok('5 church A + no membership → deny', assertFails(getDoc(doc(sNone, 'study_content/sc_chA'))));
await ok('6 church A + pending A → deny', assertFails(getDoc(doc(sP, 'study_content/sc_chA'))));
await ok('8 church A + revoked A → deny', assertFails(getDoc(doc(sR, 'study_content/sc_chA'))));
await ok('9 church A + active B → deny', assertFails(getDoc(doc(sB, 'study_content/sc_chA'))));
await ok('10 church + empty allowedChurchIds → deny', assertFails(getDoc(doc(sA, 'study_content/sc_chA_empty'))));
await ok('11 missing audience → deny', assertFails(getDoc(doc(sA, 'study_content/sc_missing_aud'))));
await ok('   missing status → deny', assertFails(getDoc(doc(sA, 'study_content/sc_missing_status'))));
await ok('12 by-id cannot bypass (B cannot get chA)', assertFails(getDoc(doc(sB, 'study_content/sc_chA'))));
// admin bypass。
await ok('admin 可讀 internal', assertSucceeds(getDoc(doc(admin, 'study_content/sc_internal'))));
await ok('admin(claim) 可讀 church', assertSucceeds(getDoc(doc(claimAdmin, 'study_content/sc_chA'))));
// workspace / versions：學生 deny、admin allow。
await ok('student 不可讀 study_content_workspace', assertFails(getDoc(doc(sA, 'study_content_workspace/sc_ws'))));
await ok('admin 可讀 study_content_workspace', assertSucceeds(getDoc(doc(admin, 'study_content_workspace/sc_ws'))));
await ok('student 不可讀 versions 子集合', assertFails(getDoc(doc(sA, 'study_content/sc_pub/versions/1'))));
await ok('admin 可讀 versions 子集合', assertSucceeds(getDoc(doc(admin, 'study_content/sc_pub/versions/1'))));
await ok('student 不可寫 study_content', assertFails(setDoc(doc(sA, 'study_content/sc_hack'), { status: 'published', audience: 'public' })));
await ok('admin 可寫 study_content', assertSucceeds(setDoc(doc(admin, 'study_content/sc_admin'), { status: 'published', audience: 'internal', version: 1 })));

// ---- Study Topic（Option A）----
await ok('15 topic church A + active A → allow', assertSucceeds(getDoc(doc(sA, 'study_topics/tp_chA'))));
await ok('16 topic church A + active B → deny', assertFails(getDoc(doc(sB, 'study_topics/tp_chA'))));
await ok('   topic public → allow', assertSucceeds(getDoc(doc(sNone, 'study_topics/tp_pub'))));
await ok('   topic draft → deny', assertFails(getDoc(doc(sNone, 'study_topics/tp_draft'))));
await ok('   student 不可讀 study_topics_workspace', assertFails(getDoc(doc(sA, 'study_topics_workspace/tp_ws'))));

// ---- Teacher hierarchy（17：no metadata leak）----
await ok('17 teacher book church A + active B → deny', assertFails(getDoc(doc(sB, 'teacher_books/tb_chA'))));
await ok('   teacher book church A + active A → allow', assertSucceeds(getDoc(doc(sA, 'teacher_books/tb_chA'))));
await ok('   teacher chapter church A + active B → deny', assertFails(getDoc(doc(sB, 'teacher_books/tb_chA/chapters/tc_chA'))));
await ok('   teacher chapter church A + active A → allow', assertSucceeds(getDoc(doc(sA, 'teacher_books/tb_chA/chapters/tc_chA'))));

// ---- Churches（public/private split）----
await ok('active church 可讀', assertSucceeds(getDoc(doc(sNone, 'churches/A'))));
await ok('21 inactive church 非 admin 不可讀', assertFails(getDoc(doc(sNone, 'churches/X'))));
await ok('admin 可讀 inactive church', assertSucceeds(getDoc(doc(admin, 'churches/X'))));
await ok('student 不可讀 church private', assertFails(getDoc(doc(sA, 'churches/A/private/admin'))));
await ok('student 不可寫 church', assertFails(setDoc(doc(sA, 'churches/A'), { active: true })));

// ---- Teacher Area capability（private、只限自己的 Active Church）----
await ok('active Church A 可讀 A capability',
  assertSucceeds(getDoc(doc(sA, 'churches/A/private/capabilities'))));
await ok('active Church A 不可讀 B capability',
  assertFails(getDoc(doc(sA, 'churches/B/private/capabilities'))));
await ok('pending 不可讀 capability',
  assertFails(getDoc(doc(sP, 'churches/A/private/capabilities'))));
const sRejCapability = env.authenticatedContext('sRej', { email: 'j@e.com' }).firestore();
await ok('rejected 不可讀 capability',
  assertFails(getDoc(doc(sRejCapability, 'churches/A/private/capabilities'))));
await ok('revoked 不可讀 capability',
  assertFails(getDoc(doc(sR, 'churches/A/private/capabilities'))));
await ok('no membership 不可讀 capability',
  assertFails(getDoc(doc(sNone, 'churches/A/private/capabilities'))));
await ok('自己的 capability 缺 teacher_area 仍可讀（client fail-closed 為 false）',
  assertSucceeds(getDoc(doc(sC, 'churches/C/private/capabilities'))));
await ok('inactive Church 即使 membership active 仍不可讀 capability',
  assertFails(getDoc(doc(sX, 'churches/X/private/capabilities'))));
await ok('student 不可寫 capability',
  assertFails(setDoc(doc(sA, 'churches/A/private/capabilities'), { teacher_area: false })));
await ok('admin 可讀 capability',
  assertSucceeds(getDoc(doc(admin, 'churches/A/private/capabilities'))));
await ok('admin 可寫 capability',
  assertSucceeds(setDoc(doc(admin, 'churches/B/private/capabilities'), { teacher_area: true })));

// ---- Membership（self-read / legal pending / no self-approve）----
await ok('student 可讀自己的 membership', assertSucceeds(getDoc(doc(sA, 'memberships/sA'))));
await ok('student 不可讀他人 membership', assertFails(getDoc(doc(sA, 'memberships/sB'))));
await ok('19 student 可建立自己的 pending（active church）', assertSucceeds(setDoc(doc(sNone, 'memberships/sNone'), { uid: 'sNone', church_id: 'A', status: 'pending', reviewed_by: '' })));
await ok('19b student 不可建立 active（self-approve）', assertFails(setDoc(doc(guest, 'memberships/guestx'), { uid: 'guestx', church_id: 'A', status: 'active', reviewed_by: '' })));
const sInact = env.authenticatedContext('sInact', { email: 'i@e.com' }).firestore();
await ok('21b student 不可用 inactive church 申請', assertFails(setDoc(doc(sInact, 'memberships/sInact'), { uid: 'sInact', church_id: 'X', status: 'pending', reviewed_by: '' })));
await ok('20 student(pending) 不可自己改 active', assertFails(setDoc(doc(sP, 'memberships/sP'), { status: 'active' }, { merge: true })));
await ok('admin 可 approve membership', assertSucceeds(setDoc(doc(admin, 'memberships/sP'), { status: 'active', reviewed_by: ADMIN }, { merge: true })));
await ok('student 不可寫 membership history', assertFails(setDoc(doc(sA, 'memberships/sA/history/h1'), { x: 1 })));

// ---- Annotation audience 授權 ----
await ok('annotation public → guest allow', assertSucceeds(getDoc(doc(guest, 'annotations/book_1'))));
await ok('annotation church A + active A → allow', assertSucceeds(getDoc(doc(sA, 'annotations/ann_chA'))));
await ok('7 annotation church A + active B → deny', assertFails(getDoc(doc(sB, 'annotations/ann_chA'))));
await ok('annotation church A + no membership → deny', assertFails(getDoc(doc(sNone, 'annotations/ann_chA'))));
await ok('annotation 缺 audience → deny（fail-closed）', assertFails(getDoc(doc(sA, 'annotations/ann_noaud'))));
// ---- 同節 public + church 共存（multi-doc）：逐 doc 授權，rules 才是邊界 ----
await ok('coexist: 同節 public → active A allow', assertSucceeds(getDoc(doc(sA, 'annotations/ann_v111_pub'))));
await ok('coexist: 同節 church A → active A allow', assertSucceeds(getDoc(doc(sA, 'annotations/ann_v111_chA'))));
await ok('coexist: 同節 public → active B allow', assertSucceeds(getDoc(doc(sB, 'annotations/ann_v111_pub'))));
await ok('coexist: 同節 church B → active B allow', assertSucceeds(getDoc(doc(sB, 'annotations/ann_v111_chB'))));
await ok('coexist: 同節 church A → active B deny（by-id 不可 bypass）', assertFails(getDoc(doc(sB, 'annotations/ann_v111_chA'))));
await ok('coexist: 同節 church B → active A deny', assertFails(getDoc(doc(sA, 'annotations/ann_v111_chB'))));
await ok('coexist: 同節 church A → no membership deny，只 public', assertFails(getDoc(doc(sNone, 'annotations/ann_v111_chA'))));
await ok('coexist: 同節 public → no membership allow', assertSucceeds(getDoc(doc(sNone, 'annotations/ann_v111_pub'))));
await ok('coexist: church 空 allowedChurchIds → active A deny（fail-closed）', assertFails(getDoc(doc(sA, 'annotations/ann_v111_chEmpty'))));

// ---- Membership self-switch bypass 封死（§2 A–H）----
// D active A → pending B：DENY
await ok('D active A → pending B: DENY',
  assertFails(setDoc(doc(sA, 'memberships/sA'), { status: 'pending', church_id: 'B' }, { merge: true })));
// E active A → pending A：DENY
await ok('E active A → pending A: DENY',
  assertFails(setDoc(doc(sA, 'memberships/sA'), { status: 'pending' }, { merge: true })));
// F active A → change churchId B（維持 active）：DENY
await ok('F active A → change church B: DENY',
  assertFails(setDoc(doc(sA, 'memberships/sA'), { church_id: 'B' }, { merge: true })));
// G pending → active by student：DENY（sP 已被 admin approve；改用 pending 使用者 sG，種子於頂部）
const sG = env.authenticatedContext('sG', { email: 'g@e.com' }).firestore();
const sRej = env.authenticatedContext('sRej', { email: 'j@e.com' }).firestore();
await ok('G pending A → active A by student: DENY',
  assertFails(setDoc(doc(sG, 'memberships/sG'), { status: 'active' }, { merge: true })));
// H pending A → pending B by student：DENY（不得繞過 admin 換教會）
await ok('H pending A → pending B by student: DENY',
  assertFails(setDoc(doc(sG, 'memberships/sG'), { status: 'pending', church_id: 'B' }, { merge: true })));
// B rejected A → pending A（legal reapply）：allow
await ok('B rejected A → pending A reapply: allow',
  assertSucceeds(setDoc(doc(sRej, 'memberships/sRej'), { status: 'pending', church_id: 'A', reviewed_by: '' }, { merge: true })));
// C revoked A → pending A（legal reapply）：allow
await ok('C revoked A → pending A reapply: allow',
  assertSucceeds(setDoc(doc(sR, 'memberships/sR'), { status: 'pending', church_id: 'A', reviewed_by: '' }, { merge: true })));

await env.cleanup();
console.log(`\n全部 ${passed} 項 rules 測試通過。`);
