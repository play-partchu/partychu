/// 대분류별 **하위 탐색(드릴다운)**과 **빠른 필터 한 줄**의 정본.
///
/// ── 왜 한 타입으로 묶는가 ─────────────────────────────────────────────────
/// 두 줄은 생김새도 위치도 다르지만 하는 일은 같다 — "칩 하나를 눌러 조건 하나를
/// 켜고 끈다". 다른 점은 **어느 축을 켜느냐**뿐이다:
///
///   · 클럽 → 힙합        = 음악 장르   ([EventFilter.attributes] musicGenres)
///   · 이벤트 → 생일      = 이벤트 갈래 ([EventFilter.eventKinds])
///   · 콜키지프리 · 구워주는집 = 특징    ([EventFilter.features])
///   · 무제한 → 하이볼    = 속성 시트   ([EventFilter.attributes] unlimited)
///   · 업종 → 고기·BBQ    = 소분류 시트 ([EventFilter.subcategories])
///
/// 마지막 둘이 예외처럼 보이지만 실은 같다 — 칩은 여전히 하나고, 다만 고를
/// 것이 여럿이라 **누르면 켜는 대신 세부종류 시트를 연다**
/// (무제한은 이제 자기 칩이 아니라 ✨ 편의·서비스 시트 안의 한 묶음이다)
/// ([PlacePickAxis.sheet]). 무제한처럼 업종마다 뜻이 다른 조건을 boolean 한
/// 칸으로 두면 "무엇이 무제한인지"를 영영 검색할 수 없고, 푸드 소분류처럼
/// 열넷짜리 갈래를 한 줄에 깔면 앞 서너 칸 말고는 아무도 못 본다.
///
/// 그래서 축을 아는 것은 [PlaceQuickPick] 하나로 두고, 드릴다운 줄과 빠른필터
/// 줄은 "받은 칩을 그리기만" 한다. 판정은 어느 쪽도 새로 쓰지 않는다 —
/// 전부 [EventFilter.matchesDiscovery] 하나가 예전 그대로 한다.
///
/// ── 왜 업종마다 다른가 ────────────────────────────────────────────────────
/// 모든 업종에 같은 열여섯 칸을 보여주면(핫플·무제한·콜키지·수영장 …) 카페를
/// 보는 사람이 '콜키지 가능'을, 클럽을 보는 사람이 '반려동물'을 지나쳐야
/// 한다. 정작 그 업종에서 가장 많이 묻는 조건은 줄 끝으로 밀려 안 보인다.
///
/// ── 새 필드를 만들지 않는다 ───────────────────────────────────────────────
/// 여기 있는 값은 전부 이미 있는 것들이다 — [PlaceFeatures]의 특징 키,
/// [PlaceAttributeCatalog]의 속성 값, [PlaceTaxonomy]의 소분류,
/// [PlaceEventTaxonomy]의 갈래. 옛 문서도 그대로 걸린다(특징은
/// [PlaceFeatures.of]가 themeTags·petPolicy·영업시간에서 유도하고, 옛 클럽
/// 소분류는 [PlaceTaxonomy.legacyClubGenresOf]가 장르로 읽어 준다).
library;

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_event_taxonomy.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_taxonomy.dart';

/// 칩 하나가 켜고 끄는 축.
enum PlacePickAxis {
  /// [EventFilter.features] — AND.
  feature,

  /// [EventFilter.attributes]의 한 그룹 — 그룹 안 OR.
  attribute,

  /// [EventFilter.subcategories] — OR.
  subcategory,

  /// [EventFilter.eventKinds] — OR.
  eventKind,

  /// [EventFilter]의 on/off 스위치 하나(지금은 '현재 영업 중'). 축을 새로
  /// 만든 게 아니라 이미 있던 필드를 칩으로 노출하는 것뿐이다.
  openNow,

  /// 🎉 With파티 — [EventFilter.withPartyOnly] on/off. [openNow]와 같은
  /// 성격이다(이미 있던 필드를 칩으로 노출할 뿐, 저장값도 판정도 새로
  /// 만들지 않는다 — 판정의 정본은 [PlacePartyIndex]다).
  withParty,

  /// **세부종류를 작은 시트에서** 고르는 칩(♾ 무제한 · 🍽 업종).
  ///
  /// 무제한은 업종마다 뜻이 달라서(뷔페·고기·맥주·노래방 시간·이용시간 …)
  /// 값 하나짜리 칩으로 두면 검색이 안 되고, 값마다 칩을 두면 빠른필터 줄이
  /// 아홉 칸 길어진다. 그래서 **줄에는 칩 하나만** 두고 세부종류는 눌렀을 때
  /// 시트에서 고른다 — 켜고 끄는 값은 안에 든 칩([options])이 그대로 든다.
  ///
  /// 시트 안 칩이 무슨 축인지는 상관하지 않는다 — 무제한은 [attribute],
  /// 푸드 업종은 [subcategory]다. 시트는 "칩 여럿을 담는 그릇"일 뿐이라
  /// 축이 늘어도 여는 쪽·그리는 쪽은 그대로다.
  sheet,
}

/// 탐색 칩 하나 — 드릴다운 줄과 빠른필터 줄이 함께 쓴다.
class PlaceQuickPick {
  /// 특징 칩. [label]을 주면 그 문구로 적는다 — 좁은 빠른필터 줄에서만 짧게
  /// 부르고 싶을 때다('🔥 구워주는 집' → '🔥 구워줘요'). 켜는 값은 그대로
  /// [PlaceFeature.key]라, 상세필터·판정은 아무것도 달라지지 않는다.
  PlaceQuickPick.feature(String key, {String? label})
    : axis = PlacePickAxis.feature,
      groupKey = null,
      values = [key],
      options = const [],
      recommended = 0,
      _label = label;

  /// 속성 값 칩. [values]에 여러 개를 주면 **하나의 칩이 그 값들 전체**를
  /// 뜻한다('힙합·R&B' = HIPHOP 또는 R&B) — 그룹 안이 OR이므로 자연스럽게
  /// 읽히고, 저장값을 합치지 않으므로 데이터는 갈라진 채로 남는다.
  PlaceQuickPick.attribute(String group, List<String> values, {String? label})
    : axis = PlacePickAxis.attribute,
      groupKey = group,
      // ignore: prefer_initializing_formals
      values = values,
      options = const [],
      recommended = 0,
      _label = label;

  /// **속성 세부종류를 시트에서 고르는** 칩(♾ 무제한). 줄에는 이 칩 하나만
  /// 나가고, [options]에 담긴 속성 칩들이 시트 안에 그려진다.
  ///
  /// 시트 안 칩은 전부 평범한 [PlaceQuickPick.attribute]다 — 켜고 끄는 방법도,
  /// 판정도 새로 만들지 않는다([EventFilter.matchesDiscovery] 그대로).
  PlaceQuickPick.attributeSheet(
    String group,
    this.options, {
    required String label,
    required String sheetHint,
    String? sheetTitle,
    String otherLabel = '다른 갈래',
    this.recommended = 0,
  }) : axis = PlacePickAxis.sheet,
       groupKey = group,
       values = const [],
       _label = label {
    _emoji = PlaceAttributeCatalog.groupOf(group)?.emoji ?? '';
    _sheetTitle = sheetTitle;
    _sheetHint = sheetHint;
    _otherLabel = otherLabel;
  }

