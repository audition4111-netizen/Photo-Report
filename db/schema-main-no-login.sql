-- main 배포판: 일반 사용자 로그인 제거, 작성자는 입력칸으로 직접 받기
-- Supabase 프로젝트의 SQL Editor에 전체를 붙여넣고 한 번 실행하세요.
-- 여러 번 실행해도 안전하도록 작성했습니다.
--
-- 바뀌는 것:
--   - documents·feedback 모두 로그인 없이(anon) 조회·저장할 수 있게 연다.
--   - author_id(로그인 사용자 UUID)는 더 이상 채우지 않으므로 NOT NULL을 뺀다.
--     author_name은 매뉴얼·고장 보고서는 화면 입력칸에서 직접 받고, 개선요청은
--     항상 "익명"으로 표기하므로(저장 자체는 비워 둠) 이것도 NOT NULL을 뺀다.
--   - feedback은 수정·삭제를 "로그인 여부와 무관하게 누구나" 할 수 있게 연다.
--     단, 답변 등록·완료 표시(관리자 전용 칸)는 기존 feedback_guard_admin_fields
--     트리거가 여전히 관리자(김영섭) 계정으로 로그인했을 때만 실제로 반영되도록
--     막아 준다 — 이 트리거는 db/schema.sql에 이미 있고 이 스크립트가 건드리지
--     않으므로 그대로 유효하다.
--   - documents는 삭제 권한을 넓히지 않는다(관리자만 계속 삭제 가능) — 매뉴얼·
--     고장 보고서를 아무나 지울 수 있게 할 이유는 없다고 보고 열지 않았다.
--     필요하면 나중에 이 부분만 추가로 열 수 있다.

-- ---------------------------------------------------------------------------
-- documents — 로그인 없이 저장·조회 허용 (삭제·수정은 계속 관리자/본인만)
-- ---------------------------------------------------------------------------
alter table public.documents alter column author_id drop not null;
alter table public.documents alter column author_name drop not null;

grant select, insert on public.documents to anon;

drop policy if exists "documents_select_anon" on public.documents;
create policy "documents_select_anon"
  on public.documents for select
  to anon
  using (true);

-- author_id는 로그인 없이 채울 수 없으니 반드시 비어 있어야만 저장을 허용한다
-- (다른 사람 계정 명의로 위장 저장하는 것을 막기 위함).
drop policy if exists "documents_insert_anon" on public.documents;
create policy "documents_insert_anon"
  on public.documents for insert
  to anon
  with check (author_id is null);

drop policy if exists "docs_storage_read_anon" on storage.objects;
create policy "docs_storage_read_anon"
  on storage.objects for select
  to anon
  using (bucket_id = 'documents');

drop policy if exists "docs_storage_insert_anon" on storage.objects;
create policy "docs_storage_insert_anon"
  on storage.objects for insert
  to anon
  with check (bucket_id = 'documents');

-- ---------------------------------------------------------------------------
-- feedback — 로그인 없이 작성·조회·수정·삭제 모두 허용(익명 게시판으로 전환).
-- 답변·완료 표시는 db/schema.sql의 feedback_guard_admin_fields 트리거가
-- 관리자 계정이 아니면 그 값을 원래대로 되돌려서 계속 막아 준다.
-- ---------------------------------------------------------------------------
alter table public.feedback alter column author_id drop not null;
alter table public.feedback alter column author_name drop not null;

grant select, insert, update, delete on public.feedback to anon;

drop policy if exists "feedback_select_anon" on public.feedback;
create policy "feedback_select_anon"
  on public.feedback for select
  to anon
  using (true);

drop policy if exists "feedback_insert_anon" on public.feedback;
create policy "feedback_insert_anon"
  on public.feedback for insert
  to anon
  with check (author_id is null);

drop policy if exists "feedback_update_anon" on public.feedback;
create policy "feedback_update_anon"
  on public.feedback for update
  to anon
  using (true)
  with check (true);

drop policy if exists "feedback_delete_anon" on public.feedback;
create policy "feedback_delete_anon"
  on public.feedback for delete
  to anon
  using (true);

drop policy if exists "feedback_storage_read_anon" on storage.objects;
create policy "feedback_storage_read_anon"
  on storage.objects for select
  to anon
  using (bucket_id = 'feedback-photos');

drop policy if exists "feedback_storage_insert_anon" on storage.objects;
create policy "feedback_storage_insert_anon"
  on storage.objects for insert
  to anon
  with check (bucket_id = 'feedback-photos');

-- 사진 삭제는 열지 않았다(관리자만 가능) — 개선요청 글은 누구나 지울 수 있게
-- 했지만, 첨부 사진 파일까지 무차별로 지울 수 있게 하면 관계없는 다른 글의
-- 사진까지 건드릴 여지가 있어 위험 대비 이득이 적다고 보았다. 게시글을
-- 지우면 사진 파일만 고아로 남는데(용량만 차지, 화면에는 안 보임), 문제가
-- 되면 나중에 관리자가 정리하면 된다.
