const V='djops-shell-v11-static-v2-stage1-proposed';
const SHELL=['./','index.html','app.js','crypto.js','feed-v2-loader.mjs','style.css','config.js','manifest.webmanifest','icon-192.png','icon-512.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(V).then(c=>Promise.all(SHELL.map(u=>fetch(u,{cache:'reload'}).then(r=>c.put(u,r))))));self.skipWaiting();});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==V).map(x=>caches.delete(x)))));self.clients.claim();});
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.method!=='GET'||u.origin!==location.origin)return; // never cache writes or GitHub API data
 if(u.searchParams.has('u')){e.respondWith(fetch(e.request,{cache:'no-store'}));return;}
 if((u.pathname.endsWith('/feed.json')||u.pathname.endsWith('/feed-v2.json'))){e.respondWith(fetch(e.request,{cache:'no-store'}));return;}
 e.respondWith(fetch(e.request,{cache:'no-cache'}).then(r=>{const c=r.clone();caches.open(V).then(x=>x.put(e.request,c));return r;}).catch(async()=>{
 const c=await caches.open(V),exact=await c.match(e.request);if(exact)return exact;
 // Shell is one reviewed cache version. Query-string imports must boot offline too.
 // Never ignore search for data or arbitrary resources.
 if(SHELL.some(x=>new URL(x,self.location.href).pathname===u.pathname))return c.match(e.request,{ignoreSearch:true});
 return undefined;
 }));});
