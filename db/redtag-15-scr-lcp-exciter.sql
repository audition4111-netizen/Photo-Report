-- SCR 판넬 내부 MCCB 4개와 여자기 히터 — 마지막 남은 조작대상을 채운다
--
-- 사용자 지침(2026-11-23)
--   · "Reducing 과 Ammonia Pump 들은 판넬 내부 460V MCCB 를 내리는 컨셉으로
--      지정해 주면 돼. UPS 전원은 컨트롤전원이라 굳이 내릴 필요는 없어.
--      460V MCCB 만 내려도 전동기 기동이 안 되기 때문에 충분히 작업이 가능해.
--      대신 그룹명에 Local Pnl 명을 지정해서 위치도 지정해 줬으면 좋겠어."
--   · ST EXCITER HEATER 는 "벤더 도면 → EDCL Cable Schedule 의 From-To →
--      Interconnection Wiring" 순서로 찾으라는 방법을 알려 주셨다. 그대로 따라가
--      찾았다.
--
-- ---------------------------------------------------------------------------
-- 1) SCR & YPES LCP — 판넬 내부 MCCB 4개 【확실】
-- ---------------------------------------------------------------------------
-- 근거: 403-1-E-VD-633-605-3-2 (SHEET 2/23, AS-BUILT Rev.2, 2023-06-14,
--       제작 대영씨엔이㈜) 단선도 직접 판독. 단선도 심볼 옆 표기와 하단
--       TAG No./FEEDER NAME 표 양쪽에서 교차확인.
--
--   K23(HRSG MCC) → LCP 메인 MCCB ABH 100AF/30AT
--                 → MCCB 01~04 (각 ABS 33AF/5AT) → 인버터 0.75kW → 전동기
--
--   MCCB 01  633-M-PP-001  AMMONIA SUPPLY PUMP #1
--   MCCB 02  633-M-PP-002  AMMONIA SUPPLY PUMP #2
--   MCCB 03  633-M-PP-003  REDUCING AGENT SUPPLY PUMP #1
--   MCCB 04  633-M-PP-004  REDUCING AGENT SUPPLY PUMP #2
--   ELCB 05  633-M-HT-001  AMMONIA DILUTION TANK HEATER (이번 대상 아님)
--   MCCB 06  SPARE
--
-- 전동기 4대 모두 인버터(LSLV008S100-4) 경유다. MCCB 를 내리면 인버터와
-- 전동기가 함께 무전압이 된다 — 그래서 이것이 조작점으로 맞다.
--
-- UPS 220V 제어전원(444-E-DP-002 ← HL-C2-0027, 판넬 안 UPS MCCB ABS 32AF/10AT)은
-- 460V 동력계통과 완전히 분리된 별도 계통이다. 전동기를 세우는 데는 필요 없다
-- (사용자 지침 그대로). 판넬 **안쪽**을 손대는 작업이면 이것도 끊어야 한다.
--
-- ⚠️ 도면 표기는 하이픈 없는 `MCCB 01` 이다. 2026 대장의 "MCCB-01(SCR PNL)" 은
--    하이픈이 덧붙은 표기다. 도면을 따랐다.
--
-- ⚠️ 벤더 Electrical Load List(403-1-E-VD-633-605-9 Rev.1) 한 건만 전동기
--    번호를 반대로(PP-001/2=환원제, PP-003/4=암모니아) 적고 있다. AS-BUILT
--    단선도·Cable Schedule·Power Layout·General Layout·P&ID 다섯 건이 모두
--    "PP-001/2=암모니아, PP-003/4=환원제" 로 일치하므로 그쪽을 따랐다.
--    아래 배정은 **기기번호로** 하므로 이름이 어떻든 어긋나지 않는다.
--
-- ---------------------------------------------------------------------------
-- 2) ST EXCITER HEATER — 지난번 "넣으면 안 된다" 를 뒤집는다 【확실】
-- ---------------------------------------------------------------------------
-- 지난번에는 "J32-3 의 기기번호는 MKA10GE030 이고 엑셀의 히터는 MKC20GE010 —
-- 다른 기기이므로 넣으면 안 된다" 고 보고했다. **그 판단이 틀렸다.**
--
-- MKC20GE010 은 히터가 아니라 **여자기 접속함(Junction Box)** 이고, 그 안에
-- 성격이 다른 두 회로가 들어 있다:
--
--   -X4   계자권선 직류  ← AVR 반 CGA10-X05 에서 DC 71.5V/12.1A
--                          (케이블 CGA10_WL003, Rev.4 까지 HOLD)
--   -X41  여자기 히터    ← 접속함 MKA10GE030 경유 220V AC
--           (히터 본체는 MKC20AH010-R1/R2, 각 230V 100W)
--
-- 지난번에 "케이블 상태 HOLD" 로 막힌 것은 **계자 DC 회로**였다. 히터 회로는
-- 그 케이블이 아니다 — 정상 등재되어 있다:
--
--   435-E-DP-1901 (220V ST MCC Aux.TR 분전반) B03 / 부하LIST J32-3
--     ─ SL-C2-0018 (TFR-CV 2C-4sq, 100m) → MKA10GE030-X01:13
--       → MKA10GE030-X0:3,6,PE "TO EXCITER HEATER"
--         → MKC20GE010-X41 → MKC20AH010-R1 / -R2
--
-- 근거(세 단계 모두 눈으로 판독)
--   ① 벤더: Siemens DPPPG-70212481 "JUNCTION BOX VOLTAGE" Page 43/82,
--      DPPPG-70212485 "JUNCTION BOX EXCITER FIELD; HEATER" 단자표 Page 55/82
--      (01_YangSan_CHP_EG000511_Installation_Manual_Rev_B.pdf p551 / p563)
--   ② EDCL Cable Schedule 403-1-E-CK-035-001 Rev.4 — 케이블 SL-C2-0018
--      From 435-E-DP-1901 / To MKA10GE030
--   ③ EDCL IWD 403-1-E-CW-035-001 Rev.2 시트 "8.4 0.46kV ST MCC" —
--      435-E-DP-1901 B03 →(SL-C2-0018)→ MKA10GE030-X01:13
--
-- ⚠️ 이 차단기 하나에 **여자기 히터 + 여자기 후드등 + MTB 큐비클 히터**가
--    함께 물려 있다. 내리면 셋 다 꺼진다. 아래 remarks 에 적는다.
--
-- ⚠️ 계자 DC(-X4) 를 다루는 작업이면 조작점이 전혀 다르다 — AVR 반 CGA10
--    (주제어동 3층 전자기기실)의 FIELD BREAKER 다. MCC 피더가 아니다.
--    그쪽은 아직 조작대상으로 등록하지 않았다.
--
-- 여러 번 돌려도 안전하다. 실행 순서: 01~14 뒤.

