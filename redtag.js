/* 조작대상 찾기 — 데이터 읽기 전용 모듈
 *
 * 점검할 기기 이름을 치면, 그 기기를 점검하려고 열고 닫아야 할 차단기·단로기·
 * 접지개폐기가 "어디에 있는지"와 함께 나온다.
 *
 * ⚠️ 이 모듈은 보관함(archive.js)과 **다른 Supabase 프로젝트**를 본다.
 *    정전조작 데이터는 red-tag-manager 에서 몇 달에 걸쳐 확정한 별도 자료라
 *    사진대장·매뉴얼과 합치지 않고 그대로 가져다 쓴다. 연결값은
 *    supabase-config.js 의 REDTAG_CONFIG.
 *
 * 쓰기는 하지 않는다. 데이터를 고쳐야 하면 red-tag-manager 쪽에서 SQL 로 한다.
 */
(function (global) {
  'use strict';

  var client = null;

  function config() {
    return global.REDTAG_CONFIG || {};
  }

  function isEnabled() {
    var c = config();
    return !!(c.url && c.anonKey && global.supabase && global.supabase.createClient);
  }

  function getClient() {
    if (!isEnabled()) return null;
    if (!client) {
      var c = config();
      /* 보관함 쪽 클라이언트와 저장소를 공유하지 않게 해 둔다. 로그인도 쓰지
         않으므로 세션을 들고 있을 이유가 없다. */
      client = global.supabase.createClient(c.url, c.anonKey, {
        auth: { persistSession: false, autoRefreshToken: false }
      });
    }
    return client;
  }

  /* 검색어가 기기명이나 기기번호에 들어 있으면 그 기기로 본다.

     PostgREST 의 or 조건에 쓰는 값이라 쉼표·괄호가 들어오면 조건이 깨진다.
     검색어에 그런 글자를 쓸 일이 없으므로 미리 털어 낸다. */
  function sanitize(term) {
    return String(term || '').trim().replace(/[,()*%"']/g, ' ').replace(/\s+/g, ' ').trim();
  }

  /* 사업장 구분.

     양산 열원과 사송가압장은 서로 다른 사업장인데, 사송 쪽 차단기 이름에는
     지역 표시가 없어서 ES-101·LC-1_ACB-101 처럼 양산 것과 똑같은 이름이 있다.
     이름만으로는 가릴 수 없으므로 "어느 사업장을 보는 중인지" 를 먼저 고르게
     하고, 그 사업장 것만 찾는다. 섞이지 않으면 헷갈릴 일도 없다.

     가르는 기준은 차단기가 실제로 놓인 자리(location)다. 대장도 조작이
     일어나는 사업장 기준으로 나뉘므로 이것이 맞다.
     위치가 비어 있는 것들(HRSG MCC, #1 CONTROL BLDG MCC 등)은 전부 양산
     설비라 양산으로 본다 — 사송은 위치가 모두 채워져 있다. */
  var SITES = {
    yangsan: { label: '양산 열원',   sheet: 'Tag 대장(양산 열원)' },
    sasong:  { label: '사송 가압장', sheet: 'TAG 대장(사송 가압장)' }
  };

  function siteOf(row) {
    return (row && (row.location || '')).indexOf('사송') !== -1 ? 'sasong' : 'yangsan';
  }

  /* 기기 찾기 → 그 기기들의 조작대상까지 한 번에.

     equipment_switch_map 을 가운데 두고 양쪽을 끌어온다. inner 로 묶어 조건에
     맞는 행만 남긴다 — 기기는 검색어로, 조작대상은 사업장으로 걸러진다. */
  function search(term, site) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('조작대상 데이터에 연결되어 있지 않습니다.'));

    var q = sanitize(term);
    if (!q) return Promise.resolve([]);
    var like = '%' + q + '%';

    var req = c.from('equipment_switch_map')
      .select(
        'operation_order,operation_type,remarks,' +
        'equipment:equipment_id!inner(id,equipment_name,equipment_number,equipment_type,sub_type,voltage_class),' +
        'switch:switch_device_id!inner(id,device_name,group_name,location,device_type,device_subtype,voltage_class,default_operation,description)'
      )
      .or('equipment_name.ilike.' + like + ',equipment_number.ilike.' + like,
          { referencedTable: 'equipment' });

    if (site === 'sasong') {
      req = req.ilike('switch.location', '%사송%');
    } else {
      // 위치가 비어 있는 것도 양산으로 본다
      req = req.or('location.not.ilike.%사송%,location.is.null',
                   { referencedTable: 'switch' });
    }

    return req
      .order('operation_order', { ascending: true })
      .limit(500)
      .then(function (res) {
        if (res.error) throw res.error;
        return (res.data || []).map(toRow).filter(function (r) { return r.deviceName; });
      });
  }

  function toRow(raw) {
    var eq = raw.equipment || {};
    var sw = raw.switch || {};
    return {
      equipmentId: eq.id,
      equipmentName: eq.equipment_name || '',
      equipmentNumber: eq.equipment_number || '',
      equipmentType: eq.equipment_type || '',
      subType: eq.sub_type || '',
      deviceId: sw.id,
      deviceName: sw.device_name || '',
      groupName: sw.group_name || '',
      location: sw.location || '',
      deviceType: sw.device_type || '',
      deviceSubtype: sw.device_subtype || '',
      voltage: sw.voltage_class || '',
      /* 조작 방향은 연결(map)에 적힌 값이 최종이다. 같은 차단기라도 어느 기기를
         점검하느냐에 따라 달라질 수 있어 차단기 자체의 기본값보다 앞선다. */
      operation: raw.operation_type || sw.default_operation || '',
      order: raw.operation_order || 0,
      remarks: raw.remarks || '',
      description: sw.description || ''
    };
  }

  // 사송가압장 것인지 — 엑셀 시트를 나눠 담을 때 쓴다
  function isSasong(row) {
    return siteOf(row) === 'sasong';
  }

  // 개방 → OPEN, 투입 → CLOSE (관리대장 표기)
  function operationEnglish(op) {
    if (op === '개방') return 'OPEN';
    if (op === '투입') return 'CLOSE';
    return op || '';
  }

  global.RedTag = {
    isEnabled: isEnabled,
    search: search,
    isSasong: isSasong,
    siteOf: siteOf,
    SITES: SITES,
    operationEnglish: operationEnglish
  };
})(window);
