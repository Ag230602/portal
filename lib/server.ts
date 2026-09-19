import { env } from 'cloudflare:workers';
import { initialDepartments, years, type Entry, type Evidence } from './fields';
// Bindings are supplied by Sites and Cloudflare, never by browser input.
export const bindings=env as unknown as {DB:any;EVIDENCE:any;ADMIN_EMAIL?:string;OPENAI_API_KEY?:string;OPENAI_MODEL?:string};
export const db=()=>bindings.DB;
export type User={email:string;name:string;role:string;department:string};
export const now=()=>new Date().toISOString();
export const id=()=>crypto.randomUUID();
export class HttpError extends Error {constructor(message:string,public status=400){super(message);}}
export async function audit(user:User,action:string,entityId:string){return db().prepare('INSERT INTO audit_logs VALUES (?,?,?,?,?)').bind(id(),action,entityId,now(),user.email).run();}
export async function identity(request:Request):Promise<User>{
 const email=request.headers.get('oai-authenticated-user-email')?.toLowerCase().trim();
 if(!email)throw new HttpError('Sign in to access the portal.',401);
 const user=await db().prepare('SELECT * FROM users WHERE email = ?').bind(email).first();
 if(user)return user;
 if(bindings.ADMIN_EMAIL?.toLowerCase()===email){const t=now();await db().prepare('INSERT OR IGNORE INTO users VALUES (?,?,?,?,?,?)').bind(email,email,'admin','',t,t).run();return {email,name:email,role:'admin',department:''};}
 throw new HttpError('Your account has not been authorized. Ask the administrator to add your email.',403);
}
export function guardOrigin(req:Request){const origin=req.headers.get('origin');if(origin&&origin!==new URL(req.url).origin)throw new HttpError('Cross-origin request rejected.',403);}
export function canRead(u:User,e:Entry){return u.role==='admin'||(u.role==='coordinator'&&u.department===e.department)||(u.role==='respondent'&&u.email===e.createdBy);}
export function canEdit(u:User,e:Entry){return canRead(u,e)&&['Draft','Returned'].includes(e.status)&&(u.role==='admin'||u.email===e.createdBy);}
export function canReview(u:User,e:Entry){return u.role==='admin'||u.role==='coordinator'&&u.department===e.department;}
export function requireAdmin(u:User){if(u.role!=='admin')throw new HttpError('Administrator access required.',403);}
export async function records(u:User):Promise<Entry[]>{const q=u.role==='admin'?'SELECT payload FROM submissions ORDER BY updated_at DESC':u.role==='coordinator'?'SELECT payload FROM submissions WHERE department = ? ORDER BY updated_at DESC':'SELECT payload FROM submissions WHERE created_by = ? ORDER BY updated_at DESC';const stmt=db().prepare(q);const r=await (u.role==='admin'?stmt:stmt.bind(u.role==='coordinator'?u.department:u.email)).all();return r.results.map((r:any)=>JSON.parse(r.payload));}
export async function record(u:User,id:string){const row=await db().prepare('SELECT payload FROM submissions WHERE id = ?').bind(id).first();if(!row)throw new HttpError('Record not found.',404);const e=JSON.parse(row.payload) as Entry;if(!canRead(u,e))throw new HttpError('Access denied.',403);return e;}
export async function evidence(u:User):Promise<Evidence[]>{const accessible=new Set((await records(u)).map(e=>e.id));const rows=await db().prepare('SELECT payload FROM evidence_documents').all();return rows.results.map((r:any)=>JSON.parse(r.payload)).filter((e:Evidence)=>accessible.has(e.entryId));}
export async function setup(){const t=now();await db().batch([...initialDepartments.map(d=>db().prepare('INSERT OR IGNORE INTO departments VALUES (?,?)').bind(d,t)),...years.map(y=>db().prepare('INSERT OR IGNORE INTO academic_years VALUES (?)').bind(y))]);}
export function failure(e:unknown){console.error(e instanceof Error?e.message:'Request failed');return Response.json({error:e instanceof HttpError?e.message:'The request could not be completed. Please try again.'},{status:e instanceof HttpError?e.status:500});}
export const json=(data:unknown)=>Response.json(data,{headers:{'Cache-Control':'no-store'}});