begin;

-- ---------------------------------------------------------------------------
-- 1) SCR & YPES LCP 의 분기차단기 4개를 만든다
-- ---------------------------------------------------------------------------
insert into switch_device
  (device_name, device_type, device_subtype, voltage_class, default_operation,
   group_name, location, description)
select v.device_name, 'CB', 'MCCB', '460V', '개방',
       'SCR & YPES LCP', 'SCR 설비구역(옥외) 펌프스테이션', v.description
from (values
  ('SCR & YPES LCP_MCCB 01',
   '633-M-PP-001 AMMONIA SUPPLY PUMP #1 분기. MCCB: ABS 33AF/5AT. 인버터 0.75kW(LSLV008S100-4) 경유 — 이것을 내리면 인버터와 전동기가 함께 무전압이 된다. 판넬 메인은 ABH 100AF/30AT, 수전은 HRSG MCC_K23. 판넬 내부 작업이면 UPS 220V 제어전원(판넬 안 UPS MCCB ABS 32AF/10AT, 444-E-DP-002 급전)도 끊어야 한다. 출처: 403-1-E-VD-633-605-3-2(SHEET 2/23, AS-BUILT Rev.2, 2023-06-14) 직접 판독.'),
  ('SCR & YPES LCP_MCCB 02',
   '633-M-PP-002 AMMONIA SUPPLY PUMP #2 분기. MCCB: ABS 33AF/5AT. 인버터 0.75kW(LSLV008S100-4) 경유. 판넬 메인 ABH 100AF/30AT, 수전 HRSG MCC_K23. 출처: 403-1-E-VD-633-605-3-2(SHEET 2/23, AS-BUILT Rev.2) 직접 판독.'),
  ('SCR & YPES LCP_MCCB 03',
   '633-M-PP-003 REDUCING AGENT SUPPLY PUMP #1 분기. MCCB: ABS 33AF/5AT. 인버터 0.75kW(LSLV008S100-4) 경유. 판넬 메인 ABH 100AF/30AT, 수전 HRSG MCC_K23. 출처: 403-1-E-VD-633-605-3-2(SHEET 2/23, AS-BUILT Rev.2) 직접 판독.'),
  ('SCR & YPES LCP_MCCB 04',
   '633-M-PP-004 REDUCING AGENT SUPPLY PUMP #2 분기. MCCB: ABS 33AF/5AT. 인버터 0.75kW(LSLV008S100-4) 경유. 판넬 메인 ABH 100AF/30AT, 수전 HRSG MCC_K23. 출처: 403-1-E-VD-633-605-3-2(SHEET 2/23, AS-BUILT Rev.2) 직접 판독.')
) as v(device_name, description)
where not exists (
  select 1 from switch_device d where d.device_name = v.device_name
);

