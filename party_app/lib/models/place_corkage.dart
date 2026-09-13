import 'package:party_app/models/place_attributes.dart';

/// 플레이스 **콜키지 정책의 정본**.
///
/// 등록 → 저장 → 수정 복원 → 필터 판정 → 목록 카드 → 상세 표시가 전부 이
/// 파일 하나를 거친다. 예전에는 "콜키지 프리인가"를 묻는 코드가 필터·특징
/// 유도·상세 표시에 따로 흩어져 있어서, 유료 콜키지를 받는 가게가 **필터에서
/// 통째로 빠지는데** 상세페이지에는 콜키지 정보가 멀쩡히 떠 있었다.
///
/// ── 필터가 묻는 것이 바뀌었다 ─────────────────────────────────────────────
/// 예전: "콜키지가 **무료**인가"(🍷 콜키지 프리)
/// 지금: "콜키지를 **허용하는가**"(🍶 콜키지 가능)
///
/// 무료든 유료든 "술을 가져가도 되는 집"을 찾는 것이 게스트의 질문이다.
/// 무료만 걸러 주면 유료로 받는 집은 아예 만날 수 없고, 게스트는 그런 집이
/// 없다고 오해한다. **무료/유료의 구분은 필터가 아니라 표시로 푼다** —
/// 목록 카드에서 바로 갈라 보여주므로([cardBadge]) 상세까지 들어가 볼 필요가
/// 없다.
///
/// ── 저장값은 건드리지 않는다 ──────────────────────────────────────────────
/// 문서에 남는 값은 예전 그대로 `placeAttributes.corkage`의 라벨 하나다
/// ([PlaceAttributeCatalog.corkage]). 마이그레이션하지 않고, 여기서 **읽어서**
/// 판정한다. 그래서 옛 문서도 새 필터에 그대로 걸린다.
///
///   '콜키지 불가'  → [notAllowed]  : 필터 미통과
///   '콜키지 프리'  → [free]        : 필터 통과 · 카드에 "콜키지 무료"
///   '콜키지 유료'  → [paid]        : 필터 통과 · 카드에 "콜키지 유료(+금액)"
///   '콜키지 가능'  → [allowed]     : 필터 통과 · 무료인지 유료인지는 모름
///   (고르지 않음)  → [unset]       : 필터 미통과
///
/// `'콜키지 가능'`은 **없애지 않는다.** 이 값이 그룹의 선택지 목록에서 빠지면
/// [PlaceAttributes.toMap]이 저장에서 통째로 떨궈, 이미 그렇게 등록한 가게가
/// 다음 저장 때 콜키지 정보를 잃는다. 무료·유료를 모르는 상태를 지어내지 않고
/// "가능"까지만 말하는 것이 맞다.
enum PlaceCorkagePolicy {
  /// 호스트가 콜키지를 고르지 않았다 — 모른다(= 허용한다고 말할 근거가 없다).
  unset,

  /// 콜키지 불가.
  notAllowed,

  /// 허용하지만 무료인지 유료인지는 저장돼 있지 않다.
  allowed,

  /// 무료(옛 표기 '콜키지 프리').
  free,

  /// 유료 — 금액이 함께 저장돼 있을 수 있다([PlaceCorkage.feeText]).
  paid,
}

/// 문서 하나의 콜키지 정책 + 금액. 읽기 전용 값 객체.
class PlaceCorkage {
  const PlaceCorkage._(this.policy, this.feeText);

  final PlaceCorkagePolicy policy;

  /// 호스트가 적어 둔 콜키지 비용 원문(자유 입력, 예: `'1병 10,000원'`).
  /// 비어 있으면 빈 문자열 — **없는 금액을 지어내지 않는다.**
  final String feeText;

  static const _emoji = '🍶';

  /// 이미 읽어 둔 속성으로 판정한다.
  factory PlaceCorkage.fromAttributes(PlaceAttributes attrs) {
    final value = attrs.single(PlaceAttributeCatalog.corkageKey);
    final fee = attrs
        .detailText(PlaceAttributeCatalog.corkageKey, 'fee')
        .trim();
    return PlaceCorkage._(_policyOf(value), fee);
  }

  /// 플레이스 문서에서 바로 판정한다.
  factory PlaceCorkage.of(Map<String, dynamic> data) =>
      PlaceCorkage.fromAttributes(PlaceAttributes.fromDoc(data));

  static PlaceCorkagePolicy _policyOf(String? value) => switch (value) {
    null => PlaceCorkagePolicy.unset,
    PlaceAttributeCatalog.corkageNotAllowed => PlaceCorkagePolicy.notAllowed,
    PlaceAttributeCatalog.corkageFree => PlaceCorkagePolicy.free,
    PlaceAttributeCatalog.corkagePaid => PlaceCorkagePolicy.paid,
    PlaceAttributeCatalog.corkageAllowed => PlaceCorkagePolicy.allowed,
    // 카탈로그에 없는 값(앱 버전 차이)은 허용으로 보지 않는다 — 모르는 값을
    // "가능"으로 통과시키면 불가인 집이 필터에 섞인다(fail-closed).
    _ => PlaceCorkagePolicy.unset,
  };

