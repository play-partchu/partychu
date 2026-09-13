import 'package:flutter/material.dart';

/// 태블릿/데스크톱 전용 상단 바 — 모바일은 기존 헤더 이미지 + TabBar를 그대로
/// 쓰므로 이 위젯을 사용하지 않는다(모바일 동작에 영향 없음).
/// 로고 / 카테고리 전환 / 검색창 / 지도 / 로그인·마이페이지 / 등록하기 버튼을 한 줄에 배치.
///
/// 좌측(로고·카테고리·검색창)만 가로 스크롤로 빠지고, 우측 액션
/// (지도·로그인/마이페이지·등록하기)은 스크롤 밖에 고정한다. 예전에는 줄
/// 전체를 스크롤로 감쌌는데, 그러면 폭이 좁은 태블릿(720dp)에서 줄 끝의
/// 버튼이 화면 밖으로 밀려 **가로로 스크롤해야만 보이는 메뉴**가 된다
/// (지도를 더하니 등록하기가 통째로 화면 밖으로 나갔다). 검색창을 Expanded로
/// 늘리지 않고 고정 폭으로 두는 것은 그대로 — 스크롤되는 쪽에 들어 있어서
/// Expanded를 쓸 수 없다.
class MainTopBar extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool isLoggedIn;
  final VoidCallback onLoginOrMyPageTap;
  final VoidCallback onRegisterTap;

  /// 지도 진입 — 모바일 하단 네비의 '지도' 칸과 **같은 핸들러**를 받는다.
  /// 넓은 화면에는 하단 네비가 없어 지도로 들어갈 입구가 통째로 없었다.
  final VoidCallback onMapTap;

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
    required this.onMapTap,
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
            // 폭을 좁힌다. 그래도 안 맞으면 좌측(로고·탭·검색)만 가로 스크롤로
            // 빠지고, 우측 액션은 항상 제자리에 보인다.
            final compact = constraints.maxWidth < 1000;
            final searchWidth = compact ? 180.0 : 320.0;
            final tabGap = compact ? 12.0 : 32.0;

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 24,
                vertical: 14,
              ),
              child: Row(
                children: [
                  // ── 좌측: 로고 / 카테고리 / 검색창 (넘치면 가로 스크롤) ──
                  Expanded(
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
                                  foregroundColor: selected
                                      ? const Color(0xFFFF6FA0)
                                      : Colors.black54,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: compact ? 8 : 16,
                                    vertical: 8,
                                  ),
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
                                        fontWeight: selected
                                            ? FontWeight.w800
                                            : FontWeight.w500,
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
                                icon: Icon(
                                  Icons.search,
                                  size: 18,
                                  color: Colors.black45,
                                ),
                                hintText: '검색',
                                hintStyle: TextStyle(fontSize: 13),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ── 우측 액션 — 스크롤 밖에 고정해 항상 보인다 ──
                  SizedBox(width: compact ? 8 : 16),
                  // 지도 — 모바일 하단 네비의 '지도' 칸과 같은 화면(MapScreen)으로
                  // 같은 핸들러를 통해 들어간다. 넓은 화면에는 하단 네비가 없어
                  // 여기가 유일한 지도 입구다.
                  TextButton.icon(
                    onPressed: onMapTap,
                    icon: const Icon(
                      Icons.map_outlined,
                      size: 18,
                      color: Color(0xFFFF6FA0),
                    ),
                    label: const Text(
                      '지도',
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 6 : 12,
                      ),
                    ),
                  ),
                  SizedBox(width: compact ? 4 : 8),
                  TextButton(
                    onPressed: onLoginOrMyPageTap,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 6 : 12,
                      ),
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
                        horizontal: compact ? 12 : 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
