import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';

import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/services/media_upload_service.dart';
import 'package:party_app/utils/firestore_payload.dart';

/// 등록 화면 공통 "필수값 검증 + 첫 누락 항목으로 자동 이동" 유틸.
///
/// 화면마다 흩어져 있던 `hasError`/`firstErrorKey`/`_scrollToKey` 조합을 하나로
/// 모은 것이다. 각 화면은 **화면에 보이는 순서 그대로** [RegisterFieldCheck]
/// 목록을 만들어 [RegisterValidation.check]에 넘기기만 하면 된다.
///
/// 처리 순서:
///   1. 누락 항목을 모두 찾는다(개수를 세어 안내 문구에 쓴다).
///   2. 그중 **첫 번째**(화면 위에서 가장 먼저 나오는) 항목을 대상으로
///      접힌 섹션이면 펼치고([RegisterFieldCheck.reveal]),
///   3. 펼침이 실제로 레이아웃에 반영된 다음 프레임에 스크롤하고,
///   4. 입력칸이 있으면 포커스를 주고,
///   5. 하단에 안내 스낵바를 띄운다.
///
/// 이 함수가 false를 돌려주면 **등록 요청을 시작하면 안 된다**(로딩 상태로도
/// 들어가지 않는다) — 입력 오류와 서버 오류를 구분하기 위함이다.
class RegisterFieldCheck {
  /// 스크롤 대상 위젯의 키. 보통 섹션 앞에 둔 `SizedBox(key: ..., height: 0)`나
  /// `SectionSummaryRow.rowKey`를 그대로 쓴다.
  final GlobalKey? anchorKey;

  /// true면 이 항목이 비어 있다(= 누락).
  final bool missing;

  /// 사용자에게 보여줄 구체적인 한국어 안내.
  /// 예: '파티 날짜를 선택해주세요.', '대표 사진 / 동영상을 설정해주세요.'
  ///
  /// 입력칸 아래 오류 문구는 각 화면이 그리고, 여기 문구는 스낵바에서
  /// "무엇이 비었는지"를 한 번 더 알려주는 데 쓴다.
  final String message;

  /// 접힌 섹션 펼치기 등 "오류가 실제로 보이게" 만드는 동작.
  /// [missing]이 참인 첫 항목에 대해서만 호출된다.
  final VoidCallback? reveal;

  /// 이동 후 커서를 놓을 입력칸.
  final FocusNode? focusNode;

  /// 이 항목이 들어 있는 **스크롤 목록의 컨트롤러**.
  ///
  /// 등록 화면 본문은 대부분 [ListView]인데, ListView는 화면 밖 항목을
  /// **아예 만들지 않는다**. 그래서 아래쪽 섹션의 [anchorKey]는
  /// `currentContext`가 null이고, [Scrollable.ensureVisible]에 넘길 것이
  /// 없어 누락 항목을 눌러도 아무 일도 일어나지 않았다(상품의 취소·환불
  /// 규정이 바로 그 경우다).
  ///
  /// 컨트롤러를 주면 [RegisterValidation.goTo]가 **그 위젯이 만들어질 때까지
  /// 목록을 훑어 내려간 뒤** 정확한 위치로 맞춘다. 주지 않으면 예전과 같이
  /// "이미 만들어져 있으면 이동"만 한다.
  final ScrollController? scrollController;

  const RegisterFieldCheck({
    required this.missing,
    required this.message,
    this.anchorKey,
    this.reveal,
    this.focusNode,
    this.scrollController,
  });
}

/// "이 앵커를 잠깐 강조해줘" 요청 하나.
///
/// [serial]을 함께 드는 이유는 하나다 — 같은 항목을 연달아 눌렀을 때
/// 앵커 키만 보면 값이 그대로라 아무 일도 일어나지 않는다(다시 반짝이지
/// 않는다). 번호가 달라지므로 매번 새 요청으로 읽힌다.
@immutable
class RegisterHighlightRequest {
  const RegisterHighlightRequest(this.anchorKey, this.serial);

  final Object anchorKey;
  final int serial;
}