  /// **속성 그룹이 아닌 칩들을 시트에서 고르는** 칩(🍽 업종 · ✨ 편의·서비스).
  ///
  /// 무제한 시트와 다른 것은 안에 든 칩의 축뿐이다 — 업종은
  /// [PlaceQuickPick.subcategory]라 [EventFilter.subcategories]를,
  /// 편의·서비스는 [PlaceQuickPick.feature]라 [EventFilter.features]를 켠다.
  /// 여는 방법도, 그리는 시트도, 판정도 무제한과 완전히 같다.
  ///
  /// 속성 그룹이 없으므로 [groupKey]는 null이다 — 이모지를 직접 받는다.
  /// [extra]를 주면 시트 **맨 아래에 따로 묶여** 나간다([extraLabel]이 그
  /// 묶음의 소제목). ♾ 무제한이 그 자리다 — 줄에서 독립 칩을 없애고 이
  /// 시트 안으로 들어왔지만, 특징(AND)과 뜻이 달라(그중 하나라도 = OR)
  /// 추천·다른 편의·서비스에 섞어 놓으면 같은 규칙처럼 읽힌다.
  ///
  /// 담기고 나면 [options]의 일부라, 켜졌는지 세는 것도 초기화도 칩 이름도
  /// 예전 그대로 동작한다(새 상태를 만들지 않는다).
  PlaceQuickPick.optionSheet(
    List<PlaceQuickPick> options, {
    required String label,
    required String emoji,
    required String sheetHint,
    String? sheetTitle,
    String otherLabel = '다른 조건',
    this.recommended = 0,
    List<PlaceQuickPick> extra = const [],
    String extraLabel = '',
  }) : axis = PlacePickAxis.sheet,
       groupKey = null,
       values = const [],
       options = [...options, ...extra],
       _label = label {
    _emoji = emoji;
    _sheetTitle = sheetTitle;
    _sheetHint = sheetHint;
    _otherLabel = otherLabel;
    _extraFrom = extra.isEmpty ? null : this.options.length - extra.length;
    _extraLabel = extraLabel;
  }

  /// 소분류 칩. [values]에 여러 개를 주면 **하나의 칩이 그 값들 전체**를
  /// 뜻한다 — 소분류도 그룹 안이 OR이라 "그중 하나라도"로 자연스럽게 읽힌다.
  ///
  /// 켤 때는 **첫 값만** 저장한다([values]`.first`). 나머지는 옛 문서를 잇는
  /// 값이라(예: '글로벌 푸드'로 묶기 전의 '멕시칸'), 새로 고른 사람의 필터에
  /// 여섯 값을 한꺼번에 심으면 상세검색 화면이 여섯 칸 켜진 채로 보인다.
  /// 그 대신 켜졌는지 볼 때와 끌 때는 옛 값도 함께 본다 — 상세검색에서 옛
  /// 값을 켜 두었어도 이 칩이 켜진 것으로 보이고, 여기서 끌 수 있다.
  /// 매칭 쪽 다리는 [PlaceTaxonomy.expandGlobalFood]가 놓는다.
  PlaceQuickPick.subcategory(List<String> values, {String? label})
    : axis = PlacePickAxis.subcategory,
      groupKey = null,
      // ignore: prefer_initializing_formals
      values = values,
      options = const [],
      recommended = 0,
      _label = label;

  PlaceQuickPick.eventKind(String key)
    : axis = PlacePickAxis.eventKind,
      groupKey = null,
      values = [key],
      options = const [],
      recommended = 0,
      _label = null;

  /// '지금 영업 중인 곳만' — [EventFilter.openNowOnly]를 그대로 켠다.
  PlaceQuickPick.openNow()
    : axis = PlacePickAxis.openNow,
      groupKey = null,
      values = const [],
      options = const [],
      recommended = 0,
      _label = '🟢 지금 영업중';

  /// '🎉 With파티' — [EventFilter.withPartyOnly]를 그대로 켠다.
  ///
  /// 예전에는 상단 카테고리 격자의 칸 하나였다. 그 줄은 '무슨 가게인가'를
  /// 고르는 자리라 With파티만 성격이 달랐고, 누르면 카테고리가 바뀌는
  /// 것처럼 읽혔다. 지금은 **✨ 편의·서비스 시트 안의 한 항목**이다 —
  /// 자리만 옮긴 것이라 이름·저장값·연결 판정은 하나도 달라지지 않는다.
  PlaceQuickPick.withParty()
    : axis = PlacePickAxis.withParty,
      groupKey = null,
      values = const [],
      options = const [],
      recommended = 0,
      _label = '🎉 With파티';

  final PlacePickAxis axis;

  /// 속성 칩일 때만 — `placeAttributes`의 그룹 키.
  final String? groupKey;

  /// 이 칩이 켜고 끄는 저장값들. 대부분 하나다.
  /// 시트 칩([PlacePickAxis.attributeSheet])은 비어 있다 — 값은 [options]가 든다.
  final List<String> values;

  /// 시트 칩일 때만 — 시트 안에 그릴 세부종류 칩들.
  final List<PlaceQuickPick> options;

  /// 시트에서 **앞쪽 몇 칸이 추천 영역인가**. 0이면 나누지 않는다.
  ///
  /// 표시만 가르는 값이다 — 뒤쪽 칸도 똑같이 고르고 끌 수 있어야 한다. 업종에
  /// 안 맞는 갈래를 시트에서 빼 버리면, 다른 업종에서 켜 둔 조건을 끌 자리가
  /// 사라져 "안 보이는데 걸려 있는" 상태가 된다.
  final int recommended;

  /// 시트 안 추천 영역의 칸들.
  List<PlaceQuickPick> get recommendedOptions =>
      options.take(recommended).toList();

  /// 추천과 [extraOptions] 사이의 나머지 칸들.
  List<PlaceQuickPick> get otherOptions => options
      .skip(recommended)
      .take((_extraFrom ?? options.length) - recommended)
      .toList();

  /// 시트 맨 아래에 **따로 묶여** 나가는 칸들(♾ 무제한). 없으면 빈 목록.
  List<PlaceQuickPick> get extraOptions =>
      _extraFrom == null ? const [] : options.skip(_extraFrom!).toList();

  /// 그 묶음의 소제목('♾ 무제한').
  String get sheetExtraLabel => _extraLabel;

  final String? _label;

  // 아래 넷은 시트 칩에서만 뜻이 있다. 생성자 본문에서 채우므로 final이
  // 아니지만, 만든 뒤에는 아무도 고치지 않는다(읽기 전용 게터만 낸다).
  String _emoji = '';
  String? _sheetTitle;
  String _sheetHint = '';
  String _otherLabel = '';
  int? _extraFrom;
  String _extraLabel = '';

  /// 시트를 여는 칩인가 — 바가 "누르면 켠다" 대신 "누르면 연다"로 갈라진다.
  bool get opensSheet => axis == PlacePickAxis.sheet;

  /// 시트 맨 위에 적히는 제목. 안 주면 칩 이름 그대로다('♾ 무제한').
  String get sheetTitle => _sheetTitle ?? display;

