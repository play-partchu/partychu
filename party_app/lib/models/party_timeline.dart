import 'package:party_app/models/party_round_offer.dart';
import 'package:party_app/models/party_schedule.dart';

/// "이 일정이 이미 지났는가"를 판정하는 곳.
///
/// ## 왜 한 곳에 모으는가
///
/// 목록의 대표 일정("가장 가까운 다음 일정", [PartySeries.collapse])과 상세의
/// "날짜 선택"이 각자 판정하면 같은 파티가 목록에서는 8/13, 상세에서는 8/10을
/// 가리키게 된다. 두 화면이 **같은 함수**를 부르게 해서 어긋날 수 없게 한다.
///
/// ## 기준은 시작이 아니라 종료 시각
///
/// 오후 8시에 시작해 11시에 끝나는 파티는 9시에도 여전히 오늘의 일정이다.
/// 시작 시각만 보면 파티가 열리자마자 '지난 일정'이 되어 목록·상세에서
/// 사라진다. 그래서 종료 시각으로 판정하고, 종료 시각은 늦은 쪽이 이긴다:
///
/// 1. 회차 자체의 종료([PartyOccurrence.end]) — 일회성은 그 문서의
///    `singleSchedule.endTime`, 정기 파티는 그 요일 슬롯의 종료 시각이다.
/// 2. 차수(1차·2차 …)의 종료. 차수 시각은 문서에 캐시된 절대 시각이 아니라
///    **그 회차 날짜에 맞춰 다시 계산한다**([PartyRoundOffers.windowOf]) —
///    상세의 "차수 및 참가비"가 쓰는 재계산과 같은 기준이라, 아직 열리지도
///    않은 차수를 종료로 보는 어긋남이 생기지 않는다.
/// 3. 종료 시각을 아예 저장하지 않은 레거시 문서는 [PartyOccurrence.end]가
///    시작 시각과 같으므로, 예전 판정("시작했으면 지난 일정")이 그대로 남는다.
class PartyTimeline {
  PartyTimeline._();

  /// 이 문서의 [occurrence](없으면 [now] 기준 다음 회차)가 실제로 끝나는 시각.
  /// 남은 회차가 없는 정기 파티는 null.
  static DateTime? endAt(
    Map<String, dynamic> data, {
    DateTime? now,
    PartyOccurrence? occurrence,
  }) {
    final occ = occurrence ?? PartySchedule.nextOccurrence(data, now: now);
    if (occ == null) return null;
    var end = occ.end;
    for (final round in PartyRoundOffers.roundsOf(data)) {
      final window = PartyRoundOffers.windowOf(round, occ.start);
      if (window != null && window.end.isAfter(end)) end = window.end;
    }
    return end;
  }

  /// 이 문서의 회차가 [now] 기준으로 이미 끝났는지.
  static bool hasEnded(
    Map<String, dynamic> data, {
    DateTime? now,
    PartyOccurrence? occurrence,
  }) {
    final at = now ?? DateTime.now();
    final end = endAt(data, now: at, occurrence: occurrence);
    // 회차를 못 찾은 경우는 두 가지다. 정기 파티는 운영 종료일이 지나 더
    // 열리지 않는다는 뜻이므로 끝난 것으로 보고, 일회성 파티는 날짜를 읽지
    // 못한 것뿐이라 끝났다고 단정하지 않는다(예전 판정도 그대로 뒀다).
    if (end == null) return PartySchedule.isRecurring(data);
    return !at.isBefore(end);
  }
}
