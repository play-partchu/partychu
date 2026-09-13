import 'package:cloud_firestore/cloud_firestore.dart';

/// 고객센터 문의 — Firestore `feedbackRequests` 컬렉션 문서 모델.
///
/// 파티 신고·사용자 신고·환불 요청·결제 분쟁·긴급 문의 등과는 완전히 분리된
/// 전용 컬렉션이다. 개선 제안·버그 신고로 시작했지만 지금은 고객센터 문의가
/// **같은 컬렉션에 유형(type)으로만 갈려** 들어온다 — 별도 시스템을 만들면
/// 관리자 화면·상태 체계·규칙이 두 벌이 된다.
class FeedbackType {
  FeedbackType._();

  /// ⚠️ 값은 **문서에 그대로 저장된다.** 이미 접수된 글이 들고 있는 값이므로
  ///    문자열을 바꾸면 옛 문서의 유형이 라벨을 잃는다. 추가만 한다.
  static const improvement = 'improvement';
  static const bug = 'bug';
  static const inquiry = 'inquiry';
  static const payment = 'payment';
  static const host = 'host';
  static const other = 'other';

  /// **읽기용 전체 목록** — 관리자 필터의 목록이자 라벨이 붙는 값 전부.
  ///
  /// 지금은 고를 수 없는 유형도 **빼지 않는다** — 이미 그 값으로 접수된 글이
  /// 있고, 목록에서 사라지면 관리자가 유형으로 걸러 볼 수 없게 된다(라벨도
  /// 함께 잃는다). 새 문의로 받을 것인지는 [composable]이 정한다.
  static const List<String> all = [
    bug,
    inquiry,
    payment,
    host,
    improvement,
    other,
  ];

  /// 새 문의에서 **더는 받지 않는** 유형.
  ///
  /// `payment`(결제/환불) — 파티츄 고객센터는 결제·환불을 직접 처리하지
  /// 않는다. 처리 주체는 그 거래의 호스트이므로, 고객센터로 받으면 답변이
  /// 갈 곳이 없는 글만 쌓인다(작성 화면은 대신 호스트에게 문의하라고 안내한다).
  ///
  /// ⚠️ 값 자체는 [all]·[label]에 그대로 남는다 — 이미 접수된 글을 읽는
  ///    쪽(내 문의 목록·관리자 화면)이 라벨을 잃으면 안 된다.
  static const List<String> retired = [payment];

  /// 작성 화면의 선택지 순서 — [all]에서 [retired]를 뺀 것.
  static const List<String> composable = [
    bug,
    inquiry,
    host,
    improvement,
    other,
  ];

  /// 새 문의로 접수할 수 있는 유형인가 — 작성 화면(선택지)과
  /// [FeedbackService.submit](마지막 방어선)이 같은 판정을 쓴다.
  static bool isComposable(String type) => composable.contains(type);

  /// 연락처를 **반드시** 받아야 하는 유형 — 구버전 앱은 이 값을 보내지
  /// 못하므로(선택지에 없다) firestore.rules도 이 둘에만 필수를 건다.
  ///
  /// `payment`가 남아 있는 이유는 [retired]와 같다 — 스토어에 나가 있는
  /// 구버전 앱은 아직 이 값을 보낼 수 있고, 그 글의 연락처 필수는 그대로
  /// 지켜져야 한다(규칙도 이 둘을 본다).
  static const List<String> contactRequired = [payment, host];

  static String label(String type) => switch (type) {
    improvement => '개선 제안',
    bug => '버그 신고',
    inquiry => '이용 문의',
    payment => '결제/환불 문의',
    host => '사업자/호스트 문의',
    other => '기타 문의',
    _ => type,
  };
}

/// 답변받을 연락처의 **유일한 판정식**.
///
/// 작성 화면(버튼 잠금)과 [FeedbackService.submit](마지막 방어선)이 같은
/// 함수를 쓴다 — 두 곳에 따로 적으면 화면은 통과시키는데 제출은 실패하는
/// 조합이 조용히 생긴다.
class FeedbackContact {
  FeedbackContact._();

  /// 형식 검증용 최소 규격 — 계정 이메일이 아니라 **답변받을 주소**라서
  /// 도메인 존재 여부까지는 따지지 않는다(오타를 걸러 주는 정도).
  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$');

  static bool isValidEmail(String? value) =>
      _email.hasMatch((value ?? '').trim());

