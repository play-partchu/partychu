import 'package:party_app/models/capacity_filter.dart';
import 'package:party_app/models/place_area.dart';
import 'package:party_app/models/room_price_type.dart';
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/utils/geo_distance.dart';
import 'package:party_app/utils/partychu_perk_ranking.dart';
import 'package:party_app/widgets/place_card_widget.dart'
    show placeRentalPrice, placeRentalPriceIsNightly;

/// 장소대여(`places`) 목록 정렬 방식 — 목록 헤더 오른쪽 끝의 **정렬 버튼**
/// 하나에서만 고른다(파티의 [PartySortMode]와 같은 구조).
///
/// 정렬은 [PlaceFilter]에 넣지 않았다 — 검색 시트의 "전체 초기화"가 필터를
/// 통째로 새로 만들어도 보고 있던 정렬은 그대로 남아야 하고, 상세검색 조건
/// 개수(`isActive`)에도 섞이면 안 된다.
///
/// ## 새 필드를 만들지 않는다
///
/// 모든 정렬 기준은 이미 저장돼 있는 값과 **카드가 쓰는 것과 같은 판독기**로만
/// 읽는다. 카드에 '₩30,000 / 시간 · 최대 20명'이라고 적힌 장소가 금액순·
/// 인원순에서 다른 자리에 놓이면 안 되기 때문이다.
///
///   | 정렬        | 값                                          |
///   |-------------|---------------------------------------------|
///   | 거리순      | `lat`/`lng` + [distanceMetersBetween]        |
///   | 금액순      | `pricePerHour` ([placeRentalPrice]), 대상은  |
///   |             | `priceUnit`([placeRentalPriceIsNightly])     |
///   | 수용인원순  | [CapacityFilter.capacityOf]                  |
///   | 평수순      | [PlaceArea.of] (`areaPyeong`, 숫자·평 단위)   |
///   | 최근 등록순 | `createdAt`                                  |
///
/// ## 금액순만은 "거르기 + 정렬"이다
///
/// `places` 한 컬렉션에 시간제 공간(파티룸·스튜디오)과 숙박 공간(펜션·호텔·
/// 게스트하우스)이 함께 들어 있고, 대표 가격의 단위도 문서마다 다르다.
/// ₩/시간과 ₩/박은 **비교할 수 없는 값**이라 한 목록에 함께 세울 방법이 없다
/// — 환산 계수를 정하는 순간 카드에 적힌 금액과 정렬 근거가 갈리므로 환산도
/// 하지 않는다.
///
/// 그래서 금액순은 단위마다 **따로 고르는 네 가지**이고, 고른 단위의 장소만
/// 결과에 남는다([placeSortIncludes]). 다른 단위를 숫자로 섞어 뒤에 붙이지
/// 않는다 — 사용자가 '1박당 낮은순'을 눌렀는데 시간제 장소가 아래에 줄줄이
/// 붙어 있으면 그것대로 순서를 오해한다.
///
/// 이 한정은 상세검색 조건과 **AND**다. 숙박형만 걸러 둔 상태에서 시간당
/// 정렬을 고르면 결과가 0개가 될 수 있고, 그때도 걸어 둔 필터를 몰래 풀지
/// 않는다.
enum PlaceSortMode {
  /// 앱이 원래 쓰던 순서 — 등록 최신순 + 같은 등록 날짜 안에서 파티츄 혜택
  /// 우선([PartychuPerkRanking.compareNewestFirst]). 목록에 들어온 순서가
  /// 이미 그것이므로 이 모드는 **아무것도 다시 정렬하지 않는다**.
  defaultOrder('기본순'),
  distance('거리순'),

  // ── 금액 (단위별) ─────────────────────────────────────────────────
  // 선언 순서가 곧 정렬 시트에 보이는 순서다 — 네 가지가 붙어 있어야 "단위가
  // 나뉜 한 묶음"으로 읽힌다([PlaceSortSheet]).
  nightPriceLow('1박당 금액 낮은순', unit: PlacePriceUnit.night),
  nightPriceHigh('1박당 금액 높은순', unit: PlacePriceUnit.night),
  hourPriceLow('시간당 금액 낮은순', unit: PlacePriceUnit.hour),
  hourPriceHigh('시간당 금액 높은순', unit: PlacePriceUnit.hour),

  capacityHigh('수용인원 많은순'),
  areaLarge('평수 큰순'),

  /// 순수 `createdAt` 최신순 — [defaultOrder]와 달리 혜택 가중치가 없다.
  newest('최근 등록순');

  const PlaceSortMode(this.label, {this.unit});

  final String label;

  /// 이 정렬이 **한정하는 가격 단위**. null이면 단위를 가리지 않는다
  /// (기본순·거리순·수용인원순·평수순·최근 등록순).
  final PlacePriceUnit? unit;

  /// 고른 단위의 장소만 남기는 정렬인지 — 결과가 0개가 될 수 있어서, 빈 목록
  /// 안내 문구가 이유를 밝힐 때 쓴다.
  bool get limitsToUnit => unit != null;
}

/// 대표 가격의 단위 — 저장값(`priceUnit`)의 'night' / 'hour'에 대응한다.
/// 값을 새로 만든 것이 아니라 이미 저장돼 있는 두 값에 이름을 붙인 것이다.
enum PlacePriceUnit {
  night('1박'),
  hour('시간');

  const PlacePriceUnit(this.label);

  /// 안내 문구에 쓰는 표기 — 카드의 '/ 박', '/ 시간'과 같은 말.
  final String label;
}

/// 거리순의 기준점(현재 위치).
typedef PlaceSortOrigin = ({double lat, double lng});

