-- 조작대상 찾기 — 부속기기 범주 다시 나누기 + MOV 피더 위치 채우기
--
-- 사용자 지시(2026-11-22):
--   ① 부속기기 23건 중 14건을 다른 범주로 옮긴다.
--        154kV #A/#B BUS PT                      → GIS
--        GT 발전기에 딸린 것 6건                  → GT 발전기
--        ST 발전기에 딸린 것 6건                  → ST 발전기
--      나머지 9건(터빈·윤활유 쪽 히터)은 부속기기에 그대로 둔다.
--   ② CT MOV → 냉각탑동 2층 전기실
--      DH MOV → DH동 B1F 공동구
--      ST MOV → ST동 3층 전기실
--
-- ⚠️ 범주 이름을 'GT 발전기' / 'ST 발전기' 로 받았으므로, 지금 '발전기'
--    범주에 혼자 들어 있는 기기 'GT 발전기'·'ST 발전기' 자신도 같은 범주로
--    옮긴다. 그래야 "GT 발전기" 를 누르면 발전기 본체와 그 딸린 것들이 한자리
--    에 모인다. 그 결과 '발전기' 범주는 비게 되고, 화면에는 'GT 발전기 7건' ·
--    'ST 발전기 7건' 두 칩이 나온다.
--    본체는 '발전기' 에 그대로 두길 원하면 아래 2) 블록만 지우면 된다.
--
-- ⚠️ 이 수정은 red-tag-manager 쪽 원본 배치 파일에는 반영돼 있지 않다.
--    거기서 배치를 다시 만들어 올리면 덮일 수 있다(redtag-09 와 같은 사정).
--
-- 여러 번 실행해도 안전하다(같은 값을 다시 쓸 뿐이다).

-- ===========================================================================
-- 0) 범주 검사 규칙을 먼저 넓힌다 — 안 그러면 아래 update 가 막힌다
-- ===========================================================================
alter table equipment drop constraint if exists equipment_equipment_type_check;
alter table equipment add  constraint equipment_equipment_type_check
  check (equipment_type in
    ('GIS','변압기','발전기','GT 발전기','ST 발전기','전동기','부속기기','수배전반'));

-- ===========================================================================
-- 1) 부속기기 14건을 옮긴다 — 이름을 하나하나 적는다
--    (like 로 쓸어 담으면 부속기기에 남겨야 할 GT/ST 히터까지 딸려 간다)
-- ===========================================================================

-- 1-1) GIS 로
update equipment set equipment_type = 'GIS'
 where equipment_name in ('154kV #A BUS PT',
                          '154kV #B BUS PT');

-- 1-2) GT 발전기 로
update equipment set equipment_type = 'GT 발전기'
 where equipment_name in ('GT AVR',
                          'GT GENERATOR SPACE HEATER',
                          'GT GENERATOR SPACE HEATER FOR COLLECTOR',
                          'GT GLAC COMPARTMENT HEATERS',
                          'GT GNAC COMPARTMENT HEATERS',
                          'SFC');

-- 1-3) ST 발전기 로
update equipment set equipment_type = 'ST 발전기'
 where equipment_name in ('ST AVR',
                          'ST EXCITER HEATER',
                          'ST GENERATOR DE HEATER',
                          'ST GENERATOR NDE HEATER',
                          'ST LINE SIDE CUBICLE HEAETER',
                          'ST NEUTRAL SIDE CUBICLE HEAETER');

-- ===========================================================================
-- 2) 발전기 본체도 같은 범주로 — 본체를 '발전기' 에 두려면 이 블록만 지운다
-- ===========================================================================
update equipment set equipment_type = 'GT 발전기' where equipment_name = 'GT 발전기';
update equipment set equipment_type = 'ST 발전기' where equipment_name = 'ST 발전기';

-- ===========================================================================
-- 3) MOV 피더 위치 채우기 — 비어 있는 23건
--    (이미 값이 있는 것은 같은 값이라 결과가 달라지지 않는다)
-- ===========================================================================
update switch_device set location = '냉각탑동 2층 전기실' where group_name = 'CT MOV';
update switch_device set location = 'DH동 B1F 공동구'     where group_name = 'DH MOV';
update switch_device set location = 'ST동 3층 전기실'      where group_name = 'ST MOV';

-- ===========================================================================
-- 확인
-- ===========================================================================
-- 1) 범주별 건수
select equipment_type, count(*) as 건수
from equipment
group by equipment_type
order by 건수 desc;
-- 기대(양산+사송을 합친 전체): 수배전반 999 · 전동기 304 · 변압기 27 ·
--       부속기기 9 · GT 발전기 7 · ST 발전기 7 · GIS 5 = 1358
--       '발전기' 범주는 사라진다(본체가 GT/ST 로 옮겨 갔다).

-- 2) 하나도 새거나 빠지지 않았는지
select count(*) as 전체 from equipment;
-- 기대: 1358

-- 3) 옮긴 14건이 제대로 갔는지
select equipment_type, equipment_name
from equipment
where equipment_type in ('GIS','GT 발전기','ST 발전기')
order by equipment_type, equipment_name;
-- 기대: GIS 5건 · GT 발전기 7건 · ST 발전기 7건

-- 4) 부속기기에 남은 9건
select equipment_name from equipment
where equipment_type = '부속기기' order by equipment_name;
-- 기대: GT GAS COMPARTMENT AIR INLET HEATER / GT LOAD GEAR COMPARTMENT AIR
--       HEATER / GT LUBE OIL COMPARTMENT AIR HEATER / GT LUBE OIL HEATER #1
--       TO 2 / GT LUBE OIL HEATER #3 TO 4 / GT TURBINE COMPARTMENT HEATER /
--       ST CONTROL OIL TANK HEATING HEATER / ST CONTROL OIL TANK HEATING
--       HEATER(추가) / ST LUBE OIL TANK HEATING HEATER
--       ※ 사송 부속기기 5건은 사업장이 달라 여기 섞여 나온다.

-- 5) MOV 위치가 다 찼는지
select group_name, location, count(*) as 건수
from switch_device
where group_name in ('HRSG MOV PNL','ST MOV','CT MOV','DH MOV')
group by group_name, location
order by group_name;
-- 기대: 그룹마다 한 줄씩만, 빈 위치 없음
--       CT MOV 냉각탑동 2층 전기실 54 · DH MOV DH동 B1F 공동구 30 ·
--       HRSG MOV PNL HRSG동 1층 42 · ST MOV ST동 3층 전기실 55
