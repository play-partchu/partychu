/// 🎪 **이벤트 탐색 축**의 정본.
///
/// ── 이벤트는 업종이 아니다 ────────────────────────────────────────────────
/// 푸드·카페·클럽은 "무슨 가게인가"([PlaceTaxonomy], `placeCategory`)이고,
/// 이벤트는 "그 가게가 지금 무엇을 하고 있는가"다. 한 플레이스가 **BAR이면서
/// 생일 이벤트 중**일 수 있으므로, 이벤트를 `placeCategory`에 적으면 원래
/// 업종을 잃는다. 그래서 이벤트는 **다른 축**으로 둔다 — 홈 화면에서만 다른
/// 대분류와 같은 버튼처럼 보이고, 데이터는 업종과 나란히 공존한다.
///
///   BAR + 생일 이벤트인 가게 → 'BAR'에서도, '이벤트 → 생일'에서도 걸린다.
///
/// ── 이미 있던 구조를 그대로 쓴다 ──────────────────────────────────────────
/// 이벤트 노출의 정본은 예전부터 **플레이스 본체 문서의 특징 태그**였다
/// (`themeTags`에 '이벤트' = [ListingConstants.placeEventTag], 화면 표기
/// '이벤트 진행중'). 내용은 `placePromotions` 컬렉션에 있고
/// ([PlacePromotion]), 그 둘을 맞추는 일은 이미 party_event_source.dart가
/// 하고 있다. 새 컬렉션도, 새 등록 폼도 만들지 않는다.
///
/// ── 소분류만 미러 두 개를 더한다 ──────────────────────────────────────────
/// 목록·지도는 `events` 문서 하나만 읽는다(프로모션 컬렉션을 함께 훑지
/// 않는다). 그래서 "이 가게가 어떤 갈래의 이벤트를 하고 있는지"를 본체에
/// 비춰 둬야 목록에서 걸러진다 — `placeSubcategories`·`statusMirror`와 같은
/// 관례다.
///
///   · [kindsField]  `eventKinds`  (배열) — 진행 중인 이벤트의 갈래들
///   · [endsAtField] `eventEndsAt` (시각) — 마지막 한정 이벤트의 종료일.
///                   상시 이벤트가 하나라도 있거나 종료일이 없으면 **비운다**.
///
/// 둘 다 **더하기만 하는 필드**다. 없는 문서(지금까지 등록된 전부)는 예전과
/// 똑같이 '이벤트 전체'에 그대로 나오고, 옛 단일 `eventSubtype`('생일파티
/// 이벤트')은 [kindsOf]가 생일 갈래로 읽어 준다. 마이그레이션은 하지 않는다.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/models/host_offering.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/place_promotion.dart';

/// 이벤트 갈래 하나.
class PlaceEventKind {
  const PlaceEventKind({
    required this.key,
    required this.emoji,
    required this.label,
    required this.meaning,
    this.short,
  });

  /// 저장값이자 필터 값 — `eventKinds` 배열에 이 문자열 그대로 들어간다.
  /// 배포 후 변경 금지(바꾸면 이미 비춰 둔 문서가 필터에서 사라진다).
  final String key;

  final String emoji;
  final String label;

  /// 좁은 자리(드릴다운 칩) 표기.
  final String? short;

  /// 이 갈래가 무엇을 뜻하는지 — 판정 규칙과 화면 안내가 갈리지 않게
  /// 한 문장으로 적어 둔다.
  final String meaning;

  String get shortLabel => short ?? label;

  String get display => '$emoji $label';
}

class PlaceEventTaxonomy {
  PlaceEventTaxonomy._();

  /// Firestore 필드 — 진행 중인 이벤트 갈래(문자열 배열, 본체 문서의 미러).
  static const String kindsField = 'eventKinds';

  /// Firestore 필드 — 한정 이벤트가 끝나는 시각(본체 문서의 미러).
  static const String endsAtField = 'eventEndsAt';

  /// 옛 단일 소분류 필드 — 지금도 읽는다([kindsOf]).
  static const String legacySubtypeField = 'eventSubtype';

  // ── 갈래 ──────────────────────────────────────────────────────────────

  static const limited = PlaceEventKind(
    key: '한정',
    emoji: '⏰',
    label: '한정 이벤트',
    short: '한정',
    meaning: '특정 기간·날짜에만 진행 — 기간이 끝나면 탐색에서 저절로 빠진다.',
  );

  static const birthday = PlaceEventKind(
    key: '생일',
    emoji: '🎂',
    label: '생일 이벤트',
    short: '생일',
    meaning: '생일자 할인·서비스·케이크/주류 제공.',
  );

  static const always = PlaceEventKind(
    key: '상시',
    emoji: '♾️',
    label: '상시 이벤트',
    short: '상시',
    meaning: '종료일 없이 계속 제공 — 날짜가 없어도 정상이다.',
  );

