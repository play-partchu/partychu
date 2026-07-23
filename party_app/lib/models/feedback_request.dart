import 'package:cloud_firestore/cloud_firestore.dart';

/// 의견 보내기 — Firestore `feedbackRequests` 컬렉션 문서 모델.
///
/// 파티 신고·사용자 신고·환불 요청·결제 분쟁·긴급 문의 등과는 완전히 분리된
/// 전용 컬렉션이다 (서비스 개선/버그/일반 문의 전용).
class FeedbackType {
  FeedbackType._();
  static const improvement = 'improvement';
  static const bug = 'bug';
  static const inquiry = 'inquiry';
  static const other = 'other';

  static const List<String> all = [improvement, bug, inquiry, other];

  static String label(String type) => switch (type) {
        improvement => '개선 제안',
        bug => '버그 신고',
        inquiry => '이용 문의',
        other => '기타',
        _ => type,
      };
}

class FeedbackStatus {
  FeedbackStatus._();
  static const received = 'received';
  static const reviewing = 'reviewing';
  static const planned = 'planned';
  static const answered = 'answered';
  static const hold = 'hold';

  static const List<String> all = [received, reviewing, planned, answered, hold];

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
  final String? relatedScreen;
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
