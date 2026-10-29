// Generates separate review candidates; never contacts or deploys Firebase.
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export function stage4bRules(source, ordering = true) {
  function replaceOnce(from, to) {
    if (source.split(from).length !== 2) throw new Error('Stage 4B Rules anchor changed: ' + from.slice(0, 80));
    source = source.replace(from, to);
  }
  if (!source.includes('function menuDeletesEnabled() { return false; }')) throw new Error('Deletion must remain closed');
  if (ordering) replaceOnce('function checkoutWritesEnabled() { return false; }', 'function checkoutWritesEnabled() { return true; }');
  replaceOnce('    function safeId(id)', `    function countPath(uid) { return /databases/$(database)/documents/stallQueueCounts/$(uid); }
    function lastTicketBefore(uid) {
      return exists(counterPath(uid)) ? get(counterPath(uid)).data.lastTicket : 0;
    }
    function lastTicketAfter(uid) {
      return existsAfter(counterPath(uid)) ? getAfter(counterPath(uid)).data.lastTicket : 0;
    }
    function countQueueAfter(uid) {
      return existsAfter(queuePath(uid)) ? getAfter(queuePath(uid)).data
        : {'nextTicket':1, 'preparingOrderId':null, 'revision':0};
    }
    function countMatches(d, uid, last, q) {
      return d == {'schemaVersion':1, 'vendorUid':uid, 'lastTicket':last,
          'nextTicket':q.nextTicket, 'preparing':q.preparingOrderId != null,
          'count':last - q.nextTicket + 1 + (q.preparingOrderId != null ? 1 : 0), 'updatedAt':d.updatedAt}
        && d.updatedAt is timestamp && d.schemaVersion is int && d.lastTicket is int
        && d.nextTicket is int && d.preparing is bool && last is int && last >= 0 && last <= 2147483647
        && q.nextTicket is int && q.nextTicket >= 1 && q.nextTicket <= last + 1
        && d.count is int && d.count >= 0 && d.count <= last;
    }
    function countCurrent(d, uid) { return countMatches(d, uid, lastTicketBefore(uid), queueBefore(uid)); }
    function countAfter(d, uid) { return countMatches(d, uid, lastTicketAfter(uid), countQueueAfter(uid)); }
    function countForCounter(uid, last) {
      let d = getAfter(countPath(uid)).data;
      return d.lastTicket == last && d.updatedAt == request.time;
    }
    function countForQueue(uid, q) {
      let d = getAfter(countPath(uid)).data;
      return d.nextTicket == q.nextTicket && d.preparing == (q.preparingOrderId != null)
        && d.updatedAt == request.time;
    }
    function bootstrapCounter(uid) {
      let c = getAfter(counterPath(uid)).data;
      let o = getAfter(orderPath(c.lastOrderId)).data;
      return c.keys().hasAll(['schemaVersion','vendorUid','lastTicket','lastOrderId','updatedAt'])
        && c.keys().hasOnly(['schemaVersion','vendorUid','lastTicket','lastOrderId','updatedAt'])
        && c.schemaVersion == 1 && c.vendorUid == uid && c.updatedAt is timestamp
        && c.lastTicket is int && c.lastTicket >= 1 && c.lastTicket <= 2147483647
        && o.vendorUid == uid && o.ticket == c.lastTicket && o.orderId == c.lastOrderId
        && o.status in ['Pending','Preparing','Ready','Completed'];
    }
    function bootstrapQueue(uid) {
      let q = getAfter(queuePath(uid)).data;
      return q.keys().hasAll(['schemaVersion','vendorUid','nextTicket','preparingOrderId','revision','updatedAt'])
        && q.keys().hasOnly(['schemaVersion','vendorUid','nextTicket','preparingOrderId','revision','updatedAt'])
        && q.schemaVersion == 1 && q.vendorUid == uid && q.updatedAt is timestamp
        && q.nextTicket is int && q.nextTicket >= 2 && q.revision is int
        && q.revision == 2 * (q.nextTicket - 1) - (q.preparingOrderId != null ? 1 : 0)
        && (q.preparingOrderId == null ||
          (getAfter(orderPath(q.preparingOrderId)).data.vendorUid == uid
            && getAfter(orderPath(q.preparingOrderId)).data.status == 'Preparing'
            && getAfter(orderPath(q.preparingOrderId)).data.ticket == q.nextTicket - 1));
    }
    function countBootstrap(uid) {
      return (!existsAfter(counterPath(uid)) || bootstrapCounter(uid))
        && (!existsAfter(queuePath(uid)) || bootstrapQueue(uid));
    }
    match /stallQueueCounts/{vendorUid} {
      // Reads verify agreement with current authority, so rollback/old clients
      // cannot leave a stale projection that still appears server-confirmed.
      allow get: if (studentMenuReader(vendorUid) && (resource == null || countCurrent(resource.data, vendorUid)))
        || configuredVendor(vendorUid);
      allow list, delete: if false;
      allow create: if configuredVendor(vendorUid) && countBootstrap(vendorUid)
        && request.resource.data.updatedAt == request.time && countAfter(request.resource.data, vendorUid);
      allow update: if request.resource.data.updatedAt == request.time
        && ((checkoutWritesEnabled() && student()
            && getAfter(counterPath(vendorUid)).data.updatedAt == request.time
            && getAfter(counterPath(vendorUid)).data.lastTicket == resource.data.lastTicket + 1)
          || (configuredVendor(vendorUid) && countBootstrap(vendorUid)))
        && countAfter(request.resource.data, vendorUid);
    }
    function safeId(id)`);
  replaceOnce('allow read: if studentMenuReader(vendorUid) || configuredVendor(vendorUid);',
    'allow get: if configuredVendor(vendorUid);\n      allow list: if false;');
  replaceOnce('&& request.resource.data.lastTicket == 1;',
    '&& request.resource.data.lastTicket == 1 && countForCounter(vendorUid, 1);');
  replaceOnce('&& request.resource.data.lastTicket == resource.data.lastTicket + 1;',
    '&& request.resource.data.lastTicket == resource.data.lastTicket + 1\n        && countForCounter(vendorUid, request.resource.data.lastTicket);');
  replaceOnce('&& progressMatches(getAfter(progressPath(vendorUid)).data, request.resource.data, vendorUid);',
    '&& progressMatches(getAfter(progressPath(vendorUid)).data, request.resource.data, vendorUid)\n        && countForQueue(vendorUid, request.resource.data);');
  return source;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length !== 2) throw new Error('No arguments allowed: generation only, no deployment.');
  const source = readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8');
  for (const [name, ordering] of [['stage4b',true],['stage4b.closed',false]]) {
    writeFileSync(new URL('../pilot/firestore.' + name + '.rules', import.meta.url), stage4bRules(source, ordering));
  }
  console.log('Prepared Stage 4B candidates; default/pilot/Stage 4A Rules unchanged. Nothing deployed.');
}