  /// 제목 아래 한 줄 안내 — 무엇을 고르는 자리인지.
  String get sheetHint => _sheetHint;

  /// 추천 영역 뒤에 오는 묶음의 소제목('다른 무제한' · '다른 업종').
  String get sheetOtherLabel => _otherLabel;

  /// 이 칩이 실제로 켜는 저장값 전부 — 시트 칩은 자식들의 값을 합친 것이다.
  /// 상세필터 배지가 "줄에 보이는 조건"을 빼고 셀 때 쓴다.
  List<String> get allValues =>
      opensSheet ? [for (final o in options) ...o.values] : values;

  /// 칸에 적히는 표기.
  String get display {
    final custom = _label;
    if (custom != null) return custom;
    return switch (axis) {
      PlacePickAxis.feature => PlaceFeatures.displayOf(values.first),
      PlacePickAxis.eventKind => PlaceEventTaxonomy.displayOf(values.first),
      PlacePickAxis.subcategory => values.first,
      PlacePickAxis.attribute => _attributeDisplay(),
      PlacePickAxis.sheet => _label ?? _attributeDisplay(),
      PlacePickAxis.openNow => '🟢 지금 영업중',
      PlacePickAxis.withParty => '🎉 With파티',
    };
  }

  /// 지금 필터 상태에서 칸에 적히는 표기.
  ///
  /// 시트 칩은 **고른 세부종류를 칩 자신이 말한다** — 메인에 선택칩을 따로
  /// 쌓지 않기로 했으므로("♾ 무제한" 아래에 "하이볼 ×"를 또 붙이지 않는다),
  /// 무엇을 골랐는지 알려 줄 자리가 이 칸 하나뿐이다.
  ///   · 아무것도 안 고름 → '♾ 무제한'      · '🍽 업종'   · '✨ 편의·서비스'
  ///   · 하나            → '♾ 하이볼·주류 무제한' · '🍽 고기·BBQ' · '🔥 구워줘요'
  ///   · 여럿            → '♾ 무제한 3'      · '🍽 업종 3' · '✨ 편의·서비스 3'
  String displayFor(EventFilter filter) {
    if (!opensSheet) return display;
    final on = options.where((o) => o.isOn(filter)).toList();
    if (on.isEmpty) return display;
    // 고른 것이 하나면 그 이름을 그대로 말한다. 다만 특징 칩은 **이미 자기
    // 이모지를 달고 있어서**('🔥 구워줘요') 시트 이모지를 앞에 또 붙이면
    // '✨ 🔥 구워줘요'가 된다 — 그때는 칩 이름만 쓴다.
    if (on.length == 1) {
      final one = on.first;
      if (one._hasOwnEmoji) return one.display;
      // 속성 칩은 자기 그룹 이모지를 쓴다 — 편의·서비스 시트가 든 무제한을
      // 고르면 '✨ 뷔페·음식 무제한'이 아니라 '♾ 뷔페·음식 무제한'이다.
      final emoji = one._groupEmoji ?? _emoji;
      return '$emoji ${one.display}'.trim();
    }
    return '$display ${on.length}';
  }

  /// 이 칩의 표기가 **자기 이모지를 이미 달고 있는가**.
  /// 특징은 [PlaceFeature.display]가 '🔥 구워주는 집'처럼 이모지째 준다.
  /// With파티도 이름에 🎉를 달고 있어 시트 이모지를 앞에 또 붙이면
  /// '✨ 🎉 With파티'가 된다.
  bool get _hasOwnEmoji =>
      axis == PlacePickAxis.feature || axis == PlacePickAxis.withParty;

  /// 속성 칩이 속한 그룹의 이모지(♾ 등). 속성 칩이 아니면 null.
  String? get _groupEmoji {
    final g = groupKey;
    if (g == null || axis != PlacePickAxis.attribute) return null;
    return PlaceAttributeCatalog.groupOf(g)?.emoji;
  }

  String _attributeDisplay() {
    final emoji = PlaceAttributeCatalog.groupOf(groupKey!)?.emoji;
    final text = values.join('·');
    return emoji == null ? text : '$emoji $text';
  }

  /// 좁은 드릴다운 줄에 쓰는 짧은 표기 — 이모지를 빼고 이름만.
  String get shortLabel {
    final custom = _label;
    if (custom != null) return custom;
    return switch (axis) {
      PlacePickAxis.feature => PlaceFeatures.labelOf(values.first),
      PlacePickAxis.eventKind =>
        PlaceEventTaxonomy.byKey(values.first)?.shortLabel ?? values.first,
      _ => values.join('·'),
    };
  }

  bool isOn(EventFilter filter) => switch (axis) {
    PlacePickAxis.feature => filter.isFeatureOn(values.first),
    // 값이 여럿인 칩은 **하나라도 켜져 있으면** 켜진 것으로 본다 — 옛 나라별
    // 소분류가 상세검색에서 켜져 있어도 '글로벌푸드' 칩이 켜져 보인다.
    PlacePickAxis.subcategory => values.any(filter.subcategories.contains),
    PlacePickAxis.eventKind => filter.isEventKindOn(values.first),
    PlacePickAxis.openNow => filter.openNowOnly,
    PlacePickAxis.withParty => filter.withPartyOnly,
    // 값이 여럿인 칩은 **하나라도 켜져 있으면** 켜진 것으로 본다.
    PlacePickAxis.attribute => values.any(
      (v) => filter.isAttributeOn(groupKey!, v),
    ),
    PlacePickAxis.sheet => options.any((o) => o.isOn(filter)),
  };

  void toggle(EventFilter filter) {
    switch (axis) {
      case PlacePickAxis.feature:
        filter.toggleFeature(values.first);
      case PlacePickAxis.subcategory:
        // 켤 때는 첫 값(정본)만 심고, 끌 때는 이 칩이 아우르는 옛 값까지
        // 모두 걷어낸다 — 끄고 나면 아무 흔적도 남지 않아야 한다.
        if (isOn(filter)) {
          filter.subcategories.removeAll(values);
        } else {
          filter.subcategories.add(values.first);
        }
      case PlacePickAxis.eventKind:
        filter.toggleEventKind(values.first);
      case PlacePickAxis.openNow:
        filter.openNowOnly = !filter.openNowOnly;
      case PlacePickAxis.withParty:
        // 켜고 끄는 값은 예전 그대로 하나다 — 화면에서 자리만 옮겼다.
        filter.withPartyOnly = !filter.withPartyOnly;
      case PlacePickAxis.attribute:
        // 켜져 있으면 이 칩이 든 값을 **모두** 끄고, 아니면 모두 켠다 —
        // 칩 하나가 곧 한 덩어리라 반쯤 켜진 상태를 만들지 않는다.
        final on = isOn(filter);
        for (final v in values) {
          if (filter.isAttributeOn(groupKey!, v) == on) {
            filter.toggleAttribute(groupKey!, v);
          }
        }
      case PlacePickAxis.sheet:
        // 시트 칩은 눌러서 켜는 것이 아니라 **여는** 것이다(바가 시트를 띄운다).
        // 그래도 여기로 들어오면 "다 끈다"가 유일하게 뜻이 통하는 동작이다.
        clear(filter);
    }
  }

