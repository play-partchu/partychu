import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/services/content_delete_service.dart'
    show
        ContentDeleteException,
        ContentDeleteService,
        DeletableContent,
        DeleteScope;

/// 날짜 슬롯 ↔ 파티 문서 동기화 — **등록·편집·수정 화면이 모두 이 서비스를**
/// 쓴다.
///
/// ## 왜 서비스로 뺐나
///
/// 저장 구조는 "날짜 슬롯 1개 = `parties` 문서 1개"이고, 한 게시글의 날짜 문서는
/// 같은 `seriesId`로 묶인다. 그래서 날짜를 편집하면 문서를 **이어받고(update) ·
/// 새로 만들고(set) · 지워야(delete)** 한다.
///
/// 이 규칙이 화면마다 따로 있으면 "수정에서는 날짜를 못 늘리고, 재등록에서는
/// 늘어나는데 지운 날짜는 문서가 남는" 식으로 화면마다 동작이 갈린다(실제로
/// 그랬다). 이제 슬롯↔문서 판정은 여기 한 곳뿐이고, 화면은 "이 슬롯에 저장할
/// 필드"만 만들어 넘긴다.
///
/// ## 슬롯이 어느 문서였는지 찾는 순서
///  1. 문서에 저장해 둔 `dateSlotId` (정본)
///  2. 같은 시작 시각 (`dateSlotId`가 없던 예전 문서용 폴백)
///
/// 못 찾으면 새 문서다. 한 문서가 두 슬롯에 겹쳐 배정되지 않도록 배정된 id를
/// 따로 기억한다.
///
/// ## 날짜를 지울 때
///
/// 삭제는 **기존 삭제 흐름을 그대로 재사용**한다
/// ([ContentDeleteService.delete], scope: single). 그래서 "신청자가 있는 날짜는
/// 삭제 불가" 같은 정책이 서버 한 곳(`contentCleanup.js`의 blockingReason)에만
/// 있고, 사진·찜·신청서 정리까지 평소 삭제와 동일하게 처리된다. 여기서 문서를
/// 직접 지우면 그 정책과 정리 로직을 우회하게 된다.
class PartySlotSyncService {
  PartySlotSyncService._();

  /// 날짜(문서)마다 **따로 굴러가는 운영 상태** 필드들.
  ///
  /// 게시글 하나를 여러 날짜 문서로 나눠 저장하기 때문에, 수정 저장이 공통
  /// 정보를 시리즈 전체에 덮어쓰는 것은 맞다(제목·소개·카테고리·대표 이미지…).
  /// 하지만 아래 값들은 **그 날짜만의 상태**다 — 8/10이 모집 마감됐다고 8/13까지
  /// 마감으로 바뀌거나, 8/10의 신청 인원이 8/13에 복사되면 안 된다.
  ///
  /// 그래서 다른 날짜 문서를 갱신할 때는 [sharedOnly]로 이 키들을 걷어낸다.
  /// 판정을 화면이 아니라 여기 두는 이유는, 화면마다 목록이 갈리면 어느 화면에서
  /// 저장했는지에 따라 다른 날짜의 상태가 오염되기 때문이다.
  ///
  /// 모집 시작·마감 **시각**(`recruitOpenAt`/`recruitDeadlineAt`)은 여기 넣지
  /// 않는다 — 그 값은 각 슬롯의 날짜에 규칙을 적용해 **다시 계산**되므로 복사가
  /// 아니라 그 날짜 자신의 값이다.
  static const perDateStateKeys = <String>{
    // 모집 상태 · 취소/확정 상태
    'recruitStatus',
    // 성별별 모집 상태 — 모집 상태와 같은 성질이다. 8/10의 남성 모집을
    // 닫았다고 8/13까지 닫히면 안 된다([PartyGenderRecruit]).
    'genderRecruitStatus',
    'cancelReason',
    'cancelledBySystem',
    'autoCancelledAt',
    'minCapacityAtCancel',
    'participantsAtCancel',
    'cancelledAt',
    'confirmedAt',
    // 신청 인원 카운터
    'currentParticipants',
    'currentMaleCount',
    'currentFemaleCount',
    'people',
    // 신청자 명단
    'applicants',
    'approvedApplicants',
    'rejectedApplicants',
    // 회차별 카운터가 들어 있는 정기 파티 칸 — 그 날짜 문서의 회차별 인원·
    // 신청자 명단·차수 카운터가 전부 여기 있다. 다른 날짜 문서로 복사되면
    // 신청하지도 않은 회차에 인원이 생긴다. 서버(partyCapacity.js)만 쓴다.
    'occurrenceStats',
    // 문서 수명 — 한 날짜를 지웠다고 다른 날짜가 삭제 표시되면 안 된다
    'isDeleted',
    'deletedAt',
    'status',
    'isActive',
  };

