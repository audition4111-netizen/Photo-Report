-- 사진대장 & 매뉴얼 & 고장 보고서 — 문서 보관/조회용 스키마
-- Supabase 프로젝트의 SQL Editor에 전체를 붙여넣고 한 번 실행하세요.
-- 여러 번 실행해도 안전하도록 작성했습니다.

-- 한글 부분검색(파일명·고장내용·설비명)용 확장
create extension if not exists pg_trgm;

-- ---------------------------------------------------------------------------
-- 문서 테이블
-- ---------------------------------------------------------------------------
create table if not exists public.documents (
  id            uuid primary key default gen_random_uuid(),

  -- 공통
  doc_type      text        not null check (doc_type in ('photo', 'manual', 'fault')),
  file_name     text        not null,
  title         text        not null,
  author_id     uuid        not null references auth.users(id) on delete restrict,
  author_name   text        not null,
  created_at    timestamptz not null default now(),

  -- 저장된 파일 — PDF 출력·Word 출력을 각각 누르면 그때마다 별도 행이 생기므로
  -- 한 행에는 보통 둘 중 하나만 채워진다(문서 하나에 pdf_path와 docx_path가
  -- 동시에 차는 경우는 없음). 그래서 원래 not null 이던 pdf_path를 완화했다.
  pdf_path      text,
  pdf_bytes     integer,
  docx_path     text,
  docx_bytes    integer,
  page_count    integer,
  photo_count   integer     not null default 0,

  -- 매뉴얼 전용
  manual_type   text,                 -- 업무/조작/운전/점검/정비 매뉴얼
  field         text,                 -- 분야 (매뉴얼 9종 / 고장보고서 7종 공용)
  revision      text,                 -- 개정번호

  -- 저장 경로용 (documents/{지사}/{연도}/{종류}/{제목}.pdf)
  year          integer,              -- PDF 생성 연도

  -- 고장 보고서 전용
  occurred_at   timestamptz,          -- 발생일시
  branch        text,                 -- 지사
  facility      text,                 -- 설비명
  device        text,                 -- 기기명(고장위치)
  fault_content text,                 -- 고장내용
  situation     text,                 -- 상황
  cause         text,                 -- 추정 원인
  recover_at    timestamptz,          -- 예상복구(조치) 일시
  recover_note  text,                 -- 예상복구 직접 입력
  action_taken  text,                 -- 조치사항
  outage_none   boolean,              -- 열공급 중단 해당없음
  outage_apt    integer,              -- APT 세대
  outage_bldg   integer,              -- 건물 개소
  outage_at     timestamptz,          -- 중단시간
  outage_mins   integer               -- 기간(분). 표시할 때 시간/분으로 변환
);

comment on column public.documents.outage_mins is '기간을 분 단위 정수로 저장해 정렬·집계가 가능하게 함';

-- 이미 만들어진 테이블에는 create table if not exists가 컬럼을 추가해 주지 않으므로 별도로 추가한다.
alter table public.documents add column if not exists year integer;
comment on column public.documents.year is 'PDF 생성 연도 — 저장 경로(documents/{지사}/{연도}/{종류}/{제목}.pdf)의 연도와 맞춘다';

-- Word(.docx) 출력 지원 — 기존에 만들어진 테이블은 pdf_path가 not null이라
-- 그 제약부터 풀어야 docx 전용 행(pdf_path가 비고 docx_path만 있는 행)을 넣을 수 있다.
alter table public.documents alter column pdf_path drop not null;
alter table public.documents add column if not exists docx_path text;
alter table public.documents add column if not exists docx_bytes integer;

-- 둘 다 비어 있는(=아무 파일도 없는) 행은 만들어지지 않게 막는다.
alter table public.documents drop constraint if exists documents_has_file;
alter table public.documents add constraint documents_has_file
  check (pdf_path is not null or docx_path is not null);

-- ---------------------------------------------------------------------------
-- 조회 성능용 인덱스
-- ---------------------------------------------------------------------------
create index if not exists documents_type_created_idx
  on public.documents (doc_type, created_at desc);

