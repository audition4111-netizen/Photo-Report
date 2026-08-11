/* 사내망 배포용 단일 HTML 만들기
 *
 *   node build-standalone.js
 *   -> 뚝DOC-사내망.html  (파일 하나만 주고받으면 되는 오프라인 버전)
 *
 * index.html 을 원본으로 삼아
 *   - Supabase 관련 스크립트를 빼서 로그인·보관함·개선요청을 모두 끄고
 *   - 메일로 전송 버튼을 감추고
 *   - 라이브러리와 이미지를 파일 안에 넣는다.
 *
 * 남는 기능: 작성 · 사진 편집 · 임시저장 · 미리보기 · PDF 출력
 *
 * ※ DOM 을 지우지 않고 CSS 로 감추는 이유
 *   checkFeedbackBadge() 같은 함수가 배지 요소를 조건 없이 건드려서, 요소를
 *   지우면 null 참조로 스크립트가 죽는다. 감추면 눌릴 수 없어 핸들러가 아예
 *   실행되지 않으므로 결과는 같고 훨씬 안전하다.
 *
 * ※ index.html 이 바뀌어 아래 앵커를 못 찾으면 즉시 오류로 멈춘다.
 *   조용히 반쯤 지워진 파일이 나오는 것보다 낫다.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, 'index.html');
const OUT = path.join(__dirname, '뚝DOC-사내망.html');

// 원본은 CRLF 로 저장돼 있다. 앵커를 \n 하나로 쓸 수 있게 먼저 통일한다.
let html = fs.readFileSync(SRC, 'utf8').split('\r\n').join('\n');

// ---- 도우미 --------------------------------------------------------------

function cut(needle, label) {
  if (html.indexOf(needle) === -1) {
    throw new Error('찾지 못함 [' + label + ']: ' + needle.slice(0, 70));
  }
  html = html.split(needle).join('');
  console.log('  제거  ' + label);
}

function swap(needle, replacement, label) {
  if (html.indexOf(needle) === -1) {
    throw new Error('찾지 못함 [' + label + ']: ' + needle.slice(0, 70));
  }
  html = html.split(needle).join(replacement);
  console.log('  치환  ' + label);
}

function dataUri(file) {
  const ext = path.extname(file).slice(1).toLowerCase();
  const mime = ext === 'gif' ? 'image/gif' : ext === 'jpg' || ext === 'jpeg' ? 'image/jpeg' : 'image/png';
  return 'data:' + mime + ';base64,' + fs.readFileSync(path.join(__dirname, file)).toString('base64');
}

function inlineScript(file) {
  const code = fs.readFileSync(path.join(__dirname, file), 'utf8');
  // </script> 가 코드 안에 있으면 태그가 일찍 닫히므로 끊어 준다
  return '<script>\n' + code.split('</script>').join('<\\/script>') + '\n</script>';
}

// ---- 1. 설치·오프라인 관련 태그 (파일 하나로는 쓸 수 없다) ----------------

console.log('[1] 설치 관련 태그 제거');
cut('<link rel="manifest" href="manifest.json">\n', 'manifest 링크');
cut('<link rel="icon" type="image/png" sizes="192x192" href="icon-192.png">\n', 'favicon 링크');
cut('<link rel="apple-touch-icon" href="apple-touch-icon.png">\n', 'iOS 아이콘 링크');

// ---- 2. Supabase 제거 -> 로그인 / 보관함 / 개선요청이 모두 꺼진다 ---------

console.log('[2] Supabase 제거');
cut('<script src="libs/supabase.min.js"></script>\n', 'supabase 라이브러리');
cut('<script src="supabase-config.js"></script>\n', 'supabase 설정');
cut('<script src="archive.js"></script>\n', 'archive.js');

const swBlock = html.match(/<script>\s*\/\* 서비스 워커 등록[\s\S]*?<\/script>\n/);
if (!swBlock) throw new Error('서비스 워커 등록 블록을 찾지 못했습니다.');
cut(swBlock[0], '서비스 워커 등록');

// ---- 3. 남은 UI 감추기 ---------------------------------------------------

console.log('[3] 사용하지 않는 UI 감추기');
swap('<style>', `<style>
  /* --- 사내망 단일 파일 버전에서 감추는 것들 ---
     저장 기능이 없으므로 메일 전송·개선요청·로그인 관련 UI 는 쓰지 않는다.
     (요소를 지우면 이 노드를 참조하는 스크립트가 죽어서 감추기만 한다) */
  #mailBtn, .feedback-fab, #modeAuthRow, #authRow, #authModal, #feedbackModal { display:none !important; }
  /* 메일 버튼이 빠졌으니 PDF 출력이 주 버튼 자리를 대신한다 */
  #pdfBtn{ background:var(--primary); border-color:var(--primary); color:#fff; }
  #pdfBtn:disabled{ background:var(--primary-disabled); border-color:var(--primary-disabled); }