  /// 시리즈 전체에 덮어써도 되는 **공통 정보만** 남긴다
  /// ([perDateStateKeys] 참고).
  static Map<String, dynamic> sharedOnly(Map<String, dynamic> fields) => {
    for (final entry in fields.entries)
      if (!perDateStateKeys.contains(entry.key)) entry.key: entry.value,
  };

  /// 차수 배열을 다시 만들 때, **그 문서의 현재 차수 카운터를 그대로 옮긴다.**
  ///
  /// 차수를 날짜에 맞춰 다시 계산하면(`PartyRound.toMap`) 현재 인원이 0으로
  /// 초기화된다 — 새 문서에는 맞지만 이미 신청자가 있는 문서에는 재앙이다.
  /// [existingRounds]에서 같은 `roundNumber`의 카운터를 찾아 덮어씌운다.
  ///
  /// ## 여기서 옮기는 것은 **최상단 `rounds[]` 카운터뿐**이다
  ///
  /// 호스트가 파티를 수정할 때 차수 정의(시각·정원·참가비)를 다시 만들면서
  /// 인원만 잃지 않게 하는 것이 이 함수의 전부다. 인원을 **늘리거나 줄이지
  /// 않는다** — 그건 서버 reserve/releaseApplicantSlot만 한다
  /// (functions/partyCapacity.js 상단 '정원 카운터의 소유권').
  ///
  /// 정기 파티의 차수 인원은 최상단이 아니라 `occurrenceStats.{회차}.rounds`에
  /// 회차별로 들어 있고, 이 화면은 그 필드를 **아예 쓰지 않는다**
  /// ([perDateStateKeys]에 있어 다른 날짜 문서로도 복사되지 않는다). 그래서
  /// 수정해도 회차별 인원은 그대로 보존된다.
  ///
  /// 여기서 회차 카운터까지 같이 옮기려 들면 안 된다 — 최상단 값은 회차 구분이
  /// 없는 수라, 어느 회차에 넣어도 틀린 값이 된다.
  static List<Map<String, dynamic>> carryOverRoundCounters(
    List<Map<String, dynamic>> rebuilt,
    dynamic existingRounds,
  ) {
    if (existingRounds is! List) return rebuilt;
    final byNumber = <int, Map<String, dynamic>>{};
    for (final raw in existingRounds) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final n = (m['roundNumber'] as num?)?.toInt();
      if (n != null) byNumber[n] = m;
    }
    if (byNumber.isEmpty) return rebuilt;

