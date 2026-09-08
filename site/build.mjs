import { mkdir, copyFile, cp } from 'node:fs/promises';
// Explicit allowlist: source tests, host configuration and local files never ship.
await mkdir(new URL('./public/',import.meta.url),{recursive:true});
for (const name of ['index.html','privacy.html','style.css','app.mjs','report.mjs']) await copyFile(new URL(name,import.meta.url),new URL(`public/${name}`,import.meta.url));
await cp(new URL('assets/',import.meta.url),new URL('public/assets/',import.meta.url),{recursive:true});
console.log('Built static Workbench site in site/public');
