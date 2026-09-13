import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/models/custom_play_item.dart';

const _kAccent = Color(0xFFFF6FA0);
const _kBoxFill = Color(0xFFF7F7FA);
const _kBorder = Color(0xFFE8EBF2);

/// 놀거리 프리셋에서 **'기타'를 골랐을 때** 그 아래에 펼쳐지는 자유기재 칸.
///
/// 프리셋([PlaceAttributeCatalog.playItems])은 조금도 건드리지 않는다 —
/// 여기서 적은 말은 [CustomPlayItems.field] 배열로만 간다.
///
/// ── 검색되는 이름을 받는 칸으로 읽히게 하는 장치 ──────────────────────────
/// 게스트는 이 목록에서 **이름을 눌러** 플레이스를 좁힌다. 그래서 문장이
/// 들어오면 그 항목은 아무에게도 안 눌린다. 안내가 먼저 짧은 이름을 말하고,
/// 칸 자체가 [CustomPlayItems.maxLength]에서 잘리며, 넘치면
/// [CustomPlayItems.shortNameMessage]로 막는다.
///
/// ── 저장 버튼을 따로 두지 않는다 ──────────────────────────────────────────
/// '추가'는 목록에 한 줄을 넣는 것이고, 문서에 쓰는 시점은 등록 화면의
/// 저장 하나뿐이다. 저장 경로가 둘이 되면 어느 쪽이 정본인지 알 수 없어진다.
class CustomPlayItemSection extends StatefulWidget {
  /// 지금까지 추가한 항목(표시 원문). 순서가 곧 저장 순서다.
  final List<String> items;

  /// 항목이 바뀔 때마다 — 이미 [CustomPlayItems.sanitize]를 거친 값이다.
  final ValueChanged<List<String>> onChanged;

  const CustomPlayItemSection({
    super.key,
    required this.items,
    required this.onChanged,
  });

  @override
  State<CustomPlayItemSection> createState() => _CustomPlayItemSectionState();
}

class _CustomPlayItemSectionState extends State<CustomPlayItemSection> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'custom-play-item-input');

  /// 추가를 막은 이유. 입력이 바뀌면 지운다.
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final message = CustomPlayItems.validate(raw, existing: widget.items);
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    widget.onChanged(CustomPlayItems.sanitize([...widget.items, raw]));
    _controller.clear();
    setState(() => _error = null);
    // 연달아 여러 개를 넣는 경우가 흔하다 — 포커스를 그대로 둔다.
    _focus.requestFocus();
  }

  void _remove(String item) {
    widget.onChanged([
      for (final i in widget.items)
        if (!CustomPlayItems.sameItem(i, item)) i,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.items.length >= CustomPlayItems.maxCount;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: _kBoxFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            CustomPlayItems.sectionTitle,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          // 안내가 입력칸보다 **먼저** 온다 — 칸을 본 뒤에 읽는 안내는 늦다.
          const Text(
            CustomPlayItems.inputGuide,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: Colors.black45,
            ),
          ),
          const SizedBox(height: 10),
          _buildInput(full),
          if (widget.items.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in widget.items)
                  _PlayItemChip(label: item, onRemove: () => _remove(item)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInput(bool full) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            enabled: !full,
            textInputAction: TextInputAction.done,
            // 칸 자체가 길이를 넘기지 못하게 막는다 — 다 쓰고 나서 거절당하는
            // 것보다 애초에 안 써지는 편이 덜 답답하다.
            maxLength: CustomPlayItems.maxLength,
            inputFormatters: [
              LengthLimitingTextInputFormatter(CustomPlayItems.maxLength),
            ],
            style: const TextStyle(fontSize: 13),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: _add,
            decoration: InputDecoration(
              hintText: full
                  ? CustomPlayItems.fullMessage
                  : CustomPlayItems.inputHint,
              hintStyle: const TextStyle(fontSize: 12.5, color: Colors.black26),
              counterText: '',
              errorText: _error,
              errorStyle: const TextStyle(fontSize: 11.5),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kAccent),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // 칸이 오류 문구로 길어져도 버튼은 입력줄에 붙어 있어야 한다.
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: TextButton(
            onPressed: full ? null : () => _add(_controller.text),
            style: TextButton.styleFrom(
              backgroundColor: full ? const Color(0xFFE4E6EE) : _kAccent,
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              minimumSize: const Size(0, 42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              '추가',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

/// 추가한 항목 한 칸 — 개별 삭제(×)가 붙는다.
class _PlayItemChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _PlayItemChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kAccent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _kAccent,
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(3),
              child: Icon(Icons.close, size: 13, color: _kAccent),
            ),
          ),
        ],
      ),
    );
  }
}
