import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const _kPink = Color(0xFFFF6FA0);

/// 사용자가 직접 지정한 방문 시간 조건.
/// [end]가 null이면 **지정시간**("그 시각에 영업 중"), 있으면 **지정구간**
/// ("그 구간을 전부/일부 영업")이다. 두 방식은 뜻이 달라 서로를 대체하지 않는다.
typedef VisitTimeChoice = ({TimeOfDay start, TimeOfDay? end});

/// 플레이스 빠른 시간 필터의 '시간지정' 시트 — 알람 설정처럼 **30분 단위 휠**을
/// 돌려 고른다.
///
/// 48줄짜리 세로 목록을 스크롤하던 방식을 대신한다. 휠은 높이가 고정(176px)
/// 이라 목록처럼 시트가 길어지지 않고, 자정을 넘기는 조건(20:00 ~ 익일 02:00)도
/// 종료가 시작보다 이르면 그대로 성립한다.
///
///     [ 지정시간 | 지정구간 ]        ← 위에서 방식을 먼저 고른다
///           20:00                  ← 지정시간: 휠 1개
///        20:00  →  02:00           ← 지정구간: 휠 2개
///
/// 돌려주는 값은 [VisitTimeChoice]이고, 취소하면 null이라 기존 조건이 그대로
/// 남는다.
Future<VisitTimeChoice?> showVisitTimePicker(
  BuildContext context, {
  TimeOfDay? start,
  TimeOfDay? end,
}) {
  return showModalBottomSheet<VisitTimeChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VisitTimePickerSheet(start: start, end: end),
  );
}

/// 30분 단위 슬롯 48개 — 휠의 한 칸이 곧 하나의 시각이다.
const int _slotCount = 48;

TimeOfDay _slotTime(int i) => TimeOfDay(hour: i ~/ 2, minute: (i % 2) * 30);

int _slotIndex(TimeOfDay t) => t.hour * 2 + (t.minute >= 30 ? 1 : 0);

String _hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';

class _VisitTimePickerSheet extends StatefulWidget {
  const _VisitTimePickerSheet({this.start, this.end});

  final TimeOfDay? start;
  final TimeOfDay? end;

  @override
  State<_VisitTimePickerSheet> createState() => _VisitTimePickerSheetState();
}

class _VisitTimePickerSheetState extends State<_VisitTimePickerSheet> {
  /// 지금 고르는 방식 — 이미 범위가 걸려 있으면 범위로 열어준다.
  late bool _isRange = widget.end != null;

  late int _startIndex = _slotIndex(
    widget.start ?? const TimeOfDay(hour: 20, minute: 0),
  );
  late int _endIndex = _slotIndex(
    widget.end ?? const TimeOfDay(hour: 2, minute: 0),
  );

  late final _startCtrl = FixedExtentScrollController(initialItem: _startIndex);
  late final _endCtrl = FixedExtentScrollController(initialItem: _endIndex);

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  TimeOfDay get _start => _slotTime(_startIndex);
  TimeOfDay get _end => _slotTime(_endIndex);

  /// 종료가 시작보다 이르거나 같으면 자정을 넘긴 것으로 읽는다(필터 판정과
  /// 같은 규칙).
  bool get _crossesMidnight => _isRange && _endIndex <= _startIndex;

  /// 확인 버튼에 그대로 얹는 미리보기 — 휠을 굴리는 동안에도 갱신된다.
  String get _preview => _isRange
      ? '${_hhmm(_start)} ~ ${_crossesMidnight ? '익일 ' : ''}${_hhmm(_end)}'
      : '${_hhmm(_start)} 영업 중';

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
        16 + MediaQuery.of(context).padding.bottom,
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
          const SizedBox(height: 14),
          // 방식 고르기 — 두 조건은 뜻이 다르므로 먼저 무엇을 정할지 고른다.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _modeChip('지정시간', selected: !_isRange, range: false),
              const SizedBox(width: 6),
              _modeChip('지정구간', selected: _isRange, range: true),
            ],
          ),
          const SizedBox(height: 12),
          // 휠 영역 — 높이는 방식과 무관하게 고정이라 시트가 길어지지 않는다.
          SizedBox(
            height: 176,
            child: Stack(
              children: [
                // 가운데 선택줄.
                Center(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kPink.withValues(alpha: 0.4)),
                    ),
                  ),
                ),
                if (_isRange)
                  Row(
                    children: [
                      _wheel(
                        controller: _startCtrl,
                        selectedIndex: _startIndex,
                        onChanged: (i) => _startIndex = i,
                      ),
                      const SizedBox(
                        width: 28,
                        child: Center(
                          child: Text(
                            '→',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.black38,
                            ),
                          ),
                        ),
                      ),
                      _wheel(
                        controller: _endCtrl,
                        selectedIndex: _endIndex,
                        onChanged: (i) => _endIndex = i,
                        // 자정을 넘기는 칸은 '익일'을 붙여 그 자리에서 알린다.
                        nextDayFrom: _startIndex,
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      _wheel(
                        controller: _startCtrl,
                        selectedIndex: _startIndex,
                        onChanged: (i) => _startIndex = i,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, (
                start: _start,
                end: _isRange ? _end : null,
              )),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPink,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                '$_preview 적용',
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

  Widget _modeChip(
    String label, {
    required bool selected,
    required bool range,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _isRange = range),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _kPink : const Color(0xFFF6F6F8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _kPink : const Color(0xFFEDEDF0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : const Color(0xFF4A4A4A),
          ),
        ),
      ),
    );
  }

  /// 30분 단위 시각 휠 하나. [nextDayFrom]을 주면 그 인덱스 이하인 칸에
  /// '익일'을 붙인다.
  Widget _wheel({
    required FixedExtentScrollController controller,
    required int selectedIndex,
    required ValueChanged<int> onChanged,
    int? nextDayFrom,
  }) {
    return Expanded(
      child: CupertinoPicker(
        scrollController: controller,
        itemExtent: 42,
        looping: true,
        squeeze: 1.1,
        magnification: 1.05,
        useMagnifier: true,
        selectionOverlay: const SizedBox.shrink(),
        onSelectedItemChanged: (i) => setState(() => onChanged(i)),
        children: List.generate(_slotCount, (i) {
          final isSelected = i == selectedIndex;
          final nextDay = nextDayFrom != null && i <= nextDayFrom;
          return Center(
            child: Text(
              '${nextDay ? '익일 ' : ''}${_hhmm(_slotTime(i))}',
              style: TextStyle(
                fontSize: isSelected ? 20 : 18,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? _kPink : Colors.black26,
              ),
            ),
          );
        }),
      ),
    );
  }
}