  /// 이 칩이 켜 둔 값을 전부 끈다 — 시트의 '초기화'가 부른다.
  void clear(EventFilter filter) {
    if (opensSheet) {
      for (final o in options) {
        if (o.isOn(filter)) o.toggle(filter);
      }
      return;
    }
    if (isOn(filter)) toggle(filter);
  }
}

class PlaceQuickPicks {
  PlaceQuickPicks._();

  static const String _unlimited = PlaceAttributeCatalog.unlimitedKey;
  static const String _alcohol = 'alcoholTypes';
  static const String _genres = PlaceAttributeCatalog.musicGenresKey;
  static const String _playItems = PlaceAttributeCatalog.playItemsKey;
  static const String _clubEntry = PlaceAttributeCatalog.clubEntryKey;

  static PlaceQuickPick _f(PlaceFeature f) => PlaceQuickPick.feature(f.key);

  /// 빠른필터 줄에서만 쓰는 짧은 이름 — 저장값도 특징 이름도 바꾸지 않는다.
  static PlaceQuickPick _short(PlaceFeature f, String label) =>
      PlaceQuickPick.feature(f.key, label: label);

  /// '🔥 구워줘요' — 줄이 좁아서 짧게 부른다. 상세필터에서는 '🔥 구워주는 집'
  /// 그대로다([PlaceFeatures.grill]).
  static PlaceQuickPick get _grillChip =>
      _short(PlaceFeatures.grill, '🔥 구워줘요');

  // ── ♾ 무제한 세부종류 ──────────────────────────────────────────────────
  //
  // 무제한은 업종마다 뜻이 다르다 — 고깃집은 고기가, 노래방은 시간이, 카페는
  // 음료가 무제한이다. 그래서 칩 하나에 boolean으로 담지 않고 **세부종류를 가진
  // 구조**로 두되, 메인 줄이 아홉 칸 길어지지 않도록 시트에서 고르게 한다.
  //
  // 시트에는 **언제나 아홉 갈래 전부**를 넣고, 그 업종에서 실제로 있을 법한
  // 것만 앞쪽 '추천' 영역으로 올린다([_unlimitedHead]). 갈래를 아예 잘라내면
  // 카페를 보는 사람은 다른 업종에서 켜 둔 '노래방 시간 무제한'을 어디서도 끌
  // 수 없게 된다 — 안 보이는데 걸려 있는 조건이 생긴다.

  /// 갈래 하나 — (게스트에게 보이는 문구, 그것이 켜는 저장값들).
  ///
  /// 저장값은 [PlaceAttributeCatalog]의 것 그대로다. '하이볼·주류'처럼 한 칩이
  /// 여러 값을 켜는 것은 그룹 안이 OR이라서 자연스럽게 "셋 중 하나라도"가 된다
  /// — 저장값을 합치지 않으므로 데이터는 갈라진 채로 남는다.
  static const Map<String, (String, List<String>)> _unlimitedKinds = {
    'buffet': ('뷔페·음식 무제한', [PlaceAttributeCatalog.unlimitedFood]),
    'meat': ('고기·BBQ 무제한', [PlaceAttributeCatalog.unlimitedMeat]),
    'beer': ('맥주 무제한', [PlaceAttributeCatalog.unlimitedBeer]),
    'alcohol': (
      '하이볼·주류 무제한',
      [
        PlaceAttributeCatalog.unlimitedHighball,
        PlaceAttributeCatalog.unlimitedAlcohol,
        PlaceAttributeCatalog.unlimitedWine,
      ],
    ),
    'drink': ('음료 무제한', [PlaceAttributeCatalog.unlimitedDrink]),
    'karaoke': ('노래방 시간 무제한', [PlaceAttributeCatalog.unlimitedKaraokeTime]),
    'play': ('놀거리 이용 무제한', [PlaceAttributeCatalog.unlimitedPlay]),
    'time': ('이용시간 무제한', [PlaceAttributeCatalog.unlimitedStayTime]),
    'etc': ('기타 무제한', [PlaceAttributeCatalog.unlimitedEtc]),
  };

  /// 업종별 **추천 갈래**. 이 순서 그대로 시트 위쪽에 오고, 나머지는 정의
  /// 순서대로 아래 '다른 무제한'에 붙는다.
  static const Map<String, List<String>> _unlimitedHead = {
    // 푸드 — 고기·음식·맥주·하이볼·와인·주류·음료가 전부 앞으로 온다
    // ('alcohol' 한 칸이 하이볼·주류·와인 셋을 든다).
    '맛집': ['meat', 'buffet', 'beer', 'alcohol', 'drink'],
    // 다이닝 — 무제한을 파는 자리는 아니지만, 와인·주류 무제한을 내는
    // 코스가 있다. 먹는 것보다 마시는 것이 앞이다.
    '다이닝·파인다이닝': ['alcohol', 'meat', 'buffet', 'drink'],
    '술집': ['meat', 'beer', 'alcohol', 'buffet', 'drink'],
    '카페·디저트': ['drink', 'buffet', 'time'],
    'BAR': ['alcohol', 'beer', 'drink'],
    '혼술바': ['alcohol', 'beer', 'drink'],
    '클럽': ['alcohol', 'beer', 'drink', 'time'],
    // 놀거리 — 여기서 무제한은 먹는 것이 아니라 **시간과 이용**이다.
    '놀거리': ['karaoke', 'play', 'time'],
    '체험·클래스': ['time', 'play', 'buffet', 'meat'],
    '라이브·공연': ['alcohol', 'beer', 'drink', 'time'],
  };

  /// 이 업종의 추천 갈래 id들 — 없으면 빈 목록(= 시트를 나누지 않는다).
  static List<String> _unlimitedHeadOf(String? category) =>
      _unlimitedHead[category == null
          ? null
          : PlaceTaxonomy.canonical(category)] ??
      const <String>[];

  /// 시트 안에 그릴 세부종류 칩들 — 아홉 갈래 전부, 추천이 앞.
  static List<PlaceQuickPick> unlimitedKinds(String? category) {
    final head = _unlimitedHeadOf(category);
    final ids = [
      ...head,
      for (final id in _unlimitedKinds.keys)
        if (!head.contains(id)) id,
    ];
    return [
      for (final id in ids)
        PlaceQuickPick.attribute(
          _unlimited,
          _unlimitedKinds[id]!.$2,
          label: _unlimitedKinds[id]!.$1,
        ),
    ];
  }

  // 메인 줄의 독립 '♾ 무제한' 칩은 없앴다 — 같은 갈래를 ✨ 편의·서비스 시트
  // 맨 아래 '♾ 무제한' 묶음이 그대로 받는다([amenityChip]). 줄에는 이제
  // '✨ 편의·서비스'와 '＋ 조건'만 남는다.

