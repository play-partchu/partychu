/// 파티 참가비 — 일반 파티 등록과 플레이스+파티 등록이 공유하는 단일 모델.
///
/// 저장 형태(Firestore, parties 문서):
/// ```
/// pricingType: 'same' | 'gendered' | 'free'
/// price:       30000,   // same일 때만 값이 있다
/// malePrice:   null,    // gendered일 때만 값이 있다
/// femalePrice: null,
/// ```
///
/// ## 기존 데이터 호환
/// 예전 문서에는 `pricingType`이 없고 `maleFee`/`femaleFee`(또는 아주 오래된
/// 문서의 단일 `fee`)만 있다. [fromMap]은 그 값들을 읽어 아래처럼 해석한다.
///  - maleFee == femaleFee (또는 한쪽만 존재)  → `same`
///  - maleFee != femaleFee                    → `gendered`
///  - 값이 0(또는 없음)                        → `free`
///
/// ## 새 문서도 레거시 필드를 함께 쓴다
/// [toMap]은 새 4개 필드와 함께 `maleFee`/`femaleFee`도 그대로 채운다.
/// 목록/지도/결제/Cloud Functions 등 아직 옛 필드를 읽는 곳이 남아 있어도
/// 금액이 어긋나지 않게 하기 위한 이중 기록이며, 읽는 쪽이 모두 이 모델로
/// 옮겨간 뒤에 레거시 필드를 정리하면 된다.
library;

enum PartyPricingType {
  /// 남녀 같은 금액.
  same('same'),

  /// 남녀 다른 금액.
  gendered('gendered'),

  /// 무료.
  free('free');

  const PartyPricingType(this.key);
  final String key;

  static PartyPricingType? fromKey(String? key) {
    for (final t in PartyPricingType.values) {
      if (t.key == key) return t;
    }
    return null;
  }
}

class PartyPricing {
  final PartyPricingType type;

  /// [PartyPricingType.same]일 때의 금액. 그 외에는 null(free는 0).
  final int? price;

  /// [PartyPricingType.gendered]일 때만 값이 있다.
  final int? malePrice;
  final int? femalePrice;

  const PartyPricing._({
    required this.type,
    this.price,
    this.malePrice,
    this.femalePrice,
  });

  const PartyPricing.free()
    : type = PartyPricingType.free,
      price = 0,
      malePrice = 0,
      femalePrice = 0;

  /// 남녀 같은 금액. 0 이하면 무료로 정규화한다.
  factory PartyPricing.same(int? amount) {
    if (amount == null || amount <= 0) return const PartyPricing.free();
    return PartyPricing._(type: PartyPricingType.same, price: amount);
  }

  /// 남녀 다른 금액. 두 값이 같으면 [same]으로, 둘 다 0 이하면 무료로 정규화한다
  /// — 저장된 형태가 사용자가 고른 것과 항상 일치하도록.
  factory PartyPricing.gendered({int? male, int? female}) {
    final m = (male ?? 0) < 0 ? 0 : (male ?? 0);
    final f = (female ?? 0) < 0 ? 0 : (female ?? 0);
    if (m <= 0 && f <= 0) return const PartyPricing.free();
    if (m == f) return PartyPricing.same(m);
    return PartyPricing._(
      type: PartyPricingType.gendered,
      malePrice: m,
      femalePrice: f,
    );
  }

  bool get isFree => type == PartyPricingType.free;

  /// 성별을 모를 때 대표로 보여줄 금액(목록 카드 등). gendered면 더 낮은 쪽을
  /// 대표로 쓴다 — "최소 참가비"로 보여주는 기존 목록/지도 동작과 같다.
  int get displayPrice {
    switch (type) {
      case PartyPricingType.free:
        return 0;
      case PartyPricingType.same:
        return price ?? 0;
      case PartyPricingType.gendered:
        final values = [
          malePrice,
          femalePrice,
        ].whereType<int>().where((v) => v > 0).toList();
        if (values.isEmpty) return 0;
        return values.reduce((a, b) => a < b ? a : b);
    }
  }

