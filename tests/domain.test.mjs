import {tmpdir} from 'node:os';
import {join} from 'node:path';
import assert from 'node:assert/strict';
import test from 'node:test';
import ts from 'typescript';
import fs from 'node:fs';
const compiled = fs.mkdtempSync(join(tmpdir(),'naac-tests-'));
for(const name of ['fields','reports','demo']){const source=fs.readFileSync(new URL('../lib/'+name+'.ts',import.meta.url),'utf8').replaceAll("'./fields'","'./fields.mjs'");fs.writeFileSync(compiled+'/'+name+'.mjs',ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ES2022}}).outputText);}
const {panels,missing}=await import(compiled+'/fields.mjs');
const {compileReport}=await import(compiled+'/reports.mjs');
const {demoEntries}=await import(compiled+'/demo.mjs');
test('original Word annexure columns have dedicated fields',()=>{const expected={'5.1':['Name of Project guide','Name of students','Title of the project','Broader subject area covered','Whether collaborative / interdisciplinary','Whether report is available','Does it support flipped learning'],'5.3':['Seminar topic','Name of students','Name of guide','Broader subject area','Whether seminar report/ PPT is preserved?'],'5.4':['Name of laboratory','Name of experiment','Whether implementing the concept','If yes How?'],'5.6':['Name of students','Name of company/ institute','Tenure of internship','Paid/ un paid','Does department has all relevant documents?'],'5.7':['Name of student','Name of faculty member','Name of subject','Topic covered','Previous grade','Present grade','Signature of the student','Signature of the faculty member']};for(const [id,labels] of Object.entries(expected)){const panel=panels.find(p=>p.id===id);assert.ok(panel);for(const label of labels)assert.ok(panel.fields.some(f=>f.label===label),id+': '+label);}});
test('all 13 annexures, separate SWAYAM/seminar panels, and institutional sections exist',()=>{assert.equal(panels.length,17);assert.equal(new Set(panels.map(p=>p.id)).size,17);for(let n=1;n<=13;n++)assert.ok(panels.some(p=>p.id.startsWith('5.'+n)&&p.id.replace(/[ab]$/,'')==='5.'+n));});
test('report excludes drafts and scopes by department and year',()=>{const out=compileReport(demoEntries,[],{year:'2025–26',department:'Electrical Engineering',parameter:''});assert.match(out[0].text,/1 submitted records/);assert.deepEqual(out[0].sources,['demo-0']);assert.match(out.find(s=>s.heading==='Supporting Evidence Status').text,/1 have evidence missing/);assert.ok(out.every(s=>s.sources.every(id=>id==='demo-0')));});
test('report never invents data for empty parameters',()=>{const out=compileReport([],[],{year:'',department:'',parameter:''});assert.ok(out.every(s=>s.text==='Data not provided.'&&s.sources.length===0));});
test('required respondent and annexure information is checked',()=>{const e=structuredClone(demoEntries[0]);e.designation='';e.data['Title of the project']='';assert.ok(missing(e).includes('designation'));assert.ok(missing(e).includes('Title of the project'));});
