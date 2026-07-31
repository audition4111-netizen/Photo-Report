-- 가입 도메인 제한 — @kdhc.co.kr 메일만 회원가입 허용
--
-- schema.sql 을 먼저 실행한 뒤, 이 파일을 SQL Editor 에 붙여넣고 실행하세요.
-- 실행만으로는 적용되지 않습니다. 마지막에 대시보드에서 훅을 연결해야 합니다.
--   Authentication → Hooks → "Before User Created"
--     → Postgres 선택 → public.hook_restrict_signup_by_email_domain 지정 → Enable
--
-- ⚠️ 이 훅은 "신규 가입"만 막습니다.
--    이미 만들어진 계정은 도메인이 달라도 그대로 로그인됩니다.
--    테스트로 만든 외부 메일 계정이 있으면
--    Authentication → Users 에서 먼저 삭제하세요.

-- ---------------------------------------------------------------------------
-- 허용 도메인 목록 (나중에 추가·삭제만 하면 되고 함수는 고칠 필요 없음)
-- ---------------------------------------------------------------------------
create table if not exists public.signup_allowed_domains (
  domain text primary key
);

insert into public.signup_allowed_domains (domain)
values ('kdhc.co.kr')
on conflict (domain) do nothing;

-- 이 표는 훅에서만 읽습니다. 정책을 만들지 않으므로 anon/authenticated 는 접근 불가.
alter table public.signup_allowed_domains enable row level security;

-- ---------------------------------------------------------------------------
-- 훅 함수
--   허용  → '{}'          (빈 객체를 돌려주면 가입 진행)
--   거부  → error 객체     (message 가 사용자에게 그대로 보입니다)
-- ---------------------------------------------------------------------------
create or replace function public.hook_restrict_signup_by_email_domain(event jsonb)
returns jsonb
language plpgsql
security definer            -- 소유자 권한으로 실행해 위 표를 읽을 수 있게
set search_path = public
as $$
declare
  v_email   text;
  v_domain  text;
  v_allowed int;
begin
  v_email  := lower(coalesce(event -> 'user' ->> 'email', ''));
  v_domain := split_part(v_email, '@', 2);

  if v_domain = '' then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'message', '유효한 이메일 주소를 입력해 주세요.',
        'http_code', 400
      )
    );
  end if;

  select count(*) into v_allowed
  from public.signup_allowed_domains
  where lower(domain) = v_domain;

  if v_allowed > 0 then
    return '{}'::jsonb;
  end if;

  return jsonb_build_object(
    'error', jsonb_build_object(
      'message', '회사 이메일로만 가입할 수 있습니다.',
      'http_code', 403
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 권한 — 인증 서비스만 실행할 수 있고, 일반 사용자는 호출조차 못 하게
-- ---------------------------------------------------------------------------
grant usage on schema public to supabase_auth_admin;

grant execute
  on function public.hook_restrict_signup_by_email_domain(jsonb)
  to supabase_auth_admin;

revoke execute
  on function public.hook_restrict_signup_by_email_domain(jsonb)
  from authenticated, anon, public;

grant select on public.signup_allowed_domains to supabase_auth_admin;

-- ---------------------------------------------------------------------------
-- 확인용 — 실행하면 허용/거부가 바로 보입니다
-- ---------------------------------------------------------------------------
-- select public.hook_restrict_signup_by_email_domain(
--   '{"user":{"email":"hong@kdhc.co.kr"}}'::jsonb);   -- 기대: {}
-- select public.hook_restrict_signup_by_email_domain(
--   '{"user":{"email":"hong@gmail.com"}}'::jsonb);    -- 기대: error 403
