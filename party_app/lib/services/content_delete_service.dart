import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;

// ══════════════════════════════════════════════════════════════════════════
// 콘텐츠 삭제 — 앱 전체가 쓰는 **단 하나의** 삭제 경로.
//
// 파티·장소·플레이스·파티샵·파트너의 모든 삭제 버튼이 이 서비스를 거친다.
// 화면에서 `FirebaseFirestore...delete()`를 직접 부르면 안 된다:
//
//  - 클라이언트는 규칙상 parties/{id}/applications, 예약·주문 컬렉션을 아예
//    쓸 수 없다(allow write: if false). 직접 지우면 연결 데이터가 반드시
//    고아로 남는다.
//  - 화면마다 정리 범위가 갈라지면 어떤 화면으로 지웠느냐에 따라 남는
//    쓰레기가 달라진다.
//
// 실제 삭제는 Cloud Functions의 deleteContent 콜러블이 Admin SDK로 수행한다
// (functions/contentDelete.js). 권한 검사·삭제 가능 여부 판정·연결 데이터
// 정리·Cloudflare 미디어 정리가 전부 서버 한 곳에 있다.
// ══════════════════════════════════════════════════════════════════════════

const String _functionsRegion = 'asia-northeast3';

/// 삭제할 수 있는 콘텐츠 유형. key는 서버(contentDelete.js의 TYPES)와 1:1로
/// 맞춰야 한다 — 유형을 추가할 때는 양쪽에 함께 넣는다.
enum DeletableContent {
  party('party', '파티'),
  place('place', '장소'),
  event('event', '플레이스'),
  partyShop('partyShop', '파티샵'),
  crew('crew', '파트너');

  const DeletableContent(this.key, this.label);

  /// 서버에 보내는 유형 문자열.
  final String key;

  /// 확인창·안내 문구에 쓰는 이름("이 파티를 삭제하시겠습니까?").
  final String label;
}

/// 삭제 범위 — 여러 날짜/회차로 나뉜 콘텐츠에서만 의미가 있다.
enum DeleteScope {
  /// 이 문서 하나만.
  single('single'),

  /// 같은 seriesId를 공유하는 문서 전부(= 이 파티의 전체 일정).
  series('series');

  const DeleteScope(this.key);
  final String key;
}

/// 삭제를 막고 있는 것이 **무엇인지** — 안내창의 "내역 보기" 버튼이 어느
/// 관리 화면으로 보낼지를 이 값으로 고른다.
///
/// 서버는 사람이 읽을 문장 하나만 내려준다(contentCleanup.js의
/// blockingReasonFor*). 화면을 고르려면 그 문장에서 종류를 되짚어야 하는데,
/// 문구는 서버가 쥐고 있으므로 여기 키워드 표가 **contentCleanup.js와 짝**이다
/// — 그쪽 문구를 고치면 이 표도 같이 고쳐야 한다. 못 알아보면 [unknown]이
/// 되고 버튼이 그냥 안 뜬다(엉뚱한 화면으로 보내는 것보다 낫다).
enum DeleteBlockerKind {
  /// 장소대여 예약(placeReservationGroups) · 패키지 예약(packageBookings).
  placeReservation,

  /// 방문예약(placeVisitReservations).
  placeVisit,

  /// 사용되지 않은 이용권(placeProductOrders).
  placeProductOrder,

  /// 파티 신청자(parties/{id}/applications).
  partyApplication,

  /// 파티샵 주문(orders).
  shopOrder,

  /// 알아보지 못했거나, 예약과 무관한 실패(권한 없음 등).
  unknown;

  /// 서버 문구에서 종류를 되짚는다. 순서가 중요하다 — '패키지 예약'과
  /// '방문예약'은 둘 다 '예약'을 품고 있어, 좁은 것부터 본다.
  static DeleteBlockerKind fromMessage(String message) {
    if (message.contains('방문예약')) return placeVisit;
    if (message.contains('이용권')) return placeProductOrder;
    if (message.contains('신청자')) return partyApplication;
    if (message.contains('주문')) return shopOrder;
    if (message.contains('예약')) return placeReservation;
    return unknown;
  }
}

/// 삭제가 거절됐을 때 — [message]는 사용자에게 그대로 보여줄 문구다.
///
/// 서버가 이유를 문장으로 만들어 내려주므로(결제한 신청자 N명, 진행 중인
/// 예약 N건 …) 화면은 이 값을 그대로 띄우기만 하면 된다.
class ContentDeleteException implements Exception {
  final String message;

