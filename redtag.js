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

  /* ---- 목록으로 찾기 -------------------------------------------------------
     이름을 정확히 모르면 검색이 막막하다. 그래서 단선도를 따라가듯
     전압등급 → 배전반(그룹) → 피더 로 펼쳐 보고 고를 수 있게 한다.
     현장에서 차단기를 찾아가는 순서가 원래 이렇고, 확정 데이터를 배치로
     나눈 기준(GIS → SWGR → LC → MCC → MOV → UPS/DC)과도 같다. */

  // 전압은 높은 쪽부터. 목록에 없는 값이 생기면 뒤로 보낸다.
  var VOLT_ORDER = ['154kV', '22.9kV', '13.8kV', '6.9kV', '460V', '220V', '125V', '110V'];
  var NO_GROUP = '(그룹 없음 · 단독 설비)';

  var groupCache = {};   // 사업장별로 한 번만 받아 둔다

  /* 서버는 한 번에 1,000건까지만 내준다(PostgREST 기본 상한). limit 을 크게
     줘도 그 위로는 안 온다 — 실제로 6.9kV 전체가 목록에서 통째로 빠졌었다.
     그래서 끝까지 나눠 받는다. */
  var PAGE = 1000;

  function fetchAllDevices(site) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('조작대상 데이터에 연결되어 있지 않습니다.'));
    var all = [];

    function page(from) {
      var req = c.from('switch_device')
        .select('id,device_name,group_name,location,voltage_class,device_type,default_operation')
        .order('device_name', { ascending: true })
        .range(from, from + PAGE - 1);
      req = site === 'sasong'
        ? req.ilike('location', '%사송%')
        : req.or('location.not.ilike.%사송%,location.is.null');
      return req.then(function (res) {
        if (res.error) throw res.error;
        var got = res.data || [];
        all = all.concat(got);
        // 꽉 채워 왔으면 뒤가 더 있을 수 있다
        return got.length === PAGE ? page(from + PAGE) : all;
      });
    }
    return page(0);
  }

  /* 한 사업장의 조작대상을 모두 받아 전압·그룹으로 묶는다.
     PostgREST 에는 group by 가 없어 화면에서 묶는다. */
  function listGroups(site) {
    if (groupCache[site]) return Promise.resolve(groupCache[site]);

    return fetchAllDevices(site).then(function (data) {
      var byVolt = {};
      data.forEach(function (d) {
        var v = d.voltage_class || '기타';
        var g = d.group_name || NO_GROUP;
        if (!byVolt[v]) byVolt[v] = {};
        if (!byVolt[v][g]) byVolt[v][g] = { name: g, count: 0, locations: {} };
        byVolt[v][g].count += 1;
        if (d.location) byVolt[v][g].locations[d.location] = 1;
      });
      var out = Object.keys(byVolt).sort(function (a, b) {
        var ia = VOLT_ORDER.indexOf(a), ib = VOLT_ORDER.indexOf(b);
        return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
      }).map(function (v) {
        var groups = Object.keys(byVolt[v]).map(function (g) {
          var o = byVolt[v][g];
          var locs = Object.keys(o.locations);
          return { name: g, count: o.count, location: locs.length === 1 ? locs[0] : (locs[0] || '') };
        });
        /* 단독 설비 묶음은 맨 아래로, 나머지는 이름순. 숫자가 섞인 이름
           (LC-2 / LC-10)이 사전순으로 엉키지 않게 자연스러운 순서로 맞춘다. */
        groups.sort(function (a, b) {
          if (a.name === NO_GROUP) return 1;
          if (b.name === NO_GROUP) return -1;
          return a.name.localeCompare(b.name, 'ko', { numeric: true });
        });
        return { voltage: v, groups: groups,
                 count: groups.reduce(function (n, g) { return n + g.count; }, 0) };
      });
      groupCache[site] = out;
      return out;
    });
  }

  /* 고른 배전반의 피더를 그 피더가 무엇을 먹이는지와 함께 가져온다.
     점검대상 이름이 실제로 어떻게 적혀 있는지 여기서 눈으로 익히게 된다. */
  function listFeeders(site, group) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('조작대상 데이터에 연결되어 있지 않습니다.'));

    var req = c.from('equipment_switch_map')
      .select(
        'operation_order,operation_type,remarks,' +
        'equipment:equipment_id(id,equipment_name,equipment_number,equipment_type,sub_type,voltage_class),' +
        'switch:switch_device_id!inner(id,device_name,group_name,location,device_type,device_subtype,voltage_class,default_operation,description)'
      )
      .limit(PAGE);

    req = group === NO_GROUP
      ? req.is('switch.group_name', null)
      : req.eq('switch.group_name', group);
    req = site === 'sasong'
      ? req.ilike('switch.location', '%사송%')
      : req.or('location.not.ilike.%사송%,location.is.null', { referencedTable: 'switch' });

    return req.then(function (res) {
      if (res.error) throw res.error;
      var rows = (res.data || []).map(toRow).filter(function (r) { return r.deviceName; });
      rows.sort(function (a, b) {
        return a.deviceName.localeCompare(b.deviceName, 'ko', { numeric: true });
      });
      return rows;
    });
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
    listGroups: listGroups,
    listFeeders: listFeeders,
    NO_GROUP: NO_GROUP,
    SITES: SITES,
    operationEnglish: operationEnglish
  };
})(window);
