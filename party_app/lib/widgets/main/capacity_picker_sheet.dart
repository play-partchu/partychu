import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/models/capacity_filter.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 필요한 인원을 고르는 바텀시트 — 고른 인원(또는 해제를 뜻하는 null)을
/// 돌려준다. 그냥 닫으면 아무것도 돌려주지 않으므로 호출부는 **기존 값을
/// 그대로 유지**해야 한다.
///
/// ## 왜 고정 버튼이 아니라 스테퍼인가
///
/// 처음에는 1·2·3·4·5·6·8·10·15·20명+ 버튼을 늘어놓았다. 7명·13명·27명처럼
/// **목록에 없는 인원이면 고를 방법이 아예 없었다**. 그래서 −/숫자/+ 스테퍼로
/// 바꾸고, 숫자를 누르면 키보드로 직접 적어 넣을 수 있게 했다.
///
/// 돌려주는 값의 뜻은 [CapacityFilter]가 정한다 — "이 인원을 받을 수 있는
/// 곳"이고, 인원을 입력하지 않은 장소는 걸러지지 않는다. **판정은 그대로이고
/// 고르는 방법만 바뀌었다.**
///
/// ## 구간 버튼은 스테퍼를 대체하지 않는다
///
/// 게스트가 실제로 아는 것은 '우리 일행 5~10명'이지 '10명을 받는 곳'이
/// 아니다. 그래서 [CapacityFilter.presets] 구간 버튼을 **위에 얹었다.**
/// 다만 예전에 고정 버튼만 두었다가 7명·13명·27명을 고를 수 없어 스테퍼로
/// 바꿨던 이력이 있으므로(위 참고), 스테퍼는 그대로 둔다 — 구간은 지름길일
/// 뿐이고 누르면 스테퍼 값이 그 구간의 최대 인원으로 바뀔 뿐이다.
Future<int?> showCapacityPickerSheet(
  BuildContext context, {
  required int? selected,
}) {
  return showModalBottomSheet<_CapacityResult>(
    context: context,
    isScrollControlled: true, // 키보드가 올라와도 입력칸이 가리지 않게
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _CapacityPickerSheet(selected: selected),
  ).then((r) => r == null ? selected : r.people);
}

/// null(= 인원 무관)과 "닫기만 함"을 구별하기 위한 포장.
class _CapacityResult {
  final int? people;
  const _CapacityResult(this.people);
}

class _CapacityPickerSheet extends StatefulWidget {
  final int? selected;

  const _CapacityPickerSheet({required this.selected});

  @override
  State<_CapacityPickerSheet> createState() => _CapacityPickerSheetState();
}

class _CapacityPickerSheetState extends State<_CapacityPickerSheet> {
  /// 아직 고른 적이 없으면 2명에서 시작한다 — 혼자 쓰는 경우보다 일행이 있는
  /// 경우가 많고, −를 한 번 누르면 곧바로 1명이 된다.
  static const int _initialWhenUnset = 2;

  late final TextEditingController _controller = TextEditingController(
    text: '${widget.selected ?? _initialWhenUnset}',
  );

  /// +/− 를 길게 누르는 동안만 살아 있는 타이머. 손을 떼거나 시트가 사라지면
  /// 반드시 멈춘다 — 남아 있으면 dispose된 State에 setState를 부른다.
  Timer? _repeat;

