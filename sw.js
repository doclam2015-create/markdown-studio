var CACHE='mdstudio-v3';
var FILES=['./','index.html','manifest.webmanifest','apple-touch-icon.png','icon-192.png','icon-512.png'];
self.addEventListener('install',function(e){ e.waitUntil(caches.open(CACHE).then(function(c){ return c.addAll(FILES); })); self.skipWaiting(); });
self.addEventListener('activate',function(e){
  e.waitUntil(caches.keys().then(function(ks){ return Promise.all(ks.filter(function(k){ return /^mdstudio-/.test(k) && k!==CACHE; }).map(function(k){ return caches.delete(k); })); }));
  self.clients.claim();
});
// Propios: caché con actualización en segundo plano. Librerías de cdn.jsdelivr.net: se guardan al primer uso (OCR y voz sin conexión después).
self.addEventListener('fetch',function(e){
  if(e.request.method!=='GET') return;
  var u=new URL(e.request.url), same=u.origin===location.origin, cdn=u.hostname==='cdn.jsdelivr.net';
  if(!same && !cdn) return;
  e.respondWith(caches.match(e.request,{ignoreSearch:same}).then(function(hit){
    if(hit && cdn) return hit;
    var net=fetch(e.request).then(function(r){
      if(r && (r.ok || r.type==='opaque')){ var cp=r.clone(); caches.open(CACHE).then(function(c){ c.put(e.request,cp); }); }
      return r;
    }).catch(function(){ return hit; });
    return hit||net;
  }));
});
