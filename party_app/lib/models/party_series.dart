import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show immutable;

import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/models/party_timeline.dart';

/// "게시글 하나 = 여러 날짜"를 목록에서 카드 한 장으로 보여주기 위한 묶음 로직.
///
/// ## 왜 필요한가
///
/// 저장 구조는 **날짜 슬롯 1개 = `parties` 문서 1개**다(등록 화면이 슬롯마다
/// 문서를 하나씩 만들고 같은 `seriesId`로 묶는다). 정원·모집 마감·차수·패키지·
/// 신청자(`applications` 서브컬렉션)가 모두 문서 단위라 날짜별로 독립적으로
/// 굴러가야 하므로, 이 구조 자체는 그대로 두는 것이 맞다.
///
/// 문제는 목록이 그 문서를 1:1로 그려서 8/10·8/13을 등록하면 같은 파티 카드가
/// 2장 보였다는 것이다. 그래서 **표시할 때만** 시리즈로 묶어 카드 한 장으로
/// 접고, 대표는 "가장 가까운 다음 일정"으로 고른다. 사용자에게는 파티 하나로
/// 보이지만 신청·정원·결제 로직은 예전 그대로 문서 단위로 돌아간다.
///
/// ## 레거시 호환
///
/// `seriesId`가 없던 예전 문서는 **자기 문서 id를 시리즈 id로 본다**([idOf]) —
/// 삭제 흐름(`content_delete_service.dart`)이 이미 쓰는 것과 같은 폴백이라,
/// 그 문서들은 지금처럼 카드 한 장으로 그대로 보인다.
class PartySeries {
  PartySeries._(this._slotCounts);

  /// 시리즈 id → 살아 있는(삭제되지 않은) 일정 문서 수.
  final Map<String, int> _slotCounts;

  /// 문서의 시리즈 id — 없으면 문서 자신의 id(레거시 문서는 곧 시리즈 하나다).
  static String idOf(Map<String, dynamic> data, String docId) {
    final raw = (data['seriesId'] as String?)?.trim();
    return raw != null && raw.isNotEmpty ? raw : docId;
  }

  /// 이 문서가 목록에 나올 수 있는 상태인지 — 삭제된 문서는 대표가 되어서도,
  /// 일정 개수에 세어져서도 안 된다.
  static bool isVisible(Map<String, dynamic> data) =>
      data['isDeleted'] != true && data['status'] != 'deleted';

  /// **필터 이전의 전체 문서 집합**으로 일정 개수를 센다.
  ///
  /// 개수를 필터 이후 집합에서 세면 "오늘" 필터를 켰을 때 3일짜리 파티가
  /// "일정 1개"로 보인다 — 배지는 파티가 실제로 며칠 열리는지를 말해야 하므로
  /// 항상 전체 집합을 기준으로 센다.
  factory PartySeries.index(Iterable<QueryDocumentSnapshot> allDocs) {
    final counts = <String, int>{};
    for (final doc in allDocs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null || !isVisible(data)) continue;
      final id = idOf(data, doc.id);
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return PartySeries._(counts);
  }

  /// 이 문서가 속한 시리즈의 일정 수(최소 1).
  int slotCountOf(Map<String, dynamic> data, String docId) =>
      _slotCounts[idOf(data, docId)] ?? 1;