`, '감추기용 CSS 삽입');

// ---- 4. 이미지 인라인 ----------------------------------------------------

/* 이미지는 HTML 속성뿐 아니라 스크립트 문자열로도 들어간다
   (출력물의 로고·배너는 logo.src = 'manual-logo.gif' 처럼 JS 에서 붙인다).
   속성만 바꾸면 출력물이 file:// 이미지를 불러 캔버스가 오염되고,
   PDF 저장이 "Tainted canvases may not be exported" 로 실패한다.
   그래서 따옴표로 감싼 모든 형태를 바꾼다. */
console.log('[4] 이미지 인라인');
['manual-logo.gif', 'banner.png', 'mascot.png'].forEach(function (file) {
  const uri = dataUri(file);
  let hits = 0;
  ['"', "'"].forEach(function (q) {
    const needle = q + file + q;
    while (html.indexOf(needle) !== -1) {
      html = html.replace(needle, q + uri + q);
      hits++;
    }
  });
  if (!hits) throw new Error('이미지 참조를 찾지 못함: ' + file);
  console.log('  인라인  ' + file + '  (' + hits + '곳, ' + Math.round(uri.length / 1024) + ' KB)');
});

// ---- 5. 스크립트 인라인 --------------------------------------------------

console.log('[5] 스크립트 인라인');
const inlinedBodies = [];   // 아래 검사에서 라이브러리 본문은 빼기 위해 기억해 둔다
[['libs/html2canvas.min.js', 'html2canvas'],
 ['libs/jspdf.umd.min.js', 'jsPDF'],
 ['draft.js', 'draft.js']].forEach(function (pair) {
  const body = inlineScript(pair[0]);
  inlinedBodies.push(body);
  swap('<script src="' + pair[0] + '"></script>', body, pair[1]);
});

// ---- 6. 제목 ------------------------------------------------------------

swap('<title>뚝 DOC — 자동 문서 생성기</title>',
     '<title>뚝 DOC — 자동 문서 생성기 (사내망용)</title>', '제목');

// ---- 확인 ---------------------------------------------------------------

/* 파일명이 어떤 형태로든(속성·JS 문자열) 남아 있으면 실패로 본다.
   src="..." 만 확인했다가 JS 안의 'manual-logo.gif' 를 놓친 적이 있다. */
const leftovers = [
  ['libs/', '외부 라이브러리 참조'],
  ['supabase-config.js', 'supabase 설정 참조'],
  ['archive.js', 'archive.js 참조'],
  ['draft.js', 'draft.js 참조'],
  ['manifest.json', 'manifest 참조'],
  ['mascot.png', 'mascot 파일 참조'],
  ['banner.png', 'banner 파일 참조'],
  ['manual-logo.gif', '로고 파일 참조'],
  ['icon-192.png', '아이콘 참조'],
  ['apple-touch-icon.png', 'iOS 아이콘 참조'],
  ['sw.js', '서비스 워커 참조'],
  ['search.html', '보관함 페이지 링크'],
  ['guide.html', '가이드 페이지 링크']
];
/* 라이브러리 본문은 빼고 검사한다. jsPDF 안에는 이 앱이 쓰지 않는
   'libs/pdfobject/...' 같은 CDN 주소가 들어 있어 그대로 두면 오탐이 난다. */
let checkTarget = html;
inlinedBodies.forEach(function (body) { checkTarget = checkTarget.split(body).join(''); });

const found = leftovers.filter(function (l) { return checkTarget.indexOf(l[0]) !== -1; });
if (found.length) {
  throw new Error('외부 파일 참조가 남았습니다: ' + found.map(function (f) { return f[1]; }).join(', '));
}

fs.writeFileSync(OUT, html, 'utf8');
console.log('\n완료: ' + path.basename(OUT) + '  (' + (Buffer.byteLength(html) / 1024 / 1024).toFixed(2) + ' MB)');
console.log('외부 파일 참조 없음 — 이 파일 하나만 주고받으면 됩니다.');