    const counters = [
      'currentParticipants',
      'currentMaleCount',
      'currentFemaleCount',
    ];
    return [
      for (final round in rebuilt)
        () {
          final n = (round['roundNumber'] as num?)?.toInt();
          final before = n == null ? null : byNumber[n];
          if (before == null) return round;
          return <String, dynamic>{
            ...round,
            for (final key in counters)
              if (before.containsKey(key)) key: before[key],
          };
        }(),
    ];
  }

  /// 시리즈의 기존 날짜 문서를 읽어 "무엇을 이어받고 무엇을 지울지" 계획을 세운다.
  ///
  /// [primaryDocId]는 지금 편집 중인 문서(신규 등록이면 null — 그때는 전부 새
  /// 문서가 된다).
  ///
  /// **편집 대상 문서를 첫 슬롯에 고정 배정하지 않는다.** 슬롯 목록은 날짜순으로
  /// 정렬돼 오므로, 8/13 문서를 열어 8/10을 추가하면 첫 슬롯이 8/10이 된다 —
  /// 그때 첫 슬롯을 8/13 문서에 강제로 붙이면 8/10 문서가 "지운 날짜"로 오해돼
  /// 삭제되고, 8/13 신청자가 8/10 문서로 옮겨 붙는다. 그래서 편집 대상도 다른
  /// 문서와 똑같이 `dateSlotId`/시작 시각으로 자기 날짜를 찾고, 못 찾았을 때만
  /// (= 사용자가 그 문서의 날짜를 바꾼 경우) 아직 주인이 없는 첫 슬롯을 맡는다.
  static Future<PartySlotSyncPlan> plan({
    required String seriesId,
    required String? primaryDocId,
    required List<PartyDateSlot> slots,
  }) async {
    final col = FirebaseFirestore.instance.collection('parties');
    final reusableBySlotId = <String, String>{};
    final reusableByStart = <int, String>{};
    final liveDocs = <String, Map<String, dynamic>>{};

    if (primaryDocId != null) {
      final snap = await col.where('seriesId', isEqualTo: seriesId).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['isDeleted'] == true || data['status'] == 'deleted') continue;
        liveDocs[doc.id] = data;
      }
      // `seriesId`가 없던 예전 문서는 위 쿼리에 안 잡힌다 — 편집 대상은 반드시
      // 후보에 있어야 하므로 따로 읽어 넣는다.
      if (!liveDocs.containsKey(primaryDocId)) {
        final self = await col.doc(primaryDocId).get();
        final data = self.data();
        if (data != null) liveDocs[primaryDocId] = data;
      }
      for (final entry in liveDocs.entries) {
        final slotId = entry.value['dateSlotId'] as String?;
        if (slotId != null && slotId.isNotEmpty) {
          reusableBySlotId.putIfAbsent(slotId, () => entry.key);
        }
        final ts = entry.value['partyDateTime'];
        if (ts is Timestamp) {
          reusableByStart.putIfAbsent(
            ts.toDate().millisecondsSinceEpoch,
            () => entry.key,
          );
        }
      }
    }

    // 1) 슬롯마다 "자기 문서"를 찾는다(dateSlotId → 시작 시각).
    final assigned = <String>{};
    final reuseDocIds = <String?>[
      for (final slot in slots)
        _reusableDocIdFor(
          slot,
          bySlotId: reusableBySlotId,
          byStart: reusableByStart,
          assigned: assigned,
        ),
    ];

    // 2) 편집 대상 문서가 어느 슬롯에도 배정되지 않았다면(= 그 문서의 날짜를
    //    바꾼 경우) 주인이 없는 첫 슬롯을 맡긴다 — 문서를 새로 만들고 옛 문서를
    //    지우는 대신 그대로 이어 쓴다(신청자·정원이 살아 있는 문서다).
    if (primaryDocId != null && !assigned.contains(primaryDocId)) {
      final free = reuseDocIds.indexOf(null);
      if (free >= 0) {
        reuseDocIds[free] = primaryDocId;
        assigned.add(primaryDocId);
      }
    }

    // 3) 아무 슬롯도 이어받지 않은 문서 = 사용자가 지운 날짜.
    final orphans =
        <PartySlotOrphan>[
          for (final entry in liveDocs.entries)
            if (!assigned.contains(entry.key))
              PartySlotOrphan(
                docId: entry.key,
                start: PartySchedule.startAt(entry.value),
                hasApplicants: hasLiveApplicants(entry.value),
              ),
        ]..sort((a, b) {
          final x = a.start;
          final y = b.start;
          if (x == null || y == null) return 0;
          return x.compareTo(y);
        });

    return PartySlotSyncPlan._(
      seriesId: seriesId,
      primaryDocId: primaryDocId,
      slots: slots,
      reuseDocIds: reuseDocIds,
      orphans: orphans,
      liveDocs: liveDocs,
    );
  }

  /// 신청자·참가자가 남아 있는 문서인지 — 삭제하면 안 되는 날짜를 저장 **전에**
  /// 알려주기 위한 클라이언트 사전 점검이다.
  ///
  /// 최종 판정은 언제나 서버(`contentCleanup.js`)가 한다. 여기서 먼저 걸러 주는
  /// 이유는, 저장을 눌러 절반쯤 진행된 뒤에 실패를 알리는 대신 "이 날짜는 지울
  /// 수 없다"를 미리 보여줄 수 있기 때문이다(판정 기준은
  /// `PlacePartyLink.hasApplicants`와 같다).
  static bool hasLiveApplicants(Map<String, dynamic> data) {
    int len(String key) => (data[key] as List?)?.length ?? 0;
    if (len('applicants') > 0 || len('approvedApplicants') > 0) return true;
    return ((data['currentParticipants'] as num?)?.toInt() ?? 0) > 0;
  }

  static String? _reusableDocIdFor(
    PartyDateSlot slot, {
    required Map<String, String> bySlotId,
    required Map<int, String> byStart,
    required Set<String> assigned,
  }) {
    final candidates = <String?>[bySlotId[slot.id]];
    final startTime = slot.startTime;
    if (startTime != null) {
      candidates.add(byStart[slot.start.millisecondsSinceEpoch]);
    }
    for (final id in candidates) {
      if (id != null && assigned.add(id)) return id;
    }
    return null;
  }
}

