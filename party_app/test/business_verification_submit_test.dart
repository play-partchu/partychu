// 사업자 인증 화면의 **제출 경로** — 인증 버튼이 실제로 서버까지 닿는가.
//
// ── 이 파일이 막는 재발 ─────────────────────────────────────────────────────
// 인증 버튼을 눌렀는데 서버 로그에 호출이 0건이고 Firestore도 그대로였던 일이
// 있었다. 그때 화면은 값을 두 벌로 들고 있었다.
//   · 사업장 기본주소만 Form 밖의 String + 별도 오류 플래그
//   · 나머지 다섯 칸은 TextFormField(= Form이 검증)
// 그래서 `_formKey.currentState.validate()`는 주소를 보지 못했고, 주소 오류는
// 스크롤 밖에서 조용히 켜졌으며, currentState가 null이면 `?? false` 하나로
// 통째로 막혔다. 사용자에게는 "눌렀는데 아무 일도 안 일어남"이었다.
//
// 여기서 고정하는 것:
//   · 기존 인증 계정이 재진입하면 저장된 값이 채워지고 **그대로 눌러도** 서버까지 간다
//   · 화면에 보이는 주소와 서버로 보내는 주소가 **같은 값**이다
//   · 주소가 비면 서버를 부르지 않고 **오류를 보여준다**
//   · 다른 필수 칸이 비어도 마찬가지다(조용한 return이 없다)
//   · 정상 입력은 콜러블을 **정확히 한 번** 부른다
//   · 연타해도 한 번뿐이다
//
// ⚠️ 서버(verifyBusinessRegistration)·firestore.rules·인증 판정은 이 파일의
//    대상이 아니다. 여기서 보는 것은 "화면이 서버를 부르는가"까지다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/models/business_verification.dart';
import 'package:party_app/screens/business_verification_screen.dart';
import 'package:party_app/services/business_verification_service.dart';
import 'package:party_app/utils/user_session.dart';

/// 운영에서 실제로 막혔던 계정과 같은 모양 — 국세청 진위는 통과(verified)했지만
/// 권한 축(authorization)이 기록되기 전에 인증을 마쳐 권한이 없다. 그래서
/// 화면은 '다시 확인하기' 폼을 저장된 값으로 채워 보여준다.
const _legacyVerified = BusinessVerification(
  status: BusinessVerificationStatus.verified,
  businessNumber: '1991003344',
  representativeName: '박효정',
  openingDate: '20260622',
  businessName: '파티츄',
  businessAddress: '서울특별시 강남구 강남대로92길 31 6층 6632호',
  businessBaseAddress: '서울특별시 강남구 강남대로92길 31',
  businessDetailAddress: '6층 6632호',
);

/// 주소를 기본/상세로 나눠 저장하기 전의 문서 — businessAddress 한 덩어리만 있다.
const _legacyOneLineAddress = BusinessVerification(
  status: BusinessVerificationStatus.verified,
  businessNumber: '1991003344',
  representativeName: '박효정',
  openingDate: '20260622',
  businessName: '파티츄',
  businessAddress: '서울특별시 강남구 강남대로92길 31',
);

const _verifiedReply = BusinessVerifyResult(
  status: BusinessVerificationStatus.verified,
  authorization: BusinessAuthorization.self,
);

const _baseAddressHint = '주소를 검색해주세요';
const _detailAddressHint = '예: 101동 1203호, 3층 파티츄';

