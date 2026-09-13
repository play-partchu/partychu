// ─────────────────────────────────────────────────────────────────────────────
// 등록 개수 제한 — **유형별 각각 10개**. 앱에서 이 판정을 하는 유일한 자리.
//
// 한 계정이 동시에 운영할 수 있는 등록물 수를 유형마다 따로 센다. 합산이
// 아니다 — 파티 10 + 이벤트 10 + 플레이스 10 + 장소대여 10까지 된다.
//
// ── 왜 한 곳인가 ─────────────────────────────────────────────────────────────
// 예전에는 파티만, 그것도 **두 곳에서 서로 다른 기준으로** 셌다. 등록 진입
// 화면은 parties 문서를 그대로 셌고(날짜 5개짜리 파티 = 5개), 저장 직전
// 검사는 seriesId로 묶어 셌다(= 1개). 같은 계정이 진입에서는 막히고 저장에서는
// 통과하는 구간이 실제로 있었다. 이제 세는 규칙도, 숫자도, 안내 문구도 여기
// 하나뿐이다.
//
// ── 서버가 마지막 문이다 ─────────────────────────────────────────────────────
// 여기는 **화면을 막는 자리**일 뿐이다. 실제 강제는 서버가 한다 —
// functions/registrationLimits.js(같은 규칙)와 그것을 쓰는
// registrationLimitGuard(네 컬렉션의 onCreate 트리거) · createParty 콜러블.
// 두 쪽의 상한과 "무엇을 세는가"가 어긋나면 앱은 통과시키고 서버가 지우는
// 상태가 된다.
//
// ── 무엇이 자리를 차지하는가 ─────────────────────────────────────────────────
// **지금 살아 있는 것만** 센다.
//   파티      최종 종료 시각이 아직 안 지난 것(무기한 정기 파티 포함)
//   이벤트    진행 중 · 시작 전([PlacePromotion.statusAt]이 공개로 보는 것)
//   플레이스  isActive != false
//   장소대여  isActive != false
//
// 지난 파티·끝난 이벤트·숨긴 장소는 자리를 차지하지 않는다 — 어차피 14일 뒤
// 자동 삭제되는 대기열이고([AutoDeleteRetention]), 그 사이에 새 등록이 막히면
// 호스트는 지울 방법을 찾아 헤매게 된다. 삭제된 것도 물론 빠진다.
//
// 파티만 **게시글 단위**다. 날짜를 여러 개 고른 일회성 파티는 날짜마다 문서가
// 생기고 그 문서들이 `seriesId`를 공유한다 — 사용자가 만든 것은 하나이므로
// 하나로 센다.
//
// 수정은 개수를 늘리지 않는다: 세는 것은 "지금 있는 것"이지 "만든 횟수"가
// 아니다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/utils/user_session.dart';

/// 등록물 유형 — 컬렉션과 사람이 부르는 이름이 어긋나 있어서 **둘 다** 적어
/// 둔다(서버 registrationLimits.js의 키와 같은 이름이다).
enum RegistrationKind {
  /// 🎉 파티 — `parties`.
  party(key: 'party', collection: 'parties', label: '파티'),

  /// ✨ 이벤트(매장 이벤트 · 공간 이벤트) — `placePromotions`.
  promotion(key: 'promotion', collection: 'placePromotions', label: '이벤트'),

  /// 🍷 플레이스(술집·바·카페) — `events`. **컬렉션 이름에 속지 말 것.**
  placeListing(key: 'event', collection: 'events', label: '플레이스'),

  /// 🏠 장소대여(공간대여·숙박) — `places`.
  rentalListing(key: 'place', collection: 'places', label: '장소대여');

  const RegistrationKind({
    required this.key,
    required this.collection,
    required this.label,
  });

  /// 서버와 맞춘 유형 키.
  final String key;

  /// 실제 Firestore 컬렉션.
  final String collection;

  /// 안내 문구에 쓰는 이름.
  final String label;
}

/// 목록에서 셀 문서 한 건 — Firestore 없이 판정을 테스트하려고 둔 최소 형태.
class RegistrationDoc {
  const RegistrationDoc(this.id, this.data);

  final String id;
  final Map<String, dynamic> data;
}

class RegistrationLimits {
  RegistrationLimits._();

  /// 유형별 상한. 네 유형이 같은 값을 쓴다 — 유형마다 다른 숫자를 두면
  /// 안내 문구도 유형마다 갈라진다.
  ///
  /// ⚠️ functions/registrationLimits.js의 MAX_PER_TYPE과 **같아야 한다.**
  static const int maxPerType = 10;

  /// 한도에 걸렸을 때 보여줄 안내. 서버 limitMessage와 같은 뜻이다.
  static String limitMessage(RegistrationKind kind) =>
      '${kind.label}는 최대 $maxPerType개까지 등록할 수 있어요.\n'
      '기존 등록물을 삭제하거나 종료한 뒤 다시 시도해주세요.';

  // ── 판정(순수) ─────────────────────────────────────────────────────────

  /// soft delete — 네 유형이 같은 두 필드를 쓴다.
  static bool _isDeleted(Map<String, dynamic> d) =>
      d['isDeleted'] == true || d['status'] == 'deleted';

