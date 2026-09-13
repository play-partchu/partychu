import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const _kPink = Color(0xFFFF6FA0);

/// 파티 폼 공통 시간선택기 — 오전/오후 · 시(1~12) · 분(00~59)을 각각 세로
/// 휠로 굴려 고른다(삼성 알람 방식).
///
/// 예전에는 시간 버튼 그리드 + 정각/30분 두 개짜리 선택(showCustomTimePicker)
/// 이었는데, 30분 단위로 묶이는 제약 때문에 "오후 7시 23분" 같은 시각을 아예
/// 넣을 수 없었다. 지금은 이 선택기 하나로 통일해서 등록/재등록/콤보 등록과
/// 체크인·체크아웃까지 전부 1분 단위로 고른다.
///
/// 돌려주는 값은 항상 24시간제 [TimeOfDay]라 기존 저장 포맷·서버 로직과
/// 그대로 호환된다(오후 7시 23분 → 19:23, 오전 12시 05분 → 00:05).
Future<TimeOfDay?> showWheelTimePicker(
  BuildContext context, {
  required TimeOfDay initial,
  required String title,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WheelTimePickerSheet(initial: initial, title: title),
  );
}

/// 12시간제 라벨 — 0시는 "오전 12시", 12시는 "오후 12시"로 읽고 분은 두 자리로
/// 채운다("오전 12시 05분").
String formatKoreanTime(TimeOfDay t) {
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '${t.hour < 12 ? '오전' : '오후'} $hour12시 $minute분';
}

class _WheelTimePickerSheet extends StatefulWidget {
  const _WheelTimePickerSheet({required this.initial, required this.title});

  final TimeOfDay initial;
  final String title;

  @override
  State<_WheelTimePickerSheet> createState() => _WheelTimePickerSheetState();
}

class _WheelTimePickerSheetState extends State<_WheelTimePickerSheet> {
  // 0 = 오전, 1 = 오후.
  late int _period = widget.initial.hour < 12 ? 0 : 1;
  // 시 휠은 1시~12시를 순서대로 나열한다 — 인덱스 i가 (i + 1)시.
  late int _hourIndex =
      (widget.initial.hour % 12 == 0 ? 12 : widget.initial.hour % 12) - 1;
  late int _minute = widget.initial.minute;

  late final _periodCtrl = FixedExtentScrollController(initialItem: _period);
  late final _hourCtrl = FixedExtentScrollController(initialItem: _hourIndex);
  late final _minuteCtrl = FixedExtentScrollController(initialItem: _minute);

  @override
  void dispose() {
    _periodCtrl.dispose();
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  /// 휠 세 개(오전·오후 / 시 / 분)를 24시간제로 되돌린다.
  TimeOfDay get _selected {
    final hour12 = _hourIndex + 1;
    final h24 = _period == 0
        ? (hour12 == 12 ? 0 : hour12)
        : (hour12 == 12 ? 12 : hour12 + 12);
    return TimeOfDay(hour: h24, minute: _minute);
  }

  Widget _wheel({
    required int itemCount,
    required int selectedIndex,
    required FixedExtentScrollController controller,
    required ValueChanged<int> onChanged,
    required String Function(int) label,
    bool looping = true,
  }) => Expanded(
    child: CupertinoPicker(
      scrollController: controller,
      itemExtent: 44,
      looping: looping,
      squeeze: 1.1,
      magnification: 1.05,
      useMagnifier: true,
      selectionOverlay: const SizedBox.shrink(),
      onSelectedItemChanged: (i) => setState(() => onChanged(i)),
      children: List.generate(itemCount, (i) {
        // 가운데 값만 진하게, 위아래로 스쳐 지나가는 값들은 흐리게.
        final isSelected = i == selectedIndex;
        return Center(
          child: Text(
            label(i),
            style: TextStyle(
              fontSize: isSelected ? 21 : 19,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? _kPink : Colors.black26,
            ),
          ),
        );
      }),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          // 휠 3개(오전·오후 / 시 / 분). 가운데 선택줄은 핑크 배경 띠 하나로
          // 표시하고, 휠 자체의 기본 오버레이는 끈다.
          SizedBox(
            height: 220,
            child: Stack(
              children: [
                Center(
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kPink.withValues(alpha: 0.4)),
                    ),
                  ),
                ),
                Row(
                  children: [
                    _wheel(
                      itemCount: 2,
                      selectedIndex: _period,
                      controller: _periodCtrl,
                      // 오전/오후는 두 칸뿐이라 순환시키면 오히려 헷갈린다.
                      looping: false,
                      onChanged: (i) => _period = i,
                      label: (i) => i == 0 ? '오전' : '오후',
                    ),
                    _wheel(
                      itemCount: 12,
                      selectedIndex: _hourIndex,
                      controller: _hourCtrl,
                      onChanged: (i) => _hourIndex = i,
                      label: (i) => '${i + 1}시',
                    ),
                    _wheel(
                      itemCount: 60,
                      selectedIndex: _minute,
                      controller: _minuteCtrl,
                      onChanged: (i) => _minute = i,
                      label: (i) => '${i.toString().padLeft(2, '0')}분',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 확인 버튼이 곧 미리보기 — 휠을 굴리는 동안에도 바로 갱신된다.
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                '${formatKoreanTime(_selected)} 선택',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
