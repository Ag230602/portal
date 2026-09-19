export type PortalTransport = {
 request:(url:string,body?:unknown,method?:string)=>Promise<any>;
 upload:(data:FormData)=>Promise<any>;
 download:(id:string)=>Promise<void>;
 signIn:()=>Promise<void>;
 signOut:()=>Promise<void>;
};
let active:PortalTransport|null=null;
export function setPortalTransport(transport:PortalTransport){active=transport;}
export function isGooglePortal(){return active!==null;}
export async function portalRequest(url:string,body?:unknown,method='POST'){
 if(active)return active.request(url,body,method);
 const r=await fetch(url,body?{method,headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}:undefined);
 const data=await r.json();if(!r.ok)throw new Error(data.error||'Request failed');return data;
}
export async function uploadEvidence(data:FormData){if(active)return active.upload(data);const r=await fetch('/api/evidence',{method:'POST',body:data});const d=await r.json();if(!r.ok)throw new Error(d.error);return d;}
export async function downloadEvidence(id:string){if(active)return active.download(id);window.location.assign('/api/evidence?id='+encodeURIComponent(id));}
export async function portalSignIn(){if(active)return active.signIn();window.location.assign('/signin-with-chatgpt?return_to=%2F');}
export async function portalSignOut(){if(active)return active.signOut();window.location.assign('/signout-with-chatgpt?return_to=%2F');}
