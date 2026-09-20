// 지도 홈 상단 빠른 필터 **한 줄**의 폭 계산과 짧은 표기.
//
// 한 줄에 여덟 칸이 선다:
//   [전체][✨특징][파티][이벤트][플레이스][장소대여][🕐][₩]
//
// **한 줄 유지가 최우선**이다. 가로로 끌어야 보이거나 두 줄로 내려가면 안
// 된다. 그래서 다음 순서로 자리를 만든다(어떤 기기 폭도 숫자로 박지 않고,
// 실제 가용 폭으로 계산한다):
//   1. 칸마다 **자기 글자에 필요한 최소 폭**만 준다(남는 폭을 나눠 갖지
//      않는다 — 예전에는 여섯 칸이 남는 폭을 모두 나눠 가져 뚱뚱했다)
//   2. 좌우 안쪽 여백을 [basePad]에서 [minPad]까지 줄인다
//   3. 그래도 모자라면 🕐·₩의 값 글자를 떼고 아이콘만 남긴다(부르는 쪽)
//   4. 그래도 모자라면 글자 크기를 [minScale]까지 조금 줄인다
//   5. 그래도 안 되면(아주 좁은 화면) 그때만 가로로 넘긴다
import 'dart:math' as math;

/// 한 줄의 치수 — 화면과 테스트가 **같은 값**을 본다.
//
// 글자 크기와 높이는 예전 수준을 지키고(읽기 어려워지면 안 된다), 좌우 여백과
// 간격만 최소로 줄여 여덟 칸 자리를 만든다.
const double kQuickChipHeight = 40;
const double kQuickChipFontSize = 13.5;
/// 칸 사이 간격.
const double kQuickChipGap = 2;
/// 줄 좌우 바깥 여백.
const double kQuickRowSidePad = 3;
/// 칸 안쪽 좌우 여백 — 넉넉할 때.
const double kQuickChipBasePad = 7;
/// 칸 안쪽 좌우 여백 — 좁을 때 여기까지 줄인다.
const double kQuickChipMinPad = 2;
const double kQuickChipIconSize = 13;
const double kQuickChipIconGap = 2;
/// 🕐·₩ 버튼에서 아이콘과 짧은 값 사이 간격.
const double kQuickLabelGap = 3;

// 한 줄 배치 결과.
typedef QuickRowLayout = ({
  /// 칸마다의 최종 폭(순서 그대로).
  List<double> widths,

  /// 칸 안쪽 좌우 여백.
  double pad,

  /// 글자 크기 배율(1이면 그대로 줄이지 않음).
  double scale,

  /// 한 줄에 못 넣어 가로로 넘겨야 하는가(마지막 수단).
  bool scroll,
});

/// 글자 폭 [texts]와 아이콘 폭 [icons](칸마다 하나씩, 없으면 0)로 한 줄을 짠다.
///
/// [available]은 **칸들이 나눠 쓸 수 있는 폭**이다(줄 좌우 여백과 칸 사이
/// 간격을 이미 뺀 값). 글자를 줄일 때 아이콘은 그대로 두므로 아이콘 폭은
/// 배율에서 빠진다.
QuickRowLayout quickRowLayout({
  required List<double> texts,
  required List<double> icons,
  required double available,
  required double basePad,
  required double minPad,
  double minScale = 0.85,
}) {
  assert(texts.length == icons.length);
  final n = texts.length;
  if (n == 0) {
    return (widths: const [], pad: basePad, scale: 1, scroll: false);
  }
  final textSum = texts.fold<double>(0, (a, b) => a + b);
  final iconSum = icons.fold<double>(0, (a, b) => a + b);
  final contentSum = textSum + iconSum;

  List<double> widthsWith(double pad, double scale) => [
    for (var i = 0; i < n; i++) texts[i] * scale + icons[i] + pad * 2,
  ];

  // 1·2. 여백을 기본에서 최소까지 줄여 본다.
  if (contentSum + basePad * 2 * n <= available) {
    return (
      widths: widthsWith(basePad, 1),
      pad: basePad,
      scale: 1,
      scroll: false,
    );
  }
  if (contentSum + minPad * 2 * n <= available) {
    final pad = (available - contentSum) / (2 * n);
    return (widths: widthsWith(pad, 1), pad: pad, scale: 1, scroll: false);
  }

  // 4. 글자만 줄인다(아이콘·여백은 이미 최소).
  final room = available - minPad * 2 * n - iconSum;
  final scale = textSum <= 0 ? 1.0 : room / textSum;
  if (scale >= minScale) {
    final s = math.min(scale, 1.0);
    return (widths: widthsWith(minPad, s), pad: minPad, scale: s, scroll: false);
  }
  // 5. 마지막 수단 — 가로로 넘긴다(글자를 더 줄이지는 않는다).
  return (
    widths: widthsWith(minPad, minScale),
    pad: minPad,
    scale: minScale,
    scroll: true,
  );
}

/// 💳 가격 칸 고름 — 종류마다 쓰던 칸을 그대로 담는다(새 체계가 아니다).
class MapPriceSelection {
  const MapPriceSelection({
    this.partyFees = const {},
    this.placeRanges = const {},
    this.rentalRanges = const {},
  });

  /// 🎉 파티 참가비 — [PartyFilter.feeRanges].
  final Set<String> partyFees;

  /// 🏬 플레이스 가격대 — [EventFilter.priceRanges].
  final Set<String> placeRanges;

  /// 🏠 장소대여 가격 — [PlaceFilter.priceRanges].
  final Set<String> rentalRanges;

  bool get isEmpty =>
      partyFees.isEmpty && placeRanges.isEmpty && rentalRanges.isEmpty;

  bool get isActive => !isEmpty;

  int get count => partyFees.length + placeRanges.length + rentalRanges.length;

  /// 고른 칸 전부(중복은 하나로) — 한 칸만 골랐을 때 짧게 적으려고 쓴다.
  Set<String> get all => {...partyFees, ...placeRanges, ...rentalRanges};

  MapPriceSelection copyWith({
    Set<String>? partyFees,
    Set<String>? placeRanges,
    Set<String>? rentalRanges,
  }) => MapPriceSelection(
    partyFees: partyFees ?? this.partyFees,
    placeRanges: placeRanges ?? this.placeRanges,
    rentalRanges: rentalRanges ?? this.rentalRanges,
  );

  static const MapPriceSelection none = MapPriceSelection();
}

/// ₩ 버튼에 붙일 **아주 짧은** 값. 조건이 없으면 null(아이콘만).
///
/// 한 칸만 고르면 그 칸을 줄여 적고('3~5만원' → '3~5만'), 여러 칸이면 개수만
/// 적는다. 한 줄이 깨질 것 같으면 부르는 쪽이 이 값을 버리고 아이콘만 쓴다.
String? mapPriceFilterLabel(MapPriceSelection selection) {
  if (selection.isEmpty) return null;
  final all = selection.all;
  if (all.length == 1) {
    final one = all.first;
    if (one == '무료') return '무료';
    // '3만원 이하' → '3만 이하', '3~5만원' → '3~5만', '20만원 이상' → '20만+'
    final short = one.replaceAll('만원', '만');
    if (short.endsWith(' 이상')) {
      return '${short.substring(0, short.length - 3)}+';
    }
    return short;
  }
  return '가격 ${selection.count}';
}
