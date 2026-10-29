import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stage4bRules } from './prepare_stage4b.mjs';
const read = path => readFileSync(new URL('../'+path,import.meta.url),'utf8');
test('separate closed/ordering candidates are reproducible and retain deletion-disabled defaults', () => {
  const source = read('firestore.rules');
  for (const [file, ordering] of [['stage4b',true],['stage4b.closed',false]]) {
    const candidate = read('pilot/firestore.'+file+'.rules'); assert.equal(candidate,stage4bRules(source,ordering));
    assert.ok(candidate.includes('function menuDeletesEnabled() { return false; }'));
    assert.ok(candidate.includes('allow delete: if false;'));
  }
  assert.ok(source.includes('function checkoutWritesEnabled() { return false; }'));
  assert.equal(JSON.parse(read('firebase.stage4b.json')).firestore.rules,'pilot/firestore.stage4b.rules');
  assert.equal(JSON.parse(read('firebase.stage4b.closed.json')).firestore.rules,'pilot/firestore.stage4b.closed.rules');
});
test('candidate changes only reviewed counter-read/reciprocal rules and adds sanitized projection', () => {
  const source = read('firestore.rules'), candidate = stage4bRules(source);
  assert.ok(candidate.includes('countForCounter(vendorUid'));
  assert.ok(candidate.includes('countForQueue(vendorUid'));
  for (const [start,end] of [['function validOrderProgress','function progressPath'],
    ['function validOrder(d','function validCounter'],['function validOrderItem','function validOrder(d']]) {
    const body = s => s.slice(s.indexOf(start),s.indexOf(end,s.indexOf(start)));
    assert.equal(body(source),body(candidate));
  }
  const counter = candidate.slice(candidate.indexOf('match /checkoutCounters'),candidate.indexOf('match /queueProgress'));
  assert.ok(counter.includes('allow get: if configuredVendor(vendorUid)'));
  assert.ok(!counter.includes('studentMenuReader'));
});
test('generation fails on changed/duplicated anchors or a deletion-enabled source', () => {
  const source = read('firestore.rules');
  assert.throws(() => stage4bRules(source+source));
  assert.throws(() => stage4bRules(source.replace('function menuDeletesEnabled() { return false; }','function menuDeletesEnabled() { return true; }')));
});
