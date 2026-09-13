// ─────────────────────────────────────────────────────────────────────────────
// 🎪 **이벤트 탐색 판정의 정본** — 지금 보여줄 이벤트가 하나 이상 있는 매장 id
// 집합.
//
// ── 이벤트는 별도 탐색이 아니라 매장 목록의 필터다 ──────────────────────────
// 🎪 이벤트는 업종 격자 안의 한 칸이고([PlaceCategoryExplorer.eventValue]),
// 누르면 **기존 플레이스 카드 그대로** 이벤트 중인 매장만 남는다. 카드를
// 누르면 평소와 똑같이 매장 상세로 가고, 이벤트는 거기 이미 있는 영역
// ([PlacePromotionListSection])이 보여준다 — 이벤트만 따로 떼어낸 목록도,
// 이벤트 전용 상세 진입도 두지 않는다.
//
// 그래서 이 색인의 결과는 **이벤트 목록이 아니라 매장 id 집합**이다. 매장
// 하나에 이벤트가 몇 개든 id는 하나라, 카드가 제목 수만큼 복제될 수 없다.
//
// ── 새 데이터 구조를 만들지 않는다 ───────────────────────────────────────────
// 이벤트 한 건의 정본은 예전 그대로 `placePromotions`([PlacePromotion])이고,
// 매장 본체는 `events`다(이름이 헷갈리는 이유는 party_event_source.dart 상단
// 주석 참고). 여기서는 이미 있는 목록을 훑어 id만 모은다 — 새 컬렉션도, 새
// 미러 필드도 만들지 않는다.
//
// ── 노출 판정을 여기서 새로 만들지 않는다 ────────────────────────────────────
// 이벤트가 지금 보일 것인지는 [PlacePromotion.statusAt]이 정한다(숨김·종료는
// 빠지고 진행 중·시작 전만 남는 [PromotionStatus.isPublic]). 플레이스 상세의
// 이벤트 영역(`watchPublicForPlace`)이 쓰는 것과 **같은 판정**이라, 목록에
// 떴는데 매장 상세에는 볼 이벤트가 없거나 그 반대인 상태가 생길 수 없다.
//
// ── 한 색인에는 한 컬렉션만 담는다 ───────────────────────────────────────────
// `placePromotions`에는 매장·즐길거리(`events`)의 이벤트와 공간대여·숙박
// (`places`)의 이벤트가 함께 살지만, 탐색에서는 **절대 섞이지 않는다** —
// 플레이스 탭은 매장 이벤트만, 장소대여 탭은 공간 이벤트만 본다. 그래서 색인도
// 컬렉션별로 따로 만든다([fromPromotions]의 `collection`). 둘을 한 집합에
// 담으면 id가 우연히 겹칠 때 남의 탭 이벤트가 새어 들어온다.
//
// 두 종류를 함께 보는 자리는 파티츄/이벤트 탭 하나뿐이고, 거기서도 합치는 것은
// **표시용 피드**([EventFeed])이지 이 색인이 아니다.
//
// Firestore를 모르는 순수 함수다 — 화면 없이 테스트할 수 있다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart' show TimeOfDay;

import 'package:party_app/models/day_time_match.dart';
import 'package:party_app/models/place_event_time.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/models/place_weekly_hours.dart';

class PlaceEventIndex {
  const PlaceEventIndex(
    this.placeIds, [
    this.byPlace = const {},
    this.signature = '',
  ]);

  /// 지금 손님에게 보일 이벤트가 하나 이상 있는 **원본 문서 id**.
  final Set<String> placeIds;

  /// 원본 id → 그 원본의 **보여줄 이벤트들**.
  ///
  /// id 집합만으로는 날짜·시간 조건을 걸 수 없다 — "이벤트가 있다"와 "고른
  /// 날짜·시각에 하는 이벤트가 있다"는 다른 물음이고, 뒤쪽은 이벤트 한 건 한
  /// 건의 기간·시각을 봐야 답할 수 있다([PlaceEventTime]).
  ///
  /// 조건을 안 걸면 쓰이지 않는다 — 그때는 [has]가 예전 그대로 답한다.
  final Map<String, List<PlacePromotion>> byPlace;

