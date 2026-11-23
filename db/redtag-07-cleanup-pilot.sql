-- 조작대상 찾기 — 초기 시범 데이터 비우기
--
-- ⚠️⚠️ 2026-11-23 고침 — 이 파일은 위험했다 ⚠️⚠️
--   주석에는 "시범 데이터 기기 10건·조작대상 22건만 지운다" 고 적어 두고,
--   정작 SQL 은 조건 없는 delete 네 줄이었다:
--       delete from equipment_switch_map;
--       delete from interlock;
--       delete from switch_device;
--       delete from equipment;
--   실행했다면 실제 설비 자료 전부(기기 1,358 · 조작대상 1,478 ·
--   연결 1,526 · 인터록 17)가 사라졌다. 게다가 "01~06 을 끝낸 뒤 아무
--   때나" 라고 적혀 있어 더 위험했다. 다행히 실행된 적은 없다.
--   감사 에이전트(redtag-data-auditor)가 찾아냈다.
--
--   이제 지울 이름을 하나하나 적는다. 실수로 실행해도 실제 설비는 안 다친다.
--
-- ⚠️ 그리고 **이 파일은 이제 할 일이 없다.** 2026-11-23 실물 DB 를 확인한
--    결과 아래 이름들은 한 건도 남아 있지 않다. 확정 시드로 갈아엎는
--    과정에서 이미 사라졌다. 실행해도 0건이 지워진다 — 그래도 혹시 모르니
--    안전하게 고쳐 남겨 둔다.
--
-- 무엇이었나: 구조를 시험하려고 넣었던 가짜 이름들.
-- ---------------------------------------------------------------------------

-- 시범 기기에 걸린 연결부터
delete from equipment_switch_map
 where equipment_id in (
         select id from equipment where equipment_name in
           ('GEN-1','MTR-1A','MTR-1B','SAT-1A','UAT-1',
            'GIS-154-1','CEP-1A','CWP-1A','FWP-1A','MCC-1A-01'))
    or switch_device_id in (
         select id from switch_device where device_name in
           ('CB-154-1A','CB-154-1B','CB-6.9-FWP1A','CB-6.9-CWP1A','CB-6.9-CEP1A',
            'GCB-1','DS-13.8-GEN1-1','DS-13.8-GEN1-2','ES-13.8-GEN1',
            'DS-154-1A','DS-154-1B','ES-154-1A','ES-154-1B',
            'CB-0.48-MCC1A','CB-6.9-MTR1A','CB-6.9-MTR1B',
            'DS-6.9-MTR1A','ES-6.9-MTR1A','CB-154-SAT1A','CB-13.8-UAT1',
            'DS-13.8-UAT1','ES-13.8-UAT1'));

delete from interlock
 where switch_device_id in (
         select id from switch_device where device_name in
           ('CB-154-1A','CB-154-1B','CB-6.9-FWP1A','CB-6.9-CWP1A','CB-6.9-CEP1A',
            'GCB-1','DS-13.8-GEN1-1','DS-13.8-GEN1-2','ES-13.8-GEN1',
            'DS-154-1A','DS-154-1B','ES-154-1A','ES-154-1B',
            'CB-0.48-MCC1A','CB-6.9-MTR1A','CB-6.9-MTR1B',
            'DS-6.9-MTR1A','ES-6.9-MTR1A','CB-154-SAT1A','CB-13.8-UAT1',
            'DS-13.8-UAT1','ES-13.8-UAT1'));

delete from switch_device
 where device_name in
   ('CB-154-1A','CB-154-1B','CB-6.9-FWP1A','CB-6.9-CWP1A','CB-6.9-CEP1A',
    'GCB-1','DS-13.8-GEN1-1','DS-13.8-GEN1-2','ES-13.8-GEN1',
    'DS-154-1A','DS-154-1B','ES-154-1A','ES-154-1B',
    'CB-0.48-MCC1A','CB-6.9-MTR1A','CB-6.9-MTR1B',
    'DS-6.9-MTR1A','ES-6.9-MTR1A','CB-154-SAT1A','CB-13.8-UAT1',
    'DS-13.8-UAT1','ES-13.8-UAT1');

delete from equipment
 where equipment_name in
   ('GEN-1','MTR-1A','MTR-1B','SAT-1A','UAT-1',
    'GIS-154-1','CEP-1A','CWP-1A','FWP-1A','MCC-1A-01');

-- ---------------------------------------------------------------------------
-- 확인
-- ---------------------------------------------------------------------------
-- 1) 시범 이름이 남았는지
select equipment_name from equipment where equipment_name in
  ('GEN-1','MTR-1A','MTR-1B','SAT-1A','UAT-1','GIS-154-1','CEP-1A','CWP-1A','FWP-1A','MCC-1A-01');
-- 기대: 0줄

-- 2) ★ 실제 설비는 그대로인지 — 이 숫자가 줄었으면 큰일난 것이다
select (select count(*) from equipment)            as 기기,
       (select count(*) from switch_device)        as 조작대상,
       (select count(*) from equipment_switch_map) as 연결,
       (select count(*) from interlock)            as 인터록;
-- 기대: 1358 / 1478 / 1526 / 17  (2026-11-23 기준)
