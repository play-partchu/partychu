import 'package:flutter/material.dart';

import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/reservation_modes.dart';
import 'package:party_app/widgets/filter_sheet_ui.dart';
import 'package:party_app/widgets/main/quick_filter_icon_button.dart';

/// 장소대여 목록 위 **"대여유형" 시트**가 한 번에 묻는 두 가지.
///
/// 두 축은 뜻이 다르다 — 하나는 **어떻게 빌리는가**(시간제/숙박), 하나는
/// **어떤 곳인가**(파티룸·펜션·호텔…). 그래서 하나의 목록으로 합치지 않고
/// 시트 안에서도 두 문단으로 나눠 묻는다.
///
/// 이 객체는 시트가 주고받는 **한 번의 선택**일 뿐이고, 저장되는 곳은
/// `PlaceFilter`의 원래 두 칸(`reservationMode` / `placeTypes`)이다 — 상세검색이
/// 쓰는 바로 그 칸이라, 여기서 고른 것이 상세검색에도 그대로 보인다.
@immutable
class PlaceRentalTypeSelection {
  const PlaceRentalTypeSelection({this.mode, this.placeTypes = const {}});

  /// 예약 방식 — null이면 '전체'(거르지 않는다). **하나만** 고른다.
  ///
  /// '전체'는 화면에서만 쓰는 말이다. 저장되는 값도, 판정에 넘기는 값도 null일
  /// 뿐 '전체'라는 값이 따로 있는 게 아니다.
  final ReservationMode? mode;

  /// 장소 유형 — **여러 개** 고를 수 있고 서로 OR다(판정은
  /// `PlaceFilter.matchesPlaceTypes`). 값의 정본은 등록 화면이 쓰는
  /// [ListingConstants.placeTypes] 그대로다.
  final Set<String> placeTypes;

  bool get isEmpty => mode == null && placeTypes.isEmpty;
}

/// "대여유형" 빠른 선택 시트 — 어떻게 빌리는지(전체/⏱ 시간제/🛏 숙박)와
/// 어떤 곳인지(파티룸·펜션·…)를 한 자리에서 고른다.
///
/// ## 상세검색과 같은 조건, 같은 칩
///
/// 고른 값은 상세검색과 **같은 두 칸**(`PlaceFilter.reservationMode` /
/// `PlaceFilter.placeTypes`)으로 들어간다. 그래서 여기서 파티룸+루프탑을 고르면
/// 상세검색의 '장소 유형'에도 둘 다 켜져 있고, 반대도 마찬가지다. 칩도 상세검색
/// 시트가 쓰는 [FilterOptionChip] 그대로라 두 곳의 선택 표시가 갈릴 수 없다.
///
/// ## 시간제와 숙박은 배타적이지 않다
///
/// 여기서 고르는 것은 "장소를 둘 중 하나로 분류하는 값"이 아니라 **"내가 원하는
/// 이용 방식을 받는 곳만 보기"**다. 4시간 대여도 되고 1박도 되는 파티룸은 어느
/// 쪽을 골라도 목록에 남는다 — 판정은 룸 문서를 정본으로 하는
/// [placeReservationModes]가 하고, 그 결과 집합에 고른 방식이 들어 있는지만
/// 본다([reservationModeOverlapHint]).
///
/// ## 닫기와 적용
///
/// 장소 유형이 **여러 개** 골라지므로 칩 하나를 누를 때마다 닫을 수 없다.
/// 시트 안에서는 임시 사본을 고치고 '적용'을 눌렀을 때만 정본에 반영한다
/// (지역 선택 시트와 같은 규약). 바깥을 누르거나 뒤로가기로 닫으면 [selected]가
/// 그대로 돌아온다 — 즉 **아무것도 바뀌지 않는다**.
Future<PlaceRentalTypeSelection> showPlaceRentalTypeSheet(
  BuildContext context, {
  required PlaceRentalTypeSelection selected,
}) {
  return showModalBottomSheet<PlaceRentalTypeSelection>(
    context: context,
    backgroundColor: Colors.white,
    // 작은 화면·큰 글씨 설정에서도 잘리지 않게.
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PlaceRentalTypeSheet(selected: selected),
  ).then((r) => r ?? selected);
}

