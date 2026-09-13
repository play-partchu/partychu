import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/models/custom_amenity.dart';
import 'package:party_app/services/custom_amenity_catalog_service.dart';

/// 호스트가 **기타 편의 서비스**를 직접 입력하는 영역.
///
/// 정식 편의 서비스 선택지 **아래에** 붙는다 — 정본 taxonomy는 그대로 두고,
/// 거기 없는 것만 여기에 적는다.
///
/// ── 검색 키워드를 받는 칸으로 읽히게 하는 장치 ────────────────────────────
/// 이 칸은 홍보 문구를 적는 자리가 아니다. 그렇게 읽히면 "루프탑에서 즐기는
/// 특별한 밤"처럼 아무도 검색하지 않는 문장이 쌓이고, 그때부터 이 축의 필터는
/// 쓸모가 없어진다. 그래서
///
///  · 안내 문구가 "짧고 명확한 단어"를 먼저 말하고([CustomAmenities.inputGuide]),
///  · placeholder도 예시 하나만 짧게 보여주고([CustomAmenities.inputHint]),
///  · 입력칸 자체가 [CustomAmenities.maxLength]에서 잘리며,
///  · 길게 쓰면 저장 전에 [CustomAmenities.tooLongMessage]로 막는다.
///
/// 두세 단어("반려동물 물그릇")는 막지 않는다 — 막아야 하는 것은 문장이다.
///
/// ── 자동완성 ──────────────────────────────────────────────────────────────
/// 입력 중에 이미 쓰이는 항목을 먼저 보여준다. 새 말을 만들기 전에 기존 말을
/// 고르게 해서 유아의자 / 아기의자 / 유아 의자가 따로 쌓이는 것을 줄인다.
class CustomAmenitySection extends StatefulWidget {
  /// 지금까지 고른 항목(표시 원문). 순서가 곧 저장 순서다.
  final List<String> items;

  /// 항목이 바뀔 때마다 — 이미 [CustomAmenities.sanitize]를 거친 값이다.
  final ValueChanged<List<String>> onChanged;

  /// 제목과 흰 카드를 이 위젯이 그릴지. 이미 카드 안에 넣는 화면은 false로
  /// 두고 자기 카드 스타일을 그대로 쓴다.
  final bool showTitle;

  const CustomAmenitySection({
    super.key,
    required this.items,
    required this.onChanged,
    this.showTitle = true,
  });

  @override
  State<CustomAmenitySection> createState() => _CustomAmenitySectionState();
}

