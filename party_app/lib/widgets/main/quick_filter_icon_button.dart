import 'package:flutter/material.dart';

/// 목록 위 **빠른 필터 아이콘 버튼** 하나 — 📅 날짜 / 🕐 시간 / 👥 인원이
/// 모두 이 버튼을 쓴다.
///
/// 플레이스 탭의 빠른 조건 줄([PlaceQuickTimeBar])과 장소대여 탭의 상단 필터
/// 줄이 같은 버튼을 쓴다. 각자 그리면 같은 뜻의 버튼이 탭마다 다른 크기·색으로
/// 보인다(예전에 인원 버튼을 새로 그렸다면 정확히 그렇게 됐을 것이다).
///
/// 상태는 두 가지뿐이다:
/// - [active] — 조건이 실제로 걸려 있음(핑크로 **채운다**)
/// - [opened] — 지금 선택지가 펼쳐져 있음(옅은 핑크로 **비춘다**)
class QuickFilterIconButton extends StatelessWidget {
  static const Color pink = Color(0xFFFF6FA0);

  // ── 폭 계산에 쓰는 치수 ───────────────────────────────────────────────
  //
  // 라벨이 길어지면 이 버튼도 그만큼 넓어진다. 좁은 줄에서는 그 폭이 옆
  // 버튼(장소대여 상단 줄의 지역선택)을 밀어내므로, 부르는 쪽이 "이 글자가
  // 들어가는가"를 미리 재야 한다([placeRentalTypeButtonLabel]).
  //
  // **재는 값과 그리는 값이 같아야** 계산이 뜻을 가진다 — 그래서 아래 값들을
  // build가 그대로 쓴다(지역 버튼의 [RegionFilterFit]과 같은 규칙).

  /// 라벨 글자 스타일(색은 폭에 영향이 없어 여기 두지 않는다).
  static const TextStyle labelStyle = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
  );

  /// 라벨이 있을 때의 좌우 안쪽 여백.
  static const double hPadding = 9;

  /// 라벨 옆 아이콘 크기와 사이 간격.
  static const double labelIconSize = 15;
  static const double labelIconGap = 5;

  /// 라벨이 없을 때(아이콘만)의 폭.
  static const double iconOnlyWidth = 38;

  /// 라벨이 [text]일 때 이 버튼이 실제로 차지하는 폭.
  static double widthForLabel(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = hPadding * 2 + labelIconSize + labelIconGap + painter.width;
    return width < iconOnlyWidth ? iconOnlyWidth : width;
  }

  final IconData icon;

  /// 조건이 걸려 있는가 — 채움 여부를 정한다.
  final bool active;

  /// 지금 이 버튼의 선택지가 열려 있는가. 바텀시트로 고르는 버튼은 언제나
  /// false여도 된다(열려 있는 동안 버튼이 가려지므로).
  final bool opened;

  final VoidCallback onTap;

  /// 아이콘 위에 얹는 작은 숫자(고른 날 수 등).
  final String? badge;

  /// 아이콘 옆에 붙는 현재 값('20:00' / '5명'). 주면 버튼이 글자만큼만
  /// 늘어난다(줄 높이는 그대로 32).
  final String? label;

  /// 플레이스 탭의 밤 모드 — 버튼 재질을 다크 글래스로 바꾼다.
  final bool night;

  const QuickFilterIconButton({
    super.key,
    required this.icon,
    required this.active,
    required this.onTap,
    this.opened = false,
    this.badge,
    this.label,
    this.night = false,
  });

  @override
  Widget build(BuildContext context) {
    final filled = active || opened;
    final bg = filled
        ? pink.withValues(alpha: opened && !active ? 0.14 : 1)
        : night
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white;
    final fg = filled && active
        ? Colors.white
        : filled
        ? pink
        : night
        ? Colors.white70
        : Colors.black45;
    final border = filled
        ? pink
        : night
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFF0E2E9);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 32,
            // 폭은 **최소값**으로만 잡는다. 예전처럼 `width: 38`을 고정하면
            // 라벨이 새로 붙는 순간(인원을 고른 직후) 애니메이션이 폭을 아직
            // 38로 잡고 있어 글자가 밀려나 RenderFlex overflow가 났다.
            // 최소폭이면 내용이 길어지는 만큼 자연스럽게 늘어난다.
            constraints: const BoxConstraints(minWidth: iconOnlyWidth),
            padding: label == null
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: hPadding),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: label == null
                ? Icon(icon, size: 16, color: fg)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: labelIconSize, color: fg),
                      const SizedBox(width: labelIconGap),
                      Text(label!, style: labelStyle.copyWith(color: fg)),
                    ],
                  ),
          ),
          // 고른 날 수 — 아이콘만으로는 몇 날인지 알 수 없으니 숫자만 얹는다.
          if (badge != null)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: pink,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: night ? const Color(0xFF14121A) : Colors.white,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 9.5,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 📅 🕐 👥를 **한 알약 안에** 묶은 버튼 — 플레이스 목록 위 한 줄에서 방문
/// 조건 셋을 함께 여는 입구다.
///
/// ## 왜 셋을 묶었나
///
/// 목록 위 한 줄에는 방문 조건 · 편의·서비스 · 보기 방식 · 돋보기가 함께
/// 앉는다. 예전처럼 날짜·시간·인원이 각자 버튼을 가지면 그 셋만으로 줄의
/// 절반을 먹어서, 나머지가 둘째 줄로 밀리거나 좁은 화면에서 넘쳤다.
///
/// 묶어도 **무엇이 걸려 있는지는 그대로 보인다** — 아이콘 하나하나가 자기
/// 조건이 켜졌을 때만 핑크로 물든다([QuickConditionIcon.active]). 그래서
/// 접힌 상태에서도 "날짜만 걸려 있다"가 한눈에 읽힌다.
///
/// 누르면 세 조건이 **함께** 펼쳐진다(부르는 쪽이 그린다) — 셋 중 하나를
/// 고르러 들어와서 다른 하나도 바꾸는 일이 흔하기 때문이다.
class QuickConditionGroupButton extends StatelessWidget {
  final List<QuickConditionIcon> icons;

  /// 지금 선택지가 펼쳐져 있는가 — 옅은 핑크로 비춘다.
  final bool opened;

  final VoidCallback onTap;

  /// 툴팁·접근성 라벨('방문 조건 · 날짜 2일').
  final String label;

  final bool night;

  const QuickConditionGroupButton({
    super.key,
    required this.icons,
    required this.onTap,
    required this.label,
    this.opened = false,
    this.night = false,
  });

  @override
  Widget build(BuildContext context) {
    const pink = QuickFilterIconButton.pink;
    final anyActive = icons.any((i) => i.active);
    final lit = anyActive || opened;
    final bg = opened
        ? pink.withValues(alpha: 0.14)
        : night
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white;
    final border = lit
        ? pink
        : night
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFF0E2E9);
    // 꺼진 아이콘 색 — 켜진 것과 확실히 갈려야 "무엇이 걸렸나"가 읽힌다.
    final off = night ? Colors.white70 : Colors.black45;

    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, i) in icons.indexed) ...[
                  if (index > 0) const SizedBox(width: 7),
                  Icon(i.icon, size: 16, color: i.active ? pink : off),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [QuickConditionGroupButton] 안의 아이콘 하나 — 자기 조건이 걸렸는지만 안다.
@immutable
class QuickConditionIcon {
  final IconData icon;
  final bool active;

  const QuickConditionIcon({required this.icon, required this.active});
}
