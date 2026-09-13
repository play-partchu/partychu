import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:party_app/models/party_schedule.dart';

const _kPink = Color(0xFFFF6FA0);

/// "시작 몇 전"을 시간·분 두 휠로 고르는 시트. 돌려주는 값은 **전체 분**이다
/// (1시간 30분 → 90).
///
/// 모집 마감을 1·2·3시간처럼 정해진 칸에서만 고르던 걸 대체한다 — 59분 전,
/// 1시간 30분 전처럼 1분 단위로 잡을 수 있어야 하기 때문이다.
Future<int?> showWheelDurationPicker(
  BuildContext context, {
  required int initialMinutes,
  String title = '파티 시작 전 시간',
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _WheelDurationSheet(initialMinutes: initialMinutes, title: title),
  );
}

/// 휠에 올릴 수 있는 최대치 — 30일 전까지.
const int kMaxDeadlineMinutesBefore = 30 * 24 * 60;

class _WheelDurationSheet extends StatefulWidget {
  const _WheelDurationSheet({
    required this.initialMinutes,
    required this.title,
  });

  final int initialMinutes;
  final String title;

  @override
  State<_WheelDurationSheet> createState() => _WheelDurationSheetState();
}

class _WheelDurationSheetState extends State<_WheelDurationSheet> {
  // 시 휠은 0~72시간(3일)까지. 그보다 긴 마감은 직접 입력으로 넣는다.
  static const _maxHours = 72;

  late int _hours = (widget.initialMinutes ~/ 60).clamp(0, _maxHours);
  late int _minutes = widget.initialMinutes % 60;

  late final _hourCtrl = FixedExtentScrollController(initialItem: _hours);
  late final _minuteCtrl = FixedExtentScrollController(initialItem: _minutes);

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  int get _selected => _hours * 60 + _minutes;

  Widget _wheel({
    required int itemCount,
    required int selectedIndex,
    required FixedExtentScrollController controller,
    required ValueChanged<int> onChanged,
    required String Function(int) label,
  }) => Expanded(
    child: CupertinoPicker(
      scrollController: controller,
      itemExtent: 44,
      looping: false,
      squeeze: 1.1,
      magnification: 1.05,
      useMagnifier: true,
      selectionOverlay: const SizedBox.shrink(),
      onSelectedItemChanged: (i) => setState(() => onChanged(i)),
      children: List.generate(itemCount, (i) {
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
                      itemCount: _maxHours + 1,
                      selectedIndex: _hours,
                      controller: _hourCtrl,
                      onChanged: (i) => _hours = i,
                      label: (i) => '$i시간',
                    ),
                    _wheel(
                      itemCount: 60,
                      selectedIndex: _minutes,
                      controller: _minuteCtrl,
                      onChanged: (i) => _minutes = i,
                      label: (i) => '$i분',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              // 0분 전 = 시작 시각에 마감 — 의미가 있으므로 막지 않는다.
              onPressed: () => Navigator.pop(context, _selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                '${formatMinutesBeforeStart(_selected)} 선택',
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