-- 상위 피더 K23 에도 "판넬 수전" 이라는 사실을 적어 둔다.
update switch_device
set description = coalesce(description, '') ||
  ' ⚠️ 이것은 SCR & YPES LCP 로 들어가는 판넬 수전이다. 열면 암모니아·환원제 펌프 4대와 희석탱크 히터가 모두 죽는다. 펌프 한 대만 떼려면 판넬 안의 MCCB 01~04 중 해당 차단기를 연다(2026-11-23 도면 검증).'
where device_name = 'HRSG MCC_K23'
  and coalesce(description, '') not like '%판넬 안의 MCCB 01~04%';

-- ---------------------------------------------------------------------------
-- 2) 전동기 4대를 분기차단기에 붙인다 — 기기번호로 짝을 짓는다
-- ---------------------------------------------------------------------------
-- 이름이 자료마다 흔들리므로(SUPPLY / INJECTION) 기기번호를 기준으로 붙인다.
insert into equipment_switch_map
  (equipment_id, switch_device_id, operation_order, operation_type, remarks)
select e.id, d.id, 1, '개방',
       '판넬 안의 분기 MCCB 다. 상위 수전(HRSG MCC_K23)을 열면 펌프 4대가 모두 죽는다. 인버터 경유라 이 차단기를 내리면 인버터도 함께 무전압이 된다.'
from (values
  ('633-M-PP-001','SCR & YPES LCP_MCCB 01'),
  ('633-M-PP-002','SCR & YPES LCP_MCCB 02'),
  ('633-M-PP-003','SCR & YPES LCP_MCCB 03'),
  ('633-M-PP-004','SCR & YPES LCP_MCCB 04')
) as v(eq_number, sw_name)
join equipment     e on e.equipment_number = v.eq_number
join switch_device d on d.device_name      = v.sw_name
on conflict (equipment_id, switch_device_id) do nothing;

-- ---------------------------------------------------------------------------
-- 3) ST EXCITER HEATER → STEAM TURBINE MCC_J32-3
-- ---------------------------------------------------------------------------
insert into equipment_switch_map
  (equipment_id, switch_device_id, operation_order, operation_type, remarks)
select e.id, d.id, 1, '개방',
       '⚠️ 이 차단기 하나에 여자기 히터·여자기 후드등·MTB 큐비클 히터가 함께 물려 있다 — 내리면 셋 다 꺼진다. 히터 본체는 MKC20AH010-R1/R2 이고, 접속함 MKA10GE030 을 거쳐 MKC20GE010-X41 로 들어간다. 같은 접속함의 -X4(계자권선 직류)는 전혀 다른 회로다 — 그쪽 조작점은 AVR 반 CGA10(주제어동 3층 전자기기실)이다.'
