-- 조작대상 찾기 — 표 만들기 / 기존 표 손보기
--
-- 뚝DOC 에 "조작대상 찾기" 화면을 붙이기 위한 준비다. 점검할 기기 이름을 치면
-- 그 기기를 점검하려고 열고 닫아야 할 차단기·단로기·접지개폐기가, 어느 전기실에
-- 있는지와 함께 나온다.
--
-- ⚠️ 이 SQL 은 뚝DOC 의 Supabase 가 아니라 **조작대상 전용 Supabase 프로젝트**
--    (pqiqfdzcrrvagkccqnpz)에서 실행한다. 사진대장·매뉴얼 보관함과는 완전히 다른
--    프로젝트다. 뚝DOC 하나가 Supabase 두 개를 쓰는 구조다.
--
-- 실행 순서: 이 파일 → redtag-02 → 03 → 04 → 05 → 06 (번호대로)
--            99(검토 기록)는 선택이다.
--
-- 여러 번 실행해도 안전하다. 이 파일은 데이터를 지우지 않는다 —
-- 초기 시범 데이터(가짜 이름 32건)를 지우는 일은 redtag-07 로 따로 뺐다.

-- ---------------------------------------------------------------------------
-- 1) 표가 없으면 만든다
-- ---------------------------------------------------------------------------
-- 원본: red-tag-manager/supabase/schema.sql. 이미 표가 있는 프로젝트에서는
-- 아무 일도 일어나지 않고, 2)에서 빠진 칸을 채운다.
create table if not exists equipment (
  id               uuid primary key default gen_random_uuid(),
  equipment_name   varchar(100) not null,
  equipment_type   varchar(20)  not null,
  voltage_class    varchar(10)  not null,
  system_category  varchar(20)  not null,
  drawing_id       uuid,
  description      text,
  metadata         jsonb default '{}'::jsonb,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table if not exists switch_device (
  id                 uuid primary key default gen_random_uuid(),
  device_name        varchar(100) not null,
  device_type        varchar(2)   not null,
  voltage_class      varchar(10)  not null,
  default_operation  varchar(2)   not null,
  drawing_id         uuid,
  position           jsonb,
  description        text,
  created_at         timestamptz not null default now()
);

create table if not exists equipment_switch_map (
  id                 uuid primary key default gen_random_uuid(),
  equipment_id       uuid not null references equipment (id) on delete cascade,
  switch_device_id   uuid not null references switch_device (id) on delete cascade,
  operation_order    integer not null,
  operation_type     varchar(2) not null,
  remarks            text,
  created_at         timestamptz not null default now(),
  unique (equipment_id, switch_device_id)
);

create table if not exists interlock (
  id                       uuid primary key default gen_random_uuid(),
  source_equipment_id      uuid not null references equipment (id) on delete cascade,
  target_equipment_id      uuid not null references equipment (id) on delete cascade,
  interlock_type           varchar(20) not null,
  description              text,
  created_at               timestamptz not null default now()
);

create table if not exists sld_drawing (
  id               uuid primary key default gen_random_uuid(),
  drawing_name     varchar(100) not null,
  drawing_number   varchar(50),
  file_path        text not null,
  voltage_class    varchar(10),
  system_type      varchar(20),
  metadata         jsonb default '{}'::jsonb,
  created_at       timestamptz not null default now()
);

create table if not exists confirmed_review_row (
  id                 uuid primary key default gen_random_uuid(),
  batch              integer not null,
  source_file        text not null,
  row_no             integer not null,
  equipment_id       uuid references equipment (id) on delete set null,
  switch_device_id   uuid references switch_device (id) on delete set null,
  row_data           jsonb not null,
  confirmed_on       date,
  created_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 2) 예전에 만들어진 표에 빠진 칸을 채운다
-- ---------------------------------------------------------------------------
-- 이 프로젝트는 초기 시범 단계에서 만들어진 터라 그 뒤에 추가된 칸들이 없다.
-- 시드가 이 칸들에 값을 넣으므로, 먼저 만들어 두지 않으면 시드가 통째로 실패한다.
alter table equipment     add column if not exists equipment_number varchar(50);
alter table equipment     add column if not exists sub_type         varchar(50);
alter table equipment     add column if not exists facility_group   varchar(20);

alter table switch_device add column if not exists device_number    varchar(50);
alter table switch_device add column if not exists device_subtype   varchar(10);
alter table switch_device add column if not exists metadata         jsonb default '{}'::jsonb;

-- 이 화면이 보여 줄 두 가지. 없으면 "어디 가서 찾지?" 를 못 알려 준다.
alter table switch_device add column if not exists location         varchar(50);
alter table switch_device add column if not exists group_name       varchar(30);

comment on column switch_device.location is
  '이 차단기가 물리적으로 있는 전기실·건물. 예: "관리동 1층 전기실".';
comment on column switch_device.group_name is
  'device_name 의 "_" 앞부분(예: SWGR-1). 플랜트에 하나뿐인 설비는 비어 있는 것이 정상.';

-- ---------------------------------------------------------------------------
-- 3) 값 제한을 시드에 맞춘다
-- ---------------------------------------------------------------------------
-- 초기 표에는 값 목록이 좁게 잡혀 있다. 그 뒤에 늘어난 값(13.8kV·22.9kV,
-- 수배전반·부속기기 …)이 들어가면 막히므로, 원본 스키마(red-tag-manager/
-- supabase/schema.sql)의 목록 전부를 그대로 다시 건다.
--
-- ⚠️ 하나씩 짚어 고치지 말고 전부 다시 걸 것. 전압만 넓히고 기기 종류를
--    빠뜨렸다가 시드가 중간에 통째로 막힌 적이 있다.
alter table equipment     drop constraint if exists equipment_equipment_type_check;
alter table equipment     add  constraint equipment_equipment_type_check
  check (equipment_type in ('GIS','변압기','발전기','전동기','부속기기','수배전반'));

