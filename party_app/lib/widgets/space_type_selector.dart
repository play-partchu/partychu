import 'package:flutter/material.dart';

import 'package:party_app/models/combo_place_type.dart';
import 'package:party_app/widgets/combo_form/combo_form_styles.dart';

/// 공간 등록 화면 최상단의 "어떤 공간인가요?" 선택 카드.
///
/// **플레이스+파티 등록(콤보)과 플레이스 등록(단독)이 이 위젯 하나를 함께
/// 쓴다** — 선택지·배지·예시 문구가 모두 [ComboPlaceType]에서 나오므로, 두
/// 화면의 유형 선택 UI가 구조적으로 어긋날 수 없다. 새 선택지를 넣는 곳도
/// 그 enum 한 곳뿐이다.
///
/// 여기서 고른 유형에 따라 아래에 보이는 입력 섹션과 최종 저장 스키마가
/// 갈린다([ComboPlaceType] 참고).
class SpaceTypeSelector extends StatelessWidget {
  final ComboPlaceType value;

  /// 다른 유형을 눌렀을 때 — 전용 입력값 경고/초기화는 호출한 쪽이 처리한다.
  final ValueChanged<ComboPlaceType> onChanged;

  const SpaceTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return comboSectionCard(
      title: '어떤 공간인가요?',
      subtitle: '선택한 유형에 맞는 입력 항목만 보여드려요',
      child: Column(
        children: [
          const SizedBox(height: 12),
          for (final type in ComboPlaceType.values) ...[
            _TypeOption(
              type: type,
              selected: type == value,
              onTap: () => onChanged(type),
            ),
            if (type != ComboPlaceType.values.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  final ComboPlaceType type;
  final bool selected;
  final VoidCallback onTap;

  const _TypeOption({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? type.tint : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? type.accent : const Color(0xFFE8EBF2),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(type.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          type.label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: selected ? type.accent : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // 방문형/예약형 배지 — 두 유형을 가르는 기준을 이름
                      // 옆에 바로 붙여 고를 때 헷갈리지 않게 한다.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? type.accent.withValues(alpha: 0.14)
                              : const Color(0xFFEDEFF5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          type.kindLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: selected ? type.accent : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    type.examples,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? type.accent : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }
}

/// 유형을 바꾸기 전 확인 — 지금 유형에만 있는 입력값이 화면에서 사라진다는
/// 걸 분명히 알린다(사라진 값은 그 유형의 임시저장으로 남아 다시 돌아오면
/// "이어서 작성"으로 복구할 수 있다).
///
/// 두 유형의 폼은 **상태를 하나도 공유하지 않는다** — 유형을 바꾸면 화면
/// 입력은 모두 사라지고, 지금까지 쓴 내용은 그 유형의 임시저장에만 남는다.
/// 문구가 그 사실을 그대로 말한다.
///
/// (예전에는 공통 입력값을 셸이 들고 있던 콤보 등록이 이 함수를 함께 써서
///  "공통 정보는 유지된다"는 다른 문구가 필요했다. 콤보 등록이 없어지면서
///  그 갈래[keepsCommonInfo]도 함께 지웠다 — 남겨두면 아무도 안 쓰는 거짓
///  문구가 코드에 남는다.)
Future<bool> confirmSpaceTypeChange(
  BuildContext context, {
  required ComboPlaceType from,
  required ComboPlaceType to,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('공간 유형을 바꿀까요?', style: comboTitleStyle),
      content: Text(
        '"${from.label}" → "${to.label}"로 바꾸면 '
        '입력 항목이 완전히 달라져서 지금 화면의 입력값은 모두 사라져요.\n\n'
        '지금까지 쓴 내용은 "${from.label}" 임시저장에 남으니, 다시 돌아오면 '
        '"이어서 작성"으로 복구할 수 있어요.',
        style: const TextStyle(height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: to.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('유형 바꾸기'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
