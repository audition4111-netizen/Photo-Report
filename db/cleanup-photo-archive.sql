-- 사진대장(doc_type = 'photo') 보관 기록 정리
--
-- 사진대장은 이제 보관함에 저장하지 않습니다. 그 전에 저장된 기록은 조회 화면에서
-- 볼 수 없는 상태로 남아 용량만 차지하므로, 아래 순서대로 지웁니다.
--
-- ⚠️ 되돌릴 수 없습니다. 반드시 1단계로 무엇이 지워질지 먼저 확인하세요.
-- ⚠️ 매뉴얼·고장 보고서는 건드리지 않습니다 (doc_type = 'photo' 만 대상).

-- ---------------------------------------------------------------------------
-- 1단계 — 무엇이 지워질지 확인 (지우지 않음, 안전)
-- ---------------------------------------------------------------------------
select doc_type,
       count(*)                as 건수,
       pg_size_pretty(sum(coalesce(pdf_bytes, 0))::bigint) as 용량,
       min(created_at)         as 가장_오래된,
       max(created_at)         as 가장_최근
from public.documents
group by doc_type
order by doc_type;

-- 지워질 목록을 눈으로 확인하고 싶으면:
-- select created_at, author_name, file_name, pdf_path, pdf_bytes
-- from public.documents
-- where doc_type = 'photo'
-- order by created_at;


-- ---------------------------------------------------------------------------
-- 2단계 — 저장된 PDF 파일 삭제 (Storage)
-- ---------------------------------------------------------------------------
-- 파일은 대시보드에서 지우는 것이 확실합니다. SQL로 storage.objects 행만 지우면
-- 실제 파일이 남아 용량이 계속 잡힐 수 있습니다.
--
--   Storage → documents 버킷 → photo 폴더 선택 → Delete
--
-- 사진대장 파일은 모두 photo/ 아래에만 있으므로(경로 규칙: doc_type/연/월/uuid.pdf),
-- 이 폴더만 지우면 매뉴얼(manual/)·고장 보고서(fault/)는 영향받지 않습니다.
--
-- 지우기 전에 개수를 확인하려면:
-- select count(*) as 사진대장_파일수
-- from storage.objects
-- where bucket_id = 'documents' and name like 'photo/%';


-- ---------------------------------------------------------------------------
-- 3단계 — 표에서 기록 삭제
-- ---------------------------------------------------------------------------
-- 2단계로 파일을 먼저 지우세요. 행을 먼저 지우면 어떤 파일이 사진대장 것이었는지
-- 알 수 없게 되어(pdf_path 가 사라져) 파일이 고아로 남습니다.

delete from public.documents
where doc_type = 'photo';


-- ---------------------------------------------------------------------------
-- 4단계 — 정리 확인
-- ---------------------------------------------------------------------------
select doc_type, count(*) as 건수
from public.documents
group by doc_type
order by doc_type;
-- 기대: photo 가 목록에 없고, manual / fault 건수는 그대로
