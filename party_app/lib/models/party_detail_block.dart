/// 파티 상세페이지 블록 — Firestore `parties.detailBlocks` 배열 원소 1개에
/// 대응하는 순수 직렬화 모델. 노션처럼 블록을 쌓아 상세 소개를 구성하는
/// 기능의 데이터 구조로, `description`(기존 단일 텍스트 소개)과는 별개로
/// 함께 저장된다.
library;

/// 지원하는 블록 종류. [unknown]은 이 앱 버전이 모르는 type 문자열을
/// 만났을 때의 안전한 폴백이다 — 절대 크래시하지 않고, 원본 데이터를
/// 그대로 보존해 재저장 시 유실을 막는다.
enum PartyDetailBlockType {
  heading,
  subheading,
  paragraph,
  image,
  divider,
  notice,
  checklist,
  faq,
  timeline,
  infoCard,
  video,
  imageGroup,
  unknown,
}

const _kWireNames = {
  PartyDetailBlockType.heading: 'heading',
  PartyDetailBlockType.subheading: 'subheading',
  PartyDetailBlockType.paragraph: 'paragraph',
  PartyDetailBlockType.image: 'image',
  PartyDetailBlockType.divider: 'divider',
  PartyDetailBlockType.notice: 'notice',
  PartyDetailBlockType.checklist: 'checklist',
  PartyDetailBlockType.faq: 'faq',
  PartyDetailBlockType.timeline: 'timeline',
  PartyDetailBlockType.infoCard: 'infoCard',
  PartyDetailBlockType.video: 'video',
  PartyDetailBlockType.imageGroup: 'imageGroup',
};

PartyDetailBlockType? _typeFromWire(String? wire) {
  for (final entry in _kWireNames.entries) {
    if (entry.value == wire) return entry.key;
  }
  return null;
}

int _idSalt = 0;

/// 이 세션 안에서 유일한 블록/항목 ID를 만든다. 프로젝트에 uuid 패키지가
/// 없어 `PartyRoundDraft`(round_list_editor.dart)와 동일하게 타임스탬프
/// 기반으로 만들되, 같은 마이크로초에 여러 개를 만들 수 있는 상황을
/// 대비해 카운터를 덧붙인다.
String generatePartyDetailBlockId() {
  _idSalt = (_idSalt + 1) % 100000;
  return '${DateTime.now().microsecondsSinceEpoch}_$_idSalt';
}

/// FAQ 한 쌍(질문/답변).
class PartyDetailFaqItem {
  final String id;
  final String question;
  final String answer;

  const PartyDetailFaqItem({
    required this.id,
    required this.question,
    required this.answer,
  });

