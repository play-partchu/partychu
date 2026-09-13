import 'package:flutter/material.dart';
import 'package:party_app/models/party_constants.dart';
import 'package:party_app/models/party_detail_block.dart';
import 'package:party_app/models/party_detail_decoration_intensity.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/utils/auto_description_classifier.dart';
import 'package:party_app/widgets/party_auto_keyword_badges.dart';
import 'package:party_app/widgets/party_detail_block_preview.dart';
import 'package:party_app/widgets/party_detail_theme.dart';
import 'package:party_app/widgets/party_form/decoration_intensity_picker.dart';
import 'package:party_app/widgets/party_form/paragraph_style_edit_sheet.dart';
import 'package:party_app/widgets/party_form/party_detail_theme_picker.dart';
import 'package:party_app/widgets/web_frame.dart';

const _kAccent = Color(0xFFFF6FA0);

/// "간편 자동 꾸미기"에서 고를 수 있는 테마 — 요청대로 전체 5종이 아니라
/// 3종만 노출한다(직접 만들기 쪽 블록 에디터는 여전히 5종 전부 제공).
final _kAutoThemes = [
  PartyDetailThemeRegistry.fromKey(PartyDetailThemeKey.partychu),
  PartyDetailThemeRegistry.fromKey(PartyDetailThemeKey.lovely),
  PartyDetailThemeRegistry.fromKey(PartyDetailThemeKey.premiumDark),
];

/// 미리보기 화면이 pop으로 돌려주는 값 — "다시 꾸미기"로 바뀐 변형 시드와,
/// 문단별 탭 편집으로 저장된 스타일/이모지 오버라이드 목록을 함께 담는다.
typedef PartyIntroPreviewResult = (
  int variantSeed,
  List<Map<String, dynamic>> paragraphStyles,
);

class PartyIntroSelection {
  final String intro;
  final List<String> tags;
  final PartyDetailThemeKey theme;
  final PartyDetailDecorationIntensity intensity;
  final int variantSeed;
  final List<Map<String, dynamic>> paragraphStyles;

  const PartyIntroSelection({
    required this.intro,
    required this.tags,
    required this.theme,
    required this.intensity,
    required this.variantSeed,
    this.paragraphStyles = const [],
  });
}

/// "상세 소개" 행 — 파티 소개 텍스트 + 태그 입력/칩 + "간편 자동 꾸미기"용
/// 테마/강도 선택. 등록/수정 화면이 "상세 설명 방식" 선택 시트에서 "간편
/// 자동 꾸미기"를 고른 경우에만 이 화면으로 진입한다(직접 상세페이지
/// 만들기는 기존 `PartyDetailBlockEditorScreen`을 그대로 쓴다).
///
/// 여기서 고른 테마/강도는 새 렌더러를 만들지 않고, 소개글 원문을
/// `classifyDescriptionToBlocks`로 자동 분석해 기존 `PartyDetailBlockPreview`
/// (블록형 상세페이지가 쓰는 바로 그 위젯)에 넘겨 미리보기/실제 렌더링
/// 모두에 재사용한다.
class PartyIntroScreen extends StatefulWidget {
  final String initialIntro;
  final List<String> initialTags;
  final PartyDetailThemeKey initialTheme;
  final PartyDetailDecorationIntensity initialIntensity;
  final int initialVariantSeed;
  final List<Map<String, dynamic>> initialParagraphStyles;

  const PartyIntroScreen({
    super.key,
    required this.initialIntro,
    required this.initialTags,
    this.initialTheme = PartyDetailThemeKey.partychu,
    this.initialIntensity = PartyDetailDecorationIntensity.standard,
    this.initialVariantSeed = 0,
    this.initialParagraphStyles = const [],
  });

  @override
  State<PartyIntroScreen> createState() => _PartyIntroScreenState();
}