class RegisterValidation {
  RegisterValidation._();

  /// 서버 저장/네트워크 실패에 공통으로 쓰는 문구.
  /// 예외 원문(FirebaseException 메시지 등)은 절대 사용자에게 노출하지 않는다.
  static const String submitFailedMessage = '등록 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.';

  /// 누락 항목 개수에 맞는 안내 문구.
  static String summaryMessage(int missingCount) => missingCount > 1
      ? '필수 항목 $missingCount개를 확인해주세요.'
      : '입력하지 않은 필수 항목이 있어요. 표시된 항목을 확인해주세요.';

  /// 비어 있는 항목들의 안내 문구 — 화면 상단 배너에 목록으로 보여줄 때 쓴다.
  /// 스낵바는 금방 사라져서 "뭐가 빠졌는지" 확인하기 어렵기 때문이다.
  static List<String> missingMessages(List<RegisterFieldCheck> checks) =>
      checks.where((c) => c.missing).map((c) => c.message).toList();

  /// 비어 있는 항목 자체 — 배너가 각 줄을 눌렀을 때 그 입력칸으로 이동시키려면
  /// 문구뿐 아니라 앵커/펼치기 동작까지 필요해서 항목을 통째로 넘긴다.
  static List<RegisterFieldCheck> missingFields(
    List<RegisterFieldCheck> checks,
  ) => checks.where((c) => c.missing).toList();

  /// **지금 강조해 보여줄 앵커** — [RegisterFieldAnchor]가 이 값을 듣는다.
  ///
  /// 이동만 하면 화면이 바뀐 것은 알겠는데 "어디로 온 것인지"는 알기 어렵다.
  /// 그래서 도착한 영역에 잠깐 테두리를 둘러 준다. 어느 영역을 강조할지는
  /// 앵커 키 하나로 정해지므로, 이동 대상과 강조 대상이 갈라질 수 없다.
  ///
  /// ⚠️ **끄는 타이머는 여기 없다.** 강조를 끄는 일은 [RegisterFieldAnchor]가
  /// 자기 [State] 안에서 한다 — 여기(전역)에 타이머를 두면 화면이 사라진
  /// 뒤에도 살아남아, 테스트에서는 "타이머가 아직 있다"로 걸리고 실제
  /// 앱에서는 이미 없는 화면을 향해 계속 알림을 쏜다.
  static final ValueNotifier<RegisterHighlightRequest?> highlightRequest =
      ValueNotifier<RegisterHighlightRequest?>(null);

  /// 강조가 켜져 있는 시간.
  static const Duration highlightDuration = Duration(milliseconds: 1800);

  /// 요청 일련번호 — 같은 곳을 연달아 눌러도 값이 달라져야 다시 반짝인다.
  static int _highlightSerial = 0;

  /// 화면 밖 위젯을 찾느라 목록을 훑는 최대 횟수 — 무한 루프 방지용 상한이다
  /// (한 번에 뷰포트의 80%씩 움직이므로, 아무리 긴 폼이어도 이 안에 든다).
  static const int _maxMaterializeSteps = 24;

