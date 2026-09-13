# 파티 등록 — 앱 / 웹 파리티

앱과 웹이 **같은 파티 문서**를 만들도록 붙잡아 두는 장치와, 지금 남아 있는
차이를 적어 둔 문서다.

---

## 1. 지금 구조

```
        [앱 등록 화면]                       [웹 등록 폼]
  party_register_screen.dart            website/js/party-register.js
              │                                    │
              │ Firestore 직접 쓰기                 │ createParty(callable)
              │ (기존 경로 — 그대로 둔다)            │
              ▼                                    ▼
        parties 컬렉션  ◄──────────────  functions/partyRegistration.js
              ▲                          (정규화 · 검증 · 문서 조립)
              │
        firestore.rules
    (hostId / openState / hostBusinessVerified만 검사)
```

핵심은 **웹이 Firestore에 직접 쓰지 않는다**는 것이다. 웹이 앱과 같은 방식으로
직접 쓰면 참가비·차수·일정·얼리버드 직렬화가 세 번째로 구현되고, `firestore.rules`
의 `parties` create는 그 값을 하나도 검사하지 않으므로 어긋나도 저장이 그냥
된다. 그 어긋남은 나중에 `applyToParty`가 금액을 다르게 계산하는 형태로 터진다.

### 각 파일의 몫

| 파일 | 몫 |
|---|---|
| `functions/partyRegistration.js` | 등록 입력 → parties 문서 필드. **웹 등록의 유일한 정본** |
| `functions/index.js` → `createParty` | 인증·권한 확인 후 위 모듈을 돌리고 문서를 쓴다 |
| `functions/partyRegistration.selfcheck.js` | 모듈의 회귀 잠금 + 픽스처 생성 |
| `functions/fixtures/party_registration_cases.json` | **앱과 서버가 함께 읽는 골든 픽스처** |
| `party_app/test/party_registration_parity_test.dart` | 앱 모델이 같은 픽스처 값을 내는지 확인 |
| `functions/partyAgeRestriction.js` | 성별별 연령 제한 — 저장 필드 조립·하위호환 읽기·신청 자격의 서버 정본 |
| `party_app/lib/models/party_age_restriction.dart` | 위 파일의 앱 쪽 거울(같은 규칙) |
| `functions/partyAgeRestriction.selfcheck.js` | 두 층(조립·강제)의 회귀 잠금 |

---

## 2. 파리티를 지키는 방법

픽스처 파일 **하나**를 두 검증이 읽는다.

```bash
# 서버 쪽
cd functions && npm run check:partyregister

# 앱 쪽 (KST 환경에서)
cd party_app && flutter test test/party_registration_parity_test.dart
```

두 개가 모두 초록일 때만 "앱과 웹이 같은 문서를 만든다"고 말할 수 있다.

### 정책을 바꿀 때 순서

1. 앱 모델(`lib/models/party_*.dart`)을 고친다.
2. `functions/partyRegistration.js`의 대응 함수를 같이 고친다.
3. `cd functions && node partyRegistration.selfcheck.js --write` 로 픽스처를 다시
   만든다.
4. **반드시** Dart 파리티 테스트를 돌려 앱이 같은 값을 내는지 확인한다.
   이 단계를 건너뛰면 픽스처가 서버 출력을 그대로 베낀 셈이라 아무것도 지키지
   못한다.

2번을 빼먹으면 3번에서 회귀 잠금이 깨지고, 1번을 빼먹으면 4번에서 파리티가
깨진다. 어느 쪽이든 조용히 지나가지 않는다.

### 새 필드·새 정책을 더할 때

파티 등록에 **필드를 하나 더하는 것은 곧 픽스처를 갱신하는 일**이다. 다음 두
가지를 함께 하지 않으면 그 필드는 앱과 서버 중 한쪽에만 있는 채로 남는다.

