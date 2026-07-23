import 'package:party_app/models/party_detail_block.dart';
import 'package:party_app/models/region_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
// "간편 자동 꾸미기" 문단 자동 분석 — 소개글(description) 원문을 분석해
// **저장되지 않는 합성(synthetic) PartyDetailBlock 리스트**를 만든다.
// 매 렌더링(미리보기/실제 상세화면)마다 이 함수를 다시 호출할 뿐, 결과를
// Firestore에 쓰지 않는다 — 원문은 절대 바뀌지 않고, 이모지가 붙은 문자열은
// 이 합성 블록 안에서만 잠깐 존재했다가 사라진다.
//
// 새 카드 위젯을 만들지 않고 기존 8종 블록 렌더러(PartyDetailBlockPreview)를
// 그대로 재사용한다 — 분류 결과를 heading/subheading/paragraph/notice/
// checklist/infoCard 같은 기존 payload로 감싸기만 한다.
//
// **줄(line) 단위로 분류한다** — 날짜/장소/가격/주의/마감처럼 특정 키워드에
// 매칭되는 줄은 그 줄 하나만 바로 전용 카드가 되고, 나머지("일반") 줄들은
// 연속된 구간끼리만 모아서 배너/아이콘 리스트/본문 카드로 묶는다.
//
// 문단별 탭 편집(`paragraph_style_edit_sheet.dart`)이 저장한 오버라이드를
// **줄 원문 내용 기반 키**(`_keyFor`)로 다시 매칭한다 — 사용자가 그 줄을
// 편집하지 않는 한 항상 같은 키를 받고, 텍스트가 바뀌면 오버라이드는 조용히
// 안 걸리게 될 뿐(엉뚱한 줄에 잘못 적용되는 사고 방지).
// ─────────────────────────────────────────────────────────────────────────────

/// 문단 자동 분류 카테고리 — 편집 시트(`paragraph_style_edit_sheet.dart`)의
/// "스타일 변경" 선택지와 1:1로 대응한다.
enum AutoDescriptionCategory {
  date,
  location,
  price,
  caution,
  deadline,
  banner,
  iconList,
  bodyCard,
}

const _kCategoryLabels = {
  AutoDescriptionCategory.date: '일정',
  AutoDescriptionCategory.location: '장소',
  AutoDescriptionCategory.price: '혜택',
  AutoDescriptionCategory.caution: '주의',
  AutoDescriptionCategory.deadline: '마감',
  AutoDescriptionCategory.banner: '배너',
  AutoDescriptionCategory.iconList: '리스트',
  AutoDescriptionCategory.bodyCard: '본문',
};

String autoDescriptionCategoryLabel(AutoDescriptionCategory category) =>
    _kCategoryLabels[category]!;

AutoDescriptionCategory? _categoryFromWire(String? raw) {
  for (final c in AutoDescriptionCategory.values) {
    if (c.name == raw) return c;
  }
  return null;
}

const _kShortLineMaxLength = 18;

final _kDateTimePattern = RegExp(
  r'\d{1,2}\s*[./]\s*\d{1,2}|\d{1,2}\s*시|오전|오후|요일|매주|평일|주말',
);
final _kLocationPattern = RegExp(
  r'장소|위치|주소|오시는\s*길|찾아오시는|[가-힣]+(동|로|길)\s*\d',
);
final _kPricePattern = RegExp(
  r'\d[,\d]*\s*원|₩|%|할인|무료|참가비|입장료|가격',
);
final _kCautionPattern = RegExp(r'주의|필독|안내사항|참고사항|유의');
final _kDeadlinePattern = RegExp(r'마감|선착순|매진|마지막');

const _kEmojiPools = {
  AutoDescriptionCategory.date: ['📅', '🗓️', '⏰'],
  AutoDescriptionCategory.location: ['📍', '🗺️'],
  AutoDescriptionCategory.price: ['💰', '🎟️', '💳'],
  AutoDescriptionCategory.caution: ['⚠️', '❗', '📌'],
  AutoDescriptionCategory.deadline: ['🔥', '⏰', '🎯'],
  AutoDescriptionCategory.banner: ['💗', '✨', '🎉', '🌸', '💫'],
  AutoDescriptionCategory.iconList: ['💗', '✨', '🎉', '🌸', '💫'],
  AutoDescriptionCategory.bodyCard: <String>[], // 긴 본문은 이모지 없음
};

