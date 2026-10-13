import 'package:flutter/material.dart' show TimeOfDay;

import 'package:party_app/models/mobile_place_schedule.dart';

/// 🚚 이동형 플레이스를 **지도 핀 자리들**로 푸는 한 줄 다리.
///
/// ── 날짜 하나당 핀 하나 ─────────────────────────────────────────────────
/// 한 업체는 **하루에 한 장소**에서 영업한다. 그래서 날짜 하나에는 핀이
/// 하나(또는 없음)다. 사용자가 날짜를 여럿 고르면 **고른 날짜마다** 그 날의
/// 자리에 핀이 선다:
///
///     월 선택        → 홍대 1개
///     월+화 선택     → 홍대·강남 2개
///     월+화+수 선택  → 홍대·강남·여의도 3개
///     목(휴무) 선택  → 없음
///
/// 고르지 않은 날짜의 핀은 만들지 않는다. 날짜 조건이 비어 있으면 **오늘**을
/// 본다.
///
/// ── 왜 따로 꺼냈는가 ────────────────────────────────────────────────────
/// 지도 화면에 일정 계산을 두면, 같은 규칙이 목록·상세에도 복사되며 곧
/// 갈라진다. 그래서 "어느 좌표에 핀을 찍을까"만 여기서 정하고, **판정은 전부
/// [MobilePlaceSchedule]을 부른다** — 이 파일에는 시간 계산이 없다.
///
/// ── 고정형은 건드리지 않는다 ───────────────────────────────────────────
/// [MobilePinResolution.isMobile]이 false면 고정형이다. 호출부는 그때 예전
/// 경로(문서의 평면 `latitude`/`longitude`)를 한 글자도 바꾸지 않고 그대로
/// 쓴다. `isMobilePlace`가 없는 기존 문서는 전부 이 길로 간다.
abstract final class MobilePlacePins {
  /// 고른 날짜들에서 영업하는 **자리들**. 고정형이면
  /// [MobilePinResolution.fixed].
  ///
  /// · [dates]가 비면 **오늘**로 본다 — 조건을 걸지 않은 사용자에게는 "지금
  ///   어디서 하는가"가 답이고, 지난 일정을 지도에 남기지 않기 위해서다.
  /// · 시간은 **날짜마다** 영업 여부를 가리는 게이트다. 장소를 고르는 데 쓰지
  ///   않는다(한 날에 한 곳이므로 고를 것이 없다).
  /// · 휴무이거나 그 날 일정이 없는 날짜는 **건너뛴다** — 핀을 찍지 않는다.
  /// · 좌표가 없거나 시간 형식이 깨진 일정은 모델이 걸러 내므로 여기까지
  ///   오지 않는다.
  ///
  /// 돌려주는 목록은 **영업 시작 순**이고, 같은 영업이 두 번 담기지 않는다
  /// (아래 [dateKeyOf] 주석 참고).
  static MobilePinResolution resolve(
    Map<String, dynamic> data, {
    Set<DateTime> dates = const {},
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    DateTime? now,
  }) {
    final schedule = MobilePlaceSchedule.ofPlace(data);
    if (schedule == null) return const MobilePinResolution.fixed();

    final base = now ?? DateTime.now();
    final targets = dates.isEmpty
        ? <DateTime>[DateTime(base.year, base.month, base.day)]
        : (dates.toList()..sort());

    final openings = <PlaceOpening>[];
    final seen = <String>{};
    for (final date in targets) {
      final opening = schedule.openingFor(
        date: date,
        startTime: startTime,
        endTime: endTime,
      );
      if (opening == null) continue;
      if (seen.add(dateKeyOf(opening))) openings.add(opening);
    }
    openings.sort((a, b) => a.start.compareTo(b.start));
    return MobilePinResolution.mobile(openings);
  }

  /// 핀 하나를 가리키는 키 — **그 영업이 시작한 날짜**다.
  ///
  /// 한 업체는 하루에 한 곳에서 영업하므로 날짜 하나가 영업 하나를 가린다.
  /// 그래서 이 값이 마커 id를 가르는 데 그대로 쓰인다
  /// ([MapListing.key]).
  ///
  /// 고른 날짜가 아니라 **영업의 날짜**를 쓰는 이유: 자정을 넘기는 영업은
  /// 두 날짜 질의에 모두 걸린다(금 22:00~02:00은 금요일과 토요일 조건 양쪽에
  /// 나온다). 고른 날짜로 키를 만들면 **같은 영업에 핀이 두 개** 생겨 같은
  /// 자리에 겹쳐 쌓인다. 영업의 날짜로 묶으면 그 건은 금요일 핀 하나로
  /// 남고, 서로 다른 날의 영업은(같은 좌표라도) 각각 남는다 — 날짜 정보가
  /// 사라지지 않는다.
  static String dateKeyOf(PlaceOpening opening) =>
      ScheduleException.dateKeyOf(opening.start);
}

/// [MobilePlacePins.resolve]의 답.
///
/// `List<PlaceOpening>?`으로는 **"고정형이다"와 "이동형인데 고른 날짜에 전부
/// 쉰다"**를 구분할 수 없다. 둘을 섞으면 쉬는 트럭이 기준 좌표에 핀을 남기거나,
/// 고정형 가게가 지도에서 사라진다. 그래서 이름 있는 두 상태로 둔다.
class MobilePinResolution {
  /// 고정형 — 호출부는 예전 경로(문서의 `latitude`/`longitude`)를 그대로 쓴다.
  const MobilePinResolution.fixed() : openings = const [], isMobile = false;

  /// 이동형 — 고른 날짜들에서 영업하는 자리들(비어 있을 수 있다).
  const MobilePinResolution.mobile(this.openings) : isMobile = true;

  /// 영업 시작 순. 이동형이 아니면 언제나 빈 목록이다.
  final List<PlaceOpening> openings;

  final bool isMobile;

  /// 핀을 올려야 하는가 — 고정형은 언제나, 이동형은 영업이 있을 때만.
  bool get hasPin => !isMobile || openings.isNotEmpty;
}
