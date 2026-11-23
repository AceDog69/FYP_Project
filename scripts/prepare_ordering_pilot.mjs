import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
import { stage4bRules } from './prepare_stage4b.mjs';

export const project = 'fyp-v2-fd5fb';
export function pilotRules(source) {
  return stage4bRules(source, true);
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
  writeFileSync(resolve(root, 'pilot/firestore.stage4b.rules'), pilotRules(source));
  writeFileSync(resolve(root, 'firebase.v2.pilot.json'), JSON.stringify({firestore: {rules: 'pilot/firestore.stage4b.rules'}}, null, 2) + '\n');
  process.stdout.write(`Prepared Stage 4B Rules for manual review: ${project}. No Firebase connection or deployment performed.\n`);
}
