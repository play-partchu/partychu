import 'package:flutter/material.dart';
import 'package:party_app/models/party_detail_theme_key.dart';

/// 파티 상세페이지(detailBlocks) 렌더러가 쓰는 색상 팔레트 — 각 위젯 파일에
/// 흩어져 있던 `_kAccent` 등 개별 색상 상수를 여기 하나로 모았다. 모델
/// 계층(`party_detail_theme_key.dart`)은 이 클래스를 모른다 — Firestore에는
/// [key]의 문자열 이름만 저장되고, 실제 팔레트는 항상 [PartyDetailThemeRegistry]가
/// 그 문자열로부터 다시 만들어낸다.
class PartyDetailThemeData {
  final PartyDetailThemeKey key;
  final String label;

  /// 에디터 미리보기 화면 전체 배경(실제 파티 상세화면의 핵심 정보 영역
  /// 배경은 이번 단계에서 테마 대상이 아니므로 건드리지 않는다).
  final Color pageBackground;

  /// 블록 콘텐츠를 감싸는 패널 배경 — 디자인 보기/사진만 보기에서 쓰인다.
  final Color sectionBackground;

  final Color primary;
  final Color secondary;
  final Color headingColor;
  final Color subheadingColor;
  final Color bodyColor;
  final Color mutedColor;
  final Color dividerColor;
  final Color noticeBackground;
  final Color noticeTextColor;
  final Color cardBackground;
  final Color cardBorder;
  final Color iconColor;
  final Color iconBackground;
  final Color timelineColor;
  final Color selectedTabBackground;
  final Color selectedTabForeground;
  final Color unselectedTabForeground;
  final Color tabTrackBackground;

  /// 카드형 요소(주의사항/FAQ/정보카드)에 줄 그림자 — 대부분 테마는 비워
  /// 두고("그림자 최소"), 러블리 테마만 은은한 그림자를 쓴다.
  final List<BoxShadow> cardShadow;

  /// 블록 사이 기본 간격 — "감성 미니멀"처럼 여백을 더 넓게 쓰는 테마를
  /// 위한 값(사진만 보기의 "사진 간격"도 이 값을 그대로 쓴다).
  final double contentGap;

  const PartyDetailThemeData({
    required this.key,
    required this.label,
    required this.pageBackground,
    required this.sectionBackground,
    required this.primary,
    required this.secondary,
    required this.headingColor,
    required this.subheadingColor,
    required this.bodyColor,
    required this.mutedColor,
    required this.dividerColor,
    required this.noticeBackground,
    required this.noticeTextColor,
    required this.cardBackground,
    required this.cardBorder,
    required this.iconColor,
    required this.iconBackground,
    required this.timelineColor,
    required this.selectedTabBackground,
    required this.selectedTabForeground,
    required this.unselectedTabForeground,
    required this.tabTrackBackground,
    this.cardShadow = const [],
    this.contentGap = 14,
  });
}

const _partychu = PartyDetailThemeData(
  key: PartyDetailThemeKey.partychu,
  label: 'PartyChu 기본',
  pageBackground: Color(0xFFFFFFFF),
  sectionBackground: Color(0xFFFFFFFF),
  primary: Color(0xFFFF6FA0),
  secondary: Color(0xFFFFB6C9),
  headingColor: Color(0xFF1A1A1A),
  subheadingColor: Color(0xFFFF6FA0),
  bodyColor: Color(0xFF333333),
  mutedColor: Color(0xFF8A8A8E),
  dividerColor: Color(0xFFE8EBF2),
  noticeBackground: Color(0xFFFFF3F7),
  noticeTextColor: Color(0xFFB23A63),
  cardBackground: Color(0xFFFAFAFC),
  cardBorder: Color(0xFFE8EBF2),
  iconColor: Color(0xFFFF6FA0),
  iconBackground: Color(0xFFFFF3F7),
  timelineColor: Color(0xFFFF6FA0),
  selectedTabBackground: Color(0xFFFF6FA0),
  selectedTabForeground: Colors.white,
  unselectedTabForeground: Color(0xFF6B6B70),
  tabTrackBackground: Color(0xFFF1F3F8),
);

const _lovely = PartyDetailThemeData(
  key: PartyDetailThemeKey.lovely,
  label: '러블리',
  pageBackground: Color(0xFFFFF6F2),
  sectionBackground: Color(0xFFFFF6F2),
  primary: Color(0xFFFF8FB1),
  secondary: Color(0xFFB9A7E6),
  headingColor: Color(0xFF4A3A45),
  subheadingColor: Color(0xFFB9A7E6),
  bodyColor: Color(0xFF5C4A54),
  mutedColor: Color(0xFF9C8A94),
  dividerColor: Color(0xFFF0DCE6),
  noticeBackground: Color(0xFFFFE8F0),
  noticeTextColor: Color(0xFFA85A7E),
  cardBackground: Color(0xFFFFFFFF),
  cardBorder: Color(0xFFF3D9E6),
  iconColor: Color(0xFFFF8FB1),
  iconBackground: Color(0xFFFFE3ED),
  timelineColor: Color(0xFFB9A7E6),
  selectedTabBackground: Color(0xFFFF8FB1),
  selectedTabForeground: Colors.white,
  unselectedTabForeground: Color(0xFF8A7480),
  tabTrackBackground: Color(0xFFFCEFF5),
  cardShadow: [
    BoxShadow(color: Color(0x1FB98CA8), blurRadius: 12, offset: Offset(0, 4)),
  ],
  contentGap: 16,
);