  static const benefit = PlaceEventKind(
    key: '할인·혜택',
    emoji: '💸',
    label: '할인·혜택',
    short: '할인·혜택',
    meaning: '할인, 조건부 혜택, 해피아워.',
  );

  static const gift = PlaceEventKind(
    key: '증정',
    emoji: '🎁',
    label: '증정 이벤트',
    short: '증정',
    meaning: '무료 메뉴, 웰컴드링크, 사은품.',
  );

  static const special = PlaceEventKind(
    key: '특별',
    emoji: '🎭',
    label: '특별 이벤트',
    short: '특별',
    meaning: '위 갈래에 들어가지 않는 매장 자체 특별행사.',
  );

  /// 화면 순서 그대로 — 드릴다운 칩도 이 순서를 쓴다.
  static const List<PlaceEventKind> all = [
    limited,
    birthday,
    always,
    benefit,
    gift,
    special,
  ];

  // ── 표기 ──────────────────────────────────────────────────────────────
  //
  // 이 축이 가리키는 것은 **🎪 매장 이벤트**다([HostOffering.placeEvent]) —
  // 매장이 주체가 되어 여는 행사·프로모션·혜택. 참가자를 모집해 신청을 받는
  // 🎉 파티(`parties`)와 이름도 이모지도 갈라 둔다. 예전에는 이 축도 🎉를
  // 써서, 목록에서 파티와 같은 것으로 읽혔다.

  /// 🎪 — 매장 이벤트를 한 글자로 가리키는 표시. 파티(🎉)와 절대 겹치지 않는다.
  static const String categoryEmoji = kPlaceEventEmoji;

  /// 정식 표기 — 자리가 있는 곳(드릴다운 머리, 필터 칩)에서 쓴다.
  static const String categoryLabel = kPlaceEventLabel;

  /// 좁은 자리(업종 격자 칸)용 축약 — 이모지가 이미 🎪라 '이벤트'만으로도
  /// 파티와 헷갈리지 않는다.
  static const String categoryShortLabel = kPlaceEventShortLabel;

  static PlaceEventKind? byKey(String? key) {
    if (key == null || key.isEmpty) return null;
    for (final k in all) {
      if (k.key == key) return k;
    }
    return null;
  }

  static String displayOf(String key) => byKey(key)?.display ?? key;

  static String labelOf(String key) => byKey(key)?.label ?? key;

  // ── 문서 읽기 ─────────────────────────────────────────────────────────

  /// 이 플레이스가 지금 하고 있는 이벤트 갈래들.
  ///
  /// 새 미러([kindsField])가 정본이고, 없으면 옛 단일 `eventSubtype`을 읽는다
  /// — 지금까지 '생일파티 이벤트'로 등록된 문서가 새 '생일' 갈래에서 그대로
  /// 걸리게 하는 다리다(저장값은 건드리지 않는다).
  ///
  /// 둘 다 없으면 비어 있다 — 그 플레이스는 '이벤트 → 전체'에는 나오고
  /// 특정 갈래를 골랐을 때만 빠진다([PlaceTaxonomy.categoryOf]가 미분류
  /// 문서를 다루는 방식과 같다).
  static Set<String> kindsOf(Map<String, dynamic> data) {
    final list = (data[kindsField] as List?)?.whereType<String>().toSet();
    if (list != null && list.isNotEmpty) return list;

    final legacy = (data[legacySubtypeField] as String?)?.trim() ?? '';
    if (legacy == ListingConstants.birthdayEventSubtype) return {birthday.key};
    return const {};
  }

  /// 비춰 둔 종료 시각. 없으면 null(= 기간으로는 끝나지 않는다).
  static DateTime? endsAtOf(Map<String, dynamic> data) {
    final v = data[endsAtField];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    return null;
  }

  /// 지금 이벤트를 하고 있는가 — 🎪 이벤트 대분류를 켰을 때의 판정.
  ///
  /// ① 본체에 '이벤트 진행중' 태그가 켜져 있고,
  /// ② 비춰 둔 종료일이 지나지 않았다.
  ///
  /// ②는 **미러가 있을 때만** 본다. 지금까지 등록된 문서에는 그 값이 없으므로
  /// 예전과 똑같이 그대로 노출된다 — 종료 판정이 없다고 목록에서 빼면 기존
  /// 이벤트 플레이스가 통째로 사라진다.
  ///
  /// 종료일은 **그날 끝까지** 진행으로 본다([PlacePromotion.statusAt]과 같은
  /// 규칙 — 8월 31일까지인 이벤트는 8월 31일 23:59까지 살아 있다).
  static bool isRunningAt(Map<String, dynamic> data, DateTime now) {
    if (!ListingConstants.hasEventTag(data)) return false;
    final ends = endsAtOf(data);
    if (ends == null) return true;
    return !now.isAfter(DateTime(ends.year, ends.month, ends.day, 23, 59, 59));
  }