/// 편집 시트가 카테고리별로 고를 수 있는 이모지 후보(공개) — "이모지 없음"
/// 옵션은 시트 쪽에서 별도로 추가한다.
List<String> autoDescriptionEmojiPool(AutoDescriptionCategory category) =>
    _kEmojiPools[category] ?? const [];

// ── "화려하게" 전용 어휘 사전 ─────────────────────────────────────────────
// 이모지 풀 확장(인라인 본문 장식 포함)과 키워드 배지 추출이 같은 사전을
// 공유한다 — 두 기능이 서로 다른 목록을 관리하면 어긋날 수 있어서다.
// 리스트 순서가 매칭 우선순위다 — 구체적인 표현(와인파티)을 일반적인
// 표현(파티)보다 먼저 둬서, "와인파티"가 "파티"로 뭉뚱그려지지 않게 한다.
class _VibeKeyword {
  final List<String> triggers;
  final String emoji;
  const _VibeKeyword(this.triggers, this.emoji);
}

const _kVibeKeywords = [
  _VibeKeyword(['와인파티'], '🍷'),
  _VibeKeyword(['생일파티', '생일'], '🎂'),
  _VibeKeyword(['클럽파티', '클럽'], '🍾'),
  _VibeKeyword(['소개팅'], '💕'),
  _VibeKeyword(['댄스파티', '댄스', '춤'], '💃'),
  _VibeKeyword(['술자리', '음주', '술'], '🍻'),
  _VibeKeyword(['음악', 'DJ', '디제잉'], '🎵'),
  _VibeKeyword(['초보환영', '초보가능'], '😊'),
  _VibeKeyword(['환영'], '❤️'),
  _VibeKeyword(['추천'], '✨'),
  _VibeKeyword(['인기'], '🔥'),
  _VibeKeyword(['모임'], '🥂'),
  _VibeKeyword(['파티'], '🎉'),
];

const _kDayTimeKeywords = [
  '월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일',
  '평일', '주말', '오늘', '내일',
];

/// 공식 구/시/군 목록(`RegionData`)에는 없는, 파티 소개글에 훨씬 자주
/// 쓰이는 번화가 콜로키얼 명칭 — 키워드 배지의 "장소" 매칭에서 공식
/// 행정구역보다 먼저 확인한다.
const _kColloquialNeighborhoods = [
  '홍대', '이태원', '강남', '건대', '신촌', '성수', '압구정', '가로수길',
  '한남동', '여의도', '잠실', '신사', '청담', '명동',
];

/// [text] 안에서 매칭되는 어휘 그룹을 우선순위(리스트 순서) 그대로 찾아
/// (매칭된 원문 그대로의 단어, 이모지) 쌍 리스트로 돌려준다. 그룹당 가장
/// 먼저 매칭되는 표현 하나만 채택한다(예: "생일파티"면 "생일파티"가 통째로
/// 매칭되지 "생일"만 따로 잡히지 않는다). 서로 다른 그룹끼리 겹치는 경우도
/// 걸러낸다 — 예: "와인파티"가 와인파티 그룹으로 잡히면, 그 부분 문자열에
/// 불과한 일반 "파티" 그룹은 중복 정보이므로 결과에서 제외한다.
List<(String, String)> _findVibeMatches(String text) {
  final raw = <(String, String)>[];
  for (final group in _kVibeKeywords) {
    for (final trigger in group.triggers) {
      if (text.contains(trigger)) {
        raw.add((trigger, group.emoji));
        break;
      }
    }
  }
  return [
    for (final m in raw)
      if (!raw.any((other) => other.$1 != m.$1 && other.$1.contains(m.$1)))
        m,
  ];
}

/// 카테고리별 이모지 풀 — "화려하게"(rich)일 때만 banner/iconList 풀에
/// 어휘 사전 이모지를 추가로 합친다(교체 아님 — simple/standard는 항상
/// 기존 풀 그대로).
List<String> _poolFor(AutoDescriptionCategory category, bool rich) {
  final base = autoDescriptionEmojiPool(category);
  if (!rich) return base;
  if (category != AutoDescriptionCategory.banner &&
      category != AutoDescriptionCategory.iconList) {
    return base;
  }
  final merged = [...base];
  for (final v in _kVibeKeywords) {
    if (!merged.contains(v.emoji)) merged.add(v.emoji);
  }
  return merged;
}

