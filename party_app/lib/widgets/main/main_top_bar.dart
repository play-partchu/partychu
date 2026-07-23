import 'package:flutter/material.dart';

/// 태블릿/데스크톱 전용 상단 바 — 모바일은 기존 헤더 이미지 + TabBar를 그대로
/// 쓰므로 이 위젯을 사용하지 않는다(모바일 동작에 영향 없음).
/// 로고 / 카테고리 전환 / 검색창 / 로그인·마이페이지 / 등록하기 버튼을 한 줄에 배치.
///
/// 검색창을 Expanded로 늘리지 않고 고정 폭으로 둔 이유: 이 Row 전체를
/// 가로 SingleChildScrollView로 감싸 태블릿처럼 좁은 폭에서도 절대
/// overflow 에러 없이 스크롤로 빠지게 하기 위함(Expanded는 스크롤 가능한
/// 무한폭 부모와 함께 쓸 수 없다).
class MainTopBar extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool isLoggedIn;
  final VoidCallback onLoginOrMyPageTap;
  final VoidCallback onRegisterTap;

  const MainTopBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.searchController,
    required this.onSearchChanged,
    required this.isLoggedIn,
    required this.onLoginOrMyPageTap,
    required this.onRegisterTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 태블릿 폭(~700~1000)에서도 한 줄에 다 들어오도록 간격/검색창
            // 폭을 좁힌다. 그래도 안 맞는 극단적인 경우엔 가로 스크롤로 빠진다.
            final compact = constraints.maxWidth < 1000;
            final searchWidth = compact ? 180.0 : 320.0;
            final tabGap = compact ? 12.0 : 32.0;

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 24, vertical: 14),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text(
                      '파티츄',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFFF6FA0),
                      ),
                    ),
                    SizedBox(width: tabGap),
                    ...List.generate(tabs.length, (i) {
                      final selected = i == selectedIndex;
                      return Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: TextButton(
                          onPressed: () => onTabSelected(i),
                          style: TextButton.styleFrom(
                            foregroundColor:
                                selected ? const Color(0xFFFF6FA0) : Colors.black54,
                            padding: EdgeInsets.symmetric(
                                horizontal: compact ? 8 : 16, vertical: 8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 첫 탭("파티츄")만 검정 발자국 이모지 대신
                              // 파스텔 핑크 고양이 발바닥 아이콘을 고정
                              // 색으로 그린다(선택 상태와 무관하게 동일 톤).
                              if (i == 0) ...[
                                const Icon(
                                  Icons.pets,
                                  size: 14,
                                  color: Color(0xFFFFACD2),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                tabs[i],
                                style: TextStyle(
                                  fontSize: compact ? 13 : 15,
                                  fontWeight:
                                      selected ? FontWeight.w800 : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    SizedBox(width: compact ? 8 : 16),
                    Container(
                      width: searchWidth,
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F7FA),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: searchController,
                        onChanged: onSearchChanged,
                        decoration: const InputDecoration(
                          icon: Icon(Icons.search, size: 18, color: Colors.black45),
                          hintText: '검색',
                          hintStyle: TextStyle(fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    SizedBox(width: compact ? 8 : 16),
                    TextButton(
                      onPressed: onLoginOrMyPageTap,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12),
                      ),
                      child: Text(
                        isLoggedIn ? '마이페이지' : '로그인',
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: onRegisterTap,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('등록하기'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6FA0),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                            horizontal: compact ? 12 : 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