  @override
  void dispose() {
    _repeat?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 지금 적혀 있는 값. 숫자가 아니거나 0·음수면 null(= 적용 불가).
  int? get _value => CapacityFilter.parse(_controller.text);

  void _setValue(int people) {
    final next = CapacityFilter.clamp(people);
    if (_controller.text == '$next') return;
    _controller.text = '$next';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  /// 한 칸 움직인다. 빈 칸이거나 잘못된 값이면 최소 인원부터 다시 센다.
  void _step(int delta) {
    setState(() => _setValue((_value ?? CapacityFilter.minPeople) + delta));
  }

  /// 길게 누르는 동안 반복 — 끝값에 닿으면 [CapacityFilter.clamp]가 막아 주고,
  /// 값이 더 변하지 않으면 타이머를 스스로 멈춘다(무한 반복 방지).
  void _startRepeat(int delta) {
    _repeat?.cancel();
    _repeat = Timer.periodic(const Duration(milliseconds: 80), (t) {
      final before = _value;
      _step(delta);
      if (_value == before) t.cancel();
    });
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  /// 구간 버튼 하나 — 지금 값이 그 구간의 수와 같으면 켜진 것으로 보인다.
  Widget _presetChip(String label, int people, int? value) {
    final selected = value == people;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _setValue(people)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? PartyChuColors.primary : const Color(0xFFF6F6F8),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? PartyChuColors.primary : const Color(0xFFEDEDF0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF4A4A55),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    return Padding(
      // 키보드가 올라온 만큼 시트를 밀어 올린다.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
              const Text(
                '몇 명이 이용하나요?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                '고른 인원을 받을 수 있는 곳만 보여드려요.',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
              const SizedBox(height: 16),
              // 구간 지름길 — 누르면 스테퍼 값이 바뀐다(별도 상태가 없다).
              Wrap(
                spacing: 7,
                runSpacing: 7,
                alignment: WrapAlignment.center,
                children: [
                  for (final preset in CapacityFilter.presets)
                    _presetChip(preset.label, preset.people, value),
                ],
              ),
              const SizedBox(height: 16),
              _stepper(),
              const SizedBox(height: 6),
              SizedBox(
                height: 18,
                child: Text(
                  value == null
                      ? '1명 이상 숫자로 적어주세요.'
                      : '최대 ${CapacityFilter.maxPeople}명까지 고를 수 있어요.',
                  style: TextStyle(
                    fontSize: 11,
                    color: value == null
                        ? const Color(0xFFE53935)
                        : Colors.black38,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  // 0·음수·빈 값이면 적용할 수 없다.
                  onPressed: value == null
                      ? null
                      : () => Navigator.pop(context, _CapacityResult(value)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PartyChuColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFF0F0F4),
                    disabledForegroundColor: Colors.black26,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    value == null ? '적용' : '${CapacityFilter.label(value)} 적용',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 초기화 — '인원 무관'을 고르면 조건이 풀린다.
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, const _CapacityResult(null)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.selected == null
                        ? PartyChuColors.primary
                        : Colors.black54,
                    side: BorderSide(
                      color: widget.selected == null
                          ? PartyChuColors.primary
                          : const Color(0xFFE0E0E6),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '인원 무관',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 인원을 적지 않은 장소를 왜 계속 보여주는지 그 자리에서 알린다 —
              // 모르고 보면 "필터가 안 걸렸다"로 읽힌다.
              const Text(
                '인원 정보가 없는 곳은 숨기지 않고 함께 보여드려요.',
                style: TextStyle(fontSize: 11, color: Colors.black38),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [ − ]  7명  [ + ] — 가운데 숫자를 누르면 키보드로 직접 적는다.
  Widget _stepper() {
    final value = _value;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _stepButton(
          icon: Icons.remove_rounded,
          // 최소값에서는 더 줄일 수 없다 — 길게 눌러도 마찬가지다.
          enabled: value == null || value > CapacityFilter.minPeople,
          delta: -1,
        ),
        SizedBox(
          width: 120,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              IntrinsicWidth(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  // 숫자만, 세 자리까지 — maxPeople(999)과 같은 길이다.
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  onChanged: (_) => setState(() {}),
                  // 다 적고 확인을 누르면 곧바로 적용한다.
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    final v = _value;
                    if (v != null) {
                      Navigator.pop(context, _CapacityResult(v));
                    }
                  },
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: PartyChuColors.primary,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: '0',
                  ),
                ),
              ),
              const Text(
                '명',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        _stepButton(
          icon: Icons.add_rounded,
          enabled: value == null || value < CapacityFilter.maxPeople,
          delta: 1,
        ),
      ],
    );
  }

  Widget _stepButton({
    required IconData icon,
    required bool enabled,
    required int delta,
  }) {
    return GestureDetector(
      onTap: enabled ? () => _step(delta) : null,
      // 길게 누르면 빠르게 반복 — 끝값에 닿으면 스스로 멈추고, 손을 떼면
      // 어느 경로로 끝나든(취소 포함) 반드시 멈춘다.
      onLongPress: enabled ? () => _startRepeat(delta) : null,
      onLongPressEnd: (_) => _stopRepeat(),
      onLongPressCancel: _stopRepeat,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : const Color(0xFFF7F7FA),
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled ? PartyChuColors.primary : const Color(0xFFE0E0E6),
          ),
        ),
        child: Icon(
          icon,
          size: 22,
          color: enabled ? PartyChuColors.primary : Colors.black26,
        ),
      ),
    );
  }
}
