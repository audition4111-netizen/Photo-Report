-- 변압기 Cooling Fan — 조작대상을 현장판넬 분기차단기(52CG*)로 바꾼다
--
-- 왜 바꾸나
--   지금은 팬 20대가 모두 MCC 쪽 상용·예비 피더(E16/C16 등)를 조작대상으로
--   갖고 있다. 그런데 그 둘은 **현장판넬로 들어가는 수전**이고, 팬은 판넬
--   안에서 52CG1 / 52CG2 / 52CG 로 다시 갈린다.
--
--   ⚠️ 상용·예비는 ATS 자동절체(AUTO 5SEC)다. 상용만 열면 5초 뒤 예비로
--      절체되어 팬이 그대로 돈다. 즉 지금 자료대로 E16 하나만 열면 안 멈춘다.
--      판넬 안의 52CG* 를 여는 것이 팬을 확실히 세우는 길이고,
--      배치7 검토엑셀에 사용자가 적어 둔 조작대상도 52CG* 다.
--
--   사용자 지침(2026-11-23): "그룹별로 할 거라 굳이 E16 C16 을 개방할 필요까진
--   없다. 배치 7 에 기입해 놓은 걸 반영해서 수정하면 된다."
--
-- 근거
--   · review_batch7_motors_yangsan.xlsx '검토용' 시트 301~320행 (사용자 확정)
--     조작대상명 52CG1/52CG2/52CG, 조작차단기 "52CG1(GSUT Local PNL)" 등,
--     차단기 정격 TD100NFMU16A/3-AX,L,S (16AT), 460V, 개방
--   · 벤더 준공도면 403-1-E-VD-432-105 Rev.3 p6/p8 (GSUT 현장판넬),
--     403-1-E-VD-432-205 p8 (SSUT), 403-1-E-VD-432-306 p7/p20 (UAT)
--     — 팬 분기 MCCB 와 팬 대수(GSUT 4+4, SSUT 3+3, UAT 3)가 엑셀과 일치
--
-- 팬 1대만 떼는 길은 없다. 52CG1 을 열면 그 그룹 4대(또는 3대)가 다 선다.
--
-- 여러 번 돌려도 안전하다. 실행 순서: 01~12 뒤.

begin;

-- ---------------------------------------------------------------------------
-- 1) 현장판넬 4개와 분기차단기 6개를 만든다
-- ---------------------------------------------------------------------------
-- 위치는 도면 판독값이다 — 변압기 방호벽 안쪽 옥외 지상층(GL±0.00 = EL+6.50).
insert into switch_device
  (device_name, device_type, device_subtype, voltage_class, default_operation,
   group_name, location, description)
select v.device_name, 'CB', 'MCCB', '460V', '개방', v.group_name, v.location, v.description
from (values
  ('GSUT Local PNL_52CG1', 'GSUT Local PNL', 'GT 주변압기 구역(옥외)',
   'GT SUT. Cooling FAN #1~#4 분기. MCCB: TD100NFMU16A/3-AX,L,S (16AT). 소속: GSUT(GT 주변압기) 현장판넬. ⚠️ 판넬 수전은 E16(GAS TURBINE BLDG MCC) 상용 + C16(#1 ESSENTIAL MCC) 예비의 ATS 자동절체(AUTO 5SEC) — 상용만 열면 5초 뒤 예비로 절체된다. 출처: 403-1-E-VD-432-105 Rev.3 p6/p8 + review_batch7 301~304행(사용자 확정).'),
  ('GSUT Local PNL_52CG2', 'GSUT Local PNL', 'GT 주변압기 구역(옥외)',
   'GT SUT. Cooling FAN #5~#8 분기. MCCB: TD100NFMU16A/3-AX,L,S (16AT). 소속: GSUT(GT 주변압기) 현장판넬. ⚠️ 판넬 수전은 E16 상용 + C16 예비의 ATS 자동절체(AUTO 5SEC). 출처: 403-1-E-VD-432-105 Rev.3 p6/p8 + review_batch7 305~308행(사용자 확정).'),
  ('SSUT Local PNL_52CG1', 'SSUT Local PNL', 'ST 주변압기 구역(옥외)',
   'ST SUT. Cooling FAN #1~#3 분기. MCCB: TD100NFMU16A/3-AX,L,S (16AT). 소속: SSUT(ST 주변압기) 현장판넬. ⚠️ 판넬 수전은 F13(STEAM TURBINE BLDG MCC) 상용 + D20(#2 ESSENTIAL MCC) 예비의 ATS 자동절체(AUTO 5SEC). 출처: 403-1-E-VD-432-205 p8 + review_batch7 309~311행(사용자 확정).'),
  ('SSUT Local PNL_52CG2', 'SSUT Local PNL', 'ST 주변압기 구역(옥외)',
   'ST SUT. Cooling FAN #4~#6 분기. MCCB: TD100NFMU16A/3-AX,L,S (16AT). 소속: SSUT(ST 주변압기) 현장판넬. ⚠️ 판넬 수전은 F13 상용 + D20 예비의 ATS 자동절체(AUTO 5SEC). 출처: 403-1-E-VD-432-205 p8 + review_batch7 312~314행(사용자 확정).'),
  ('GUAT Local PNL_52CG', 'GUAT Local PNL', 'GT 주변압기 구역(옥외)',
   'GT UAT Cooling FAN #1~#3 분기. MCCB: TD100NFMU16A/3-AX,L,S (16AT). 소속: GUAT(GT 소내변압기) 현장판넬. ⚠️ 판넬 수전은 E17(GAS TURBINE BLDG MCC) 상용 + C17(#1 ESSENTIAL MCC) 예비의 ATS 자동절체(AUTO 5SEC). 출처: 403-1-E-VD-432-306 p7/p20 + review_batch7 315~317행(사용자 확정).'),
  ('SUAT Local PNL_52CG', 'SUAT Local PNL', 'ST 주변압기 구역(옥외)',
   'ST UAT Cooling FAN #1~#3 분기. MCCB: TD100NFMU16A/3-AX,L,S (16AT). 소속: SUAT(ST 소내변압기) 현장판넬. ⚠️ 판넬 수전은 F14(STEAM TURBINE BLDG MCC) 상용 + D21(#2 ESSENTIAL MCC) 예비의 ATS 자동절체(AUTO 5SEC). 출처: 403-1-E-VD-432-306 p7/p20 + review_batch7 318~320행(사용자 확정).')
) as v(device_name, group_name, location, description)
where not exists (
  select 1 from switch_device d where d.device_name = v.device_name
);