/// 지워질 날짜 문서 한 건.
@immutable
class PartySlotOrphan {
  final String docId;
  final DateTime? start;

  /// 신청자가 남아 있어 삭제할 수 없는 날짜 — 화면이 저장 전에 안내한다.
  final bool hasApplicants;

  const PartySlotOrphan({
    required this.docId,
    this.start,
    this.hasApplicants = false,
  });

  /// '8월 13일 (목)' — 안내 문구에 쓴다.
  String get label => start == null ? '날짜 미정' : formatPartyScheduleDate(start);
}

/// [PartySlotSyncService.plan]의 결과 — 그대로 [commit]에 넘겨 쓴다.
class PartySlotSyncPlan {
  final String seriesId;
  final String? primaryDocId;
  final List<PartyDateSlot> slots;

  /// [slots]와 같은 순서·길이. null이면 새 문서로 만든다.
  final List<String?> reuseDocIds;

  /// 슬롯에서 빠져 삭제 대상이 된 문서들.
  final List<PartySlotOrphan> orphans;

  /// 시리즈의 살아 있는 문서들(id → 데이터) — 갱신 대상 문서의 **현재 값**이다.
  /// 화면이 "이 문서의 기존 상태는 그대로 두기"를 판단하는 데 쓴다.
  final Map<String, Map<String, dynamic>> liveDocs;

  const PartySlotSyncPlan._({
    required this.seriesId,
    required this.primaryDocId,
    required this.slots,
    required this.reuseDocIds,
    required this.orphans,
    this.liveDocs = const {},
  });

  /// 신청자가 있어 지울 수 없는 날짜들 — 저장을 시작하기 전에 막아야 한다.
  List<PartySlotOrphan> get blockedOrphans =>
      orphans.where((o) => o.hasApplicants).toList();

  /// 지워도 되는 날짜들.
  List<PartySlotOrphan> get deletableOrphans =>
      orphans.where((o) => !o.hasApplicants).toList();

  int get createCount => reuseDocIds.where((id) => id == null).length;
  int get updateCount => reuseDocIds.length - createCount;

