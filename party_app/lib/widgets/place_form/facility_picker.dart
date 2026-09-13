import 'package:flutter/material.dart';

/// 편의시설 선택(프리셋 칩 + 직접 입력) 블록.
///
/// 이 위젯이 따로 있는 이유는 두 가지 스크롤 문제 때문이다.
///
/// 1) **포커스가 옮겨가면서 화면이 위로 튀는 문제**
///    직접 입력한 값을 추가하면 입력칸이 트리에서 사라지는데, 그때 그 입력칸이
///    아직 포커스를 갖고 있으면 Flutter가 포커스를 잃은 노드 대신
///    `FocusScopeNode.focusedChild`(= 그 전에 포커스를 가졌던 입력칸, 보통
///    화면 위쪽의 이름 입력칸)로 포커스를 되돌린다. 되돌아간 입력칸의
///    EditableText는 `showOnScreen()`을 호출하고, 그게 조상 ListView를 그
///    입력칸 위치까지 스크롤시킨다 — 이게 "갑자기 위로 튀어 오르는" 정체다.
///    그래서 입력칸을 없애기 **전에** 반드시 [FocusNode.unfocus]를 부른다.
///    기본 [UnfocusDisposition.scope]가 스코프의 포커스 이력을 비워주기 때문에
///    되돌아갈 입력칸 자체가 없어진다.
///
/// 2) **화면 전체 rebuild로 스크롤이 흔들리는 문제**
///    편의시설 상태를 등록 화면 State가 들고 있으면 칩 하나 켤 때마다
///    `setState`가 페이지 전체(ListView의 모든 자식, 아코디언, 객실 카드까지)를
///    다시 만든다. 선택 상태를 이 위젯이 직접 들고 있어서 바깥 화면은 다시
///    빌드되지 않고, 따라서 보고 있던 스크롤 위치가 그대로 유지된다.
///
/// 선택값은 [selected] · [custom] Set을 **제자리에서** 고친다 — 부모는 저장
/// 시점에 넘겨준 그 Set을 그대로 읽으면 된다. 값이 바뀌면 [onChanged]로만
/// 알리므로, 부모는 임시저장 dirty 표시 같은 가벼운 일만 하고 `setState`는
/// 하지 않아야 한다(했다면 2번 문제가 그대로 돌아온다).
class FacilityPicker extends StatefulWidget {
  /// 프리셋 편의시설 목록.
  final List<String> options;

  /// 프리셋 중 선택된 것 — 부모 소유 Set을 제자리에서 고친다.
  final Set<String> selected;

  /// 직접 입력으로 추가한 것 — 부모 소유 Set을 제자리에서 고친다.
  final Set<String> custom;

  /// 선택이 바뀔 때마다 호출. 부모는 여기서 `setState`를 부르지 않는다.
  final VoidCallback? onChanged;

  final String inputHint;

  /// 선택된 칩·직접 입력 칩의 강조색.
  final Color accent;

  /// 선택되지 않은 프리셋 칩의 배경색(화면마다 흰색/연회색으로 다르다).
  final Color unselectedFill;

  /// 입력칸 꾸밈 — 화면의 공통 `_inputDeco`를 그대로 넘겨 통일감을 유지한다.
  final InputDecoration Function(String hint) inputDecoration;

  const FacilityPicker({
    super.key,
    required this.options,
    required this.selected,
    required this.custom,
    required this.inputDecoration,
    this.onChanged,
    this.inputHint = '편의시설 이름',
    this.accent = const Color(0xFF7C5CBF),
    this.unselectedFill = Colors.white,
  });

  @override
  State<FacilityPicker> createState() => _FacilityPickerState();
}

class _FacilityPickerState extends State<FacilityPicker> {
  final _ctrl = TextEditingController();

  /// build마다 새로 만들면 매 프레임 포커스가 끊겨 키보드가 닫힌다 —
  /// State가 하나만 들고 있다가 dispose에서 정리한다.
  final _focus = FocusNode(debugLabel: 'facility-custom-input');

  bool _open = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    widget.onChanged?.call();
  }

  void _openInput() {
    setState(() => _open = true);
    // autofocus 대신 한 번만 명시적으로 요청한다 — autofocus는 rebuild될 때마다
    // 다시 적용될 수 있어서 포커스/키보드가 깜빡이는 원인이 된다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open) _focus.requestFocus();
    });
  }

  /// 입력칸을 닫는다. 순서가 중요하다 — **먼저 포커스를 놓고**(스코프의 포커스
  /// 이력까지 비운 뒤) 트리에서 없앤다. 반대로 하면 사라지는 입력칸의 포커스가
  /// 이전 입력칸으로 되돌아가면서 화면이 그쪽으로 스크롤된다.
  void _closeInput() {
    _focus.unfocus(); // 기본 UnfocusDisposition.scope — 포커스 이력을 비운다
    _ctrl.clear();
    setState(() => _open = false);
  }

  void _addCustom() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      _closeInput();
      return;
    }
    // 프리셋에 있는 이름을 직접 쳤으면 프리셋 선택으로 처리한다(중복 방지).
    if (widget.options.contains(text)) {
      widget.selected.add(text);
    } else if (!widget.custom.contains(text)) {
      widget.custom.add(text);
    }
    _closeInput();
    widget.onChanged?.call();
  }

  void _togglePreset(String f) {
    if (widget.selected.contains(f)) {
      widget.selected.remove(f);
    } else {
      widget.selected.add(f);
    }
    _changed();
  }

  void _removeCustom(String f) {
    widget.custom.remove(f);
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in widget.options)
              GestureDetector(
                onTap: () => _togglePreset(f),
                child: _presetChip(f, widget.selected.contains(f)),
              ),
            for (final f in widget.custom)
              _customChip(f, onDelete: () => _removeCustom(f)),
            GestureDetector(
              onTap: _openInput,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7FA),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFDDE1EC)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 14, color: Colors.black54),
                    SizedBox(width: 2),
                    Text(
                      '직접 입력',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_open) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  textInputAction: TextInputAction.done,
                  decoration: widget.inputDecoration(widget.inputHint),
                  onSubmitted: (_) => _addCustom(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addCustom,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.accent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('추가'),
              ),
              IconButton(
                onPressed: _closeInput,
                icon: const Icon(Icons.close, size: 20),
                tooltip: '취소',
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _presetChip(String label, bool selected) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFFF3EFFA) : widget.unselectedFill,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: selected ? widget.accent : const Color(0xFFDDE1EC),
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        color: selected ? widget.accent : Colors.black54,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
    ),
  );

  Widget _customChip(String label, {required VoidCallback onDelete}) =>
      Container(
        padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF3EFFA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: widget.accent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: widget.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: onDelete,
              child: Icon(Icons.close, size: 14, color: widget.accent),
            ),
          ],
        ),
      );
}
