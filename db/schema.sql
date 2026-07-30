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

  -- 저장된 PDF
  pdf_path      text        not null,
  pdf_bytes     integer,
  page_count    integer,
  photo_count   integer     not null default 0,

  -- 매뉴얼 전용
  manual_type   text,                 -- 업무/조작/운전/점검/정비 매뉴얼
  field         text,                 -- 분야 (매뉴얼 9종 / 고장보고서 7종 공용)
  revision      text,                 -- 개정번호

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

drop policy if exists "documents_delete_own" on public.documents;
create policy "documents_delete_own"
  on public.documents for delete
  to authenticated
  using (author_id = auth.uid());

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

-- 업로드한 본인만 삭제
drop policy if exists "docs_storage_delete_own" on storage.objects;
create policy "docs_storage_delete_own"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'documents' and owner = auth.uid());
