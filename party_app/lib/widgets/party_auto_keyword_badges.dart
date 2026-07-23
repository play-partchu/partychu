import 'package:flutter/material.dart';
import 'package:party_app/widgets/party_detail_theme.dart';

/// "간편 자동 꾸미기" · "화려하게" 전용 — 소개글 원문에서 규칙 기반으로
/// 추출한 핵심 키워드(`extractAutoDescriptionKeywords`)를 상단에 알약
/// 배지로 보여준다. AI가 지어낸 문구가 아니라 원문에 이미 있는 단어만
/// 그대로 옮겨 보여주는 것 — 이 위젯 자체는 추출 로직을 모르고 이미
/// 계산된 목록만 그린다. 목록이 비어있으면 아무것도 그리지 않는다(키워드를
/// 지어내지 않는다).
class PartyAutoKeywordBadges extends StatelessWidget {
  final List<({String emoji, String label})> keywords;
  final PartyDetailThemeData palette;

  const PartyAutoKeywordBadges({
    super.key,
    required this.keywords,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    if (keywords.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final k in keywords)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: palette.iconBackground,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(k.emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                Text(
                  k.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.primary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