  /// 계획대로 저장한다 — 문서 쓰기는 배치 하나로, 삭제는 기존 삭제 흐름으로.
  ///
  /// [fieldsFor]는 그 슬롯에 저장할 **최종 필드**를 돌려준다. 콜백이 받는 값:
  ///  · `isUpdate` — 기존 문서인지 새 문서인지
  ///  · `docId`    — 저장 대상 문서 id(새 문서면 방금 발급된 id)
  ///  · `existing` — 그 문서의 **현재 값**(새 문서면 null)
  ///
  /// 이 셋이 있어야 화면이 규칙을 스스로 정할 수 있다 — 신규 문서에만
  /// hostId·createdAt을 넣거나, 다른 날짜 문서에는 [sharedOnly]로 공통 정보만
  /// 쓰거나, 차수 카운터를 그 문서의 기존 값으로 이어붙이는 일
  /// ([carryOverRoundCounters])이 전부 여기서 갈린다.
  ///
  /// 쓰기를 먼저 커밋하고 삭제를 나중에 한다 — 삭제가 실패해도(신청자가 생긴
  /// 경우 등) 편집한 내용은 이미 저장돼 있고, 남은 날짜 문서는 그대로 살아
  /// 있으니 데이터가 반쪽이 되지 않는다.
  Future<PartySlotSyncOutcome> commit({
    required Map<String, dynamic> Function(
      PartyDateSlot slot, {
      required bool isUpdate,
      required int index,
      required String docId,
      required Map<String, dynamic>? existing,
    })
    fieldsFor,
  }) async {
    final col = FirebaseFirestore.instance.collection('parties');
    final batch = FirebaseFirestore.instance.batch();
    final savedDocIds = <String>[];

    for (var i = 0; i < slots.length; i++) {
      final reuseId = reuseDocIds[i];
      final isUpdate = reuseId != null;
      final ref = isUpdate ? col.doc(reuseId) : col.doc();
      final fields = fieldsFor(
        slots[i],
        isUpdate: isUpdate,
        index: i,
        docId: ref.id,
        existing: isUpdate ? liveDocs[reuseId] : null,
      );
      if (isUpdate) {
        batch.update(ref, fields);
      } else {
        batch.set(ref, fields);
      }
      savedDocIds.add(ref.id);
    }
    debugPrint(
      '[$PartySlotSyncService] committing ${slots.length} doc(s) '
      '(new=$createCount, reused=$updateCount, '
      'orphans=${orphans.length})',
    );
    await batch.commit();

    // 지운 날짜 — 기존 삭제 흐름을 그대로 쓴다(정책·정리 로직 공유).
    final deleted = <String>[];
    final failures = <String, String>{};
    for (final orphan in deletableOrphans) {
      try {
        await ContentDeleteService.delete(
          type: DeletableContent.party,
          id: orphan.docId,
          scope: DeleteScope.single,
        );
        deleted.add(orphan.docId);
      } on ContentDeleteException catch (e) {
        failures[orphan.docId] = e.message;
      } catch (e) {
        failures[orphan.docId] = '$e';
      }
    }
    return PartySlotSyncOutcome(
      createdCount: createCount,
      updatedCount: updateCount,
      savedDocIds: savedDocIds,
      deletedDocIds: deleted,
      deleteFailures: failures,
    );
  }
}

/// 저장 결과 — 화면이 사용자에게 무엇이 바뀌었는지 알리는 데 쓴다.
@immutable
class PartySlotSyncOutcome {
  final int createdCount;
  final int updatedCount;

  /// 이번 저장으로 **살아남은 모든 날짜 문서**의 id(새로 만든 것 + 이어받은 것).
  ///
  /// 저장이 끝난 뒤에야 할 수 있는 후속 작업이 이 값을 쓴다 — 대표적으로
  /// 플레이스 연결이다. 연결은 파티 문서와 플레이스 문서를 함께 갱신하므로
  /// 파티 id가 먼저 있어야 하고, 날짜를 여러 개 고르면 그 날짜 문서 전부가
  /// 한 번에 연결돼야 한다.
  final List<String> savedDocIds;

  final List<String> deletedDocIds;

  /// 문서 id → 실패 이유(대개 "신청자가 남아 있어 삭제할 수 없습니다").
  final Map<String, String> deleteFailures;

  const PartySlotSyncOutcome({
    required this.createdCount,
    required this.updatedCount,
    this.savedDocIds = const [],
    this.deletedDocIds = const [],
    this.deleteFailures = const {},
  });

  bool get hasDeleteFailures => deleteFailures.isNotEmpty;
}
