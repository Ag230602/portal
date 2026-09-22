import {tmpdir} from 'node:os';
import {join} from 'node:path';
import assert from 'node:assert/strict';
import test from 'node:test';
import ts from 'typescript';
import {readFileSync,mkdtempSync,writeFileSync} from 'node:fs';
const tmp=mkdtempSync(join(tmpdir(),'naac-gemini-'));
writeFileSync(tmp+'/gemini.mjs',ts.transpileModule(readFileSync(new URL('../supabase/functions/_shared/gemini.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ES2022}}).outputText);
const {generateGeminiSummary,validateSummary}=await import(tmp+'/gemini.mjs');
const counted=[{heading:'Projects',text:'1 project',sources:['record-1']}];
const generated={sections:[{heading:'Projects',text:'A project was submitted.',sources:['record-1']}]};
test('Gemini sends key only in header, requests structured JSON and parses completed response',async()=>{
 const result=await generateGeminiSummary('test-key','gemini-3.5-flash',{countedSections:counted},async(url,options)=>{
  assert.ok(url.startsWith('https://generativelanguage.googleapis.com/'));
  assert.ok(!url.includes('test-key'));assert.equal(options.headers['x-goog-api-key'],'test-key');
  assert.ok(!options.body.includes('test-key'));
  assert.equal(JSON.parse(options.body).generationConfig.responseMimeType,'application/json');
  return Response.json({candidates:[{finishReason:'STOP',content:{parts:[{text:JSON.stringify(generated)}]}}]});
 });
 assert.deepEqual(validateSummary(result,counted,['record-1']),generated.sections);
});
test('key and model validation prevent empty credentials or arbitrary endpoints',async()=>{
 const never=()=>{throw new Error('Network must not be called');};
 await assert.rejects(()=>generateGeminiSummary('','gemini-3.5-flash',{},never),/Enter your Gemini API key/);
 await assert.rejects(()=>generateGeminiSummary('test','https://other.example',{},never),/valid Gemini model/);
});
test('quota and invalid-key errors do not echo provider bodies or secrets',async()=>{
 for(const [status,expected] of [[403,/rejected access/],[429,/quota/],[404,/model is unavailable/],[400,/could not accept/]]){
  await assert.rejects(()=>generateGeminiSummary('private-test-key','gemini-3.5-flash',{},async()=>new Response('private-test-key',{status})),e=>expected.test(e.message)&&!e.message.includes('private-test-key'));
 }
});
test('truncated, blocked and malformed output fail before a report can be saved',async()=>{
 for(const data of [{candidates:[{finishReason:'MAX_TOKENS'}]},{promptFeedback:{blockReason:'SAFETY'}},{candidates:[{finishReason:'STOP',content:{parts:[{text:'not json'}]}}]}]){
  await assert.rejects(()=>generateGeminiSummary('test','gemini-3.5-flash',{},async()=>Response.json(data)),/complete summary/);
 }
});
test('validation rejects fabricated sources, missing headings and malformed sections',()=>{
 for(const sections of [[],[{...generated.sections[0],sources:['invented']}],[{...generated.sections[0],heading:'Wrong'}],[{...generated.sections[0],sources:null}],[null],[{...generated.sections[0],sources:[]}]]){
  assert.throws(()=>validateSummary({sections},counted,['record-1']),/source validation/);
 }
 assert.deepEqual(validateSummary({sections:[{heading:'Projects',text:'Data not provided.',sources:[]}]},counted,[]),[{heading:'Projects',text:'Data not provided.',sources:[]}]);
});
test('model lookup uses returned text models, handles pagination and never puts key in URL',async()=>{
 const {listGeminiModels}=await import(tmp+'/gemini.mjs');let calls=0;
 const result=await listGeminiModels('test-key',async(url,options)=>{
  assert.ok(!url.includes('test-key'));assert.equal(options.headers['x-goog-api-key'],'test-key');calls++;
  if(calls===1)return Response.json({models:[{name:'models/gemini-test-pro',supportedGenerationMethods:['generateContent']},{name:'models/gemini-test-image',supportedGenerationMethods:['generateContent']},{name:'models/gemini-embedding',supportedGenerationMethods:['embedContent']}],nextPageToken:'next'});
  assert.ok(url.includes('pageToken=next'));return Response.json({models:[{name:'models/gemini-test-flash',supportedGenerationMethods:['generateContent']}]});
 });
 assert.deepEqual(result,['gemini-test-flash','gemini-test-pro']);
 await assert.rejects(()=>listGeminiModels('test',async()=>Response.json({models:[]})),/No Gemini text/);
 await assert.rejects(()=>listGeminiModels('test',async()=>new Response('secret',{status:403})),/could not verify/);
});