-- ---------------------------------------------------------------------------
-- 2) 팬 20대의 기존 연결(상용·예비 수전)을 뗀다
-- ---------------------------------------------------------------------------
-- ⚠️ where 를 반드시 양쪽으로 좁힌다 — 팬 20대 × 그 8개 피더만.
--    수전 피더 자체의 연결(현장판넬 = FEEDER 기기)은 건드리지 않는다.
delete from equipment_switch_map m
using equipment e, switch_device d
where m.equipment_id = e.id
  and m.switch_device_id = d.id
  and e.equipment_name in (
    'GT SUT. Cooling FAN #1','GT SUT. Cooling FAN #2','GT SUT. Cooling FAN #3','GT SUT. Cooling FAN #4',
    'GT SUT. Cooling FAN #5','GT SUT. Cooling FAN #6','GT SUT. Cooling FAN #7','GT SUT. Cooling FAN #8',
    'ST SUT. Cooling FAN #1','ST SUT. Cooling FAN #2','ST SUT. Cooling FAN #3',
    'ST SUT. Cooling FAN #4','ST SUT. Cooling FAN #5','ST SUT. Cooling FAN #6',
    'GT UAT Cooling FAN #1','GT UAT Cooling FAN #2','GT UAT Cooling FAN #3',
    'ST UAT Cooling FAN #1','ST UAT Cooling FAN #2','ST UAT Cooling FAN #3'
  )
  and d.device_name in (
    'GAS TURBINE BLDG MCC_E16','#1 ESSENTIAL MCC_C16',
    'GAS TURBINE BLDG MCC_E17','#1 ESSENTIAL MCC_C17',
    'STEAM TURBINE BLDG MCC_F13','#2 ESSENTIAL MCC_D20',
    'STEAM TURBINE BLDG MCC_F14','#2 ESSENTIAL MCC_D21'
  );

-- ---------------------------------------------------------------------------
-- 3) 팬 20대를 분기차단기에 붙인다
-- ---------------------------------------------------------------------------
insert into equipment_switch_map
  (equipment_id, switch_device_id, operation_order, operation_type, remarks)
select e.id, d.id, 1, '개방',
       '같은 분기차단기를 쓰는 팬이 함께 선다 — 팬 1대만 떼는 길은 없다. 판넬 수전(상용/예비)은 ATS 자동절체이므로, 수전 쪽을 열어 팬을 세우려면 상용·예비를 함께 열어야 한다.'
from (values
  ('GT SUT. Cooling FAN #1','GSUT Local PNL_52CG1'),
  ('GT SUT. Cooling FAN #2','GSUT Local PNL_52CG1'),
  ('GT SUT. Cooling FAN #3','GSUT Local PNL_52CG1'),
  ('GT SUT. Cooling FAN #4','GSUT Local PNL_52CG1'),
  ('GT SUT. Cooling FAN #5','GSUT Local PNL_52CG2'),
  ('GT SUT. Cooling FAN #6','GSUT Local PNL_52CG2'),
  ('GT SUT. Cooling FAN #7','GSUT Local PNL_52CG2'),
  ('GT SUT. Cooling FAN #8','GSUT Local PNL_52CG2'),
  ('ST SUT. Cooling FAN #1','SSUT Local PNL_52CG1'),
  ('ST SUT. Cooling FAN #2','SSUT Local PNL_52CG1'),
  ('ST SUT. Cooling FAN #3','SSUT Local PNL_52CG1'),
  ('ST SUT. Cooling FAN #4','SSUT Local PNL_52CG2'),
  ('ST SUT. Cooling FAN #5','SSUT Local PNL_52CG2'),
  ('ST SUT. Cooling FAN #6','SSUT Local PNL_52CG2'),
  ('GT UAT Cooling FAN #1','GUAT Local PNL_52CG'),
  ('GT UAT Cooling FAN #2','GUAT Local PNL_52CG'),
  ('GT UAT Cooling FAN #3','GUAT Local PNL_52CG'),
  ('ST UAT Cooling FAN #1','SUAT Local PNL_52CG'),
  ('ST UAT Cooling FAN #2','SUAT Local PNL_52CG'),
  ('ST UAT Cooling FAN #3','SUAT Local PNL_52CG')
) as v(eq_name, sw_name)
join equipment     e on e.equipment_name = v.eq_name
join switch_device d on d.device_name    = v.sw_name
on conflict (equipment_id, switch_device_id) do nothing;

commit;

-- ---------------------------------------------------------------------------
-- 확인 — 팬마다 52CG* 하나씩, 모두 20줄이어야 한다
-- ---------------------------------------------------------------------------
select e.equipment_name, d.group_name, d.device_name, d.location, m.operation_order
from equipment e
join equipment_switch_map m on m.equipment_id = e.id
join switch_device d        on d.id = m.switch_device_id
where e.equipment_name like '%Cooling FAN%'
order by e.equipment_name;
