import 'package:flutter/material.dart';

import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/listing_price_match.dart';
import 'package:party_app/models/map_listing.dart';
import 'package:party_app/models/map_quick_filter_row.dart';
import 'package:party_app/widgets/filter_sheet_ui.dart';

/// ₩ 가격 빠른 필터 시트 — 지도 홈의 ₩ 버튼이 연다.
///
/// **새 가격 체계를 만들지 않는다.** 종류마다 목록 탭이 쓰던 칸과 판정을 그대로
/// 쓴다([listing_price_match.dart]):
///   · 🎉 파티      참가비 [partyFeeRanges] → [PartyFilter.feeRanges]
///   · 🏬 플레이스  [ListingConstants.eventPriceRanges] → [EventFilter.priceRanges]
///   · 🏠 장소대여  [ListingConstants.placePriceRanges] → [PlaceFilter.priceRanges]
/// 칩도 상세검색 시트와 같은 위젯([FilterChipWrap])이다.
///
/// 지금 지도에 올라온 종류의 칸만 보여준다 — '파티'만 켜 두고 장소대여 가격을
/// 고르게 하면 지도에 아무 일도 일어나지 않기 때문이다.
///
/// 🎊 공공 축제 칸은 없다. 원본에 금액 숫자가 없어(요금이 '무료(일부 유료)'
/// 같은 문장뿐) 가격 조건을 걸 수 없고, 조건을 켜도 축제는 그대로 남는다.
class MapPriceFilterSheet extends StatefulWidget {
  const MapPriceFilterSheet({
    super.key,
    required this.initial,
    required this.kinds,
  });

  final MapPriceSelection initial;

  /// 지금 지도에 올라온 종류들([MapListingKind]).
  final Set<MapListingKind> kinds;

  @override
  State<MapPriceFilterSheet> createState() => _MapPriceFilterSheetState();
}

class _MapPriceFilterSheetState extends State<MapPriceFilterSheet> {
  late Set<String> _party = {...widget.initial.partyFees};
  late Set<String> _place = {...widget.initial.placeRanges};
  late Set<String> _rental = {...widget.initial.rentalRanges};

  MapPriceSelection get _selection => MapPriceSelection(
    partyFees: _party,
    placeRanges: _place,
    rentalRanges: _rental,
  );

  @override
  Widget build(BuildContext context) {
    final showParty = widget.kinds.contains(MapListingKind.party);
    final showPlace = widget.kinds.contains(MapListingKind.place);
    final showRental = widget.kinds.contains(MapListingKind.rental);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '가격',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              '종류마다 가격의 뜻이 달라 칸이 따로 있어요.',
              style: TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showParty)
                      _group(
                        key: const ValueKey('mapPriceParty'),
                        title: '🎉 파티 참가비',
                        options: partyFeeRanges,
                        selected: _party,
                      ),
                    if (showPlace)
                      _group(
                        key: const ValueKey('mapPricePlace'),
                        title: '🏬 플레이스 가격대',
                        options: ListingConstants.eventPriceRanges,
                        selected: _place,
                      ),
                    if (showRental)
                      _group(
                        key: const ValueKey('mapPriceRental'),
                        title: '🏠 장소대여 시간당 요금',
                        note: '가격 문의 공간은 금액을 몰라 가격 조건을 걸면 빠져요.',
                        options: ListingConstants.placePriceRanges,
                        selected: _rental,
                      ),
                    if (!showParty && !showPlace && !showRental)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          '지금 지도에 올라온 종류에는 가격 조건이 없어요.',
                          style: TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                TextButton(
                  key: const ValueKey('mapPriceReset'),
                  onPressed: _selection.isEmpty
                      ? null
                      : () => setState(() {
                          _party = {};
                          _place = {};
                          _rental = {};
                        }),
                  child: const Text('초기화'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('mapPriceApply'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6FA0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, _selection),
                    child: const Text('적용'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _group({
    required Key key,
    required String title,
    required List<String> options,
    required Set<String> selected,
    String? note,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(
            note,
            style: const TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ],
        const SizedBox(height: 10),
        FilterChipWrap(
          options: options,
          selected: selected,
          onChanged: () => setState(() {}),
        ),
      ],
    ),
  );
}

/// ₩ 시트를 연다. 적용을 누르면 고른 값, 그냥 닫으면 null.
Future<MapPriceSelection?> showMapPriceFilterSheet(
  BuildContext context, {
  required MapPriceSelection initial,
  required Set<MapListingKind> kinds,
}) => showModalBottomSheet<MapPriceSelection>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (_) => MapPriceFilterSheet(initial: initial, kinds: kinds),
);