  /// gendered일 때 더 비싼 쪽 — "25,000~35,000원" 범위 표기에 쓴다.
  int get maxPrice {
    if (type != PartyPricingType.gendered) return displayPrice;
    final values = [malePrice, femalePrice].whereType<int>().toList();
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a > b ? a : b);
  }

  /// 이 사용자가 실제로 낼 금액. [gender]는 'male' | 'female' | null.
  /// 성별을 모르면 [displayPrice]로 떨어진다(신청 시 서버가 다시 계산한다).
  int priceFor(String? gender) {
    switch (type) {
      case PartyPricingType.free:
        return 0;
      case PartyPricingType.same:
        return price ?? 0;
      case PartyPricingType.gendered:
        if (gender == 'male') return malePrice ?? displayPrice;
        if (gender == 'female') return femalePrice ?? displayPrice;
        return displayPrice;
    }
  }

  /// 남녀 금액이 서로 다른지 — 상세 화면에서 "남 35,000 / 여 25,000"처럼
  /// 나눠 보여줄지 판단할 때 쓴다.
  bool get hasGenderedPrice => type == PartyPricingType.gendered;

  Map<String, dynamic> toMap() => {
    'pricingType': type.key,
    'price': type == PartyPricingType.gendered ? null : displayPrice,
    'malePrice': type == PartyPricingType.gendered
        ? malePrice
        : (isFree ? 0 : null),
    'femalePrice': type == PartyPricingType.gendered
        ? femalePrice
        : (isFree ? 0 : null),
    // ── 레거시 이중 기록(위 클래스 주석 참고) ──────────────────────────
    'maleFee': priceFor('male'),
    'femaleFee': priceFor('female'),
  };

  /// 임시저장용 — 저장 형태가 같아 그대로 쓴다.
  Map<String, dynamic> toDraftMap() => toMap();

  /// 새 구조와 레거시 구조를 모두 읽는다(위 "기존 데이터 호환" 참고).
  static PartyPricing fromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) return const PartyPricing.free();

    final declared = PartyPricingType.fromKey(map['pricingType'] as String?);
    if (declared != null) {
      switch (declared) {
        case PartyPricingType.free:
          return const PartyPricing.free();
        case PartyPricingType.same:
          return PartyPricing.same(
            (map['price'] as num?)?.toInt() ??
                (map['maleFee'] as num?)?.toInt(),
          );
        case PartyPricingType.gendered:
          return PartyPricing.gendered(
            male:
                (map['malePrice'] as num?)?.toInt() ??
                (map['maleFee'] as num?)?.toInt(),
            female:
                (map['femalePrice'] as num?)?.toInt() ??
                (map['femaleFee'] as num?)?.toInt(),
          );
      }
    }

    // ── pricingType이 없는 기존 문서 ────────────────────────────────────
    final male = (map['maleFee'] as num?)?.toInt();
    final female = (map['femaleFee'] as num?)?.toInt();
    // 아주 오래된 문서의 단일 필드. 콤보 등록이 쓰던 'price'도 함께 본다.
    final legacy =
        (map['fee'] as num?)?.toInt() ?? (map['price'] as num?)?.toInt();

    if (male == null && female == null) return PartyPricing.same(legacy);
    if (male == null) return PartyPricing.same(female);
    if (female == null) return PartyPricing.same(male);
    return PartyPricing.gendered(male: male, female: female);
  }

  @override
  bool operator ==(Object other) =>
      other is PartyPricing &&
      other.type == type &&
      other.price == price &&
      other.malePrice == malePrice &&
      other.femalePrice == femalePrice;

  @override
  int get hashCode => Object.hash(type, price, malePrice, femalePrice);

  @override
  String toString() =>
      'PartyPricing(${type.key}, price=$price, male=$malePrice, female=$femalePrice)';
}
