/// 파티샵 탭 전용 상세검색 필터.
/// 파티(PartyFilter)와 완전히 분리된 모델 — 쇼핑 서비스 특성에 맞는 항목만 보유.
class ShopFilter {
  Set<String> regions;
  Set<String> categories;
  Set<String> priceRanges;
  bool deliveryAvailable;
  bool pickupAvailable;
  bool discountOnly;
  bool couponOnly;
  bool inStockOnly;

  ShopFilter({
    Set<String>? regions,
    Set<String>? categories,
    Set<String>? priceRanges,
    this.deliveryAvailable = false,
    this.pickupAvailable = false,
    this.discountOnly = false,
    this.couponOnly = false,
    this.inStockOnly = false,
  }) : regions = regions ?? {},
       categories = categories ?? {},
       priceRanges = priceRanges ?? {};

  bool get isActive =>
      regions.isNotEmpty ||
      categories.isNotEmpty ||
      priceRanges.isNotEmpty ||
      deliveryAvailable ||
      pickupAvailable ||
      discountOnly ||
      couponOnly ||
      inStockOnly;

  ShopFilter copy() => ShopFilter(
    regions: {...regions},
    categories: {...categories},
    priceRanges: {...priceRanges},
    deliveryAvailable: deliveryAvailable,
    pickupAvailable: pickupAvailable,
    discountOnly: discountOnly,
    couponOnly: couponOnly,
    inStockOnly: inStockOnly,
  );

  List<MapEntry<String, String>> get selectedEntries => [
    ...regions.map((v) => MapEntry('regions', v)),
    ...categories.map((v) => MapEntry('categories', v)),
    ...priceRanges.map((v) => MapEntry('priceRanges', v)),
    if (deliveryAvailable) const MapEntry('deliveryAvailable', '배송 가능'),
    if (pickupAvailable) const MapEntry('pickupAvailable', '방문 수령 가능'),
    if (discountOnly) const MapEntry('discountOnly', '할인 상품'),
    if (couponOnly) const MapEntry('couponOnly', '쿠폰 사용 가능'),
    if (inStockOnly) const MapEntry('inStockOnly', '재고 있는 상품만'),
  ];

  void removeValue(String category, String value) {
    switch (category) {
      case 'regions':
        regions.remove(value);
        break;
      case 'categories':
        categories.remove(value);
        break;
      case 'priceRanges':
        priceRanges.remove(value);
        break;
      case 'deliveryAvailable':
        deliveryAvailable = false;
        break;
      case 'pickupAvailable':
        pickupAvailable = false;
        break;
      case 'discountOnly':
        discountOnly = false;
        break;
      case 'couponOnly':
        couponOnly = false;
        break;
      case 'inStockOnly':
        inStockOnly = false;
        break;
    }
  }
}
