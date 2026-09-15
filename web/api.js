import {config} from './config.js';
export const connected = Boolean(config.supabaseUrl && config.supabaseKey);
const storageKey = 'genz-session';
export function session() {try {return JSON.parse(localStorage.getItem(storageKey) || 'null');} catch {return null;}}
let refreshPromise;
async function token() {
  let s = session();
  if (!s) throw new Error('Masuk terlebih dahulu.');
  if ((s.expires_at || 0) * 1000 < Date.now() + 60000) {
    if (!refreshPromise) refreshPromise = auth('token?grant_type=refresh_token', {refresh_token:s.refresh_token}).finally(()=>{refreshPromise=null;});
    s = await refreshPromise;
  }
  return s.access_token;
}
async function auth(route, body) {
  const r = await fetch(`${config.supabaseUrl}/auth/v1/${route}`, {method:'POST',headers:{apikey:config.supabaseKey,'Content-Type':'application/json'},body:JSON.stringify(body)});
  const d = await r.json();
  if (!r.ok) throw new Error(d.msg || d.error_description || 'Login gagal.');
  localStorage.setItem(storageKey, JSON.stringify(d));
  return d;
}
export const login = (email,password) => auth('token?grant_type=password',{email,password});
export async function logout() {
  const s=session(); localStorage.removeItem(storageKey);
  if(s) await fetch(`${config.supabaseUrl}/auth/v1/logout`,{method:'POST',headers:{apikey:config.supabaseKey,Authorization:`Bearer ${s.access_token}`}}).catch(()=>{});
}
export async function api(path, options={}) {
  const r=await fetch(`${config.supabaseUrl}/${path}`,{...options,headers:{apikey:config.supabaseKey,Authorization:`Bearer ${await token()}`,'Content-Type':'application/json',...options.headers}});
  if(!r.ok) {const d=await r.json().catch(()=>({}));throw new Error(d.message || d.error || `Request gagal (${r.status}).`);}
  return r.status===204 || r.headers.get('content-length')==='0' ? null : r.json();
}
export const rows=(table)=>api(`rest/v1/${table}?select=*&order=created_at.desc&limit=100`);
export const insert=(table,data)=>api(`rest/v1/${table}`,{method:'POST',headers:{Prefer:'return=representation'},body:JSON.stringify(data)});
export const patch=(table,id,data)=>api(`rest/v1/${table}?id=eq.${encodeURIComponent(id)}`,{method:'PATCH',headers:{Prefer:'return=representation'},body:JSON.stringify(data)});
export async function upload(file) {
  const path=`${session().user.id}/${crypto.randomUUID()}.mp4`;
  const r=await fetch(`${config.supabaseUrl}/storage/v1/object/gameplay/${path}`,{method:'POST',headers:{apikey:config.supabaseKey,Authorization:`Bearer ${await token()}`,'Content-Type':'video/mp4'},body:file});
  if(!r.ok) throw new Error('Upload gagal. Pastikan bucket gameplay sudah dibuat dan file maksimal 50 MB.');
  return path;
}
export async function videoURL(path) {
  const d=await api(`storage/v1/object/sign/renders/${path}`,{method:'POST',body:JSON.stringify({expiresIn:3600})});
  return `${config.supabaseUrl}/storage/v1${d.signedURL}`;
}
