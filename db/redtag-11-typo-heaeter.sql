-- 조작대상 찾기 — 기기명 오기 바로잡기 (HEAETER → HEATER)
--
-- 사용자 지시(2026-11-23): "오기 수정해줘."
--
-- 배치 7(열원 전동기)에서 넘어온 이름 두 건에 HEATER 가 HEAETER 로 적혀
-- 있다. red-tag-manager 쪽 원본 배치 파일과 검토용 엑셀에도 같은 오기가
-- 있어, 열원 전동기 설비 마스터 시트에서 그대로 넘어온 것으로 보인다.
--
--   ST LINE SIDE CUBICLE HEAETER     (MKA10GE011)
--   ST NEUTRAL SIDE CUBICLE HEAETER  (MKA10GE021)
--
-- 이름뿐 아니라 설명(description)·비고에도 같은 철자가 들어 있어 함께 고친다.
--
-- ⚠️ red-tag-manager 쪽 원본에는 반영돼 있지 않다. 거기서 배치를 다시
--    만들어 올리면 되살아난다(redtag-09·10 과 같은 사정).
--
-- 여러 번 실행해도 안전하다.

-- ---------------------------------------------------------------------------
-- 1) 기기 이름과 설명
-- ---------------------------------------------------------------------------
update equipment
   set equipment_name = replace(equipment_name, 'HEAETER', 'HEATER')
 where equipment_name like '%HEAETER%';

update equipment
   set description = replace(description, 'HEAETER', 'HEATER')
 where description like '%HEAETER%';

-- ---------------------------------------------------------------------------
-- 2) 조작대상 쪽 설명에도 같은 철자가 있을 수 있다
-- ---------------------------------------------------------------------------
update switch_device
   set description = replace(description, 'HEAETER', 'HEATER')
 where description like '%HEAETER%';

-- ---------------------------------------------------------------------------
-- 확인
-- ---------------------------------------------------------------------------
-- 1) 남은 오기가 있는지
select 'equipment.name'        as 자리, count(*) as 남은것 from equipment     where equipment_name like '%HEAETER%'
union all
select 'equipment.description' , count(*) from equipment     where description    like '%HEAETER%'
union all
select 'switch.description'    , count(*) from switch_device where description    like '%HEAETER%';
-- 기대: 세 줄 모두 0

-- 2) 고쳐진 이름
select equipment_name, equipment_number, equipment_type
from equipment
where equipment_name like '%CUBICLE HEATER%'
order by equipment_name;
-- 기대: ST LINE SIDE CUBICLE HEATER / ST NEUTRAL SIDE CUBICLE HEATER
--       둘 다 equipment_type = 'ST 발전기'
