import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/models/report_reason.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';

/// 신고 제출 결과 — 화면이 "접수됨"과 "이미 신고함"을 구분해서 안내한다.
enum ReportSubmitResult { submitted, alreadyReported }

/// 사용자·콘텐츠 신고 — Firestore `reports` 컬렉션.
///
/// ── 기존 스키마를 그대로 쓴다 ────────────────────────────────────────────
/// `reports`는 예전에 규칙만 먼저 올라가 있었다(firestore.rules 주석: "현재는
/// 제출 UI가 없어 스키마·권한만 선반영한다"). 이 서비스는 **그 규칙이 이미
/// 요구하던 모양**을 그대로 채운다 — `reporterId == 내 uid`, `status ==
/// 'received'`. 컬렉션도 상태 체계도 새로 만들지 않는다.
///
/// ── 중복 신고를 문서 id로 막는다 ─────────────────────────────────────────
/// 문서 id가 `"{신고자}_{대상종류}_{대상id}"`라, 같은 사람이 같은 대상을 두 번
/// 신고하면 **같은 문서**를 가리킨다. 규칙은 create만 허용하고 update는 막으므로
/// (allow update: if isAdmin() …), 두 번째 신고는 서버에서 거부된다. 앱은 그
/// 전에 존재 여부를 확인해 "이미 신고했다"고 안내한다 — 카운터도, 스케줄러도,
/// 별도 색인도 필요 없다(favorites·chatRooms와 같은 결정적 id 패턴).
///
/// ── 신고는 아무것도 삭제하지 않는다 ──────────────────────────────────────
/// 이 서비스는 대상 문서를 건드리지 않고, 상대 계정에도 아무 표시를 남기지
/// 않는다. 신고가 곧 처벌이 되면 신고 자체가 공격 수단이 된다. 판단과 조치는
/// 운영자가 관리자 웹에서 한다(status: received → 처리).
///
/// 차단(services/block_service.dart)과는 완전히 별개다 — 신고해도 상대가
/// 안 보이게 되지 않고, 차단해도 운영자에게 알려지지 않는다.
class ReportService {
  ReportService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('reports');

  static String docIdFor({
    required String reporterId,
    required String targetType,
    required String targetId,
  }) => '${reporterId}_${targetType}_$targetId';

  /// 이미 이 대상을 신고했는가 — 신고 화면을 열기 전에 확인한다.
  static Future<bool> alreadyReported({
    required String targetType,
    required String targetId,
  }) async {
    final me = UserSession.userId;
    if (me.isEmpty || targetId.isEmpty) return false;
    try {
      final snap = await _col
          .doc(
            docIdFor(
              reporterId: me,
              targetType: targetType,
              targetId: targetId,
            ),
          )
          .get();
      return snap.exists;
    } catch (e, st) {
      // 확인하지 못했으면 **신고를 막지 않는다.** 중복은 어차피 규칙이 막고,
      // 여기서 막으면 읽기 실패가 곧 신고 불가가 된다.
      logFirestoreStreamError('ReportService.alreadyReported', e, st);
      return false;
    }
  }

  /// 신고 접수.
  ///
  /// [targetUserId]는 그 콘텐츠를 만든 사람(운영자가 계정 단위로 볼 수 있게).
  /// 사용자 신고면 [targetId]와 같다.
  static Future<ReportSubmitResult> submit({
    required String targetType,
    required String targetId,
    required String reason,
    String? targetUserId,
    String? detail,
    String? targetTitle,
  }) async {
    final me = UserSession.userId;
    if (me.isEmpty) throw StateError('로그인이 필요합니다');
    if (!ReportTargetType.isValid(targetType)) {
      throw ArgumentError('알 수 없는 신고 대상 종류: $targetType');
    }
    if (!ReportReason.isValid(reason)) {
      throw ArgumentError('알 수 없는 신고 사유: $reason');
    }
    if (targetId.isEmpty) throw ArgumentError('신고 대상이 비어 있습니다');
    // 본인 신고는 만들 수 없다. 규칙에서도 한 번 더 막는다.
    if (targetUserId != null && targetUserId == me) {
      throw ArgumentError('자기 자신은 신고할 수 없습니다');
    }
    if (targetType == ReportTargetType.user && targetId == me) {
      throw ArgumentError('자기 자신은 신고할 수 없습니다');
    }

    final trimmed = (detail ?? '').trim();
    if (ReportReason.requiresDetail(reason) && trimmed.isEmpty) {
      throw ArgumentError('상세 내용을 입력해주세요');
    }

    final ref = _col.doc(
      docIdFor(reporterId: me, targetType: targetType, targetId: targetId),
    );

    // 존재 확인 → 조건부 생성. 트랜잭션을 쓰지 않는 이유는 favorites와
    // 똑같다 — 이 프로젝트의 Firestore에서 일반 로그인 사용자로 readWrite
    // 트랜잭션을 시작하면 PERMISSION_DENIED가 난다
    // (utils/favorites_service.dart의 긴 주석 참고). 경합이 나더라도 두 번째
    // 쓰기는 규칙(update 불가)이 막으므로 안전하다.
    try {
      final existing = await ref.get();
      if (existing.exists) return ReportSubmitResult.alreadyReported;
    } catch (_) {
      // 못 읽었으면 그냥 만들어 본다 — 중복이면 규칙이 거부한다.
    }

    try {
      await ref.set({
        'reporterId': me,
        'targetType': targetType,
        'targetId': targetId,
        'targetUserId': targetUserId ?? '',
        'targetTitle': targetTitle ?? '',
        'reason': reason,
        'detail': trimmed,
        // 규칙이 요구하는 초기 상태. 이후 변경은 관리자만 할 수 있다.
        'status': 'received',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return ReportSubmitResult.submitted;
    } on FirebaseException catch (e) {
      // 중복 신고를 규칙이 막은 경우(create가 이미 있는 문서에 대해 update로
      // 평가된다) — 사용자에게는 오류가 아니라 "이미 신고했다"가 맞다.
      if (e.code == 'permission-denied') {
        final exists = await alreadyReported(
          targetType: targetType,
          targetId: targetId,
        );
        if (exists) return ReportSubmitResult.alreadyReported;
      }
      rethrow;
    }
  }
}
