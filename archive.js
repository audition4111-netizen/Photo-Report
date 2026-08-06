/* 문서 보관/조회 공통 모듈 — 작성 앱(index.html)과 조회 페이지(search.html)가 함께 사용.
   Supabase가 설정되지 않았거나 오프라인이면 isEnabled()가 false를 반환하고,
   앱은 저장 기능 없이 기존대로 동작합니다. */
(function (global) {
  'use strict';

  var BUCKET = 'documents';
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

  // ---- 인증 -----------------------------------------------------------------

  function currentUser() {
    var c = getClient();
    if (!c) return Promise.resolve(null);
    return c.auth.getUser().then(function (res) {
      return (res && res.data && res.data.user) || null;
    }).catch(function () { return null; });
  }

  function displayName(user) {
    if (!user) return '';
    var meta = user.user_metadata || {};
    return meta.display_name || meta.name || (user.email || '').split('@')[0];
  }

  function signIn(email, password) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    return c.auth.signInWithPassword({ email: email, password: password }).then(function (res) {
      if (res.error) throw res.error;
      return res.data.user;
    });
  }

  function signUp(email, password, name) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    return c.auth.signUp({
      email: email,
      password: password,
      options: { data: { display_name: name } }
    }).then(function (res) {
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
  function uploadWithRetry(c, basePath, pdfBlob) {
    function attempt(n) {
      var path = n === 1 ? basePath : withSuffix(basePath, n);
      return c.storage.from(BUCKET)
        .upload(path, pdfBlob, { contentType: 'application/pdf', upsert: false })
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

  /* meta: doc_type, file_name, title, branch, field, year, manual_type(매뉴얼만),
     photo_count, page_count 및 종류별 필드. author_id / author_name / pdf_path /
     pdf_bytes 는 여기서 채웁니다. branch·field·manual_type·title·year로 저장 경로
     (documents/{지사}/{연도}/{분야}/{종류}/{매뉴얼종류}/{제목}.pdf)를 만든다. */
  function saveDocument(meta, pdfBlob) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));

    return currentUser().then(function (user) {
      if (!user) throw new Error('로그인이 필요합니다.');

      var basePath = storagePath(meta.doc_type, meta.branch, meta.field, meta.manual_type, meta.title, meta.year);

      return uploadWithRetry(c, basePath, pdfBlob).then(function (path) {
        var row = Object.assign({}, meta, {
          author_id: user.id,
          author_name: displayName(user),
          pdf_path: path,
          pdf_bytes: pdfBlob.size
        });

        return c.from('documents').insert(row).select().single().then(function (ins) {
          if (ins.error) {
            // 행 저장이 실패하면 업로드한 파일이 고아로 남지 않게 정리
            c.storage.from(BUCKET).remove([path]);
            throw ins.error;
          }
          return ins.data;
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

  /* 저장 전 중복 확인 — 종류(doc_type) 안에서 작성자와 파일명(제목)이 둘 다 같은
     문서가 이미 보관함에 있는지 본다. 지사·분야 등은 보지 않는다 — 지사나 분야가
     달라도 같은 작성자가 같은 제목으로 또 저장하려는 경우를 잡아내려는 용도.
     PDF 출력·메일 전송을 여러 번 눌러도 작성자 모르게 같은 문서가 계속 쌓이는
     것을 막기 위한 용도라, 결과 내용은 필요 없고 있는지 여부만 확인한다.

     criteria: { docType, title, authorId } */
  function existsByTitle(criteria) {
    var c = getClient();
    criteria = criteria || {};
    if (!c || !criteria.title) return Promise.resolve(false);

    return c.from('documents').select('id')
      .eq('doc_type', criteria.docType)
      .eq('title', criteria.title)
      .eq('author_id', criteria.authorId)
      .limit(1)
      .then(function (res) {
        if (res.error) throw res.error;
        return (res.data || []).length > 0;
      });
  }

  // 작성자 본인 또는 관리자(김영섭)만 삭제할 수 있다. 실제 제한은 서버 RLS가 담당하고,
  // 이건 화면에 삭제 버튼을 보여줄지 판단하는 용도다.
  function canDelete(user, row) {
    if (!user || !row) return false;
    if (row.author_id && row.author_id === user.id) return true;
    var email = (user.email || '').toLowerCase();
    return email === ADMIN_EMAIL.toLowerCase();
  }

  // 개선요청 답변·완료 표시 버튼을 보여줄지 판단하는 용도. 실제 차단은
  // db/schema.sql의 feedback_update_admin 정책(RLS)이 담당한다.
  function isAdmin(user) {
    if (!user) return false;
    return (user.email || '').toLowerCase() === ADMIN_EMAIL.toLowerCase();
  }

  // 문서 행과 저장된 PDF를 함께 지운다. 행 삭제가 RLS에 막히면 파일은 건드리지 않는다.
  function deleteDocument(row) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    return c.from('documents').delete().eq('id', row.id).then(function (res) {
      if (res.error) throw res.error;
      return c.storage.from(BUCKET).remove([row.pdf_path]).catch(function (err) {
        console.error('PDF 파일 삭제 실패(행은 삭제됨):', err);
      });
    });
  }

  // 비공개 버킷이므로 열람은 만료되는 서명 URL로만
  function signedUrl(path, seconds) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));
    return c.storage.from(BUCKET).createSignedUrl(path, seconds || 3600).then(function (res) {
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
  // 로그인한 사용자라면 누구나 목록을 보고 새 요청을 올릴 수 있다(모든 로그인
  // 사용자에게 공개). 답변·완료 표시는 관리자만 — 실제 제한은
  // db/schema.sql의 feedback_update_admin RLS 정책이 담당한다.

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
    return currentUser().then(function (user) {
      if (!user) throw new Error('로그인이 필요합니다.');

      var row = {
        author_id: user.id,
        author_name: displayName(user),
        title: title,
        content: content,
        status: 'open'
      };

      if (!photoFile) return insertFeedbackRow(c, row);

      var path = user.id + '/' + Date.now() + '_' + sanitizeForStoragePath(photoFile.name || 'photo');
      return c.storage.from(FEEDBACK_BUCKET)
        .upload(path, photoFile, { contentType: photoFile.type || 'application/octet-stream', upsert: false })
        .then(function (up) {
          if (up.error) throw up.error;
          row.photo_path = path;
          return insertFeedbackRow(c, row).catch(function (err) {
            // 행 저장이 실패하면 업로드한 사진이 고아로 남지 않게 정리
            c.storage.from(FEEDBACK_BUCKET).remove([path]);
            throw err;
          });
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

  global.Archive = {
    isEnabled: isEnabled,
    currentUser: currentUser,
    displayName: displayName,
    signIn: signIn,
    signUp: signUp,
    signOut: signOut,
    onAuthChange: onAuthChange,
    saveDocument: saveDocument,
    queryDocuments: queryDocuments,
    existsByTitle: existsByTitle,
    canDelete: canDelete,
    isAdmin: isAdmin,
    deleteDocument: deleteDocument,
    signedUrl: signedUrl,
    minutesToText: minutesToText,
    submitFeedback: submitFeedback,
    listFeedback: listFeedback,
    feedbackPhotoUrl: feedbackPhotoUrl,
    replyFeedback: replyFeedback,
    setFeedbackStatus: setFeedbackStatus
  };
})(window);
