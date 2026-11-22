-- 조작대상 찾기 — MOV 배전반 피더의 그룹·위치 바로잡기
--
-- 사용자 지시(2026-11-22):
--   ① HRSG MOV PNL 피더들의 위치가 "ST동 3층 전기실" 로 되어 있는데
--      실제 위치는 "HRSG동 1층" 이다.
--   ② 그 피더들의 그룹은 "HRSG MOV PNL".
--   ③ 나머지 MOV 피더들도 그룹이 비어 있다 — "ST MOV", "DH MOV" 식으로 단다.
--
-- 그룹을 어떻게 가리나: 조작대상 이름의 앞머리가 그 피더가 꽂힌 배전반을
-- 가리킨다(HRSG-Q01, ST-002, CT-003, DH-014). 실제로 이 넷은 모두 MOV·밸브
-- (LCV / HV- / FV- / FCV-)로 이어지는 것을 확인했고, 배전반도 기기 목록에
-- 그대로 있다 — 460V MOV DIST. BOARD (ST)/(CT)/(DH),
-- 460V HRSG MOV POWER DIST. PANEL.
--
-- ⚠️ 위치는 HRSG 것만 바꾼다. ST·CT·DH 는 지금 값(ST동 3층 전기실 /
--    냉각탑동 2층 전기실 / DH동 B1F 공동구)이 맞다고 보아 건드리지 않는다.
--
-- ⚠️ 이 수정은 red-tag-manager 쪽 원본 파일에는 아직 반영돼 있지 않다.
--    거기서 배치를 다시 만들어 올리면 이 값이 덮일 수 있으므로, 같은 내용을
--    red-tag-manager 에도 남겨 두어야 한다.
--
-- 여러 번 실행해도 안전하다(같은 값을 다시 쓸 뿐이다).

-- ---------------------------------------------------------------------------
-- 1) HRSG MOV PNL — 그룹과 위치
-- ---------------------------------------------------------------------------
update switch_device
   set group_name = 'HRSG MOV PNL',
       location   = 'HRSG동 1층'
 where device_name like 'HRSG-%';

-- ---------------------------------------------------------------------------
-- 2) 나머지 MOV 배전반 — 그룹만
-- ---------------------------------------------------------------------------
update switch_device set group_name = 'ST MOV' where device_name like 'ST-%';
update switch_device set group_name = 'CT MOV' where device_name like 'CT-%';
update switch_device set group_name = 'DH MOV' where device_name like 'DH-%';

-- ---------------------------------------------------------------------------
-- 확인
-- ---------------------------------------------------------------------------
-- 1) 그룹·위치가 제대로 붙었는지
select group_name, location, count(*) as 건수
from switch_device
where group_name in ('HRSG MOV PNL','ST MOV','CT MOV','DH MOV')
group by group_name, location
order by group_name, location;
-- 기대: HRSG MOV PNL 은 전부 'HRSG동 1층' 한 줄로 모여야 한다.
--       ST/CT/DH MOV 는 원래 위치가 그대로 나온다.

-- 2) 아직 ST동 3층 전기실에 남은 HRSG 피더가 있는지
select count(*) as 안바뀐_HRSG
from switch_device
where device_name like 'HRSG-%' and location is distinct from 'HRSG동 1층';
-- 기대: 0

-- 3) 화면에서 보이는 모습 (HP DRUM 쪽 MOV 몇 개)
select s.location, s.group_name, s.device_name, m.operation_type, e.equipment_name
from equipment_switch_map m
join switch_device s on s.id = m.switch_device_id
join equipment e on e.id = m.equipment_id
where s.device_name like 'HRSG-%'
order by s.device_name
limit 5;
-- 기대: 위치 'HRSG동 1층', 그룹 'HRSG MOV PNL'