String _pick(List<String> pool, int seed) => pool[seed.abs() % pool.length];

String _wrap(String text, String? emoji) => emoji == null ? text : '$emoji $text $emoji';

/// 본문(bodyCard) 문단에 어휘 이모지를 최대 2개까지 단어 바로 뒤에
/// 삽입한다(원문 삭제/치환 없이 순수 삽입만) — "화려하게"일 때만, 그 외에는
/// 원문을 그대로 돌려준다(기존 "긴 본문은 이모지 없음" 규칙 유지).
/// [seed]가 바뀌면(variantSeed, "다시 꾸미기") 매칭된 후보가 여러 개일 때
/// 어떤 2개가 뽑히는지도 함께 바뀐다.
String _decorateInline(String text, {required bool rich, required int seed}) {
  if (!rich) return text;
  final matches = _findVibeMatches(text);
  if (matches.isEmpty) return text;
  final ordered = List<(String, String)>.of(matches);
  if (ordered.length > 1) {
    final swapIdx = seed.abs() % ordered.length;
    if (swapIdx != 0) {
      final tmp = ordered[0];
      ordered[0] = ordered[swapIdx];
      ordered[swapIdx] = tmp;
    }
  }
  var result = text;
  for (final (trigger, emoji) in ordered.take(2)) {
    final idx = result.indexOf(trigger);
    if (idx == -1) continue;
    final insertAt = idx + trigger.length;
    result = result.replaceRange(insertAt, insertAt, ' $emoji');
  }
  return result;
}

/// 소개글 원문에서 핵심 키워드(파티 종류/장소/요일 등)만 규칙 기반으로
/// 추출한다 — AI 생성이 아니라 원문에 이미 있는 단어만 그대로 뽑아 상단
/// 배지로 보여주기 위한 용도. "화려하게" 강도에서만 호출부에서 사용한다.
/// variantSeed를 받지 않는다 — "다시 꾸미기"로 재계산되지 않는, 원문
/// 내용의 결정적 반영이기 때문이다(장식 선택이 아님).
List<({String emoji, String label})> extractAutoDescriptionKeywords(String description) {
  final badges = <({String emoji, String label})>[];
  final seenLabels = <String>{};

  void addBadge(String emoji, String label) {
    if (seenLabels.contains(label)) return;
    seenLabels.add(label);
    badges.add((emoji: emoji, label: label));
  }

  // 1) 어휘(파티 종류/분위기) — 가장 구체적인 표현부터.
  final vibeMatches = _findVibeMatches(description);
  if (vibeMatches.isNotEmpty) {
    final (text, emoji) = vibeMatches.first;
    addBadge(emoji, text);
  }

  // 2) 장소 — 번화가 콜로키얼 명칭 우선, 없으면 공식 구/시/군으로 폴백.
  String? location;
  for (final n in _kColloquialNeighborhoods) {
    if (description.contains(n)) {
      location = n;
      break;
    }
  }
  if (location == null) {
    outer:
    for (final districts in RegionData.regionDistricts.values) {
      for (final d in districts) {
        if (description.contains(d)) {
          location = d;
          break outer;
        }
      }
    }
  }
  if (location != null) addBadge('📍', location);

  // 3) 요일/시점.
  for (final d in _kDayTimeKeywords) {
    if (description.contains(d)) {
      addBadge('🌙', d);
      break;
    }
  }

  // 4) 두 번째로 매칭된 어휘(보조) — 1)에서 쓰인 것과 다른 그룹이면 배지로.
  if (vibeMatches.length > 1) {
    final (text, emoji) = vibeMatches[1];
    addBadge(emoji, text);
  }

  return badges.length > 4 ? badges.sublist(0, 4) : badges;
}

/// 줄 원문 → 오버라이드 매칭용 안정 키. 같은 텍스트는 항상 같은 키.
String _keyFor(String text) => 'auto-${text.hashCode}';