const _premiumDark = PartyDetailThemeData(
  key: PartyDetailThemeKey.premiumDark,
  label: '프리미엄 다크',
  pageBackground: Color(0xFF0F0F10),
  sectionBackground: Color(0xFF17171A),
  primary: Color(0xFFD4AF7A),
  secondary: Color(0xFFE8CBA0),
  headingColor: Colors.white,
  subheadingColor: Color(0xFFD4AF7A),
  bodyColor: Color(0xFFE7E7EA),
  mutedColor: Color(0xFFA8A8AE),
  dividerColor: Color(0xFF2C2C30),
  noticeBackground: Color(0xFF241F1A),
  noticeTextColor: Color(0xFFE8CBA0),
  cardBackground: Color(0xFF1D1D20),
  cardBorder: Color(0xFF2E2E33),
  iconColor: Color(0xFFD4AF7A),
  iconBackground: Color(0xFF2A241C),
  timelineColor: Color(0xFFD4AF7A),
  selectedTabBackground: Color(0xFFD4AF7A),
  selectedTabForeground: Color(0xFF0F0F10),
  unselectedTabForeground: Color(0xFFB7B7BD),
  tabTrackBackground: Color(0xFF1D1D20),
);

const _clubNeon = PartyDetailThemeData(
  key: PartyDetailThemeKey.clubNeon,
  label: '클럽 네온',
  pageBackground: Color(0xFF0A0A12),
  sectionBackground: Color(0xFF12121C),
  primary: Color(0xFFFF3DAE),
  secondary: Color(0xFF7B5CFF),
  headingColor: Colors.white,
  subheadingColor: Color(0xFFFF3DAE),
  bodyColor: Color(0xFFEDEDF2),
  mutedColor: Color(0xFFB0AEBB),
  dividerColor: Color(0xFF2A2A3C),
  noticeBackground: Color(0xFF1E1630),
  noticeTextColor: Color(0xFFCDB8FF),
  cardBackground: Color(0xFF161622),
  cardBorder: Color(0xFF35304A),
  // 아이콘에만 제한된 포인트 컬러 — 요구사항의 "과도한 그림자/글로우는
  // 피하고 제목·아이콘에만 제한"을 그림자 없이 색상만으로 표현한다.
  iconColor: Color(0xFF62E0FF),
  iconBackground: Color(0xFF1B2338),
  timelineColor: Color(0xFFFF3DAE),
  selectedTabBackground: Color(0xFFFF3DAE),
  selectedTabForeground: Colors.white,
  unselectedTabForeground: Color(0xFFA9A7B8),
  tabTrackBackground: Color(0xFF161622),
);

const _minimal = PartyDetailThemeData(
  key: PartyDetailThemeKey.minimal,
  label: '감성 미니멀',
  pageBackground: Color(0xFFFDFCFA),
  sectionBackground: Color(0xFFFDFCFA),
  primary: Color(0xFFA98F76),
  secondary: Color(0xFF8C8C86),
  headingColor: Color(0xFF2B2A28),
  subheadingColor: Color(0xFFA98F76),
  bodyColor: Color(0xFF4A4844),
  mutedColor: Color(0xFF9B968E),
  dividerColor: Color(0xFFE7E3DC),
  noticeBackground: Color(0xFFF3EFE8),
  noticeTextColor: Color(0xFF6B5D4F),
  cardBackground: Colors.white,
  cardBorder: Color(0xFFE7E3DC),
  iconColor: Color(0xFFA98F76),
  iconBackground: Color(0xFFF3EFE8),
  timelineColor: Color(0xFFA98F76),
  selectedTabBackground: Color(0xFFA98F76),
  selectedTabForeground: Colors.white,
  unselectedTabForeground: Color(0xFF8C8880),
  tabTrackBackground: Color(0xFFF6F4F0),
  contentGap: 20,
);

/// key 문자열 ↔ 팔레트 매핑. 모르는/손상된 키는 항상 [PartyDetailThemeKey.partychu]로.
class PartyDetailThemeRegistry {
  const PartyDetailThemeRegistry._();

  static const Map<PartyDetailThemeKey, PartyDetailThemeData> _all = {
    PartyDetailThemeKey.partychu: _partychu,
    PartyDetailThemeKey.lovely: _lovely,
    PartyDetailThemeKey.premiumDark: _premiumDark,
    PartyDetailThemeKey.clubNeon: _clubNeon,
    PartyDetailThemeKey.minimal: _minimal,
  };

  static PartyDetailThemeData fromKey(PartyDetailThemeKey key) =>
      _all[key] ?? _partychu;

  /// Firestore에서 읽어온 원시 문자열(또는 null)로부터 바로 팔레트를 만든다.
  static PartyDetailThemeData fromString(String? raw) =>
      fromKey(partyDetailThemeKeyFromString(raw));

  /// 에디터 테마 선택 카드 목록에 쓰는 전체 팔레트 리스트.
  static List<PartyDetailThemeData> get all =>
      _all.values.toList(growable: false);
}
