import 'package:flutter/material.dart';
import 'package:party_app/utils/auto_description_classifier.dart';

const _kAccent = Color(0xFFFF6FA0);

/// "간편 자동 꾸미기" 미리보기에서 문단(합성 블록)을 탭했을 때 뜨는 시트 —
/// 스타일(카테고리)과 이모지만 바꿀 수 있다(강조색·정렬은 범위 밖 — 블록
/// 에디터와 공유하는 `PartyDetailBlock` 모델을 건드려야 해서 이번 단계에선
/// 다루지 않는다).
///
/// [currentCategory]/[currentEmoji]/[emojiRemoved]는 호출부가 이미 저장된
/// 오버라이드(있다면) 또는 자동 판정 결과를 넘겨 시트가 그 상태로 열리게
/// 한다. 반환값은 세 가지 중 하나:
/// - `null`: 취소(아무 변화 없음)
/// - `{'reset': true}`: "자동으로 되돌리기"(오버라이드 삭제)
/// - `{'category': String, 'emoji': String?, 'emojiRemoved': bool}`: 적용
Future<Map<String, dynamic>?> showParagraphStyleEditSheet(
  BuildContext context, {
  required AutoDescriptionCategory currentCategory,
  String? currentEmoji,
  bool emojiRemoved = false,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ParagraphStyleEditSheet(
      initialCategory: currentCategory,
      initialEmoji: currentEmoji,
      initialEmojiRemoved: emojiRemoved,
    ),
  );
}

class _ParagraphStyleEditSheet extends StatefulWidget {
  final AutoDescriptionCategory initialCategory;
  final String? initialEmoji;
  final bool initialEmojiRemoved;

  const _ParagraphStyleEditSheet({
    required this.initialCategory,
    required this.initialEmoji,
    required this.initialEmojiRemoved,
  });

  @override
  State<_ParagraphStyleEditSheet> createState() =>
      _ParagraphStyleEditSheetState();
}

class _ParagraphStyleEditSheetState extends State<_ParagraphStyleEditSheet> {
  late AutoDescriptionCategory _category = widget.initialCategory;
  late String? _emoji = widget.initialEmojiRemoved ? null : widget.initialEmoji;
  late bool _emojiRemoved = widget.initialEmojiRemoved;

  void _selectCategory(AutoDescriptionCategory category) {
    if (category == _category) return;
    setState(() {
      _category = category;
      // 카테고리를 바꾸면 이전 카테고리 이모지 풀 기준으로 고른 이모지는
      // 더 이상 맞지 않을 수 있어 "자동 선택"으로 되돌린다.
      _emoji = null;
      _emojiRemoved = false;
    });
  }

  void _apply() {
    Navigator.pop(context, {
      'category': _category.name,
      'emoji': _emojiRemoved ? null : _emoji,
      'emojiRemoved': _emojiRemoved,
    });
  }

  void _resetToAuto() {
    Navigator.pop(context, {'reset': true});
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final emojiPool = autoDescriptionEmojiPool(_category);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '문단 스타일 편집',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 18),
            _sectionLabel('스타일'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in AutoDescriptionCategory.values)
                  ChoiceChip(
                    label: Text(autoDescriptionCategoryLabel(category)),
                    selected: category == _category,
                    onSelected: (_) => _selectCategory(category),
                    selectedColor: _kAccent.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: category == _category ? _kAccent : Colors.black87,
                      fontWeight: category == _category
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    side: BorderSide(
                      color: category == _category ? _kAccent : Colors.black12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _sectionLabel('이모지'),
            if (emojiPool.isEmpty)
              const Text(
                '이 스타일에는 이모지가 붙지 않아요',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('이모지 없음'),
                    selected: _emojiRemoved,
                    onSelected: (_) => setState(() {
                      _emojiRemoved = true;
                      _emoji = null;
                    }),
                    selectedColor: _kAccent.withValues(alpha: 0.15),
                  ),
                  for (final emoji in emojiPool)
                    ChoiceChip(
                      label: Text(emoji, style: const TextStyle(fontSize: 16)),
                      selected: !_emojiRemoved && _emoji == emoji,
                      onSelected: (_) => setState(() {
                        _emoji = emoji;
                        _emojiRemoved = false;
                      }),
                      selectedColor: _kAccent.withValues(alpha: 0.15),
                    ),
                ],
              ),
            const SizedBox(height: 22),
            TextButton.icon(
              onPressed: _resetToAuto,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('자동으로 되돌리기'),
              style: TextButton.styleFrom(foregroundColor: Colors.black54),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '적용',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
