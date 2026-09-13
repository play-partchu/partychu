import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:party_app/models/party_detail_decoration_intensity.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/widgets/party_detail_theme.dart';

/// 블록형 상세페이지 "자동 꾸미기" — 배경 장식/사진 카드 프레임/블록 구분
/// 장식을 테마·강도(`PartyDetailDecorationIntensity`)에 따라 그린다.
///
/// 글/사진 내용은 절대 바꾸지 않는다 — 여기 위젯들은 항상 이미 완성된
/// 콘텐츠 위젯을 감싸거나(`PartyDetailPhotoFrame`), 콘텐츠와 무관한 순수
/// 장식 레이어만 그린다(`PartyDetailSectionBackground`,
/// `PartyDetailBlockSeparator`). 새 텍스트를 생성하지 않는다.
///
/// 배치는 완전히 랜덤이 아니라 [seed] 하나로 결정되는 `math.Random(seed)`
/// 시드 기반이라, 같은 파티는 새로고침해도 항상 같은 장식 배치를 보여준다
/// (`PartyDetailBlockPreview`가 partyId+blockId로 이 seed를 계산한다).

// ── 테마별 장식 프리셋 ────────────────────────────────────────────────────────
// 색상은 최대한 기존 `PartyDetailThemeData`(primary/secondary/card*)에서
// 그대로 파생시켜, 테마 색상 체계와 어긋나지 않게 한다. 배경 그라데이션만
// 팔레트에 없는 다단 그라데이션이라 프리셋에서 직접 정의한다.
class _DecorationPreset {
  final List<Color> backgroundGradient;
  final List<Color> glowColors;
  final Color ornamentColor;
  final List<IconData> ornamentIcons;
  final Color separatorColor;
  final Color photoCardBackground;
  final Color photoCardBorder;
  final Color photoAccent;
  final Color photoShadowColor;

  /// 감성 미니멀 전용 — standard에서도 블롭/장식 아이콘을 켜지 않고 옅은
  /// 그라데이션만 쓴다(테마 정체성 유지).
  final bool restrained;

  /// 클럽 네온 전용 — 기존 테마가 "그림자 없이 색상만"을 지향하므로 사진
  /// 카드에도 그림자를 넣지 않는다.
  final bool noShadow;

  const _DecorationPreset({
    required this.backgroundGradient,
    required this.glowColors,
    required this.ornamentColor,
    required this.ornamentIcons,
    required this.separatorColor,
    required this.photoCardBackground,
    required this.photoCardBorder,
    required this.photoAccent,
    required this.photoShadowColor,
    this.restrained = false,
    this.noShadow = false,
  });
}