  factory PartyDetailFaqItem.fromMap(Map<String, dynamic> m) {
    return PartyDetailFaqItem(
      id: m['id']?.toString() ?? generatePartyDetailBlockId(),
      question: m['question'] as String? ?? '',
      answer: m['answer'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'question': question,
    'answer': answer,
  };

  bool get isEmpty => question.trim().isEmpty && answer.trim().isEmpty;
}

/// 일정/타임라인 한 항목.
class PartyDetailTimelineItem {
  final String id;
  final String time;
  final String title;
  final String description;

  const PartyDetailTimelineItem({
    required this.id,
    required this.time,
    required this.title,
    required this.description,
  });

  factory PartyDetailTimelineItem.fromMap(Map<String, dynamic> m) {
    return PartyDetailTimelineItem(
      id: m['id']?.toString() ?? generatePartyDetailBlockId(),
      time: m['time'] as String? ?? '',
      title: m['title'] as String? ?? '',
      description: m['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'time': time,
    'title': title,
    'description': description,
  };

  bool get isEmpty =>
      time.trim().isEmpty && title.trim().isEmpty && description.trim().isEmpty;
}

/// 체크리스트 블록 payload — 항목은 예시 스키마 그대로 순수 문자열 배열이다.
class PartyDetailChecklistPayload {
  final String? title;
  final List<String> items;

  const PartyDetailChecklistPayload({this.title, this.items = const []});

  factory PartyDetailChecklistPayload.fromMap(Map<String, dynamic> m) {
    final rawItems = m['items'];
    final items = rawItems is List
        ? rawItems
              .map((e) => e?.toString().trim() ?? '')
              .where((s) => s.isNotEmpty)
              .toList()
        : <String>[];
    final title = m['title'] as String?;
    return PartyDetailChecklistPayload(
      title: (title != null && title.trim().isNotEmpty) ? title : null,
      items: items,
    );
  }

  Map<String, dynamic> toMap() => {
    if (title != null && title!.trim().isNotEmpty) 'title': title,
    'items': items,
  };
}

/// FAQ 블록 payload.
class PartyDetailFaqPayload {
  final String? title;
  final List<PartyDetailFaqItem> items;

  const PartyDetailFaqPayload({this.title, this.items = const []});

  factory PartyDetailFaqPayload.fromMap(Map<String, dynamic> m) {
    final rawItems = m['items'];
    final items = <PartyDetailFaqItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is! Map) continue;
        try {
          final item = PartyDetailFaqItem.fromMap(Map<String, dynamic>.from(e));
          if (!item.isEmpty) items.add(item);
        } catch (_) {
          // 항목 하나가 손상돼도 나머지 항목에는 영향을 주지 않는다.
        }
      }
    }
    final title = m['title'] as String?;
    return PartyDetailFaqPayload(
      title: (title != null && title.trim().isNotEmpty) ? title : null,
      items: items,
    );
  }

  Map<String, dynamic> toMap() => {
    if (title != null && title!.trim().isNotEmpty) 'title': title,
    'items': items.map((i) => i.toMap()).toList(),
  };
}

/// 일정/타임라인 블록 payload.
class PartyDetailTimelinePayload {
  final String? title;
  final List<PartyDetailTimelineItem> items;

  const PartyDetailTimelinePayload({this.title, this.items = const []});

  factory PartyDetailTimelinePayload.fromMap(Map<String, dynamic> m) {
    final rawItems = m['items'];
    final items = <PartyDetailTimelineItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is! Map) continue;
        try {
          final item = PartyDetailTimelineItem.fromMap(
            Map<String, dynamic>.from(e),
          );
          if (!item.isEmpty) items.add(item);
        } catch (_) {}
      }
    }
    final title = m['title'] as String?;
    return PartyDetailTimelinePayload(
      title: (title != null && title.trim().isNotEmpty) ? title : null,
      items: items,
    );
  }

  Map<String, dynamic> toMap() => {
    if (title != null && title!.trim().isNotEmpty) 'title': title,
    'items': items.map((i) => i.toMap()).toList(),
  };
}

/// 정보 카드에서 고를 수 있는 아이콘 후보 — 문자열로 저장해(Flutter
/// `IconData` 의존 없이) 모델을 순수 Dart로 유지한다. 실제 아이콘 매핑은
/// 위젯 계층(`PartyDetailBlockPreview`)에서만 한다.
const List<String> partyDetailInfoCardIconNames = [
  'location',
  'schedule',
  'payment',
  'badge',
  'dress',
  'gift',
  'warning',
];

/// 정보 카드 블록 payload(장소/준비물/포함사항/이용안내/드레스코드 등).
class PartyDetailInfoCardPayload {
  final String title;
  final String text;

  /// [partyDetailInfoCardIconNames] 중 하나가 아니면 null로 안전하게 대체된다.
  final String? icon;

  const PartyDetailInfoCardPayload({
    required this.title,
    required this.text,
    this.icon,
  });

  factory PartyDetailInfoCardPayload.fromMap(Map<String, dynamic> m) {
    final icon = m['icon'] as String?;
    return PartyDetailInfoCardPayload(
      title: m['title'] as String? ?? '',
      text: m['text'] as String? ?? '',
      icon: partyDetailInfoCardIconNames.contains(icon) ? icon : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'text': text,
    if (icon != null) 'icon': icon,
  };
}

/// 동영상 블록 payload — 실제 파일은 Cloudflare Stream에 있고 여기엔
/// UID/URL/썸네일/비율/캡션만 저장한다(바이너리 없음).
class PartyDetailVideoPayload {
  final String? videoUid;
  final String videoUrl;
  final String? thumbnailUrl;
  final double? aspectRatio;
  final String? caption;

