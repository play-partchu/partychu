import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:party_app/models/party_filter.dart';
import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/utils/party_view_mode.dart';
import 'package:party_app/widgets/detail_search_sheet.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/party_view_mode_sheet.dart';
import 'package:party_app/widgets/partychu_icon_button.dart';

/// 전체화면 영상 피드를 벗어날 때 돌려주는 결과 — 보기 방식을 바꿨는지,
/// 상세검색으로 필터를 바꿨는지 둘 중 하나(또는 둘 다 null)를 담는다.
/// MainScreen은 [filter]가 있으면 그 필터로 목록을 다시 걸러 전체화면을
/// 자동으로 다시 띄우고, [viewMode]가 있으면(그리고 video가 아니면) 목록의
/// 보기 방식을 그 값으로 바꾼다.
class VideoFeedExitResult {
  final PartyViewMode? viewMode;
  final PartyFilter? filter;

  const VideoFeedExitResult({this.viewMode, this.filter});
}

// ─────────────────────────────────────────────────────────────────────────────
// 큰 카드(영상 크게 보기)를 탭했을 때 여는 완전한 전체화면 카드 피드 — 파티
// 목록의 고정 헤더/검색창/"파티 목록" 제목/정렬 버튼은 전혀 보이지 않고,
// 화면 전체를 카드 한 장이 차지한다.
//
// - SystemUiMode.immersiveSticky로 상태바·내비게이션 바까지 숨겨 최대한
//   넓은 공간을 쓰고, 화면을 벗어나면(dispose) 원래 모드로 되돌린다.
// - 세로 PageView로 카드를 넘긴다 — 위로 스와이프하면 다음 카드, 아래로
//   스와이프하면 이전 카드. PageView 기본 동작 그대로라 첫 카드에서 아래로,
//   마지막 카드에서 위로 당겨도 그냥 튕길 뿐 화면이 닫히지 않는다(드래그로
//   닫는 제스처를 별도로 붙이지 않았음).
// - 종료는 좌상단 뒤로가기 버튼 또는 시스템 뒤로가기로만 한다.
// - 우상단 아이콘으로 기존 PartyViewModeSheet를 그대로 띄운다. 작은/기본
//   카드를 고르면 이 화면을 닫으며 그 결과를 호출자(MainScreen)에 돌려줘
//   목록 화면에 바로 반영시킨다. 영상 크게 보기를 다시 고르면 지금 보던
//   카드를 그대로 유지한다.
// - 진입하는 순간 소리를 켠 채로 재생을 시작한다(목록에 섞여 있는 작은
//   미리보기와 달리, 이 화면은 몰입해서 보는 전체화면 뷰이므로). 카드
//   자체(재생/일시정지 토글, 소리 끄기, 상세보기 버튼)는 PartyVideoFeedCard를
//   그대로 재사용하므로 기존 기능이 전부 유지된다. 화면에 보이는 카드만
//   자동재생되는 것도 PartyVideoFeedCard 내부의 가시성 감지 로직이 그대로
//   보장한다.
// ─────────────────────────────────────────────────────────────────────────────

class PartyVideoFeedScreen extends StatefulWidget {
  final List<QueryDocumentSnapshot> docs;
  final int initialIndex;
  // 상세검색 버튼(메인 목록과 동일한 DetailSearchSheet)을 이 화면에서도 바로
  // 열 수 있도록, 진입 시점의 필터/파티 날짜를 그대로 넘겨받는다.
  final PartyFilter filter;
  final Set<DateTime> partyDates;

  const PartyVideoFeedScreen({
    super.key,
    required this.docs,
    required this.initialIndex,
    required this.filter,
    this.partyDates = const {},
  });

  @override
  State<PartyVideoFeedScreen> createState() => _PartyVideoFeedScreenState();
}

class _PartyVideoFeedScreenState extends State<PartyVideoFeedScreen> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    // 상태바/내비게이션 바까지 숨겨 카드 한 장이 화면 전체를 쓰게 한다.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // 목록에 섞인 작은 미리보기와 달리 이 화면은 몰입해서 보는 전체화면
    // 뷰라 소리를 켠 채로 시작한다(사용자가 다시 끄면 그 선택은 존중된다).
    FeedVideoManager.instance.setMuted(false);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _showViewModeSheet() async {
    final selected = await showModalBottomSheet<PartyViewMode>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const PartyViewModeSheet(current: PartyViewMode.video),
    );
    if (selected == null || !mounted) return;
    await selected.save();
    if (!mounted) return;
    // 작은/기본 카드를 고르면 전체화면을 닫고 그 모드를 목록 화면에 전달한다.
    // 영상 크게 보기를 다시 고른 경우엔 지금 보던 카드를 그대로 유지한다.
    if (selected != PartyViewMode.video) {
      Navigator.pop(context, VideoFeedExitResult(viewMode: selected));
    }
  }

  // 메인 목록의 "상세검색"과 동일한 바텀시트 — 새 필터를 고르면 전체화면을
  // 닫고 그 필터를 목록 화면에 전달한다. 목록 화면은 필터를 반영해 다시
  // 걸러진 목록으로 전체화면을 즉시 다시 띄운다(_maybeAutoOpenVideoFeed 재사용).
  Future<void> _openDetailSearch() async {
    final result = await showModalBottomSheet<PartyFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DetailSearchSheet(
        initialFilter: widget.filter,
        partyDates: widget.partyDates,
      ),
    );
    if (result == null || !mounted) return;
    Navigator.pop(context, VideoFeedExitResult(filter: result));
  }

  Widget _roundIconButton(
    IconData icon,
    VoidCallback onTap, {
    Color iconColor = Colors.white,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: iconColor, size: 22),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // immersiveSticky에서는 상태바가 숨겨져 topPadding이 0이 될 수 있으므로
    // 최소 여백을 보장한다.
    final topPad = MediaQuery.of(context).padding.top;
    final topInset = (topPad > 0 ? topPad : 8.0) + 8;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: widget.docs.length,
            itemBuilder: (context, index) {
              final doc = widget.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              return PartyVideoFeedCard(
                key: ValueKey(doc.id),
                party: data,
                docId: doc.id,
              );
            },
          ),
          Positioned(
            top: topInset,
            left: 12,
            child: _roundIconButton(
              Icons.arrow_back,
              () => Navigator.pop(context),
            ),
          ),
          // 스피커 on/off — 상세보기 버튼(좌측 하단)과 겹치지 않도록 우측
          // 하단에 둔다. 전역 음소거 상태(FeedVideoManager)를 그대로 보고
          // 누르면 이 화면뿐 아니라 다음에 재생되는 모든 카드에도 이어진다.
          Positioned(
            right: 12,
            bottom:
                (MediaQuery.of(context).padding.bottom > 0
                    ? MediaQuery.of(context).padding.bottom
                    : 8.0) +
                8,
            child: const MuteToggleIconButton(size: 25),
          ),
          Positioned(
            top: topInset,
            right: 12,
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _roundIconButton(Icons.tune, _openDetailSearch),
                    if (widget.filter.isActive)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF6FA0),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                _roundIconButton(
                  partyViewModeIcon(PartyViewMode.video),
                  _showViewModeSheet,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
