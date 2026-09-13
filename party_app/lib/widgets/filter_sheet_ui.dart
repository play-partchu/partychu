/// 모든 탭(파티 / 장소대여 / 플레이스)의 **상세검색 바텀시트가 공유하는 부품**.
///
/// 원래는 파티 상세검색([DetailSearchSheet]) 안에만 있던 아코디언·칩·시트 골격을
/// 이 파일로 끌어냈다. 탭마다 상세검색을 따로 그리면 "파티는 접혀 있는데
/// 장소대여는 전부 펼쳐져 있다"처럼 조작법이 갈라지고, 한쪽만 고쳐지는 일이
/// 반복된다. 그래서 **화면(부품)은 여기 한 곳**에 두고, 각 시트는 "어떤 항목을
/// 어떤 순서로 물을지"만 정한다.
///
/// 핵심 규칙은 하나다 — **모든 필터 항목은 기본 접힘**이고, 탭했을 때만 그
/// 자리에서 펼쳐진다([FilterAccordionSection]). 접힌 상태에서도 무엇을 골랐는지
/// 보이도록 헤더 우측에 한 줄 요약(summary)을 강조 색으로 띄운다.
library;

import 'package:flutter/material.dart';

import 'package:party_app/widgets/main/search_entry_sheet.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 값이 없으면 "전체"로 표시하는 공통 요약 포맷터 — 아코디언 헤더의
/// summary에 그대로 넣는다.
String filterSummaryOrAll(Iterable<String> values, {String joiner = ', '}) =>
    values.isEmpty ? '전체' : values.join(joiner);

/// 상세검색 시트 바닥에 둬야 할 여백 — 키보드가 올라와 있으면 키보드 높이,
/// 아니면 홈 인디케이터 높이. 검색어 입력창이 시트 안으로 들어오면서 "적용
/// 버튼이 키보드에 가리는" 일이 생겼기 때문에, 골격을 쓰지 않는 시트
/// (파티샵/파티크루)도 같은 계산을 그대로 쓰도록 여기에 둔다.
double filterSheetBottomInset(BuildContext context) {
  final media = MediaQuery.of(context);
  final keyboard = media.viewInsets.bottom;
  return keyboard > 0 ? keyboard : media.padding.bottom;
}

/// 탭하면 살짝 눌리는 스케일 애니메이션 + (선택 시) Material 잉크 리플을
/// 함께 주는 공통 터치 래퍼 — 아코디언 헤더/칩/시간 버튼 등 상세검색 시트
/// 전체의 터치 피드백을 이 위젯 하나로 통일한다. [rippleRadius]를 주면
/// Material+InkWell로 리플이 함께 뜨고, 생략하면 스케일만 적용된다.
class FilterScaleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? rippleRadius;

  const FilterScaleTap({
    super.key,
    required this.child,
    required this.onTap,
    this.rippleRadius,
  });

  @override
  State<FilterScaleTap> createState() => _FilterScaleTapState();
}

class _FilterScaleTapState extends State<FilterScaleTap> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.onTap == null) return;
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final hasRipple = widget.rippleRadius != null;
    final content = hasRipple
        ? Material(
            color: Colors.transparent,
            borderRadius: widget.rippleRadius,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: widget.rippleRadius,
              child: widget.child,
            ),
          )
        : widget.child;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: hasRipple ? null : widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: content,
      ),
    );
  }
}