alter table equipment     drop constraint if exists equipment_system_category_check;
alter table equipment     add  constraint equipment_system_category_check
  check (system_category in ('전력설비','전동기설비'));

alter table equipment     drop constraint if exists equipment_facility_group_check;
alter table equipment     add  constraint equipment_facility_group_check
  check (facility_group in ('SWGR','LC','MCC','몰드변압기'));

alter table equipment     drop constraint if exists equipment_voltage_class_check;
alter table equipment     add  constraint equipment_voltage_class_check
  check (voltage_class in ('154kV','22.9kV','13.8kV','6.9kV','460V','220V','125V','110V'));

alter table switch_device drop constraint if exists switch_device_device_type_check;
alter table switch_device add  constraint switch_device_device_type_check
  check (device_type in ('CB','DS','ES'));

alter table switch_device drop constraint if exists switch_device_default_operation_check;
alter table switch_device add  constraint switch_device_default_operation_check
  check (default_operation in ('개방','투입'));

alter table switch_device drop constraint if exists switch_device_voltage_class_check;
alter table switch_device add  constraint switch_device_voltage_class_check
  check (voltage_class in ('154kV','22.9kV','13.8kV','6.9kV','460V','220V','125V','110V'));

alter table equipment_switch_map drop constraint if exists equipment_switch_map_operation_type_check;
alter table equipment_switch_map add  constraint equipment_switch_map_operation_type_check
  check (operation_type in ('개방','투입'));

alter table sld_drawing   drop constraint if exists sld_drawing_voltage_class_check;
alter table sld_drawing   add  constraint sld_drawing_voltage_class_check
  check (voltage_class in ('154kV','22.9kV','13.8kV','6.9kV','460V','220V','125V','110V'));

-- 서로 다른 기기가 같은 이름을 쓰는 경우가 있다(예: MCC 마다 하나씩 있는
-- SPACE HEATER POWER). 이름으로 막아 두면 확정 데이터가 안 들어간다.
drop index if exists equipment_name_uidx;
create index if not exists equipment_name_idx on equipment (equipment_name);

-- 조작대상도 마찬가지다. 양산 열원과 사송가압장은 서로 다른 사업장이라
-- 각자 ES-101·LC-1_ACB-101 같은 이름을 쓴다(사송 쪽은 지역 접두어가 없다).
-- 이름으로 막으면 사송 데이터가 통째로 안 들어간다.
--
-- ⚠️ 대신 이름만으로는 어느 사업장 것인지 가릴 수 없게 된다. 화면에서는
--    위치 칸이 구분해 주고, 엑셀도 위치를 보고 양산·사송 시트를 나눈다.
drop index if exists switch_device_name_uidx;
create index if not exists switch_device_name_idx on switch_device (device_name);

-- ---------------------------------------------------------------------------
-- 4) 검색이 빠르도록
-- ---------------------------------------------------------------------------
-- 기기명·기기번호를 "포함" 으로 찾으므로 일반 인덱스로는 느리다. trigram 으로
-- 가운데 글자 검색도 인덱스를 타게 한다.
create extension if not exists pg_trgm;

create index if not exists equipment_name_trgm_idx
  on equipment using gin (equipment_name gin_trgm_ops);
create index if not exists equipment_number_trgm_idx
  on equipment using gin (equipment_number gin_trgm_ops);
