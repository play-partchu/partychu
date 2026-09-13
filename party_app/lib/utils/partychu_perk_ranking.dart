import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/widgets/partychu_perk.dart';

/// "파티츄 전용 혜택"이 있는 게시물을 목록에서 조금 앞으로 당기는 정렬 규칙.
///
/// **기존 정렬을 대체하지 않는다.** 항상 "같은 노출 그룹 안에서만" 적용되는
/// 보조 가중치다 — 그룹이 다르면 기존 정렬이 그대로 이긴다. 이렇게 하지
/// 않으면 광고성 혜택 문구 한 줄만 넣은 오래된 게시물이 목록 최상단을
/// 영구히 차지하게 된다.
///
/// 적용 순서는 언제나 이렇다.
///
///   1. **그룹** (기존 정렬의 큰 축 — 등록 날짜 / 마감 날짜 / 요금 / 거리대)
///   2. **혜택 여부** (같은 그룹 안에서만)
///   3. **그룹 내 기존 정렬** (정확한 시각·금액·거리)
///
/// 또 하나의 안전장치로, 혜택 가중치는 **아직 참여할 수 있는 게시물에만**
/// 준다([boostable]). 모집이 끝났거나 이미 지난 파티는 혜택이 있어도 순위가
/// 올라가지 않는다.
class PartychuPerkRanking {
  const PartychuPerkRanking._();

  /// 혜택 우선순위 — 앞으로 당길 대상이면 0, 아니면 1.
  ///
  /// [boostable]은 "지금 참여 가능한가"를 판단한다(생략하면 항상 가능으로
  /// 본다 — 플레이스/장소대여처럼 모집 상태 개념이 없는 목록용).
  static int rank(
    Map<String, dynamic> data, {
    bool Function(Map<String, dynamic>)? boostable,
  }) {
    if (partychuPerkFrom(data) == null) return 1;
    if (boostable != null && !boostable(data)) return 1;
    return 0;
  }

  /// 그룹 → 혜택 → 그룹 내 정렬 순으로 비교한다.
  ///
  /// [group]이 0이 아니면 그대로 반환한다(기존 정렬 우선). 0일 때만 혜택
  /// 가중치가 끼어들고, 혜택까지 같으면 [within]으로 최종 순서를 정한다.
  static int compare(
    Map<String, dynamic> a,
    Map<String, dynamic> b, {
    required int Function(Map<String, dynamic>, Map<String, dynamic>) group,
    int Function(Map<String, dynamic>, Map<String, dynamic>)? within,
    bool Function(Map<String, dynamic>)? boostable,
  }) {
    final g = group(a, b);
    if (g != 0) return g;
    final p = rank(a, boostable: boostable) - rank(b, boostable: boostable);
    if (p != 0) return p;
    return within?.call(a, b) ?? 0;
  }

  /// 등록 최신순(기본 정렬) + 같은 **등록 날짜** 안에서 혜택 우선.
  ///
  /// 그룹을 "등록된 날(day)"로 잡았기 때문에, 어제 등록된 혜택 게시물이
  /// 오늘 등록된 게시물보다 위로 올라가는 일은 생기지 않는다.
  static int compareNewestFirst(
    Map<String, dynamic> a,
    Map<String, dynamic> b, {
    bool Function(Map<String, dynamic>)? boostable,
  }) => compare(
    a,
    b,
    group: (x, y) => _createdDayKey(y).compareTo(_createdDayKey(x)),
    within: (x, y) => createdMillis(y).compareTo(createdMillis(x)),
    boostable: boostable,
  );

  /// `createdAt`의 "날짜"만 뽑은 정렬 키(yyyyMMdd). 값이 없으면 0 —
  /// 최신순에서 자연스럽게 맨 뒤로 간다.
  static int _createdDayKey(Map<String, dynamic> d) {
    final ts = d['createdAt'];
    if (ts is! Timestamp) return 0;
    final at = ts.toDate().toLocal();
    return at.year * 10000 + at.month * 100 + at.day;
  }

  /// `createdAt`의 밀리초 — 값이 없으면 0(최신순에서 맨 뒤).
  ///
  /// 이 클래스 바깥에서도 쓴다: 장소대여의 '최근 등록순'(PlaceSortMode)은
  /// 혜택 가중치 없이 이 값 하나로만 정렬하므로, 기본순과 **같은 판독기**를
  /// 써야 두 정렬의 등록 시각 해석이 갈리지 않는다.
  static int createdMillis(Map<String, dynamic> d) {
    final ts = d['createdAt'];
    return ts is Timestamp ? ts.toDate().millisecondsSinceEpoch : 0;
  }

  /// 거리순에서 "같은 거리대"로 묶는 폭(m) — 이 안에서만 혜택이 앞선다.
  static const double distanceBucketMeters = 1000;

  static int distanceBucket(double meters) =>
      (meters / distanceBucketMeters).floor();

  /// 마감/날짜를 "날짜" 단위로 묶는 정렬 키(yyyyMMdd). null이면 최대값을
  /// 돌려 오름차순에서 맨 뒤로 간다.
  static int dayKeyOf(DateTime? at) {
    if (at == null) return 99999999;
    return at.year * 10000 + at.month * 100 + at.day;
  }
}
