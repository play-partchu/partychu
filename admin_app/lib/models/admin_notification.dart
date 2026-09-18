import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 관리자 업무 알림 한 건 — 서버가 `adminNotifications`에 남긴 문서.
///
/// 사용자 알림(`notifications`)과 **컬렉션부터 분리돼 있다.** 거기에 관리자
/// uid로 쓰면 푸시 트리거가 관리자 개인 폰으로 FCM을 쏘고, 관리자가 사용자
/// 앱을 켰을 때 홈 종에 운영 전용 내용이 섞여 보인다
/// (functions/adminNotifications.js 상단 주석).
///
/// 읽음은 [readBy]에 자기 uid가 들어 있는지로 판정한다 — 관리자가 여럿일 때
/// 한 사람이 읽어도 다른 사람의 안 읽음이 그대로 남아야 하기 때문이다.
@immutable
class AdminNotification {
  /// 문서 id. 서버가 `{type}__{refId}`로 결정적으로 만든다.
  final String id;

  /// 'host_pre_registration' 등. 앞으로 사업자 인증 요청·신고 접수·문의가
  /// 같은 축으로 붙는다.
  final String type;

  final String title;
  final String body;

  /// 눌렀을 때 열어야 할 문서. 라우팅 규칙은 admin_notification_route.dart
  /// 한 곳에만 있다.
  final String refCollection;
  final String refId;

  /// 이 알림을 읽은 관리자들의 uid.
  final List<String> readBy;

  final DateTime? createdAt;

  const AdminNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.refCollection = '',
    this.refId = '',
    this.readBy = const [],
    this.createdAt,
  });

  factory AdminNotification.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final ts = d['createdAt'];
    return AdminNotification(
      id: doc.id,
      type: d['type'] as String? ?? '',
      title: d['title'] as String? ?? '알림',
      body: d['body'] as String? ?? '',
      refCollection: d['refCollection'] as String? ?? '',
      refId: d['refId'] as String? ?? '',
      readBy: (d['readBy'] as List?)?.whereType<String>().toList() ?? const [],
      createdAt: ts is Timestamp ? ts.toDate().toLocal() : null,
    );
  }

  /// 지금 로그인한 관리자가 읽었는가.
  bool isReadBy(String uid) => uid.isNotEmpty && readBy.contains(uid);

  /// 목록 앞에 붙는 종류 딱지. 새 종류를 추가할 때 여기와
  /// admin_notification_route.dart 두 곳만 손대면 된다.
  String get typeLabel => switch (type) {
        'host_pre_registration' => '호스트 사전등록',
        'business_delegation' => '대표자 확인',
        'report' => '신고 접수',
        'feedback' => '문의',
        _ => '알림',
      };
}

/// '방금 전' · '3분 전' 같은 짧은 표기.
String adminNotificationTimeAgo(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  final diff = (now ?? DateTime.now()).difference(at);
  if (diff.isNegative || diff.inMinutes < 1) return '방금 전';
  if (diff.inHours < 1) return '${diff.inMinutes}분 전';
  if (diff.inDays < 1) return '${diff.inHours}시간 전';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  return '${at.month}월 ${at.day}일';
}