  /// 고른 갈래 중 하나라도 걸리는가(OR). 비어 있으면 조건 없음.
  static bool matchesAnyKind(Map<String, dynamic> data, Set<String> kinds) {
    if (kinds.isEmpty) return true;
    final owned = kindsOf(data);
    return owned.any(kinds.contains);
  }

  // ── 이벤트 본문에서 갈래 뽑기 ─────────────────────────────────────────
  //
  // 호스트에게 갈래를 **다시 묻지 않는다.** 이벤트 등록 폼([PlacePromotion])이
  // 이미 유형·상시 여부·기간·본문을 받고 있으므로, 갈래는 거기서 떨어진다.
  // 같은 것을 두 번 고르게 하면 두 값이 어긋나는 순간 어느 쪽이 정본인지
  // 알 수 없어진다(특징 태그를 저장하지 않고 유도하는 것과 같은 이유).

  /// 증정으로 읽는 낱말 — 유형을 '패키지'로 고르지 않았어도 본문이 증정이면
  /// 걸리게 한다([ListingConstants.birthdayEventKeywords]와 같은 방식).
  static const List<String> giftKeywords = [
    '증정',
    '무료',
    '웰컴드링크',
    '웰컴 드링크',
    '사은품',
    '서비스 제공',
    '1+1',
  ];

  /// 할인·혜택으로 읽는 낱말.
  static const List<String> benefitKeywords = ['할인', '해피아워', '해피 아워', '%'];

  /// 이벤트 한 건이 속하는 갈래들 — 하나가 여러 갈래일 수 있다
  /// ("8월 한정 생일자 무료" = 한정 + 생일 + 증정).
  static Set<String> kindsOfPromotion(PlacePromotion p) {
    final out = <String>{};

    // ① 기간 — 상시와 한정은 서로 배타적이다.
    if (p.isAlways) {
      out.add(always.key);
    } else if (p.startAt != null || p.endAt != null) {
      out.add(limited.key);
    }

    // ② 호스트가 고른 유형([PromotionType]) — 이미 있는 값을 그대로 옮긴다.
    out.add(switch (p.type) {
      PromotionType.benefit => benefit.key,
      PromotionType.package => gift.key,
      PromotionType.event => special.key,
    });

    // ③ 본문에서 읽어내는 갈래 — 유형 하나로는 못 담는 것들.
    final texts = p.searchTexts;
    if (ListingConstants.autoEventSubtypeFor(texts) ==
        ListingConstants.birthdayEventSubtype) {
      out.add(birthday.key);
    }
    if (_mentions(texts, giftKeywords)) out.add(gift.key);
    if (_mentions(texts, benefitKeywords)) out.add(benefit.key);

    return out;
  }

  static bool _mentions(Iterable<String> texts, List<String> keywords) {
    for (final raw in texts) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      if (keywords.any(t.contains)) return true;
    }
    return false;
  }

  /// 이 플레이스의 이벤트 전체에서 본체에 비출 값을 계산한다.
  ///
  /// **손님에게 보이는 이벤트만** 센다([PromotionStatus.isPublic]) — 숨기거나
  /// 이미 끝난 이벤트로 갈래를 켜면, 눌러 들어와 아무것도 못 보는 상태가 된다.
  ///
  /// [endsAt]은 "이 날이 지나면 이 가게의 이벤트가 전부 끝난다"는 뜻이다.
  /// 상시 이벤트가 하나라도 있거나 종료일 없는 이벤트가 있으면 null —
  /// **날짜로는 끝나지 않는다**(상시 이벤트에 날짜가 없다고 오류가 나거나
  /// 탐색에서 빠지는 일이 없어야 한다).
  static ({Set<String> kinds, DateTime? endsAt}) mirrorFrom(
    Iterable<PlacePromotion> promotions,
    DateTime now,
  ) {
    final running = promotions
        .where((p) => p.statusAt(now).isPublic)
        .toList(growable: false);

    final kinds = <String>{};
    for (final p in running) {
      kinds.addAll(kindsOfPromotion(p));
    }

    // 이벤트가 하나도 없으면 만료 판정을 걸지 않는다 — 호스트가 태그만 켜 둔
    // 플레이스(지금까지의 대부분)를 목록에서 지우지 않기 위함이다.
    var neverEnds = running.isEmpty;
    DateTime? latest;
    for (final p in running) {
      if (p.isAlways || p.endAt == null) {
        neverEnds = true;
        break;
      }
      if (latest == null || p.endAt!.isAfter(latest)) latest = p.endAt;
    }

    return (kinds: kinds, endsAt: neverEnds ? null : latest);
  }
}
