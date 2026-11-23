-- 조작대상 찾기 — 기기명 오기 10종 바로잡기
--
-- 사용자 지시(2026-11-23): 검사팀이 찾아낸 기기명 오기를 고쳐 달라.
--
-- redtag-11 이 HEAETER → HEATER 하나를 고쳤다. 같은 성격의 오기가 열 가지 더
-- 남아 있다. 감사팀이 red-tag-manager 원본 배치 파일·검토용 엑셀·실물 DB
-- 세 곳 모두에서 같은 철자를 확인했다 — 즉 설비 마스터 시트 단계부터 들어온
-- 오기이고, 도면 판독 실수가 아니다. 그래서 도면을 다시 보지 않고 고친다.
--
--   오기            바른말          기기명(대표)
--   COUPLUNG     → COUPLING       #1/#2 BFP AOP MOTOR FOR HYDRAULIC COUPLUNG
--   COUPLNG      → COUPLING       #2 BFP ACTUATOR FOR HYDRAULIC COUPLNG
--   HEAER        → HEATER         JUNCTION BOX VOLTAGE (FOR DE/NDE HEAER POWER)
--   COMPLESSOR   → COMPRESSOR     AIR COMPLESSOR LCP-3
--   EXHUST       → EXHAUST        EXHUST STEAM SECTION DRYER
--   RECIRCULTION → RECIRCULATION  CONDENSER VACUUM PUMP RECIRCULTION PUMP #A/#B
--   TRANSSFER    → TRANSFER       HV-15060 / HV-15059 ST BLDG. B/D TRANSSFER PUMP
--   TRASFER      → TRANSFER       HRSG BD TANK TRASFER PUMP #1/#2
--   SYSTMEM      → SYSTEM         IPB (FOR GT) PRESSURED SYSTMEM LCP
--   PACKGED      → PACKAGED       2층 전기실 PACKGED AIR CONDITIONER (OUT DOOR UNIT)
--
-- 실물 DB 에서 직접 센 건수(2026-11-23, 앱의 anon 키로 조회):
--   equipment.equipment_name     14건
--   equipment.description        18행(치환 지점은 19군데 — 한 행에 EXHUST 와
--                                RECIRCULTION 이 같이 들어 있다)
--   switch_device.description     9건
--   switch_device.device_name     0건 ("HRSG MCC_K36" 꼴이라 기기명이 안 들어간다)
-- 이름과 설명이 함께 틀린 행이 13개라, 손대는 기기 행은 모두 19개다.
--
-- ⚠️ red-tag-manager 원본에는 반영돼 있지 않다. 거기서 배치를 다시 만들어
--    올리면 되살아난다(redtag-09·10·11 과 같은 사정).
--
-- ⚠️ 이름이 다른 기기와 같아지지 않는지 미리 세어 두었다.
--      수정 전: 중복 이름 97종 / 서로 다른 이름 1246개
--      수정 후: 중복 이름 97종 / 서로 다른 이름 1246개 (같은 목록)
--    RECIRCULTION → RECIRCULATION 이 기존 "CPH RECIRCULATION PUMPS #1/#2" 와
--    부딪히지 않는다(앞말이 CONDENSER VACUUM PUMP 로 다르다). COUPLNG 을 고친
--    "#2 BFP ACTUATOR FOR HYDRAULIC COUPLING" 도 기존 "#1 BFP ACTUATOR ..." 와
--    번호가 달라 겹치지 않는다. 아래 확인 3)으로 실행 뒤에도 다시 센다.
--
-- ⚠️ 함정 — 설명(description)에는 틀린 철자를 **일부러 그대로 적어 둔 판독
--    메모**가 섞여 있다. 예를 들어
--      "원문 그대로 "TRANSSFER"(오탈자로 추정, 원문 유지)"
--      "판독주의: "HEAER"로 보이나 "HEATER" 오타 가능성"
--      "원문 "SYSTMEM" 그대로 기재, 오타로 추정"
--    아래 치환은 이 메모 속 인용까지 바꿔 버린다. 실행 뒤에는 "원문 그대로
--    "TRANSFER"(원문 유지)" 처럼 앞뒤가 안 맞는 문장이 남는다. 사용자가 설명도
--    고치라고 지시해 그대로 간다. 다음 사람이 이 메모를 보고 "원문에도 맞게
--    적혀 있었다"고 읽으면 안 된다 — 원문 철자의 기록은 이 주석의 위 표뿐이다.
--
-- ⚠️ equipment_switch_map.remarks 에도 같은 오기가 9건 있다(근거·출처를 원문
--    그대로 옮겨 적은 감사 기록). 사용자가 지시한 세 곳이 아니어서 손대지
--    않았다. 아래 확인 5)에서 세기만 한다 — 고칠지는 사용자가 정할 일이다.
--
-- 여러 번 실행해도 안전하다. replace 가 바른말에는 다시 걸리지 않고(COUPLING
-- 안에 COUPLUNG·COUPLNG 이 없다), 열 가지 오기끼리도 서로 부분문자열이 아니라
-- 실행 순서가 결과를 바꾸지 않는다.
--
-- 이 파일은 실행하지 않았다. 앱의 anon 키로는 조회만 된다(redtag-01-schema.sql
-- 이 익명 쓰기를 모두 거두었다). 쓰기는 red-tag-manager 쪽에서 한다.

