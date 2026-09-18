import '../models/admin_notification.dart';

/// 알림 하나가 가리키는 곳 — **단 하나의 규칙**.
///
/// 같은 알림을 두 곳에서 누를 수 있어서(상단 종 목록, 전체 알림 화면) 규칙을
/// 여기 모았다. 두 곳이 각자 판단하면 "종에서 누르면 열리는데 전체 화면에서
/// 누르면 아무 데도 안 가는" 어긋남이 생기고, 알림 종류가 늘 때마다 한쪽만
/// 고치게 된다. 사용자 앱의 notification_route.dart와 같은 구성이다.
///
/// 관리자 셸은 라우팅 패키지 없이 메뉴 인덱스로 화면을 바꾸므로, 여기서는
/// 위젯이 아니라 **"어느 메뉴의 어느 문서를 열어라"**만 돌려준다. 실제 전환은
/// admin_shell.dart가 기존 상태(_selectedPreRegistrationId 등)를 그대로 써서
/// 한다 — 새 이동 경로를 만들지 않는다.
class AdminNotificationTarget {
  /// 열어야 할 사이드바 메뉴 라벨(_menuItems의 label과 같아야 한다).
  final String menuLabel;

  /// 그 화면에서 열어야 할 문서 id. 목록만 열면 되는 종류는 null.
  final String? documentId;

  const AdminNotificationTarget({required this.menuLabel, this.documentId});

  @override
  bool operator ==(Object other) =>
      other is AdminNotificationTarget &&
      other.menuLabel == menuLabel &&
      other.documentId == documentId;

  @override
  int get hashCode => Object.hash(menuLabel, documentId);

  @override
  String toString() => 'AdminNotificationTarget($menuLabel, $documentId)';
}

/// 갈 곳이 없으면 null — 부르는 쪽은 읽음 처리만 하고 이동하지 않는다.
///
/// 종류를 추가할 때 손대는 곳은 여기와 [AdminNotification.typeLabel] 둘뿐이다.
AdminNotificationTarget? adminNotificationTarget(AdminNotification n) {
  switch (n.refCollection) {
    case 'hostPreRegistrations':
      if (n.refId.isEmpty) return null;
      return AdminNotificationTarget(
        menuLabel: '호스트 사전등록',
        documentId: n.refId,
      );

    // 앞으로 붙일 것들 — refCollection만 보고 고르면 되도록 서버가 항상
    // refCollection·refId를 함께 남긴다.
    //   case 'businessDelegations': …
    //   case 'reports': …
    //   case 'feedbackRequests': …
    default:
      return null;
  }
}