  // ── ✨ 편의·서비스 ─────────────────────────────────────────────────────
  //
  // 예전에는 특징 칩(구워줘요·콜키지 가능·프라이빗·단체석·금연·주차 …)이 줄에
  // 그대로 열 칸씩 늘어서 있었다. 좁은 화면에 보이는 것은 앞 서너 칸이라,
  // 나머지는 옆으로 한참 밀어야 나오고 정작 '♾ 무제한'·'🍽 업종'처럼 먼저
  // 물어야 할 칩까지 함께 밀려났다.
  //
  // 그래서 **무제한·업종과 똑같이** 줄에는 칩 하나('✨ 편의·서비스')만 두고
  // 시트에서 고른다. 켜고 끄는 값은 예전 그대로 [EventFilter.features]이고,
  // 판정도 [PlaceFeatures.matchesAll] 그대로다 — 특징끼리는 **AND**라 두 개를
  // 고르면 둘 다 되는 곳만 남는다(무제한이 OR인 것과 다르다).

  /// 업종별 **추천 특징**. 이 순서 그대로 시트 위쪽에 오고, 나머지는
  /// [PlaceFeatures.selectable] 순서대로 아래 '다른 편의·서비스'에 붙는다.
  ///
  /// 값은 예전에 그 업종 줄에 깔려 있던 특징들을 **그 순서 그대로** 옮긴 것이다
  /// — 어느 업종에서 무엇을 먼저 묻는지는 이미 정해져 있었고, 묶는다고 그
  /// 판단까지 새로 할 이유가 없다.
  static final Map<String, List<PlaceFeature>> _amenityHead = {
    PlaceTaxonomy.restaurant.label: [
      PlaceFeatures.grill,
      // 🔥 구워줘요 바로 옆 — 다른 질문이라 나란히 보여야 구분된다.
      PlaceFeatures.cookedServed,
      PlaceFeatures.corkageAvailable,
      PlaceFeatures.groupSeat,
      PlaceFeatures.private,
      PlaceFeatures.birthday,
      PlaceFeatures.outsideFood,
      PlaceFeatures.bbq,
      PlaceFeatures.smokeFree,
      PlaceFeatures.smokingArea,
      PlaceFeatures.parking,
      PlaceFeatures.hot,
    ],
    // 다이닝 — 자리와 예약이 먼저다. 코스를 여는 자리라 프라이빗·단체석이
    // 맨 앞이고, 술을 들고 가는 콜키지가 그 옆이다.
    PlaceTaxonomy.dining.label: [
      PlaceFeatures.private,
      PlaceFeatures.corkageAvailable,
      // 🔥 구워줘요 → 🍽️ 조리되어 나와요는 **언제나 붙어 있어야 한다** —
      // 구워주는 서비스를 묻는 업종이면 어디서든 그렇다(다른 질문이라
      // 나란히 서야 호스트가 차이를 알아챈다). 자리에서 구워 주는 한우
      // 파인다이닝이 있으므로 다이닝도 이 짝을 그대로 받는다.
      PlaceFeatures.grill,
      PlaceFeatures.cookedServed,
      PlaceFeatures.groupSeat,
      PlaceFeatures.birthday,
      PlaceFeatures.parking,
      PlaceFeatures.smokeFree,
      PlaceFeatures.hot,
    ],
    PlaceTaxonomy.cafe.label: [
      PlaceFeatures.hot,
      PlaceFeatures.play,
      PlaceFeatures.bigScreen,
      PlaceFeatures.soloFriendly,
      PlaceFeatures.private,
      PlaceFeatures.groupSeat,
      PlaceFeatures.cakeBringIn,
      PlaceFeatures.pet,
      PlaceFeatures.smokeFree,
      PlaceFeatures.parking,
    ],
    PlaceTaxonomy.pub.label: [
      PlaceFeatures.grill,
      // 🔥 구워줘요 바로 옆 — 다른 질문이라 나란히 보여야 구분된다.
      PlaceFeatures.cookedServed,
      PlaceFeatures.corkageAvailable,
      PlaceFeatures.play,
      PlaceFeatures.groupSeat,
      PlaceFeatures.lateNight,
      PlaceFeatures.bigScreen,
      PlaceFeatures.private,
      PlaceFeatures.smokeFree,
      PlaceFeatures.smokingArea,
      PlaceFeatures.parking,
      PlaceFeatures.hot,
    ],
    PlaceTaxonomy.soloBar.label: [
      PlaceFeatures.barSeat,
      PlaceFeatures.lateNight,
      PlaceFeatures.soloFriendly,
      PlaceFeatures.corkageAvailable,
      PlaceFeatures.smokeFree,
      PlaceFeatures.smokingArea,
    ],
    PlaceTaxonomy.bar.label: [
      PlaceFeatures.barSeat,
      PlaceFeatures.corkageAvailable,
      PlaceFeatures.dj,
      PlaceFeatures.private,
      PlaceFeatures.lateNight,
      PlaceFeatures.soloFriendly,
      PlaceFeatures.smokeFree,
      PlaceFeatures.smokingArea,
    ],
    PlaceTaxonomy.club.label: [
      PlaceFeatures.dj,
      PlaceFeatures.tableReservation,
      PlaceFeatures.lateNight,
      PlaceFeatures.smokingArea,
      PlaceFeatures.smokeFree,
      PlaceFeatures.private,
      PlaceFeatures.bigScreen,
      PlaceFeatures.hot,
    ],
    PlaceTaxonomy.live.label: [
      PlaceFeatures.live,
      PlaceFeatures.dj,
      PlaceFeatures.lateNight,
      PlaceFeatures.groupSeat,
      PlaceFeatures.hot,
      PlaceFeatures.private,
      PlaceFeatures.smokeFree,
    ],
    PlaceTaxonomy.play.label: [
      PlaceFeatures.private,
      PlaceFeatures.bigScreen,
      PlaceFeatures.groupSeat,
      PlaceFeatures.lateNight,
      PlaceFeatures.parking,
      PlaceFeatures.smokeFree,
    ],
    PlaceTaxonomy.experience.label: [
      PlaceFeatures.private,
      PlaceFeatures.groupSeat,
      PlaceFeatures.birthday,
      PlaceFeatures.bbq,
      PlaceFeatures.grill,
      // 🔥 구워줘요 바로 옆 — 다른 질문이라 나란히 보여야 구분된다.
      PlaceFeatures.cookedServed,
      PlaceFeatures.pet,
      PlaceFeatures.parking,
      PlaceFeatures.hot,
    ],
  };

  /// 🎉 이벤트 줄의 추천 특징 — 업종이 아니라 "오늘 갈 수 있나"를 묻는 줄이라
  /// 표를 따로 둔다(예전 그 줄에 있던 것 그대로).
  static final List<PlaceFeature> _eventAmenityHead = [
    PlaceFeatures.partychuPerk,
    PlaceFeatures.tableReservation,
    PlaceFeatures.corkageAvailable,
    PlaceFeatures.groupSeat,
    PlaceFeatures.private,
    PlaceFeatures.lateNight,
    PlaceFeatures.hot,
  ];

