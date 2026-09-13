import 'package:party_app/models/party_detail_decoration_intensity.dart';
import 'package:party_app/models/party_detail_theme_key.dart';

/// "간편 자동 꾸미기"(`PartyDescriptionMode.auto`) 선택 시의 스타일 설정 —
/// Firestore `parties.autoDescriptionStyle`에 저장된다. 소개글 원문
/// (`description`)은 절대 건드리지 않고, 이 값들로 렌더링만 바꾼다.
///
/// [variantSeed]는 "다시 꾸미기"가 바꾸는 값이고, [paragraphStyles]는 문단별
/// 탭 편집이 저장한 스타일/이모지 오버라이드 목록이다(`{'key','category',
/// 'emoji','emojiRemoved'}`) — `auto_description_classifier.dart`의
/// `classifyDescriptionToBlocks`가 렌더링 시점에 이 값을 읽어 반영한다.
class PartyAutoDescriptionStyle {
  final PartyDetailThemeKey theme;
  final PartyDetailDecorationIntensity intensity;
  final int variantSeed;
  final List<Map<String, dynamic>> paragraphStyles;

  const PartyAutoDescriptionStyle({
    this.theme = PartyDetailThemeKey.partychu,
    this.intensity = PartyDetailDecorationIntensity.standard,
    this.variantSeed = 0,
    this.paragraphStyles = const [],
  });

  factory PartyAutoDescriptionStyle.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const PartyAutoDescriptionStyle();
    return PartyAutoDescriptionStyle(
      theme: partyDetailThemeKeyFromString(m['theme'] as String?),
      intensity: partyDetailDecorationIntensityFromString(
        m['intensity'] as String?,
      ),
      variantSeed: (m['variantSeed'] as num?)?.toInt() ?? 0,
      paragraphStyles:
          (m['paragraphStyles'] as List?)?.cast<Map<String, dynamic>>() ??
          const [],
    );
  }

  Map<String, dynamic> toMap() => {
    'theme': theme.name,
    'intensity': intensity.name,
    'variantSeed': variantSeed,
    'paragraphStyles': paragraphStyles,
  };

  PartyAutoDescriptionStyle copyWith({
    PartyDetailThemeKey? theme,
    PartyDetailDecorationIntensity? intensity,
    int? variantSeed,
    List<Map<String, dynamic>>? paragraphStyles,
  }) {
    return PartyAutoDescriptionStyle(
      theme: theme ?? this.theme,
      intensity: intensity ?? this.intensity,
      variantSeed: variantSeed ?? this.variantSeed,
      paragraphStyles: paragraphStyles ?? this.paragraphStyles,
    );
  }
}