/// 소개글을 자동 분석해 합성 블록 리스트로 바꾼다. 빈 문자열이면 빈 리스트.
/// [variantSeed]가 바뀌면 분류(카테고리)는 그대로 유지한 채 이모지 선택만
/// 달라진다("다시 꾸미기"). [paragraphStyles]는 문단별 탭 편집으로 저장된
/// 오버라이드 목록(`{'key','category','emoji','emojiRemoved'}`) — 매칭되는
/// 줄이 있으면 자동 분류 대신 그 값을 쓴다.
List<PartyDetailBlock> classifyDescriptionToBlocks(
  String description, {
  int variantSeed = 0,
  List<Map<String, dynamic>> paragraphStyles = const [],
  bool rich = false,
}) {
  final lines = description
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return [];

  final overrides = <String, Map<String, dynamic>>{
    for (final o in paragraphStyles)
      if (o['key'] is String) o['key'] as String: o,
  };

  final blocks = <PartyDetailBlock>[];
  final buffer = <String>[];

  void flushBuffer() {
    if (buffer.isEmpty) return;
    final group = List<String>.of(buffer);
    buffer.clear();
    blocks.add(_buildGenericBlock(group, overrides, seed: variantSeed + blocks.length, rich: rich));
  }

  for (final line in lines) {
    final override = overrides[_keyFor(line)];
    final resolved = _resolveLineCategory(line, override);
    // banner/bodyCard로 강제된 단독 줄만 즉시 전용 블록 — iconList로 강제된
    // 줄이나 자동 판정에서 특정 카테고리에 안 걸린 줄은 버퍼로 보내
    // 연속 구간끼리 묶이게 한다.
    if (resolved != null && resolved != AutoDescriptionCategory.iconList) {
      flushBuffer();
      blocks.add(_buildSingleLineBlock(
        resolved,
        line,
        override: override,
        seed: variantSeed + blocks.length,
        rich: rich,
      ));
    } else {
      buffer.add(line);
    }
  }
  flushBuffer();

  return blocks;
}

/// 이 줄이 강제(오버라이드) 또는 자동 판정으로 "특정 카테고리 단독 블록"이
/// 되어야 하는지 판단. null이면 버퍼(연속 구간 묶기)로 보낸다.
AutoDescriptionCategory? _resolveLineCategory(String line, Map<String, dynamic>? override) {
  if (override != null) {
    final forced = _categoryFromWire(override['category'] as String?);
    if (forced != null) return forced; // iconList로 강제되면 버퍼 처리(호출부에서 분기)
  }
  if (_kDateTimePattern.hasMatch(line)) return AutoDescriptionCategory.date;
  if (_kLocationPattern.hasMatch(line)) return AutoDescriptionCategory.location;
  if (_kPricePattern.hasMatch(line)) return AutoDescriptionCategory.price;
  if (_kCautionPattern.hasMatch(line)) return AutoDescriptionCategory.caution;
  if (_kDeadlinePattern.hasMatch(line)) return AutoDescriptionCategory.deadline;
  return null;
}

String? _resolveEmoji(
  AutoDescriptionCategory category,
  Map<String, dynamic>? override,
  int seed, {
  bool rich = false,
}) {
  if (override != null) {
    if (override['emojiRemoved'] == true) return null;
    final custom = override['emoji'] as String?;
    if (custom != null && custom.isNotEmpty) return custom;
  }
  final pool = _poolFor(category, rich);
  if (pool.isEmpty) return null;
  return _pick(pool, seed);
}

PartyDetailBlock _buildSingleLineBlock(
  AutoDescriptionCategory category,
  String line, {
  required Map<String, dynamic>? override,
  required int seed,
  required bool rich,
}) {
  final id = _keyFor(line);
  final emoji = _resolveEmoji(category, override, seed, rich: rich);
  switch (category) {
    case AutoDescriptionCategory.date:
      return PartyDetailBlock(
        id: id,
        type: PartyDetailBlockType.infoCard,
        infoCard: PartyDetailInfoCardPayload(
          title: '일정',
          text: _wrap(line, emoji),
          icon: 'schedule',
        ),
      );
    case AutoDescriptionCategory.location:
      return PartyDetailBlock(
        id: id,
        type: PartyDetailBlockType.infoCard,
        infoCard: PartyDetailInfoCardPayload(
          title: '장소',
          text: _wrap(line, emoji),
          icon: 'location',
        ),
      );
    case AutoDescriptionCategory.price:
      return PartyDetailBlock(
        id: id,
        type: PartyDetailBlockType.infoCard,
        infoCard: PartyDetailInfoCardPayload(
          title: '혜택',
          text: _wrap(line, emoji),
          icon: 'payment',
        ),
      );
    case AutoDescriptionCategory.caution:
    case AutoDescriptionCategory.deadline:
      return PartyDetailBlock(id: id, type: PartyDetailBlockType.notice, text: _wrap(line, emoji));
    case AutoDescriptionCategory.banner:
      return PartyDetailBlock(
        id: id,
        type: PartyDetailBlockType.subheading,
        text: _wrap(line, emoji),
      );
    case AutoDescriptionCategory.bodyCard:
      return PartyDetailBlock(id: id, type: PartyDetailBlockType.paragraph, text: line);
    case AutoDescriptionCategory.iconList:
      // 단독 줄이 iconList로 강제되는 경우는 없다(호출부에서 버퍼로 보냄) —
      // 안전망으로 배너와 동일하게 처리.
      return PartyDetailBlock(
        id: id,
        type: PartyDetailBlockType.subheading,
        text: _wrap(line, emoji),
      );
  }
}