create index if not exists equipment_switch_map_equipment_idx
  on equipment_switch_map (equipment_id, operation_order);
create index if not exists switch_device_group_idx on switch_device (group_name);

-- ---------------------------------------------------------------------------
-- 5) 읽기만 열고 쓰기는 모두 막는다  ❗ 꼭 실행해야 한다
-- ---------------------------------------------------------------------------
-- 뚝DOC 은 브라우저에서 직접 이 프로젝트를 읽는다. 그러려면 공개 키가 앱 파일에
-- 들어가고, 그 파일은 공개 저장소에 올라간다 — 즉 키는 누구나 보게 된다.
-- 원래 그러라고 있는 키지만(Supabase 의 publishable 키), 실제 방어는 아래 권한이
-- 한다. 이걸 걸지 않으면 키를 본 사람이 몇 달 걸려 확정한 정전조작 데이터를
-- 지우거나 고칠 수 있다.
--
-- 확인해 보니 이 프로젝트는 지금 익명 쓰기가 열려 있다(insert/update/delete 전부
-- 통과). 그래서 읽기 정책만 더하는 것으로는 부족하고, 먼저 쓰기를 거둬야 한다.
--
-- 데이터 갱신은 앞으로도 red-tag-manager 에서 SQL 로만 한다.

-- ① 테이블 권한 자체를 조회만 남기고 거둔다
revoke all on equipment, switch_device, equipment_switch_map, interlock, sld_drawing,
              confirmed_review_row
  from anon, authenticated;

-- ② 혹시 남아 있을 수 있는 "누구나 쓰기" 정책을 걷어낸다
do $cleanup$
declare p record;
begin
  for p in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('equipment','switch_device','equipment_switch_map',
                        'interlock','sld_drawing','confirmed_review_row')
      and cmd <> 'SELECT'
  loop
    execute format('drop policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;
end
$cleanup$;

alter table equipment            enable row level security;
alter table switch_device        enable row level security;
alter table equipment_switch_map enable row level security;
alter table interlock            enable row level security;
alter table sld_drawing          enable row level security;

drop policy if exists "redtag_read_equipment"   on equipment;
create policy "redtag_read_equipment"   on equipment            for select to public using (true);
drop policy if exists "redtag_read_switch"      on switch_device;
create policy "redtag_read_switch"      on switch_device        for select to public using (true);
drop policy if exists "redtag_read_map"         on equipment_switch_map;
create policy "redtag_read_map"         on equipment_switch_map for select to public using (true);
drop policy if exists "redtag_read_interlock"   on interlock;
create policy "redtag_read_interlock"   on interlock            for select to public using (true);
drop policy if exists "redtag_read_drawing"     on sld_drawing;
create policy "redtag_read_drawing"     on sld_drawing          for select to public using (true);

-- ③ 조회만 돌려준다
grant usage on schema public to anon, authenticated;
grant select on equipment, switch_device, equipment_switch_map, interlock, sld_drawing
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 확인
-- ---------------------------------------------------------------------------
-- 1) 칸이 다 생겼는지
select table_name, column_name
from information_schema.columns
where table_schema = 'public'
  and (table_name = 'switch_device' and column_name in ('location','group_name','device_number','device_subtype')
    or table_name = 'equipment'     and column_name in ('equipment_number','sub_type','facility_group'))
order by table_name, column_name;
-- 기대: 7줄

-- 2) 쓰기가 정말 막혔는지 — 실행 뒤 아래가 0줄이어야 한다
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('equipment','switch_device','equipment_switch_map')
  and grantee in ('anon','authenticated')
  and privilege_type <> 'SELECT'
order by table_name, grantee;
-- 기대: 0줄 (조회 권한만 남아야 한다)

-- 3) 값 제한이 원본과 맞는지 — 좁으면 시드가 중간에 막힌다
select conname, pg_get_constraintdef(oid) as 정의
from pg_constraint
where conrelid in ('equipment'::regclass,'switch_device'::regclass,
                   'equipment_switch_map'::regclass,'sld_drawing'::regclass)
  and contype = 'c'
order by conname;
-- equipment_equipment_type_check 에 '수배전반','부속기기' 가 보여야 한다

-- 4) 지금 들어 있는 양
select
  (select count(*) from equipment)            as 기기,
  (select count(*) from switch_device)        as 조작대상,
  (select count(*) from equipment_switch_map) as 연결;
-- 시범 데이터(가짜 이름 32건)가 아직 들어 있다. 지우려면 redtag-07 을 실행한다.
-- 지우지 않아도 02~06 은 그대로 실행된다(id 가 겹치지 않는다).