class _CustomAmenitySectionState extends State<CustomAmenitySection> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'custom-amenity-input');

  /// 입력칸을 펼쳤는지 — 평소에는 '+ 기타 편의 서비스 추가' 버튼만 보인다.
  bool _open = false;

  /// 저장을 막은 이유. 입력이 바뀌면 지운다.
  String? _error;

  /// 다른 호스트가 이미 쓰고 있는 항목(자동완성 후보).
  List<CustomAmenityEntry> _catalog = CustomAmenityCatalogService.cached;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    // 후보가 늦게 와도 화면은 이미 쓸 수 있다 — 오면 조용히 붙는다.
    CustomAmenityCatalogService.load().then((v) {
      if (mounted) setState(() => _catalog = v);
    });
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_error != null) setState(() => _error = null);
    // 후보 목록이 입력에 따라 바뀐다.
    setState(() {});
  }

  void _openInput() {
    setState(() => _open = true);
    // autofocus 대신 한 번만 요청한다 — autofocus는 rebuild마다 다시 걸려
    // 키보드가 깜빡인다(장소대여 등록 화면의 직접 입력과 같은 이유).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open) _focus.requestFocus();
    });
  }

  /// 입력칸을 닫는다. **먼저 포커스를 놓고** 트리에서 없앤다 — 포커스를 가진
  /// 채 사라지면 스코프가 직전 입력칸으로 포커스를 되돌리며 목록이 튄다.
  void _closeInput() {
    _focus.unfocus();
    _controller.clear();
    setState(() {
      _open = false;
      _error = null;
    });
  }

  void _add(String raw) {
    final message = CustomAmenities.validate(raw, existing: widget.items);
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    final next = CustomAmenities.sanitize([...widget.items, raw]);
    widget.onChanged(next);
    _controller.clear();
    setState(() => _error = null);
    // 연달아 여러 개를 넣는 경우가 흔하다 — 칸을 닫지 않고 포커스를 유지한다.
    _focus.requestFocus();
  }

  void _remove(String item) {
    widget.onChanged([
      for (final i in widget.items)
        if (!CustomAmenities.sameItem(i, item)) i,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (!widget.showTitle) return body;
    // 같은 화면의 다른 섹션(좌석·공간 / 외부 음식)과 같은 카드 모양을 쓴다 —
    // 이 칸만 다르게 생기면 "정식 항목이 아닌 무언가"로 읽힌다.
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '✨ 기타 편의 서비스',
            style: TextStyle(
              fontFamily: 'SeoulHangang',
              fontSize: 17,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }

  Widget _buildBody() {
    final full = widget.items.length >= CustomAmenities.maxCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 안내가 입력칸보다 **먼저** 온다 — 칸을 본 뒤에 읽는 안내는 이미 늦다.
        const Text(
          CustomAmenities.inputGuide,
          style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black54),
        ),
        const SizedBox(height: 2),
        const Text(
          CustomAmenities.inputExamples,
          style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black38),
        ),
        const SizedBox(height: 10),
        if (widget.items.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in widget.items)
                _AmenityChip(label: item, onRemove: () => _remove(item)),
            ],
          ),
          const SizedBox(height: 10),
        ],
        if (!_open)
          _AddButton(
            enabled: !full,
            onTap: full ? null : _openInput,
            label: full
                ? '최대 ${CustomAmenities.maxCount}개까지 추가할 수 있어요'
                : '＋ 기타 편의 서비스 추가',
          )
        else
          _buildInput(),
      ],
    );
  }

  Widget _buildInput() {
    final suggestions = CustomAmenities.suggestionsFor(
      _catalog,
      _controller.text,
      exclude: widget.items,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                textInputAction: TextInputAction.done,
                // 칸 자체가 길이를 넘기지 못하게 막는다 — 다 쓰고 나서
                // 거절당하는 것보다 애초에 안 써지는 편이 덜 답답하다.
                maxLength: CustomAmenities.maxLength,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(CustomAmenities.maxLength),
                ],
                decoration: InputDecoration(
                  hintText: CustomAmenities.inputHint,
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: Colors.black38,
                  ),
                  counterText: '',
                  errorText: _error,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFDDE1EC)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF7C5CBF)),
                  ),
                ),
                onSubmitted: _add,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _add(_controller.text),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF7C5CBF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('추가', style: TextStyle(fontSize: 13)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.black38),
              onPressed: _closeInput,
              tooltip: '닫기',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            '이미 쓰이고 있는 항목',
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in suggestions)
                _SuggestionChip(entry: s, onTap: () => _add(s.label)),
            ],
          ),
        ],
      ],
    );
  }
}

/// 고른 항목 한 칸.
class _AmenityChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _AmenityChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EFFB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF7C5CBF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5B3FA0),
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(3),
              child: Icon(Icons.close, size: 13, color: Color(0xFF5B3FA0)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 이미 쓰이는 항목 후보 한 칸 — 몇 곳이 쓰는지까지 보여준다.
class _SuggestionChip extends StatelessWidget {
  final CustomAmenityEntry entry;
  final VoidCallback onTap;

  const _SuggestionChip({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFDDE1EC)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              entry.label,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
            const SizedBox(width: 4),
            Text(
              '${entry.count}',
              style: const TextStyle(fontSize: 11, color: Colors.black38),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;
  final String label;

  const _AddButton({
    required this.enabled,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: enabled ? const Color(0xFF7C5CBF) : const Color(0xFFDDE1EC),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: enabled ? const Color(0xFF5B3FA0) : Colors.black38,
          ),
        ),
      ),
    );
  }
}
