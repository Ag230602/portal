import React,{useEffect,useState} from 'react';
import {createRoot} from 'react-dom/client';
import {GraduationCap,ShieldAlert,ArrowRight} from 'lucide-react';
import Portal from '../app/portal';
import '../app/globals.css';
import {setPortalTransport} from '../lib/transport';
import {transport,supabase,configured,configurationErrors,rpc,appBase} from './supabase';
import {authProblem,oauthErrorFromUrl,cleanAuthUrl,dashboardPath,loadAuthenticatedProfile,type AuthProblem} from './auth';

const landingError=oauthErrorFromUrl(window.location.href);
if(landingError)window.history.replaceState({},'',cleanAuthUrl(window.location.href));
// Supabase's singleton client completes PKCE initialization before getSession resolves.
// Reuse one bootstrap promise so React StrictMode never exchanges a code twice.
let boot:Promise<any>|undefined;
function bootstrap(){return boot??=(async()=>{
 if(!supabase)return null;
 const {data,error}=await supabase.auth.getSession();if(error)throw error;
 if(!data.session)return null;
 return loadAuthenticatedProfile(supabase,()=>rpc('load'));
})();}
function App(){
 const [ready,setReady]=useState(false);const [problem,setProblem]=useState<AuthProblem|null>(landingError);const [saving,setSaving]=useState(false);const [portalKey,setPortalKey]=useState(0);
 const routeToProfile=(state:any)=>{window.history.replaceState({},'',dashboardPath(state.user.role,appBase));};
 useEffect(()=>{
  let active=true;
  setPortalTransport({...transport,async signIn(){setProblem(null);try{await transport.signIn();}catch(e){setProblem(authProblem(e));}},async signOut(){try{await transport.signOut();}catch(e){setProblem(authProblem(e));}}});
  if(landingError){setReady(true);return ()=>{active=false;};}
  bootstrap().then(state=>{if(!active)return;if(state)routeToProfile(state);else window.history.replaceState({},'',appBase);}).catch(e=>{if(active)setProblem(authProblem(e));}).finally(()=>{if(active){window.history.replaceState({},'',cleanAuthUrl(window.location.href));setReady(true);}});
  // A sign-out from another tab must not leave the previous user's data visible.
  const listener=supabase?.auth.onAuthStateChange(event=>{if(event==='SIGNED_OUT'&&active){setPortalKey(k=>k+1);window.history.replaceState({},'',appBase);}});
  return()=>{active=false;listener?.data.subscription.unsubscribe();};
 },[]);
 if(!configured)return <div className="auth-page"><section className="auth-card"><GraduationCap size={36}/><p className="eyebrow">NAAC POINT-5 PORTAL</p><h1>Authentication setup required</h1><p>The developer needs to provide these build-time settings before users can sign in:</p><ul>{configurationErrors.map(k=><li key={k}><code>{k}</code></li>)}</ul><p>Set them in <code>github/.env.local</code> for development or GitHub Actions repository variables for deployment, then rebuild.</p><p>Google’s Client ID and Client Secret belong in Supabase’s Google provider settings. They must never be placed in browser environment variables.</p></section></div>;
 if(!ready)return <div className="loading" role="status"><GraduationCap size={38}/><h2>Signing you in securely</h2><p>Verifying your account and loading your portal permissions…</p></div>;
 if(problem)return <div className="auth-page"><section className="auth-card" role="alert"><ShieldAlert size={35}/><p className="eyebrow">NAAC POINT-5 · SECURE SIGN-IN</p><h1>{problem.title}</h1><p>{problem.message}</p><div className="notice">{problem.action}</div><div className="button-row"><button className="primary" disabled={saving} onClick={async()=>{setSaving(true);try{await transport.signIn();}catch(e){setProblem(authProblem(e));}finally{setSaving(false);}}}>Try Google sign-in again <ArrowRight size={16}/></button><button className="secondary" onClick={()=>{setProblem(null);setReady(true);}}>Back to portal</button></div><small>Reference: {problem.code}</small></section></div>;
 return <Portal key={portalKey}/>;
}
// Register before Portal's first render; all NAAC requests continue through the existing adapter.
setPortalTransport(transport);
createRoot(document.getElementById('root')!).render(<React.StrictMode><App/></React.StrictMode>);
