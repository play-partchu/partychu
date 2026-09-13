// ─────────────────────────────────────────────────────────────────────────────
// 매장 메뉴 — 술집·바·카페가 파는 음식/음료 한 줄("하이볼 8,000원").
//
// 상품([PlaceProduct])·프로모션([PlacePromotion])과 **컬렉션부터 분리**한다.
// 상품은 앱에서 결제하고 QR로 쓰는 이용권이라 재고·주문·정산이 붙지만, 메뉴는
// 매장에서 그냥 시켜 먹는 것이라 그런 개념이 하나도 없다. 섞으면 손님이 "이건
// 앱에서 사는 건가"를 헷갈리고, 메뉴마다 무의미한 결제 필드가 따라붙는다.
//
// Firestore 저장 형태 — placePromotions와 완전히 같은 축을 쓴다.
//   placeMenus/{menuId}
//     placeId / placeCollection / hostId   ← 소속 축
//     name / price / imageUrl / description / sortOrder / isVisible
//
// **events 문서 안에 배열로 넣지 않는 이유**: 메뉴는 수십~수백 개까지 늘어날
// 수 있는 유일한 항목이다. 배열로 넣으면 (1) 문서 1MB 한도에 걸리고, (2) 메뉴
// 한 줄만 고쳐도 문서 전체를 다시 쓰게 되며, (3) 플레이스 목록 쿼리가 매번
// 메뉴 전체를 실어 나른다. 상품·프로모션이 이미 별도 컬렉션인 것과 같은 이유다.
//
// 반대로 **전체 메뉴판 사진**은 몇 장뿐이고 매장 자체에 딸린 것이라 events
// 문서의 `menuBoardImageUrls`(소개 이미지와 같은 방식)에 그대로 둔다.
// ─────────────────────────────────────────────────────────────────────────────

/// 메뉴 한 줄.
class PlaceMenu {
  const PlaceMenu({
    required this.id,
    required this.placeId,
    required this.placeCollection,
    required this.hostId,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.description,
    required this.isVisible,
    required this.isFeatured,
    required this.sortOrder,
    this.localImagePath,
  });

  final String id;
  final String placeId;

  /// 'events'(술집·바·카페) 또는 'places'(공간대여·숙박).
  final String placeCollection;
  final String hostId;

  final String name;

  /// 원 단위. 0이면 "가격 미표기"로 보고 화면에서 가격 줄을 뺀다.
  final int price;

  /// 업로드가 끝난 사진 주소. 선택 항목이라 비어 있을 수 있다.
  final String imageUrl;

  /// 한 줄 설명. 선택 항목.
  final String description;

  /// 사장님이 켜고 끄는 노출 스위치 — 품절/시즌 종료를 지우지 않고 감출 때.
  final bool isVisible;

  /// 대표 메뉴 — 상세화면 맨 위에 사진 카드로 크게 먼저 보여준다.
  /// 최대 [maxFeatured]개까지만 켤 수 있다(등록 화면이 막는다).
  final bool isFeatured;

  /// 대표 메뉴 개수 상한 — 이 값을 등록 화면과 상세화면이 함께 본다.
  ///
  /// 일반 메뉴 개수에는 제한이 없다. 상한이 걸리는 건 "먼저 보여줄 것"을
  /// 고르는 이 자리뿐이고, 상세 상단의 가로 카드 줄이 목록처럼 길어지면
  /// "대표"라는 말이 무의미해지기 때문이다.
  static const int maxFeatured = 5;

  final int sortOrder;

  /// 아직 업로드하지 않은 사진의 로컬 경로 — **Firestore에 절대 쓰지 않는다**
  /// ([toMap]에서 빠진다). 등록 화면이 저장 버튼을 누르기 전까지 들고 있다가,
  /// 저장 시 업로드하고 [imageUrl]로 바꾼다. 임시저장([toDraftMap])에만 함께
  /// 실어서, 앱을 껐다 켜도 고른 사진이 남아 있게 한다.
  final String? localImagePath;

