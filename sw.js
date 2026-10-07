var CACHE='mdstudio-v1';
var FILES=['./','index.html','manifest.webmanifest','apple-touch-icon.png','icon-192.png','icon-512.png'];
self.addEventListener('install',function(e){ e.waitUntil(caches.open(CACHE).then(function(c){ return c.addAll(FILES); })); self.skipWaiting(); });
self.addEventListener('activate',function(e){
  e.waitUntil(caches.keys().then(function(ks){ return Promise.all(ks.filter(function(k){ return k!==CACHE; }).map(function(k){ return caches.delete(k); })); }));
  self.clients.claim();
});
self.addEventListener('fetch',function(e){
  if(e.request.method!=='GET') return;
  e.respondWith(caches.match(e.request,{ignoreSearch:true}).then(function(hit){
    var net=fetch(e.request).then(function(r){
      if(r && r.ok && new URL(e.request.url).origin===location.origin){ var cp=r.clone(); caches.open(CACHE).then(function(c){ c.put(e.request,cp); }); }
      return r;
    }).catch(function(){ return hit; });
    return hit||net;
  }));
});
