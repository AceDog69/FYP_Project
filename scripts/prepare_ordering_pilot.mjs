import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';

export const project = 'fyp-app-9d78a';
export function pilotRules(source) {
  const closed = 'function checkoutWritesEnabled() { return false; }';
  if (source.split(closed).length !== 2 ||
      source.split('function checkoutWritesEnabled()').length !== 2 ||
      source.split('function menuDeletesEnabled() { return false; }').length !== 2) {
    throw new Error('Expected exactly one disabled checkout and deletion gate.');
  }
  return source.replace(closed, 'function checkoutWritesEnabled() { return true; }');
}
export function validateArgs(args) {
  if (args.length !== 2 || args[0] !== '--project' || args[1] !== project) {
    throw new Error(`Only --project ${project} is accepted. This command only generates files, never deploys.`);
  }
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  validateArgs(process.argv.slice(2));
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  const source = readFileSync(resolve(root, 'firestore.rules'), 'utf8');
  mkdirSync(resolve(root, 'pilot'), { recursive: true });
  writeFileSync(resolve(root, 'pilot/firestore.ordering.rules'), pilotRules(source));
  writeFileSync(resolve(root, 'firebase.pilot.json'), JSON.stringify({firestore: {rules: 'pilot/firestore.ordering.rules'}}, null, 2) + '\n');
  process.stdout.write(`Prepared ordering Rules for manual review: ${project}. No Firebase connection or deployment performed.\n`);
}
