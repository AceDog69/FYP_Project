import { doc, getDocFromServer, runTransaction, serverTimestamp } from 'firebase/firestore';
import { orderRef } from './checkout_helpers.mjs';
export const queueRef=(db,uid='vendor')=>doc(db,'vendorQueues',uid);
export const progressRef=(db,uid='vendor')=>doc(db,'queueProgress',uid);
export const progressData=(uid,queue)=>({schemaVersion:1,vendorUid:uid,nextTicket:queue.nextTicket,
  preparing:queue.preparingOrderId!==null,revision:queue.revision,updatedAt:queue.updatedAt});
export const initialQueue=()=>({nextTicket:1,preparingOrderId:null,revision:0});
export const statuses=['Pending','Preparing','Ready','Completed'];
export function progressWrites(writer,db,order,queue) {
  const next=statuses[statuses.indexOf(order.status)+1];
  writer.update(orderRef(db,order.orderId),{status:next,statusRevision:(order.statusRevision??0)+1,
    statusUpdatedAt:serverTimestamp(),
    [next==='Preparing'?'preparingAt':next==='Ready'?'readyAt':'completedAt']:serverTimestamp()});
  if(next!=='Completed') {
    const after={
    schemaVersion:1,vendorUid:order.vendorUid,nextTicket:queue.nextTicket+(next==='Preparing'?1:0),
    preparingOrderId:next==='Preparing'?order.orderId:null,revision:queue.revision+1,updatedAt:serverTimestamp()};
    writer.set(queueRef(db,order.vendorUid),after);
    writer.set(progressRef(db,order.vendorUid),progressData(order.vendorUid,after));
  }
}
// Executable JS counterpart of the Dart processing transaction. The adversarial
// cases bypass this guard completely and exercise Rules with raw batches.
export async function advance(db,expected,{maxAttempts=8}={}) {
  await runTransaction(db,async tx=>{
    const record=await tx.get(orderRef(db,expected.orderId));
    const cursor=await tx.get(queueRef(db,expected.vendorUid));
    const order=record.data(),queue=cursor.data()??initialQueue();
    if(order?.status!==expected.status||(order.statusRevision??0)!==(expected.statusRevision??0))
      throw new Error('stale-order');
    if((order.status==='Pending'&&(queue.preparingOrderId!==null||queue.nextTicket!==order.ticket))||
       (order.status==='Preparing'&&queue.preparingOrderId!==order.orderId)||order.status==='Completed')
      throw new Error('ineligible-order');
    progressWrites(tx,db,order,queue);
  },{maxAttempts});
  const confirmed=await getDocFromServer(orderRef(db,expected.orderId));
  if(confirmed.metadata.hasPendingWrites) throw new Error('unconfirmed-order');
  return confirmed.data();
}
