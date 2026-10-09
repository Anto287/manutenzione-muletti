const CACHE_PREFIX='liftcare-shell-';
const CACHE=CACHE_PREFIX+'__BUILD_VERSION__';
const FILES=/*__PRECACHE__*/[];
const ROOT=new URL('./',self.location.href);
const urls=FILES.map(file=>new URL(file,ROOT).href);
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(urls))));
self.addEventListener('activate',event=>event.waitUntil((async()=>{
  for(const key of await caches.keys())if(key.startsWith(CACHE_PREFIX)&&key!==CACHE)await caches.delete(key);
  await self.clients.claim();
})()));
self.addEventListener('message',event=>{if(event.data?.type==='SKIP_WAITING')self.skipWaiting()});
self.addEventListener('fetch',event=>{
  const url=new URL(event.request.url);
  // Only the public shell is cached. Auth, API responses and private photos bypass this worker.
  if(event.request.method!=='GET'||url.origin!==ROOT.origin||!url.pathname.startsWith(ROOT.pathname))return;
  const clean=new URL(url.pathname,url.origin).href;
  if(event.request.mode==='navigate'){
    event.respondWith(fetch(event.request).catch(async()=>
      (await caches.open(CACHE)).match(new URL('index.html',ROOT).href).then(response=>response||Response.error())));
  }else if(urls.includes(clean)){
    event.respondWith((async()=>{
      const cache=await caches.open(CACHE);
      return (await cache.match(clean))||fetch(event.request);
    })());
  }
});
