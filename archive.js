/* 문서 보관/조회 공통 모듈 — 작성 앱(index.html)과 조회 페이지(search.html)가 함께 사용.
   Supabase가 설정되지 않았거나 오프라인이면 isEnabled()가 false를 반환하고,
   앱은 저장 기능 없이 기존대로 동작합니다. */
(function (global) {
  'use strict';

  var BUCKET = 'documents';
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

  function storagePath(docType, id) {
    var now = new Date();
    var yyyy = now.getFullYear();
    var mm = ('0' + (now.getMonth() + 1)).slice(-2);
    return docType + '/' + yyyy + '/' + mm + '/' + id + '.pdf';
  }

  function uuid() {
    if (global.crypto && global.crypto.randomUUID) return global.crypto.randomUUID();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (ch) {
      var r = (Math.random() * 16) | 0;
      return (ch === 'x' ? r : ((r & 0x3) | 0x8)).toString(16);
    });
  }

  /* meta: doc_type, file_name, title, photo_count, page_count 및 종류별 필드.
     author_id / author_name / pdf_path / pdf_bytes 는 여기서 채웁니다. */
  function saveDocument(meta, pdfBlob) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('Supabase가 설정되지 않았습니다.'));

    return currentUser().then(function (user) {
      if (!user) throw new Error('로그인이 필요합니다.');

      var id = uuid();
      var path = storagePath(meta.doc_type, id);

      return c.storage.from(BUCKET)
        .upload(path, pdfBlob, { contentType: 'application/pdf', upsert: false })
        .then(function (up) {
          if (up.error) throw up.error;

          var row = Object.assign({}, meta, {
            id: id,
            author_id: user.id,
            author_name: displayName(user),
            pdf_path: path,
            pdf_bytes: pdfBlob.size
          });

          return c.from('documents').insert(row).select().single();
        })
        .then(function (ins) {
          if (ins.error) {
            // 행 저장이 실패하면 업로드한 파일이 고아로 남지 않게 정리
            c.storage.from(BUCKET).remove([path]);
            throw ins.error;
          }
          return ins.data;
        });
    });
  }

  // ---- 조회 -----------------------------------------------------------------

  /* filters:
       docType   'photo' | 'manual' | 'fault'
       fileName  파일명 부분검색
       manualType, field
       occurredFrom, occurredTo   (YYYY-MM-DD)
       branch, facility, faultContent  부분검색
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

  // 작성자 본인 또는 관리자(김영섭)만 삭제할 수 있다. 실제 제한은 서버 RLS가 담당하고,
  // 이건 화면에 삭제 버튼을 보여줄지 판단하는 용도다.
  function canDelete(user, row) {
    if (!user || !row) return false;
    if (row.author_id && row.author_id === user.id) return true;
    var email = (user.email || '').toLowerCase();
    return email === ADMIN_EMAIL.toLowerCase();
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
    canDelete: canDelete,
    deleteDocument: deleteDocument,
    signedUrl: signedUrl,
    minutesToText: minutesToText
  };
})(window);
