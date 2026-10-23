-- 보관함에 저장한 문서를 나중에 다시 수정할 수 있게 하는 준비
--
-- 지금까지는 PDF 만 저장했다. PDF 는 사진과 글자를 눌러 찍은 결과물이라
-- 되돌릴 수가 없어서, 한 번 출력한 문서는 고칠 방법이 없었다.
--
-- 그래서 PDF 와 별개로 "작성 화면을 그대로 되살릴 수 있는 원본 꾸러미"를
-- 함께 저장한다. 작성한 입력값, 사진, 설명, 사진 위에 그린 표시까지 들어 있는
-- JSON 파일이고, 브라우저에서 gzip 으로 압축해 올린다.
--
-- 원본 꾸러미는 documents 버킷이 아니라 document-sources 라는 별도 버킷에
-- 둔다. 그래야 documents 버킷을 통째로 내려받는 전집 다운로드에 JSON 파일이
-- 섞이지 않는다.
--
-- 이 파일을 SQL Editor 에 붙여넣고 Run 하면 된다. 여러 번 실행해도 안전하다.

-- ---------------------------------------------------------------------------
-- 1) documents 표에 원본 꾸러미 위치를 적을 칸을 만든다
-- ---------------------------------------------------------------------------
-- 비어 있어도 되는 칸이라, 이미 저장된 문서들은 그대로 둬도 된다.
-- source_path 가 비어 있으면 = 원본이 없는 예전 문서 = 보관함에서 수정 버튼이
-- 보이지 않는다.
alter table public.documents add column if not exists source_path  text;
alter table public.documents add column if not exists source_bytes integer;

-- 수정하면 내용이 바뀌므로, 마지막으로 고친 시각도 남긴다.
alter table public.documents add column if not exists updated_at timestamptz;

comment on column public.documents.source_path is
  'document-sources 버킷 안의 원본 꾸러미 경로. 비어 있으면 수정할 수 없는 예전 문서.';

-- ---------------------------------------------------------------------------
-- 2) 원본 꾸러미를 담을 버킷을 만든다
-- ---------------------------------------------------------------------------
-- public=false : 주소를 아는 것만으로는 열리지 않고, 앱이 그때그때 발급하는
--                임시 주소(signed URL)로만 받을 수 있다. documents 버킷과 같다.
insert into storage.buckets (id, name, public)
values ('document-sources', 'document-sources', false)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 3) 문서 행을 덮어쓸 수 있게 한다
-- ---------------------------------------------------------------------------
-- 수정은 "새 문서를 또 만드는" 것이 아니라 "있던 문서를 갱신"하는 방식이다.
-- 지금은 select(조회)와 insert(저장) 정책만 있어서 update 가 막혀 있다.
--
-- 주의: 로그인 없이 쓰는 앱이라 "내가 만든 것만" 같은 조건을 걸 수가 없다.
--       보관함에 들어온 사람은 누구나 수정할 수 있다는 뜻이다. 삭제는 지금처럼
--       관리자만 할 수 있다.
--
-- author_id 는 로그인 없이 채울 수 없으니, 수정할 때도 계속 비어 있어야 한다.
-- (누가 남의 문서에 작성자 UUID 를 심어 놓는 일을 막는다)
-- ❗ 정책(RLS)만으로는 부족하다. SQL 차원의 권한(GRANT)이 따로 있어야 한다.
--    db/schema-main-no-login.sql 은 "grant select, insert" 까지만 줬기 때문에,
--    이게 없으면 정책이 있어도 permission denied for table documents 로 막힌다.
grant update on public.documents to anon, authenticated;

drop policy if exists "documents_update_anon" on public.documents;
create policy "documents_update_anon"
  on public.documents for update
  to public
  using (true)
  with check (author_id is null);

-- ---------------------------------------------------------------------------
-- 4) documents 버킷 — 덮어쓰기(update) 를 허용한다
-- ---------------------------------------------------------------------------
-- 같은 자리에 PDF 를 다시 올리려면(upsert) insert 말고 update 권한이 필요하다.
-- 이것이 없으면 수정 후 출력할 때 "이미 있는 파일"이라며 막힌다.
drop policy if exists "docs_storage_update_anon" on storage.objects;
create policy "docs_storage_update_anon"
  on storage.objects for update
  to public
  using (bucket_id = 'documents')
  with check (bucket_id = 'documents');