create index if not exists documents_manual_idx
  on public.documents (doc_type, manual_type, field);

create index if not exists documents_occurred_idx
  on public.documents (occurred_at desc nulls last);

create index if not exists documents_branch_idx
  on public.documents (branch);

create index if not exists documents_author_idx
  on public.documents (author_id, created_at desc);

-- 한글 부분검색: to_tsvector는 한국어 형태소를 모르므로 trigram + ILIKE 사용
create index if not exists documents_filename_trgm_idx
  on public.documents using gin (file_name gin_trgm_ops);

create index if not exists documents_content_trgm_idx
  on public.documents using gin (fault_content gin_trgm_ops);

create index if not exists documents_facility_trgm_idx
  on public.documents using gin (facility gin_trgm_ops);

create index if not exists documents_author_trgm_idx
  on public.documents using gin (author_name gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- 테이블 접근 권한
--   프로젝트에 따라 public 스키마 기본 권한이 자동으로 주어지지 않는 경우가 있어
--   (그러면 로그인해도 "permission denied for table documents" 로 실패)
--   로그인 역할에 명시적으로 부여합니다. 실제 행 제한은 아래 RLS 정책이 담당합니다.
-- ---------------------------------------------------------------------------
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.documents to authenticated;

-- 비로그인(anon)은 어떤 경우에도 접근 불가
revoke all on public.documents from anon;

-- ---------------------------------------------------------------------------
-- RLS — anon 키는 공개 페이지에 노출되므로 이 정책이 유일한 방어선입니다.
-- ---------------------------------------------------------------------------
alter table public.documents enable row level security;

drop policy if exists "documents_select_authenticated" on public.documents;
create policy "documents_select_authenticated"
  on public.documents for select
  to authenticated
  using (true);

-- 저장은 로그인 사용자만, 그리고 본인 명의로만
drop policy if exists "documents_insert_own" on public.documents;
create policy "documents_insert_own"
  on public.documents for insert
  to authenticated
  with check (author_id = auth.uid());

drop policy if exists "documents_update_own" on public.documents;
create policy "documents_update_own"
  on public.documents for update
  to authenticated
  using (author_id = auth.uid())
  with check (author_id = auth.uid());

-- 본인 명의 문서, 또는 관리자(김영섭) 계정은 모든 문서를 삭제할 수 있다
drop policy if exists "documents_delete_own" on public.documents;
create policy "documents_delete_own"
  on public.documents for delete
  to authenticated
  using (author_id = auth.uid() or auth.jwt() ->> 'email' = 'audition411@kdhc.co.kr');

-- ---------------------------------------------------------------------------
-- Storage — 비공개 버킷 'documents'
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('documents', 'documents', false)
on conflict (id) do nothing;

drop policy if exists "docs_storage_read" on storage.objects;
create policy "docs_storage_read"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'documents');

drop policy if exists "docs_storage_insert" on storage.objects;
create policy "docs_storage_insert"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'documents');

-- 업로드한 본인, 또는 관리자(김영섭) 계정만 삭제
drop policy if exists "docs_storage_delete_own" on storage.objects;
create policy "docs_storage_delete_own"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'documents'
    and (owner = auth.uid() or auth.jwt() ->> 'email' = 'audition411@kdhc.co.kr'));

-- ---------------------------------------------------------------------------
-- 개선요청 게시판
--   로그인한 사용자라면 누구나 목록을 보고 새 요청을 올릴 수 있다(모든 로그인
--   사용자에게 공개). 답변·완료 표시(update)는 관리자(김영섭)만 가능하다.
-- ---------------------------------------------------------------------------
create table if not exists public.feedback (
  id           uuid primary key default gen_random_uuid(),
  author_id    uuid        not null references auth.users(id) on delete restrict,
  author_name  text        not null,
  title        text        not null,
  content      text        not null,
  photo_path   text,                 -- 'feedback-photos' 버킷 내 경로(선택 사항)
  status       text        not null default 'open' check (status in ('open', 'resolved')),
  reply        text,                 -- 관리자 답변
  replied_at   timestamptz,
  created_at   timestamptz not null default now()
);