  /// 숫자만 남긴 값. 하이픈을 넣든 말든 같은 번호로 본다.
  static String digitsOf(String? value) =>
      (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');

  /// 전화번호는 **선택 입력**이라 비어 있으면 유효하다 — 비었다는 이유로
  /// 제출을 막으면 선택이 아니게 된다. 적었다면 형식은 본다.
  ///
  /// 0으로 시작하는 9~11자리(02-123-4567 ~ 010-1234-5678)까지 받는다.
  static bool isValidPhoneOrEmpty(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return true;
    final d = digitsOf(v);
    return d.length >= 9 && d.length <= 11 && d.startsWith('0');
  }
}

/// 버그 신고인데 스크린샷을 붙일 수 없는 경우의 사유.
///
/// 저장은 **사람이 읽는 문구 그대로** 한다 — 관리자 화면이 코드→문구 대응표를
/// 따로 들고 있지 않아도 되고, 나중에 목록이 바뀌어도 옛 문서가 빈칸으로
/// 보이지 않는다(`기타`는 사용자가 쓴 문장이 그대로 들어온다).
class FeedbackScreenshotBlocker {
  FeedbackScreenshotBlocker._();

  static const noNotification = '알림이 오지 않음';
  static const screenClosed = '화면이 바로 종료되어 캡처 불가';
  static const intermittent = '간헐적으로 발생';
  static const other = '기타';

  /// 선택지로 보여줄 순서.
  static const List<String> presets = [
    noNotification,
    screenClosed,
    intermittent,
    other,
  ];
}

class FeedbackStatus {
  FeedbackStatus._();
  static const received = 'received';
  static const reviewing = 'reviewing';
  static const planned = 'planned';
  static const answered = 'answered';
  static const hold = 'hold';

  static const List<String> all = [
    received,
    reviewing,
    planned,
    answered,
    hold,
  ];

  static String label(String status) => switch (status) {
    received => '접수',
    reviewing => '확인 중',
    planned => '처리 예정',
    answered => '답변 완료',
    hold => '보류',
    _ => status,
  };
}

class FeedbackRequest {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String content;
  final List<String> imageUrls;

  /// 스크린샷을 남길 수 없는 오류라고 작성자가 표시했는가.
  /// 이 필드가 생기기 전에 접수된 문서에는 없으므로 기본값은 false다.
  final bool screenshotUnavailable;

  /// 위가 true일 때 작성자가 고른(또는 직접 쓴) 사유.
  final String? screenshotUnavailableReason;
  final String? relatedScreen;

  /// 답변받을 이메일. 고객센터 문의에서는 필수로 받지만, **이 필드가 생기기
  /// 전에 접수된 글에는 없다** — 빈 문자열로 읽혀 관리자 화면이 '-'를 띄운다.
  final String contactEmail;

  /// 답변받을 전화번호. 선택 입력이라 비어 있을 수 있다.
  final String contactPhone;

  final String status;
  final String userReply;
  final String adminMemo;
  final String? appVersion;
  final String? platform;
  final String? osVersion;
  final String? deviceInfo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FeedbackRequest({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.content,
    required this.imageUrls,
    this.screenshotUnavailable = false,
    this.screenshotUnavailableReason,
    this.contactEmail = '',
    this.contactPhone = '',
    required this.status,
    required this.userReply,
    required this.adminMemo,
    this.relatedScreen,
    this.appVersion,
    this.platform,
    this.osVersion,
    this.deviceInfo,
    this.createdAt,
    this.updatedAt,
  });

  factory FeedbackRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return FeedbackRequest(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      type: d['type'] as String? ?? FeedbackType.other,
      title: d['title'] as String? ?? '',
      content: d['content'] as String? ?? '',
      imageUrls: (d['imageUrls'] as List?)?.cast<String>() ?? [],
      // 옛 문서에는 두 필드가 아예 없다 — false/null로 읽혀 기존 동작 그대로다.
      screenshotUnavailable: d['screenshotUnavailable'] as bool? ?? false,
      screenshotUnavailableReason: d['screenshotUnavailableReason'] as String?,
      // 고객센터 문의 이전 문서에는 두 필드가 없다 — 빈 문자열로 떨어진다.
      contactEmail: d['contactEmail'] as String? ?? '',
      contactPhone: d['contactPhone'] as String? ?? '',
      relatedScreen: d['relatedScreen'] as String?,
      status: d['status'] as String? ?? FeedbackStatus.received,
      userReply: d['userReply'] as String? ?? '',
      adminMemo: d['adminMemo'] as String? ?? '',
      appVersion: d['appVersion'] as String?,
      platform: d['platform'] as String?,
      osVersion: d['osVersion'] as String?,
      deviceInfo: d['deviceInfo'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