/// 이미 만들어진 합성 블록을 보고 어떤 카테고리로 분류됐었는지 역으로
/// 추정한다 — 탭 편집 시트를 열 때 현재 스타일을 미리 선택해두기 위한
/// 용도(카테고리 자체를 블록에 저장하지 않으므로 타입/아이콘으로 되짚는다).
/// notice는 caution/deadline 둘 다 이 타입으로 렌더링되어 사후에 구분할 수
/// 없으므로 caution으로 근사한다 — 사용자가 시트에서 언제든 다시 고를 수
/// 있어 실제 동작에는 영향이 없다.
AutoDescriptionCategory autoDescriptionCategoryForBlock(PartyDetailBlock block) {
  switch (block.type) {
    case PartyDetailBlockType.infoCard:
      switch (block.infoCard?.icon) {
        case 'schedule':
          return AutoDescriptionCategory.date;
        case 'location':
          return AutoDescriptionCategory.location;
        case 'payment':
          return AutoDescriptionCategory.price;
        default:
          return AutoDescriptionCategory.bodyCard;
      }
    case PartyDetailBlockType.notice:
      return AutoDescriptionCategory.caution;
    case PartyDetailBlockType.subheading:
      return AutoDescriptionCategory.banner;
    case PartyDetailBlockType.checklist:
      return AutoDescriptionCategory.iconList;
    default:
      return AutoDescriptionCategory.bodyCard;
  }
}

/// 특정 카테고리에 안 걸린("일반") 줄들의 연속 구간을 배너/아이콘 리스트/
/// 본문 카드 중 하나로 묶는다. 각 줄 자체의 오버라이드(이모지)도 반영한다.
PartyDetailBlock _buildGenericBlock(
  List<String> lines,
  Map<String, Map<String, dynamic>> overrides, {
  required int seed,
  required bool rich,
}) {
  final allShort = lines.every((l) => l.length <= _kShortLineMaxLength);
  final groupId = _keyFor(lines.join('\n'));

  if (lines.length >= 2 && allShort) {
    final items = [
      for (var i = 0; i < lines.length; i++)
        _wrap(
          lines[i],
          _resolveEmoji(
            AutoDescriptionCategory.iconList,
            overrides[_keyFor(lines[i])],
            seed + i,
            rich: rich,
          ),
        ),
    ];
    return PartyDetailBlock(
      id: groupId,
      type: PartyDetailBlockType.checklist,
      checklist: PartyDetailChecklistPayload(items: items),
    );
  }
  if (lines.length == 1 && allShort) {
    final line = lines.first;
    final emoji = _resolveEmoji(
      AutoDescriptionCategory.banner,
      overrides[_keyFor(line)],
      seed,
      rich: rich,
    );
    return PartyDetailBlock(
      id: _keyFor(line),
      type: PartyDetailBlockType.subheading,
      text: _wrap(line, emoji),
    );
  }

  // 긴 문단(또는 길이가 제각각인 여러 줄) → 일반 본문 카드. simple/standard는
  // 과한 장식을 피하기 위해 이모지를 붙이지 않고("긴 본문은 이모지 없음"),
  // rich일 때만 어휘 매칭 단어 뒤에 최소한으로(최대 2개) 삽입한다. 원문
  // 줄바꿈은 항상 그대로 보존한다.
  final text = _decorateInline(lines.join('\n'), rich: rich, seed: seed);
  return PartyDetailBlock(id: groupId, type: PartyDetailBlockType.paragraph, text: text);
}
