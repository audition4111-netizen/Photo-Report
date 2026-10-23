/* 문서 보관/조회 + 개선요청 게시판 공용 모듈 — 작성 앱(index.html)과 조회
   페이지(search.html)가 함께 사용. Supabase가 설정되지 않았거나 오프라인이면
   isEnabled()가 false를 반환하고, 앱은 저장 기능 없이 기존대로 동작합니다.

   ⚠️ 일반 사용자용 로그인/회원가입은 없앴습니다. 매뉴얼·고장 보고서의 작성자는
   화면 입력칸에서 직접 받고(로그인과 무관), 개선요청은 항상 "익명"으로
   저장됩니다. signIn()은 관리자 전용 숨은 입구(길게 누르기)에서만 쓰이며,
   관리자로 로그인하면 개선요청 답변·완료 표시 같은 관리자 전용 기능이 보입니다
   — 실제 차단은 db/schema.sql의 feedback_guard_admin_fields 트리거가
   담당합니다. db/schema-main-no-login.sql 을 먼저 실행해야 로그인 없이도
   저장·조회가 됩니다. */
(function (global) {
  'use strict';

  var BUCKET = 'documents';
  // 수정용 원본 꾸러미. documents 버킷을 통째로 내려받는 전집 다운로드에
  // JSON 이 섞이지 않도록 버킷을 따로 둔다. db/edit-source.sql 참고.
  var SOURCE_BUCKET = 'document-sources';
  var FEEDBACK_BUCKET = 'feedback-photos';
  var ADMIN_EMAIL = 'audition411@kdhc.co.kr';
  var client = null;

  function config() {
    return global.SUPABASE_CONFIG || {};
  }

  function isEnabled() {
    var c = config();
    return !!(c.url && c.anonKey && global.supabase && global.supabase.createClient);
  }

  function getClient() {
    if (!isEnabled()) return null;
    if (!client) {
      client = global.supabase.createClient(config().url, config().anonKey);
    }
    return client;
  }

  // ---- 관리자 로그인(숨은 입구 전용) ------------------------------------------
  // 일반 사용자는 이 기능을 화면에서 볼 수 없다. 회원가입은 더 이상 지원하지
  // 않는다(관리자 계정은 이미 만들어져 있음).

  function currentUser() {
    var c = getClient();
    if (!c) return Promise.resolve(null);
    return c.auth.getUser().then(function (res) {
      return (res && res.data && res.data.user) || null;
    }).catch(function () { return null; });
  }

  function signIn(email, password) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    return c.auth.signInWithPassword({ email: email, password: password }).then(function (res) {
      if (res.error) throw res.error;
      return res.data.user;
    });
  }

  function signOut() {
    var c = getClient();
    if (!c) return Promise.resolve();
    return c.auth.signOut();
  }

  function onAuthChange(handler) {
    var c = getClient();
    if (!c) return;
    c.auth.onAuthStateChange(function (_event, session) {
      handler((session && session.user) || null);
    });
  }

  // 개선요청 답변·완료 표시, 매뉴얼/고장 보고서 삭제 버튼을 보여줄지 판단하는
  // 용도. 실제 차단은 서버 RLS·트리거가 담당한다.
  function isAdmin(user) {
    if (!user) return false;
    return (user.email || '').toLowerCase() === ADMIN_EMAIL.toLowerCase();
  }

  // ---- 저장 -----------------------------------------------------------------

  var MAX_UPLOAD_ATTEMPTS = 50;

  /* Supabase Storage는 오브젝트 키에 ASCII 외 문자(한글 포함)를 허용하지 않는다
     (서버가 \w — 즉 [A-Za-z0-9_] — 와 일부 기호만 통과시킨다). 그래서 한글은
     로마자(발음)로 바꿔 저장 경로에 넣는다. 화면에 보이는 한글 원문은 documents
     테이블의 branch·title·file_name 컬럼에 그대로 저장되므로 조회 화면은 안 바뀐다. */
  var HANGUL_BASE = 0xAC00, HANGUL_LAST = 0xD7A3;
  var CHO = ['g', 'kk', 'n', 'd', 'tt', 'r', 'm', 'b', 'pp', 's', 'ss', '', 'j', 'jj', 'ch', 'k', 't', 'p', 'h'];
  var JUNG = ['a', 'ae', 'ya', 'yae', 'eo', 'e', 'yeo', 'ye', 'o', 'wa', 'wae', 'oe', 'yo', 'u', 'wo', 'we', 'wi', 'yu', 'eu', 'ui', 'i'];
  var JONG = ['', 'k', 'k', 'k', 'n', 'n', 'n', 't', 'l', 'k', 'm', 'l', 'l', 'l', 'p', 'l', 'm', 'p', 'p', 't', 't', 'ng', 'j', 'ch', 'k', 't', 'p', 'h'];

  // 완성형 한글 음절 한 글자를 로마자로 (국립국어원 로마자 표기법 간이 버전)
  function romanizeHangulSyllable(ch) {
    var code = ch.charCodeAt(0) - HANGUL_BASE;
    var jong = code % 28;
    var jung = ((code - jong) / 28) % 21;
    var cho = ((code - jong) / 28 - jung) / 21;
    return CHO[cho] + JUNG[jung] + JONG[jong];
  }

  // Supabase Storage 키로 안전한 문자(영문·숫자·밑줄, 공백, 일부 기호)만 남긴다
  var SAFE_KEY_CHAR = /[\w\-.'() &$@=;:+,]/;

  // pdf_path에 그대로 들어가는 경로용 새니타이즈. 로컬 다운로드 파일명에 쓰는
  // sanitizeFileName()(index.html, '_'로 치환)과는 별개다.
  function sanitizeForStoragePath(name) {
    var s = String(name || '')
      .replace(/[\\/?#%:*"<>|]/g, '')   // OS에서도 꺼리는 문자 — 안전을 위해 우선 제거
      .replace(/[\x00-\x1f\x7f]/g, '');

    var out = '';
    for (var i = 0; i < s.length; i++) {
      var ch = s[i];
      var code = ch.charCodeAt(0);
      if (code >= HANGUL_BASE && code <= HANGUL_LAST) {
        out += romanizeHangulSyllable(ch);
      } else if (SAFE_KEY_CHAR.test(ch)) {
        out += ch;   // 그 외 한글 자모·한자·이모지 등은 버린다(Storage가 거부하므로)
      }
    }
    return out.trim();
  }

  /* documents/{지사}/{연도}/{분야}/{manual|fault}/({매뉴얼종류}/){제목}.pdf
     지사·분야·매뉴얼종류·제목은 로마자로 변환됨. 매뉴얼만 종류별 폴더가 한 단계
     더 있고, 고장 보고서는 분야 아래 바로 fault 폴더로 들어간다. */
  function storagePath(docType, branch, field, manualType, title, year) {
    var safeBranch = sanitizeForStoragePath(branch) || 'unknown';
    var safeField = sanitizeForStoragePath(field) || 'unknown';
    var safeTitle = sanitizeForStoragePath(title) || 'document';
    var y = year || new Date().getFullYear();

    var parts = [safeBranch, y, safeField, docType];
    if (docType === 'manual') parts.push(sanitizeForStoragePath(manualType) || 'unknown');
    parts.push(safeTitle + '.pdf');
    return parts.join('/');
  }

  // Supabase Storage가 upsert:false에서 기존 경로와 충돌할 때 주는 오류 판별.
  // SDK 버전에 따라 문구가 다를 수 있어 메시지와 상태코드를 함께 본다.
  function isDuplicatePathError(err) {
    var msg = ((err && (err.message || err.error)) || '') + '';
    var status = err && (err.statusCode || err.status);
    return /already exists|duplicate/i.test(msg) || status === 409 || status === '409';
  }

  // 확장자 앞에 (n)을 끼워 넣는다: "제목.pdf" -> "제목(2).pdf"
  function withSuffix(path, n) {
    var dot = path.lastIndexOf('.');
    if (dot === -1) return path + '(' + n + ')';
    return path.slice(0, dot) + '(' + n + ')' + path.slice(dot);
  }

  // 동명 파일이 있으면 (2), (3)... 순으로 자동 증가시켜 재시도한다.
  // 조용히 처리해야 하므로(사용자에게 팝업 노출 금지) 여기서는 어떤 UI도 건드리지 않는다.
  function uploadWithRetry(c, bucket, basePath, blob, contentType) {
    function attempt(n) {
      var path = n === 1 ? basePath : withSuffix(basePath, n);
      return c.storage.from(bucket)
        .upload(path, blob, { contentType: contentType, upsert: false })
        .then(function (up) {
          if (up.error) {
            if (isDuplicatePathError(up.error) && n < MAX_UPLOAD_ATTEMPTS) return attempt(n + 1);
            throw up.error;
          }
          return path;
        });
    }
    return attempt(1);
  }

  // ---- 수정용 원본 꾸러미 ---------------------------------------------------

  /* 원본 꾸러미 = 작성 화면을 그대로 되살릴 수 있는 값 전부(입력값·사진·설명).
     PDF 는 눌러 찍은 결과물이라 되돌릴 수 없어서, 수정하려면 이것이 따로 있어야
     한다. 파일 이름을 문서 id 로 정해 두면 제목을 바꿔도 자리가 그대로라,
     덮어쓸 때 예전 파일이 고아로 남지 않는다. */
  function sourcePathFor(docId) {
    return docId + '.json.gz';
  }

  function newDocId() {
    if (global.crypto && global.crypto.randomUUID) return global.crypto.randomUUID();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (ch) {
      var r = Math.random() * 16 | 0;
      return (ch === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
    });
  }

  /* 사진이 base64 로 들어 있어 꾸러미가 수 MB 가 된다. gzip 으로 올리면 base64
     때문에 늘어난 만큼을 대부분 되돌려받는다. 압축을 못 쓰는 브라우저에서는
     그냥 평문으로 올린다 — 읽을 때 내용을 보고 판단하므로 섞여 있어도 된다. */
  function toSourceBlob(source) {
    var plain = new Blob([JSON.stringify(source)], { type: 'application/json' });
    if (!global.CompressionStream || !plain.stream) return Promise.resolve(plain);
    try {
      var stream = plain.stream().pipeThrough(new global.CompressionStream('gzip'));
      return new Response(stream).blob().then(function (gz) {
        return new Blob([gz], { type: 'application/gzip' });
      }, function () { return plain; });
    } catch (e) {
      return Promise.resolve(plain);
    }
  }

  function fromSourceBlob(blob) {
    // gzip 파일은 1f 8b 로 시작한다. 파일 이름이 아니라 내용으로 판단한다.
    return blob.slice(0, 2).arrayBuffer().then(function (head) {
      var b = new Uint8Array(head);
      var gzipped = b.length >= 2 && b[0] === 0x1f && b[1] === 0x8b;
      if (!gzipped) return blob.text().then(function (t) { return JSON.parse(t); });
      var stream = blob.stream().pipeThrough(new global.DecompressionStream('gzip'));
      return new Response(stream).text().then(function (t) { return JSON.parse(t); });
    });
  }

  /* 꾸러미가 수백 KB~수 MB 라 휴대폰 전파가 약하면 올리다 끊기기 쉽다. 한 번
     끊기면 그 문서는 영영 수정할 수 없게 되므로 두 번까지 다시 시도한다.
     upsert 라서 앞 시도가 서버에 닿았더라도 덮어쓰기만 될 뿐 탈이 없다. */
  var SOURCE_UPLOAD_ATTEMPTS = 3;

  function putSource(c, docId, source) {
    var path = sourcePathFor(docId);
    return toSourceBlob(source).then(function (blob) {
      function attempt(n) {
        return c.storage.from(SOURCE_BUCKET)
          .upload(path, blob, { contentType: blob.type, upsert: true })
          .then(function (up) {
            if (up.error) throw up.error;
            return { path: path, bytes: blob.size };
          })
          .catch(function (err) {
            if (n >= SOURCE_UPLOAD_ATTEMPTS) throw err;
            console.warn('원본 꾸러미 업로드 ' + n + '차 실패, 다시 시도합니다:', err);
            return new Promise(function (go) { setTimeout(go, 600 * n); }).then(function () {
              return attempt(n + 1);
            });
          });
      }
      return attempt(1);
    });
  }

  // 수정할 수 있는 문서인지 — 원본 꾸러미가 있어야 한다(예전 문서는 없다)
  function canEdit(row) {
    return !!(row && row.source_path);
  }

  function getDocument(id) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    return c.from('documents').select('*').eq('id', id).maybeSingle().then(function (res) {
      if (res.error) throw res.error;
      return res.data || null;
    });
  }

  function loadSource(path) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    return c.storage.from(SOURCE_BUCKET).download(path).then(function (res) {
      if (res.error) throw res.error;
      if (!res.data) throw new Error('원본을 찾지 못했습니다.');
      return fromSourceBlob(res.data);
    });
  }

  /* meta: doc_type, file_name, title, author_name(화면 입력칸에서 직접 받음),
     branch, field, year, manual_type(매뉴얼만), photo_count, page_count 및
     종류별 필드. 로그인이 없으므로 author_id는 채우지 않는다(null로 저장). */
  function saveDocument(meta, pdfBlob, source) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));

    // 원본 꾸러미 이름을 문서 id 로 쓰므로, 행을 넣기 전에 id 를 먼저 정한다
    var docId = newDocId();
    var basePath = storagePath(meta.doc_type, meta.branch, meta.field, meta.manual_type, meta.title, meta.year);

    return uploadWithRetry(c, BUCKET, basePath, pdfBlob, 'application/pdf').then(function (path) {
      /* 원본 꾸러미가 실패해도 PDF 저장까지 되돌리지는 않는다. 수정만 못 할 뿐
         보관·열람은 정상이라, 문서를 통째로 잃는 것보다 낫다. */
      var sourceError = null;
      var srcStep = source
        ? putSource(c, docId, source).catch(function (err) {
            /* 조용히 넘기면 "왜 수정 버튼이 없지?" 하고 한참을 헤매게 된다.
               이유를 담아 올려 보내, 화면에 그대로 띄운다. */
            sourceError = (err && err.message) || String(err);
            console.error('원본 꾸러미 저장 실패(PDF 는 저장됨):', err);
            return null;
          })
        : Promise.resolve(null);

      return srcStep.then(function (src) {
        var row = Object.assign({}, meta, {
          id: docId,
          pdf_path: path,
          pdf_bytes: pdfBlob.size,
          source_path: src ? src.path : null,
          source_bytes: src ? src.bytes : null
        });

        return c.from('documents').insert(row).select().single().then(function (ins) {
          if (ins.error) {
            // 행 저장이 실패하면 업로드한 파일이 고아로 남지 않게 정리
            c.storage.from(BUCKET).remove([path]);
            if (src) c.storage.from(SOURCE_BUCKET).remove([src.path]);
            throw ins.error;
          }
          /* 저장은 됐지만 원본이 없으면 수정이 안 된다. 어느 쪽인지 알 수 있게
             행에 표시를 달아 보낸다(DB 에 들어가는 값이 아니다). */
          var saved = ins.data;
          if (saved && sourceError) saved.__sourceError = sourceError;
          return saved;
        });
      });
    });
  }

  /* 수정한 뒤 다시 출력할 때 — 새 행을 만들지 않고 있던 행을 덮어쓴다.
     제목·지사·분야가 바뀌면 PDF 가 들어갈 폴더와 파일명도 달라지므로 새 자리에
     올리고 예전 파일을 치운다. 원본 꾸러미는 문서 id 로 이름이 정해져 있어
     언제나 같은 자리에 덮어쓴다. */
  function updateDocument(row, meta, pdfBlob, source) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));

    var newPath = storagePath(meta.doc_type, meta.branch, meta.field, meta.manual_type, meta.title, meta.year);
    var movedFile = newPath !== row.pdf_path;

    return c.storage.from(BUCKET)
      .upload(newPath, pdfBlob, { contentType: 'application/pdf', upsert: true })
      .then(function (up) {
        if (up.error) throw up.error;
        return source
          ? putSource(c, row.id, source).catch(function (err) {
              console.error('원본 꾸러미 저장 실패(PDF 는 갱신됨):', err);
              return null;
            })
          : Promise.resolve(null);
      })
      .then(function (src) {
        var patch = Object.assign({}, meta, {
          pdf_path: newPath,
          pdf_bytes: pdfBlob.size,
          updated_at: new Date().toISOString()
        });
        if (src) {
          patch.source_path = src.path;
          patch.source_bytes = src.bytes;
        }
        delete patch.created_at;   // 최초 작성 시각은 건드리지 않는다

        return c.from('documents').update(patch).eq('id', row.id).select().then(function (res) {
          if (res.error) throw res.error;
          /* RLS 는 권한이 없어도 에러 대신 0건으로 조용히 넘어간다. 갱신된 행을
             직접 세어, 안 된 것을 성공으로 넘기지 않는다. */
          if (!res.data || res.data.length === 0) {
            throw new Error('수정 권한이 없습니다. db/edit-source.sql 을 실행했는지 확인해 주세요.');
          }
          if (!movedFile) return { row: res.data[0], oldFileRemoved: true };
          return c.storage.from(BUCKET).remove([row.pdf_path]).then(function (rm) {
            var removed = !rm.error && rm.data && rm.data.length > 0;
            if (!removed) console.error('자리를 옮긴 뒤 예전 PDF 삭제 실패:', rm.error || '0건 삭제');
            return { row: res.data[0], oldFileRemoved: removed };
          }, function () {
            return { row: res.data[0], oldFileRemoved: false };
          });
        });
      });
  }

  // ---- 조회 -----------------------------------------------------------------

  /* filters:
       docType   'photo' | 'manual' | 'fault'
       fileName  파일명 부분검색
       manualType, field
       occurredFrom, occurredTo   (YYYY-MM-DD)
       branch, facility, faultContent, authorName  부분검색
       limit */
  function queryDocuments(filters) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    filters = filters || {};

    var q = c.from('documents').select('*');

    if (filters.docType) q = q.eq('doc_type', filters.docType);
    if (filters.manualType) q = q.eq('manual_type', filters.manualType);
    if (filters.field) q = q.eq('field', filters.field);
    if (filters.branch) q = q.ilike('branch', '%' + filters.branch + '%');
    if (filters.facility) q = q.ilike('facility', '%' + filters.facility + '%');
    if (filters.faultContent) q = q.ilike('fault_content', '%' + filters.faultContent + '%');
    if (filters.fileName) q = q.ilike('file_name', '%' + filters.fileName + '%');
    if (filters.authorName) q = q.ilike('author_name', '%' + filters.authorName + '%');
    // 현지 날짜의 00:00~23:59:59를 UTC 순간으로 바꿔 비교 (경계가 9시간 밀리지 않게)
    if (filters.occurredFrom) {
      var from = new Date(filters.occurredFrom + 'T00:00:00');
      if (!isNaN(from.getTime())) q = q.gte('occurred_at', from.toISOString());
    }
    if (filters.occurredTo) {
      var to = new Date(filters.occurredTo + 'T23:59:59.999');
      if (!isNaN(to.getTime())) q = q.lte('occurred_at', to.toISOString());
    }

    // 고장 보고서는 발생일시, 나머지는 작성일 기준 정렬
    if (filters.docType === 'fault') {
      q = q.order('occurred_at', { ascending: false, nullsFirst: false });
    } else {
      q = q.order('created_at', { ascending: false });
    }

    return q.limit(filters.limit || 200).then(function (res) {
      if (res.error) throw res.error;
      return res.data || [];
    });
  }

  /* 저장 전 중복 확인 — 종류(doc_type) 안에서 제목과 작성자(입력칸에 쓴 이름)가
     둘 다 같은 문서가 이미 있는지 본다. 로그인이 없어 진짜 동일인인지는 알 수
     없지만, 같은 이름을 적었다면 같은 사람일 가능성이 높다고 보고 다룬다.
     PDF 출력·메일 전송을 여러 번 눌러도 같은 문서가 계속 쌓이는 것을 막기
     위한 용도라, 결과 내용은 필요 없고 있는지 여부만 확인한다.

     criteria: { docType, title, authorName } */
  function existsByTitle(criteria) {
    var c = getClient();
    criteria = criteria || {};
    if (!c || !criteria.title) return Promise.resolve(false);

    var q = c.from('documents').select('id')
      .eq('doc_type', criteria.docType)
      .eq('title', criteria.title);
    if (criteria.authorName) q = q.eq('author_name', criteria.authorName);

    return q.limit(1).then(function (res) {
      if (res.error) throw res.error;
      return (res.data || []).length > 0;
    });
  }

  // 관리자만 매뉴얼·고장 보고서를 삭제할 수 있다(작성자가 로그인하지 않으므로
  // 본인 확인이 불가능하다). 실제 제한은 서버 RLS가 담당하고, 이건 화면에
  // 삭제 버튼을 보여줄지 판단하는 용도다.
  function canDelete(user) {
    return isAdmin(user);
  }

  /* 문서 행과 저장된 PDF를 함께 지운다. 행 삭제가 RLS에 막히면 파일은 건드리지 않는다.
     ⚠️ RLS는 "권한 없음"을 에러로 알려주지 않는다 — using 조건에 안 맞는 행은
     그냥 조용히 0건 삭제로 처리되어 res.error가 비어 있다. .select()로 실제
     삭제된 행을 돌려받아, 비어 있으면 직접 에러를 던져 화면에 실패로 알린다
     (그러지 않으면 "삭제했습니다"라고 뜨고 카드도 사라지지만 실제로는 안
     지워져서, 다시 조회하면 그대로 나오는 혼란스러운 상황이 된다). */
  function deleteDocument(row) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    return c.from('documents').delete().eq('id', row.id).select('id').then(function (res) {
      if (res.error) throw res.error;
      if (!res.data || res.data.length === 0) {
        throw new Error('삭제 권한이 없습니다. 관리자 계정으로 로그인되어 있는지 확인해 주세요.');
      }
      /* ⚠️ storage.remove() 는 실패해도 예외를 던지지 않는다. {data, error} 를
         돌려줄 뿐이라 .catch 만 걸어 두면 아무것도 걸리지 않는다. 게다가 삭제
         정책이 없으면 error 조차 비어 있고 data 가 빈 배열로 온다 — 그래서
         "지웠다"고 나오는데 Storage 에는 파일이 그대로 남는 일이 생겼다.
         error 와 지워진 개수를 모두 확인해서 호출한 쪽에 알린다. */
      // 수정용 원본 꾸러미도 짝으로 지운다. 없는 문서(예전 자료)면 건너뛴다.
      var dropSource = row.source_path
        ? c.storage.from(SOURCE_BUCKET).remove([row.source_path]).then(function (res) {
            if (res.error || !res.data || res.data.length === 0) {
              console.error('원본 꾸러미 삭제 실패(행은 삭제됨):', res.error || '0건 삭제');
            }
          }, function (err) {
            console.error('원본 꾸러미 삭제 실패(행은 삭제됨):', err);
          })
        : Promise.resolve();

      return c.storage.from(BUCKET).remove([row.pdf_path]).then(function (res) {
        var removed = !res.error && res.data && res.data.length > 0;
        if (!removed) console.error('PDF 파일 삭제 실패(행은 삭제됨):', res.error || '0건 삭제');
        return dropSource.then(function () { return { fileRemoved: removed }; });
      }, function (err) {
        console.error('PDF 파일 삭제 실패(행은 삭제됨):', err);
        return dropSource.then(function () { return { fileRemoved: false }; });
      });
    });
  }

  /* 비공개 버킷이므로 열람은 만료되는 서명 URL로만.

     downloadName 을 주면 서버가 "내려받기" 로 응답하게 하고 그 이름으로 저장된다.
     Storage 에 올라간 파일 이름은 한글을 못 써서 영문으로 바꿔 두었는데, 이
     방법을 쓰면 받는 쪽에는 원래 한글 이름으로 떨어진다. 파일을 브라우저로
     한 번 받아 와 다시 저장하는 방식(blob)보다 가볍기도 하다. */
  function signedUrl(path, seconds, downloadName) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    var opts = downloadName ? { download: downloadName } : undefined;
    return c.storage.from(BUCKET).createSignedUrl(path, seconds || 3600, opts).then(function (res) {
      if (res.error) throw res.error;
      return res.data.signedUrl;
    });
  }

  function minutesToText(mins) {
    if (mins === null || mins === undefined || mins === '') return '';
    mins = Number(mins);
    if (isNaN(mins) || mins < 0) return '';
    if (mins < 60) return mins + '분';
    var h = Math.floor(mins / 60), m = mins % 60;
    return m === 0 ? h + '시간' : h + '시간 ' + m + '분';
  }

  // ---- 개선요청 게시판 -------------------------------------------------------
  // 로그인이 없어 누구나 목록을 보고 새 요청을 올릴 수 있고, 작성자는 항상
  // "익명"으로 저장·표시한다(입력칸조차 두지 않는다). 같은 이유로 제목·내용
  // 수정과 삭제도 누구나 할 수 있다. 답변 등록·완료 표시만 관리자 전용이며,
  // db/schema.sql의 feedback_guard_admin_fields 트리거가 실제 관리자 계정이
  // 아니면 그 값을 되돌려서 막아 준다.

  function insertFeedbackRow(c, row) {
    return c.from('feedback').insert(row).select().single().then(function (res) {
      if (res.error) throw res.error;
      return res.data;
    });
  }

  // photoFile은 <input type="file">에서 온 File 객체 또는 null(선택 사항이므로).
  function submitFeedback(title, content, photoFile) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));

    var row = { title: title, content: content, status: 'open' };

    if (!photoFile) return insertFeedbackRow(c, row);

    var path = Date.now() + '_' + sanitizeForStoragePath(photoFile.name || 'photo');
    return uploadWithRetry(c, FEEDBACK_BUCKET, path, photoFile, photoFile.type || 'application/octet-stream')
      .then(function (savedPath) {
        row.photo_path = savedPath;
        return insertFeedbackRow(c, row).catch(function (err) {
          // 행 저장이 실패하면 업로드한 사진이 고아로 남지 않게 정리
          c.storage.from(FEEDBACK_BUCKET).remove([savedPath]);
          throw err;
        });
      });
  }

  function listFeedback() {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    return c.from('feedback').select('*').order('created_at', { ascending: false })
      .then(function (res) {
        if (res.error) throw res.error;
        return res.data || [];
      });
  }

  // 비공개 버킷이므로 열람은 만료되는 서명 URL로만 (signedUrl()은 documents 전용이라 분리)
  function feedbackPhotoUrl(path, seconds) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    return c.storage.from(FEEDBACK_BUCKET).createSignedUrl(path, seconds || 3600).then(function (res) {
      if (res.error) throw res.error;
      return res.data.signedUrl;
    });
  }

  // 제목·내용 수정 — 로그인이 없어 누구나 할 수 있다.
  function updateFeedback(id, title, content) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    return c.from('feedback')
      .update({ title: title, content: content })
      .eq('id', id).select().single()
      .then(function (res) {
        if (res.error) throw res.error;
        return res.data;
      });
  }

  // 답변 등록 — 관리자만 실제로 반영된다(트리거가 막음). 버튼 자체는 관리자로
  // 로그인했을 때만 화면에 보인다.
  function replyFeedback(id, replyText) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    return c.from('feedback')
      .update({ reply: replyText, replied_at: new Date().toISOString() })
      .eq('id', id).select().single()
      .then(function (res) {
        if (res.error) throw res.error;
        return res.data;
      });
  }

  function setFeedbackStatus(id, status) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    return c.from('feedback')
      .update({ status: status })
      .eq('id', id).select().single()
      .then(function (res) {
        if (res.error) throw res.error;
        return res.data;
      });
  }

  /* 삭제 — 로그인이 없어 누구나 할 수 있다. 행만 지우고 사진 파일은 그대로
     둔다(anon에게 스토리지 삭제 권한을 주지 않았다 — 관계없는 글의 사진까지
     지울 수 있게 되는 위험을 피하기 위함). .select()로 실제 삭제된 행을
     확인하는 이유는 deleteDocument()의 주석 참고. */
  function deleteFeedback(row) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    return c.from('feedback').delete().eq('id', row.id).select('id').then(function (res) {
      if (res.error) throw res.error;
      if (!res.data || res.data.length === 0) {
        throw new Error('삭제하지 못했습니다.');
      }
    });
  }

  global.Archive = {
    isEnabled: isEnabled,
    currentUser: currentUser,
    signIn: signIn,
    signOut: signOut,
    onAuthChange: onAuthChange,
    isAdmin: isAdmin,
    saveDocument: saveDocument,
    updateDocument: updateDocument,
    getDocument: getDocument,
    loadSource: loadSource,
    canEdit: canEdit,
    queryDocuments: queryDocuments,
    existsByTitle: existsByTitle,
    canDelete: canDelete,
    deleteDocument: deleteDocument,
    signedUrl: signedUrl,
    minutesToText: minutesToText,
    submitFeedback: submitFeedback,
    listFeedback: listFeedback,
    feedbackPhotoUrl: feedbackPhotoUrl,
    updateFeedback: updateFeedback,
    replyFeedback: replyFeedback,
    setFeedbackStatus: setFeedbackStatus,
    deleteFeedback: deleteFeedback
  };
})(window);