  /// 결제·예약이 남아 삭제가 막힌 경우 true — 화면이 "먼저 정리해주세요"
  /// 안내를 조금 더 눈에 띄게 보여줄 때 쓴다.
  final bool blockedByLinkedData;

  /// 무엇이 막고 있는지 — [blockedByLinkedData]가 true일 때만 의미가 있다.
  final DeleteBlockerKind blocker;

  const ContentDeleteException(
    this.message, {
    this.blockedByLinkedData = false,
    this.blocker = DeleteBlockerKind.unknown,
  });

  @override
  String toString() => message;
}

/// 삭제 결과 — 지운 콘텐츠 문서 수와, 지우지 않고 남긴 거래기록 수.
///
/// 주문·이용권·예약·결제된 신청서는 전자상거래법상 보존 대상이라 콘텐츠가
/// 사라져도 남는다(functions/contentCleanup.js). 사용자가 "다 지웠는데 왜
/// 내역이 남아 있지?" 하고 놀라지 않도록 화면이 이 수치를 함께 안내한다.
class ContentDeleteResult {
  final int deletedCount;
  final int preservedCount;

  const ContentDeleteResult({
    required this.deletedCount,
    required this.preservedCount,
  });
}

class ContentDeleteService {
  ContentDeleteService._();

  /// 이 콘텐츠가 몇 개의 문서로 나뉘어 있는지 — 1이면 "이 일정만/전체 일정"을
  /// 물을 필요가 없다.
  ///
  /// 파티는 날짜 슬롯 하나가 문서 하나이고, 한 번의 등록에서 나온 문서들이
  /// 같은 seriesId를 공유한다(party_register_screen.dart 참고). 다른 유형은
  /// 이런 분할이 없어 항상 1이다.
  ///
  /// 판정을 화면이 아니라 여기서 하는 이유는, 화면마다 "여러 일정인가"를 다르게
  /// 계산하면 같은 파티인데 어떤 화면에서는 선택지가 뜨고 어떤 화면에서는 안
  /// 뜨는 일이 생기기 때문이다. 조회에 실패하면 1로 본다 — 선택지를 잘못
  /// 띄우느니 안 띄우는 쪽이 안전하다.
  static Future<int> scheduleCount({
    required DeletableContent type,
    required String id,
    String? seriesId,
  }) async {
    if (type != DeletableContent.party) return 1;
    final series = (seriesId ?? '').trim().isNotEmpty ? seriesId!.trim() : id;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('parties')
          .where('seriesId', isEqualTo: series)
          .get();
      final live = snap.docs.where((d) {
        final data = d.data();
        return data['isDeleted'] != true && data['status'] != 'deleted';
      }).length;
      return live < 1 ? 1 : live;
    } catch (e) {
      debugPrint('[ContentDelete] 시리즈 조회 실패: $e');
      return 1;
    }
  }

  /// 콘텐츠를 삭제한다.
  ///
  /// 실패하면 [ContentDeleteException]을 던진다 — 권한 없음/이미 삭제됨/
  /// 결제·예약이 남아 있음이 전부 여기로 온다.
  static Future<ContentDeleteResult> delete({
    required DeletableContent type,
    required String id,
    DeleteScope scope = DeleteScope.single,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: _functionsRegion,
      ).httpsCallable('deleteContent');
      final result = await callable.call<Map<String, dynamic>>({
        'type': type.key,
        'id': id,
        'scope': scope.key,
      });
      return ContentDeleteResult(
        deletedCount: (result.data['deletedCount'] as num?)?.toInt() ?? 1,
        preservedCount: (result.data['preservedCount'] as num?)?.toInt() ?? 0,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[ContentDelete] ${e.code}: ${e.message}');
      final blocked = e.code == 'failed-precondition';
      final message = e.message?.trim().isNotEmpty == true
          ? e.message!.trim()
          : '삭제하지 못했습니다. 잠시 후 다시 시도해주세요.';
      throw ContentDeleteException(
        message,
        blockedByLinkedData: blocked,
        blocker: blocked
            ? DeleteBlockerKind.fromMessage(message)
            : DeleteBlockerKind.unknown,
      );
    } catch (e) {
      debugPrint('[ContentDelete] 실패: $e');
      throw const ContentDeleteException(
        '삭제하지 못했습니다. 네트워크 상태를 확인한 뒤 다시 시도해주세요.',
      );
    }
  }
}
