-- 소방펌프 LCP 와 ST 히터 3건 — 조작대상이 비어 있던 것을 채운다
--
-- 사용자 지침(2026-11-23)
--   · "소방 Jockey Pump 는 2026년 대장처럼 해 줘. 소방 LCP 판넬의 위치는
--      DH동 B1F 공동구야."
--   · "사실 ACB-305 는 Local 소방 판넬 Main 전원으로 가는 공급전원이야.
--      거기서 Main 과 Jockey 로 분기되어 전원차단기 MCCB 가 별도로 있어."
--
-- 즉 LC-3_ACB-305 는 **판넬 수전**이고, 펌프 2대는 판넬 안에서 각자의 MCCB 로
-- 갈린다. 2005년 준공도면의 COMMON MCC #1_MC-110 직접 급전은 2023년 교체 때
-- 바뀐 것으로 정리한다(MC-110 자체는 지우지 않고 그대로 둔다).
--
-- 2026 Tag대장(승인No 574829 / 순번 187·188)
--   352-M-PP-001 소방 MAIN PUMP   → "MAIN P/P MCCB(LCP)"
--   352-M-PP-003 소방 JOCKEY PUMP → "JOCKEY P/P MCCB(LCP)"
--
-- ⚠️ MAIN PUMP 도 함께 바꾼다. 지금은 MAIN 이 ACB-305(판넬 수전)를 조작대상으로
--    갖고 있는데, JOCKEY 만 분기 MCCB 로 옮기면 두 펌프가 서로 다른 층위를 보게
--    된다. 그 상태로 MAIN 을 점검하려고 ACB-305 를 열면 JOCKEY 까지 함께 죽어
--    소방계통 전체가 내려간다. 대장도 두 펌프 모두 MCCB(LCP) 로 적고 있다.
--    원치 않으시면 3)번 블록만 지우고 돌리면 된다.
--
-- 여러 번 돌려도 안전하다. 실행 순서: 01~13 뒤.

begin;

-- ---------------------------------------------------------------------------
-- 1) 소방펌프 LCP 의 분기차단기 2개를 만든다
-- ---------------------------------------------------------------------------
insert into switch_device
  (device_name, device_type, device_subtype, voltage_class, default_operation,
   group_name, location, description)
select v.device_name, 'CB', 'MCCB', '460V', '개방', '소방펌프 LCP', 'DH동 B1F 공동구', v.description
from (values
  ('소방펌프 LCP_MAIN P/P MCCB',
   '소방 MAIN PUMP(352-M-PP-001) 분기. LCP(Local Control Panel) 내부 전용 차단기. 판넬 수전은 LC-3_ACB-305(관리동 1층 전기실) — 수전을 열면 JOCKEY 까지 함께 죽는다. 출처: 2026 Tag대장 순번 187 "MAIN P/P MCCB(LCP)" + 사용자 확인(2026-11-23).'),
  ('소방펌프 LCP_JOCKEY P/P MCCB',
   '소방 JOCKEY PUMP(352-M-PP-003) 3.75kW 분기. LCP(Local Control Panel) 내부 전용 차단기. 판넬 수전은 LC-3_ACB-305(관리동 1층 전기실) — 수전을 열면 MAIN 까지 함께 죽는다. 출처: 2026 Tag대장 승인No 574829 / 순번 188 "JOCKEY P/P MCCB(LCP)" + 사용자 확인(2026-11-23).')
) as v(device_name, description)
where not exists (
  select 1 from switch_device d where d.device_name = v.device_name
);

-- 판넬 수전이라는 사실을 ACB-305 쪽에도 적어 둔다.
-- 정격은 참조파일 기준(630AF/160AT). LC-305 계통도에는 1250AF/320AT 로 적혀
-- 있어 서로 다르다 — 사용자 판단으로 참조파일을 따른다(2026-11-23).
update switch_device
set description = '소방펌프 LCP(Local Control Panel) 수전. ACB: 630AF/160AT(참조파일 기준 — LC-305 계통도는 1250AF/320AT 로 달라, 사용자 판단으로 참조파일을 따름). ⚠️ 이것을 열면 MAIN·JOCKEY 두 펌프가 함께 죽는다. 펌프 한 대만 떼려면 LCP 안의 해당 MCCB 를 연다.'
where device_name = 'LC-3_ACB-305';

-- ---------------------------------------------------------------------------
-- 2) 소방 JOCKEY PUMP — 조작대상이 없던 것을 붙인다
-- ---------------------------------------------------------------------------
insert into equipment_switch_map
  (equipment_id, switch_device_id, operation_order, operation_type, remarks)
select e.id, d.id, 1, '개방',
       '판넬 안의 분기 MCCB 다. 판넬 수전(LC-3_ACB-305)을 열면 MAIN PUMP 까지 죽으므로 이쪽을 연다.'
from equipment e, switch_device d
where e.equipment_name = '소방 JOCKEY PUMP'
  and d.device_name    = '소방펌프 LCP_JOCKEY P/P MCCB'
on conflict (equipment_id, switch_device_id) do nothing;

update equipment
set description = '소방 JOCKEY PUMP (352-M-PP-003) 3.75kW — 소방펌프 LCP 내부 JOCKEY P/P MCCB 급전. 근거: 2026 Tag대장 승인No 574829 + 사용자 확인(2026-11-23) "ACB-305 는 소방 LCP 수전이고, 거기서 MAIN 과 JOCKEY 로 분기되어 MCCB 가 별도로 있다". LCP 위치: DH동 B1F 공동구. 2005년 준공도면(403-2-E-SL-443-003)의 COMMON MCC #1_MC-110 직접 급전은 2023년 교체 전 상태다.'
where equipment_name = '소방 JOCKEY PUMP';