  /// **필터 판정의 정본** — 🍶 콜키지 가능 필터가 이것 하나만 본다.
  ///
  /// 무료·유료·(무료유료 미상) 셋 다 통과한다. 불가와 미설정만 막는다.
  bool get isAllowed => switch (policy) {
    PlaceCorkagePolicy.free ||
    PlaceCorkagePolicy.paid ||
    PlaceCorkagePolicy.allowed => true,
    PlaceCorkagePolicy.notAllowed || PlaceCorkagePolicy.unset => false,
  };

  /// 목록 카드의 특징·혜택 배지 한 줄 — 허용하지 않으면 null(배지 없음).
  ///
  /// 유료이고 금액을 읽어낼 수 있으면 금액까지 짧게 적는다. 읽어낼 수 없으면
  /// **'콜키지 유료'까지만** 적는다 — 카드에 적힌 금액이 실제와 다르면
  /// 그 자리에서 신뢰를 잃는다.
  String? get cardBadge {
    switch (policy) {
      case PlaceCorkagePolicy.notAllowed:
      case PlaceCorkagePolicy.unset:
        return null;
      case PlaceCorkagePolicy.free:
        return '$_emoji 콜키지 무료';
      case PlaceCorkagePolicy.allowed:
        return '$_emoji 콜키지 가능';
      case PlaceCorkagePolicy.paid:
        final short = shortFee;
        return short == null ? '$_emoji 콜키지 유료' : '$_emoji $short';
    }
  }

  /// 상세페이지 한 줄 — 카드보다 자세히. 허용하지 않으면 null.
  ///
  ///   `🍶 콜키지 가능 · 무료`
  ///   `🍶 콜키지 가능 · 유료`
  ///   `🍶 콜키지 가능 · 유료 · 1병 10,000원`   ← 금액은 **저장된 원문 그대로**
  String? get detailText {
    switch (policy) {
      case PlaceCorkagePolicy.notAllowed:
      case PlaceCorkagePolicy.unset:
        return null;
      case PlaceCorkagePolicy.allowed:
        return '$_emoji 콜키지 가능';
      case PlaceCorkagePolicy.free:
        return '$_emoji 콜키지 가능 · 무료';
      case PlaceCorkagePolicy.paid:
        // 상세에서는 파싱한 요약이 아니라 호스트가 적은 원문을 그대로 보여준다
        // — '2인 이상 1병 무료, 이후 1병 10,000원' 같은 조건이 카드에서는
        // 잘리지만 여기서는 온전히 읽혀야 한다.
        return feeText.isEmpty
            ? '$_emoji 콜키지 가능 · 유료'
            : '$_emoji 콜키지 가능 · 유료 · $feeText';
    }
  }

  /// 카드에 넣을 짧은 금액 표기 — 읽어낼 수 없으면 null.
  ///
  ///   `'1병 10,000원'`  → `'병당 10,000원'`
  ///   `'20000'`         → `'콜키지 20,000원'`
  ///   `'문의'`          → null (금액이 없다 — 지어내지 않는다)
  String? get shortFee {
    final amount = _amountOf(feeText);
    if (amount == null) return null;
    final formatted = _formatWon(amount);
    return _mentionsBottle(feeText) ? '병당 $formatted' : '콜키지 $formatted';
  }

  /// '병'을 말하고 있는가 — '1병', '병당', '한 병' 등.
  static bool _mentionsBottle(String text) => text.contains('병');

  /// 자유 입력에서 **콜키지 금액**을 읽어낸다. 확신할 수 없으면 null.
  ///
  /// 입력란은 자유 텍스트라('예) 1병 10,000원') 숫자가 여럿 섞인다. 그래서
  /// 규칙을 둘로 좁힌다.
  ///
  ///  ① `'…원'` 앞에 붙은 숫자를 먼저 찾는다 — '1병 10,000원'에서 병 수(1)가
  ///     아니라 금액(10,000)을 집는 유일하게 확실한 단서다.
  ///  ② 그런 표기가 없으면 1,000 이상인 수 중 **가장 큰** 것을 금액으로 본다.
  ///     콜키지 비용이 1,000원 미만인 경우는 사실상 없고, 병 수·인원수 같은
  ///     작은 수와 섞이지 않는다.
  ///
  /// 둘 다 실패하면 null이다 — 그 경우 카드에는 '콜키지 유료'만 적힌다.
  static int? _amountOf(String text) {
    if (text.isEmpty) return null;

    final won = RegExp(r'([0-9][0-9,]*)\s*원').firstMatch(text);
    if (won != null) {
      final n = int.tryParse(won.group(1)!.replaceAll(',', ''));
      if (n != null && n > 0) return n;
    }

    int? best;
    for (final m in RegExp(r'[0-9][0-9,]*').allMatches(text)) {
      final n = int.tryParse(m.group(0)!.replaceAll(',', ''));
      if (n == null || n < 1000) continue;
      if (best == null || n > best) best = n;
    }
    return best;
  }

  /// 20000 → '20,000원'.
  static String _formatWon(int won) {
    final s = won.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '$b원';
  }
}