- `functions/partyRegistration.selfcheck.js`의 `REGISTRATION_DATA_KEYS`에 새
  필드 이름을 더한다. 이 목록에 없는 필드는 **비교되지 않는다** — 조용히
  갈라질 수 있는 자리가 하나 늘어난 것과 같다.
- 그 필드가 **실제 값을 갖는** 케이스를 최소 하나 둔다. 기본값(빈 문자열,
  `null`, `{mode: 'none'}`)만 있는 케이스는 양쪽이 똑같이 비어 있기만 하면
  통과하므로 아무것도 지키지 못한다(3-1이 정확히 그 함정이었다).

### 비교에서 필드를 빼고 싶어질 때

빼지 마라. 지금 `registrationData` 비교에서 제외되는 필드는 **하나도 없고**,
그 상태가 정상이다. 예전에 예외를 하나 뒀던 적이 있는데(3-1), 그건 앱 안의 두
등록 화면이 서로 다른 값을 저장하던 **버그를 덮어두는 장치**였다. 예외를
만들고 싶어졌다면 먼저 "앱과 서버가 이 필드에서 정말 달라야 하는가"에 답해야
한다 — 대개는 고쳐야 할 버그다.

### 시간에 흔들리는 케이스를 만들지 말 것

`PartyRegistrationData.toFirestore()`는 `now`를 받지 않아 정기 파티에서
`DateTime.now()`로 다음 회차를 계산한다. 그래서 `registrationData`의 정기
케이스는 운영 기간을 **아주 먼 미래**(2099년)로 둔다 — 가까운 날짜를 쓰면
기간이 지나는 순간 어느 날 갑자기 빨개진다. 다른 섹션(`recurringSchedule`)은
`now`를 직접 넘길 수 있어 이 제약이 없다.

---

## 3. 지금 알고 있는 차이

### 3-1. `recruitOpenRule` / `recruitOpenAt` — **고쳤다 (2026-08-22)**

> 상태: 해결. 앱·서버 양쪽을 같은 동작으로 맞췄고 파리티 테스트의 예외도
> 없앴다. 같은 실수가 되풀이되지 않도록 기록만 남긴다.

**무엇이 문제였나** — `PartyRegistrationData`에 모집 시작 규칙 필드가 아예 없어서
`toFirestore()`가 `PartySchedule.buildSingleFields()`를 `openRule` 없이 불렀다.

```dart
// 고치기 전 — lib/models/party_registration_data.dart
...PartySchedule.buildSingleFields(
  singleSchedule!,
  deadlineRule: deadlineRule,   // openRule을 넘기지 않았다
),
```

그래서 저장 결과가 등록 화면마다 갈렸다.

| 등록 경로 | 고치기 전 | 고친 뒤 |
|---|---|---|
| 파티 등록 (`party_register_screen.dart`) | 값 있음 | 값 있음 |
| 플레이스+파티 콤보 (`place_party_combo_register_screen.dart`) | **항상 null** | 값 있음 |

두 화면은 **같은 일정 에디터**(`PartyScheduleSection`)를 쓴다. 즉 호스트는 콤보
등록에서도 모집 시작을 고를 수 있었는데 그 값이 저장 단계에서 조용히 버려지고
있었다 — 화면에 없는 기능이 아니라 **입력한 값이 사라지는 데이터 유실**이었다.
그 결과 콤보로 등록한 파티는 수정 화면에서 규칙이 복원되지 않았고, 서버의 모집
시작 판정에도 걸리지 않았다.

**어떻게 고쳤나** — 세 곳을 함께 고쳐야 동작이 하나가 된다.

1. `PartyRegistrationData`에 `openRule` 필드를 더하고 `buildSingleFields`에 넘긴다.
2. 콤보 등록 화면이 `_partyOpenRule`(= `_partySchedule.openRule`)을 넘기고, 슬롯마다
   `registrationOpen`(절대 시각)도 함께 계산해 넘긴다 — **규칙만 넘기면 안 된다.**
   `recruitOpenRule`은 남지만 `recruitOpenAt`이 비어 서버 판정이 여전히 갈린다.
