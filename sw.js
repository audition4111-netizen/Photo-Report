/* 서비스 워커 — 앱으로 설치해 쓰고, 신호가 약한 현장에서도 켜지도록 한다.
 *
 * 캐시 전략을 둘로 나눈 이유:
 *   - HTML과 루트의 .js 는 자주 고친다. 캐시를 먼저 주면 배포해도 예전 화면이
 *     계속 떠서, 온라인이면 항상 새로 받는다(network-first).
 *   - libs/ 와 이미지는 크고 거의 안 바뀐다. 캐시를 먼저 주고 뒤에서 조용히
 *     갱신한다(stale-while-revalidate). 매번 받으면 모바일에서 느리다.
 *
 * Supabase 같은 외부 주소는 손대지 않는다. 캐시하면 로그인·저장이 깨진다.
 *
 * ⚠️ 파일을 고쳐 배포할 때 CACHE_VERSION 을 올려 주세요.
 *    올리면 예전 캐시가 모두 지워지고 새로 받습니다.
 */
var CACHE_VERSION = 'v13';
var CACHE = 'ddoc-' + CACHE_VERSION;

// 오프라인에서도 앱이 켜지도록 미리 받아 두는 것들
var PRECACHE = [
  './',
  './index.html',
  './search.html',
  './archive.js',
  './draft.js',
  './supabase-config.js',
  './libs/html2canvas.min.js',
  './libs/jspdf.umd.min.js',
  './libs/supabase.min.js',
  './manual-logo.gif',
  './banner.png',
  './mascot.png',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './icon-maskable-512.png',
  './apple-touch-icon.png'
];

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE).then(function (cache) {
      /* addAll 은 하나만 실패해도 전체가 실패한다. 파일 하나가 없다고 설치가
         통째로 실패하면 안 되므로 개별로 담고 실패는 넘긴다. */
      return Promise.all(PRECACHE.map(function (url) {
        return cache.add(new Request(url, { cache: 'reload' })).catch(function () {});
      }));
    }).then(function () {
      return self.skipWaiting();   // 새 버전을 기다리지 않고 바로 적용
    })
  );
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (names) {
      return Promise.all(names.map(function (name) {
        if (name !== CACHE) return caches.delete(name);
      }));
    }).then(function () {
      return self.clients.claim();
    })
  );
});

// 자주 고치는 파일 — 온라인이면 항상 새로 받는다
function isFreshFirst(url) {
  if (url.pathname.indexOf('/libs/') !== -1) return false;
  return /\.(html|js|json)$/i.test(url.pathname) || url.pathname.slice(-1) === '/';
}

function networkFirst(request) {
  return fetch(request).then(function (res) {
    if (res && res.ok) {
      var copy = res.clone();
      caches.open(CACHE).then(function (c) { c.put(request, copy); });
    }
    return res;
  }).catch(function () {
    return caches.match(request).then(function (hit) {
      if (hit) return hit;
      // 페이지 이동인데 캐시에도 없으면 시작 화면이라도 보여 준다
      if (request.mode === 'navigate') return caches.match('./index.html');
      throw new Error('offline');
    });
  });
}

function cacheFirst(request) {
  return caches.match(request).then(function (hit) {
    if (hit) {
      // 뒤에서 조용히 갱신 — 다음 실행 때 최신이 된다
      fetch(request).then(function (res) {
        if (res && res.ok) {
          caches.open(CACHE).then(function (c) { c.put(request, res); });
        }
      }).catch(function () {});
      return hit;
    }
    return fetch(request).then(function (res) {
      if (res && res.ok) {
        var copy = res.clone();
        caches.open(CACHE).then(function (c) { c.put(request, copy); });
      }
      return res;
    });
  });
}

self.addEventListener('fetch', function (event) {
  var request = event.request;
  if (request.method !== 'GET') return;

  var url;
  try { url = new URL(request.url); } catch (e) { return; }

  // 외부 주소(Supabase 등)는 그대로 통과시킨다
  if (url.origin !== self.location.origin) return;

  event.respondWith(isFreshFirst(url) ? networkFirst(request) : cacheFirst(request));
});
