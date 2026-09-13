import 'package:flutter/material.dart';

import 'package:party_app/utils/party_scale_filter.dart';
import 'package:party_app/widgets/filter_sheet_ui.dart';

/// 파티 목록 위 **인원(파티 규모) 빠른 선택 시트** — 전체 / 2~5명 / … /
/// 100명 이상.
///
/// ## 신청 인원이 아니라 파티 총 정원이다
///
/// 여기서 고르는 수는 "내가 몇 명이서 갈까"가 아니라 **"몇 명을 모으는
/// 파티인가"**다. 판정은 [PartyScaleFilter]가 하고, 그 값의 정본은 카드에
/// 찍히는 최대 모집 인원 하나다(성비 맞춤 파티는 남·여 정원의 합) — 새 필드도,
/// 새 구간도 만들지 않는다. 상세검색의 '파티 규모'와 **같은 한 칸**
/// ([PartyFilter.partyScale])을 고친다.
///
/// 고른 값(또는 '전체'를 뜻하는 null)을 돌려주고, 그냥 닫으면 [selected]가
/// 그대로 돌아온다 — 플레이스 인원 시트([showCapacityPickerSheet])와 같은
/// 규약이다.
Future<String?> showPartyScalePickerSheet(
  BuildContext context, {
  required String? selected,
}) {
  return showModalBottomSheet<_ScaleResult>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SingleChildScrollView(
      child: _PartyScalePickerSheet(selected: selected),
    ),
  ).then((r) => r == null ? selected : r.id);
}

/// null('전체')과 "그냥 닫음"을 구별하기 위한 포장.
class _ScaleResult {
  final String? id;
  const _ScaleResult(this.id);
}

class _PartyScalePickerSheet extends StatelessWidget {
  final String? selected;

  const _PartyScalePickerSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
              '몇 명이 모이는 파티를 찾으세요?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              '파티가 모으는 총 인원(정원) 기준이에요.',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
            const SizedBox(height: 14),
            // 고르는 즉시 닫힌다(적용 버튼 없음).
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilterOptionChip(
                  label: '전체',
                  selected: selected == null,
                  onTap: () => Navigator.pop(context, const _ScaleResult(null)),
                ),
                for (final range in PartyScaleFilter.options)
                  FilterOptionChip(
                    label: range.label,
                    selected: selected == range.id,
                    onTap: () => Navigator.pop(context, _ScaleResult(range.id)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const FilterHintText(
              '남은 자리가 아니라 모집 인원으로 골라요 — 이미 마감된 파티도 '
              '규모가 맞으면 함께 보여드려요.',
            ),
          ],
        ),
      ),
    );
  }
}
