import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:party_app/models/payment_status.dart';
import 'package:party_app/models/place_rental_reservation.dart';
import 'package:party_app/models/place_visit_reservation.dart';
import 'package:party_app/services/place_rental_reservation_service.dart';
import 'package:party_app/services/place_visit_reservation_service.dart';
import 'package:party_app/utils/applicant_identity.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 통합 신청자·예약자 관리 — **네 종류를 한 목록으로**.
//
// 호스트는 지금까지 파티는 파티대로(파티 카드의 '신청자'), 플레이스는 플레이스
// 대로(방문 예약 관리), 공간대여는 또 따로(예약 관리) 들어가야 했다. 종류가
// 늘수록 "어디에 처리할 게 남았는지"를 사람이 기억해야 했고, 그래서 승인제
// 파티의 pending 신청이 며칠씩 방치되기도 했다.
//
// **새 컬렉션을 만들지 않는다.** 여기서 하는 일은 기존 신청/예약 문서를 그대로
// 읽어 한 줄 모양으로 맞추는 것뿐이고, 승인·거절·입금확인은 전부 기존 화면과
// 기존 콜러블이 그대로 한다.
//
// 왜 파티만 콜러블인가
//   예약 3종은 문서에 `requesterName`·`placeName`이 이미 들어 있어 앱이 바로
//   읽는다. 파티 신청 문서에는 신청자 uid만 있고 닉네임·실명은 users 문서에
//   있는데, 그건 규칙상 본인·관리자만 읽을 수 있다 — 호스트가 신청자 이름을
//   보려면 호스트임을 검사하는 서버를 반드시 거쳐야 한다
//   (functions/index.js의 getHostApplicationInbox, getApplicants와 같은 이유).
// ─────────────────────────────────────────────────────────────────────────────

/// 통합 목록에 섞이는 네 가지.
enum HostInboxKind {
  party('파티', 'party'),
  visit('플레이스', 'visit'),
  rental('장소대여', 'rental'),

  /// 숙박+파티 콤보 — 관리 화면과 콜러블은 장소대여와 같은 것을 쓴다.
  /// 배지만 갈라 두는 이유는 호스트가 "파티도 함께 잡힌 예약"임을 알아야
  /// 하기 때문이다.
  package('숙박+파티', 'package');

  const HostInboxKind(this.label, this.key);

  final String label;
  final String key;
}

/// 필터 네 개 — 상단 알약.
enum HostInboxFilter {
  all('전체'),
  needsAction('처리 필요'),
  confirmed('승인·확정'),
  closed('취소·거절');

  const HostInboxFilter(this.label);

  final String label;

  bool matches(HostInboxEntry e) => switch (this) {
    HostInboxFilter.all => true,
    HostInboxFilter.needsAction => e.state == HostInboxState.needsAction,
    HostInboxFilter.confirmed => e.state == HostInboxState.confirmed,
    HostInboxFilter.closed => e.state == HostInboxState.closed,
  };

  String get emptyText => switch (this) {
    HostInboxFilter.all => '들어온 신청이나 예약이 아직 없어요.',
    HostInboxFilter.needsAction => '지금 처리할 신청·예약이 없어요.',
    HostInboxFilter.confirmed => '승인·확정된 건이 없어요.',
    HostInboxFilter.closed => '취소·거절된 건이 없어요.',
  };
}

/// 한 건이 어느 묶음인지. **판정은 이 세 값이 전부**다.
enum HostInboxState {
  /// 호스트가 지금 해야 할 일이 남은 건 — 승인 대기, 입금 확인 대기.
  needsAction,

  /// 처리가 끝나 살아 있는 건 — 승인·확정·참석.
  confirmed,

  /// 끝난 건 — 취소·거절·만료.
  closed,
}

/// 통합 목록의 한 줄.
@immutable
class HostInboxEntry {
  final HostInboxKind kind;

  /// 신청/예약 문서 id — 목록 정렬 안정화와 위젯 키에 쓴다.
  final String id;

  /// 파티명 · 플레이스명 · 장소명.
  final String contentTitle;

  /// 신청자/예약자 — 닉네임(실명) 또는 예약자명.
  final String personLabel;

  /// 화면에 보여줄 **신청/예약 날짜**. 정기 파티는 회차 시작 시각이다.
  final DateTime? at;

  /// 목록 정렬 기준(들어온 순서). 날짜가 없는 건도 자리를 잃지 않도록 따로 둔다.
  final DateTime? receivedAt;

  /// '승인 대기' · '입금확인중' · '예약 확정' 처럼 그대로 그리는 문구.
  final String statusLabel;

  final HostInboxState state;

  /// 파티 신청일 때만 채워진다 — 탭하면 이 파티의 신청자 화면을 연다.
  final String? partyId;

  /// 부가 한 줄(패키지명 · 룸 이름 등). 없으면 그리지 않는다.
  final String? subtitle;

