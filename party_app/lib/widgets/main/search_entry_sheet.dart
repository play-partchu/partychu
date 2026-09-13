import 'package:flutter/material.dart';

import 'package:party_app/widgets/fullscreen_card_feed.dart'
    show feedRoundIconButton;

// ─────────────────────────────────────────────────────────────────────────────
// 공용 검색 진입 — 파티츄/플레이스/장소대여(그리고 그 안의 파티샵·파티크루)가
// **모두 똑같은 검색 UX**를 쓰도록 한 곳에 모아둔 파일. 목록 화면뿐 아니라
// 큰 카드 전체화면 피드의 돋보기([feedSearchEntryButton])도 여기 있다 —
// 앱 안의 검색 입구는 이 파일이 전부다.
//
// 목록 화면 상단에는 돋보기([SearchEntryIconButton]) **하나만** 둔다. 돋보기를
// 누르면 시트가 **하나만** 열리고, 그 안에
//
//   [ 검색어 입력 🔍 ]
//   지역 / 날짜 / 업종·장소 유형 / 가격 …   ← 그 탭의 상세검색 항목 그대로
//   [ 검색 ]
//
// 이 한 화면에 다 들어 있다. 예전처럼 "상세검색 >" 버튼으로 시트를 한 번 더
// 띄우지 않는다(팝업 위에 팝업이 쌓여 뒤로가기가 두 번 필요했다).
//
// 그래서 이 파일에는 검색 **입구**만 남는다 — 검색어 입력창([SearchEntryField])과
// 그 값을 담는 설정([SearchEntryConfig]). 조건 UI와 필터 로직은 탭마다 예전부터
// 쓰던 상세검색 시트(DetailSearchSheet / EventDetailSearchSheet /
// PlaceDetailSearchSheet / ShopDetailSearchSheet / CrewDetailSearchSheet)가
// 그대로 갖고 있고, 그 시트들이 이 입력창을 자기 머리에 얹어 통째로 검색
// 시트가 된다. 검색어 상태도 호출부가 이미 쓰던 컨트롤러 그대로다.
// ─────────────────────────────────────────────────────────────────────────────

const Color _kPink = Color(0xFFFF6FA0);

/// 목록 헤더 오른쪽 끝의 돋보기 버튼 — 네 탭이 같은 위젯을 공유한다.
///
/// 크기·색·터치 영역이 한 곳에만 있어서 한 탭만 따로 달라 보일 수가 없다
/// (예전 파티 탭 전용 `_PartyListHeaderIconButton`을 그대로 옮겨온 것).
class SearchEntryIconButton extends StatelessWidget {
  final VoidCallback onTap;

  /// 검색어나 상세검색 조건이 하나라도 걸려 있으면 아이콘 오른쪽 위에 점을
  /// 찍어 "지금 걸러진 목록"임을 알린다 — 상세검색 아이콘이 사라진 뒤에도
  /// 조건이 걸려 있는지 한눈에 보이게 하기 위함이다.
  final bool active;

  final String tooltip;

  const SearchEntryIconButton({
    super.key,
    required this.onTap,
    this.active = false,
    this.tooltip = '검색',
  });

  @override
  Widget build(BuildContext context) {
    // 큰 원형 흰 배경/테두리 없이 아이콘만 보이는 단순한 버튼 — 아이콘 자체는
    // 20px로 다른 헤더 요소들과 비율이 맞는 작은 크기를 쓰고, 터치 영역만
    // 40px로 확보한다(배경 없는 기본 핑크 아이콘 스타일 유지).
    //
    // [MaterialTapTargetSize.shrinkWrap]이 없으면 아래 constraints가 40이어도
    // 실제로는 **48**로 그려진다 — IconButton이 테마 기본값
    // (MaterialTapTargetSize.padded, 48×48)을 constraints 위에 한 번 더
    // 얹기 때문이다. 그 8px은 눈에 보이지 않으면서 이 버튼이 들어가는 줄의
    // 높이만 48로 밀어올려, 같은 줄의 낮은 요소(제목 글씨 20)가 세로 중앙에서
    // 어긋나 보이는 원인이 됐다. 여기서 선언한 40이 곧 그려지는 40이 되게 한다.
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.search_rounded, size: 20, color: _kPink),
          if (active)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: _kPink,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 큰 카드 전체화면 피드 위에 얹는 돋보기 — 목록 헤더의
/// [SearchEntryIconButton]과 **여는 것도 동작도 완전히 같고**, 검은 몰입
/// 화면에서도 보이도록 겉모습만 피드 공용 원형 버튼을 쓴다.
///
/// 파티 영상 전체화면과 플레이스/장소대여 전체화면이 이 하나를 함께 쓰므로,
/// 두 화면의 버튼이 서로 달라질 수 없다(예전에는 각자 튠 아이콘 + 분홍 점
/// Stack을 따로 갖고 있었다).
Widget feedSearchEntryButton({
  required VoidCallback onTap,
  required bool active,
}) {
  return Stack(
    clipBehavior: Clip.none,
    children: [
      feedRoundIconButton(Icons.search_rounded, onTap),
      if (active)
        Positioned(
          top: 2,
          right: 2,
          child: Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: _kPink,
              shape: BoxShape.circle,
            ),
          ),
        ),
    ],
  );
}