  /// ✨ 편의·서비스 시트에 **넣지 않는** 특징.
  ///
  /// 값을 지우는 것이 아니다 — [PlaceFeatures]의 어휘에도, 이미 저장된
  /// 문서에도 그대로 남아 있고, 유도([PlaceFeatures.of])와 판정
  /// ([PlaceFeatures.matchesAll])도 예전 그대로다. 플레이스 상세검색·지도
  /// 필터([PlaceFeatures.selectable]를 쓰는 화면들)와 등록 화면의 시설·반입
  /// 조건도 손대지 않는다. **이 시트에서 새로 고를 자리만** 없앤다.
  ///
  ///   · 무제한 — 이 시트 맨 아래 '♾ 무제한' 묶음이 세부종류째 맡는다.
  ///     특징 칸으로 또 두면 같은 조건을 켜는 자리가 둘이 된다.
  ///   · 이벤트 진행중 — 카테고리 영역의 '🎉 이벤트' 칸이 맡는 다른 축이다.
  ///   · 놀거리 · 심야영업 · 케이크 반입 · 배달음식 · BBQ — 목록이 길어
  ///     정작 자주 쓰는 조건이 밀렸다.
  static final Set<String> _amenityExcluded = {
    PlaceFeatures.unlimited.key,
    '이벤트중',
    PlaceFeatures.play.key,
    PlaceFeatures.lateNight.key,
    PlaceFeatures.cakeBringIn.key,
    PlaceFeatures.delivery.key,
    PlaceFeatures.bbq.key,
  };

  /// 업종별·이벤트별 추천 표에서 [_amenityExcluded]에 든 것을 걷어낸 목록.
  ///
  /// 표 자체는 예전 순서 그대로 두고 여기서 거른다 — 무엇을 시트에서 뺄지가
  /// 한 곳([_amenityExcluded])에만 있어야 추천과 나머지가 갈라지지 않는다.
  static List<PlaceFeature> _amenityHeadOf(String? category, bool event) {
    final head = _rawAmenityHeadOf(category, event);
    return [
      for (final f in head)
        if (!_amenityExcluded.contains(f.key)) f,
    ];
  }

  static List<PlaceFeature> _rawAmenityHeadOf(String? category, bool event) {
    if (event) return _eventAmenityHead;
    if (category == null) {
      // '전체'에서는 업종을 모르니 예전 그대로 [PlaceFeatures.quick] 순서다.
      return [
        for (final f in PlaceFeatures.quick)
          if (!_amenityExcluded.contains(f.key) && !f.retired) f,
      ];
    }
    return _amenityHead[PlaceTaxonomy.canonical(category)] ??
        const <PlaceFeature>[];
  }

  /// 🎉 With파티 칩 — 특징([PlaceFeature])이 아니라 **파티 연결 조건**이라
  /// 위 추천 표에는 들어가지 않는다. 시트에서는 추천 묶음 **맨 앞**에 붙는다
  /// (업종이 무엇이든 가장 먼저 묻는 조건이다).
  static final PlaceQuickPick _withPartyChip = PlaceQuickPick.withParty();

  /// 시트 안에 그릴 특징 칩들 — 추천이 앞, 나머지 전부가 뒤.
  ///
  /// 뒤쪽을 잘라내지 않는 이유는 무제한 시트와 같다 — 다른 업종에서 켜 둔
  /// 조건을 끌 자리가 없어지면 "안 보이는데 걸려 있는" 상태가 된다.
  static List<PlaceQuickPick> amenityKinds(
    String? category, {
    bool event = false,
  }) {
    final head = _amenityHeadOf(category, event);
    final headKeys = {for (final f in head) f.key};
    return [
      // 🎉 With파티 — 추천 묶음의 **맨 앞**. 업종이 무엇이든 물어볼 수 있는
      // 조건이라 업종별 표(_amenityHead)를 타지 않고 늘 여기 붙는다.
      _withPartyChip,
      // '구워주는 집'만은 줄에서 쓰던 짧은 이름을 그대로 쓴다 — 묶는 것이지
      // 이름을 바꾸는 것이 아니다.
      for (final f in head)
        if (f.key == PlaceFeatures.grill.key) _grillChip else _f(f),
      for (final f in PlaceFeatures.selectable)
        if (!headKeys.contains(f.key) && !_amenityExcluded.contains(f.key))
          if (f.key == PlaceFeatures.grill.key) _grillChip else _f(f),
    ];
  }

  /// 메인 줄에 나가는 **✨ 편의·서비스 칩 하나** — 누르면 시트가 열린다.
  ///
  /// ♾ 무제한도 이 시트 안에 있다([PlaceQuickPick.optionSheet]의 extra) —
  /// 예전에는 줄에 독립 칩으로 나가 있었고, 지금은 시트 맨 아래 '♾ 무제한'
  /// 묶음이다. 켜고 끄는 값도 판정도 그대로라([unlimitedKinds]) 이미 걸어 둔
  /// 무제한 조건은 이 칩에 그대로 켜져 보이고 여기서 끌 수 있다.
  static PlaceQuickPick amenityChip(String? category, {bool event = false}) =>
      PlaceQuickPick.optionSheet(
        amenityKinds(category, event: event),
        label: '✨ 편의·서비스',
        emoji: '✨',
        sheetTitle: '어떤 편의·서비스가 필요하세요?',
        // 특징은 **AND**다 — 무제한 묶음의 "그중 하나라도"와 반대라, 문구를
        // 그대로 베끼면 결과를 정반대로 기대하게 된다.
        sheetHint: '필요한 것을 골라주세요. 여러 개 고르면 그걸 모두 갖춘 곳을 찾아요.',
        otherLabel: '다른 편의·서비스',
        // +1은 추천 묶음 맨 앞에 붙는 🎉 With파티 칩([amenityKinds]).
        recommended: _amenityHeadOf(category, event).length + 1,
        extra: unlimitedKinds(category),
        extraLabel: '♾ 무제한',
      );

  // ── 🍽 푸드 업종 ───────────────────────────────────────────────────────
  //
  // 푸드 소분류는 열넷이다(한식·중식·일식·양식·고기·BBQ·해산물·글로벌 푸드·
  // 멕시칸·인도·태국·베트남·중동·지중해·기타). 이걸 드릴다운 한 줄에 그대로
  // 깔면 화면에 보이는 것은 앞 서너 칸뿐이고, 나머지는 옆으로 밀어야 나온다 —
  // 정작 고깃집을 찾는 사람이 '고기·BBQ'를 다섯 번째 칸에서 찾아야 했다.
  //
  // 그래서 **♾ 무제한과 똑같이** 줄에는 칩 하나('🍽 업종')만 두고 시트에서
  // 고른다. 켜고 끄는 값은 예전 그대로 [EventFilter.subcategories]다.
  //
  // 나라별 여섯 칸(멕시칸·인도·태국·베트남·중동·지중해)은 '글로벌푸드' 한
  // 칸으로 묶었다. **저장값은 지우지 않는다** — 이미 나라별로 등록된 문서는
  // [PlaceTaxonomy.expandGlobalFood]가 글로벌푸드 조건에 함께 걸어 준다.

