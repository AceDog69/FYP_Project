import { test } from 'node:test';
import assert from 'node:assert/strict';
import { budgetFailures } from './checkout_budget.mjs';

test('budget guard identifies exhaustion hidden behind permission errors',()=>{
  assert.equal(budgetFailures('Error: maximum of 1000 expressions to evaluate has been reached.').length,1);
  assert.equal(budgetFailures('PERMISSION_DENIED: maximum of 1,000 expressions exceeded').length,1);
  assert.equal(budgetFailures('Rules evaluation exceeded the document access limit').length,1);
  assert.equal(budgetFailures('Document access calls limit exceeded (maximum 20)').length,1);
  assert.equal(budgetFailures('maximum allowed number of calls to get(), exists(), and getAfter()').length,1);
  assert.equal(budgetFailures('PERMISSION_DENIED: false for create at L301').length,0);
});
