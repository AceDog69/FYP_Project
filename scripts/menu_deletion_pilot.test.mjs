import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const base = readFileSync(new URL('../pilot/firestore.ordering.rules', import.meta.url), 'utf8');
const candidate = readFileSync(new URL('../pilot/firestore.menu-deletion.rules', import.meta.url), 'utf8');
const config = JSON.parse(readFileSync(new URL('../firebase.menu-deletion.pilot.json', import.meta.url)));

test('menu-deletion candidate changes only the dedicated food-delete gate', () => {
  const closed = 'function menuDeletesEnabled() { return false; }';
  const open = 'function menuDeletesEnabled() { return true; }';
  assert.equal(base.split(closed).length, 2);
  assert.equal(candidate, base.replace(closed, open));
  assert.ok(candidate.includes('function checkoutWritesEnabled() { return true; }'));
  assert.equal((candidate.match(/function\s+menuDeletesEnabled\s*\(/g) ?? []).length, 1);
});

test('the isolated configuration references only the reviewable candidate', () => {
  assert.deepEqual(config, { firestore: { rules: 'pilot/firestore.menu-deletion.rules' } });
});