-- ---------------------------------------------------------------------------
-- 3) 소방 MAIN PUMP — 수전(ACB-305) 에서 분기 MCCB 로 옮긴다
-- ---------------------------------------------------------------------------
-- 이 블록만 지우면 MAIN 은 지금처럼 ACB-305 를 가리킨 채 남는다.
delete from equipment_switch_map m
using equipment e, switch_device d
where m.equipment_id = e.id
  and m.switch_device_id = d.id
  and e.equipment_name = '소방 MAIN PUMP'
  and d.device_name    = 'LC-3_ACB-305';

insert into equipment_switch_map
  (equipment_id, switch_device_id, operation_order, operation_type, remarks)
select e.id, d.id, 1, '개방',
       '판넬 안의 분기 MCCB 다. 판넬 수전(LC-3_ACB-305)을 열면 JOCKEY PUMP 까지 죽으므로 이쪽을 연다.'
from equipment e, switch_device d
where e.equipment_name = '소방 MAIN PUMP'
  and d.device_name    = '소방펌프 LCP_MAIN P/P MCCB'
on conflict (equipment_id, switch_device_id) do nothing;

-- ---------------------------------------------------------------------------
-- 4) ST CONTROL OIL TANK HEATING HEATER 2대 → J03 + J16 둘 다
-- ---------------------------------------------------------------------------
-- 같은 기기번호(MAX10AH110-E01)로 히터가 2대고, STEAM TURBINE MCC 의 J03 과
-- J16 이 둘 다 그 이름을 달고 있다. 도면만으로는 어느 히터가 어느 피더인지
-- 가려지지 않는다 — 그래서 **둘 다 조작대상으로 둔다.** 어느 히터를 떼든
-- 두 차단기를 열면 확실히 죽는다. 하나만 열고 작업하면 살아 있을 수 있다.
insert into equipment_switch_map
  (equipment_id, switch_device_id, operation_order, operation_type, remarks)
select e.id, d.id, v.ord, '개방',
       '⚠️ 같은 기기번호 히터가 2대(원래 + 추가)인데 J03·J16 중 어느 쪽이 어느 히터인지 도면으로 가려지지 않는다. 둘 다 열어야 확실히 죽는다.'
from (values
  ('ST CONTROL OIL TANK HEATING HEATER',       'STEAM TURBINE MCC_J03', 1),
  ('ST CONTROL OIL TANK HEATING HEATER',       'STEAM TURBINE MCC_J16', 2),
  ('ST CONTROL OIL TANK HEATING HEATER(추가)', 'STEAM TURBINE MCC_J03', 1),
  ('ST CONTROL OIL TANK HEATING HEATER(추가)', 'STEAM TURBINE MCC_J16', 2)
) as v(eq_name, sw_name, ord)
join equipment     e on e.equipment_name = v.eq_name
join switch_device d on d.device_name    = v.sw_name
on conflict (equipment_id, switch_device_id) do nothing;

-- ---------------------------------------------------------------------------
-- 5) ST NEUTRAL SIDE CUBICLE HEATER → J32-9 (LSC 와 한 회로)
-- ---------------------------------------------------------------------------
-- 검증 결과: 케이블 한 가닥(SL-C2-0031)이 LSC 와 NSC 둘 다로 간다. 그래서
-- J32-9 하나가 두 히터를 먹인다. 이미 ST LINE SIDE CUBICLE HEATER 가 J32-9 에
-- 붙어 있고, NSC 도 같은 차단기다.
insert into equipment_switch_map
  (equipment_id, switch_device_id, operation_order, operation_type, remarks)
select e.id, d.id, 1, '개방',
       'LSC(ST LINE SIDE CUBICLE HEATER)와 한 회로다 — 케이블 SL-C2-0031 한 가닥이 둘 다로 간다. 이 차단기를 열면 LSC 히터도 함께 죽는다.'
from equipment e, switch_device d
where e.equipment_name = 'ST NEUTRAL SIDE CUBICLE HEATER'
  and d.device_name    = 'STEAM TURBINE MCC_J32-9'
on conflict (equipment_id, switch_device_id) do nothing;

update equipment
set description = 'ST NEUTRAL SIDE CUBICLE HEATER (MKA10GE021) — J32-9(STEAM TURBINE MCC, 220V) 급전. LSC 와 한 회로다: 케이블 SL-C2-0031 한 가닥이 LSC·NSC 둘 다로 간다(도면 검증 2026-11-23). 차단기 MCCB EBS52Fb/20A.'
where equipment_name = 'ST NEUTRAL SIDE CUBICLE HEATER';

commit;

-- ---------------------------------------------------------------------------
-- 확인
-- ---------------------------------------------------------------------------
-- (가) 이번에 채운 6건이 모두 조작대상을 갖는지
select e.equipment_name, m.operation_order, d.device_name, d.group_name, d.location
from equipment e
left join equipment_switch_map m on m.equipment_id = e.id
left join switch_device d        on d.id = m.switch_device_id
where e.equipment_name in (
  '소방 JOCKEY PUMP','소방 MAIN PUMP',
  'ST CONTROL OIL TANK HEATING HEATER','ST CONTROL OIL TANK HEATING HEATER(추가)',
  'ST NEUTRAL SIDE CUBICLE HEATER'
)
order by e.equipment_name, m.operation_order;

-- (나) 조작대상이 아직 없는 기기 — ST AVR(정상)과 SCR 펌프 4대, ST EXCITER HEATER 만 남아야 한다
select e.equipment_name, e.equipment_number
from equipment e
where not exists (select 1 from equipment_switch_map m where m.equipment_id = e.id)
order by e.equipment_name;
