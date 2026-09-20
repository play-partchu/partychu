import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────
// 등록 화면의 입력칸을 **자리가 아니라 이름으로** 찾는 도구.
//
// 예전에는 여러 테스트가 `find.byType(TextField).first`를 "이름 칸"으로 삼았다.
// 폼 맨 위에 다른 입력칸(파티츄 혜택 등)이 하나 생기는 순간 그 가정이 조용히
// 깨지는데, 실패 메시지는 "저장된 이름이 ''이다"로 나와서 **제품이 고장 난
// 것처럼** 보인다. 실제로는 테스트가 엉뚱한 칸에 글자를 넣고 있었다.
//
// 그래서 힌트 문구(InputDecoration.hintText)로 찾는다. 힌트는 그 칸이 무엇을
// 받는 칸인지 말하는 값이고, 화면 순서가 바뀌어도 따라 움직인다.
//
// ⚠️ 화면에 그려진 힌트 **글자**를 찾지 않는다(`find.widgetWithText`). 힌트는
//    칸이 비어 있을 때만 그려지므로, 값이 채워진 뒤에는 찾을 수 없다 —
//    임시저장 복원처럼 "이미 채워진 칸을 읽어 보는" 검사가 그래서 깨진다.
//    여기서는 위젯의 decoration 속성을 직접 보므로 비어 있든 채워져 있든
//    똑같이 찾힌다.
// ─────────────────────────────────────────────────────────────────────────

/// 힌트 문구가 [hint]인 [TextField]. 값이 채워져 있어도 찾힌다.
///
/// `TextFormField`가 만든 칸도 함께 걸린다 — 내부적으로 같은 decoration을 가진
/// [TextField]를 만들기 때문이다(PartyTitleField 등).
Finder fieldWithHint(String hint) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == hint,
  description: 'TextField(hint: "$hint")',
);

/// 힌트로 찾은 칸에 지금 들어 있는 글자.
String textInField(WidgetTester tester, String hint) =>
    tester.widget<TextField>(fieldWithHint(hint)).controller?.text ?? '';

// ── 등록 화면별 "이름/제목" 칸의 힌트 ────────────────────────────────
//
// 제품 문구를 그대로 옮겨 적은 상수다. 문구가 바뀌면 이 파일 한 곳만 고치면
// 되고, 고치지 않으면 `fieldWithHint`가 아무것도 못 찾아 **그 자리에서**
// 실패한다("이름이 ''"처럼 엉뚱한 곳에서 터지지 않는다).

/// 플레이스 등록(`events`) — 플레이스 제목(매장 이름).
const kEventNameHint = '예: 파티츄 2호 혼술바';

/// 장소대여 등록(`places`) — 장소명.
const kPlaceNameHint = '예: 한강뷰 루프탑 파티룸';

/// 파티샵 등록 — 샵 이름.
const kMarketNameHint = '샵 이름을 입력해주세요';

/// 파티 등록 — 파티 제목.
const kPartyTitleHint = '예: 한강 야경 드라이브 번개';

/// 룸(객실) 카드 — 룸 이름.
const kRoomNameHint = '예: VIP 룸, 루프탑, 1번 룸';

/// 파티크루 등록(구인) — 제목.
const kCrewRecruitTitleHint = '예: 10월 할로윈 파티 DJ 구인합니다';

/// 파티크루 등록(구직) — 제목.
const kCrewSeekTitleHint = '예: 파티 MC 경력 3년, 활동 가능합니다';