_DecorationPreset _presetFor(PartyDetailThemeKey key) {
  final palette = PartyDetailThemeRegistry.fromKey(key);
  switch (key) {
    case PartyDetailThemeKey.partychu:
      return _DecorationPreset(
        backgroundGradient: const [Color(0xFFFFFFFF), Color(0xFFFFF3F7)],
        glowColors: [palette.primary, palette.secondary],
        ornamentColor: palette.primary,
        ornamentIcons: const [
          Icons.auto_awesome,
          Icons.favorite,
          Icons.star_rounded,
        ],
        separatorColor: palette.primary,
        photoCardBackground: Colors.white,
        photoCardBorder: palette.primary.withValues(alpha: 0.25),
        photoAccent: palette.primary,
        photoShadowColor: Colors.black.withValues(alpha: 0.08),
      );
    case PartyDetailThemeKey.lovely:
      return _DecorationPreset(
        backgroundGradient: const [
          Color(0xFFFFFBF7),
          Color(0xFFFFF0F5),
          Color(0xFFF5F0FF),
        ],
        glowColors: [palette.primary, palette.secondary],
        ornamentColor: palette.primary,
        ornamentIcons: const [
          Icons.favorite,
          Icons.auto_awesome,
          Icons.favorite_border,
        ],
        separatorColor: palette.secondary,
        photoCardBackground: Colors.white,
        photoCardBorder: palette.secondary.withValues(alpha: 0.3),
        photoAccent: palette.secondary,
        photoShadowColor: const Color(0x1FB98CA8),
      );
    case PartyDetailThemeKey.premiumDark:
      return _DecorationPreset(
        backgroundGradient: const [
          Color(0xFF0F0F10),
          Color(0xFF17171A),
          Color(0xFF1A1620),
        ],
        glowColors: [palette.primary],
        ornamentColor: palette.primary,
        ornamentIcons: const [Icons.auto_awesome],
        separatorColor: palette.primary,
        photoCardBackground: palette.cardBackground,
        photoCardBorder: palette.primary.withValues(alpha: 0.28),
        photoAccent: palette.primary,
        photoShadowColor: palette.primary.withValues(alpha: 0.12),
      );
    case PartyDetailThemeKey.clubNeon:
      return _DecorationPreset(
        backgroundGradient: const [
          Color(0xFF0A0A12),
          Color(0xFF15111F),
          Color(0xFF12121C),
        ],
        glowColors: [palette.primary, palette.secondary],
        ornamentColor: palette.iconColor,
        ornamentIcons: const [Icons.auto_awesome, Icons.star_rounded],
        separatorColor: palette.secondary,
        photoCardBackground: palette.cardBackground,
        photoCardBorder: palette.primary.withValues(alpha: 0.35),
        photoAccent: palette.primary,
        photoShadowColor: Colors.transparent,
        noShadow: true,
      );
    case PartyDetailThemeKey.minimal:
      return _DecorationPreset(
        backgroundGradient: const [Color(0xFFFDFCFA), Color(0xFFF8F4EE)],
        glowColors: [palette.primary],
        ornamentColor: palette.primary,
        ornamentIcons: const [Icons.auto_awesome],
        separatorColor: palette.dividerColor,
        photoCardBackground: Colors.white,
        photoCardBorder: palette.dividerColor,
        photoAccent: palette.primary.withValues(alpha: 0.7),
        photoShadowColor: Colors.black.withValues(alpha: 0.05),
        restrained: true,
      );
  }
}

// ── 1. 배경 장식 ──────────────────────────────────────────────────────────
class PartyDetailSectionBackground extends StatelessWidget {
  final PartyDetailThemeKey theme;
  final PartyDetailDecorationIntensity intensity;
  final int seed;

  const PartyDetailSectionBackground({
    super.key,
    required this.theme,
    required this.intensity,
    required this.seed,
  });

  @override
  Widget build(BuildContext context) {
    final preset = _presetFor(theme);
    final palette = PartyDetailThemeRegistry.fromKey(theme);

    if (intensity == PartyDetailDecorationIntensity.simple) {
      return ColoredBox(color: palette.sectionBackground);
    }

    final gradient = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: preset.backgroundGradient,
      ),
    );

    // 감성 미니멀은 standard에서 옅은 그라데이션만 — rich를 골라야 절제된
    // 수준의 블롭 1개 정도만 추가로 켠다.
    final showBlobsAndOrnaments =
        !preset.restrained || intensity == PartyDetailDecorationIntensity.rich;
    if (!showBlobsAndOrnaments) {
      return DecoratedBox(decoration: gradient);
    }

    final rng = math.Random(seed);
    final blobCount = preset.restrained
        ? 1
        : (intensity == PartyDetailDecorationIntensity.rich ? 3 : 2);
    final ornamentCount = preset.restrained
        ? 2
        : (intensity == PartyDetailDecorationIntensity.rich ? 8 : 4);

    return IgnorePointer(
      child: DecoratedBox(
        decoration: gradient,
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < blobCount; i++)
              _glowBlob(rng, preset.glowColors[i % preset.glowColors.length]),
            for (var i = 0; i < ornamentCount; i++) _ornament(rng, preset),
          ],
        ),
      ),
    );
  }

  Widget _glowBlob(math.Random rng, Color color) {
    final size = 120.0 + rng.nextDouble() * 100;
    final dx = rng.nextDouble() * 2 - 1;
    final dy = rng.nextDouble() * 2 - 1;
    return Align(
      alignment: Alignment(dx, dy),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }

  Widget _ornament(math.Random rng, _DecorationPreset preset) {
    final icon = preset.ornamentIcons[rng.nextInt(preset.ornamentIcons.length)];
    final dx = rng.nextDouble() * 2 - 1;
    final dy = rng.nextDouble() * 2 - 1;
    final size = 12.0 + rng.nextDouble() * 10;
    final alpha = 0.12 + rng.nextDouble() * 0.14;
    return Align(
      alignment: Alignment(dx, dy),
      child: Icon(
        icon,
        size: size,
        color: preset.ornamentColor.withValues(alpha: alpha),
      ),
    );
  }
}