/// 돋보기로 열리는 검색 시트의 "검색어" 쪽 설정 — 탭마다 다른 값은 이것뿐이다.
///
/// 상세검색 시트에 이 설정을 넘기면 그 시트가 곧 **검색 시트**가 된다
/// (제목이 "플레이스 검색"으로 바뀌고, 조건들 위에 검색어 입력창이 얹히고,
/// 적용 버튼 문구가 "검색"이 된다). 넘기지 않으면 예전 그대로의 상세검색
/// 시트다 — 지도 화면과 태블릿 좌측 필터 패널이 그렇게 쓴다.
class SearchEntryConfig {
  /// 시트 제목("파티 검색" / "플레이스 검색" / "장소대여 검색" …).
  final String title;

  final String hintText;

  /// 호출부가 이미 들고 있는 검색어 컨트롤러 — 시트가 새로 만들지 않는다.
  /// 그래서 시트를 닫았다 다시 열어도 직전 검색어가 그대로 남아 있다.
  final TextEditingController controller;

  /// 한 글자 칠 때마다 호출 — 호출부는 자기 검색어 상태만 갱신하면 목록이
  /// 곧바로 다시 걸러진다(파티 탭이 예전부터 쓰던 방식 그대로). 그래서 아래
  /// 상세조건을 "적용"하기 전에도 검색어는 이미 반영돼 있고, 둘을 같이 걸어도
  /// 서로를 지우지 않는다.
  final ValueChanged<String> onQueryChanged;

  const SearchEntryConfig({
    required this.title,
    required this.hintText,
    required this.controller,
    required this.onQueryChanged,
  });

  /// 검색어를 지우고 목록에 걸린 검색어 조건까지 **즉시** 푼다 — 입력창의
  /// 지우기(x)와 "전체 초기화"가 함께 쓰는 하나의 길이다. 검색어 상태는
  /// 호출부의 컨트롤러와 [onQueryChanged] 그대로이고, 여기서 따로 들고 있는
  /// 것은 없다.
  void clearQuery() {
    controller.clear();
    onQueryChanged('');
  }
}

/// 검색 시트 맨 위의 검색어 입력창 — 다섯 개 상세검색 시트가 이 **하나**를
/// 머리에 얹는다(탭마다 입력창이 달라질 수 없다).
class SearchEntryField extends StatefulWidget {
  final SearchEntryConfig config;

  const SearchEntryField({super.key, required this.config});

  @override
  State<SearchEntryField> createState() => _SearchEntryFieldState();
}

class _SearchEntryFieldState extends State<SearchEntryField> {
  @override
  void initState() {
    super.initState();
    widget.config.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(SearchEntryField old) {
    super.didUpdateWidget(old);
    if (old.config.controller != widget.config.controller) {
      old.config.controller.removeListener(_onControllerChanged);
      widget.config.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    // 컨트롤러 자체는 호출부의 것이라 여기서 버리지 않는다.
    widget.config.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// 지우기(x) 버튼이 나타나고 사라지도록 다시 그린다. 직접 친 경우뿐 아니라
  /// **"전체 초기화"처럼 밖에서 컨트롤러를 비운 경우**에도 버튼이 함께
  /// 사라져야 해서, onChanged가 아니라 컨트롤러를 직접 듣는다.
  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  String get _query => widget.config.controller.text.trim();

  @override
  Widget build(BuildContext context) {
    return Container(
      // 위아래 4 → 2. 높이는 아래 contentPadding이 정하고, 여기서는
      // 그림자와 둥근 모서리만 남긴다.
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1AFF6FA0),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: widget.config.controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: (value) => widget.config.onQueryChanged(value.trim()),
        // 키보드의 "검색"은 조건까지 함께 볼 수 있게 키보드만 내린다 —
        // 시트를 닫는 것은 아래 "검색" 버튼 하나로 통일한다.
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        decoration: InputDecoration(
          icon: const Icon(Icons.search, color: _kPink),
          hintText: widget.config.hintText,
          border: InputBorder.none,
          // 테두리 없는 입력칸의 기본 위아래 여백은 16씩이라 칸 하나가
          // 60px 가까이 된다. 12로 줄여도 글자 크기 그대로 **48px 안팎**이
          // 남아 터치 영역은 충분하다(권장 최소 48).
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(
                    Icons.clear,
                    size: 18,
                    color: Colors.black38,
                  ),
                  // 검색어만 따로 지우는 길 — "전체 초기화"와 같은
                  // clearQuery를 쓰되 상세조건은 건드리지 않는다.
                  onPressed: widget.config.clearQuery,
                ),
        ),
      ),
    );
  }
}
