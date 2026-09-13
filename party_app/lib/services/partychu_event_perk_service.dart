// ─────────────────────────────────────────────────────────────────────────────
// 파티츄 오픈혜택 — 이벤트 등록 화면 맨 위에 보여주는 **운영 안내**.
//
// 호스트가 입력하거나 저장하는 값이 아니다. "지금 파티츄가 무슨 혜택을 돌리고
// 있는지"를 등록 전에 먼저 읽고, 자기 이벤트가 그것과 겹치는지·함께 걸 수
// 있는지 판단하게 하는 것이 전부다.
//
// ── 왜 appConfig인가 ────────────────────────────────────────────────────────
// 이 문구는 오픈 기간마다 바뀐다. 코드에 박아 두면 문구 한 줄 고치는 데 앱
// 배포가 필요하다. 이미 같은 성격의 값(앱 버전 정책 `appConfig/version`,
// 호스트 정책 `appConfig/policy`)이 그 컬렉션에 있으므로 **새 컬렉션을 만들지
// 않고** 문서 하나를 더한다. 규칙도 이미 있다 — appConfig는 공개 읽기 +
// 관리자만 쓰기(firestore.rules).
//
// 문서 구조 (Firebase Console에서 직접 생성):
// ```
// appConfig/eventPerk
// {
//   isActive: true,
//   title:   '🎁 파티츄 오픈혜택',                       // 없으면 기본 문구
//   message: '오픈 기간 동안 등록된 이벤트에는 파티츄 프로모션이 함께 노출될 수 있어요.',
//   startAt: <Timestamp>,   // 선택 — 지나면 알아서 사라진다
//   endAt:   <Timestamp>,   // 선택
//   perks: [                // 선택 — 실제 운영 중인 공식 혜택 카드
//     { title: '오픈 수수료 0%', description: '9월 30일까지 등록한 이벤트는 수수료를 받지 않아요.' },
//   ],
// }
// ```
//
// ⚠️ **없으면 아무것도 그리지 않는다.** 문서가 없거나 `isActive`가 꺼져 있거나
// 기간이 지났거나 보여줄 내용이 하나도 없으면 [watch]가 null을 흘리고 화면에서
// 영역째 사라진다 — 빈 카드가 등록 폼 위에 남지 않게 하려는 것이다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/utils/firestore_error_log.dart';

/// 공식 혜택 카드 한 장.
class PartychuEventPerkItem {
  const PartychuEventPerkItem({required this.title, required this.description});

  final String title;
  final String description;

  static PartychuEventPerkItem? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final title = (raw['title'] as String? ?? '').trim();
    final description = (raw['description'] as String? ?? '').trim();
    // 제목도 설명도 없는 항목은 카드로 그릴 것이 없다.
    if (title.isEmpty && description.isEmpty) return null;
    return PartychuEventPerkItem(title: title, description: description);
  }
}

/// 이벤트 등록 화면 머리에 붙는 운영 안내 한 덩어리.
class PartychuEventPerk {
  const PartychuEventPerk({
    required this.title,
    required this.message,
    required this.items,
  });

  final String title;
  final String message;
  final List<PartychuEventPerkItem> items;

  /// 보여줄 내용이 하나도 없는가 — 제목만 있는 카드는 그리지 않는다.
  bool get isEmpty => message.isEmpty && items.isEmpty;
}

class PartychuEventPerkService {
  PartychuEventPerkService._();

  static const String docPath = 'appConfig/eventPerk';

  /// 운영에서 제목을 따로 정하지 않았을 때 쓰는 문구.
  static const String defaultTitle = '🎁 파티츄 오픈혜택';

  /// 지금 보여줄 안내. 보여줄 것이 없으면 null.
  ///
  /// 읽기에 실패해도 **등록을 막지 않는다** — 안내는 부가 정보이므로 조용히
  /// 접고(null) 로그만 남긴다. 등록 폼은 그대로 쓸 수 있어야 한다.
  /// `handleError`는 **스트림이 만들어진 뒤**의 실패만 받는다. 스트림을 만드는
  /// 순간(`FirebaseFirestore.instance`)의 실패는 [PartychuEventPerkBanner]의
  /// build 안에서 그대로 터져 등록 폼째로 무너뜨리므로 여기서도 접는다 —
  /// 위 계약("읽기에 실패해도 등록을 막지 않는다")은 두 실패 모두에 해당한다.
  static Stream<PartychuEventPerk?> watch() {
    try {
      return FirebaseFirestore.instance
          .doc(docPath)
          .snapshots()
          .map((s) => parse(s.data(), now: DateTime.now()))
          .handleError((Object e, StackTrace st) {
            logFirestoreStreamError('PartychuEventPerkService.watch', e, st);
          });
    } catch (e, st) {
      logFirestoreStreamError('PartychuEventPerkService.watch', e, st);
      return Stream<PartychuEventPerk?>.value(null);
    }
  }

  /// 문서 → 화면에 그릴 값. 조건에 맞지 않으면 null.
  ///
  /// 판정을 한곳에 모아 둔다 — "언제 숨는가"가 화면 쪽에 흩어지면 조건이
  /// 하나 늘 때마다 빈 카드가 새는 자리가 생긴다.
  static PartychuEventPerk? parse(
    Map<String, dynamic>? data, {
    required DateTime now,
  }) {
    if (data == null) return null;
    if (data['isActive'] != true) return null;

    final startAt = _dateOf(data['startAt']);
    if (startAt != null && now.isBefore(startAt)) return null;
    final endAt = _dateOf(data['endAt']);
    if (endAt != null && now.isAfter(endAt)) return null;

    final items = <PartychuEventPerkItem>[];
    for (final raw in (data['perks'] as List?) ?? const []) {
      final item = PartychuEventPerkItem.fromMap(raw);
      if (item != null) items.add(item);
    }

    final perk = PartychuEventPerk(
      title: (data['title'] as String? ?? '').trim().isEmpty
          ? defaultTitle
          : (data['title'] as String).trim(),
      message: (data['message'] as String? ?? '').trim(),
      items: items,
    );
    return perk.isEmpty ? null : perk;
  }

  static DateTime? _dateOf(Object? raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }
}