  /// 이 색인을 만든 이벤트들의 **판정에 쓰이는 값**만 모은 지문.
  ///
  /// [sameAs]가 id만 비교하면, 사장님이 이벤트 시각을 22:00에서 20:00으로
  /// 고쳐도 id 집합은 그대로라 색인이 갱신되지 않는다 — 화면은 낡은 시각으로
  /// 계속 거른다. 그래서 판정에 실제로 쓰는 필드만 지문에 넣어 비교한다.
  ///
  /// ⚠️ **순서에는 흔들리지 않는다**(만들 때 정렬한다). 스트림이 같은 이벤트를
  ///    다른 순서로 주는 일은 흔한데, 그때마다 목록을 다시 그리면 스크롤이
  ///    튄다 — 집합이 같으면 같다는 기존 계약을 그대로 지킨다.
  final String signature;

  /// 매장·즐길거리 — 플레이스 탭의 이벤트 축.
  static const String placeCollection = 'events';

  /// 공간대여·숙박 — 장소대여 탭의 이벤트 축.
  ///
  /// 두 컬렉션의 이벤트는 **같은 `placePromotions`에 살지만 절대 섞이지
  /// 않는다** — 색인을 컬렉션별로 따로 만들고([fromPromotions]의 [collection]),
  /// 각 탭은 자기 것만 본다. 한 색인에 둘을 담으면 id가 우연히 겹칠 때 남의
  /// 탭 이벤트가 새어 들어온다.
  static const String rentalCollection = 'places';

  /// 아직 이벤트를 못 읽었을 때 쓰는 빈 색인.
  ///
  /// ⚠️ "이벤트가 없다"와 "아직 모른다"는 다르다. 아직 모르는 동안에는 색인을
  /// 아예 넘기지 않아 예전 미러 판정([PlaceEventTaxonomy.isRunningAt])이
  /// 그대로 답하게 한다([EventFilter.matchesDiscovery]) — 목록이 잠깐 통째로
  /// 비는 것보다 낫다.
  static const PlaceEventIndex empty = PlaceEventIndex(<String>{});

  bool get isEmpty => placeIds.isEmpty;

  int get length => placeIds.length;

  /// 이 매장에 지금 보여줄 이벤트가 있는가.
  bool has(String? placeId) =>
      placeId != null && placeId.isNotEmpty && placeIds.contains(placeId);

  /// 고른 **날짜·시각에** 이 매장이 하는 이벤트가 있는가.
  ///
  /// 조건이 하나도 없으면 [has]와 같다 — 예전 동작 그대로다. 조건이 걸리면
  /// 이벤트 한 건씩 [PlaceEventTime.matches]로 본다(하나라도 맞으면 통과).
  ///
  /// 판정 규칙을 여기서 새로 만들지 않는다 — 파티츄/이벤트 탭의 목록이 쓰는
  /// 것과 **글자 그대로 같은 함수**다. 그래서 같은 조건을 걸면 지도·플레이스
  /// 목록·이벤트 목록이 같은 답을 낼 수밖에 없다.
  ///
  /// [hours]는 **영업중(전시간)** 이벤트에만 쓰인다 — 그 이벤트의 적용 시간이
  /// 곧 그 매장의 영업시간이라, 원본 문서에서 읽어 넘겨야 한다
  /// ([PlaceWeeklyHours.fromPlaceDoc]). 영업시간을 등록하지 않은 매장은 시간
  /// 조건이 걸린 동안 빠진다(모르는 시간을 추측하지 않는다).
  bool hasMatching(
    String? placeId, {
    Iterable<DateTime> dates = const [],
    TimeOfDay? start,
    TimeOfDay? end,
    PlaceWeeklyHours? hours,
    DateTime? now,
  }) {
    if (!has(placeId)) return false;
    final dateList = dates.toList();
    if (dateList.isEmpty && !DayTimeMatch.isActive(start, end)) return true;
    final list = byPlace[placeId];
    // 옛 방식으로 만든 색인(byPlace가 빈 경우)은 조건을 걸 재료가 없다.
    // 통과시키면 조건을 안 건 것과 같아지므로 걸러낸다 — 색인이 null일 때와
    // 같은 태도다(fail-closed).
    if (list == null || list.isEmpty) return false;
    return list.any(
      (p) => PlaceEventTime.matches(
        p,
        dates: dateList,
        start: start,
        end: end,
        hours: hours,
        now: now,
      ),
    );
  }