/// "전체 초기화" — 텍스트 버튼 대신 새로고침 아이콘이 붙은 연핑크 필 버튼으로,
/// 눌리는 촉감이 느껴지는 실제 액션 버튼처럼 보이게 한다.
class FilterResetButton extends StatelessWidget {
  final VoidCallback onTap;
  const FilterResetButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilterScaleTap(
      onTap: onTap,
      rippleRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: PartyChuColors.surfaceTint,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PartyChuColors.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.refresh_rounded,
              size: 15,
              color: PartyChuColors.primaryDeep,
            ),
            SizedBox(width: 5),
            Text(
              '전체 초기화',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: PartyChuColors.primaryDeep,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 시트가 높이를 잡는 방식.
enum FilterSheetSizing {
  /// 화면 비율로 열고 손잡이로 끌어 늘린다([DraggableScrollableSheet]).
  /// 플레이스·이벤트·파티샵·크루 상세검색이 지금까지 쓰던 방식 그대로다.
  draggable,

  /// **내용 높이만큼만** 올라온다. 항목이 적으면 낮게, 많으면 화면 상한까지
  /// 자라고 그때부터 안쪽이 스크롤된다. 고정 height를 박지 않는다.
  ///
  /// 파티 상세검색이 이 방식을 쓴다 — 격자가 2열 다섯 칸이라 내용이 짧은데
  /// 비율로 열면 검색 버튼 아래가 통째로 비어 보였다.
  content,
}

/// 상세검색 시트의 바깥 골격 — 시트 비율·배경·손잡이·제목/초기화 줄·선택 조건
/// 칩·스크롤 영역·적용 버튼까지. 각 탭의 시트는 [sections]에 아코디언만 나열하면
/// 된다.
class FilterSheetShell extends StatelessWidget {
  /// 시트 제목 — '상세검색' / '장소대여 상세검색'처럼 탭 이름을 붙인다.
  /// [search]가 있으면 그쪽 제목('플레이스 검색')이 대신 쓰인다.
  final String title;

  /// 제목 왼쪽 아이콘.
  final IconData icon;

  /// 돋보기로 연 **검색 시트**일 때만 채워진다 — 제목 줄 아래에 검색어
  /// 입력창이 붙고, 적용 버튼 문구가 '검색'이 된다. 즉 검색어와 상세조건이
  /// 한 시트에서 함께 다뤄진다(예전처럼 상세검색 시트를 한 번 더 띄우지
  /// 않는다). null이면 예전 그대로의 상세검색 시트 — 지도 화면과 태블릿
  /// 좌측 필터 패널이 그렇게 쓴다.
  final SearchEntryConfig? search;

  /// 제목 줄 아래의 "선택된 조건" 칩 행([FilterSelectedChips]).
  final Widget selectedChips;

  /// 스크롤 영역에 그대로 들어가는 항목들 — 보통 [FilterAccordionSection] 목록.
  final List<Widget> sections;

  final VoidCallback onReset;
  final VoidCallback onApply;
  final String applyLabel;

  /// 높이를 잡는 방식 — 기본값은 지금까지의 비율 시트다.
  final FilterSheetSizing sizing;

  const FilterSheetShell({
    super.key,
    required this.title,
    required this.selectedChips,
    required this.sections,
    required this.onReset,
    required this.onApply,
    this.search,
    this.icon = Icons.tune_rounded,
    this.applyLabel = '적용하기',
    this.sizing = FilterSheetSizing.draggable,
  });

  /// [FilterSheetSizing.content]에서 화면 위에 반드시 남기는 여백.
  ///
  /// 내용이 아무리 많아도 시트가 화면을 통째로 덮지 않게 한다 — 뒤에 목록이
  /// 조금이라도 보여야 "전체 화면으로 넘어온 것"이 아니라 "위에 뜬 시트"로
  /// 읽히고, 바깥을 눌러 닫을 자리도 남는다.
  static const double contentTopGap = 56;

  @override
  Widget build(BuildContext context) {
    if (sizing == FilterSheetSizing.content) {
      // 내용 높이 시트 — 세로 크기를 여기서 정하지 않는다. 아래 Column이
      // mainAxisSize.min이라 항목만큼만 차지하고, 그 합이 상한을 넘는
      // 순간부터 [Flexible]에 물린 목록이 안쪽에서 스크롤된다.
      final media = MediaQuery.of(context);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: media.size.height - media.padding.top - contentTopGap,
        ),
        child: _frame(context, null),
      );
    }
    return DraggableScrollableSheet(
      // 처음 열리는 높이. 예전 0.9는 거의 전체화면이라, 조건을 몇 개
      // 안 고른 상태에서는 목록과 검색 버튼 사이가 텅 비어 보였다.
      // 아래 여백들을 함께 줄여 같은 항목이 더 촘촘히 들어가므로,
      // 처음에는 조금 낮게 열고 필요하면 예전처럼 0.95까지 끌어올린다.
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => _frame(ctx, scrollCtrl),
    );
  }