  const HostInboxEntry({
    required this.kind,
    required this.id,
    required this.contentTitle,
    required this.personLabel,
    required this.statusLabel,
    required this.state,
    this.at,
    this.receivedAt,
    this.partyId,
    this.subtitle,
  });

  bool get unhandled => state == HostInboxState.needsAction;
}

/// 한 번에 받은 통합 목록.
@immutable
class HostInboxSnapshot {
  final List<HostInboxEntry> entries;

  /// 파티 신청을 못 불러왔다 — 예약은 그대로 보여주고 이 사실만 따로 알린다.
  /// (전부 실패로 처리하면 파티 조회 하나 때문에 멀쩡한 예약까지 사라진다.)
  final bool partyFailed;

  /// 파티 신청이 상한(서버 300건)에 걸려 잘렸다.
  final bool truncated;

  const HostInboxSnapshot({
    this.entries = const [],
    this.partyFailed = false,
    this.truncated = false,
  });

  int get unhandledCount => entries.where((e) => e.unhandled).length;
}

class HostInboxService {
  HostInboxService._();

  /// 파티 신청 상태 → 화면 문구. 서버가 쓰는 문자열과 1:1이다.
  static const _partyStatusLabel = {
    'pending': '승인 대기',
    'applied': '신청 접수',
    'approved': '승인 완료',
    'attended': '참석 완료',
    'rejected': '거절됨',
    'cancelled': '취소됨',
    'no_show': '노쇼',
  };

  static const _closedPartyStatuses = {'rejected', 'cancelled'};