  /// 문서 하나가 지금 자리를 차지하는가.
  static bool isLive(
    RegistrationKind kind,
    RegistrationDoc doc, {
    DateTime? now,
  }) {
    final data = doc.data;
    if (_isDeleted(data)) return false;
    final at = now ?? DateTime.now();
    switch (kind) {
      case RegistrationKind.party:
        // 끝나는 때가 없는 무기한 정기 파티(null)는 살아 있다 — 서버의 자동
        // 삭제도 그런 파티는 건드리지 않는다. 두 판정이 어긋나면 "세지도
        // 않는데 지워지지도 않는" 파티가 생긴다.
        final end = PartySchedule.finalEndAt(data);
        return end == null || !end.isBefore(at);
      case RegistrationKind.promotion:
        // 종료·숨김만 빠진다(진행 중·시작 전은 남는다) — 상세·목록이 쓰는
        // 판정 하나를 그대로 쓴다.
        return PlacePromotion.fromMap(doc.id, data).statusAt(at).isPublic;
      case RegistrationKind.placeListing:
      case RegistrationKind.rentalListing:
        // 날짜가 없는 상시 등록물이라 숨김 여부가 전부다. 값이 없는 옛 문서는
        // 노출 중으로 본다(목록 판정 ListingSources와 같다).
        return data['isActive'] != false;
    }
  }

  /// 문서를 "사용자가 만든 것 하나" 단위로 묶는 열쇠 — 파티만 seriesId다.
  static String groupKeyOf(RegistrationKind kind, RegistrationDoc doc) {
    if (kind != RegistrationKind.party) return doc.id;
    final series = (doc.data['seriesId'] as String? ?? '').trim();
    return series.isNotEmpty ? series : doc.id;
  }

  /// 목록에서 지금 자리를 차지하는 등록물 수.
  ///
  /// [excludeKeys]에 든 열쇠는 빼고 센다 — "이것 말고 몇 개가 있나"를 물어야
  /// 하는 자리(수정 중인 문서 등)를 위해 둔다.
  static int countLive(
    RegistrationKind kind,
    Iterable<RegistrationDoc> docs, {
    DateTime? now,
    Set<String> excludeKeys = const {},
  }) {
    final keys = <String>{};
    for (final doc in docs) {
      if (!isLive(kind, doc, now: now)) continue;
      final key = groupKeyOf(kind, doc);
      if (excludeKeys.contains(key)) continue;
      keys.add(key);
    }
    return keys.length;
  }

  // ── Firestore ──────────────────────────────────────────────────────────

  /// 테스트 주입점 — 이 프로젝트의 Dart 테스트에는 Firestore 페이크가 없다
  /// ([PlaceCreateEligibility]와 같은 방식). 운영 코드는 null이라 실물
  /// Firestore를 그대로 쓴다.
  static Future<List<RegistrationDoc>> Function(RegistrationKind kind)? _source;

  @visibleForTesting
  static void debugSetSource(
    Future<List<RegistrationDoc>> Function(RegistrationKind kind)? source,
  ) => _source = source;

  @visibleForTesting
  static void debugResetSource() => _source = null;

  static Future<List<RegistrationDoc>> _fetch(RegistrationKind kind) async {
    final override = _source;
    if (override != null) return override(kind);
    final uid = UserSession.userId;
    if (uid.isEmpty) return const [];
    // hostId 하나로만 거르고 상태는 메모리에서 본다 — 상태 축이 유형마다
    // 다르고(종료 시각·isVisible·isActive), 한 계정의 문서는 많아야 수십 건이다.
    // 캐시를 우회한다: 방금 지운 등록물이 캐시에 남아 한도를 잘못 채우면
    // 사용자는 "지웠는데도 못 만드는" 상태를 만난다.
    final snap = await FirebaseFirestore.instance
        .collection(kind.collection)
        .where('hostId', isEqualTo: uid)
        .get(const GetOptions(source: Source.server));
    return [for (final d in snap.docs) RegistrationDoc(d.id, d.data())];
  }

  /// 지금 이 계정이 갖고 있는 [kind] 등록물 수.
  static Future<int> countActive(
    RegistrationKind kind, {
    DateTime? now,
    Set<String> excludeKeys = const {},
  }) async {
    final docs = await _fetch(kind);
    return countLive(kind, docs, now: now, excludeKeys: excludeKeys);
  }

  /// 하나 더 만들 수 있는가. 조회에 실패하면 **막지 않는다** — 개수 제한은
  /// 안전장치지 관문이 아니고(진짜 관문은 사업자 인증이다), 서버가 초과분을
  /// 다시 잡아낸다. 여기서 fail-closed로 막으면 네트워크가 흔들릴 때마다
  /// 등록 자체가 안 되는 것처럼 보인다.
  static Future<bool> canCreate(RegistrationKind kind, {DateTime? now}) async {
    try {
      return await countActive(kind, now: now) < maxPerType;
    } catch (_) {
      return true;
    }
  }

  // ── 화면에서 쓰는 관문 ─────────────────────────────────────────────────

  /// 등록을 시작해도 되는지 확인하고, 꽉 찼으면 안내를 띄운 뒤 false.
  ///
  /// 등록 폼을 여는 모든 길이 이 함수를 지나야 한다 — 한 곳이라도 빠지면
  /// 그 길이 그대로 우회로가 된다(사업자 인증 관문과 같은 규칙).
  static Future<bool> ensure(
    BuildContext context,
    RegistrationKind kind, {
    DateTime? now,
  }) async {
    if (await canCreate(kind, now: now)) return true;
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '등록 개수를 다 채웠어요',
          style: TextStyle(
            fontFamily: 'SeoulHangang',
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
        content: Text(
          limitMessage(kind),
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '확인',
              style: TextStyle(color: Color(0xFFFF6FA0)),
            ),
          ),
        ],
      ),
    );
    return false;
  }
}
