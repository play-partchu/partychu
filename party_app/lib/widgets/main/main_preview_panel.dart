import 'package:flutter/material.dart';

/// 데스크톱 3단 레이아웃 우측 패널에 보여줄 선택 항목.
/// [card]는 main_screen.dart가 이미 가진 카드 렌더링 메서드
/// (_buildPartyCard/_shopCard/_placeGridCard)로 만든 위젯을 그대로 넘겨받는다 —
/// 엔티티별 필드 구조를 이 위젯이 다시 알 필요가 없도록(중복 제거) 하기 위함이다.
class MainPreviewItem {
  final String type; // 'party' | 'place' | 'shop'
  final Widget card;
  final VoidCallback onOpenDetail;

  const MainPreviewItem({
    required this.type,
    required this.card,
    required this.onOpenDetail,
  });
}

/// 데스크톱 전용 우측 "미리보기" 패널 — 아직 지도는 넣지 않고, 선택된 카드의
/// 미리보기 + 상세보기 버튼 중심으로 구성한다.
class MainPreviewPanel extends StatelessWidget {
  final MainPreviewItem? item;

  const MainPreviewPanel({super.key, this.item});

  @override
  Widget build(BuildContext context) {
    final current = item;
    return Container(
      color: Colors.white,
      child: current == null ? _buildEmpty() : _buildContent(current),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app_outlined, size: 40, color: Colors.black26),
            SizedBox(height: 12),
            Text(
              '카드를 선택하면\n상세 미리보기가 여기 표시됩니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black45, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(MainPreviewItem current) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '미리보기',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // 카드 자체의 onTap(있다면)까지 눌리지 않도록 흡수 — 이 패널에서는
            // 오직 아래 "상세보기" 버튼으로만 상세화면으로 이동한다.
            child: IgnorePointer(child: current.card),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: current.onOpenDetail,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6FA0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('상세보기', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }
}