-- ---------------------------------------------------------------------------
-- 1) 기기 이름
-- ---------------------------------------------------------------------------
-- where 절을 반드시 둔다. redtag-07 에서 주석엔 "10건만 지운다"고 적고 조건
-- 없는 delete 를 둬서 자료를 통째로 지울 뻔한 전례가 있다.
update equipment set equipment_name = replace(equipment_name, 'COUPLUNG',     'COUPLING')      where equipment_name like '%COUPLUNG%';
update equipment set equipment_name = replace(equipment_name, 'COUPLNG',      'COUPLING')      where equipment_name like '%COUPLNG%';
update equipment set equipment_name = replace(equipment_name, 'HEAER',        'HEATER')        where equipment_name like '%HEAER%';
update equipment set equipment_name = replace(equipment_name, 'COMPLESSOR',   'COMPRESSOR')    where equipment_name like '%COMPLESSOR%';
update equipment set equipment_name = replace(equipment_name, 'EXHUST',       'EXHAUST')       where equipment_name like '%EXHUST%';
update equipment set equipment_name = replace(equipment_name, 'RECIRCULTION', 'RECIRCULATION') where equipment_name like '%RECIRCULTION%';
update equipment set equipment_name = replace(equipment_name, 'TRANSSFER',    'TRANSFER')      where equipment_name like '%TRANSSFER%';
update equipment set equipment_name = replace(equipment_name, 'TRASFER',      'TRANSFER')      where equipment_name like '%TRASFER%';
update equipment set equipment_name = replace(equipment_name, 'SYSTMEM',      'SYSTEM')        where equipment_name like '%SYSTMEM%';
update equipment set equipment_name = replace(equipment_name, 'PACKGED',      'PACKAGED')      where equipment_name like '%PACKGED%';

-- ---------------------------------------------------------------------------
-- 2) 기기 설명
-- ---------------------------------------------------------------------------
update equipment set description = replace(description, 'COUPLUNG',     'COUPLING')      where description like '%COUPLUNG%';
update equipment set description = replace(description, 'COUPLNG',      'COUPLING')      where description like '%COUPLNG%';
update equipment set description = replace(description, 'HEAER',        'HEATER')        where description like '%HEAER%';
update equipment set description = replace(description, 'COMPLESSOR',   'COMPRESSOR')    where description like '%COMPLESSOR%';
update equipment set description = replace(description, 'EXHUST',       'EXHAUST')       where description like '%EXHUST%';
update equipment set description = replace(description, 'RECIRCULTION', 'RECIRCULATION') where description like '%RECIRCULTION%';
update equipment set description = replace(description, 'TRANSSFER',    'TRANSFER')      where description like '%TRANSSFER%';
update equipment set description = replace(description, 'TRASFER',      'TRANSFER')      where description like '%TRASFER%';
update equipment set description = replace(description, 'SYSTMEM',      'SYSTEM')        where description like '%SYSTMEM%';
update equipment set description = replace(description, 'PACKGED',      'PACKAGED')      where description like '%PACKGED%';

-- ---------------------------------------------------------------------------
-- 3) 조작대상 설명
-- ---------------------------------------------------------------------------
update switch_device set description = replace(description, 'COUPLUNG',     'COUPLING')      where description like '%COUPLUNG%';
update switch_device set description = replace(description, 'COUPLNG',      'COUPLING')      where description like '%COUPLNG%';
update switch_device set description = replace(description, 'HEAER',        'HEATER')        where description like '%HEAER%';
update switch_device set description = replace(description, 'COMPLESSOR',   'COMPRESSOR')    where description like '%COMPLESSOR%';
update switch_device set description = replace(description, 'EXHUST',       'EXHAUST')       where description like '%EXHUST%';
update switch_device set description = replace(description, 'RECIRCULTION', 'RECIRCULATION') where description like '%RECIRCULTION%';
update switch_device set description = replace(description, 'TRANSSFER',    'TRANSFER')      where description like '%TRANSSFER%';
update switch_device set description = replace(description, 'TRASFER',      'TRANSFER')      where description like '%TRASFER%';
update switch_device set description = replace(description, 'SYSTMEM',      'SYSTEM')        where description like '%SYSTMEM%';
update switch_device set description = replace(description, 'PACKGED',      'PACKAGED')      where description like '%PACKGED%';

