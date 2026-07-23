import 'package:flutter/material.dart';
import 'package:party_app/utils/age_range_utils.dart';

/// 나이 휠 선택 바텀시트 — 출생연도 대신 사용자가 이해하기 쉬운 "몇 세"
/// 단위로 고른다(내부 저장/비교용 출생연도 변환은 `age_range_utils.dart`).
/// 휠에 나타나는 범위는 [audienceType]별로 다르다(`partyAgeRangeFor` 참고)
/// — 그 범위 밖의 나이는 애초에 휠에 나타나지 않아 선택할 수 없다.
Future<int?> showAgePickerSheet(
  BuildContext context, {
  required int currentAge,
  PartyAudienceType audienceType = PartyAudienceType.adult,
}) async {
  final range = partyAgeRangeFor(audienceType);
  final ages = List.generate(range.maxAge - range.minAge + 1, (i) => range.minAge + i);
  int selectedAge = currentAge.clamp(range.minAge, range.maxAge);
  final controller = FixedExtentScrollController(
    initialItem: ages.indexOf(selectedAge),
  );

  final result = await showModalBottomSheet<int>(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => SizedBox(
      height: 300,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 16),
          const Text('나이 선택',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: ListWheelScrollView.useDelegate(
              controller: controller,
              itemExtent: 48,
              perspective: 0.003,
              diameterRatio: 2.0,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: (i) => selectedAge = ages[i],
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: ages.length,
                builder: (_, i) => Center(
                  child: Text(
                    '${ages[i]}세',
                    style: TextStyle(
                      fontSize: ages[i] == selectedAge ? 20 : 16,
                      fontWeight: ages[i] == selectedAge
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: ages[i] == selectedAge
                          ? Colors.indigo
                          : Colors.black45,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, 16 + MediaQuery.of(context).padding.bottom),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context, selectedAge),
                child: const Text('확인', style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}
