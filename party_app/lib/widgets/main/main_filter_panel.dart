import 'package:flutter/material.dart';

/// 태블릿/데스크톱 좌측 필터 패널 — 모바일에는 없는 화면이라 새로 만든 UI다.
/// [quickFilters]는 main_screen.dart가 탭별로 이미 갖고 있는 필터 위젯
/// (카테고리 칩/지역 선택 등)을 그대로 넘겨받는 슬롯 — 여기서 필터 로직을
/// 다시 구현하지 않고 기존 상태/로직을 100% 재사용하기 위함이다.
class MainFilterPanel extends StatelessWidget {
  final String title;
  final Widget? quickFilters;
  // null이면 "상세 검색" 버튼 자체를 숨긴다(예: 플레이스 탭처럼 별도 상세검색
  // 시트가 없고 quickFilters의 카테고리 칩만으로 필터링하는 경우).
  final VoidCallback? onOpenDetailSearch;
  final bool detailFilterActive;

  const MainFilterPanel({
    super.key,
    required this.title,
    this.quickFilters,
    this.onOpenDetailSearch,
    this.detailFilterActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (quickFilters != null) ...[
              quickFilters!,
              const SizedBox(height: 16),
            ],
            if (onOpenDetailSearch != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onOpenDetailSearch,
                  icon: Icon(
                    Icons.tune,
                    size: 18,
                    color: detailFilterActive
                        ? Colors.white
                        : const Color(0xFFFF6FA0),
                  ),
                  label: Text(
                    '상세 검색',
                    style: TextStyle(
                      color: detailFilterActive
                          ? Colors.white
                          : const Color(0xFFFF6FA0),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: detailFilterActive
                        ? const Color(0xFFFF6FA0)
                        : Colors.white,
                    side: const BorderSide(color: Color(0xFFFF6FA0)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