void main() {
  /// 콜러블에 실제로 실려 나간 값들 — 한 건도 없으면 "서버를 안 불렀다"다.
  late List<Map<String, dynamic>> sent;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 인증 상태는 아래 주입점으로 고정하므로 uid는 쓰이지 않는다. 빈 값으로
    // 두면 인증 성공 뒤 이어지는 수취계좌 안내가 실물 Firestore를 건드리지
    // 않고 곧바로 '미등록'으로 떨어진다.
    UserSession.userId = '';
    sent = [];
  });

  tearDown(() {
    BusinessVerificationService.debugResetSource();
  });

  /// 저장된 인증 상태와 콜러블 응답을 고정한다.
  void use(
    BusinessVerification stored, {
    BusinessVerifyResult reply = _verifiedReply,
  }) {
    BusinessVerificationService.debugSetSource(
      fetch: () async => stored,
      verify: (payload) async {
        sent.add(payload);
        return reply;
      },
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: BusinessVerificationScreen()),
    );
    await tester.pumpAndSettle();
  }

  /// 인증 버튼 — 문구가 상태에 따라 갈리므로 종류로 잡는다(이 화면의
  /// ElevatedButton은 이것 하나뿐이다).
  final submitButton = find.byType(ElevatedButton);

  /// 인증이 통과하면 화면은 곧바로 **수취계좌 안내 다이얼로그**를 띄우고,
  /// 그것을 닫기 전까지 버튼은 진행 중 표시(끝나지 않는 애니메이션)를 유지한다.
  /// 그래서 여기서는 pumpAndSettle로 몰아가지 않고 프레임을 세어 넘긴 뒤
  /// 안내가 떠 있으면 닫는다.
  Future<void> drainFrames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final later = find.text('나중에 할게요');
    if (later.evaluate().isNotEmpty) {
      await tester.tap(later);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await drainFrames(tester);
  }

  /// 스낵바가 스스로 사라질 때까지 시간을 흘려보낸다 — 남겨 두면 타이머가
  /// 걸린 채로 테스트가 끝난다. 스낵바 문구를 본 **뒤에** 부른다.
  Future<void> settleSnack(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  /// 힌트 문구로 칸을 집어 **화면이 실제로 들고 있는 값**을 읽는다.
  String shownValueOf(WidgetTester tester, String hint) => tester
      .widgetList<TextField>(find.byType(TextField))
      .firstWhere((t) => t.decoration?.hintText == hint)
      .controller!
      .text;

  // ── 기존 인증 계정 재진입 ────────────────────────────────────────────────

  group('기존 인증 계정이 다시 확인할 때', () {
    testWidgets('저장된 값이 채워지고, 그대로 눌러도 서버까지 간다', (tester) async {
      use(_legacyVerified);
      await pump(tester);

      expect(find.text('1991003344'), findsOneWidget);
      expect(find.text('박효정'), findsWidgets);
      expect(find.text('파티츄'), findsWidgets);
      expect(find.text('서울특별시 강남구 강남대로92길 31'), findsOneWidget);
      expect(find.text('6층 6632호'), findsOneWidget);

      // 아무것도 고치지 않고 그대로 누른다 — 화면이 "그대로 두고 누르셔도
      // 됩니다"라고 말하는 바로 그 경로다.
      await tapSubmit(tester);

      expect(sent, hasLength(1), reason: '콜러블까지 닿아야 한다');
      expect(sent.single['businessNumber'], '1991003344');
      expect(sent.single['representativeName'], '박효정');
      expect(sent.single['openingDate'], '20260622');
      expect(sent.single['businessName'], '파티츄');
    });

    testWidgets('화면에 보이는 주소와 서버로 보내는 주소가 같은 값이다', (tester) async {
      use(_legacyVerified);
      await pump(tester);

      final shownBase = shownValueOf(tester, _baseAddressHint);
      final shownDetail = shownValueOf(tester, _detailAddressHint);
      expect(shownBase, '서울특별시 강남구 강남대로92길 31');
      expect(shownDetail, '6층 6632호');

      await tapSubmit(tester);

      expect(sent, hasLength(1));
      // 표시값과 전송값을 두 벌로 들면 여기서 갈린다.
      expect(sent.single['businessBaseAddress'], shownBase);
      expect(sent.single['businessDetailAddress'], shownDetail);
      expect(sent.single['businessAddress'], '$shownBase $shownDetail');
    });

    // 주소를 나눠 저장하기 전의 문서에는 상세주소가 아예 없다. 그 칸은
    // 사용자만 채울 수 있으므로 **막는 것이 맞다** — 다만 조용히 막으면 안 된다.
    testWidgets('나눠 저장하기 전 문서는 기본주소로 되살아나고, 빈 상세주소를 짚어 준다', (tester) async {
      use(_legacyOneLineAddress);
      await pump(tester);

      expect(shownValueOf(tester, _baseAddressHint), '서울특별시 강남구 강남대로92길 31');

      await tapSubmit(tester);

      expect(sent, isEmpty, reason: '빈 필수값으로는 서버를 부르지 않는다');
      expect(find.text('상세주소를 입력해주세요'), findsOneWidget);
      expect(find.text('필수 정보를 확인해주세요.'), findsOneWidget);
      await settleSnack(tester);
    });
  });

  // ── 막힐 때는 이유가 보여야 한다 ─────────────────────────────────────────

  group('필수값이 비면', () {
    testWidgets('주소가 없으면 서버를 부르지 않고 주소 칸에 오류를 보여준다', (tester) async {
      use(
        const BusinessVerification(
          status: BusinessVerificationStatus.verified,
          businessNumber: '1991003344',
          representativeName: '박효정',
          openingDate: '20260622',
          businessName: '파티츄',
          businessDetailAddress: '6층 6632호',
        ),
      );
      await pump(tester);

      await tapSubmit(tester);

      expect(sent, isEmpty);
      // 주소 칸이 Form 밖에 있으면 이 오류 문구가 나오지 않는다
      // (힌트와 같은 문구라 힌트 1 + 오류 1로 두 개다).
      expect(find.text(_baseAddressHint), findsNWidgets(2));
      expect(find.text('필수 정보를 확인해주세요.'), findsOneWidget);
      await settleSnack(tester);
    });

    testWidgets('대표자명이 비면 서버를 부르지 않고 그 칸을 짚어 준다', (tester) async {
      use(
        const BusinessVerification(
          status: BusinessVerificationStatus.verified,
          businessNumber: '1991003344',
          openingDate: '20260622',
          businessName: '파티츄',
          businessBaseAddress: '서울특별시 강남구 강남대로92길 31',
          businessDetailAddress: '6층 6632호',
        ),
      );
      await pump(tester);

      await tapSubmit(tester);

      expect(sent, isEmpty);
      expect(find.text('대표자명을 입력해주세요'), findsOneWidget);
      expect(find.text('필수 정보를 확인해주세요.'), findsOneWidget);
      await settleSnack(tester);
    });

    testWidgets('사업자등록번호가 짧으면 서버를 부르지 않는다', (tester) async {
      use(
        const BusinessVerification(
          status: BusinessVerificationStatus.verified,
          businessNumber: '199100',
          representativeName: '박효정',
          openingDate: '20260622',
          businessName: '파티츄',
          businessBaseAddress: '서울특별시 강남구 강남대로92길 31',
          businessDetailAddress: '6층 6632호',
        ),
      );
      await pump(tester);

      await tapSubmit(tester);

      expect(sent, isEmpty);
      expect(find.text('사업자등록번호 10자리를 입력해주세요'), findsOneWidget);
      expect(find.text('필수 정보를 확인해주세요.'), findsOneWidget);
      await settleSnack(tester);
    });

    // 하나 고치고 다시 눌렀을 때 나머지가 새로 나타나지 않도록 오류는 전부
    // 함께 켠다 — 화면 밖 칸도 포함해서(그래서 ListView가 아니다).
    testWidgets('여러 칸이 비면 오류를 한꺼번에 보여준다', (tester) async {
      use(
        const BusinessVerification(status: BusinessVerificationStatus.failed),
      );
      await pump(tester);

      await tapSubmit(tester);

      expect(sent, isEmpty);
      expect(find.text('사업자등록번호 10자리를 입력해주세요'), findsOneWidget);
      expect(find.text('대표자명을 입력해주세요'), findsOneWidget);
      expect(find.text('개업일자를 YYYYMMDD 형식으로 입력해주세요'), findsOneWidget);
      expect(find.text('상호명을 입력해주세요'), findsOneWidget);
      expect(find.text('상세주소를 입력해주세요'), findsOneWidget);
      await settleSnack(tester);
    });
  });

  // ── 정상 입력 ────────────────────────────────────────────────────────────

  group('정상 입력', () {
    testWidgets('빈 칸이 없으면 콜러블을 정확히 한 번 부른다', (tester) async {
      use(_legacyVerified);
      await pump(tester);

      await tapSubmit(tester);

      expect(sent, hasLength(1));
    });

    testWidgets('고쳐 넣은 값이 그대로 실려 나간다', (tester) async {
      use(_legacyVerified);
      await pump(tester);

      final repName = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '예: 홍길동',
      );
      await tester.enterText(repName, '김대표');
      await tester.pumpAndSettle();

      await tapSubmit(tester);

      expect(sent, hasLength(1));
      expect(sent.single['representativeName'], '김대표');
    });
  });

  // ── 중복 제출 ────────────────────────────────────────────────────────────

  group('중복 제출', () {
    testWidgets('연타해도 콜러블은 한 번만 나간다', (tester) async {
      // 응답을 붙잡아 두고 그 사이에 다시 누른다.
      final gate = Completer<BusinessVerifyResult>();
      BusinessVerificationService.debugSetSource(
        fetch: () async => _legacyVerified,
        verify: (payload) {
          sent.add(payload);
          return gate.future;
        },
      );
      await pump(tester);

      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pump(); // 요청은 나갔고 아직 안 돌아왔다.

      await tester.tap(submitButton, warnIfMissed: false);
      await tester.pump();
      expect(sent, hasLength(1), reason: '진행 중에는 다시 보내지 않는다');

      gate.complete(_verifiedReply);
      await drainFrames(tester);
      expect(sent, hasLength(1));
      await settleSnack(tester);
    });
  });
}