/// 이 장소가 [mode]의 **정렬 대상인지**.
///
/// 금액순 네 가지만 대상을 가린다 — 판정은 카드가 '/ 박'과 '/ 시간'을 가르는
/// 것과 **같은 함수**([placeRentalPriceIsNightly] = `priceUnit == 'night'`,
/// 단위가 없는 옛 문서는 시간제)다. 그 밖의 정렬은 언제나 true라 목록에서
/// 빠지는 장소가 없다.
bool placeSortIncludes(PlaceSortMode mode, Map<String, dynamic> data) {
  final unit = mode.unit;
  if (unit == null) return true;
  final nightly = placeRentalPriceIsNightly(data);
  return unit == PlacePriceUnit.night ? nightly : !nightly;
}

/// 고른 정렬 방식의 비교자. **null이면 "지금 순서를 그대로 둔다"**는 뜻이다
/// ([PlaceSortMode.defaultOrder], 그리고 위치를 못 얻은 거리순).
///
/// 대상을 가리는 일은 하지 않는다 — 그건 [placeSortIncludes]가 맡고, 호출부는
/// 걸러낸 뒤에 이 비교자로 정렬한다.
///
/// 문서 맵만 받는 순수 함수라 화면 없이 그대로 시험할 수 있다
/// (`test/place_sort_mode_test.dart`).
int Function(Map<String, dynamic>, Map<String, dynamic>)? placeSortComparator(
  PlaceSortMode mode, {
  PlaceSortOrigin? origin,
}) {
  switch (mode) {
    case PlaceSortMode.defaultOrder:
      return null;

    case PlaceSortMode.distance:
      // 위치를 못 얻었으면 정렬하지 않는다 — 좌표가 없다고 0,0에서 잰
      // 엉뚱한 거리로 목록을 뒤집으면 안 된다(호출부도 이때는 기본순으로
      // 되돌린다).
      if (origin == null) return null;
      final at = origin;
      // 좌표가 없는(또는 0,0인) 장소는 맨 뒤로 — 지오코딩이 실패한 옛 문서가
      // "가장 가까운 곳"으로 올라오면 안 된다([hasUsableCoords]).
      double distOf(Map<String, dynamic> m) {
        final lat = PlacePartyLink.placeLatOf(m);
        final lng = PlacePartyLink.placeLngOf(m);
        if (!hasUsableCoords(lat, lng)) return double.infinity;
        return distanceMetersBetween(at.lat, at.lng, lat!, lng!);
      }

      return (a, b) {
        final da = distOf(a);
        final db = distOf(b);
        // 같은 거리대(1km) 안에서만 혜택이 앞선다 — 파티 거리순과 같은 규칙.
        return PartychuPerkRanking.compare(
          a,
          b,
          group: (_, _) => _bucketOf(da).compareTo(_bucketOf(db)),
          within: (x, y) {
            final exact = da.compareTo(db);
            return exact != 0 ? exact : _createdDesc(x, y);
          },
        );
      };

    // 네 가지 금액순은 **대상이 이미 한 단위로 좁혀진 뒤에** 불린다
    // ([placeSortIncludes]). 그래서 비교는 카드에 적히는 금액 하나로 끝나고,
    // 환산도 단위 비교도 여기 없다.
    // 가격 문의 공간은 금액을 모르므로 어느 방향이든 맨 뒤에 둔다.
    case PlaceSortMode.nightPriceLow:
    case PlaceSortMode.hourPriceLow:
      return _byKey(
        (m) => isInquiryPlace(m)
            ? double.infinity
            : placeRentalPrice(m).toDouble(),
        descending: false,
      );

    case PlaceSortMode.nightPriceHigh:
    case PlaceSortMode.hourPriceHigh:
      return _byKey(
        (m) => isInquiryPlace(m)
            ? double.negativeInfinity
            : placeRentalPrice(m).toDouble(),
        descending: true,
      );

    case PlaceSortMode.capacityHigh:
      // 0은 "0명 수용"이 아니라 "호스트가 인원을 입력하지 않음"이다
      // ([CapacityFilter] 참고) — 내림차순이라 자연히 맨 뒤로 간다.
      return _byKey(
        (m) => CapacityFilter.capacityOf(m).toDouble(),
        descending: true,
      );

    case PlaceSortMode.areaLarge:
      // 평수가 없는 옛 문서는 맨 뒤 — [PlaceArea.of]가 null을 준다.
      return _byKey((m) => PlaceArea.of(m) ?? -1, descending: true);

    case PlaceSortMode.newest:
      return (a, b) => _createdDesc(a, b);
  }
}

int _bucketOf(double meters) => meters.isFinite
    ? PartychuPerkRanking.distanceBucket(meters)
    // 좌표 없는 장소끼리는 같은 그룹 — 그 안에서 등록 최신순으로 정리된다.
    : 1 << 30;

/// 값 하나를 기준으로 한 비교자 — 같은 값끼리는 파티츄 혜택이 앞서고,
/// 그래도 같으면 등록 최신순으로 순서를 고정한다(정렬이 흔들리지 않게).
int Function(Map<String, dynamic>, Map<String, dynamic>) _byKey(
  double Function(Map<String, dynamic>) keyOf, {
  required bool descending,
}) {
  return (a, b) => PartychuPerkRanking.compare(
    a,
    b,
    group: (x, y) => descending
        ? keyOf(y).compareTo(keyOf(x))
        : keyOf(x).compareTo(keyOf(y)),
    within: _createdDesc,
  );
}

int _createdDesc(Map<String, dynamic> a, Map<String, dynamic> b) =>
    PartychuPerkRanking.createdMillis(
      b,
    ).compareTo(PartychuPerkRanking.createdMillis(a));
