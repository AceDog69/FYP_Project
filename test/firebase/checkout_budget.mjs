// Firestore reports Rules exhaustion as permission-denied to clients. A negative
// assertion alone cannot distinguish it from the intended authorization failure.
export const budgetDiagnostic = /maximum of\s+[\d,]+\s+expressions|(?:expression|document.access|evaluation)\s+(?:(?:count|calls)\s+)?(?:limit|budget).{0,60}(?:exceed|exhaust)|(?:exceed|exhaust).{0,100}(?:expression|document.access|evaluation\s+(?:limit|budget))|too many (?:document access|(?:get|exists)\(\))|maximum (?:number of )?(?:document )?access calls|(?:maximum|limit) of\s+(?:10|20)\s+(?:document access|(?:get|exists)\(\))|maximum allowed number of calls/i;

export function budgetFailures(text) {
  return text.split(/\r?\n/).filter(line=>budgetDiagnostic.test(line));
}