3. 서버 `partyRegistration.js`는 이미 값을 남기는 쪽이라 그대로 두고, 파리티
   테스트의 `ignoreKeys` 예외 장치를 **통째로 제거**했다. 지금은 비교에서 빠지는
   필드가 하나도 없다.

**지금 이 필드를 지키는 것** — `registrationData` 픽스처 케이스가 실제 규칙
(`prevDayTime`)을 쓰도록 바꿨다. `{mode: 'none'}`만 있으면 두 필드가 늘 null이라
회귀가 잡히지 않는다. **비어 있는 값으로는 아무것도 지킬 수 없다.**

**곁다리로 함께 고친 것** — 정기 파티 `registrationData` 케이스의 운영 기간을
2099년으로 옮겼다. `PartyRegistrationData.toFirestore()`는 `now`를 받지 않아
`DateTime.now()`로 다음 회차를 계산하므로, 운영 기간이 가까우면 **테스트를 돌린
날짜에 따라 기대값이 흔들린다**(기간이 지나면 어느 날 갑자기 빨개진다). 시작일이
한참 뒤면 `nextOccurrence`가 운영 시작일부터 훑어 결과가 항상 같다.

### 3-2. 차수 패키지 기본 이름 — 중복 차수에서 값이 갈린다

> 상태: **고치지 않는다(의도된 보류).** 지금 UI에서 실제로 발생하는 경로가
> 없어 건드리지 않고 기록만 유지하기로 했다. 중복 차수를 만들 수 있는 UI가
> 생기면 그때 아래 "고칠 때"대로 처리한다.

`PartyRoundPackage`의 두 게터가 서로 다른 목록을 본다.

```dart
String get displayName =>
    name.trim().isEmpty ? defaultNameFor(roundNumbers) : name.trim();
//                                       ^^^^^^^^^^^^ 원본 목록

List<int> get normalizedRoundNumbers => (roundNumbers.toSet().toList()..sort());
//                                                    ^^^^^^^ 중복 제거

static String defaultNameFor(List<int> roundNumbers) {
  final sorted = [...roundNumbers]..sort();   // 정렬만, 중복 제거 없음
  return '${sorted.join('+')}차 패키지';
}
```

`roundNumbers: [2, 1, 2]`로 만들면 저장되는 값이 이렇게 갈린다.

| 필드 | 값 |
|---|---|
| `roundNumbers` | `[1, 2]` |
| `name` | `1+2+2차 패키지` |

**영향** — 화면이 중복된 차수 번호를 만들지 않는 한 드러나지 않는다. 지금
등록 화면의 차수 선택 UI가 중복을 만드는 경로는 확인되지 않았다.

**공용 모듈의 선택** — `partyRegistration.js`는 이름도 중복 제거된 목록으로
만든다(`1+2차 패키지`). 픽스처에는 중복 없는 입력만 두어 두 쪽이 같은 값을
내도록 했다.

**고칠 때** — `displayName`이 `normalizedRoundNumbers`를 쓰도록 한 줄 바꾸면
된다. 이미 저장된 문서의 `name`은 그대로 남으므로 마이그레이션은 필요 없다.

---

## 4. 픽스처가 덮지 못하는 층

**문서 전체 조립** — 슬롯 팬아웃(날짜마다 문서 하나), 공유 필드, 차수 정원
합계는 앱 쪽 대응 코드가 `party_register_screen.dart` 안의 **로컬 클로저**라
(`buildRoundsField`, `buildRoundPackagesField`, `buildSlotDateFields`) 테스트에서
부를 수 없다. 그래서 이 층은 서버 셀프체크만 덮는다.

같은 이유로 `buildRoundsField`/`buildRoundPackagesField`는 이미 앱 안에서만
두 벌이다 — 파티 등록 화면과 플레이스+파티 콤보 등록 화면에 각각 복사돼 있다.

