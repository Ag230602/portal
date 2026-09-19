import {createClient} from '@supabase/supabase-js';
import type {PortalTransport} from '../lib/transport';
import {validateAuthConfig,applicationUrl} from './auth';
const url=import.meta.env.VITE_SUPABASE_URL?.trim()||'';
const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim()||'';
export const configurationErrors=validateAuthConfig(url,key);
export const configured=configurationErrors.length===0;
export const supabase=configured?createClient(url,key,{auth:{flowType:'pkce',persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}):null;
export const appBase=import.meta.env.BASE_URL;
export const returnUrl=()=>applicationUrl(window.location.origin,appBase);
export async function rpc(action:string,payload:unknown={}){if(!supabase)throw new Error('The Supabase publishable key has not been configured.');const {data,error}=await supabase.rpc('naac_portal',{action,payload});if(error)throw new Error(error.message);return data;}
export const transport:PortalTransport={
 async request(path,body:any,method){
  if(!supabase)throw new Error('The Supabase publishable key has not been configured.');
  if(path==='/api/portal')return rpc(body?.action||'load',body||{});
  if(path==='/api/evidence'&&method==='PATCH')return rpc('verifyEvidence',body);
  if(path==='/api/report'){
   if(body.action==='update')return rpc('updateReport',body);
   const {data,error}=await supabase.functions.invoke('naac-report',{body});
   if(error){const context=(error as any).context;if(context instanceof Response){const d=await context.json().catch(()=>null);throw new Error(d?.error||error.message);}throw error;}return data;
  }
  throw new Error('Unsupported portal request.');
 },
 async upload(form){if(!supabase)throw new Error('Sign in first.');const file=form.get('file') as File;const entryId=String(form.get('entryId'));const id=crypto.randomUUID();if(!file||file.size>20*1024*1024)throw new Error('Choose a file up to 20 MB.');const objectKey=entryId+'/'+id;const {error}=await supabase.storage.from('naac-evidence').upload(objectKey,file,{upsert:false,contentType:'application/octet-stream'});if(error)throw error;return rpc('registerEvidence',{entryId,id,objectKey,name:file.name,type:String(form.get('type')),size:file.size});},
 async download(id){if(!supabase)throw new Error('Sign in first.');const info=await rpc('evidenceDownload',{id});const {data,error}=await supabase.storage.from('naac-evidence').createSignedUrl(info.objectKey,60,{download:info.name});if(error)throw error;const a=document.createElement('a');a.href=data.signedUrl;a.rel='noopener';a.click();},
 async signIn(){if(!supabase)throw new Error('Configure the Supabase publishable key first.');const redirectTo=returnUrl();const {error}=await supabase.auth.signInWithOAuth({provider:'google',options:{redirectTo,scopes:'openid email profile'}});if(error)throw error;},
 async signOut(){if(supabase){const {error}=await supabase.auth.signOut();if(error)throw error;}window.location.replace(returnUrl());}
};