-- ---------------------------------------------------------------------------
-- 5) document-sources 버킷 — 읽기·올리기·덮어쓰기·지우기
-- ---------------------------------------------------------------------------
-- 원본 꾸러미는 사람이 열어 보는 파일이 아니라 앱이 읽는 파일이라, documents
-- 버킷보다 느슨하게 둔다. 문서를 지울 때 짝이 되는 원본도 같이 지워야 하므로
-- delete 도 열어 둔다.
drop policy if exists "src_storage_read_anon" on storage.objects;
create policy "src_storage_read_anon"
  on storage.objects for select
  to public
  using (bucket_id = 'document-sources');

drop policy if exists "src_storage_insert_anon" on storage.objects;
create policy "src_storage_insert_anon"
  on storage.objects for insert
  to public
  with check (bucket_id = 'document-sources');

drop policy if exists "src_storage_update_anon" on storage.objects;
create policy "src_storage_update_anon"
  on storage.objects for update
  to public
  using (bucket_id = 'document-sources')
  with check (bucket_id = 'document-sources');

drop policy if exists "src_storage_delete_anon" on storage.objects;
create policy "src_storage_delete_anon"
  on storage.objects for delete
  to public
  using (bucket_id = 'document-sources');

-- ---------------------------------------------------------------------------
-- 6) 원본은 올라갔는데 행에 연결이 안 된 문서를 고친다
-- ---------------------------------------------------------------------------
-- 저장할 때 원본 업로드는 성공했는데 그 응답이 앱에 닿지 못하면, 파일은 남고
-- 행에는 "원본 없음"으로 기록된다. 그러면 보관함에 수정 버튼이 뜨지 않는다.
--
-- 원본 파일 이름이 문서 id 라서 짝을 정확히 찾을 수 있다. 아래를 실행하면
-- 짝이 있는 문서가 다시 수정 가능해진다. 여러 번 실행해도 안전하다.
update public.documents d
set source_path  = o.name,
    source_bytes = nullif(o.metadata ->> 'size', '')::int
from storage.objects o
where o.bucket_id = 'document-sources'
  and o.name = d.id::text || '.json.gz'
  and d.source_path is null;

-- ---------------------------------------------------------------------------
-- 확인
-- ---------------------------------------------------------------------------
-- 1) 칸이 생겼는지
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'documents'
  and column_name in ('source_path', 'source_bytes', 'updated_at')
order by column_name;
-- 기대: 세 줄 모두 YES(비어 있어도 됨)

-- 2) 버킷이 생겼는지
select id, public from storage.buckets where id = 'document-sources';
-- 기대: document-sources / false

-- 3) update 권한이 들어갔는지
select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and table_name = 'documents'
  and privilege_type = 'UPDATE' and grantee in ('anon', 'authenticated')
order by grantee;
-- 기대: anon / UPDATE, authenticated / UPDATE  (두 줄이 나와야 한다)

-- 4) 정책이 다 붙었는지
select policyname, cmd
from pg_policies
where (schemaname = 'public'  and tablename = 'documents')
   or (schemaname = 'storage' and tablename = 'objects')
order by tablename, policyname;
-- 기대: documents_update_anon(UPDATE), docs_storage_update_anon(UPDATE),
--       src_storage_read_anon(SELECT), src_storage_insert_anon(INSERT),
--       src_storage_update_anon(UPDATE), src_storage_delete_anon(DELETE)
--       + 원래 있던 정책들

-- ---------------------------------------------------------------------------
-- 참고 — 이 작업 전에 만든 문서들은 원본이 없어 수정할 수 없다.
-- 아래로 몇 건이 수정 가능한지 셀 수 있다.
-- ---------------------------------------------------------------------------
-- select
--   count(*) filter (where source_path is not null) as 수정가능,
--   count(*) filter (where source_path is null)     as 열람만가능
-- from public.documents;