  /// 시트 안 칸들 — (보이는 문구, 그것이 켜는 저장값들).
  /// 첫 값이 정본이고 뒤따르는 값은 옛 문서를 잇는 값이다.
  ///
  /// **순서를 여기서 따로 정하지 않는다** — [PlaceTaxonomy.restaurant]의
  /// 소분류 목록을 그대로 훑는다. 예전에는 앞 몇 칸을 여기 손으로 늘어놓고
  /// 나머지를 뒤에 붙였는데, 그러면 정본 목록의 순서를 고쳐도 시트만 옛 순서에
  /// 머물러 등록 화면·상세검색과 자리가 어긋난다.
  ///
  /// 정본 목록과 딱 하나 다른 점은 나라별 여섯 칸을 '글로벌푸드' 한 칸으로
  /// 접는 것뿐이다 — 접는 자리도 부모('글로벌 푸드')가 있던 그 자리다.
  static List<PlaceQuickPick> foodKinds() => [
    for (final s in PlaceTaxonomy.restaurant.subcategories)
      if (s == PlaceTaxonomy.globalFood)
        PlaceQuickPick.subcategory(const [
          PlaceTaxonomy.globalFood,
          ...PlaceTaxonomy.legacyGlobalFoodSubcategories,
        ], label: '글로벌푸드')
      // 나라별 옛 소분류는 바로 위 '글로벌푸드' 칸이 이미 아우른다.
      else if (!PlaceTaxonomy.legacyGlobalFoodSubcategories.contains(s))
        PlaceQuickPick.subcategory([s]),
  ];

  /// 메인 줄에 나가는 **🍽 업종 칩 하나** — 누르면 업종 시트가 열린다.
  static PlaceQuickPick foodKindChip() => PlaceQuickPick.optionSheet(
    foodKinds(),
    label: '${PlaceTaxonomy.restaurant.emoji} 업종',
    emoji: PlaceTaxonomy.restaurant.emoji,
    sheetTitle: '어떤 음식점을 찾으세요?',
    sheetHint: '여러 개 고르면 그중 하나라도 맞는 곳을 찾아요.',
    otherLabel: '다른 업종',
  );

  // ── 하위 탐색(드릴다운) ────────────────────────────────────────────────

  /// 클럽의 하위 탐색 — **음악 장르 하나가 정본**이다.
  ///
  /// 예전에는 소분류('힙합클럽')와 장르('HIPHOP')가 같은 말을 두 곳에 담고
  /// 있었다. 지금은 장르만 쓰고, 소분류는 읽기 전용으로 남겨
  /// [PlaceTaxonomy.legacyClubGenresOf]가 옛 값을 이 장르로 읽어 준다.
  ///
  /// '힙합·R&B'는 칩 하나가 두 저장값을 켠다 — 그룹 안이 OR이므로 "힙합이거나
  /// R&B"가 되고, 저장값 자체는 갈라진 채로 남는다.
  static List<PlaceQuickPick> clubGenres() => [
    PlaceQuickPick.attribute(_genres, ['HIPHOP', 'R&B'], label: '힙합·R&B'),
    PlaceQuickPick.attribute(_genres, ['EDM'], label: 'EDM'),
    PlaceQuickPick.attribute(_genres, ['House'], label: '하우스'),
    PlaceQuickPick.attribute(_genres, ['Techno'], label: '테크노'),
    PlaceQuickPick.attribute(_genres, ['K-POP'], label: 'K-POP'),
    PlaceQuickPick.attribute(_genres, ['Latin'], label: '라틴'),
    // 'All Mix'가 "여러 장르를 다 튼다"는 뜻의 기존 저장값이다 — '기타'라는
    // 새 값을 만들면 같은 자리에 값이 둘이 된다.
    PlaceQuickPick.attribute(_genres, ['All Mix'], label: '올믹스'),
  ];

  /// 대분류를 눌렀을 때 **같은 자리**에 펼쳐지는 하위 탐색 칩들.
  ///
  /// [category]가 null이고 [event]가 true면 🎉 이벤트의 갈래를 돌려준다.
  static List<PlaceQuickPick> drillFor({String? category, bool event = false}) {
    if (event) {
      return [
        for (final k in PlaceEventTaxonomy.all) PlaceQuickPick.eventKind(k.key),
      ];
    }
    if (category == null) return const [];
    final c = PlaceTaxonomy.byLabel(category);
    if (c == null) return const [];
    if (c.label == PlaceTaxonomy.club.label) return clubGenres();
    // 푸드는 소분류를 여기 깔지 않는다 — 열넷을 한 줄에 늘어놓으면 앞 서너
    // 칸만 보이고 '고기·BBQ'조차 밀려난다. 대신 빠른필터 줄의 '🍽 업종' 칩이
    // 시트에서 받는다([foodKindChip]). 켜는 값은 그대로 소분류다.
    if (c.label == PlaceTaxonomy.restaurant.label) return const [];
    return [
      for (final s in c.subcategories) PlaceQuickPick.subcategory([s]),
    ];
  }

  // ── 빠른 필터 한 줄 ────────────────────────────────────────────────────

  /// 대분류를 안 골랐을 때(= '전체') 보여주는 줄.
  ///
  /// 특징은 전부 '✨ 편의·서비스' 시트가 받는다 — 순서는 예전 그대로
  /// [PlaceFeatures.quick]이고, 시트 안 추천 영역에 그 순서로 들어간다.
  static List<PlaceQuickPick> get _general => [amenityChip(null)];

  /// 🎉 이벤트를 보고 있을 때의 줄.
  ///
  /// 갈래(한정·생일·상시 …)는 **바로 위 드릴다운에 이미 있다** — 여기서 또
  /// 반복하면 같은 말이 두 줄이 된다. 그래서 "그래서 오늘 갈 수 있나"를 묻는
  /// 조건만 남긴다. '지금 영업중'은 편의·서비스가 아니라 **지금 상태**라
  /// 시트에 넣지 않고 줄에 그대로 둔다.
  static List<PlaceQuickPick> get _event => [
    PlaceQuickPick.openNow(),
    amenityChip(null, event: true),
  ];