from equipment e, switch_device d
where e.equipment_name = 'ST EXCITER HEATER'
  and d.device_name    = 'STEAM TURBINE MCC_J32-3'
on conflict (equipment_id, switch_device_id) do nothing;

-- 기기 설명을 바로잡는다. 이름(MKC20GE010 단독 표기)은 사용자 확인 전까지
-- 그대로 둔다 — 아래 '남은 확인거리' 참고.
update equipment
set description = 'ST EXCITER HEATER — 히터 본체는 MKC20AH010-R1/R2(각 230V 100W, 운전 220V 91.5W). J32-3(STEAM TURBINE MCC 220V 분전반 435-E-DP-1901, 반 쪽 차단기 번호 B03) 급전: SL-C2-0018 → 접속함 MKA10GE030-X01:13 → -X0:3,6,PE "TO EXCITER HEATER" → MKC20GE010-X41. ⚠️ 같은 차단기에 여자기 후드등·MTB 큐비클 히터가 함께 물린다. ⚠️ 기기번호 MKC20GE010 은 히터가 아니라 여자기 접속함이다 — 그 안의 -X4 는 계자권선 직류(AVR 반 CGA10-X05, DC 71.5V/12.1A, 케이블 CGA10_WL003 은 Rev.4 까지 HOLD)로 전혀 다른 회로다. 근거: Siemens DPPPG-70212481 p43/82 · DPPPG-70212485 p55/82 + EDCL Cable Schedule 403-1-E-CK-035-001 Rev.4(SL-C2-0018) + IWD 403-1-E-CW-035-001 Rev.2 시트 8.4 (도면 검증 2026-11-23).'
where equipment_name = 'ST EXCITER HEATER';

commit;

-- ---------------------------------------------------------------------------
-- 확인
-- ---------------------------------------------------------------------------
-- (가) 이번에 채운 5건 — 다섯 줄이 모두 조작대상을 가져야 한다
select e.equipment_name, e.equipment_number, d.device_name, d.group_name, d.location
from equipment e
join equipment_switch_map m on m.equipment_id = e.id
join switch_device d        on d.id = m.switch_device_id
where e.equipment_number in ('633-M-PP-001','633-M-PP-002','633-M-PP-003','633-M-PP-004')
   or e.equipment_name = 'ST EXCITER HEATER'
order by e.equipment_number nulls last, e.equipment_name;

-- (나) 조작대상이 아직 없는 기기 — ST AVR 하나만 남아야 한다(자여자라 정상)
select e.equipment_name, e.equipment_number
from equipment e
where not exists (select 1 from equipment_switch_map m where m.equipment_id = e.id)
order by e.equipment_name;

-- (다) 전체 건수 — 기기 1358 / 조작대상 1490 / 연결 1517 이 되어야 한다
select
  (select count(*) from equipment)            as 기기,
  (select count(*) from switch_device)        as 조작대상,
  (select count(*) from equipment_switch_map) as 연결;

-- ---------------------------------------------------------------------------
-- 남은 확인거리 — 사용자 확인 전까지 손대지 않은 것
-- ---------------------------------------------------------------------------
--  (1) 기기명 'ST EXCITER HEATER' 의 기기번호를 MKC20GE010(접속함) 에서
--      MKC20AH010-R1/R2(히터 본체) 로 바꿀지
--  (2) 차단기 명판이 B03 인지 J32-3 인지 (실반 확인 필요)
--  (3) LCP 기기번호 633-E-LP-001(벤더 전 도면) vs 633-M-LP-001(EDCL·현재 DB)
--  (4) 전동기 이름 'REDUCING AGENT INJECTION PUMP' vs 도면 'REDUCING AGENT
--      SUPPLY PUMP' — 어느 쪽으로 통일할지
--  (5) 계자 DC(CGA10 FIELD BREAKER)를 조작대상으로 따로 등록할지
