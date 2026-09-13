import 'package:flutter/material.dart';

/// PartyChu 앱 전체에서 공통으로 쓰는 브랜드 톤과 부품 모음.
///
/// 목표는 "귀엽지만 유치하지 않고, 사랑스럽지만 고급스러운 핑크 테마" —
/// 화면마다 핑크 색을 따로 고르거나 카드/버튼을 새로 그리지 않고, 이 파일의
/// 색상·위젯을 재사용해서 앱 전체가 같은 브랜드로 보이게 하는 것이 목적이다.
/// 고양이 발바닥(Icons.pets)을 반복되는 모티프로 써서 섹션 제목·빈 화면·
/// 버튼·구분선 등 곳곳에 자연스럽게 녹인다 — 아이콘 하나 붙이는 수준이
/// 아니라, 이 부품들을 여러 화면에서 그대로 재사용하는 것 자체가 통일감을
/// 만든다.
class PartyChuColors {
  PartyChuColors._();

  static const primary = Color(0xFFFF6FA0);
  static const primaryLight = Color(0xFFFF8FB3);
  static const primaryDeep = Color(0xFFE2568A);
  static const bg = Color(0xFFFFF7FA);
  static const surfaceTint = Color(0xFFFFF3F7);
  static const border = Color(0xFFFFDCE8);
  static const heading = Color(0xFF3A2E39);
  static const muted = Color(0xFF8C7A87);

  /// [muted]보다 한 단계 진한 보조 텍스트 색.
  ///
  /// 상세검색 필터의 "선택값" 줄처럼 **작지만 반드시 읽혀야 하는** 글자에 쓴다.
  /// muted는 힌트·부연설명용이라 작은 글자에 얹으면 흐려서 눈에 안 들어온다.
  static const subtleText = Color(0xFF6B5A66);
  static const neonPink = Color(0xFFFF2D95);
  static const neonPurple = Color(0xFFB026FF);

  /// 혜택·매장 이벤트 계열의 **은은한 골드**.
  ///
  /// 원래 이벤트 등록 화면 맨 위 "파티츄 오픈혜택" 안내
  /// ([PartychuEventPerkBanner])의 테두리 색이었다. 플레이스 상세의
  /// ✨ 매장 이벤트 카드도 같은 선을 두르므로, 같은 금색을 화면마다 다시
  /// 적지 않도록 값을 여기 한 곳에 모은다.
  ///
  /// 노란색이 아니라 **샴페인 골드**다 — 카드가 번쩍이지 않고 "이건 이벤트
  /// 카드"라는 것만 알아볼 정도로만 선다.
  static const eventGold = Color(0xFFF2D79B);

  /// [eventGold]와 짝이 되는 아주 옅은 금색 바탕.
  static const eventGoldBg = Color(0xFFFFF9EC);
}

/// 프로젝트 전체에서 "제목"에만 쓰는 커스텀 폰트 — 본문/설명/버튼/입력창
/// 등 일반 텍스트는 시스템 기본 폰트를 그대로 쓰고, AppBar/다이얼로그/섹션
/// 제목/카드 제목처럼 "제목" 역할을 하는 텍스트에만 이 폰트를 적용한다.
/// 폰트 파일이 Light(300)/Medium(500) 두 굵기만 있어서, 제목은 기본적으로
/// medium을 쓰고 강조가 필요 없는 일반 제목에만 light를 쓴다.
class PartyChuTitleFont {
  PartyChuTitleFont._();

  static const family = 'SeoulHangang';
  static const medium = FontWeight.w500;
  static const light = FontWeight.w300;
}

/// 발바닥 모티프가 들어간 작은 섹션 제목 — "환불 규정", "상세 설명"처럼
/// 화면 곳곳의 소제목에 반복해서 쓴다. sparkle을 켜면 끝에 작은 반짝임을
/// 더해 강조 섹션에 쓸 수 있다.
class PawSectionTitle extends StatelessWidget {
  final String text;
  final Color color;
  final double fontSize;
  final bool sparkle;