  /// 시트 속 내용 — 두 sizing이 **같은 골격**을 쓴다. 다른 것은 목록을
  /// [Expanded](비율 시트: 남는 높이를 다 쓴다)로 물리느냐 [Flexible] +
  /// `shrinkWrap`(내용 높이 시트: 필요한 만큼만 쓴다)으로 물리느냐 하나뿐이다.
  Widget _frame(BuildContext context, ScrollController? scrollCtrl) {
    final fitContent = scrollCtrl == null;
    return DecoratedBox(
      // 기본 흰 시트 대신 아주 은은한 핑크 톤 배경으로 — PartyChu다운
      // 화사한 분위기를 화면 전체에 깔아준다(카드 자체는 흰색으로 남겨
      // 카드/배경 구분이 또렷하게 보이게 한다).
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF7FA), Color(0xFFFFFCFD)],
          stops: [0.0, 0.3],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          // 내용 높이 시트는 자식들의 합만큼만 차지한다 — 이 한 줄이
          // "빈 공간 없이 내용만큼 올라오는" 동작의 핵심이다.
          mainAxisSize: fitContent ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // 손잡이 위아래 — 14/18에서 줄였다. 손잡이 자체 크기는 그대로라
            // 잡아 끄는 데는 달라지는 게 없다.
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD1E4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(icon, size: 20, color: PartyChuColors.primary),
                const SizedBox(width: 8),
                // 제목이 길어도(‘장소대여 상세검색’) 초기화 버튼을 밀어내지
                // 않도록 Expanded로 남은 폭을 채우고, 정말 모자랄 때만 줄인다.
                Expanded(
                  child: Text(
                    search?.title ?? title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: PartyChuColors.heading,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 검색 시트로 열렸으면 검색어까지 함께 지운다 — 이 시트에서
                // 걸 수 있는 조건을 한 번에 푸는 버튼이라, 검색어만 남아
                // 목록이 계속 걸러져 있는 일이 없어야 한다.
                FilterResetButton(
                  onTap: () {
                    search?.clearQuery();
                    onReset();
                  },
                ),
              ],
            ),
            // 돋보기로 열었으면 조건들 **바로 위**에 검색어 입력창이 붙는다 —
            // 여기가 예전에 "상세검색 >" 버튼이 있던 자리다.
            if (search != null) ...[
              const SizedBox(height: 10),
              SearchEntryField(config: search!),
            ],
            selectedChips,
            const SizedBox(height: 2),
            // 항목 목록. 비율 시트는 남는 높이를 전부 쓰고(Expanded),
            // 내용 높이 시트는 필요한 만큼만 쓴다(Flexible + shrinkWrap).
            // 어느 쪽이든 넘치면 여기 안쪽에서만 스크롤된다 — 제목 줄과
            // 아래 검색 버튼은 늘 제자리에 남는다.
            _sectionList(fitContent: fitContent, scrollCtrl: scrollCtrl),
            const SizedBox(height: 4),
            PartyChuPrimaryButton(
              // 검색 시트로 열렸으면 '검색', 상세검색만이면 '적용하기'.
              // 어느 쪽이든 누르면 이 시트 하나만 닫히고 목록에 반영된다.
              label: search == null ? applyLabel : '검색',
              height: 56,
              showBadge: false,
              onTap: onApply,
            ),
            // 키보드가 올라오면 그만큼 바닥을 띄워, 적용 버튼이 키보드 뒤로
            // 숨지 않게 한다(검색어 입력창이 같은 시트에 들어오면서 생긴 상황).
            // 키보드가 없을 때는 하단 안전영역(제스처 바) 높이가 들어간다.
            SizedBox(height: 10 + filterSheetBottomInset(context)),
          ],
        ),
      ),
    );
  }

  Widget _sectionList({
    required bool fitContent,
    required ScrollController? scrollCtrl,
  }) {
    final list = ListView(
      controller: scrollCtrl,
      // 내용 높이 시트에서는 목록이 **자기 내용만큼만** 커진다. 그래서
      // 항목이 적으면 시트도 그만큼 낮게 열리고, 버튼 아래에 빈 공간이
      // 생기지 않는다.
      shrinkWrap: fitContent,
      physics: fitContent
          // 내용이 상한보다 짧으면 스크롤이 필요 없다 — 이때 튕기는 스크롤을
          // 허용하면 다 보이는 시트가 이유 없이 움직인다.
          ? const ClampingScrollPhysics()
          : const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
      // 검색어 입력창이 위에 있는 경우(header) 키보드가 올라온 채로
      // 조건을 훑게 되는데, 목록을 끌어내리면 키보드가 함께 내려가
      // 아래쪽 조건과 적용 버튼이 곧바로 다시 보인다.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const SizedBox(height: 4),
        ...sections,
        // 검색 버튼 위 빈칸 — 14 → 8 → 6. 아래 4까지 합쳐 10이다
        // (버튼 자체 높이 56은 그대로).
        const SizedBox(height: 6),
      ],
    );
    return fitContent ? Flexible(child: list) : Expanded(child: list);
  }
}

/// 3×3 그리드로 늘어놓는 필터 항목 하나 — [FilterGridSection]에 넘긴다.
///
/// 담는 값은 [FilterAccordionSection]과 **똑같다**. 펼쳤을 때 보여줄 [child]도
/// 기존 아코디언 본문을 그대로 받는다 — 배치만 바뀌고 선택 UI·상태·요약 문구는
/// 하나도 새로 만들지 않는다.
@immutable
class FilterGridItem {
  final String title;
  final IconData icon;
  final Color iconColor;

  /// 현재 선택값. 고른 게 없으면 '전체'가 들어온다(filterSummaryOrAll).
  final String summary;

  final bool hasSelection;
  final bool expanded;
  final VoidCallback onToggle;

  /// 펼쳤을 때 보여줄 선택 UI — 아코디언 시절 본문 그대로.
  ///
  /// **null이면 이 칸은 펼쳐지지 않는다** — [onToggle]이 바텀시트를 여는
  /// 칸이다(파티 유형·분위기). 그런 칸은 아래 화살표도 돌지 않고, 줄
  /// 아래에 본문 자리를 차지하지도 않는다.
  final Widget? child;

  /// 그 자리에서 펼쳐지는 칸인가 — 시트를 여는 칸은 false다.
  bool get canExpand => child != null;

  const FilterGridItem({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.summary,
    required this.hasSelection,
    required this.expanded,
    required this.onToggle,
    this.child,
  });
}