  /// 내 파티·플레이스·장소로 들어온 신청/예약 **전부**.
  ///
  /// 예약 3종은 Firestore 스트림이라 승인하면 곧바로 목록이 바뀌고, 파티 신청은
  /// 콜러블이라 한 번 받아 온다(호스트 권한 검사를 서버가 해야 신청자 이름을
  /// 내려줄 수 있다). 그래서 파티 쪽을 새로 고치려면 이 스트림을 다시 만든다 —
  /// 화면이 `setState`로 스트림을 갈아끼우는 방식이다(party_applicants_screen이
  /// Future를 갈아끼우는 것과 같다).
  static Stream<HostInboxSnapshot> watch(String uid) {
    if (uid.isEmpty) return Stream.value(const HostInboxSnapshot());

    final subscriptions = <StreamSubscription<dynamic>>[];
    var visit = const <HostInboxEntry>[];
    var rental = const <HostInboxEntry>[];
    var package = const <HostInboxEntry>[];
    var party = const <HostInboxEntry>[];
    var partyFailed = false;
    var truncated = false;

    late final StreamController<HostInboxSnapshot> controller;

    void emit() {
      if (controller.isClosed) return;
      final all = [...party, ...visit, ...rental, ...package];
      // 최신순 — 들어온 시각이 없는 옛 문서는 맨 뒤로 보낸다(0으로 채우면
      // 1970년으로 취급돼 목록 맨 아래에 뒤섞인다).
      all.sort((a, b) {
        final at = a.receivedAt;
        final bt = b.receivedAt;
        if (at == null && bt == null) return a.id.compareTo(b.id);
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
      controller.add(
        HostInboxSnapshot(
          entries: all,
          partyFailed: partyFailed,
          truncated: truncated,
        ),
      );
    }

    controller = StreamController<HostInboxSnapshot>(
      onListen: () {
        subscriptions.add(
          PlaceVisitReservationService.hostReservations(uid).snapshots().listen(
            (snap) {
              visit = snap.docs
                  .map(PlaceVisitReservation.fromDoc)
                  .map(_fromVisit)
                  .toList();
              emit();
            },
            onError: controller.addError,
          ),
        );
        subscriptions.add(
          PlaceRentalReservationService.hostReservations(
            uid,
          ).snapshots().listen((snap) {
            rental = snap.docs
                .map((d) => PlaceRentalReservation.fromDoc(d))
                .map(_fromRental)
                .toList();
            emit();
          }, onError: controller.addError),
        );
        subscriptions.add(
          PlaceRentalReservationService.hostPackageBookings(
            uid,
          ).snapshots().listen((snap) {
            package = snap.docs
                .map(
                  (d) => PlaceRentalReservation.fromDoc(
                    d,
                    source: RentalSource.package,
                  ),
                )
                .map(_fromRental)
                .toList();
            emit();
          }, onError: controller.addError),
        );

        // 파티는 한 번만 받아 온다. 실패해도 예약 목록은 그대로 살린다.
        fetchPartyApplications()
            .then((result) {
              party = result.entries;
              truncated = result.truncated;
              partyFailed = false;
            })
            .catchError((Object e) {
              debugPrint('[HostInbox] 파티 신청 조회 실패: $e');
              party = const [];
              partyFailed = true;
            })
            .whenComplete(emit);
      },
      onCancel: () async {
        for (final s in subscriptions) {
          await s.cancel();
        }
      },
    );

    return controller.stream;
  }

  /// 호스트가 가진 **모든 파티**의 신청 — `getHostApplicationInbox`.
  static Future<({List<HostInboxEntry> entries, bool truncated})>
  fetchPartyApplications() async {
    final result = await FirebaseFunctions.instanceFor(
      region: 'asia-northeast3',
    ).httpsCallable('getHostApplicationInbox').call<Map<Object?, Object?>>();

    final raw = (result.data['items'] as List<Object?>?) ?? const [];
    return (
      entries: raw
          .whereType<Map<Object?, Object?>>()
          .map(_fromPartyApplication)
          .toList(),
      truncated: result.data['truncated'] == true,
    );
  }

  // ── 문서 한 건 → 목록 한 줄 ────────────────────────────────────────────

  static HostInboxEntry _fromPartyApplication(Map<Object?, Object?> m) {
    final status = m['status'] as String? ?? 'applied';
    final payment = (m['payment'] as Map?)?.map(
      (k, v) => MapEntry(k.toString(), v),
    );
    final paymentStatus = PaymentStatus.fromKey(payment?['status'] as String?);
    // 미처리 판정은 **서버 값을 그대로 믿는다** — 배지 숫자와 필터가 갈리지
    // 않으려면 판정이 한 곳이어야 한다(functions/hostInbox.js).
    final unhandled = m['unhandled'] == true;

    // 상태 문구는 "지금 호스트가 무엇을 봐야 하는가"를 우선한다. 무통장입금
    // 신청은 신청 상태(applied)보다 결제 상태(입금확인중)가 할 일을 말해준다.
    final base = _partyStatusLabel[status] ?? status;
    final label = unhandled && status != 'pending' && paymentStatus != null
        ? paymentStatus.label
        : base;

    final title = (m['partyTitle'] as String? ?? '').trim();
    return HostInboxEntry(
      kind: HostInboxKind.party,
      id: '${m['partyId'] ?? ''}_${m['applicationId'] ?? ''}',
      contentTitle: title.isNotEmpty
          ? title
          : (m['partyDeleted'] == true ? '(삭제된 파티)' : '내 파티'),
      personLabel: ApplicantIdentity.fromMap(
        m['identity'] as Map<Object?, Object?>?,
      ).personLabel,
      at: _fromMs(m['startAtMs']),
      receivedAt: _fromMs(m['appliedAtMs']),
      statusLabel: label,
      state: unhandled
          ? HostInboxState.needsAction
          : (_closedPartyStatuses.contains(status)
                ? HostInboxState.closed
                : HostInboxState.confirmed),
      partyId: m['partyId'] as String?,
      subtitle: m['applicationType'] == 'package'
          ? (m['packageName'] as String?)
          : null,
    );
  }

  static HostInboxEntry _fromVisit(PlaceVisitReservation r) {
    final unhandled =
        r.status == VisitReservationStatus.requested ||
        r.payment?.status == PaymentStatus.depositPending;
    return HostInboxEntry(
      kind: HostInboxKind.visit,
      id: r.id,
      contentTitle: r.placeName,
      personLabel: r.requesterName.isEmpty ? '이름 없음' : r.requesterName,
      at: r.visitAt,
      receivedAt: r.createdAt ?? r.visitAt,
      statusLabel: r.payment?.status == PaymentStatus.depositPending
          ? PaymentStatus.depositPending.label
          : r.status.label,
      state: unhandled
          ? HostInboxState.needsAction
          : (r.status.isLive
                ? HostInboxState.confirmed
                : HostInboxState.closed),
      subtitle: '${r.peopleCount}명',
    );
  }

  static HostInboxEntry _fromRental(PlaceRentalReservation r) {
    final unhandled =
        r.status == PlaceRentalStatus.requested ||
        r.payment?.status == PaymentStatus.depositPending;
    return HostInboxEntry(
      kind: r.source == RentalSource.package
          ? HostInboxKind.package
          : HostInboxKind.rental,
      id: r.id,
      contentTitle: r.placeName,
      personLabel: r.requesterName.isEmpty ? '이름 없음' : r.requesterName,
      at: r.useStartAt,
      receivedAt: r.createdAt ?? r.useStartAt,
      statusLabel: r.payment?.status == PaymentStatus.depositPending
          ? PaymentStatus.depositPending.label
          : r.status.label,
      state: unhandled
          ? HostInboxState.needsAction
          : (r.status.isLive
                ? HostInboxState.confirmed
                : HostInboxState.closed),
      subtitle: r.packageName ?? r.roomName,
    );
  }

  static DateTime? _fromMs(Object? value) {
    final ms = (value as num?)?.toInt();
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  }
}