  /// 대분류(저장값) → 그 업종에서 먼저 묻는 조건들.
  ///
  /// 키는 **저장값**이다('맛집'). 화면 이름('푸드')이 들어와도
  /// [PlaceTaxonomy.canonical]이 되돌리므로 표기를 바꿔도 이 표는 안 바뀐다.
  ///
  /// ── 줄에는 '무엇을'만 남긴다 ─────────────────────────────────────────
  /// 좁은 화면에서 스크롤 없이 보이는 것은 서너 칸이다. 예전에는 그 뒤로
  /// 특징 칩이 열 칸씩 이어져 있어서, 주차·금연·핫플을 보려면 한참 밀어야
  /// 했다. 지금은 특징을 전부 '✨ 편의·서비스' 시트가 받으므로
  /// ([amenityChip]) 줄에는 **그 업종에서 무엇을 고르는지**만 남는다 —
  /// 업종·주종·장르·놀거리처럼 시트로 묶을 수 없는 축들이다.
  ///
  /// 어느 특징을 그 업종에서 먼저 묻는지는 사라지지 않았다 — 예전 줄 순서가
  /// 그대로 시트의 추천 영역이 된다([_amenityHead]).
  static final Map<String, List<PlaceQuickPick>> _byCategory = {
    // 푸드 — 업종 / 편의·서비스(무제한 묶음 포함).
    //
    // '🍽 업종'이 맨 앞이다 — 푸드에서 가장 먼저 좁히는 것은 "무엇을 먹느냐"고,
    // 예전에는 그것이 위 드릴다운 줄에 있었다. 줄을 없앤 대신 그 자리를 여기
    // 첫 칸이 받는다([foodKindChip]).
    PlaceTaxonomy.restaurant.label: [
      foodKindChip(),
      amenityChip(PlaceTaxonomy.restaurant.label),
    ],
    // 다이닝 — 음식 종류는 바로 위 드릴다운이 맡는다([drillFor]가 소분류를
    // 그대로 깐다: 한식·중식·일식…). 여기서 또 하면 같은 줄이 둘이 된다.
    PlaceTaxonomy.dining.label: [amenityChip(PlaceTaxonomy.dining.label)],
    PlaceTaxonomy.cafe.label: [amenityChip(PlaceTaxonomy.cafe.label)],
    PlaceTaxonomy.pub.label: [amenityChip(PlaceTaxonomy.pub.label)],
    // 혼술바 — 와인 / 위스키 / 하이볼 / 전통주.
    // "무엇을 마시나"가 먼저고, "혼자 앉을 자리가 있나"(바좌석)는 편의·서비스
    // 시트의 추천 맨 앞에 있다.
    PlaceTaxonomy.soloBar.label: [
      PlaceQuickPick.attribute(_alcohol, ['와인']),
      PlaceQuickPick.attribute(_alcohol, ['위스키']),
      PlaceQuickPick.attribute(_alcohol, ['하이볼']),
      PlaceQuickPick.attribute(_alcohol, ['전통주']),
      PlaceQuickPick.attribute(_alcohol, ['칵테일']),
      amenityChip(PlaceTaxonomy.soloBar.label),
    ],
    PlaceTaxonomy.bar.label: [
      PlaceQuickPick.attribute(_alcohol, ['와인']),
      PlaceQuickPick.attribute(_alcohol, ['위스키']),
      PlaceQuickPick.attribute(_alcohol, ['하이볼']),
      PlaceQuickPick.attribute(_alcohol, ['칵테일']),
      amenityChip(PlaceTaxonomy.bar.label),
    ],
    // 클럽 — DJ / 테이블 / 심야 / 입장료 / 흡연공간 / 신분증.
    // 장르는 바로 위 드릴다운이 맡으므로 여기서는 **입장·시간 조건**만.
    //
    // '입장료'는 무료입장 쪽을 칩으로 낸다 — 게스트가 누르고 싶은 것은 "돈을
    // 받는 곳"이 아니라 "그냥 들어갈 수 있는 곳"이다. 금액 자체는 상세페이지의
    // 입장 정보(entryFee)가 계속 정본이다.
    PlaceTaxonomy.club.label: [
      PlaceQuickPick.attribute(_clubEntry, [
        PlaceAttributeCatalog.clubEntryFree,
      ], label: '🆓 무료입장'),
      PlaceQuickPick.attribute(_clubEntry, ['신분증 필수'], label: '🪪 신분증'),
      PlaceQuickPick.attribute(_clubEntry, ['드레스코드 있음'], label: '👗 드레스코드'),
      amenityChip(PlaceTaxonomy.club.label),
    ],
    PlaceTaxonomy.live.label: [
      PlaceQuickPick.attribute(_genres, ['K-POP']),
      PlaceQuickPick.attribute(_genres, ['HIPHOP', 'R&B'], label: '🎧 힙합·R&B'),
      amenityChip(PlaceTaxonomy.live.label),
    ],
    // 놀거리 — 노래방 / 보드게임 / 다트 / 콘솔 / 시간무제한 / 프라이빗.
    //
    // 놀거리 대분류는 '놀거리' 특징이 저절로 켜지므로(PlaceFeatures.of ⑤)
    // 그 칸을 두면 아무도 안 걸러진다 — 대신 무엇을 하는 곳인지를 묻는다.
    // '시간무제한'은 편의·서비스 시트의 '♾ 무제한' 묶음이 맡는다 — 노래방
    // 시간·놀거리 이용·이용시간이 그 묶음 맨 앞에 선다([_unlimitedHead]).
    PlaceTaxonomy.play.label: [
      PlaceQuickPick.attribute(_playItems, ['노래방']),
      PlaceQuickPick.attribute(_playItems, ['보드게임']),
      PlaceQuickPick.attribute(_playItems, ['다트']),
      PlaceQuickPick.attribute(_playItems, ['콘솔게임']),
      PlaceQuickPick.attribute(_playItems, ['당구']),
      amenityChip(PlaceTaxonomy.play.label),
    ],
    PlaceTaxonomy.experience.label: [
      amenityChip(PlaceTaxonomy.experience.label),
    ],
  };

  /// 지금 보고 있는 것에 맞는 빠른 조건들.
  static List<PlaceQuickPick> forCategory(
    String? category, {
    bool event = false,
  }) {
    if (event) return _event;
    if (category == null) return _general;
    return _byCategory[PlaceTaxonomy.canonical(category)] ?? _general;
  }

  /// 줄에 나와 있는 특징 키들 — 상세필터 배지가 "여기 안 보이는 조건"만
  /// 세도록 [EventFilter.hiddenConditionCount]에 넘긴다.
  /// 시트 칩('✨ 편의·서비스')이 든 특징도 **보이는 것으로 친다** — 칩 자신이
  /// 고른 것을 이름에 적고 있으므로('🔥 구워줘요', '✨ 편의·서비스 3'), 배지가
  /// 그것을 한 번 더 세면 같은 말을 두 번 하는 것이 된다(무제한과 같은 규칙).
  static Set<String> visibleFeatures(String? category, {bool event = false}) =>
      {
        for (final p in forCategory(category, event: event))
          if (p.axis == PlacePickAxis.feature)
            p.values.first
          else if (p.opensSheet)
            for (final o in p.options)
              if (o.axis == PlacePickAxis.feature) o.values.first,
      };

  /// 줄에 나와 있는 속성 값들 — 그룹키 → 값들. 드릴다운 줄에 나온 장르도
  /// 함께 넣는다(그쪽도 이미 화면에 보이는 조건이다).
  ///
  /// 시트 칩(♾ 무제한)이 든 값도 **보이는 것으로 친다** — 칩 자신이 고른
  /// 세부종류를 이름에 적고 있으므로('♾ 하이볼·주류 무제한'), 상세필터 배지가
  /// 그것을 한 번 더 세면 같은 말을 두 번 하는 것이 된다.
  static Map<String, Set<String>> visibleAttributes(
    String? category, {
    bool event = false,
  }) {
    final map = <String, Set<String>>{};
    void put(String? group, Iterable<String> values) {
      if (group == null) return;
      map.putIfAbsent(group, () => <String>{}).addAll(values);
    }

    void add(Iterable<PlaceQuickPick> picks) {
      for (final p in picks) {
        if (p.opensSheet) {
          // 시트 칩 자신의 그룹(♾ 무제한 시트)과, 시트 안 칩이 저마다 아는
          // 그룹을 함께 본다 — ✨ 편의·서비스처럼 그룹이 없는 시트가 무제한
          // 묶음을 품고 있어도 그 값들이 "안 보이는 조건"으로 세어지지 않게.
          put(p.groupKey, p.allValues);
          for (final o in p.options) {
            put(o.groupKey, o.allValues);
          }
          continue;
        }
        if (p.axis != PlacePickAxis.attribute) continue;
        put(p.groupKey, p.allValues);
      }
    }

    add(forCategory(category, event: event));
    add(drillFor(category: category, event: event));
    return map;
  }
}
