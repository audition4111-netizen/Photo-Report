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
  url: '',
  anonKey: ''
};
