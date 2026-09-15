import {mkdir, cp, writeFile} from 'node:fs/promises';
await mkdir('dist', {recursive: true});
await cp('web', 'dist', {recursive: true});
// Explicit allowlist: never copy backend credentials into browser assets.
await writeFile('dist/config.js', `export const config = ${JSON.stringify({
  supabaseUrl: process.env.PUBLIC_SUPABASE_URL || '',
  supabaseKey: process.env.PUBLIC_SUPABASE_ANON_KEY || ''
})};\n`);
console.log('Built static dashboard in dist/');
