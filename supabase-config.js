// Supabase 연결 설정 — 아래 두 값을 본인 프로젝트 값으로 바꿔 주세요.
//
// 찾는 곳: Supabase 프로젝트 → Settings → API
//   SUPABASE_URL      = "Project URL"
//   SUPABASE_ANON_KEY = "Project API keys" 의 anon / public 키
//
// ⚠️ anon 키는 공개되어도 되는 값입니다(브라우저에서 쓰도록 설계된 키).
//    실제 보안은 db/schema.sql 의 RLS 정책이 담당합니다.
//    "service_role" 키는 절대 여기에 넣지 마세요. 모든 정책을 우회합니다.
//
// 값을 비워 두면 앱은 저장 기능 없이 지금처럼 동작합니다.

window.SUPABASE_CONFIG = {
  url: 'https://fmgxmkccmpbadmomfhbw.supabase.co',
  anonKey: 'sb_publishable_cdBgTZgdjvMaFg3FQPCxVg_A036RJ8h'
};

// 조작대상 찾기 전용 — 위와는 다른 Supabase 프로젝트입니다.
//
// 정전조작 데이터(점검대상 기기 ↔ 조작할 차단기 ↔ 위치)는 red-tag-manager 에서
// 몇 달에 걸쳐 만든 것이라 그쪽 프로젝트에 그대로 있습니다. 사진대장·매뉴얼
// 보관함과는 아무 관계가 없어 합치지 않고 따로 연결합니다.
//
// 이 값이 비어 있으면 "조작대상 찾기" 화면만 꺼지고 나머지는 그대로 동작합니다.
//
// ⚠️ 키를 아직 비워 둔 이유: 이 저장소는 공개라 여기 적는 키는 누구나 보게
//    됩니다. 원래 공개되라고 있는 키지만(publishable), 실제 방어는 DB 쪽
//    권한이 합니다. 확인해 보니 그 프로젝트는 지금 익명 쓰기가 열려 있어,
//    키를 먼저 올리면 몇 달 걸려 확정한 정전조작 데이터를 누구나 지울 수
//    있습니다. db/redtag-01-schema.sql 을 실행해 쓰기를 막은 뒤 채웁니다.
// 준비용 SQL 은 db/redtag-01-schema.sql 부터 번호대로.
window.REDTAG_CONFIG = {
  url: 'https://pqiqfdzcrrvagkccqnpz.supabase.co',
  anonKey: ''   // ← db/redtag-01-schema.sql 로 쓰기를 막은 뒤에 채웁니다
};