class _PartyIntroScreenState extends State<PartyIntroScreen> {
  late final _introController = TextEditingController(
    text: widget.initialIntro,
  );
  late final _tagController = TextEditingController();
  late final List<String> _tags = [...widget.initialTags];
  late PartyDetailThemeKey _theme = widget.initialTheme;
  late PartyDetailDecorationIntensity _intensity = widget.initialIntensity;
  late int _variantSeed = widget.initialVariantSeed;
  late List<Map<String, dynamic>> _paragraphStyles = [
    ...widget.initialParagraphStyles,
  ];

  @override
  void dispose() {
    _introController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _showMessage(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _addTag() {
    if (_tags.length >= PartyConstants.maxTags) {
      _showMessage('태그는 최대 ${PartyConstants.maxTags}개까지 추가할 수 있어요');
      return;
    }
    var value = _tagController.text.trim();
    if (value.isEmpty) return;
    if (value.startsWith('#')) value = value.substring(1);
    if (value.isEmpty) return;
    if (!_tags.contains(value)) setState(() => _tags.add(value));
    _tagController.clear();
  }

  Future<void> _openPreview() async {
    final intro = _introController.text.trim();
    if (intro.isEmpty) {
      _showMessage('소개글을 먼저 입력해주세요');
      return;
    }
    final result = await Navigator.push<PartyIntroPreviewResult>(
      context,
      webFramedRoute(
        (_) => _AutoDescriptionPreviewScreen(
          intro: intro,
          theme: _theme,
          intensity: _intensity,
          initialVariantSeed: _variantSeed,
          initialParagraphStyles: _paragraphStyles,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _variantSeed = result.$1;
      _paragraphStyles = result.$2;
    });
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF7F7FA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );

  void _confirm() {
    Navigator.pop(
      context,
      PartyIntroSelection(
        intro: _introController.text,
        tags: _tags,
        theme: _theme,
        intensity: _intensity,
        variantSeed: _variantSeed,
        paragraphStyles: _paragraphStyles,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '간편 자동 꾸미기',
          style: TextStyle(
            fontFamily: 'SeoulHangang',
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListView(
                children: [
                  _label('파티 소개'),
                  TextField(
                    controller: _introController,
                    maxLines: 6,
                    decoration: _inputDecoration('파티 분위기, 준비물, 주의사항 등을 적어줘'),
                  ),
                  const SizedBox(height: 22),
                  _label('꾸미기 테마'),
                  PartyDetailThemePicker(
                    selected: _theme,
                    onChanged: (key) => setState(() => _theme = key),
                    themes: _kAutoThemes,
                  ),
                  const SizedBox(height: 16),
                  _label('꾸미기 정도'),
                  DecorationIntensityPicker(
                    selected: _intensity,
                    onChanged: (value) => setState(() => _intensity = value),
                    accentColor: _kAccent,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _openPreview,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('미리보기'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kAccent,
                      side: const BorderSide(color: _kAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _label(
                    '파티 태그 (${_tags.length}/${PartyConstants.maxTags}개 · 자유 입력)',
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagController,
                          decoration: _inputDecoration(
                            '예: 외국인, 20대, 바다 (# 없이 입력)',
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _addTag(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addTag,
                        child: const Text('추가'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _tags
                        .map(
                          (tag) => Chip(
                            label: Text('#$tag'),
                            onDeleted: () => setState(() => _tags.remove(tag)),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  '선택 완료',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "간편 자동 꾸미기" 미리보기 — 소개글 원문을 `classifyDescriptionToBlocks`로
/// 자동 분석해(날짜/장소/가격/주의/마감/배너/리스트/본문 카드) 실제
/// 상세화면과 동일한 렌더러(`PartyDetailBlockPreview`)에 넣는다. 원문
/// 텍스트(`intro`) 자체는 여기서 전혀 가공하지 않는다 — 분류·이모지는
/// 매번 새로 계산되는 렌더링 전용 파생물일 뿐 저장되지 않는다.
///
/// "다시 꾸미기"는 [_variantSeed]만 바꿔 그 자리에서 다시 그린다 — 문단
/// 분류(카테고리)는 원문 내용 기반이라 그대로 유지되고, 이모지·배경 장식·
/// 구분 장식 조합만 바뀐다.
///
/// 문단을 탭하면 `paragraph_style_edit_sheet.dart`가 열려 그 문단만 스타일/
/// 이모지를 직접 고를 수 있다 — 여기서만 `onBlockTap`을 넘긴다(실제
/// 상세페이지에는 절대 넘기지 않는다, `PartyDetailBlockPreview` 참고).
/// 화면을 나갈 때 최종 시드와 오버라이드 목록을 함께 pop으로 돌려준다.
class _AutoDescriptionPreviewScreen extends StatefulWidget {
  final String intro;
  final PartyDetailThemeKey theme;
  final PartyDetailDecorationIntensity intensity;
  final int initialVariantSeed;
  final List<Map<String, dynamic>> initialParagraphStyles;

  const _AutoDescriptionPreviewScreen({
    required this.intro,
    required this.theme,
    required this.intensity,
    required this.initialVariantSeed,
    required this.initialParagraphStyles,
  });

  @override
  State<_AutoDescriptionPreviewScreen> createState() =>
      _AutoDescriptionPreviewScreenState();
}

class _AutoDescriptionPreviewScreenState
    extends State<_AutoDescriptionPreviewScreen> {
  late int _variantSeed = widget.initialVariantSeed;
  late List<Map<String, dynamic>> _paragraphStyles = [
    ...widget.initialParagraphStyles,
  ];

  void _regenerate() => setState(() => _variantSeed++);

  Future<void> _onBlockTap(PartyDetailBlock block) async {
    final existing = _paragraphStyles.firstWhere(
      (o) => o['key'] == block.id,
      orElse: () => const {},
    );
    var currentCategory = autoDescriptionCategoryForBlock(block);
    final overrideCategoryName = existing['category'];
    if (overrideCategoryName is String) {
      for (final c in AutoDescriptionCategory.values) {
        if (c.name == overrideCategoryName) {
          currentCategory = c;
          break;
        }
      }
    }
    final result = await showParagraphStyleEditSheet(
      context,
      currentCategory: currentCategory,
      currentEmoji: existing['emoji'] as String?,
      emojiRemoved: existing['emojiRemoved'] == true,
    );
    if (result == null || !mounted) return;
    setState(() {
      _paragraphStyles = _paragraphStyles
          .where((o) => o['key'] != block.id)
          .toList();
      if (result['reset'] != true) {
        _paragraphStyles.add({
          'key': block.id,
          'category': result['category'],
          'emoji': result['emoji'],
          'emojiRemoved': result['emojiRemoved'],
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = PartyDetailThemeRegistry.fromKey(widget.theme);
    final isRich = widget.intensity == PartyDetailDecorationIntensity.rich;
    final keywords = isRich
        ? extractAutoDescriptionKeywords(widget.intro)
        : const <({String emoji, String label})>[];
    final blocks = classifyDescriptionToBlocks(
      widget.intro,
      variantSeed: _variantSeed,
      paragraphStyles: _paragraphStyles,
      rich: isRich,
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, (_variantSeed, _paragraphStyles));
      },
      child: Scaffold(
        backgroundColor: palette.pageBackground,
        appBar: AppBar(
          title: const Text(
            '미리보기',
            style: TextStyle(
              fontFamily: 'SeoulHangang',
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
              ],
            ),
          ),
          centerTitle: true,
          actions: [
            TextButton.icon(
              onPressed: _regenerate,
              icon: const Icon(Icons.refresh, color: _kAccent, size: 18),
              label: const Text('다시 꾸미기', style: TextStyle(color: _kAccent)),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '문단을 탭하면 스타일과 이모지를 직접 바꿀 수 있어요',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: _kAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (keywords.isNotEmpty) ...[
                PartyAutoKeywordBadges(keywords: keywords, palette: palette),
                const SizedBox(height: 12),
              ],
              PartyDetailBlockPreview(
                blocks: blocks,
                theme: widget.theme,
                intensity: widget.intensity,
                variantSeed: _variantSeed,
                onBlockTap: _onBlockTap,
                richAutoDecorations: isRich,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
