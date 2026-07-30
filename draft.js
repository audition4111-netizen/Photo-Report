/* 임시저장 — 작성 중인 문서를 이 브라우저에 보관한다.
 *
 * localStorage 대신 IndexedDB를 쓰는 이유: 사진 30장을 data URL로 담으면 수 MB가
 * 되는데 localStorage 한도는 보통 5~10MB라 바로 넘친다. IndexedDB는 한도가 훨씬
 * 크고 큰 문자열도 그대로 저장할 수 있다.
 *
 * 서버로 올리지 않으므로 다른 기기·다른 브라우저에서는 보이지 않는다.
 */
(function (global) {
  'use strict';

  var DB_NAME = 'photo-report-draft';
  var STORE = 'drafts';
  var VERSION = 1;
  var KEY_PAYLOAD = 'payload';   // 사진까지 포함한 전체 (수 MB)
  var KEY_META = 'meta';         // 안내창에 쓸 요약 (작아서 빨리 읽힌다)

  function available() {
    try { return !!global.indexedDB; } catch (e) { return false; }
  }

  function openDb() {
    return new Promise(function (resolve, reject) {
      if (!available()) {
        reject(new Error('이 브라우저에서는 임시저장을 사용할 수 없습니다.'));
        return;
      }
      var req = global.indexedDB.open(DB_NAME, VERSION);
      req.onupgradeneeded = function () {
        var db = req.result;
        if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE);
      };
      req.onsuccess = function () { resolve(req.result); };
      req.onerror = function () { reject(req.error || new Error('임시저장 저장소를 열지 못했습니다.')); };
      // 다른 탭이 예전 버전을 붙들고 있으면 upgrade가 멈춘다
      req.onblocked = function () { reject(new Error('다른 탭에서 이 앱이 열려 있습니다. 닫고 다시 시도해 주세요.')); };
    });
  }

  /* 읽기/쓰기 한 번을 트랜잭션으로 감싼다. 요청 결과는 oncomplete 시점에 이미
     채워져 있으므로, 값을 담아 두었다가 완료될 때 넘긴다. */
  function withStore(mode, fn) {
    return openDb().then(function (db) {
      return new Promise(function (resolve, reject) {
        var t, box;
        try {
          t = db.transaction(STORE, mode);
        } catch (e) {
          db.close();
          reject(e);
          return;
        }
        box = fn(t.objectStore(STORE));
        t.oncomplete = function () {
          db.close();
          resolve(box && typeof box.result !== 'undefined' ? box.result : null);
        };
        t.onerror = t.onabort = function () {
          db.close();
          reject(t.error || new Error('임시저장 처리에 실패했습니다.'));
        };
      });
    });
  }

  /* payload 는 앱이 만든 평범한 객체. meta 는 그중 안내창에 보여 줄 값만. */
  function save(payload, meta) {
    return withStore('readwrite', function (store) {
      store.put(payload, KEY_PAYLOAD);
      store.put(meta, KEY_META);
    }).catch(function (err) {
      // 용량 초과는 사진이 너무 많을 때 생긴다 — 원인을 알려 준다
      var name = err && err.name;
      if (name === 'QuotaExceededError') {
        throw new Error('저장 공간이 부족해 임시저장하지 못했습니다. 사진을 줄여 주세요.');
      }
      throw err;
    });
  }

  function peek() {
    return withStore('readonly', function (store) {
      return store.get(KEY_META);
    }).catch(function () {
      return null;   // 임시저장을 못 읽는다고 앱이 멈추면 안 된다
    });
  }

  function load() {
    return withStore('readonly', function (store) {
      return store.get(KEY_PAYLOAD);
    });
  }

  function clear() {
    return withStore('readwrite', function (store) {
      store.delete(KEY_PAYLOAD);
      store.delete(KEY_META);
    }).catch(function () { /* 지우기 실패는 조용히 넘긴다 */ });
  }

  // "2026. 7. 30. 오후 3:42" 처럼 사람이 읽는 형태로
  function formatSavedAt(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    function p(n) { return (n < 10 ? '0' : '') + n; }
    return d.getFullYear() + '.' + (d.getMonth() + 1) + '.' + d.getDate()
      + '. ' + p(d.getHours()) + ':' + p(d.getMinutes());
  }

  global.Draft = {
    isEnabled: available,
    save: save,
    peek: peek,
    load: load,
    clear: clear,
    formatSavedAt: formatSavedAt
  };
})(window);