  const PawSectionTitle(
    this.text, {
    super.key,
    this.color = PartyChuColors.primary,
    this.fontSize = 15,
    this.sparkle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.pets, size: fontSize - 1, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontFamily: PartyChuTitleFont.family,
            fontSize: fontSize,
            fontWeight: PartyChuTitleFont.medium,
            color: PartyChuColors.heading,
            shadows: const [
              Shadow(color: PartyChuColors.heading, offset: Offset(0.3, 0)),
              Shadow(color: PartyChuColors.heading, offset: Offset(-0.3, 0)),
              Shadow(color: PartyChuColors.heading, offset: Offset(0, 0.3)),
              Shadow(color: PartyChuColors.heading, offset: Offset(0, -0.3)),
            ],
          ),
        ),
        if (sparkle) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.auto_awesome,
            size: fontSize - 3,
            color: color.withValues(alpha: 0.7),
          ),
        ],
      ],
    );
  }
}

/// 발바닥 장식이 가운데 박힌 얇은 구분선 — 기본 Divider보다 훨씬 PartyChu
/// 다운 느낌을 준다. 좌우 그라데이션 선 + 가운데 작은 발바닥 아이콘.
class PawDivider extends StatelessWidget {
  final double verticalPadding;

  const PawDivider({super.key, this.verticalPadding = 16});

  @override
  Widget build(BuildContext context) {
    Widget line() => Expanded(
      child: Container(
        height: 1.2,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              PartyChuColors.border.withValues(alpha: 0),
              PartyChuColors.border,
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Row(
        children: [
          line(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              Icons.pets,
              size: 13,
              color: PartyChuColors.primary.withValues(alpha: 0.55),
            ),
          ),
          Transform.flip(flipX: true, child: line()),
        ],
      ),
    );
  }
}

/// 정보 한 줄 앞에 붙는 동그란 아이콘 배지 — 맨 아이콘 하나만 덩그러니
/// 있는 것보다 훨씬 카드다운 입체감을 준다.
class PartyChuIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const PartyChuIconBadge(
    this.icon, {
    super.key,
    this.color = PartyChuColors.primary,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: size * 0.52, color: color),
    );
  }
}

/// "Pearl Marble Gloss Card" — 단순 반투명 글래스모피즘이 아니라, 우유빛
/// 대리석 원석을 은은하게 진주 코팅한 듯한 화이트 카드. 5개 레이어를
/// Stack으로 쌓아 만든다(아래부터): ①우유빛 흰색 바탕 → ②아주 흐린
/// 대리석 결(고정된 3개의 곡선, 카드마다 랜덤 없이 항상 같은 패턴) →
/// ③카드 상단부에 넓게 걸리는 진주광택(Pearl Gloss) → ④작은 별빛 반짝임
/// 1~2개 → ⑤좌상단은 밝고 우하단은 옅은 핑크로 지는 대각선 유광 테두리.
/// 그림자는 무거운 회색 대신 아래쪽 연핑크 soft shadow + 위쪽 흰색 glow로
/// "살짝 떠 있는" 느낌만 낸다. 앱 곳곳의 "정보 카드"가 전부 이 스타일
/// 하나로 통일되도록 재사용한다.
class PartyChuCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const PartyChuCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(26),
    this.radius = 28,
  });

  /// 한두 줄짜리 안내용 — 테두리·그림자·핑크 톤은 그대로 두고 **안쪽 여백만**
  /// 줄인 카드다.
  ///
  /// 기본 여백(사방 26)은 본문이 여러 줄인 카드(환불 규정 등)에 맞춘 값이라,
  /// 얼리버드 안내처럼 내용이 한두 줄인 곳에서는 글자보다 여백이 더 커 보였다.
  /// 내용 높이는 Column이 이미 알아서 줄이므로, 여백만 줄이면 카드가 내용
  /// 높이에 맞게 붙는다.
  const PartyChuCard.compact({
    super.key,
    required this.child,
    this.padding = compactPadding,
    this.radius = compactRadius,
  });

  static const EdgeInsets compactPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 12,
  );
  static const double compactRadius = 18;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: PartyChuColors.primaryLight.withValues(alpha: 0.5),
          width: 1.8,
        ),
        boxShadow: [
          // 아래쪽 연핑크 soft shadow — 무거운 회색 그림자 대신.
          BoxShadow(
            color: PartyChuColors.primaryLight.withValues(alpha: 0.16),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
          // 카드 전체를 감싸는 아주 약한 흰색 glow.
          BoxShadow(color: Colors.white.withValues(alpha: 0.6), blurRadius: 16),
        ],
      ),
      child: child,
    );
  }
}