/// 격자 칸 하나의 **치수 한 벌** — 폭·높이·여백·글자·아이콘·모서리가 전부
/// 여기 모여 있다. 카드가 제각각으로 보이지 않게 하려면 값을 화면에 흩지 말고
/// 이 클래스만 고친다.
@immutable
class FilterGridCellStyle {
  const FilterGridCellStyle({
    required this.columns,
    required this.columnGap,
    required this.keepEmptySlots,
    required this.padding,
    required this.radius,
    required this.iconSize,
    required this.titleSize,
    required this.summarySize,
    required this.chevronSize,
    required this.chevronAtCenter,
    required this.iconGap,
    required this.titleGap,
  });

  /// 한 줄에 놓는 칸 수.
  final int columns;

  final double columnGap;

  /// 마지막 줄이 덜 찼을 때 남는 자리를 **빈 칸으로 남길지**. false면 남은
  /// 칸들이 그 폭을 나눠 갖는다(칸마다 폭이 달라진다).
  final bool keepEmptySlots;

  final EdgeInsets padding;
  final double radius;
  final double iconSize;
  final double titleSize;
  final double summarySize;
  final double chevronSize;

  /// ▼를 카드 오른쪽 **세로 가운데**에 둘지(true), 선택값과 같은 줄 끝에
  /// 둘지(false).
  final bool chevronAtCenter;

  /// 아이콘 ↔ 항목명 사이, 항목명 ↔ 선택값 사이 간격.
  final double iconGap;
  final double titleGap;
}

/// 칸을 늘어놓는 방식.
enum FilterGridLayout {
  /// 3열. 마지막 줄이 덜 차면 남은 칸이 폭을 나눠 갖는다 — 플레이스·이벤트·
  /// 파티샵·크루 상세검색이 지금까지 쓰던 배치 그대로다.
  compact3(
    FilterGridCellStyle(
      columns: FilterGridSection.columns,
      columnGap: FilterGridSection.columnGap,
      keepEmptySlots: false,
      // 1/3 폭이라 글자가 들어갈 자리가 얼마 없다 — 좌우를 바짝 조인다.
      padding: EdgeInsets.fromLTRB(7, 3, 6, 3),
      radius: 14,
      iconSize: 13,
      titleSize: 13,
      summarySize: 12.5,
      chevronSize: 14,
      chevronAtCenter: false,
      iconGap: 3,
      titleGap: 1,
    ),
  ),

  /// 2열 **균일 배치** — 모든 카드의 가로폭·세로높이·안쪽 여백·모서리가 같다.
  /// 마지막 줄에 한 칸만 남아도 그 칸을 넓히지 않는다.
  ///
  /// 파티 상세검색이 쓴다. 칸이 다섯이라 3열로 놓으면 3+2가 되어 둘째 줄
  /// 카드만 넓어졌고, 마지막 한 칸을 넓게 쓰던 규칙까지 겹쳐 폭이 세 가지로
  /// 갈렸다. 2열은 칸 폭이 1/2로 넉넉해져 여백과 글자도 함께 키울 수 있다.
  uniform2(
    FilterGridCellStyle(
      columns: 2,
      columnGap: 8,
      keepEmptySlots: true,
      // 1/2 폭이라 3열보다 여유가 있다 — 카드 안이 답답해 보이지 않게
      // 좌우·위아래를 함께 넓힌다(모든 카드가 같은 값을 쓴다).
      padding: EdgeInsets.fromLTRB(12, 9, 10, 9),
      radius: 16,
      iconSize: 15,
      titleSize: 13.5,
      summarySize: 12.5,
      chevronSize: 18,
      chevronAtCenter: true,
      iconGap: 5,
      titleGap: 3,
    ),
  );

  const FilterGridLayout(this.style);

  final FilterGridCellStyle style;
}

/// 필터 항목을 **한 줄에 세 개씩** 놓는 미니 카드 배치 — 아홉 항목이 3×3
/// 그리드로 한눈에 들어온다.
///
/// 항목마다 한 줄을 통째로 쓰던 예전 배치는 아홉 줄이라 검색창에서 검색
/// 버튼까지 한 화면에 들어오지 않았다. 카드 재질은 파티츄 카드 그대로
/// (흰 배경·둥근 모서리·연핑크 그림자)이고, 폭을 1/3로 줄이고 높이도 두 줄
/// 분량까지 낮춰 아홉 장이 촘촘히 모이게 한다.
///
/// **아홉 칸의 크기는 모두 같다** — 칸 안은 늘 두 줄(항목명 / 선택값)이고 각
/// 줄은 한 줄로 잘리므로(말줄임), 어떤 값을 골라도 카드가 커지거나 줄지
/// 않는다. 줄 안의 세 칸 높이는 [IntrinsicHeight]로 맞춘다.
///
/// 펼친 항목의 본문은 **가로 전체 폭**으로, 그 항목이 속한 줄 바로 아래에
/// 그린다 — 칩이 여러 줄로 접히는 본문(파티 유형·분위기)을 1/3 폭에 우겨넣지
/// 않기 위해서다.
class FilterGridSection extends StatelessWidget {
  final List<FilterGridItem> items;

  /// 칸을 늘어놓는 방식 — 기본값은 지금까지의 3열 배치다.
  final FilterGridLayout layout;

  /// 한 줄에 놓는 칸 수(3열 배치).
  static const int columns = 3;

