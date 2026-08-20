-- 관리자가 문서를 지울 때 저장된 PDF 파일도 함께 지워지게 하는 정책
--
-- 증상: 보관함에서 관리자가 문서를 삭제하면 목록에서는 사라지는데,
--       Supabase Storage 의 documents 버킷에는 PDF 파일이 그대로 남는다.
--
-- 원인: 로그인 없는 구조로 바꾸면서(db/schema-main-no-login.sql) documents
--       버킷에 읽기(select)·업로드(insert) 정책만 만들고 삭제(delete) 정책을
--       두지 않았다. RLS 는 정책이 없으면 "권한 없음"을 에러로 알리지 않고
--       그냥 0건 삭제로 조용히 넘어가므로, 앱은 성공한 줄 알고 지나간다.
--
-- 이 파일을 SQL Editor 에 붙여넣고 Run 하면 된다. 여러 번 실행해도 안전하다.

-- ---------------------------------------------------------------------------
-- documents 버킷 — 관리자만 파일 삭제 가능
-- ---------------------------------------------------------------------------
-- 업로드는 로그인 없이(익명으로) 이루어져 owner 가 비어 있으므로, "올린 사람만
-- 지운다" 식의 조건은 쓸 수 없다. 문서 행(public.documents)의 삭제 정책과 똑같이
-- 관리자 이메일로 판단한다.
--
-- lower() 로 감싸는 이유: 이메일 대소문자가 한 글자라도 다르면 화면에는 관리자로
-- 보이는데 서버 검사에서만 막혀, 삭제한 것처럼 보이고 실제로는 남는 상황이 된다.
drop policy if exists "docs_storage_delete_admin" on storage.objects;
create policy "docs_storage_delete_admin"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'documents'
    and lower(auth.jwt() ->> 'email') = 'audition411@kdhc.co.kr'
  );

-- ---------------------------------------------------------------------------
-- 확인
-- ---------------------------------------------------------------------------
-- 1) 정책이 만들어졌는지
select policyname, cmd, roles
from pg_policies
where schemaname = 'storage' and tablename = 'objects'
  and policyname like 'docs_storage%'
order by policyname;
-- 기대: docs_storage_delete_admin (DELETE) / docs_storage_insert_anon (INSERT)
--       / docs_storage_read_anon (SELECT)

-- 2) 실제로 지워지는지는 앱에서 확인하는 것이 확실하다.
--    관리자로 로그인 → 보관함에서 문서 하나 삭제 → Storage → documents 버킷에서
--    해당 PDF 가 사라졌는지 본다.

-- ---------------------------------------------------------------------------
-- 참고 — 이 정책이 생기기 전에 삭제된 문서들의 PDF 는 이미 고아로 남아 있다.
-- 아래로 목록을 확인하고, 필요하면 Storage 화면에서 지우면 된다.
-- (documents 표에 없는 pdf_path 를 가진 파일 = 고아 파일)
-- ---------------------------------------------------------------------------
-- select o.name as 남은_파일, o.created_at
-- from storage.objects o
-- where o.bucket_id = 'documents'
--   and not exists (
--     select 1 from public.documents d where d.pdf_path = o.name
--   )
-- order by o.created_at;
