import {tmpdir} from 'node:os';
import {join} from 'node:path';
import assert from 'node:assert/strict';
import test from 'node:test';
import ts from 'typescript';
import {readFileSync,mkdtempSync,writeFileSync} from 'node:fs';
const tmp=mkdtempSync(join(tmpdir(),'naac-auth-tests-'));
writeFileSync(tmp+'/auth.mjs',ts.transpileModule(readFileSync(new URL('../github/auth.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ES2022}}).outputText);
const {validateAuthConfig,applicationUrl,dashboardPath,authProblem,oauthErrorFromUrl,cleanAuthUrl,loadAuthenticatedProfile}=await import(tmp+'/auth.mjs');
test('missing settings are explicit; server secrets are rejected',()=>{
 assert.deepEqual(validateAuthConfig('',''),['VITE_SUPABASE_URL','VITE_SUPABASE_PUBLISHABLE_KEY']);
 assert.ok(validateAuthConfig('https://test.supabase.co','sb_secret_test').some(x=>x.includes('secret')));
 const jwt='header.'+Buffer.from(JSON.stringify({role:'service_role'})).toString('base64url')+'.signature';
 assert.ok(validateAuthConfig('https://test.supabase.co',jwt).some(x=>x.includes('service_role')));
 assert.equal(validateAuthConfig('https://test.supabase.co','sb_publishable_test').length,0);
 assert.ok(validateAuthConfig('http://untrusted.example','sb_publishable_test').length);
 assert.ok(validateAuthConfig('https://test.supabase.co/path','sb_publishable_test').length);
 assert.equal(validateAuthConfig('http://localhost:54321','sb_publishable_test').length,0);
});
test('return URL follows current origin, preserving GitHub Pages base',()=>{
 assert.equal(applicationUrl('http://localhost:5173','/'),'http://localhost:5173/');
 assert.equal(applicationUrl('http://127.0.0.1:5173','/'),'http://127.0.0.1:5173/');
 assert.equal(applicationUrl('https://ag230602.github.io','/portal/'),'https://ag230602.github.io/portal/');
 assert.equal(applicationUrl('https://portal.example.edu','/'),'https://portal.example.edu/');
 for(const path of ['//evil.example','https://evil.example','/../evil','/\\evil'])assert.throws(()=>applicationUrl('https://portal.example.edu',path));
});
test('roles map to requested routes and unknown roles fail closed',()=>{
 for(const [role,path] of [['respondent','student'],['student','student'],['coordinator','coordinator'],['admin','admin']])assert.equal(dashboardPath(role),'/'+path+'/dashboard');
 assert.equal(dashboardPath('admin','/portal/'),'/portal/admin/dashboard');
 for(const role of ['superuser','__proto__','constructor',''])assert.throws(()=>dashboardPath(role));
});
test('OAuth callback errors are safe, useful, and scrubbed from the URL',()=>{
 assert.equal(oauthErrorFromUrl('https://example.edu/?error=invalid_client&error_description=secret-do-not-show').code,'invalid_client');
 assert.equal(oauthErrorFromUrl('https://example.edu/#error=access_denied').code,'access_denied');
 assert.equal(oauthErrorFromUrl('https://example.edu/?code=valid'),null);
 assert.equal(cleanAuthUrl('https://example.edu/portal/?code=private&keep=1#access_token=private&refresh_token=private'),'/portal/?keep=1');
 assert.ok(!authProblem({message:'unknown-secret-value'}).message.includes('unknown-secret-value'));
 assert.equal(authProblem({code:'bad_code_verifier'}).code,'session_expired');
 assert.equal(authProblem({message:'Unsupported provider: provider is not enabled'}).code,'provider_disabled');
});
test('successful login verifies identity and reads authoritative profile for every role',async()=>{
 for(const role of ['respondent','coordinator','admin']){
  const calls=[];const client={auth:{getUser:async()=>{calls.push('verified');return {data:{user:{id:'verified-user',user_metadata:{role:'admin'}}},error:null};}}};
  const result=await loadAuthenticatedProfile(client,async()=>{calls.push('profile');return {user:{role}};});
  assert.deepEqual(calls,['verified','profile']);assert.equal(result.user.role,role);
 }
 let read=false;await assert.rejects(()=>loadAuthenticatedProfile({auth:{getUser:async()=>({error:new Error('expired')})}},async()=>{read=true;}));assert.equal(read,false);
 await assert.rejects(()=>loadAuthenticatedProfile({auth:{getUser:async()=>({data:{user:{id:'x'}}})}},async()=>({user:{role:'unrecognized'}})));
});
