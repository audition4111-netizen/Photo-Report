# -*- coding: utf-8 -*-
"""도면 찾기 — 11,000여 자료의 색인에서 이름·경로로 좁힌다.

  python -I .redtag-index/find.py MCC SCHEDULE
  python -I .redtag-index/find.py --elec GSUT          전기 관련만
  python -I .redtag-index/find.py --ext pdf --root VDCL 52CG
  python -I .redtag-index/find.py --limit 100 "LOAD LIST"

낱말을 여러 개 주면 모두 들어 있는 것만 나온다(순서·대소문자 무관).

⚠️ 전기 도면은 '전기분야' 폴더에만 있지 않다. 기계·계측제어·토목 폴더에도
   ELEC·단선도·MCC·PANEL 같은 전기 자료가 2,700여 건 흩어져 있다
   (VDCL 기계분야에만 354건). --elec 는 폴더가 아니라 **제목과 경로의 낱말**로
   가려내므로 그런 것들까지 같이 잡는다. 폴더만 보고 판단하지 말 것.
"""
import io, json, os, sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

HERE = os.path.dirname(os.path.abspath(__file__))
rows = json.load(io.open(os.path.join(HERE, 'drawings.json'), encoding='utf-8'))

args, ext, root, limit, elec = [], None, None, 40, False
it = iter(sys.argv[1:])
for a in it:
    if a == '--ext':     ext = next(it, '').lower().lstrip('.')
    elif a == '--root':  root = next(it, '').lower()
    elif a == '--limit': limit = int(next(it, '40'))
    elif a == '--elec':  elec = True
    else: args.append(a.lower())

if not args:
    print(__doc__)
    print('색인 %d건 (전기 관련 표시 %d건). 최상위:'
          % (len(rows), sum(1 for r in rows if r.get('elec'))))
    seen = {}
    for r in rows:
        k = r['root']
        seen[k] = seen.get(k, 0) + 1
    for k, v in sorted(seen.items(), key=lambda x: -x[1]):
        print('   %-30s %5d' % (k, v))
    sys.exit(0)

hits = []
for r in rows:
    if elec and not r.get('elec'): continue
    if ext and r['ext'].lstrip('.') != ext: continue
    if root and root not in r['root'].lower(): continue
    hay = (r['name'] + ' ' + r['dir']).lower()
    if all(w in hay for w in args): hits.append(r)

hits.sort(key=lambda r: (not r.get('elec'), r['ext'] != '.pdf', r['name']))
print('"%s"%s → %d건%s' % (' '.join(args), ' [전기만]' if elec else '',
                           len(hits), ' (앞 %d건)' % limit if len(hits) > limit else ''))
for r in hits[:limit]:
    print('  %s[%s] %s' % ('⚡' if r.get('elec') else '  ', r['root'], r['name']))
    print('        %s' % r['path'])
