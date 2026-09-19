// Local-only integration test. Requires migrations and a seeded local test admin.
import assert from 'node:assert/strict';
const base='http://localhost:3000';const admin='admin-test@example.edu';
async function call(path,body,email=admin,method='POST',expected=200){const r=await fetch(base+path,{method:body?method:'GET',headers:{...(email?{'oai-authenticated-user-email':email}:{}),...(body?{'content-type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});const d=await r.json();assert.equal(r.status,expected,JSON.stringify(d));return d;}
await call('/api/portal',null,'',undefined,401);
await call('/api/portal',null,'unauthorized@example.edu',undefined,403);
await call('/api/portal',{action:'user',email:'faculty-test@example.edu',name:'Faculty Test',role:'respondent',department:'Electrical Engineering'});
await call('/api/portal',{action:'user',email:'other-test@example.edu',name:'Other Faculty',role:'respondent',department:'Mechanical Engineering'});
let entry={id:'',panel:'5.1',year:'2025–26',department:'Electrical Engineering',respondent:'Faculty Test',designation:'Assistant Professor',email:'faculty-test@example.edu',date:'2026-09-18',data:{'Name of Project guide':'Test Guide','Name of students':'Test Student','Title of the project':'Integration Test Project','Broader subject area covered':'Electrical engineering'},version:0};
entry=(await call('/api/portal',{action:'save',entry},'faculty-test@example.edu')).entry;
await call('/api/portal',{action:'save',entry:{...entry,version:0}},'faculty-test@example.edu','POST',409);
await call('/api/portal',{action:'history',id:entry.id},'other-test@example.edu','POST',403);
const fd=new FormData();fd.set('entryId',entry.id);fd.set('type','Project Report');fd.set('file',new Blob(['Original evidence test bytes'],{type:'text/plain'}),'test-evidence.txt');let response=await fetch(base+'/api/evidence',{method:'POST',headers:{'oai-authenticated-user-email':'faculty-test@example.edu'},body:fd});assert.equal(response.status,200);const evidence=(await response.json()).evidence;
response=await fetch(base+'/api/evidence?id='+evidence.id,{headers:{'oai-authenticated-user-email':'faculty-test@example.edu'}});assert.equal(await response.text(),'Original evidence test bytes');
await call('/api/evidence?id='+evidence.id,null,'other-test@example.edu',undefined,404);
entry=(await call('/api/portal',{action:'submit',entry},'faculty-test@example.edu')).entry;
await call('/api/portal',{action:'save',entry},'faculty-test@example.edu','POST',403);
await call('/api/portal',{action:'review',id:entry.id,status:'Approved',comment:''},admin,'POST',400);
await call('/api/evidence',{id:evidence.id,status:'Verified',comments:'Checked original evidence'},admin,'PATCH');
entry=(await call('/api/portal',{action:'review',id:entry.id,status:'Returned',comment:'Please clarify title.'})).entry;
entry=(await call('/api/portal',{action:'save',entry:{...entry,data:{...entry.data,'Title of the project':'Corrected Test Project'}}},'faculty-test@example.edu')).entry;
entry=(await call('/api/portal',{action:'submit',entry},'faculty-test@example.edu')).entry;
const hist=await call('/api/portal',{action:'history',id:entry.id});assert.equal(hist.history.length,2);assert.equal(hist.history[1].payload.entry.data['Title of the project'],'Integration Test Project');
entry=(await call('/api/portal',{action:'review',id:entry.id,status:'Approved',comment:'Approved.'})).entry;
const report=(await call('/api/report',{action:'generate',year:'2025–26',department:'Electrical Engineering',parameter:'5.1',ai:false})).report;assert.equal(report.sourceSnapshots.length,1);assert.ok(report.sections[0].sources.includes(entry.id));
await call('/api/report',{action:'update',report:{...report,status:'Approved'}});
await call('/api/report',{action:'generate',ai:true},admin,'POST',503);
await call('/api/report',{action:'generate',ai:false},'faculty-test@example.edu','POST',403);
console.log('PASS: anonymous access, membership, department isolation, optimistic concurrency, draft save, R2 byte preservation, evidence authorization, submit lock, returned correction, immutable history, approval gating, source-linked report generation, AI configuration failure.');
