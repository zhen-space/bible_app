#!/usr/bin/env node
// audience_preflight_audit 純函式測試（無網路、無 credential）。
// 用法：node tools/audience_preflight_audit_test.mjs

import assert from 'node:assert';
import { readFileSync } from 'node:fs';
import { classifyDoc } from './audience_preflight_audit.mjs';

let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

// public audience
{
  const c = classifyDoc({ audience: 'public' }, { published: true });
  ok(c.audPublic && !c.missing && !c.invalid && !c.churchEmptyAllowed, 'public');
}
// church + allowed ok
{
  const c = classifyDoc({ audience: 'church', allowed_church_ids: ['A'] }, { published: true });
  ok(c.audChurch && !c.churchEmptyAllowed, 'church with allowed');
}
// church + empty allowed → manual
{
  const c = classifyDoc({ audience: 'church', allowed_church_ids: [] }, { published: true });
  ok(c.churchEmptyAllowed, 'church empty allowed → manual');
}
// church + missing allowed → manual
{
  const c = classifyDoc({ audience: 'church' }, { published: true });
  ok(c.churchEmptyAllowed, 'church missing allowed → manual');
}
// missing audience → auto-migratable
{
  const c = classifyDoc({ status: 'published' }, { published: true });
  ok(c.missing && !c.invalid && !c.legacyVisibilityOnly, 'missing audience');
}
// missing audience + legacy visibility → legacyVisibilityOnly
{
  const c = classifyDoc({ visibility: 'student' }, { published: true });
  ok(c.missing && c.legacyVisibilityOnly, 'legacy visibility only');
}
// invalid audience → manual, not overwritten
{
  const c = classifyDoc({ audience: 'weird' }, { published: true });
  ok(c.invalid && !c.missing, 'invalid audience → manual');
}
// internal
{
  const c = classifyDoc({ audience: 'internal' }, { published: false });
  ok(c.audInternal && !c.published, 'internal, unpublished');
}
// questions published flag
{
  const c = classifyDoc({ published: true, audience: 'public' }, { published: true });
  ok(c.published && c.audPublic, 'question published+public');
}

// 靜態安全：工具不得有任何寫入 / users 路徑 / deploy。
const src = readFileSync(new URL('./audience_preflight_audit.mjs', import.meta.url), 'utf8');
ok(!/\.set\(|\.update\(|\.delete\(|\.add\(|batch\(|bulkWriter/.test(src), '不得有任何 write API');
ok(!/includes\(\s*['"]--apply/.test(src) && !/const\s+APPLY/.test(src), '不得有 --apply code path');
ok(!/collection(Group)?\(\s*['"](users|memberships)['"]/.test(src), '不得觸碰 users/memberships collection');
ok(!/(openai|anthropic|fetch\(|WebSearch)/i.test(src), '不得有 LLM/Web');
ok(/collectionGroup\(['"]chapters['"]\)|collectionGroup\(name\)/.test(src), '涵蓋 chapters collection group');

console.log(`audience_preflight_audit 純函式測試通過（${n} 項）。`);
