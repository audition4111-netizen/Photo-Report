# 문서 보관함(Supabase) 설정 가이드

작성한 PDF를 자동으로 보관하고, 나중에 조회할 수 있게 해주는 기능입니다.
아래 5단계만 하시면 켜집니다. **설정하기 전까지는 앱이 지금과 똑같이(저장 기능 없이) 동작합니다.**

---

## 1단계 — Supabase 프로젝트 만들기

1. https://supabase.com 접속 → 회원가입(GitHub 계정으로 가능)
2. **New project** 클릭
3. 입력값
   - Name: `photo-report` (자유)
   - Database Password: 강한 비밀번호 (❗ 따로 보관해 두세요. 분실 시 재설정해야 합니다)
   - **Region: `Northeast Asia (Seoul)`** ← 반드시 서울로 (속도·데이터 위치)
4. 생성까지 1~2분 대기

> 💡 **요금**: 무료(Free) 플랜은 **1주일간 접속이 없으면 프로젝트가 자동 정지**됩니다.
> 매일 쓰지 않는 업무용이라면 Pro($25/월)를 권장합니다.
> 무료 플랜 용량: DB 500MB, 파일 1GB (이 앱 PDF 기준 약 6,000건 저장 가능)

## 2단계 — 테이블·정책 만들기

1. 좌측 메뉴 **SQL Editor** → **New query**
2. 이 저장소의 `db/schema.sql` 파일 내용을 **전부 복사해 붙여넣기**
3. **Run** 클릭 → `Success` 나오면 완료

이 SQL이 만드는 것:
- `documents` 테이블 (문서 정보)
- 조회용 인덱스 (한글 부분검색 포함)
- **RLS 보안 정책** (로그인한 사용자만 저장·조회 가능)
- `documents` 비공개 파일 버킷

## 3단계 — 로그인 설정 + 가입 도메인 제한 (@kdhc.co.kr)

1. 좌측 메뉴 **Authentication** → **Providers** → **Email** 활성화 확인
2. (선택) **Confirm email** 을 끄면 메일 인증 없이 바로 로그인됩니다.
   사내 인원만 쓴다면 꺼두는 게 편합니다.

### 3-1. 가입 도메인 제한 걸기 (❗ 반드시)

이걸 하지 않으면 **주소를 아는 누구나 아무 메일로 가입해 저장된 문서를 전부 볼 수 있습니다.**

1. **SQL Editor** → **New query** → `db/signup-domain-hook.sql` 내용을 붙여넣고 **Run**
2. **Authentication** → **Hooks** → **Before User Created**
   - 종류: **Postgres**
   - 함수: `public.hook_restrict_signup_by_email_domain`
   - **Enable** 저장
3. 잘 걸렸는지 확인 — SQL Editor 에서 실행

   ```sql
   select public.hook_restrict_signup_by_email_domain('{"user":{"email":"hong@kdhc.co.kr"}}'::jsonb);
   -- 기대 결과: {}   (가입 허용)

   select public.hook_restrict_signup_by_email_domain('{"user":{"email":"hong@gmail.com"}}'::jsonb);
   -- 기대 결과: error 403 "회사 이메일(@kdhc.co.kr)로만 가입할 수 있습니다."
   ```
4. 실제로 앱에서 개인 메일로 가입을 시도해 거부되는지도 한 번 확인해 보세요.

> ⚠️ **이 훅은 신규 가입만 막습니다.** 이전에 만들어 둔 계정은 도메인이 달라도 계속 로그인됩니다.
> 테스트로 개인 메일 계정을 만든 적이 있으면 **Authentication → Users** 에서 삭제하세요.

> 💡 허용 도메인을 추가하려면 함수를 고칠 필요 없이 표에 한 줄만 넣으면 됩니다.
> ```sql
> insert into public.signup_allowed_domains (domain) values ('example.co.kr');
> ```

## 4단계 — 앱에 연결 정보 입력

1. 좌측 메뉴 **Settings** → **API**
2. 두 값을 복사
   - **Project URL**
   - **Project API keys → `anon` `public`**
3. 이 저장소의 `supabase-config.js` 를 열어 붙여넣기

```js
window.SUPABASE_CONFIG = {
  url: 'https://xxxxxxxxxxx.supabase.co',
  anonKey: 'eyJhbGciOi...'
};
```

> ⚠️ `anon` 키는 브라우저에서 쓰도록 설계된 **공개용 키**라서 노출되어도 괜찮습니다.
> 실제 보안은 2단계에서 만든 RLS 정책이 담당합니다.
> **`service_role` 키는 절대 넣지 마세요.** 모든 보안 정책을 우회하는 마스터 키입니다.

## 5단계 — 계정 만들고 확인

1. 앱 접속 → 상단 **[로그인]** → **회원가입**
2. 이름(작성자로 표기됨)·이메일·비밀번호 입력
3. 로그인 후 아무 문서나 **PDF 출력** → "보관함에 저장했습니다" 표시 확인
4. 상단 **[보관함 조회]** → 방금 만든 문서가 보이는지 확인

---

## 조회 기능

`search.html` 에서 다음으로 조회할 수 있습니다.

| 구분 | 조회 조건 |
|---|---|
| 공통 | 문서 종류(사진대장/매뉴얼/고장 보고서) 탭, 파일명 부분검색 |
| 매뉴얼 | 매뉴얼 종류(업무·조작·운전·점검·정비), 분야 |
| 고장 보고서 | 발생일자 기간, 고장분야, 지사, 설비명, 고장내용 부분검색 |

목록에는 **작성자·작성일·개정번호**가 함께 표시되고, **[PDF 열기]** 로 원본을 볼 수 있습니다.
(비공개 버킷이므로 1시간 유효한 임시 링크로 열립니다)

---

## 알아두실 점

- **저장 실패해도 PDF는 정상 출력됩니다.** 인터넷이 끊겨 있거나 로그인하지 않았으면
  안내만 표시하고 다운로드는 그대로 진행합니다.
- **사내망(오프라인) 복사본에서는 보관 기능이 동작하지 않습니다.** 인터넷이 필요합니다.
  이때도 PDF 출력·메일 전송은 정상입니다.
- **저장되는 것은 PDF와 조회용 정보뿐입니다.** 원본 사진과 스케치는 저장되지 않으므로,
  보관된 문서를 나중에 다시 편집할 수는 없습니다. (필요해지면 추가 가능)
- 로그인하지 않아도 문서 작성·PDF 출력은 그대로 가능합니다. 로그인은 **보관·조회용**입니다.

## 문제가 생기면

| 증상 | 확인할 것 |
|---|---|
| "보관함이 아직 연결되지 않았습니다" | 4단계 `supabase-config.js` 값 확인 |
| 로그인은 되는데 저장 실패 | 2단계 SQL을 끝까지 실행했는지 (RLS 정책 누락) |
| 개인 메일로도 가입이 됨 | 3-1단계 훅이 **Enable** 되었는지, 함수명이 맞는지 확인 |
| "PDF를 열지 못했습니다" | Storage 버킷 이름이 `documents` 인지 확인 |
| 갑자기 전부 안 됨 | 무료 플랜 프로젝트가 정지되지 않았는지 (Supabase 대시보드에서 Restore) |