  const PartyDetailVideoPayload({
    this.videoUid,
    required this.videoUrl,
    this.thumbnailUrl,
    this.aspectRatio,
    this.caption,
  });

  factory PartyDetailVideoPayload.fromMap(Map<String, dynamic> m) {
    return PartyDetailVideoPayload(
      videoUid: m['videoUid'] as String?,
      videoUrl: m['videoUrl'] as String? ?? '',
      thumbnailUrl: m['thumbnailUrl'] as String?,
      aspectRatio: (m['aspectRatio'] as num?)?.toDouble(),
      caption: m['caption'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    if (videoUid != null) 'videoUid': videoUid,
    'videoUrl': videoUrl,
    if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
    if (aspectRatio != null) 'aspectRatio': aspectRatio,
    if (caption != null && caption!.isNotEmpty) 'caption': caption,
  };
}

/// 사진 콜라주(imageGroup) 한 칸 — 항상 정사각형(1:1) 프레임 안에서
/// 독립적으로 위치조정(크롭)한다. `id`는 로컬(아직 업로드 전) 미리보기
/// 파일을 찾는 키로도 쓰인다(`PartyDetailBlockPreview.localImageOverrides`).
class PartyDetailImageGroupItem {
  final String id;
  final String imageUrl;
  final double? width;
  final double? height;
  final double? cropX;
  final double? cropY;
  final double? cropScale;

  const PartyDetailImageGroupItem({
    required this.id,
    required this.imageUrl,
    this.width,
    this.height,
    this.cropX,
    this.cropY,
    this.cropScale,
  });

  factory PartyDetailImageGroupItem.fromMap(Map<String, dynamic> m) {
    return PartyDetailImageGroupItem(
      id: m['id']?.toString() ?? generatePartyDetailBlockId(),
      imageUrl: m['imageUrl'] as String? ?? '',
      width: (m['width'] as num?)?.toDouble(),
      height: (m['height'] as num?)?.toDouble(),
      cropX: (m['cropX'] as num?)?.toDouble(),
      cropY: (m['cropY'] as num?)?.toDouble(),
      cropScale: (m['cropScale'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'imageUrl': imageUrl,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (cropX != null) 'cropX': cropX,
    if (cropY != null) 'cropY': cropY,
    if (cropScale != null) 'cropScale': cropScale,
  };

  bool get isEmpty => imageUrl.trim().isEmpty;
}

/// 사진 콜라주 블록 payload — 2~4장일 때만 렌더링된다(`PartyDetailBlockPreview`
/// 참고). 사진별 개별 캡션은 없고, 그룹 전체에 대한 캡션 1개만 지원한다.
class PartyDetailImageGroupPayload {
  final List<PartyDetailImageGroupItem> items;
  final String? caption;

  const PartyDetailImageGroupPayload({this.items = const [], this.caption});

  factory PartyDetailImageGroupPayload.fromMap(Map<String, dynamic> m) {
    final rawItems = m['items'];
    final items = <PartyDetailImageGroupItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is! Map) continue;
        try {
          final item = PartyDetailImageGroupItem.fromMap(
            Map<String, dynamic>.from(e),
          );
          if (!item.isEmpty) items.add(item);
        } catch (_) {
          // 항목 하나가 손상돼도 나머지 항목에는 영향을 주지 않는다.
        }
      }
    }
    final caption = m['caption'] as String?;
    return PartyDetailImageGroupPayload(
      items: items,
      caption: (caption != null && caption.trim().isNotEmpty) ? caption : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'items': items.map((i) => i.toMap()).toList(),
    if (caption != null && caption!.isNotEmpty) 'caption': caption,
  };
}

class PartyDetailBlock {
  final String id;
  final PartyDetailBlockType type;

  /// heading / subheading / paragraph / notice
  final String? text;

  /// image
  final String? imageUrl;
  final double? imageWidth;
  final double? imageHeight;
  final String? caption;

  /// image — 4:5 프레임 안에서의 위치(초점, 0~1)/배율. null이면 크롭을
  /// 아직 지정하지 않은 기존 데이터로 간주해 원본 비율(`imageWidth`/
  /// `imageHeight`)로 하위 호환 렌더링한다(`PartyDetailBlockPreview` 참고).
  final double? imageCropX;
  final double? imageCropY;
  final double? imageCropScale;

  /// 확장 블록(5단계) — type에 따라 해당 필드 하나만 값을 갖는다.
  final PartyDetailChecklistPayload? checklist;
  final PartyDetailFaqPayload? faq;
  final PartyDetailTimelinePayload? timeline;
  final PartyDetailInfoCardPayload? infoCard;
  final PartyDetailVideoPayload? video;
  final PartyDetailImageGroupPayload? imageGroup;

  /// type == unknown일 때만 non-null — 원본 맵을 그대로 들고 있다가 다시
  /// 저장할 때 그대로 돌려준다(이 버전이 모르는 필드까지 보존).
  final Map<String, dynamic>? rawUnknown;

  const PartyDetailBlock({
    required this.id,
    required this.type,
    this.text,
    this.imageUrl,
    this.imageWidth,
    this.imageHeight,
    this.caption,
    this.imageCropX,
    this.imageCropY,
    this.imageCropScale,
    this.checklist,
    this.faq,
    this.timeline,
    this.infoCard,
    this.video,
    this.imageGroup,
    this.rawUnknown,
  });

  factory PartyDetailBlock.fromMap(Map<String, dynamic> m) {
    try {
      final id = m['id']?.toString() ?? generatePartyDetailBlockId();
      final typeRaw = m['type'];
      final type = typeRaw is String ? _typeFromWire(typeRaw) : null;

      if (type == null) {
        // 모르는(또는 손상된) type — 원본을 그대로 보존한 채 unknown으로.
        Map<String, dynamic> raw;
        try {
          raw = Map<String, dynamic>.from(m);
        } catch (_) {
          raw = {'id': id, if (typeRaw != null) 'type': typeRaw};
        }
        return PartyDetailBlock(
          id: id,
          type: PartyDetailBlockType.unknown,
          rawUnknown: raw,
        );
      }

      switch (type) {
        case PartyDetailBlockType.heading:
        case PartyDetailBlockType.subheading:
        case PartyDetailBlockType.paragraph:
        case PartyDetailBlockType.notice:
          return PartyDetailBlock(
            id: id,
            type: type,
            text: m['text'] as String? ?? '',
          );
        case PartyDetailBlockType.image:
          return PartyDetailBlock(
            id: id,
            type: type,
            imageUrl: m['imageUrl'] as String? ?? '',
            imageWidth: (m['width'] as num?)?.toDouble(),
            imageHeight: (m['height'] as num?)?.toDouble(),
            caption: m['caption'] as String?,
            imageCropX: (m['imageCropX'] as num?)?.toDouble(),
            imageCropY: (m['imageCropY'] as num?)?.toDouble(),
            imageCropScale: (m['imageCropScale'] as num?)?.toDouble(),
          );
        case PartyDetailBlockType.divider:
          return PartyDetailBlock(id: id, type: type);
        case PartyDetailBlockType.checklist:
          return PartyDetailBlock(
            id: id,
            type: type,
            checklist: PartyDetailChecklistPayload.fromMap(m),
          );
        case PartyDetailBlockType.faq:
          return PartyDetailBlock(
            id: id,
            type: type,
            faq: PartyDetailFaqPayload.fromMap(m),
          );
        case PartyDetailBlockType.timeline:
          return PartyDetailBlock(
            id: id,
            type: type,
            timeline: PartyDetailTimelinePayload.fromMap(m),
          );
        case PartyDetailBlockType.infoCard:
          return PartyDetailBlock(
            id: id,
            type: type,
            infoCard: PartyDetailInfoCardPayload.fromMap(m),
          );
        case PartyDetailBlockType.video:
          return PartyDetailBlock(
            id: id,
            type: type,
            video: PartyDetailVideoPayload.fromMap(m),
          );
        case PartyDetailBlockType.imageGroup:
          return PartyDetailBlock(
            id: id,
            type: type,
            imageGroup: PartyDetailImageGroupPayload.fromMap(m),
          );
        case PartyDetailBlockType.unknown:
          return PartyDetailBlock(
            id: id,
            type: PartyDetailBlockType.unknown,
            rawUnknown: {'id': id},
          );
      }
    } catch (_) {
      // 위 방어 로직에서 예상 못 한 예외가 나더라도 절대 밖으로 던지지 않는다.
      final id = generatePartyDetailBlockId();
      Map<String, dynamic>? raw;
      try {
        raw = Map<String, dynamic>.from(m);
      } catch (_) {
        raw = null;
      }
      return PartyDetailBlock(
        id: id,
        type: PartyDetailBlockType.unknown,
        rawUnknown: raw,
      );
    }
  }

  Map<String, dynamic> toMap() {
    if (type == PartyDetailBlockType.unknown) {
      final raw = rawUnknown;
      if (raw != null) return {...raw, 'id': id};
      return {'id': id};
    }
    switch (type) {
      case PartyDetailBlockType.heading:
      case PartyDetailBlockType.subheading:
      case PartyDetailBlockType.paragraph:
      case PartyDetailBlockType.notice:
        return {'id': id, 'type': _kWireNames[type], 'text': text ?? ''};
      case PartyDetailBlockType.image:
        return {
          'id': id,
          'type': _kWireNames[type],
          'imageUrl': imageUrl ?? '',
          if (imageWidth != null) 'width': imageWidth,
          if (imageHeight != null) 'height': imageHeight,
          if (caption != null) 'caption': caption,
          if (imageCropX != null) 'imageCropX': imageCropX,
          if (imageCropY != null) 'imageCropY': imageCropY,
          if (imageCropScale != null) 'imageCropScale': imageCropScale,
        };
      case PartyDetailBlockType.divider:
        return {'id': id, 'type': _kWireNames[type]};
      case PartyDetailBlockType.checklist:
        return {
          'id': id,
          'type': _kWireNames[type],
          ...(checklist ?? const PartyDetailChecklistPayload()).toMap(),
        };
      case PartyDetailBlockType.faq:
        return {
          'id': id,
          'type': _kWireNames[type],
          ...(faq ?? const PartyDetailFaqPayload()).toMap(),
        };
      case PartyDetailBlockType.timeline:
        return {
          'id': id,
          'type': _kWireNames[type],
          ...(timeline ?? const PartyDetailTimelinePayload()).toMap(),
        };
      case PartyDetailBlockType.infoCard:
        return {
          'id': id,
          'type': _kWireNames[type],
          ...(infoCard ?? const PartyDetailInfoCardPayload(title: '', text: ''))
              .toMap(),
        };
      case PartyDetailBlockType.video:
        return {
          'id': id,
          'type': _kWireNames[type],
          ...(video ?? const PartyDetailVideoPayload(videoUrl: '')).toMap(),
        };
      case PartyDetailBlockType.imageGroup:
        return {
          'id': id,
          'type': _kWireNames[type],
          ...(imageGroup ?? const PartyDetailImageGroupPayload()).toMap(),
        };
      case PartyDetailBlockType.unknown:
        return {'id': id};
    }
  }

  static List<PartyDetailBlock> listFromDynamic(dynamic raw) {
    if (raw is! List) return [];
    final result = <PartyDetailBlock>[];
    for (final e in raw) {
      if (e is! Map) continue;
      try {
        result.add(PartyDetailBlock.fromMap(Map<String, dynamic>.from(e)));
      } catch (_) {
        // 개별 원소 파싱이 완전히 실패해도 나머지 블록에는 영향을 주지 않는다.
      }
    }
    return result;
  }

  static List<Map<String, dynamic>> listToMaps(List<PartyDetailBlock> blocks) {
    return blocks.map((b) => b.toMap()).toList();
  }
}