  /// 칸 사이 가로 간격 — 320px 화면에서도 세 칸이 들어가도록 좁게 잡는다.
  static const double columnGap = 6;

  /// 줄 사이 세로 간격 — 여기서 줄인 만큼이 그대로 시트 길이에서 빠진다
  /// (카드 크기는 [_cell]의 안쪽 여백이 정한다).
  static const double rowGap = 4;

  const FilterGridSection({
    super.key,
    required this.items,
    this.layout = FilterGridLayout.compact3,
  });

  @override
  Widget build(BuildContext context) {
    final style = layout.style;
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += style.columns) {
      final row = items.sublist(
        i,
        i + style.columns > items.length ? items.length : i + style.columns,
      );

      rows.add(
        // 한 줄 안 칸들의 높이를 맞춘다. stretch만 쓰면 세로 스크롤 안에서는
        // 높이가 무한대로 내려와 layout이 터지므로([BoxConstraints forces an
        // infinite height]), IntrinsicHeight로 줄 높이를 먼저 정한다.
        //
        // 줄과 줄 사이의 높이까지 같아지는 것은 칸 **내용의 구조가 모두
        // 같기** 때문이다 — 어느 칸이든 '아이콘+항목명 한 줄 / 선택값 한 줄'
        // 이고 둘 다 maxLines: 1이라, 고른 값이 무엇이든 intrinsic 높이가
        // 같은 값으로 나온다(글자를 키워도 함께 커지므로 여전히 같다).
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < row.length; c++) ...[
                if (c > 0) SizedBox(width: style.columnGap),
                Expanded(child: _cell(row[c], style)),
              ],
              // 마지막 줄이 덜 찼을 때 남는 자리를 어떻게 둘 것인가.
              //
              // uniform 배치는 **빈 칸을 그대로 비워 둔다** — 남은 한 칸이
              // 줄을 넓게 쓰면 그 카드만 폭이 달라져, '모든 카드가 같은
              // 크기'라는 이 배치의 규칙이 깨진다.
              // compact 배치는 예전처럼 남은 칸들이 폭을 나눠 갖는다(위
              // Expanded가 이미 그렇게 동작한다).
              if (style.keepEmptySlots)
                for (var c = row.length; c < style.columns; c++) ...[
                  SizedBox(width: style.columnGap),
                  const Expanded(child: SizedBox.shrink()),
                ],
            ],
          ),
        ),
      );

      // 이 줄에서 펼쳐진 항목의 본문 — 가로 전체 폭으로 줄 아래에 붙는다.
      // 시트를 여는 칸은 본문이 없으므로 자리도 만들지 않는다.
      for (final item in row) {
        if (!item.canExpand) continue;
        rows.add(
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: rowGap),
              child: _body(item),
            ),
            crossFadeState: item.expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeInOut,
            firstCurve: Curves.easeIn,
            secondCurve: Curves.easeOut,
          ),
        );
      }
      rows.add(const SizedBox(height: rowGap));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  /// 미니 카드 한 장 — 왼쪽 위는 컬러 아이콘 + 항목명, 왼쪽 아래는 현재
  /// 선택값, 오른쪽은 아래 화살표.
  ///
  /// 두 글자 줄 모두 **한 줄로 자른다(말줄임)** — 이것이 "어떤 값을 골라도
  /// 카드 크기가 변하지 않는다"를 만드는 규칙이다. 치수는 전부
  /// [FilterGridCellStyle]에서 온다(여기에 숫자를 직접 쓰지 않는다).
  Widget _cell(FilterGridItem item, FilterGridCellStyle style) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // 고른 값이 있으면 연핑크 바탕 + 핑크 테두리로 살짝 도드라지게 —
        // 카드가 작아 글자 색만으로는 눈에 덜 띈다.
        color: item.hasSelection ? const Color(0xFFFFF1F6) : Colors.white,
        borderRadius: BorderRadius.circular(style.radius),
        boxShadow: [
          BoxShadow(
            color: PartyChuColors.primary.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          // 두께는 선택 여부와 상관없이 1로 둔다 — 테두리가 굵어지면 안쪽
          // 폭이 줄어 글자가 더 잘리고, 카드 크기도 칸마다 달라진다.
          color: item.hasSelection
              ? PartyChuColors.primary.withValues(alpha: 0.55)
              : const Color(0xFFF2E6EC),
        ),
      ),
      child: FilterScaleTap(
        rippleRadius: BorderRadius.circular(style.radius),
        onTap: item.onToggle,
        child: Padding(
          padding: style.padding,
          child: Row(
            children: [
              // 왼쪽 덩어리 — 위는 아이콘 + 항목명, 아래는 현재 선택값.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          item.icon,
                          size: style.iconSize,
                          color: item.iconColor,
                        ),
                        SizedBox(width: style.iconGap),
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: style.titleSize,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              color: PartyChuColors.heading,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // 항목명 ↔ 선택값 — 두 줄의 줄 높이(1.1)가 이미 붙어
                    // 있어 여기서 더 띄우지 않는다.
                    SizedBox(height: style.titleGap),
                    Row(
                      children: [
                        // 선택값 — 카드 폭을 넘기면 말줄임. 카드를 키우지 않는다.
                        Expanded(
                          child: Text(
                            item.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: style.summarySize,
                              height: 1.1,
                              fontWeight: item.hasSelection
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: item.hasSelection
                                  ? PartyChuColors.primaryDeep
                                  : PartyChuColors.subtleText,
                            ),
                          ),
                        ),
                        // 3열 배치에서는 ▼가 선택값과 같은 줄 끝에 붙는다
                        // (폭이 좁아 따로 세로 칸을 내주면 글자가 더 잘린다).
                        if (!style.chevronAtCenter) ...[
                          const SizedBox(width: 1),
                          _chevron(item, style),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // 2열 배치에서는 ▼가 카드 오른쪽 **세로 가운데**에 선다 —
              // Row의 기본 정렬(center)이 그 자리를 잡아 준다.
              if (style.chevronAtCenter) ...[
                const SizedBox(width: 4),
                _chevron(item, style),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 카드의 ▼ — 그 자리에서 펼쳐지는 칸이면 펼칠 때 뒤집힌다.
  /// 시트를 여는 칸(파티 유형·분위기)은 돌지 않는다.
  Widget _chevron(FilterGridItem item, FilterGridCellStyle style) {
    return AnimatedRotation(
      turns: item.canExpand && item.expanded ? 0.5 : 0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Icon(
        Icons.expand_more_rounded,
        size: style.chevronSize,
        color: PartyChuColors.muted,
      ),
    );
  }

  /// 펼친 본문을 담는 가로 전체 폭 카드 — 카드 재질은 위 칸들과 같다.
  Widget _body(FilterGridItem item) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: PartyChuColors.primary.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        // 펼친 본문 여백 — 12/14 → 10/12. 본문 안의 선택 UI는 그대로다.
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 어느 항목을 펼친 것인지 본문 위에 한 줄로 밝힌다 — 본문이 줄
            // 아래에 따로 떨어져 나오므로 표시가 없으면 헷갈린다.
            Row(
              children: [
                Icon(item.icon, size: 17, color: item.iconColor),
                const SizedBox(width: 6),
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: PartyChuColors.heading,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            item.child!,
          ],
        ),
      ),
    );
  }
}

/// 상세검색의 필터 섹션 하나 — **기본은 접힘**이고 헤더를 탭하면 그 자리에서
/// 펼쳐진다. 접힌 상태에서도 무엇을 골랐는지 알 수 있도록 헤더 우측에
/// [summary]를 보여주고, [hasSelection]이면 강조 색 알약으로 감싼다.
///
/// 펼침 상태는 호출부가 들고 있는다([expanded]/[onToggle]) — 시트마다 "한 번에
/// 하나만 펼치기 / 여러 개 펼치기" 같은 규칙을 고를 수 있게 하기 위함이다.
class FilterAccordionSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final String summary;
  final bool hasSelection;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  const FilterAccordionSection({
    super.key,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.summary,
    required this.hasSelection,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: PartyChuColors.primary.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterScaleTap(
            rippleRadius: BorderRadius.circular(20),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Icon(icon, size: 21, color: iconColor),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: PartyChuColors.heading,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: hasSelection
                            ? const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              )
                            : EdgeInsets.zero,
                        decoration: BoxDecoration(
                          color: hasSelection
                              ? PartyChuColors.surfaceTint
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          summary,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: hasSelection
                                ? FontWeight.w800
                                : FontWeight.normal,
                            color: hasSelection
                                ? PartyChuColors.primaryDeep
                                : PartyChuColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: const Icon(
                      Icons.expand_more_rounded,
                      size: 22,
                      color: PartyChuColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeInOut,
            firstCurve: Curves.easeIn,
            secondCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }
}

/// 아코디언 안에서 고르는 옵션 칩 하나. 칩 자체가 눌리는 스케일 + 리플을
/// 갖고 있어 호출부는 [onTap]만 넘기면 된다. [dim](한도 초과 등으로 고를 수
/// 없음)일 때는 [onTap]을 null로 넘기면 탭이 막힌다.
class FilterOptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool dim;
  final IconData? icon;
  final VoidCallback? onTap;

  /// 파티 유형처럼 제목 폰트를 쓰는 항목에만 true.
  final bool titleFont;

  const FilterOptionChip({
    super.key,
    required this.label,
    required this.selected,
    this.dim = false,
    this.icon,
    this.onTap,
    this.titleFont = false,
  });

  @override
  Widget build(BuildContext context) {
    return FilterScaleTap(
      onTap: onTap,
      rippleRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? PartyChuColors.primary
              : dim
              ? const Color(0xFFF5F5F7)
              : PartyChuColors.surfaceTint,
          borderRadius: BorderRadius.circular(18),
          border: selected
              ? null
              : Border.all(
                  color: dim ? const Color(0xFFEDEDF0) : PartyChuColors.border,
                ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: PartyChuColors.primary.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : PartyChuColors.primary,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: titleFont ? PartyChuTitleFont.family : null,
                fontSize: 13,
                color: selected
                    ? Colors.white
                    : dim
                    ? Colors.black26
                    : PartyChuColors.heading,
                fontWeight: titleFont
                    ? PartyChuTitleFont.medium
                    : (selected ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 여러 개를 고를 수 있는 칩 묶음 — 아코디언 본문에 가장 많이 들어가는 모양.
/// [selected] Set을 직접 고쳐 주므로 호출부는 [onChanged]에서 setState만 하면
/// 된다.
class FilterChipWrap extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;

  /// 선택이 바뀐 뒤 호출 — 보통 `() => setState(() {})`.
  final VoidCallback onChanged;

  /// 화면에 보여줄 이름을 따로 만들 때(이모지 붙이기, 코드→라벨 변환 등).
  final String Function(String option)? labelBuilder;

  final bool titleFont;

  const FilterChipWrap({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.labelBuilder,
    this.titleFont = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((opt) {
        final isSelected = selected.contains(opt);
        return FilterOptionChip(
          label: labelBuilder != null ? labelBuilder!(opt) : opt,
          selected: isSelected,
          titleFont: titleFont,
          onTap: () {
            if (isSelected) {
              selected.remove(opt);
            } else {
              selected.add(opt);
            }
            onChanged();
          },
        );
      }).toList(),
    );
  }
}

/// 제목 줄 아래에 지금까지 고른 조건을 한눈에 보여주는 칩 행 — 여기서 바로
/// 하나씩 뺄 수 있다. 각 필터 모델의 `selectedEntries`를 그대로 넘기면 된다.
class FilterSelectedChips extends StatelessWidget {
  final List<MapEntry<String, String>> entries;
  final void Function(MapEntry<String, String> entry) onDelete;

  /// 칩에 적을 문구를 따로 만들 때(파티 유형 코드→라벨 등).
  final String Function(MapEntry<String, String> entry)? labelBuilder;

  /// 칩 앞에 붙일 작은 아이콘 — 필요 없는 칩에는 null을 돌려주면 된다.
  final Widget? Function(MapEntry<String, String> entry)? avatarBuilder;

  /// 파티 유형처럼 제목 폰트로 보여줄 항목인지.
  final bool Function(MapEntry<String, String> entry)? titleFontWhen;

  const FilterSelectedChips({
    super.key,
    required this.entries,
    required this.onDelete,
    this.labelBuilder,
    this.avatarBuilder,
    this.titleFontWhen,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Padding(
        // 위아래 10 → 6. 문구('선택된 조건이 없습니다')는 그대로다.
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '선택된 조건이 없습니다',
            style: TextStyle(fontSize: 12, color: PartyChuColors.muted),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: entries.map((e) {
          return Chip(
            avatar: avatarBuilder?.call(e),
            label: Text(
              labelBuilder != null ? labelBuilder!(e) : e.value,
              style: TextStyle(
                fontFamily: (titleFontWhen?.call(e) ?? false)
                    ? PartyChuTitleFont.family
                    : null,
                fontSize: 12,
              ),
            ),
            labelStyle: const TextStyle(
              color: PartyChuColors.primaryDeep,
              fontWeight: FontWeight.w600,
            ),
            deleteIcon: const Icon(Icons.close_rounded, size: 14),
            deleteIconColor: PartyChuColors.primary,
            onDeleted: () => onDelete(e),
            backgroundColor: PartyChuColors.surfaceTint,
            side: const BorderSide(color: PartyChuColors.border),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        }).toList(),
      ),
    );
  }
}

/// 날짜·시간처럼 다른 화면을 열어서 고르는 값의 버튼 — 값이 차 있으면 핑크로
/// 채워지고, 아직 고를 수 없는 상태([enabled]=false)면 회색으로 잠긴다.
class FilterPickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final bool enabled;
  final VoidCallback onTap;

  const FilterPickerButton({
    super.key,
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return FilterScaleTap(
      onTap: enabled ? onTap : null,
      rippleRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: !enabled
              ? const Color(0xFFF5F5F7)
              : filled
              ? PartyChuColors.primary
              : PartyChuColors.surfaceTint,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: !enabled
                ? const Color(0xFFE8EBF2)
                : filled
                ? PartyChuColors.primary
                : PartyChuColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: !enabled
                  ? Colors.black26
                  : filled
                  ? Colors.white
                  : PartyChuColors.primary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: !enabled
                      ? Colors.black26
                      : filled
                      ? Colors.white
                      : PartyChuColors.heading,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 둘 중 하나만 고르는 조건(이용 가능 조건 / 운영시간 조건)의 라디오 한 줄.
class FilterRadioOption extends StatelessWidget {
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const FilterRadioOption({
    super.key,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? PartyChuColors.primary : Colors.black26,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? PartyChuColors.primary
                          : PartyChuColors.heading,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      color: PartyChuColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 아코디언 본문 아래에 붙는 안내 문구 — 시트마다 같은 톤으로 보이게.
class FilterHintText extends StatelessWidget {
  final String text;
  const FilterHintText(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 11.5,
      height: 1.4,
      color: PartyChuColors.muted,
    ),
  );
}

/// 상세검색 시트 **맨 아래의 독립 토글 카드** — 격자·아코디언에 들어가지 않는
/// on/off 조건 하나가 늘 보이는 자리에 앉는다(적용/검색 버튼 바로 위).
///
/// 서랍(아코디언) 안에 한 칸짜리 조건을 넣으면 열어 보기 전에는 있는 줄도
/// 모른다 — 파티의 ⚡ 얼리버드가 그랬고, 플레이스의 🟢 현재 영업 중이 그랬다.
/// 그래서 그런 조건은 접지 않고 여기로 꺼낸다.
///
/// ## 카드 높이가 서로 같다
///
/// 예전에는 [SwitchListTile]에 subtitle을 넘기는 방식이라, 설명문이 붙은
/// 카드만 눈에 띄게 높아져 한 쌍으로 보이지 않았다. 지금은 설명문 자리를
/// **설명이 없는 카드도 똑같이 비워 두고**(같은 높이의 빈 줄), 카드 높이를
/// [kFilterToggleCardMinHeight]로 함께 잡는다.
///
/// 파티 상세검색과 플레이스 상세검색이 **이 하나**를 쓴다 — 시트마다 따로
/// 그리면 같은 성격의 스위치가 탭마다 다른 크기·다른 여백으로 보인다.
class FilterToggleCard extends StatelessWidget {
  const FilterToggleCard({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// 없으면 같은 높이의 빈 줄이 대신 자리를 잡는다(위 주석).
  final String? subtitle;

  /// 제목 왼쪽 아이콘 — 없으면 자리 자체를 만들지 않는다.
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    // 필드는 타입 승격이 안 된다 — 지역 변수로 한 번 받아야 아래에서 icon·
    // subtitle을 null 검사만으로 그대로 쓸 수 있다(메서드였을 때의 모습 그대로).
    final icon = this.icon;
    final subtitle = this.subtitle;
    // 글자를 키우면 카드도 함께 커져야 잘리지 않는다 — 최소 높이에 사용자의
    // 글자 배율을 그대로 곱한다(고정 픽셀로 두면 확대 시 넘친다).
    final scale = MediaQuery.textScalerOf(context);
    return Container(
      constraints: BoxConstraints(
        minHeight: scale.scale(kFilterToggleCardMinHeight),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: PartyChuColors.primary.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // 카드 아무 데나 눌러도 스위치가 넘어간다 — [SwitchListTile]이 하던
      // 동작 그대로다(레이아웃만 바꾸고 조작법은 유지한다).
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                if (icon != null) ...[icon, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        // **한 줄로 고정한다.** 두 제목의 길이가 달라서, 접히도록
                        // 두면 폭에 따라 한쪽만 두 줄이 되어(360dp에서 '내가 참여
                        // 가능한 파티만 보기'만 접혔다) 카드 높이가 갈렸다.
                        // 글자 크기(14)와 문구는 그대로다.
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // 설명 줄 — **두 카드가 똑같은 크기의 자리를 잡는다.**
                      //
                      // 설명이 있든 없든, 한 줄로 끝나든 두 줄이 되든 이 상자의
                      // 높이는 늘 '두 줄'이다. 그래서 설명문이 붙은 카드만 혼자
                      // 높아지는 일이 없다. 문구도 글자 크기도 그대로이고, 두 줄을
                      // 넘기면 말줄임이라 어떤 폭에서도 넘치지 않는다.
                      SizedBox(
                        height:
                            scale.scale(kFilterToggleSubtitleSize) *
                            kFilterToggleSubtitleHeight *
                            kFilterToggleSubtitleLines,
                        child: subtitle == null
                            ? null
                            : Text(
                                subtitle,
                                maxLines: kFilterToggleSubtitleLines,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: kFilterToggleSubtitleSize,
                                  height: kFilterToggleSubtitleHeight,
                                  color: PartyChuColors.muted,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: PartyChuColors.primary,
                  // 스위치가 스스로 잡는 여백을 줄여 카드가 필요 이상으로
                  // 높아지지 않게 한다(누를 수 있는 자리는 카드 전체다).
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 토글 카드 여러 장이 함께 쓰는 최소 높이 — 제목 한 줄 + 설명 한 줄이 여백과
/// 함께 들어가는 크기다. 글자 배율을 곱해서 쓰므로 글자를 키워도 잘리지 않는다.
const double kFilterToggleCardMinHeight = 56;

/// 토글 카드의 설명 줄 — 글자 크기·줄 높이·**늘 잡아 두는 줄 수**.
///
/// 줄 수를 고정해 두는 것이 카드들의 높이를 맞추는 장치다. 설명이 없는
/// 카드도 같은 크기의 자리를 비워 두고, 설명이 길면 두 줄에서 말줄임된다.
const double kFilterToggleSubtitleSize = 11.5;
const double kFilterToggleSubtitleHeight = 1.15;
const int kFilterToggleSubtitleLines = 2;