/// "아직 없어요" 류의 빈 화면을 앱 전체에서 같은 모양으로 통일하는 공통
/// 위젯 — 신청자 목록, 찜 목록 등에서 재사용한다. 텅 빈 회색 아이콘 대신
/// 옅은 핑크 원 배지 안에 발바닥을 넣어 PartyChu다운 느낌을 준다.
class PawEmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;

  const PawEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.pets_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: PartyChuColors.surfaceTint,
              shape: BoxShape.circle,
              border: Border.all(color: PartyChuColors.border, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 34, color: PartyChuColors.primary),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: PartyChuColors.heading,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: PartyChuColors.muted,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 앱 전체의 "메인 액션" 버튼 — 신청자 목록 보기, 신청하기처럼 화면에서
/// 가장 누르길 바라는 자리에 공통으로 쓴다. 단색 그라데이션에서 한 단계
/// 더 나아가 위쪽에 살짝 유광 하이라이트를 얹고, 왼쪽엔 흰 원 배지 안에
/// 발바닥을 넣어 "브랜드 배지"처럼 보이게 했다. 누르면 살짝 눌리는 스케일
/// 애니메이션 + 그림자가 낮아지는 효과로 촉각적인 "누르고 싶다"는 느낌을
/// 준다.
class PartyChuPrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData badgeIcon;
  final double height;
  final bool showSparkle;
  final bool showBadge;

  const PartyChuPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.badgeIcon = Icons.pets,
    this.height = 60,
    this.showSparkle = true,
    this.showBadge = true,
  });

  @override
  State<PartyChuPrimaryButton> createState() => _PartyChuPrimaryButtonState();
}

class _PartyChuPrimaryButtonState extends State<PartyChuPrimaryButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.onTap == null) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SizedBox(
          width: double.infinity,
          height: widget.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: disabled
                  ? const LinearGradient(
                      colors: [Color(0xFFE0E0E0), Color(0xFFD6D6D6)],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        PartyChuColors.primary,
                        PartyChuColors.primaryLight,
                      ],
                    ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: disabled
                  ? const []
                  : [
                      BoxShadow(
                        color: PartyChuColors.primary.withValues(
                          alpha: _pressed ? 0.25 : 0.4,
                        ),
                        blurRadius: _pressed ? 10 : 20,
                        offset: Offset(0, _pressed ? 3 : 8),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  // 위쪽 유광 하이라이트 — 단색 그라데이션이 밋밋해 보이지
                  // 않도록 얇은 반투명 흰 띠를 얹어 입체감을 준다.
                  if (!disabled)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: widget.height * 0.42,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.22),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.showBadge) ...[
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(
                                alpha: disabled ? 0.7 : 1,
                              ),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              widget.badgeIcon,
                              size: 16,
                              color: disabled
                                  ? Colors.black38
                                  : PartyChuColors.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: disabled ? Colors.black45 : Colors.white,
                          ),
                        ),
                        if (widget.showSparkle && !disabled) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.auto_awesome,
                            color: Colors.white70,
                            size: 15,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