  /// 시리즈마다 대표 문서 하나만 남긴다 — 입력 순서(정렬 결과)는 그대로 지킨다.
  ///
  /// 대표는 **가장 가까운 다음 일정**이다. 남은 일정이 없으면(전부 지난 파티)
  /// 가장 나중 일정을 대표로 둔다 — 그래야 지난 파티도 목록에서 사라지지 않고
  /// 예전과 같은 자리에 남는다.
  ///
  /// 필터·정렬을 **끝낸 뒤에** 부르는 것을 전제로 한다(숨겨질 문서가 대표로
  /// 뽑히면 그 시리즈가 목록에서 통째로 사라진다).
  List<QueryDocumentSnapshot> collapse(
    List<QueryDocumentSnapshot> docs, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    // 시리즈별 대표를 고르되, 목록에 처음 등장한 위치를 그대로 지킨다 —
    // 여기서 순서를 바꾸면 호출부가 방금 적용한 정렬이 무너진다.
    final order = <String>[];
    final best = <String, _Candidate>{};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final id = idOf(data, doc.id);
      // 회차 계산은 문서마다 한 번만 한다 — 비교할 때마다 다시 계산하면 같은
      // 문서의 일정을 목록 길이만큼 반복해서 풀게 된다.
      final occurrence = PartySchedule.nextOccurrence(data, now: at);
      final candidate = (
        doc: doc,
        start: occurrence?.start,
        ended: PartyTimeline.hasEnded(data, now: at, occurrence: occurrence),
      );
      final current = best[id];
      if (current == null) {
        order.add(id);
        best[id] = candidate;
        continue;
      }
      if (_isBetterRepresentative(candidate, current)) best[id] = candidate;
    }
    return [for (final id in order) best[id]!.doc];
  }

  /// [candidate]가 [current]보다 대표로 적합한지.
  ///
  /// 1) 다가오는 일정이 지난 일정보다 우선
  /// 2) 둘 다 다가오면 더 이른 쪽
  /// 3) 둘 다 지났으면 더 나중 쪽(가장 최근에 열린 회차)
  ///
  /// "지났는지"는 시작이 아니라 **실제 종료 시각**으로 본다([PartyTimeline]) —
  /// 상세 화면의 날짜 선택이 지난 일정을 걸러낼 때 쓰는 것과 같은 판정이라,
  /// 목록 카드의 대표 날짜와 상세의 "다음 일정"이 어긋날 수 없다. 진행 중인
  /// 파티(8시 시작·11시 종료를 9시에 보는 경우)도 아직 지나지 않은 일정이다.
  static bool _isBetterRepresentative(
    _Candidate candidate,
    _Candidate current,
  ) {
    final a = candidate.start;
    final b = current.start;
    if (a == null) return false;
    if (b == null) return true;
    final aUpcoming = !candidate.ended;
    final bUpcoming = !current.ended;
    if (aUpcoming != bUpcoming) return aUpcoming;
    return aUpcoming ? a.isBefore(b) : a.isAfter(b);
  }
}

/// 대표를 고르는 동안 문서 하나에 대해 미리 풀어 둔 판정 결과 —
/// `start`는 이 문서의 시작 시각(정기 파티는 "지금 기준 다음 회차"),
/// `ended`는 그 회차가 이미 끝났는지([PartyTimeline.hasEnded])다.
typedef _Candidate = ({QueryDocumentSnapshot doc, DateTime? start, bool ended});

/// 상세 화면의 "날짜 및 시간 선택"에 쓰는 일정 한 건 — 같은 시리즈의 문서
/// 하나가 곧 일정 하나다.
///
/// 신청·정원·마감이 전부 문서 단위이므로 [docId]를 함께 들고 다닌다. 사용자가
/// 다른 날짜를 고르면 상세 화면이 **그 문서로 대상을 바꿔** 이어서 진행한다.
@immutable
class PartyScheduleOption {
  final String docId;
  final DateTime start;
  final DateTime? end;

  /// 이 일정이 지금 신청을 받는 상태인지 — 마감·모집 시작 시각까지 반영한다.
  final bool recruiting;

  /// 못 고르는 이유('모집 마감' 등). null이면 선택 가능.
  final String? blockedReason;

  const PartyScheduleOption({
    required this.docId,
    required this.start,
    this.end,
    this.recruiting = true,
    this.blockedReason,
  });

  /// '2026년 8월 10일 (월)' — **날짜만** 적는다.
  ///
  /// 시작·종료 시각은 바로 다음 단계인 차수(1차/2차) 선택에서 다시 고르므로,
  /// 날짜를 고르는 단계에서 함께 보여주면 같은 정보가 두 번 나오고 무엇을
  /// 고르는 단계인지 흐려진다.
  String get label => formatPartyScheduleDate(start);

  /// 카드·요약용 짧은 표기 — '8월 10일(월)'. [label]과 같은 이유로 시간은 뺀다.
  String get shortLabel {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${start.month}월 ${start.day}일(${weekdays[start.weekday - 1]})';
  }
}
