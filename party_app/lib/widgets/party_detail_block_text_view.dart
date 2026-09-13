import 'package:flutter/material.dart';
import 'package:party_app/models/party_detail_block.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/widgets/party_detail_theme.dart';

/// "글만 보기" 모드 렌더러 — `detailBlocks`를 그대로 재사용하되 사진은
/// 숨기고 텍스트 중심 정보만 읽기 편하게 재구성한다. 호스트가 별도로
/// 글을 다시 입력할 필요가 없도록 데이터 원본(순서 포함)은 그대로 두고
/// 스타일/구성만 다르게 그린다.
///
/// 디자인 보기([PartyDetailBlockPreview])와 달리 [theme]의 영향을
/// 최소화한다 — 배경/본문 색상은 항상 고정된 밝은 팔레트를 쓰고, 소제목
/// 색상과 구분선 색조 두 곳에만 [theme]의 포인트 컬러를 살짝 반영한다.
/// 프리미엄 다크·클럽 네온을 고르더라도 이 화면만은 항상 흰 배경 +
/// 진한 본문 색으로 대비를 확보해 읽기 편의성을 지킨다.
///
/// [PartyDetailBlockPreview]와 마찬가지로 스스로 스크롤하지 않는 고정
/// 크기 위젯이며, 블록 하나의 렌더링이 실패해도 그 블록만 조용히 생략한다.
class PartyDetailBlockTextView extends StatelessWidget {
  final List<PartyDetailBlock> blocks;
  final PartyDetailThemeKey theme;

  /// 에러 로그 식별용(선택).
  final String? partyId;

  const PartyDetailBlockTextView({
    super.key,
    required this.blocks,
    this.theme = PartyDetailThemeKey.partychu,
    this.partyId,
  });

  @override
  Widget build(BuildContext context) {
    final accent = PartyDetailThemeRegistry.fromKey(theme).primary;
    final rendered = <Widget>[];
    for (final block in blocks) {
      Widget? widget;
      try {
        widget = _buildBlock(block, accent);
      } catch (e, st) {
        debugPrint(
          '[PartyDetailBlockTextView]\n'
          'partyId: ${partyId ?? '(none)'}\n'
          'detailTheme: ${theme.name}\n'
          'blockId: ${block.id}\n'
          'type: ${block.type}\n'
          'error: $e\n'
          'stack: $st',
        );
        widget = null;
      }
      if (widget != null) rendered.add(widget);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rendered.length; i++) ...[
          rendered[i],
          if (i != rendered.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }

  /// 표시할 내용이 없으면(사진, 빈 텍스트, 모르는 타입 등) null을 돌려줘
  /// 호출부가 그 블록을 조용히 건너뛰게 한다. [accent]는 소제목/구분선
  /// 등 최소한의 지점에만 쓰는 테마 포인트 컬러다.
  Widget? _buildBlock(PartyDetailBlock block, Color accent) {
    switch (block.type) {
      case PartyDetailBlockType.heading:
        final text = block.text?.trim();
        if (text == null || text.isEmpty) return null;
        return SelectableText(
          text,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            height: 1.4,
          ),
        );
      case PartyDetailBlockType.subheading:
        final text = block.text?.trim();
        if (text == null || text.isEmpty) return null;
        return SelectableText(
          text,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: accent,
            height: 1.5,
          ),
        );
      case PartyDetailBlockType.paragraph:
        final text = block.text?.trim();
        if (text == null || text.isEmpty) return null;
        return SelectableText(
          text,
          style: const TextStyle(
            fontSize: 15,
            height: 1.8,
            color: Colors.black87,
          ),
        );
      case PartyDetailBlockType.notice:
        final text = block.text?.trim();
        if (text == null || text.isEmpty) return null;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3F7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.7,
              color: Color(0xFFB23A63),
            ),
          ),
        );
      case PartyDetailBlockType.divider:
        // 사진이 빠지면 디자인 보기의 굵은 구분선보다 더 옅은 여백 성격의
        // 구분선이 문단 사이 리듬을 자연스럽게 만든다 — 테마 포인트 컬러를
        // 옅게 탄 색조만 반영한다(고정 회색 대신).
        return Container(height: 1, color: accent.withValues(alpha: 0.25));
      case PartyDetailBlockType.image:
      case PartyDetailBlockType.imageGroup:
        // 글만 보기에서는 사진(콜라주 포함) 블록을 표시하지 않는다.
        return null;
      case PartyDetailBlockType.checklist:
        return _buildChecklist(block);
      case PartyDetailBlockType.faq:
        return _buildFaq(block);
      case PartyDetailBlockType.timeline:
        return _buildTimeline(block, accent);
      case PartyDetailBlockType.infoCard:
        return _buildInfoCard(block);
      case PartyDetailBlockType.video:
        // 동영상 자체는 숨기고, 캡션이 있으면 텍스트만 보여준다.
        final caption = block.video?.caption?.trim();
        if (caption == null || caption.isEmpty) return null;
        return SelectableText(
          caption,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black45,
            fontStyle: FontStyle.italic,
          ),
        );
      case PartyDetailBlockType.unknown:
        return null;
    }
  }

  Widget? _buildChecklist(PartyDetailBlock block) {
    final payload = block.checklist;
    if (payload == null || payload.items.isEmpty) return null;
    final title = payload.title?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null && title.isNotEmpty) ...[
          SelectableText(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
        ],
        for (final item in payload.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SelectableText(
              '✓ $item',
              style: const TextStyle(
                fontSize: 15,
                height: 1.6,
                color: Colors.black87,
              ),
            ),
          ),
      ],
    );
  }

  Widget? _buildFaq(PartyDetailBlock block) {
    final payload = block.faq;
    if (payload == null || payload.items.isEmpty) return null;
    final title = payload.title?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null && title.isNotEmpty) ...[
          SelectableText(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
        ],
        // 글만 보기에서는 디자인 보기의 아코디언과 달리 질문/답변을 모두 펼쳐서 보여준다.
        for (final item in payload.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  'Q. ${item.question}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  'A. ${item.answer}',
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget? _buildTimeline(PartyDetailBlock block, Color accent) {
    final payload = block.timeline;
    if (payload == null || payload.items.isEmpty) return null;
    final title = payload.title?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null && title.isNotEmpty) ...[
          SelectableText(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
        ],
        for (final item in payload.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectableText.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${item.time}  ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  TextSpan(
                    text: item.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  if (item.description.isNotEmpty)
                    TextSpan(
                      text: '\n${item.description}',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget? _buildInfoCard(PartyDetailBlock block) {
    final payload = block.infoCard;
    if (payload == null) return null;
    if (payload.title.trim().isEmpty && payload.text.trim().isEmpty)
      return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (payload.title.isNotEmpty)
          SelectableText(
            payload.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        if (payload.title.isNotEmpty && payload.text.isNotEmpty)
          const SizedBox(height: 4),
        if (payload.text.isNotEmpty)
          SelectableText(
            payload.text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Colors.black54,
            ),
          ),
      ],
    );
  }
}