// ── 2. 사진 카드 프레임 ───────────────────────────────────────────────────
class PartyDetailPhotoFrame extends StatelessWidget {
  final PartyDetailThemeKey theme;
  final PartyDetailDecorationIntensity intensity;

  /// 첫 번째 사진 블록 — 대표 비주얼처럼 강조한다(가장자리 여백을 없애
  /// 다른 사진 카드보다 넓어 보이게 하고, 프레임/그라데이션을 더 준다).
  /// 크롭 좌표계(4:5)와 어긋나지 않도록 가로세로 비율 자체는 바꾸지 않는다.
  final bool isHero;

  /// 이미 크롭(위치/배율) 적용까지 끝난 최종 이미지 위젯.
  final Widget child;

  const PartyDetailPhotoFrame({
    super.key,
    required this.theme,
    required this.intensity,
    required this.child,
    this.isHero = false,
  });

  @override
  Widget build(BuildContext context) {
    final preset = _presetFor(theme);
    final radius = isHero ? 20.0 : 14.0;
    final showShadow =
        intensity != PartyDetailDecorationIntensity.simple && !preset.noShadow;
    final showBottomScrim =
        isHero && intensity != PartyDetailDecorationIntensity.simple;
    final showSparkle =
        isHero &&
        intensity == PartyDetailDecorationIntensity.rich &&
        !preset.restrained;

    final card = Container(
      decoration: BoxDecoration(
        color: preset.photoCardBackground,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: preset.photoCardBorder,
          width: isHero ? 1.5 : 1,
        ),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: preset.photoShadowColor,
                  blurRadius: isHero ? 24 : 14,
                  offset: Offset(0, isHero ? 10 : 5),
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(radius - 3),
            ),
            child: Stack(
              children: [
                child,
                if (showBottomScrim)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.32),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showSparkle)
                  Positioned(
                    right: 14,
                    top: 14,
                    child: IgnorePointer(
                      child: Icon(
                        Icons.auto_awesome,
                        size: 20,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            height: isHero ? 5 : 3,
            decoration: BoxDecoration(
              color: preset.photoAccent,
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(radius - 3),
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isHero ? 0 : 8),
      child: card,
    );
  }
}

// ── 3. 블록 사이 구분 장식 ─────────────────────────────────────────────────
class PartyDetailBlockSeparator extends StatelessWidget {
  final PartyDetailThemeKey theme;
  final PartyDetailDecorationIntensity intensity;
  final int seed;

  const PartyDetailBlockSeparator({
    super.key,
    required this.theme,
    required this.intensity,
    required this.seed,
  });

  @override
  Widget build(BuildContext context) {
    final preset = _presetFor(theme);
    final rng = math.Random(seed);
    // 감성 미니멀은 아이콘 장식 없이 항상 얇은 선만.
    final variant = preset.restrained ? 0 : rng.nextInt(3);

    switch (variant) {
      case 1:
        final icons = preset.ornamentIcons;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  icons[(seed + i) % icons.length],
                  size: i == 1 ? 14 : 10,
                  color: preset.ornamentColor.withValues(alpha: 0.55),
                ),
              ),
          ],
        );
      case 2:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 9; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: preset.separatorColor.withValues(alpha: 0.45),
                  ),
                ),
              ),
          ],
        );
      default:
        return Center(
          child: Container(
            width: 72,
            height: intensity == PartyDetailDecorationIntensity.rich ? 3 : 2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  preset.separatorColor.withValues(
                    alpha: preset.restrained ? 0.6 : 0.45,
                  ),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        );
    }
  }
}
