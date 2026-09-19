/** Server/operator-only utility. Never import this module into the web application. */
const required=['SUPABASE_ACCESS_TOKEN','SUPABASE_PROJECT_REF','GOOGLE_CLIENT_ID','GOOGLE_CLIENT_SECRET'];
const missing=required.filter(name=>!process.env[name]?.trim());
if(missing.length){console.error('Missing operator environment variables: '+missing.join(', '));console.error('Google credentials must be real Web application OAuth credentials from Google Cloud. No defaults are supplied.');process.exit(1);}
if(!/^[a-z0-9]{20}$/.test(process.env.SUPABASE_PROJECT_REF)){console.error('SUPABASE_PROJECT_REF must be the project reference from your Supabase dashboard.');process.exit(1);}
if(!/^[a-zA-Z0-9._-]+\.apps\.googleusercontent\.com$/.test(process.env.GOOGLE_CLIENT_ID)){console.error('GOOGLE_CLIENT_ID must be the actual Google Web application client ID ending in .apps.googleusercontent.com.');process.exit(1);}
const ref=process.env.SUPABASE_PROJECT_REF;
console.log('Operator environment variables are present; credential values are not logged.');
console.log('Google Cloud authorized redirect URI: https://'+ref+'.supabase.co/auth/v1/callback');
if(!process.argv.includes('--apply')){console.log('No changes made. Run with --apply to update this Supabase project’s Google provider. Presence checks cannot establish whether Google still recognizes the client.');process.exit(0);}
const endpoint='https://api.supabase.com/v1/projects/'+ref+'/config/auth';
const headers={Authorization:'Bearer '+process.env.SUPABASE_ACCESS_TOKEN,'Content-Type':'application/json'};
const payload={external_google_enabled:true,external_google_client_id:process.env.GOOGLE_CLIENT_ID.trim(),external_google_secret:process.env.GOOGLE_CLIENT_SECRET.trim()};
// Avoid modifying unrelated sign-in providers, site URLs, or redirect entries.
const response=await fetch(endpoint,{method:'PATCH',headers,body:JSON.stringify(payload)});
if(!response.ok){console.error('Supabase rejected the provider configuration (HTTP '+response.status+'). Check project access and supplied credentials. Response omitted to avoid logging secrets.');process.exit(1);}
console.log('Supabase Google provider settings updated. Finish Google Cloud callback and Supabase application redirect settings described in docs/GOOGLE_AUTH.md.');