  /// 특정 항목의 입력 영역으로 이동한다. 배너의 각 줄과 [check]가 **똑같이**
  /// 이 경로를 쓰므로, 문구와 이동 위치가 화면마다 갈라질 수 없다.
  ///
  /// 순서가 중요하다:
  ///   1. 접힌 섹션이면 먼저 펼친다([RegisterFieldCheck.reveal]).
  ///   2. **키보드를 내린다** — 열려 있으면 뷰포트 높이가 곧 달라져서, 맞춰
  ///      둔 스크롤 위치가 키보드가 닫히는 만큼 그대로 어긋난다.
  ///   3. 화면 밖이라 아직 만들어지지 않은 위젯이면 목록을 훑어 내려가
  ///      **만들어질 때까지** 기다린다([RegisterFieldCheck.scrollController]).
  ///   4. 정확한 위치로 부드럽게 맞춘다.
  ///   5. 도착한 영역을 잠깐 강조하고, 입력칸이 있으면 커서를 놓는다.
  static Future<void> goTo(RegisterFieldCheck field) async {
    field.reveal?.call();

    final focused = FocusManager.instance.primaryFocus;
    if (focused != null && focused.hasPrimaryFocus) focused.unfocus();
    await _nextFrame();

    await _materialize(field);

    final ctx = field.anchorKey?.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.05,
      );
    }

    highlight(field.anchorKey);
    field.focusNode?.requestFocus();
  }

  /// [goTo]와 **완전히 같은 경로**로 한 앵커에 데려다 놓는다 — 다만 배너에
  /// 남길 문구가 없는 경우에 쓴다.
  ///
  /// "비어 있음"이 아니라 "값이 서로 안 맞음"(얼리버드 기간, 라운드 정원,
  /// 룸 카드 내부 검증 등)은 [RegisterFieldCheck] 목록에 넣지 않고 각 화면이
  /// 따로 안내한다. 그때도 이동만큼은 같아야 한다 — 예전에는 [scrollTo]를
  /// 썼는데, 그 자리가 아직 화면 밖이라 만들어지지 않았으면(ListView) 넘길
  /// context가 없어 **아무 일도 일어나지 않았다**.
  static Future<void> goToAnchor(
    GlobalKey? anchorKey, {
    ScrollController? scrollController,
    VoidCallback? reveal,
    FocusNode? focusNode,
  }) => goTo(
    RegisterFieldCheck(
      missing: true,
      message: '',
      anchorKey: anchorKey,
      reveal: reveal,
      focusNode: focusNode,
      scrollController: scrollController,
    ),
  );

  /// 도착한 영역을 잠깐 강조한다. 같은 키를 가진 [RegisterFieldAnchor]나
  /// [SectionSummaryRow]가 스스로 테두리를 그렸다 지운다.
  static void highlight(Object? anchorKey) {
    if (anchorKey == null) return;
    highlightRequest.value = RegisterHighlightRequest(
      anchorKey,
      ++_highlightSerial,
    );
  }

  /// 강조 요청을 지운다 — 화면을 떠날 때 불러 남은 요청이 다음 화면으로
  /// 새지 않게 한다(끄는 타이머는 앵커가 자기 것으로 이미 갖고 있다).
  static void clearHighlight() => highlightRequest.value = null;

  /// 앵커 위젯이 **트리에 실제로 만들어지도록** 목록을 훑는다.
  ///
  /// [ListView]는 화면 밖 항목을 만들지 않으므로, 아래쪽 섹션은 스크롤해
  /// 다가가기 전까지 존재하지 않는다. 아래로 훑어 끝까지 못 찾으면 맨 위로
  /// 올라가 다시 훑는다 — 목표가 현재 위치보다 위에 있을 수도 있어서다.
  static Future<void> _materialize(RegisterFieldCheck field) async {
    final key = field.anchorKey;
    if (key == null || key.currentContext != null) return;

    final ctrl = field.scrollController;
    if (ctrl == null || !ctrl.hasClients) {
      // 컨트롤러가 없으면 예전 동작 그대로 — 다음 프레임에 한 번 더 본다
      // (펼침 애니메이션 중이라 아직 없는 경우).
      await _nextFrame();
      return;
    }

    if (await _sweepDown(key, ctrl)) return;

    if (ctrl.hasClients && ctrl.position.pixels > 0) {
      ctrl.jumpTo(0);
      await _nextFrame();
      if (key.currentContext != null) return;
      await _sweepDown(key, ctrl);
    }
  }

  /// 한 번에 뷰포트의 80%씩 내려가며 [key]가 만들어졌는지 본다.
  /// 찾았으면 true, 끝까지 못 찾았으면 false.
  static Future<bool> _sweepDown(GlobalKey key, ScrollController ctrl) async {
    for (var step = 0; step < _maxMaterializeSteps; step++) {
      if (key.currentContext != null) return true;
      if (!ctrl.hasClients) return false;
      final pos = ctrl.position;
      if (pos.pixels >= pos.maxScrollExtent) return key.currentContext != null;
      ctrl.jumpTo(
        math.min(pos.pixels + pos.viewportDimension * 0.8, pos.maxScrollExtent),
      );
      await _nextFrame();
    }
    return key.currentContext != null;
  }

  static Future<void> _nextFrame() => WidgetsBinding.instance.endOfFrame;

  /// 등록 실패 원인을 사용자가 이해할 수 있는 문구로 바꾼다.
  ///
  /// 예외 원문은 절대 그대로 보여주지 않되, **원인 갈래는 구분해서** 안내한다 —
  /// "등록 중 문제가 발생했습니다"만 반복되면 사용자도 개발자도 무엇이 잘못됐는지
  /// 알 수 없기 때문이다. 분류가 안 되는 경우에만 짧은 코드를 덧붙여 제보에
  /// 쓸 수 있게 한다.
  ///
  /// [stage]는 실패한 단계('업로드' | '저장')로, 문구 앞에 붙는다.
  /// 특정 사진 파일 때문에 업로드가 막혔을 때의 안내.
  /// "다시 시도"로는 절대 풀리지 않는 상황이라 행동을 콕 집어 알려준다.
  static const String unusableMediaMessage =
      '선택한 사진 중 업로드할 수 없는 파일이 있습니다. 해당 사진을 삭제한 뒤 다시 추가해주세요.';

  /// 업로드 서비스 자체가 우리를 인증해주지 못하는 상황(토큰 만료 등).
  /// 사용자가 사진을 바꿔도 해결되지 않으므로 사진을 지우라고 하면 안 된다.
  static const String uploadServiceAuthMessage =
      '파일 업로드 서비스에 연결하지 못했어요. 잠시 후 다시 시도해주세요. (문제가 계속되면 문의해주세요)';

  /// 서버가 사용자에게 그대로 보여줘도 되는 문구를 붙여 보냈으면 그것.
  /// 공용 업로더를 거치며 [MediaUploadException]에 감싸인 경우까지 본다.
  static String? _serverUserMessage(Object error) {
    Object? candidate = error;
    if (candidate is MediaUploadException) candidate = candidate.cause;
    if (candidate == null) return null;
    if (candidate is CloudflareUploadException) {
      final message = candidate.userMessage?.trim();
      if (message != null && message.isNotEmpty) return message;
    }
    return null;
  }

  static String failureMessage(Object error, {String? stage}) {
    final prefix = stage == null ? '' : '$stage 중 ';

    // 저장할 수 없는 값이 payload에 섞인 경우 — 사용자가 다시 눌러도 절대
    // 풀리지 않는 앱 버그다. 로그에는 문제 필드 이름이 그대로 남아 있으므로
    // 사용자에게는 "재시도해도 소용없다"는 것만 분명히 알린다.
    if (error is FirestorePayloadException) {
      return '입력한 내용 중 저장할 수 없는 항목이 있어요. '
          '앱을 최신 버전으로 업데이트하거나 문의해주세요.';
    }

    // 서버가 이미 "무엇을 고쳐야 하는지"를 문장으로 만들어 준 실패는 그
    // 문장을 그대로 쓴다(예: "파일이 너무 큽니다. 최대 10MB까지 올릴 수
    // 있어요."). 이런 것까지 아래 갈래별 기본 문구로 뭉개면 호스트는 사진을
    // 바꿔야 하는지 기다려야 하는지 알 수 없다. 값이 없으면(=예전 경로)
    // 아무것도 달라지지 않는다.
    final serverMessage = _serverUserMessage(error);
    if (serverMessage != null) return serverMessage;

    // 업로드 단계 실패는 원인이 갈린다 — 파일이 문제면 그 사진을 빼야 하고,
    // 인증/네트워크가 문제면 사진을 지워도 소용없다. 섞어서 안내하면
    // 멀쩡한 사진을 지우게 만든다.
    if (error is MediaUploadException) {
      if (error.isFileProblem) return unusableMediaMessage;
      switch (error.reason) {
        case MediaUploadFailureReason.auth:
          return uploadServiceAuthMessage;
        case MediaUploadFailureReason.network:
          return '네트워크 연결이 불안정해요. 연결을 확인한 뒤 다시 시도해주세요.';
        default:
          return '$prefix문제가 발생했습니다. 잠시 후 다시 시도해주세요.';
      }
    }

    // 아직 공통 업로더를 거치지 않는 화면(이벤트/마켓 등록 등)에서 올라오는
    // 원본 Cloudflare 예외도 같은 갈래로 안내한다.
    if (MediaUploadService.classify(error) == MediaUploadFailureReason.auth) {
      return uploadServiceAuthMessage;
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return '등록 권한을 확인하지 못했어요. 로그아웃 후 다시 로그인한 뒤 시도해주세요.';
        case 'unauthenticated':
          return '로그인이 만료됐어요. 다시 로그인한 뒤 시도해주세요.';
        case 'unavailable':
        case 'deadline-exceeded':
          return '네트워크가 불안정해요. 연결을 확인한 뒤 다시 시도해주세요.';
        case 'resource-exhausted':
          return '요청이 많아 잠시 지연되고 있어요. 잠시 후 다시 시도해주세요.';
        default:
          return '$prefix문제가 발생했습니다. 잠시 후 다시 시도해주세요. (${error.code})';
      }
    }

    // 네트워크 계열(소켓/타임아웃) — 클래스 이름으로 판별한다(패키지 의존 없이).
    final typeName = error.runtimeType.toString();
    if (error is TimeoutException ||
        typeName.contains('SocketException') ||
        typeName.contains('ClientException') ||
        typeName.contains('HandshakeException')) {
      return '네트워크 연결이 불안정해요. 연결을 확인한 뒤 다시 시도해주세요.';
    }

    if (stage != null) {
      return '$prefix문제가 발생했습니다. 잠시 후 다시 시도해주세요.';
    }
    return submitFailedMessage;
  }

  /// 모든 항목이 채워졌으면 true. 누락이 있으면 첫 항목으로 이동시키고
  /// 안내를 띄운 뒤 false를 돌려준다.
  ///
  /// [checks]는 **화면에 나타나는 순서대로** 넘겨야 한다 — 목록 순서가 곧
  /// "가장 위에 있는 누락 항목"의 기준이 된다.
  ///
  /// 판정은 즉시 끝나고(동기) 스크롤·포커스는 다음 프레임에 이어진다 —
  /// 호출부가 400ms짜리 스크롤 애니메이션을 기다릴 이유가 없기 때문이다.
  static bool check(BuildContext context, List<RegisterFieldCheck> checks) {
    final missing = checks.where((c) => c.missing).toList();
    if (missing.isEmpty) return true;

    final first = missing.first;
    // 스낵바에는 요약이 아니라 **첫 누락 항목의 구체적인 문구**를 그대로
    // 띄운다 — "필수 항목 2개를 확인해주세요"만 보면 어디가 문제인지 알 수
    // 없기 때문이다(나머지는 상단 배너 목록에 남는다).
    showMessage(
      context,
      missing.length > 1
          ? '${first.message} (확인할 항목 ${missing.length}개)'
          : first.message,
    );

    // 접힌 섹션 펼치기·키보드 내리기·스크롤은 다음 프레임부터 이어진다 —
    // 호출부가 그 애니메이션을 기다릴 이유가 없으므로 결과를 기다리지 않는다.
    // 배너의 각 줄을 눌렀을 때와 **완전히 같은 경로**다.
    unawaited(goTo(first));
    return false;
  }

  /// [key]가 가리키는 위젯이 화면에 보이도록 스크롤한다.
  /// 아직 트리에 없으면(펼침 애니메이션 중 등) 다음 프레임에 한 번 재시도한다.
  static void scrollTo(GlobalKey? key) {
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final retry = key.currentContext;
        if (retry != null && retry.mounted) _ensureVisible(retry);
      });
      return;
    }
    if (ctx.mounted) _ensureVisible(ctx);
  }

  static void _ensureVisible(BuildContext ctx) {
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  static void showMessage(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
  }
}
