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

  /* 적어 넣은 말을 통째로 찾으면, 사이에 글자 하나만 달라도 안 잡힌다.
     실제로 "SUT Cooling Fan" 으로는 "GT SUT. Cooling FAN #1" 이 안 나왔다
     — SUT 뒤의 마침표 하나 때문이다. 그래서 띄어쓴 낱말마다 따로 찾아
     모두 들어 있는 것만 고른다(순서도 상관없다).
     sanitize 가 , ( ) * % " ' 를 이미 떼어 내므로 아래 식이 깨지지 않는다.
     * 는 PostgREST 에서 % 와 같은 자리를 맡는다. */
  function nameMatch(q) {
    var words = q.split(' ').filter(function (w) { return w; });
    if (words.length < 2) {
      return 'equipment_name.ilike.*' + q + '*,equipment_number.ilike.*' + q + '*';
    }
    return 'and(' + words.map(function (w) {
      return 'or(equipment_name.ilike.*' + w + '*,equipment_number.ilike.*' + w + '*)';
    }).join(',') + ')';
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

    var req = c.from('equipment_switch_map')
      .select(
        'operation_order,operation_type,remarks,' +
        'equipment:equipment_id!inner(id,equipment_name,equipment_number,equipment_type,sub_type,voltage_class),' +
        'switch:switch_device_id!inner(id,device_name,group_name,location,device_type,device_subtype,voltage_class,default_operation,description)'
      )
      .or(nameMatch(q), { referencedTable: 'equipment' });

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

  /* ---- 쓰지 않는 예비 회로 가리기 ------------------------------------------
     빈 피더까지 다 보이면 목록이 쓸데없이 길어진다. 다만 "예비" 라는 말만
     보고 지우면 위험하다 — 사송 예비선로(VCB-201 · LBS-201 · LC-2_ACB-201)는
     이름에 "예비" 가 들어가지만 정전 때 반드시 조작하는 것들이다.

     그래서 **두 가지가 동시에** 맞을 때만 뺀다:
       ① 설명에 SPARE / 예비 로 적혀 있고 ("SPARE 아님" 이라고 확인해 둔 것은 뺀다)
       ② 점검대상이 하나도 안 붙어 있다
     쓰이는 회로에는 점검대상이 붙어 있으므로 ②가 안전장치 노릇을 한다.
     실제로 이 규칙은 338건을 가리고, 점검대상이 붙은 예비선로 22건은 남긴다.

     ⚠️ 위치가 비어 있다고 예비로 보지는 않는다. 위치가 빈 346건 중 41건
        (W.T MCC · W.W.T MCC · GT PEECC MCC)은 차단기 규격까지 적힌 멀쩡한
        피더로, 점검대상만 아직 안 붙었을 뿐이다. 그건 그대로 보여 준다. */
  var SPARE_RE = /SPARE|예비/i;

  function looksSpare(d) {
    var t = (d && d.description) || '';
    if (t.indexOf('SPARE 아님') !== -1 || t.indexOf('SPARE아님') !== -1) return false;
    return SPARE_RE.test(t) || SPARE_RE.test((d && d.device_name) || '');
  }

  function fetchAllDevices(site) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('조작대상 데이터에 연결되어 있지 않습니다.'));
    var all = [];

    function page(from) {
      var req = c.from('switch_device')
        .select('id,device_name,group_name,location,voltage_class,device_type,default_operation,description')
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
  /* 어느 조작대상에 점검대상이 붙어 있는지 — 예비를 가릴 때 쓴다 */
  function mappedIds() {
    if (mappedCache) return Promise.resolve(mappedCache);
    var c = getClient();
    return fetchAllPaged(function (a, b) {
      return c.from('equipment_switch_map')
        .select('switch_device_id')
        .order('switch_device_id', { ascending: true })
        .range(a, b);
    }).then(function (rows) {
      var set = {};
      rows.forEach(function (m) { set[m.switch_device_id] = 1; });
      mappedCache = set;
      return set;
    });
  }
  var mappedCache = null;

  function listGroups(site) {
    if (groupCache[site]) return Promise.resolve(groupCache[site]);

    return Promise.all([fetchAllDevices(site), mappedIds()]).then(function (both) {
      var data = both[0], mapped = both[1];
      var byVolt = {};
      data.forEach(function (d) {
        if (!mapped[d.id] && looksSpare(d)) return;   // 쓰지 않는 예비
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
  /* 배전반 하나를 펼친다.
     ⚠️ 연결표(equipment_switch_map)에서 출발하면 점검대상이 아직 안 붙은
        조작대상이 통째로 사라진다 — 실제로 1,478건 중 462건이 그렇고,
        배전반 머리의 건수와 펼친 줄 수가 어긋나 있었다(CT MOV 54 vs 40).
        그래서 조작대상에서 출발해 연결을 나중에 붙인다. 안 붙은 것도
        "점검대상 미지정" 으로 그대로 내보낸다 — 안 보이면 없는 줄 안다. */
  /* volt 를 주면 그 전압등급만 가져온다. 배전반 하나가 여러 전압을 품는 일이
     있어서(#1 CONTROL BLDG MCC 는 460V 와 220V 를 함께 가진다), 전압등급을
     고르고 들어왔는데 다른 전압까지 쏟아져 나오던 것을 막는다. */
  function listFeeders(site, group, volt) {
    var c = getClient();
    if (!c) return Promise.reject(new Error('조작대상 데이터에 연결되어 있지 않습니다.'));

    var devs = fetchAllPaged(function (a, b) {
      var q = c.from('switch_device')
        .select('id,device_name,group_name,location,device_type,device_subtype,' +
                'voltage_class,default_operation,description')
        .order('device_name', { ascending: true })
        .range(a, b);
      q = group === NO_GROUP ? q.is('group_name', null) : q.eq('group_name', group);
      if (volt) q = volt === '기타' ? q.is('voltage_class', null) : q.eq('voltage_class', volt);
      return site === 'sasong'
        ? q.ilike('location', '%사송%')
        : q.or('location.not.ilike.%사송%,location.is.null');
    });

    return devs.then(function (list) {
      if (!list.length) return [];
      var ids = list.map(function (d) { return d.id; });

      return fetchAllPaged(function (a, b) {
        return c.from('equipment_switch_map')
          .select('switch_device_id,operation_order,operation_type,remarks,' +
                  'equipment:equipment_id(id,equipment_name,equipment_number,' +
                  'equipment_type,sub_type,voltage_class)')
          .in('switch_device_id', ids)
          .order('switch_device_id', { ascending: true })
          .range(a, b);
      }).then(function (links) {
        var byDev = {};
        links.forEach(function (m) {
          (byDev[m.switch_device_id] = byDev[m.switch_device_id] || []).push(m);
        });

        var rows = [];
        list.forEach(function (d) {
          var mine = byDev[d.id];
          if (mine && mine.length) {
            mine.forEach(function (m) {
              rows.push(toRow({ operation_order: m.operation_order,
                                operation_type: m.operation_type,
                                remarks: m.remarks,
                                equipment: m.equipment, switch: d }));
            });
          } else if (!looksSpare(d)) {
            // 점검대상이 아직 안 붙은 조작대상 — 예비가 아니면 숨기지 않는다
            var r = toRow({ switch: d });
            r.noEquipment = true;
            rows.push(r);
          }
        });

        rows.sort(function (a, b) {
          return a.deviceName.localeCompare(b.deviceName, 'ko', { numeric: true }) ||
                 (a.order - b.order);
        });
        return rows;
      });
    });
  }

  /* ---- 점검대상(기기)으로 찾기 ---------------------------------------------
     배전반 쪽은 "차단기가 어디 있나" 로 찾아가는 길이고, 이쪽은 "무슨 설비가
     있나" 로 훑는 길이다. 펌프 종류를 쭉 보고 싶을 때는 이쪽이 맞다.

     ⚠️ 하나라도 빠지면 안 되는 자료다. 조작대상이 아직 연결되지 않은 기기도
        숨기지 않고 그대로 보여 주고 그렇다고 적는다 — 안 보이면 없는 줄 안다. */
  var EQ_TYPE_ORDER = ['GT 발전기', 'ST 발전기', '발전기', 'GIS', '변압기',
                       '수배전반', '전동기', '부속기기'];
  var UNKNOWN_SITE = '(사업장 미상)';

  var eqCache = {};

  function fetchAllPaged(build) {
    var all = [];
    function page(from) {
      return build(from, from + PAGE - 1).then(function (res) {
        if (res.error) throw res.error;
        var got = res.data || [];
        all = all.concat(got);
        return got.length === PAGE ? page(from + PAGE) : all;
      });
    }
    return page(0);
  }

  /* 기기와 그 기기의 조작대상을 한꺼번에 받아 종류별로 묶는다.
     기기 표에는 사업장 칸이 없어서, 그 기기를 끊는 차단기가 어디 있는지로
     사업장을 가린다. 차단기가 아직 없는 기기는 가릴 수가 없어 양쪽 모두에
     "사업장 미상" 으로 둔다 — 빠뜨리는 것보다 낫다. */
  function listEquipment(site) {
    if (eqCache[site]) return Promise.resolve(eqCache[site]);
    var c = getClient();
    if (!c) return Promise.reject(new Error('조작대상 데이터에 연결되어 있지 않습니다.'));

    var eqs = fetchAllPaged(function (a, b) {
      return c.from('equipment')
        .select('id,equipment_name,equipment_number,equipment_type,sub_type,facility_group,voltage_class')
        .order('equipment_name', { ascending: true })
        .range(a, b);
    });

    var maps = fetchAllPaged(function (a, b) {
      return c.from('equipment_switch_map')
        .select('equipment_id,operation_order,operation_type,remarks,' +
                'switch:switch_device_id(id,device_name,group_name,location,device_type,device_subtype,voltage_class,default_operation,description)')
        .order('equipment_id', { ascending: true })
        .range(a, b);
    });

    return Promise.all([eqs, maps]).then(function (both) {
      var equipment = both[0], links = both[1];

      var feedersOf = {};
      links.forEach(function (m) {
        var sw = m.switch;
        if (!sw) return;
        var row = toRow({ operation_order: m.operation_order, operation_type: m.operation_type,
                          remarks: m.remarks, switch: sw, equipment: null });
        (feedersOf[m.equipment_id] = feedersOf[m.equipment_id] || []).push(row);
      });

      var byType = {};
      var counts = { total: 0, noFeeder: 0 };
      equipment.forEach(function (eq) {
        var mine = (feedersOf[eq.id] || []).slice();
        // 이 사업장 것만 남긴다. 차단기가 없으면 가릴 수 없으니 양쪽에 둔다.
        var here = mine.filter(function (f) { return siteOf(f) === site; });
        var belongs = mine.length ? here.length > 0 : true;
        if (!belongs) return;

        here.sort(function (a, b) {
          return (a.order - b.order) ||
                 a.deviceName.localeCompare(b.deviceName, 'ko', { numeric: true });
        });
        here.forEach(function (f) {
          f.equipmentName = eq.equipment_name;
          f.equipmentId = eq.id;
        });

        var t = eq.equipment_type || '기타';
        (byType[t] = byType[t] || []).push({
          id: eq.id,
          name: eq.equipment_name,
          number: eq.equipment_number || '',
          subType: eq.sub_type || '',
          facilityGroup: eq.facility_group || '',
          voltage: eq.voltage_class || '',
          site: mine.length ? site : UNKNOWN_SITE,
          feeders: here
        });
        counts.total += 1;
        if (!here.length) counts.noFeeder += 1;
      });

      var out = Object.keys(byType).sort(function (a, b) {
        var ia = EQ_TYPE_ORDER.indexOf(a), ib = EQ_TYPE_ORDER.indexOf(b);
        return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
      }).map(function (t) {
        var items = byType[t];
        items.sort(function (a, b) { return a.name.localeCompare(b.name, 'ko', { numeric: true }); });
        return { type: t, count: items.length, items: items };
      });

      eqCache[site] = { types: out, counts: counts };
      return eqCache[site];
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
    listEquipment: listEquipment,
    UNKNOWN_SITE: UNKNOWN_SITE,
    NO_GROUP: NO_GROUP,
    SITES: SITES,
    operationEnglish: operationEnglish
  };
})(window);