create index if not exists feedback_created_idx
  on public.feedback (created_at desc);

create index if not exists feedback_status_idx
  on public.feedback (status, created_at desc);

grant usage on schema public to authenticated;
grant select, insert, update on public.feedback to authenticated;
revoke all on public.feedback from anon;

alter table public.feedback enable row level security;

drop policy if exists "feedback_select_authenticated" on public.feedback;
create policy "feedback_select_authenticated"
  on public.feedback for select
  to authenticated
  using (true);

drop policy if exists "feedback_insert_own" on public.feedback;
create policy "feedback_insert_own"
  on public.feedback for insert
  to authenticated
  with check (author_id = auth.uid());

-- 답변·완료 표시는 관리자만.
drop policy if exists "feedback_update_admin" on public.feedback;
create policy "feedback_update_admin"
  on public.feedback for update
  to authenticated
  using (auth.jwt() ->> 'email' = 'audition411@kdhc.co.kr')
  with check (auth.jwt() ->> 'email' = 'audition411@kdhc.co.kr');

-- 작성자 본인은 제목·내용을 고칠 수 있다. 단, 관리자 답변이 이미 달린 뒤에는
-- 막는다 — 답변이 원래 내용을 근거로 달렸는데 그 뒤에 내용이 바뀌면 답변과
-- 어긋나 보이기 때문. (앱 화면도 답변이 있으면 수정 버튼을 보여주지 않는다.)
drop policy if exists "feedback_update_own" on public.feedback;
create policy "feedback_update_own"
  on public.feedback for update
  to authenticated
  using (author_id = auth.uid() and reply is null)
  with check (author_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 위 두 update 정책은 "행 단위"로만 걸린다 — 작성자 본인 정책이 허용하는 행이면
-- 원래는 status·reply 같은 관리자 전용 칸도 API로 직접 바꿔 보낼 수 있다.
-- 그래서 이 트리거가 "누가 보냈는지"를 다시 보고, 관리자가 아니면 그 칸들을
-- 무조건 원래 값으로 되돌린다 — 화면에 버튼이 없어도 API를 직접 호출하는
-- 경우까지 막는 마지막 안전장치.
-- ---------------------------------------------------------------------------
create or replace function public.feedback_guard_admin_fields()
returns trigger
language plpgsql
as $$
begin
  if coalesce(auth.jwt() ->> 'email', '') <> 'audition411@kdhc.co.kr' then
    new.status := old.status;
    new.reply := old.reply;
    new.replied_at := old.replied_at;
  end if;
  return new;
end;
$$;

drop trigger if exists feedback_guard_admin_fields_trigger on public.feedback;
create trigger feedback_guard_admin_fields_trigger
  before update on public.feedback
  for each row execute function public.feedback_guard_admin_fields();

-- Storage — 비공개 버킷 'feedback-photos'
insert into storage.buckets (id, name, public)
values ('feedback-photos', 'feedback-photos', false)
on conflict (id) do nothing;

drop policy if exists "feedback_storage_read" on storage.objects;
create policy "feedback_storage_read"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'feedback-photos');

drop policy if exists "feedback_storage_insert" on storage.objects;
create policy "feedback_storage_insert"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'feedback-photos');

-- 삭제 — 작성자 본인 또는 관리자(김영섭)만.
grant delete on public.feedback to authenticated;

drop policy if exists "feedback_delete_own_or_admin" on public.feedback;
create policy "feedback_delete_own_or_admin"
  on public.feedback for delete
  to authenticated
  using (author_id = auth.uid() or auth.jwt() ->> 'email' = 'audition411@kdhc.co.kr');

drop policy if exists "feedback_storage_delete" on storage.objects;
create policy "feedback_storage_delete"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'feedback-photos'
    and (owner = auth.uid() or auth.jwt() ->> 'email' = 'audition411@kdhc.co.kr'));