class _PlaceRentalTypeSheet extends StatefulWidget {
  const _PlaceRentalTypeSheet({required this.selected});

  final PlaceRentalTypeSelection selected;

  @override
  State<_PlaceRentalTypeSheet> createState() => _PlaceRentalTypeSheetState();
}

class _PlaceRentalTypeSheetState extends State<_PlaceRentalTypeSheet> {
  /// 고를 수 있는 예약 방식은 셋뿐이다 — 패키지는 시간제/숙박과 같은 층의
  /// 구분이 아니라 그 위에 얹히는 상품 형태라 게스트가 고르는 축이 아니다
  /// (상세검색의 '예약 방식'도 같은 이유로 둘만 보여준다).
  static const _modes = <ReservationMode?>[
    null,
    ReservationMode.hourly,
    ReservationMode.stay,
  ];

  late ReservationMode? _mode = widget.selected.mode;
  late final Set<String> _types = {...widget.selected.placeTypes};

  static String _modeLabel(ReservationMode? mode) => mode?.chipLabel ?? '전체';

  static String _hint(ReservationMode? mode) => switch (mode) {
    null => '대여 유형을 가리지 않고 모두 보여드려요.',
    ReservationMode.hourly => '시간 단위로 빌릴 수 있는 곳을 모두 보여드려요.',
    ReservationMode.stay => '숙박할 수 있는 곳을 모두 보여드려요.',
    ReservationMode.package => '',
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '어떻게 빌리시나요?',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _hint(_mode),
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final mode in _modes)
                        FilterOptionChip(
                          label: _modeLabel(mode),
                          selected: _mode == mode,
                          // 하나만 고른다 — 누르면 그 값이 되고, 이미 고른 것을
                          // 다시 눌러도 '전체'로 풀리지 않는다('전체' 칩이 그
                          // 자리를 이미 갖고 있다).
                          onTap: () => setState(() => _mode = mode),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const FilterHintText(reservationModeOverlapHint),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Text(
                        '장소 유형',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_types.isNotEmpty)
                        Text(
                          '${_types.length}개 선택',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFF6FA0),
                          ),
                        ),
                      const Spacer(),
                      if (_types.isNotEmpty)
                        GestureDetector(
                          onTap: () => setState(_types.clear),
                          child: const Text(
                            '초기화',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFF6FA0),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    // 대여 방식과 달리 여러 개를 고를 수 있다는 것을 먼저 말해
                    // 준다 — 칩 모양만으로는 단일/복수가 구별되지 않는다.
                    '여러 개 고를 수 있어요. 고른 유형 중 하나라도 해당하면 보여드려요.',
                    style: TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      // 목록의 정본은 **등록 화면이 쓰는 그 상수**다 — 문구를
                      // 여기 다시 적으면 호스트가 고른 값과 게스트가 고르는 값이
                      // 갈려 영영 걸리지 않는 유형이 생긴다.
                      for (final type in ListingConstants.placeTypes)
                        FilterOptionChip(
                          label: type,
                          selected: _types.contains(type),
                          onTap: () => setState(() {
                            if (!_types.remove(type)) _types.add(type);
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 적용 — 지금 무엇이 걸리는지 버튼이 그대로 말해준다(지역 선택
          // 시트와 같은 재질·같은 규약).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(
                  context,
                  PlaceRentalTypeSelection(
                    mode: _mode,
                    placeTypes: {..._types},
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6FA0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  elevation: 0,
                ),
                child: Text(
                  _mode == null && _types.isEmpty
                      ? '전체 보기'
                      : '${placeRentalTypeSummary(PlaceRentalTypeSelection(mode: _mode, placeTypes: _types))} 적용',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 목록 위 '대여유형' 버튼에 적는 요약
// ─────────────────────────────────────────────────────────────────────────────

/// 이 버튼의 이름 — 아무것도 고르지 않았을 때 적는 말.
const String kPlaceRentalTypeLabel = '대여유형';

/// 고른 값을 한 줄로 — '숙박', '파티룸 외 2개', '숙박 · 파티룸 외 2개'.
///
/// 여러 값을 '첫값 외 N개'로 줄이는 것은 이 앱의 **기존 요약 규칙** 그대로다
/// (지역 '외 N곳', 편의시설 '외 N개'). 두 축은 가운뎃점으로 잇는다 — 왼쪽이
/// 어떻게 빌리는지, 오른쪽이 어떤 곳인지.
String placeRentalTypeSummary(PlaceRentalTypeSelection selection) =>
    _summaryParts(selection).join(' · ');

/// 좁은 자리를 위해 '외 N개'를 뗀 형태 — '숙박 · 파티룸'.
String _summaryWithoutExtra(PlaceRentalTypeSelection selection) => [
  if (selection.mode != null) selection.mode!.label,
  ..._orderedTypes(selection.placeTypes).take(1),
].join(' · ');

List<String> _summaryParts(PlaceRentalTypeSelection selection) {
  final types = _orderedTypes(selection.placeTypes);
  return [
    if (selection.mode != null) selection.mode!.label,
    if (types.isNotEmpty)
      types.length == 1 ? types.first : '${types.first} 외 ${types.length - 1}개',
  ];
}

/// 고른 유형을 **선택 순서가 아니라 목록 순서**로 — 같은 조합이면 언제나 같은
/// 글자가 나온다(파티룸을 먼저 눌렀든 나중에 눌렀든 '파티룸 외 2개').
/// 목록에 없는 옛 값도 뒤에 그대로 남긴다.
List<String> _orderedTypes(Set<String> types) => [
  ...ListingConstants.placeTypes.where(types.contains),
  ...types.where((t) => !ListingConstants.placeTypes.contains(t)),
];

/// 목록 위 대여유형 버튼에 실제로 그릴 글자 — [maxWidth]에 들어가는 **가장
/// 넉넉한** 후보. 하나도 안 들어가면 null(= 아이콘만 그린다).
///
/// 지역 버튼([RegionFilterFit])과 같은 방식이다: 글자를 말줄임으로 자르지 않고
/// **곁가지부터 뗀다** — '숙박 · 파티룸 외 2개' → '숙박 · 파티룸' → '숙박' →
/// (이름) '대여유형' → 아이콘만. 어느 단계에서도 잘린 글자는 나오지 않고,
/// 아이콘만 남는 단계에서도 버튼이 핑크로 채워져 조건이 걸려 있다는 것은 보인다.
///
/// 폭은 실제로 그릴 때 쓰는 스타일 그대로 잰다
/// ([QuickFilterIconButton.widthForLabel]) — 기기 글꼴이 달라도 어긋나지 않는다.
String? placeRentalTypeButtonLabel({
  required PlaceRentalTypeSelection selection,
  required double maxWidth,
}) {
  for (final candidate in placeRentalTypeLabelCandidates(selection)) {
    if (QuickFilterIconButton.widthForLabel(candidate) <= maxWidth) {
      return candidate;
    }
  }
  return null;
}

/// 넓은 것부터 좁은 것 순의 후보 — 떼는 순서가 그대로 드러난다.
List<String> placeRentalTypeLabelCandidates(
  PlaceRentalTypeSelection selection,
) {
  if (selection.isEmpty) return const [kPlaceRentalTypeLabel];
  final parts = _summaryParts(selection);
  return <String>[
    parts.join(' · '),
    _summaryWithoutExtra(selection),
    parts.first,
    kPlaceRentalTypeLabel,
  ].fold(<String>[], (out, s) {
    // 같은 글자가 두 번 후보로 오르는 경우(값이 하나뿐일 때)를 접는다.
    if (s.isNotEmpty && !out.contains(s)) out.add(s);
    return out;
  });
}
