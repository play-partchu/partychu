import 'package:flutter/material.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_quick_picks.dart';
import 'package:party_app/widgets/filter_option_sheet.dart';

/// 빠른필터 줄의 **세부종류 시트**.
///
/// ── 왜 시트인가 ───────────────────────────────────────────────────────────
/// '무제한'은 업종마다 뜻이 다르다 — 뷔페·고기·맥주·하이볼·음료·노래방 시간·
/// 놀거리 이용·이용시간. 이걸 칩 하나(true/false)로 두면 "무엇이 무제한인지"를
/// 검색할 수 없고, 값마다 칩을 두면 빠른필터 줄이 아홉 칸 길어져 정작 봐야 할
/// 플레이스 카드가 화면 밖으로 밀린다.
///
/// 그래서 **줄에는 칩 하나만** 두고, 누르면 이 시트가 열려 세부종류를 고른다.
/// 메인에 선택칩을 따로 쌓지 않는 원칙([PlaceQuickFeatureBar])은 그대로다 —
/// 무엇을 골랐는지는 칩 자신이 이름으로 말한다('♾ 하이볼·주류 무제한').
///
/// ── 무제한만의 시트가 아니다 ──────────────────────────────────────────────
/// 푸드의 '🍽 업종'도 같은 사정이라 같은 시트를 쓴다 — 소분류 열넷을 한 줄에
/// 늘어놓으면 앞 서너 칸만 보인다. 시트는 "칩 여럿을 담는 그릇"일 뿐이라
/// 안에 든 칩의 축은 보지 않는다(무제한은 속성, 업종은 소분류). 제목·안내
/// 문구·소제목은 칩이 들고 온다([PlaceQuickPick.sheetTitle] 등).
///
/// ── 그릇은 파티 상세검색과 함께 쓴다 ──────────────────────────────────────
/// 시트의 모양(손잡이·제목·초기화·칩·적용 버튼)은 [showFilterOptionSheet]에
/// 있다. 파티 상세검색의 '파티 유형'·'분위기'도 같은 그릇을 쓰는데, **UI만**
/// 공용이다 — 무엇을 켜고 끄는지는 아래에서 [PlaceQuickPick]이 [EventFilter]를
/// 직접 고치고, 파티 쪽은 자기 [PartyFilter]를 고친다. 판정은 양쪽 다 예전
/// 그대로다([EventFilter.matchesDiscovery]).
///
/// ── 값은 새로 만들지 않는다 ───────────────────────────────────────────────
/// 시트 안 칸은 전부 평범한 칩([PlaceQuickPick.attribute] ·
/// [PlaceQuickPick.subcategory])이라, 켜고 끄는 값도 판정도 상세검색 시트와
/// 완전히 같다.
Future<void> showPlaceQuickPickSheet({
  required BuildContext context,
  required PlaceQuickPick pick,
  required EventFilter filter,
  required VoidCallback onChanged,
  bool night = true,
}) {
  FilterSheetOption chip(PlaceQuickPick option) => FilterSheetOption(
    label: option.display,
    selected: option.isOn(filter),
    onToggle: () => option.toggle(filter),
  );

  return showFilterOptionSheet(
    context: context,
    night: night,
    title: pick.sheetTitle,
    hint: () => pick.sheetHint,
    hasSelection: () => pick.options.any((o) => o.isOn(filter)),
    onReset: () => pick.clear(filter),
    onChanged: onChanged,
    // 보고 있는 업종에서 실제로 있을 법한 갈래가 위, 나머지가 아래다.
    // 아래 영역도 똑같이 고르고 끌 수 있다 — 다른 업종에서 켜 둔 조건을
    // 여기서 끌 수 없으면 "안 보이는데 걸려 있는" 상태가 된다.
    groups: () {
      final recommended = pick.recommendedOptions;
      final others = pick.otherOptions;
      // 맨 아래 별도 묶음 — ✨ 편의·서비스 시트가 든 '♾ 무제한'이 그것이다.
      // 특징(AND)과 뜻이 달라(그중 하나라도) 같은 묶음에 섞지 않는다.
      final extra = pick.extraOptions;
      final extraGroup = extra.isEmpty
          ? null
          : FilterSheetGroup(
              label: pick.sheetExtraLabel,
              options: extra.map(chip).toList(),
            );
      if (recommended.isEmpty) {
        return [
          FilterSheetGroup(
            options: [...recommended, ...others].map(chip).toList(),
          ),
          ?extraGroup,
        ];
      }
      return [
        FilterSheetGroup(label: '추천', options: recommended.map(chip).toList()),
        if (others.isNotEmpty)
          FilterSheetGroup(
            label: pick.sheetOtherLabel,
            options: others.map(chip).toList(),
          ),
        ?extraGroup,
      ];
    },
  );
}
