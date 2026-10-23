-- 문서 비밀번호 — 본인이 만든 문서만 지울 수 있게 한다
--
-- 이 앱에는 로그인이 없다. 작성자는 손으로 적는 글자일 뿐이라, 서버는 누가
-- 누구인지 알 방법이 없다. 그래서 문서를 보관함에 넣을 때 네 자리 숫자를 함께
-- 걸어 두고, 지울 때 그 숫자를 맞춰야만 지워지게 한다.
--
-- 관리자(로그인한 사람)는 숫자 없이 모든 문서를 지울 수 있다.
-- 이 파일을 실행하기 전에 만든 문서들은 숫자가 없으므로 관리자만 지울 수 있다.
--
-- ⚠️ 네 자리는 1만 가지뿐이라, 마음먹고 하나씩 넣어 보면 뚫린다. 그래서
--    비밀번호는 되돌릴 수 없는 형태(bcrypt)로만 저장하고, 틀린 횟수를 세어
--    여러 번 틀리면 한동안 잠근다. 이 둘이 함께 있어야 의미가 있다.
--
-- 이 파일을 SQL Editor 에 붙여넣고 Run 하면 된다. 여러 번 실행해도 안전하다.

-- 비밀번호를 해싱하는 데 쓴다. Supabase 에는 보통 이미 깔려 있다.
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- 1) 비밀번호를 담을 표
-- ---------------------------------------------------------------------------
-- documents 와 따로 두는 이유: documents 는 누구나 조회할 수 있어서, 거기에
-- 넣으면 목록을 받아 볼 때 비밀번호까지 같이 딸려 나간다. 이 표에는 아무
-- 정책도 걸지 않아 밖에서는 읽지도 쓰지도 못하고, 아래 함수를 통해서만 닿는다.
create table if not exists public.document_locks (
  document_id  uuid primary key references public.documents(id) on delete cascade,
  pw_hash      text        not null,
  fails        integer     not null default 0,   -- 연속으로 틀린 횟수
  locked_until timestamptz,                      -- 여기까지는 시도 자체를 막는다
  created_at   timestamptz not null default now()
);

alter table public.document_locks enable row level security;
-- 정책을 하나도 만들지 않는다 = 밖에서는 아무것도 못 한다(의도한 것).
revoke all on public.document_locks from anon, authenticated;

-- 비밀번호가 걸린 문서인지 화면에서 알아야 버튼 안내를 제대로 할 수 있다.
-- 이 값은 참/거짓뿐이라 공개되어도 문제없다.
alter table public.documents add column if not exists pw_set boolean not null default false;

-- ---------------------------------------------------------------------------
-- 2) 비밀번호 걸기 — 문서를 저장한 직후에만
-- ---------------------------------------------------------------------------
-- ⚠️ 아무 때나 걸 수 있게 두면, 남이 만들어 둔 "비밀번호 없는 문서"에 자기
--    번호를 심어 놓고 지워 버릴 수 있다. 그래서 만든 지 10분 안쪽이고 아직
--    비밀번호가 없는 문서에만 걸리게 한다.
create or replace function public.set_document_password(
  p_document_id uuid,
  p_password    text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_created timestamptz;
begin
  if p_password is null or p_password !~ '^[0-9]{4}$' then
    raise exception '비밀번호는 숫자 네 자리여야 합니다.';
  end if;

  select created_at into v_created from public.documents where id = p_document_id;
  if v_created is null then
    return false;                                   -- 없는 문서
  end if;
  if v_created < now() - interval '10 minutes' then
    return false;                                   -- 한참 전에 만든 문서는 못 건다
  end if;
  if exists (select 1 from public.document_locks where document_id = p_document_id) then
    return false;                                   -- 이미 걸려 있다
  end if;

  insert into public.document_locks (document_id, pw_hash)
  values (p_document_id, extensions.crypt(p_password, extensions.gen_salt('bf', 8)));

  update public.documents set pw_set = true where id = p_document_id;
  return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) 삭제 — 비밀번호가 맞거나, 관리자이거나
-- ---------------------------------------------------------------------------
-- 지워진 뒤 Storage 의 PDF·원본도 치워야 하므로 그 경로를 함께 돌려준다.
-- (행이 사라지면 그 파일들은 "주인 없는 파일"이 되어 앱에서 지울 수 있다)
create or replace function public.delete_document_with_password(
  p_document_id uuid,
  p_password    text
) returns table (ok boolean, reason text, pdf_path text, source_path text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_doc      record;
  v_lock     record;
  v_is_admin boolean;
  v_fails    integer;
begin
  select d.id, d.pdf_path, d.source_path into v_doc
  from public.documents d where d.id = p_document_id;
  if v_doc.id is null then
    return query select false, 'not_found'::text, null::text, null::text;
    return;
  end if;

  v_is_admin := lower(coalesce(auth.jwt() ->> 'email', '')) = 'audition411@kdhc.co.kr';

  if not v_is_admin then
    select * into v_lock from public.document_locks where document_id = p_document_id;

    if v_lock.document_id is null then
      -- 비밀번호가 없는 문서(이 기능 이전 자료) — 관리자만 지울 수 있다
      return query select false, 'admin_only'::text, null::text, null::text;
      return;
    end if;

    if v_lock.locked_until is not null and v_lock.locked_until > now() then
      return query select false, 'locked'::text, null::text, null::text;
      return;
    end if;

    if p_password is null
       or extensions.crypt(p_password, v_lock.pw_hash) <> v_lock.pw_hash then
      v_fails := v_lock.fails + 1;
      update public.document_locks
         set fails = v_fails,
             -- 다섯 번 틀리면 10분 동안 잠근다. 1만 가지를 다 넣어 보는 것을 막는다.
             locked_until = case when v_fails >= 5 then now() + interval '10 minutes' end
       where document_id = p_document_id;
      return query select false, 'wrong'::text, null::text, null::text;
      return;
    end if;
  end if;

  -- 통과 — 행을 지운다(document_locks 는 따라서 함께 지워진다)
  delete from public.documents where id = p_document_id;
  return query select true, 'ok'::text, v_doc.pdf_path, v_doc.source_path;
end;
$$;

-- 함수만 열어 준다. 표 자체는 여전히 밖에서 못 만진다.
revoke all on function public.set_document_password(uuid, text) from public;
revoke all on function public.delete_document_with_password(uuid, text) from public;
grant execute on function public.set_document_password(uuid, text) to anon, authenticated;
grant execute on function public.delete_document_with_password(uuid, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 확인
-- ---------------------------------------------------------------------------
-- 1) 표와 칸이 생겼는지
select
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_name = 'document_locks') as 잠금표,
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'documents' and column_name = 'pw_set') as pw_set칸;
-- 기대: 1 / 1

-- 2) 함수가 생겼는지
select proname, prosecdef as 권한위임
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in ('set_document_password', 'delete_document_with_password')
order by proname;
-- 기대: 두 줄 모두 권한위임 = true

-- 3) 비밀번호가 걸린 문서 수
select
  count(*) filter (where pw_set)     as 본인삭제가능,
  count(*) filter (where not pw_set) as 관리자만삭제
from public.documents;
-- 기대: 지금은 0 / 29. 이 뒤로 새로 만드는 문서부터 늘어난다.
