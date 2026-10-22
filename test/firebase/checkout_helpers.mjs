import { doc, collection, getDoc, setDoc, updateDoc, writeBatch, runTransaction, serverTimestamp } from 'firebase/firestore';

export const requestRef=(db,uid,id)=>doc(db,'users',uid,'checkoutRequests',id);
export const orderRef=(db,id)=>doc(db,'orders',id);
export const counterRef=(db,vendor='vendor')=>doc(db,'checkoutCounters',vendor);
export async function account(env,uid,role='student') {
  const db=env.authenticatedContext(uid,{email:`${uid}@example.com`}).firestore();
  await setDoc(doc(db,'users',uid),{uid,fullName:'Synthetic Account',email:`${uid}@example.com`,
    phoneNumber:'0123456789',role,createdAt:serverTimestamp(),stallSetupComplete:false,stallId:null});
  return db;
}
export async function vendor(env,uid='vendor') {
  const db=await account(env,uid,'vendor'),setup=writeBatch(db);
  setup.set(doc(db,'stalls',uid),{ownerUid:uid,name:`${uid} Kitchen`,category:'Malay',preparationMinutes:15,
    status:'closed',createdAt:serverTimestamp()});
  setup.update(doc(db,'users',uid),{stallSetupComplete:true,stallId:uid});await setup.commit();
  await updateDoc(doc(db,'stalls',uid),{status:'open',updatedAt:serverTimestamp()});
  await setDoc(doc(db,'publicStalls',uid),{vendorUid:uid,name:`${uid} Kitchen`,category:'Malay',
    preparationMinutes:15,status:'open',updatedAt:serverTimestamp()});
  for(let i=0;i<5;i++) {
    const category=writeBatch(db),categoryId=`cat${i}`,name=`Category${i}`;
    category.set(doc(db,'stalls',uid,'menuCategories',categoryId),{vendorUid:uid,name,nameKey:name.toLowerCase(),revision:1,
      createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
    category.set(doc(db,'stalls',uid,'menuCategoryNames',name.toLowerCase()),{vendorUid:uid,categoryId});await category.commit();
    const food=writeBatch(db);
    food.set(doc(db,'stalls',uid,'menuFoods',`food${i}`),{vendorUid:uid,name:`Food ${i}`,description:'Synthetic food',
      categoryId,pictureId:'nasi_lemak',priceSen:[850,905,1,100000,1100][i],available:true,revision:1,
      createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
    food.set(doc(db,'stalls',uid,'menuMemberships',`food${i}`),{vendorUid:uid,categoryId});await food.commit();
  }
  return db;
}
export async function draft(db,uid='student',vendorUid='vendor',count=1) {
  const id=doc(collection(db,'orders')).id,items=[];
  for(let i=0;i<count;i++) {
    const data=(await getDoc(doc(db,'stalls',vendorUid,'menuFoods',`food${i}`))).data();
    items.push({foodId:`food${i}`,name:data.name,description:data.description,categoryId:data.categoryId,
      pictureId:data.pictureId,priceSen:data.priceSen,quantity:i+1,foodRevision:data.revision});
  }
  return {schemaVersion:1,submissionId:id,studentUid:uid,vendorUid,stallName:`${vendorUid} Kitchen`,
    items,totalSen:items.reduce((s,i)=>s+i.priceSen*i.quantity,0),paymentMethod:'ewallet',state:'pending',
    createdAt:serverTimestamp(),updatedAt:serverTimestamp()};
}
export const prepare=(db,q)=>setDoc(requestRef(db,q.studentUid,q.submissionId),q);

// Deliberately do NOT apply Flutter's stale-Cart checks here. Adversarial
// snapshots go directly to Rules, proving client validation is insufficient.
export async function payload(db,q,read=ref=>getDoc(ref)) {
  const listing=await read(doc(db,'publicStalls',q.vendorUid));
  const counter=await read(counterRef(db,q.vendorUid));
  const lines=[];
  for(const expected of q.items) {
    await read(doc(db,'stalls',q.vendorUid,'menuFoods',expected.foodId));
    const category=await read(doc(db,'stalls',q.vendorUid,'menuCategories',expected.categoryId));
    lines.push({...expected,categoryName:category.data()?.name??'Forged category',subtotalSen:expected.priceSen*expected.quantity});
  }
  const ticket=(counter.data()?.lastTicket??0)+1;
  return {q,lines,header:{schemaVersion:1,orderId:q.submissionId,submissionId:q.submissionId,studentUid:q.studentUid,
    vendorUid:q.vendorUid,stallName:q.stallName,preparationMinutes:listing.data()?.preparationMinutes??15,
    ticket,itemCount:lines.length,totalSen:q.totalSen,status:'Pending',paymentMethod:q.paymentMethod,
    paymentStatus:'simulated',createdAt:serverTimestamp(),firstItem:lines[0]},
    counter:{schemaVersion:1,vendorUid:q.vendorUid,lastTicket:ticket,lastOrderId:q.submissionId,updatedAt:serverTimestamp()},
    omitCounter:false,omitRequest:false,omitChild:null};
}
export function writePayload(writer,db,p) {
  writer.set(orderRef(db,p.q.submissionId),p.header);
  for(let i=1;i<p.lines.length;i++) if(p.omitChild!==i) writer.set(doc(db,'orders',p.q.submissionId,'items',`${i}`),p.lines[i]);
  if(!p.omitCounter) writer.set(counterRef(db,p.q.vendorUid),p.counter);
  if(!p.omitRequest) writer.update(requestRef(db,p.q.studentUid,p.q.submissionId),{state:'confirmed',updatedAt:serverTimestamp()});
}
export async function directCheckout(db,q,mutate=()=>{}) {
  const p=await payload(db,q);mutate(p);const b=writeBatch(db);writePayload(b,db,p);return b.commit();
}
export async function submit(db,uid,id) {
  await runTransaction(db,async tx=>{
    const record=await tx.get(requestRef(db,uid,id));const q=record.data();
    if(q?.state==='confirmed') return;
    if(q?.state!=='pending') throw new Error('Request is cancelled or absent');
    const p=await payload(db,q,ref=>tx.get(ref));writePayload(tx,db,p);
  });
  return (await getDoc(orderRef(db,id))).data();
}
export function discard(db,q) {
  return runTransaction(db,async tx=>{
    const ref=requestRef(db,q.studentUid,q.submissionId),saved=await tx.get(ref);
    if(!saved.exists()) {tx.set(ref,{...q,state:'cancelled'});return 'cancelled';}
    if(saved.data().state==='confirmed') return 'confirmed';
    if(saved.data().state==='pending') tx.update(ref,{state:'cancelled',updatedAt:serverTimestamp()});
    return 'cancelled';
  });
}
