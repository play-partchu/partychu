import 'package:flutter/material.dart';

import 'package:party_app/models/custom_amenity.dart';

/// 상세 화면에 **기타 편의 서비스 항목명을 그대로** 보여주는 줄.
///
/// '기타'라는 한 단어로 접지 않는다 — 그 단어는 게스트에게 아무것도 알려주지
/// 않고, 호스트가 굳이 적어 넣은 값을 지워 버린다. 등록한 말("루프탑",
/// "보드게임 대여")이 그대로 보여야 그 값을 적을 이유도 생긴다.
///
/// 항목이 없으면 **아무것도 그리지 않는다**(`SizedBox.shrink`) — 기존 문서의
/// 상세 화면에는 줄이 하나도 늘지 않는다.
class CustomAmenityView extends StatelessWidget {
  /// 플레이스/장소대여 문서.
  final Map<String, dynamic> data;

  /// 칩 강조색 — 화면마다 쓰는 포인트 색이 달라 호출부가 정한다.
  final Color accent;

  /// 제목을 함께 그릴지. 이미 제목이 있는 묶음 안에 넣을 때는 false.
  final bool showTitle;

  const CustomAmenityView({
    super.key,
    required this.data,
    required this.accent,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final items = CustomAmenities.of(data);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          const Text(
            '✨ 기타 편의 서비스',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final item in items)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Text(
                  item,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 목록 카드에 붙는 **한 줄 요약** — 항목명을 앞에서부터 몇 개만 보여준다.
///
/// 카드에는 자리가 없으므로 [max]개까지만 적고 나머지는 `+N`으로 접는다.
/// 여기서도 '기타' 한 단어로 뭉개지 않는 것이 핵심이다.
class CustomAmenitySummary extends StatelessWidget {
  final Map<String, dynamic> data;
  final int max;
  final TextStyle? style;

  const CustomAmenitySummary({
    super.key,
    required this.data,
    this.max = 3,
    this.style,
  });

  /// 카드 한 줄에 적을 문자열. 항목이 없으면 null.
  static String? summaryOf(Map<String, dynamic> data, {int max = 3}) {
    final items = CustomAmenities.of(data);
    if (items.isEmpty) return null;
    final shown = items.take(max).join(' · ');
    final rest = items.length - max;
    return rest > 0 ? '$shown +$rest' : shown;
  }

  @override
  Widget build(BuildContext context) {
    final text = summaryOf(data, max: max);
    if (text == null) return const SizedBox.shrink();
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style:
          style ??
          const TextStyle(fontSize: 11, color: Colors.black54, height: 1.3),
    );
  }
}