이 간극은 **앱 등록 화면이 `createParty`를 쓰도록 옮겨오면 사라진다.** 그때
Dart 모델은 순수 UI 상태가 되고, 조립 규칙은 `partyRegistration.js` 하나만
남는다. 출시 일정에 영향이 없는 시점에 하는 것이 좋다.

---

## 5. 웹 골격의 범위

`website/party/register.html` + `website/js/party-register.js`가 지금 덮는 것과
덮지 않는 것.

**덮는다** — 파티명·소개, 장소(주소 직접 입력), 날짜 슬롯 여러 개, 정기 일정,
모집 시작/마감 규칙, 성별·정원·최소 모집 인원과 미달 정책, 참가비(무료/동일/
남녀별), 얼리버드(고정 시각·시작 기준 규칙), 환불 정책 구간, 결제 방식,
연령 제한(**성별별** — 남/여 각각 범위와 제한 여부), 유형·분위기·태그, 승인제 여부.

**덮지 않는다** — 사진·동영상 업로드, 상세페이지 블록 에디터, 차수(다차수 라운드)
편집, 콤보 등록, 지도 기반 장소 검색. 전부 앱 전용 UI가 무거운 부분이고, 서버
쪽은 이미 준비돼 있으므로 웹 폼만 나중에 붙이면 된다(차수는 `createParty`가
입력을 이미 받는다 — 폼만 없다).

승인제 파티의 사전질문은 웹에서도 `setPartyApplicationForm`을 따로 부른다.
`firestore.rules`가 그 필드의 클라이언트 쓰기를 막고 있고, "개인정보를 요구하는
질문은 등록을 막는다"는 판정이 그 함수에만 있기 때문이다.


---

## 6. 연령 제한 — 성별별 스키마 (2026-08-22)

연령 제한은 파티 하나에 공통 범위 하나였다(`minBirthYear`/`maxBirthYear`).
이제 **성별마다 따로** 정한다.

| 필드 | 뜻 |
|---|---|
| `ageRestrictionEnabled` | 마스터 스위치. false면 나머지는 읽지 않는다 |
| `maleAgeRestrictionEnabled` / `maleMinBirthYear` / `maleMaxBirthYear` | 남성 제한 |
| `femaleAgeRestrictionEnabled` / `femaleMinBirthYear` / `femaleMaxBirthYear` | 여성 제한 |
| `minBirthYear` / `maxBirthYear` | **옛 공통 범위**. 기존 파티의 정본이자, 신규 파티에서는 구버전 앱을 위한 사본 |

규칙 세 가지만 기억하면 된다.

1. **읽을 때** — 성별 필드가 하나도 없는 문서는 기존 파티다. 옛 공통 범위를
   남녀 모두에게 똑같이 적용한다(`parseAgeRestriction` / `fromMap`). 기존
   파티의 연령 제한이 사라지면 안 된다.
2. **쓸 때** — 모집하지 않는 성별(`genderLimit`)의 제한은 저장 직전에
   지운다(`normalizedFor`). 호스트가 성별 모집을 바꿔도 화면에 없던 옛 값이
   적용되지 않는다. 옛 공통 필드는 모집하는 모든 성별이 제한을 가질 때만
   합집합으로 함께 쓴다 — 한쪽이 제한 없음이면 공통 범위로 표현할 수 없어
   아예 만들지 않는다.
3. **판정할 때** — 신청자는 **자기 성별의 범위만** 통과하면 된다. 성별별
   제한이 걸린 파티는 성별을 모르면 거절한다(성별을 안 보낸 직접 호출로
   우회할 수 없어야 한다). 옛 공통 파티는 예전처럼 생년만으로 판정한다.

강제 지점은 `partyCapacity.js`의 `reserveApplicantSlot` **하나**다 —
`applyToParty`와 `createPendingPackageBooking`이 둘 다 그곳을 지난다. 성별·생년은
호출부가 `users` 문서(본인확인 정본)에서 읽어 넘기므로 클라이언트가 고를 수 없다.
