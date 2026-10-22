import { spawn } from 'node:child_process';
import { readFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { budgetFailures } from './checkout_budget.mjs';

// Runs INSIDE firebase emulators:exec. Keep all earlier 46 cases and fail even
// when assertFails would otherwise accept expression/access exhaustion.
const directory=dirname(fileURLToPath(import.meta.url));
const paths=[resolve(directory,'firestore-debug.log'),resolve(directory,'../../firestore-debug.log')];
const offsets=new Map(paths.map(path=>[path,existsSync(path)?readFileSync(path).length:0]));
const child=spawn(process.execPath,['--test','--test-concurrency=1',
  'stage_one.test.mjs','vendor_operations.test.mjs','vendor_menu.test.mjs',
  'student_catalog.test.mjs','checkout_orders.test.mjs'],{cwd:directory,env:process.env,stdio:['inherit','pipe','pipe']});
let output='';
for(const [stream,target] of [[child.stdout,process.stdout],[child.stderr,process.stderr]]) {
  stream.on('data',chunk=>{output+=chunk.toString();target.write(chunk);});
}
const code=await new Promise((resolve,reject)=>{child.on('error',reject);child.on('close',resolve);});
const logs=paths.filter(existsSync).map(path=>{
  const data=readFileSync(path),start=offsets.get(path);
  return {path,text:data.subarray(data.length>=start?start:0).toString()};
});
const failures=[...budgetFailures(output),...logs.flatMap(log=>budgetFailures(log.text))];
const evidence=logs.some(log=>log.text.length>0);
mkdirSync(resolve(directory,'artifacts'),{recursive:true});
writeFileSync(resolve(directory,'artifacts/checkout-budget-diagnostics.json'),JSON.stringify({
  childExitCode:code,logs:logs.map(log=>log.path),budgetDiagnostics:failures,
  note:'No per-request expression count is inferred from log silence. Positive 1–2-food, over-limit rejection and all integrity/concurrency tests must also pass.'
},null,2));
if(!evidence) process.stderr.write('FAIL: Firestore debug log missing/empty; budget evidence unavailable.\n');
if(failures.length) process.stderr.write(`FAIL: ${failures.length} Rules budget diagnostics; negative assertions do not count as proof.\n`);
process.exitCode=code===0&&evidence&&failures.length===0?0:1;