-- ---------------------------------------------------------------------------
-- 확인
-- ---------------------------------------------------------------------------
-- 1) 남은 오기 — 열 가지를 세 곳에서 모두 센다. 전부 0 이어야 한다.
select '1) 남은 오기' as 확인, t.오기,
       (select count(*) from equipment     e where e.equipment_name like '%' || t.오기 || '%') as 기기이름,
       (select count(*) from equipment     e where e.description    like '%' || t.오기 || '%') as 기기설명,
       (select count(*) from switch_device s where s.description    like '%' || t.오기 || '%') as 조작대상설명
from (values ('COUPLUNG'),('COUPLNG'),('HEAER'),('COMPLESSOR'),('EXHUST'),
             ('RECIRCULTION'),('TRANSSFER'),('TRASFER'),('SYSTMEM'),('PACKGED'),
             ('HEAETER')) as t(오기)
order by t.오기;
-- 기대: 열한 줄 모두 0 / 0 / 0
--       HEAETER 는 redtag-11 이 이미 고쳤다(2026-11-23 조회로 0 확인). 배치를
--       다시 올려 되살아나지 않았는지 여기서 같이 본다.

-- 2) 전체 건수가 그대로인지 — replace 는 행을 늘리거나 줄이지 않는다.
select '2) 전체 건수' as 확인,
       (select count(*) from equipment)            as 기기,
       (select count(*) from switch_device)        as 조작대상,
       (select count(*) from equipment_switch_map) as 연결;
-- 기대: 1358 / 1478 / 1526

-- 3) 이름이 겹치지 않는지 — 고친 이름이 다른 기기와 같아지면 화면에서
--    헷갈린다. 수정 전 기준값과 같아야 한다.
select '3) 이름 중복' as 확인,
       count(*) filter (where n > 1) as 중복이름종수,
       count(*)                      as 서로다른이름수
from (select equipment_name, count(*) as n from equipment group by equipment_name) g;
-- 기대: 97 / 1246 (수정 전과 같은 값 — 미리 세어 두었다)

-- 4) 고쳐진 이름
select '4) 고친 이름' as 확인, equipment_number, equipment_name, equipment_type
from equipment
where equipment_name like '%HYDRAULIC COUPLING%'
   or equipment_name like '%DE/NDE HEATER POWER%'
   or equipment_name like '%AIR COMPRESSOR LCP-3%'
   or equipment_name like '%EXHAUST STEAM SECTION DRYER%'
   or equipment_name like '%VACUUM PUMP RECIRCULATION PUMP%'
   or equipment_name like '%B/D TRANSFER PUMP%'
   or equipment_name like '%BD TANK TRANSFER PUMP%'
   or equipment_name like '%PRESSURED SYSTEM LCP%'
   or equipment_name like '%PACKAGED AIR CONDITIONER (OUT DOOR UNIT)%'
order by equipment_name;
-- 기대: 18줄. 고친 14줄 + 처음부터 맞게 적혀 있던 이웃 4줄이다
--       (#1 BFP ACTUATOR FOR HYDRAULIC COUPLING,
--        BFP AOP MOTOR FOR HYDRAULIC COUPLING #1/#2,
--        IPB(FOR ST)PRESSURED SYSTEM LCP).
--       이 4줄이 같은 조건에 걸리는 것이 오히려 근거다 — 고친 이름이 원래
--       맞게 적힌 이름과 같은 꼴이 되었다는 뜻이다.

-- 5) 손대지 않은 곳 — equipment_switch_map.remarks
--    고칠지 사용자가 정할 일이라 그대로 두었다. 9가 그대로 나와야 정상이다.
select '5) 손대지않음 remarks' as 확인, count(*) as 남은것
from equipment_switch_map
where remarks like '%COUPLUNG%' or remarks like '%COUPLNG%' or remarks like '%HEAER%'
   or remarks like '%COMPLESSOR%' or remarks like '%EXHUST%' or remarks like '%RECIRCULTION%'
   or remarks like '%TRANSSFER%' or remarks like '%TRASFER%' or remarks like '%SYSTMEM%'
   or remarks like '%PACKGED%';
-- 기대: 9
