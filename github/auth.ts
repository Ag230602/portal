/** Pure authentication helpers. Never accept roles or return URLs from URL parameters. */
export function validateAuthConfig(url:string|undefined,key:string|undefined):string[]{
 const missing:string[]=[];
 if(!url?.trim())missing.push('VITE_SUPABASE_URL');
 else {try{const parsed=new URL(url);if(parsed.username||parsed.password||parsed.pathname!=='/'||parsed.search||parsed.hash||!(parsed.protocol==='https:'||(parsed.protocol==='http:'&&['localhost','127.0.0.1','[::1]'].includes(parsed.hostname))))missing.push('VITE_SUPABASE_URL (must be an HTTPS project origin, or localhost for development)');}catch{missing.push('VITE_SUPABASE_URL (must be a valid project URL)');}}
 if(!key?.trim())missing.push('VITE_SUPABASE_PUBLISHABLE_KEY');
 else if(key.startsWith('sb_secret_'))missing.push('VITE_SUPABASE_PUBLISHABLE_KEY (a secret key cannot be used in the browser)');
 else if(!key.startsWith('sb_publishable_')){
  try{const claims=JSON.parse(atob(key.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));if(claims.role!=='anon')missing.push('VITE_SUPABASE_PUBLISHABLE_KEY (use a publishable key or legacy anon key, never service_role)');}catch{missing.push('VITE_SUPABASE_PUBLISHABLE_KEY (use a valid publishable key or legacy anon key)');}
 }
 return missing;
}
export function appBasePath(base:string){if(!base.startsWith('/')||base.startsWith('//')||base.includes('..')||base.includes('?')||base.includes('#')||base.includes('\\'))throw new Error('The application base path is invalid.');return base.replace(/\/+$/,'')+'/';}
export function applicationUrl(origin:string,base='/'){return new URL(appBasePath(base),origin).href;}
export function dashboardPath(role:string,base='/'){
 const routes:Record<string,string>={respondent:'student/dashboard',student:'student/dashboard',coordinator:'coordinator/dashboard',admin:'admin/dashboard'};
 if(!Object.hasOwn(routes,role))throw new Error('Your account does not have a recognized portal role. Contact the NAAC administrator.');
 return appBasePath(base)+routes[role];
}
export type AuthProblem={title:string;message:string;action:string;code:string};
export function authProblem(value:unknown):AuthProblem{
 const e=value as {code?:string;message?:string};const message=typeof value==='string'?value:e?.message||'';const code=e?.code||'';const text=(code+' '+message).toLowerCase();
 if(/invalid_client|oauth client was not found|unauthorized_client/.test(text))return {title:'Google sign-in needs configuration',message:'Google could not recognize the portal’s OAuth client. Your records have not been changed.',action:'The administrator must verify the Web application Client ID and matching Client Secret in Supabase → Authentication → Sign In / Providers → Google.',code:'invalid_client'};
 if(/access_denied|cancelled|canceled/.test(text))return {title:'Sign-in was not completed',message:'Google sign-in was cancelled or access was declined.',action:'Try again and choose the Google account you want to use for this portal.',code:'access_denied'};
 if(/provider.*(disabled|not enabled)|unsupported provider|provider_disabled/.test(text))return {title:'Google sign-in is not enabled',message:'This portal’s Google authentication provider is not configured yet.',action:'The administrator must enable Google in Supabase Authentication and provide a valid Client ID and Client Secret.',code:'provider_disabled'};
 if(/code.verifier|pkce|flow_state|bad_code_verifier|otp_expired|invalid_grant|code.*expired/.test(text))return {title:'Your sign-in link has expired',message:'The sign-in session could not be completed.',action:'Start again in this browser and finish Google sign-in in the same browser.',code:'session_expired'};
 if(/redirect_uri_mismatch|redirect.*(invalid|not allowed)/.test(text))return {title:'The sign-in return address needs configuration',message:'Google or Supabase did not accept this portal’s return address.',action:'The administrator must check the Supabase callback in Google Cloud and this application’s URL in the Supabase redirect allow list.',code:'redirect_mismatch'};
 if(/failed to fetch|network|timeout/.test(text))return {title:'Unable to reach the sign-in service',message:'A connection problem prevented sign-in.',action:'Check your connection and try again.',code:'network_error'};
 return {title:'Unable to open your workspace',message:'We could not complete authentication or load your portal permissions.',action:'Try signing in again. If the problem continues, contact your NAAC administrator.',code:'authentication_failed'};
}
export function oauthErrorFromUrl(href:string):AuthProblem|null{
 const url=new URL(href);const query=url.searchParams;const hash=new URLSearchParams(url.hash.slice(1));
 for(const p of [query,hash])if(p.has('error')||p.has('error_code')||p.has('error_description'))return authProblem({code:p.get('error_code')||p.get('error')||'',message:p.get('error_description')||''});return null;
}
export function cleanAuthUrl(href:string){const url=new URL(href);for(const key of ['code','error','error_code','error_description','error_uri'])url.searchParams.delete(key);const hash=new URLSearchParams(url.hash.slice(1));if(['access_token','refresh_token','error','error_code','error_description'].some(k=>hash.has(k)))url.hash='';return url.pathname+url.search+url.hash;}
/** Reads the authoritative profile before deciding the route; UI roles cannot grant access. */
export async function loadAuthenticatedProfile(client:{auth:{getUser:()=>Promise<any>}},load:()=>Promise<any>){
 const {data,error}=await client.auth.getUser();if(error)throw error;if(!data?.user)throw new Error('The signed-in user could not be verified.');
 const state=await load();dashboardPath(state.user?.role);return state;
}