  /// 🎪 조건이 걸린 목록/지도에서 이 문서를 남길 것인가 — **색인만 보는
  /// 판정의 정본**이다.
  ///
  /// 미러 폴백이 있는 플레이스 축([EventFilter.matchesDiscovery])과 달리
  /// 여기는 색인 하나만 본다. [index]가 아직 null이면(못 읽었으면)
  /// **아무것도 남기지 않는다** — 통과시키면 조건을 안 건 것과 같아지고,
  /// 장소대여에는 기댈 옛 미러 필드가 없다.
  ///
  /// 넘기는 색인은 그 화면이 보는 컬렉션으로 만든 것이어야 한다
  /// ([rentalCollection] / [placeCollection]) — 목록과 지도가 **같은 함수에
  /// 같은 색인**을 넘기므로, 두 화면의 결과가 갈릴 수 없다.
  /// [doc]을 주면 날짜·시간 조건까지 함께 본다 — 영업중(전시간) 이벤트의
  /// 영업시간을 그 문서에서 읽기 때문이다. 안 주면 예전 그대로 "이벤트가 있는
  /// 곳인가"만 본다(기존 호출부는 아무것도 바뀌지 않는다).
  static bool allows({
    required bool eventOnly,
    required String? docId,
    required PlaceEventIndex? index,
    Map<String, dynamic>? doc,
    Iterable<DateTime> dates = const [],
    TimeOfDay? start,
    TimeOfDay? end,
    DateTime? now,
  }) {
    if (!eventOnly) return true;
    if (index == null) return false;
    if (dates.isEmpty && !DayTimeMatch.isActive(start, end)) {
      return index.has(docId);
    }
    return index.hasMatching(
      docId,
      dates: dates,
      start: start,
      end: end,
      hours: doc == null ? null : PlaceWeeklyHours.fromPlaceDoc(doc),
      now: now,
    );
  }

  /// 이벤트 목록에서 색인을 만든다.
  ///
  /// [promotions]는 걸러지지 않은 목록이어도 된다 — 노출 정책(숨김·종료 제외,
  /// 컬렉션 확인)을 여기서 다시 적용하므로, 호출부가 서버 쿼리로 무엇을
  /// 걸렀는지와 무관하게 결과가 같다.
  /// [collection]은 이 색인이 담을 원본 컬렉션이다 — 기본값은 매장·즐길거리
  /// ([placeCollection])이고, 장소대여 탭은 [rentalCollection]을 넘긴다.
  /// 넘긴 컬렉션이 아닌 이벤트는 전부 빠지므로 두 탭이 서로의 것을 볼 수 없다.
  static PlaceEventIndex fromPromotions(
    Iterable<PlacePromotion> promotions, {
    DateTime? now,
    String collection = placeCollection,
  }) {
    final at = now ?? DateTime.now();
    final ids = <String>{};
    final byPlace = <String, List<PlacePromotion>>{};
    final marks = <String>[];
    for (final p in promotions) {
      if (p.placeCollection != collection) continue;
      if (p.placeId.isEmpty) continue;
      if (!p.statusAt(at).isPublic) continue;
      ids.add(p.placeId);
      // 한 매장에 이벤트가 열 개여도 id는 하나지만, **이벤트는 전부 들고
      // 있어야** 날짜·시간 조건을 걸 수 있다(그중 하나만 맞아도 통과다).
      byPlace.putIfAbsent(p.placeId, () => <PlacePromotion>[]).add(p);
      marks.add(_signatureOf(p));
    }
    // 정렬해서 이어 붙인다 — 같은 이벤트들이면 순서가 달라도 같은 지문이다.
    marks.sort();
    return PlaceEventIndex(ids, byPlace, marks.join());
  }

  /// 판정에 쓰이는 값만 — 제목·사진이 바뀌었다고 목록을 다시 그리지 않는다.
  static String _signatureOf(PlacePromotion p) =>
      '${p.id}|${p.isAlways}|${p.startAt}|${p.endAt}'
      '|${p.weekdays.join(",")}|${p.startTime}|${p.endTime};';

  /// 같은 집합인지 — 스트림이 새 스냅샷을 줄 때마다 목록을 다시 그리지 않도록
  /// 호출부가 이 비교로 걸러 낸다.
  bool sameAs(PlaceEventIndex other) =>
      signature == other.signature &&
      placeIds.length == other.placeIds.length &&
      placeIds.containsAll(other.placeIds);
}
