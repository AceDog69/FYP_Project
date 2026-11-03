// Local file generation only. No Firebase CLI, credentials or network access.
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { stage4bRules } from './prepare_stage4b.mjs';

const closed = 'function menuDeletesEnabled() { return false; }';
const open = 'function menuDeletesEnabled() { return true; }';
export function integratedRules(stage4b) {
  if (stage4b.split(closed).length !== 2 ||
      (stage4b.match(/function\s+menuDeletesEnabled\s*\(/g) ?? []).length !== 1 ||
      !stage4b.includes('function checkoutWritesEnabled() { return true; }')) {
    throw new Error('Expected the verified ordering Stage 4B candidate with one closed Food Delete gate');
  }
  return stage4b.replace(closed, open);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length !== 2) throw new Error('No arguments allowed: local generation only.');
  const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
  const stage4b = read('pilot/firestore.stage4b.rules');
  if (stage4b !== stage4bRules(read('firestore.rules'))) {
    throw new Error('Stage 4B candidate differs from its reproducible source; stop for review');
  }
  writeFileSync(new URL('../pilot/firestore.stage4-integrated.rules', import.meta.url), integratedRules(stage4b));
  console.log('Prepared integrated Stage 4 Rules candidate. Existing candidates unchanged; nothing deployed.');
}