  /// '8,000원' — 0이면 null이라 화면에서 줄이 통째로 빠진다.
  String? get priceLabel {
    if (price <= 0) return null;
    final digits = price.toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return '$buf원';
  }

  /// 저장할 내용이 있는 항목인지 — 이름 없는 줄은 "쓰다 만 카드"로 본다.
  bool get isFilled => name.trim().isNotEmpty;

  factory PlaceMenu.fromMap(String id, Map<String, dynamic> d) => PlaceMenu(
    id: id,
    placeId: d['placeId'] as String? ?? '',
    placeCollection: d['placeCollection'] as String? ?? 'events',
    hostId: d['hostId'] as String? ?? '',
    name: d['name'] as String? ?? '',
    price: (d['price'] as num?)?.toInt() ?? 0,
    imageUrl: d['imageUrl'] as String? ?? '',
    description: d['description'] as String? ?? '',
    isVisible: d['isVisible'] as bool? ?? true,
    // 이 필드가 없던 문서는 "대표 아님"으로 읽힌다 — 기존 메뉴가 갑자기
    // 상단으로 올라오지 않는다.
    isFeatured: d['isFeatured'] as bool? ?? false,
    sortOrder: (d['sortOrder'] as num?)?.toInt() ?? 0,
    localImagePath: d['localImagePath'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'placeId': placeId,
    'placeCollection': placeCollection,
    'hostId': hostId,
    'name': name.trim(),
    'price': price,
    'imageUrl': imageUrl,
    'description': description.trim(),
    'isVisible': isVisible,
    'isFeatured': isFeatured,
    'sortOrder': sortOrder,
  };

  /// 임시저장(JSON) — 아직 업로드하지 않은 로컬 사진 경로까지 함께 남긴다.
  Map<String, dynamic> toDraftMap() => {
    ...toMap(),
    'id': id,
    'localImagePath': localImagePath,
  };

  static List<Map<String, dynamic>> listToDraft(List<PlaceMenu> items) =>
      items.map((m) => m.toDraftMap()).toList();

  static List<PlaceMenu> listFromDraft(Object? raw) {
    if (raw is! List) return const [];
    final out = <PlaceMenu>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final map = Map<String, dynamic>.from(e);
      out.add(PlaceMenu.fromMap(map['id'] as String? ?? '', map));
    }
    return out;
  }

  /// [localImagePath]는 `clearLocalImage`로만 지운다 — null을 넘겨서 지우는
  /// 방식이면 "안 건드림"과 구분되지 않는다(copyWith의 고질적인 함정).
  PlaceMenu copyWith({
    String? id,
    String? name,
    int? price,
    String? imageUrl,
    String? description,
    bool? isVisible,
    bool? isFeatured,
    int? sortOrder,
    String? localImagePath,
    bool clearLocalImage = false,
  }) => PlaceMenu(
    id: id ?? this.id,
    placeId: placeId,
    placeCollection: placeCollection,
    hostId: hostId,
    name: name ?? this.name,
    price: price ?? this.price,
    imageUrl: imageUrl ?? this.imageUrl,
    description: description ?? this.description,
    isVisible: isVisible ?? this.isVisible,
    isFeatured: isFeatured ?? this.isFeatured,
    sortOrder: sortOrder ?? this.sortOrder,
    localImagePath: clearLocalImage
        ? null
        : (localImagePath ?? this.localImagePath),
  );

  factory PlaceMenu.empty({
    required String placeId,
    required String placeCollection,
    required String hostId,
    required int sortOrder,
  }) => PlaceMenu(
    id: '',
    placeId: placeId,
    placeCollection: placeCollection,
    hostId: hostId,
    name: '',
    price: 0,
    imageUrl: '',
    description: '',
    isVisible: true,
    isFeatured: false,
    sortOrder: sortOrder,
  );
}
