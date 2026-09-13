import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────
// 플레이스 등록(단독) 화면 맨 위의 안내 — "여기에 무엇을 올릴 수 있나".
//
// 두 공간 유형(매장·즐길거리 / 공간대여·숙박)의 폼이 서로 다른 화면이라,
// 안내를 각 화면에 따로 쓰면 한쪽만 고쳐져 문구가 갈라진다. 그래서 이
// 위젯 하나를 두 화면이 함께 쓴다.
//
// 안내 UI 전용이다. 저장 스키마·필드와는 아무 관계가 없다.
// ─────────────────────────────────────────────────────────────────────────

/// 플레이스 등록 화면 상단 안내 박스.
class PlaceScopeNotice extends StatelessWidget {
  const PlaceScopeNotice({super.key});

  static const Color _bg = Color(0xFFFFF3F8);
  static const Color _border = Color(0xFFFFD9E7);
  static const Color _text = Color(0xFF8A5A72);
  static const Color _accent = Color(0xFFE75B93);

  /// 안내 본문 — 테스트가 이 목록을 그대로 확인한다(문구가 조용히 갈라지지
  /// 않게, 화면이 아니라 여기 한 곳만 정본이다).
  static const List<({String emoji, String text})> lines = [
    (
      emoji: '🏪',
      text: '음식점·카페·술집부터 클럽·라이브·놀거리·체험/클래스, 공간대여·숙박까지 '
          '다양한 플레이스를 등록할 수 있어요.',
    ),
    (
      emoji: '🔗',
      text: '플레이스만 먼저 등록할 수 있어요. 등록 후 파티·이벤트가 생기면 언제든 '
          '이 플레이스에 연결할 수 있어요.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📍 플레이스는 "내 공간"을 올리는 곳이에요',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: _accent,
            ),
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.emoji,
                    style: const TextStyle(fontSize: 12.5, height: 1.5),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      line.text,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: _text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
