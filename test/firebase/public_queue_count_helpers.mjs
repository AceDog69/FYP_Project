import { doc, getDocFromServer, runTransaction, serverTimestamp } from 'firebase/firestore';
import { requestRef, orderRef, counterRef, payload, writePayload } from './checkout_helpers.mjs';
import { queueRef, initialQueue, progressWrites } from './fcfs_helpers.mjs';

export const countRef = (db, uid = 'vendor') => doc(db, 'stallQueueCounts', uid);
export const countData = (uid, last, next, preparing) => ({schemaVersion:1, vendorUid:uid,
  lastTicket:last, nextTicket:next, preparing, count:last-next+1+(preparing?1:0), updatedAt:serverTimestamp()});

// Vendor-only initialization; Rules validate both canonical sources and their
// boundary order references. No counter/cursor reset and no collection scan.
export async function bootstrapCount(db, uid = 'vendor') {
  await runTransaction(db, async tx => {
    const c = await tx.get(counterRef(db, uid)), q = await tx.get(queueRef(db, uid));
    await tx.get(countRef(db, uid));
    const queue = q.data() ?? initialQueue();
    tx.set(countRef(db, uid), countData(uid, c.data()?.lastTicket ?? 0, queue.nextTicket, queue.preparingOrderId !== null));
  }, {maxAttempts:8});
}
export async function countPayload(db, q, read = getDocFromServer) {
  const summary = await read(countRef(db, q.vendorUid));
  if (!summary.exists()) throw new Error('queue-count-unavailable');
  const c = summary.data();
  // The private counter is written blindly; the Rules retain the private
  // resource.lastTicket + 1 check. Its lastOrderId is NEVER read by a Student.
  const p = await payload(db, q, ref => ref.path === counterRef(db, q.vendorUid).path ? summary : read(ref));
  p.summary = countData(q.vendorUid, c.lastTicket + 1, c.nextTicket, c.preparing);
  p.beforeCount = c;
  return p;
}
export function countWrites(writer, db, p) {
  writePayload(writer, db, p);
  if (!p.omitSummary) writer.set(countRef(db, p.q.vendorUid), p.summary);
}
export async function submitCount(db, q) {
  for (let attempt = 0; attempt < 5; attempt++) {
    let observed, state;
    try {
      await runTransaction(db, async tx => {
        observed = undefined; state = undefined;
        const saved = await tx.get(requestRef(db, q.studentUid, q.submissionId)); state = saved.data()?.state;
        if (state === 'confirmed') return;
        if (state !== 'pending') throw new Error('request-not-pending');
        const p = await countPayload(db, saved.data(), ref => tx.get(ref)); observed = p.beforeCount;
        countWrites(tx, db, p);
      }, {maxAttempts:8});
      return (await getDocFromServer(orderRef(db, q.submissionId))).data();
    } catch (error) {
      if (error.code !== 'permission-denied' || attempt === 4) throw error;
      const request = (await getDocFromServer(requestRef(db, q.studentUid, q.submissionId))).data();
      if (request?.state !== state && ['pending','confirmed','cancelled'].includes(request?.state)) continue;
      const current = (await getDocFromServer(countRef(db, q.vendorUid))).data();
      if (observed && current && (current.lastTicket > observed.lastTicket ||
        current.nextTicket !== observed.nextTicket || current.preparing !== observed.preparing)) continue;
      throw error;
    }
  }
}
export async function advanceCount(db, expected) {
  for (let attempt = 0; attempt < 5; attempt++) {
    let last;
    try {
      await runTransaction(db, async tx => {
        last = undefined;
        const saved = await tx.get(orderRef(db, expected.orderId));
        const cursor = await tx.get(queueRef(db, expected.vendorUid));
        const summary = await tx.get(countRef(db, expected.vendorUid));
        const order = saved.data(), queue = cursor.data() ?? initialQueue(), count = summary.data();
        if (order.status !== expected.status || (order.statusRevision??0) !== (expected.statusRevision??0)) throw new Error('stale-order');
        if (!count || count.nextTicket !== queue.nextTicket || count.preparing !== (queue.preparingOrderId !== null)) throw new Error('stale-count');
        last = count.lastTicket;
        const next = {Pending:'Preparing',Preparing:'Ready',Ready:'Completed'}[order.status];
        if (!next) throw new Error('invalid-transition');
        progressWrites(tx, db, order, queue);
        if (next !== 'Completed') tx.set(countRef(db, order.vendorUid), countData(order.vendorUid,
          last, queue.nextTicket + (next === 'Preparing' ? 1 : 0), next === 'Preparing'));
      }, {maxAttempts:8});
      return (await getDocFromServer(orderRef(db, expected.orderId))).data();
    } catch (error) {
      if (error.code !== 'permission-denied' || last === undefined || attempt === 4) throw error;
      const current = (await getDocFromServer(countRef(db, expected.vendorUid))).data();
      if (current && current.lastTicket > last) continue;
      throw error;
    }
  }
}
