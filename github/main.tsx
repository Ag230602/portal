import React,{useEffect,useState} from 'react';
import {createRoot} from 'react-dom/client';
import Portal from '../app/portal';
import '../app/globals.css';
import {setPortalTransport} from '../lib/transport';
import {transport,supabase,configured,rpc} from './supabase';
setPortalTransport(transport);
function App(){const [ready,setReady]=useState(false);const [onboard,setOnboard]=useState(false);const [departments,setDepartments]=useState<string[]>([]);const [department,setDepartment]=useState('');const [name,setName]=useState('');const [error,setError]=useState('');
useEffect(()=>{if(!supabase){setReady(true);return;}supabase.auth.getSession().then(async({data,error})=>{if(error)throw error;if(data.session){const state=await rpc('load');if(!state.user.department&&state.user.role==='respondent'){setDepartments(state.departments);setDepartment(state.departments[0]||'');setName(state.user.name);setOnboard(true);}}}).catch(e=>setError(e.message)).finally(()=>setReady(true));},[]);
if(!configured)return <div className="loading"><h1>NAAC Point-5</h1><p>This portal is waiting for its Supabase connection settings.</p><p>Set the repository variable VITE_SUPABASE_PUBLISHABLE_KEY and rebuild.</p></div>;
if(!ready)return <div className="loading"><h2>Opening your workspace…</h2></div>;
if(onboard)return <div className="loading"><form className="card admin-card" style={{maxWidth:460,width:'90%'}} onSubmit={async e=>{e.preventDefault();try{await rpc('onboard',{department,name});setOnboard(false);}catch(e){setError((e as Error).message);}}}><p className="eyebrow">WELCOME TO NAAC POINT-5</p><h1>Set up your profile</h1><p>You will join as a respondent. You can view and edit your own records. Coordinators receive their permissions separately.</p><label>Name<input required value={name} onChange={e=>setName(e.target.value)}/></label><label>Department<select required value={department} onChange={e=>setDepartment(e.target.value)}>{departments.map(d=><option key={d}>{d}</option>)}</select></label>{error&&<p role="alert">{error}</p>}<button className="primary">Continue to portal</button></form></div>;
if(error)return <div className="loading"><h2>Unable to open your workspace</h2><p role="alert">{error}</p><button className="secondary" onClick={()=>window.location.reload()}>Try again</button><button onClick={()=>transport.signOut()}>Sign out</button></div>;
return <Portal/>;}
createRoot(document.getElementById('root')!).render(<React.StrictMode><App/></React.StrictMode>);
