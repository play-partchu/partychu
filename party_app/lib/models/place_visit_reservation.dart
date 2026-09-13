// ─────────────────────────────────────────────────────────────────────────────
// 플레이스 **무료 방문 예약** — 설정·예약 1건·가능 시간 계산을 한곳에 모은 모델.
//
// 장소대여의 "공간 예약"([PlaceAvailability]/placeReservationGroups)과는 **다른
// 기능**이다. 공간대여는 룸을 통째로 빌려 그 시간을 독점하지만, 방문 예약은
// 매장에 "몇 시에 몇 명 갈게요"를 알리는 것이라 같은 시간대에 여러 팀이 들어갈
// 수 있고 정원은 좌석 총량으로만 센다. 그래서 데이터도 컬렉션도 섞지 않는다.
//
// 유료 좌석 상품([PlaceProductType.seatReservation] = '유료 좌석권')과도 다르다 —
// 그쪽은 결제하고 QR 이용권을 받는 **상품 구매**이고, 이쪽은 결제가 없는 **방문
// 요청**이다. 화면 문구도 '방문 예약' / '좌석권 구매'로 확실히 갈라 쓴다.
//
// Firestore 저장 형태
//   events/{eventId}.visitReservation          ← 업주 설정(맵 하나)
//   placeVisitReservations/{reservationId}     ← 예약 1건(비공개: 본인·업주·관리자)
//   events/{eventId}/visitSlots/{dateKey_HHmm} ← 시간대별 예약 인원 합계(공개)
//
// 계산은 전부 이 파일에 있고(순수 함수), 조회·쓰기는 서버(Functions)와 화면이
// 맡는다 — 서버(placeVisitReservations.js)도 같은 규칙을 구현하므로, 규칙이
// 바뀌면 **두 곳을 함께** 고쳐야 한다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show TimeOfDay;

import 'package:party_app/models/check_in_pass.dart';
import 'package:party_app/models/check_in_result.dart' show CheckInDomain;
import 'package:party_app/models/payment_method.dart';
import 'package:party_app/models/payment_status.dart';
import 'package:party_app/models/place_weekly_hours.dart';

/// 업주가 고르는 승인 방식.
enum VisitApprovalMode {
  /// 신청 즉시 확정 — 자리만 있으면 업주가 손대지 않아도 예약이 잡힌다.
  auto('auto', '자동 승인', '신청하면 바로 확정돼요'),

  /// 업주가 승인해야 확정 — 확인하고 받고 싶은 매장용(기본값).
  manual('manual', '승인 후 확정', '내가 확인하고 승인한 예약만 확정돼요');

  const VisitApprovalMode(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static VisitApprovalMode fromKey(String? key) =>
      values.firstWhere((m) => m.key == key, orElse: () => manual);
}

/// 예약 1건의 상태. 서버(placeVisitReservations.js)가 쓰는 문자열과 1:1이다.
///
/// 방문 완료·노쇼는 이번 범위가 아니다(다음 단계) — 값을 미리 만들어 두면
/// 화면마다 "언제 쓰는 상태인지" 헷갈리므로 넣지 않았다.
enum VisitReservationStatus {
  requested('requested', '승인 대기', true),
  approved('approved', '예약 확정', true),
  rejected('rejected', '거절됨', false),
  cancelledByGuest('cancelled_by_guest', '예약 취소', false),
  cancelledByHost('cancelled_by_host', '매장 취소', false),
  expired('expired', '기한 만료', false);

  const VisitReservationStatus(this.key, this.label, this.isLive);

  final String key;
  final String label;

  /// 아직 살아 있는 예약인지 — 목록의 '진행중' 탭과 정원 계산에 쓴다.
  final bool isLive;

  static VisitReservationStatus fromKey(String? key) =>
      values.firstWhere((s) => s.key == key, orElse: () => requested);
}

/// 예약금을 매기는 방식.
///
/// 지금은 1인당 하나뿐이다. 값이 하나뿐인 enum을 두는 이유는 나중에
/// '예약 1건당 고정액'을 더할 때 저장 구조를 바꾸지 않아도 되게 하기 위함이다
/// (필드는 이미 있고 값만 늘어난다).
enum VisitDepositType {
  /// 1인당 예약금 × 인원.
  perPerson('per_person', '1인당'),

  /// 예약 1건당 고정액 — **아직 지원하지 않는다**(자리만 잡아 둔 값).
  perBooking('per_booking', '예약당');

  const VisitDepositType(this.key, this.label);

  final String key;
  final String label;

  static VisitDepositType fromKey(String? key) =>
      values.firstWhere((t) => t.key == key, orElse: () => perPerson);
}

/// 플레이스 한 곳의 방문 예약 설정 — `events/{id}.visitReservation`.
class PlaceVisitReservationConfig {
  /// 예약 받기 ON/OFF. 꺼져 있으면 상세 화면에 예약 버튼 자체가 없다.
  final bool enabled;

  final VisitApprovalMode approvalMode;

  /// 예약 시각 간격(분) — 30이면 18:00/18:30/19:00…
  final int slotMinutes;

  /// 예약을 받는 시간대. null이면 그날 영업시간 전체에서 받는다.
  /// (1차 버전은 요일별 구분 없이 하루 한 구간만 — 요일별로 다르게 받는
  /// 매장이 나오면 그때 요일별 맵으로 넓힌다.)
  final TimeOfDay? openFrom;
  final TimeOfDay? openTo;

  /// 한 팀이 머무는 시간(분) — 정원을 어느 시간대까지 차지하는지 정한다.
  final int stayMinutes;

  final int minPeople;
  final int maxPeople;

  /// 같은 시각에 받을 수 있는 총 인원(좌석 수). 좌석 종류는 나누지 않는다.
  final int capacityPerSlot;

  /// 예약 마감 — 방문 시각 기준 N분 전까지만 신청할 수 있다.
  final int leadTimeMinutes;

  /// 오늘부터 며칠 뒤까지 예약할 수 있는지.
  final int maxAdvanceDays;

  /// 업주가 이 시간(시간 단위) 안에 응답하지 않으면 신청이 자동 만료된다.
  /// 승인 후 확정 방식일 때만 뜻이 있다.
  final int autoExpireHours;

  /// 예약 화면에 그대로 보여주는 안내 문구.
  final String notice;

  /// 예약을 받지 않는 날짜('2026-08-20').
  final List<String> blockedDates;

  /// **1인당 예약금**(원). 0이면 지금까지와 같은 무료 예약이라 결제 화면 자체가
  /// 뜨지 않는다. 설정을 만든 적 없는 기존 매장은 전부 0이다.
  final int depositPerPerson;

  /// 예약금을 매기는 방식. 지금은 1인당([depositPerPerson] × 인원)뿐이고,
  /// 나중에 '예약 1건당 고정액'을 더할 수 있게 필드로 남겨 둔다 — 금액 계산은
  /// 반드시 [depositAmountFor]를 거치므로 넓힐 때 한 곳만 고치면 된다.
  final VisitDepositType depositType;

  const PlaceVisitReservationConfig({
    this.enabled = false,
    this.approvalMode = VisitApprovalMode.manual,
    this.slotMinutes = 30,
    this.openFrom,
    this.openTo,
    this.stayMinutes = 120,
    this.minPeople = 1,
    this.maxPeople = 8,
    this.capacityPerSlot = 20,
    this.leadTimeMinutes = 60,
    this.maxAdvanceDays = 30,
    this.autoExpireHours = 12,
    this.notice = '',
    this.blockedDates = const [],
    this.depositPerPerson = 0,
    this.depositType = VisitDepositType.perPerson,
  });

  /// 예약금이 걸린 매장인지 — 0원이면 결제 화면을 건너뛴다.
  bool get hasDeposit => depositPerPerson > 0;

  /// 이 인원으로 예약할 때 받을 금액. 계산은 반드시 여기를 거친다 —
  /// [VisitDepositType]이 늘어나도 화면은 고치지 않아도 되게.
  int depositAmountFor(int peopleCount) {
    if (depositPerPerson <= 0) return 0;
    return switch (depositType) {
      VisitDepositType.perPerson => depositPerPerson * peopleCount,
      // 아직 서버가 만들지 않는 값 — 들어오면 1건당 금액으로 읽는다.
      VisitDepositType.perBooking => depositPerPerson,
    };
  }

  /// 설정이 없는(예전) 플레이스는 "예약 안 받음"으로 읽힌다.
  static const disabled = PlaceVisitReservationConfig();

  factory PlaceVisitReservationConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return disabled;
    int intOf(String key, int fallback) {
      final v = raw[key];
      final n = v is num ? v.toInt() : int.tryParse('$v');
      return n != null && n > 0 ? n : fallback;
    }

    return PlaceVisitReservationConfig(
      enabled: raw['enabled'] == true,
      approvalMode: VisitApprovalMode.fromKey(raw['approvalMode'] as String?),
      slotMinutes: intOf('slotMinutes', 30),
      openFrom: parseHhmm(raw['openFrom'] as String?),
      openTo: parseHhmm(raw['openTo'] as String?),
      stayMinutes: intOf('stayMinutes', 120),
      minPeople: intOf('minPeople', 1),
      maxPeople: intOf('maxPeople', 8),
      capacityPerSlot: intOf('capacityPerSlot', 20),
      // 0(제한 없음)을 쓸 수 있어야 해서 intOf(>0 강제)를 쓰지 않는다.
      leadTimeMinutes: (raw['leadTimeMinutes'] as num?)?.toInt() ?? 60,
      maxAdvanceDays: intOf('maxAdvanceDays', 30),
      autoExpireHours: intOf('autoExpireHours', 12),
      notice: (raw['notice'] as String?)?.trim() ?? '',
      blockedDates:
          (raw['blockedDates'] as List?)?.whereType<String>().toList() ??
          const [],
      // 0(무료)을 쓸 수 있어야 해서 intOf(>0 강제)를 쓰지 않는다.
      depositPerPerson: ((raw['depositPerPerson'] as num?)?.toInt() ?? 0).clamp(
        0,
        1 << 31,
      ),
      depositType: VisitDepositType.fromKey(raw['depositType'] as String?),
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'approvalMode': approvalMode.key,
    'slotMinutes': slotMinutes,
    'openFrom': openFrom == null ? null : formatHhmm(openFrom!),
    'openTo': openTo == null ? null : formatHhmm(openTo!),
    'stayMinutes': stayMinutes,
    'minPeople': minPeople,
    'maxPeople': maxPeople,
    'capacityPerSlot': capacityPerSlot,
    'leadTimeMinutes': leadTimeMinutes,
    'maxAdvanceDays': maxAdvanceDays,
    'autoExpireHours': autoExpireHours,
    'notice': notice,
    'blockedDates': blockedDates,
    'depositPerPerson': depositPerPerson,
    'depositType': depositType.key,
  };

  PlaceVisitReservationConfig copyWith({
    bool? enabled,
    VisitApprovalMode? approvalMode,
    int? slotMinutes,
    TimeOfDay? openFrom,
    TimeOfDay? openTo,
    bool clearOpenFrom = false,
    bool clearOpenTo = false,
    int? stayMinutes,
    int? minPeople,
    int? maxPeople,
    int? capacityPerSlot,
    int? leadTimeMinutes,
    int? maxAdvanceDays,
    int? autoExpireHours,
    String? notice,
    List<String>? blockedDates,
    int? depositPerPerson,
    VisitDepositType? depositType,
  }) => PlaceVisitReservationConfig(
    enabled: enabled ?? this.enabled,
    approvalMode: approvalMode ?? this.approvalMode,
    slotMinutes: slotMinutes ?? this.slotMinutes,
    openFrom: clearOpenFrom ? null : (openFrom ?? this.openFrom),
    openTo: clearOpenTo ? null : (openTo ?? this.openTo),
    stayMinutes: stayMinutes ?? this.stayMinutes,
    minPeople: minPeople ?? this.minPeople,
    maxPeople: maxPeople ?? this.maxPeople,
    capacityPerSlot: capacityPerSlot ?? this.capacityPerSlot,
    leadTimeMinutes: leadTimeMinutes ?? this.leadTimeMinutes,
    maxAdvanceDays: maxAdvanceDays ?? this.maxAdvanceDays,
    autoExpireHours: autoExpireHours ?? this.autoExpireHours,
    notice: notice ?? this.notice,
    blockedDates: blockedDates ?? this.blockedDates,
    depositPerPerson: depositPerPerson ?? this.depositPerPerson,
    depositType: depositType ?? this.depositType,
  );

  /// 예약을 받는 날짜인지 — 임시 휴무일과 예약 가능 기간을 본다.
  bool acceptsDate(DateTime date, {required DateTime now}) {
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day.isBefore(today)) return false;
    if (day.difference(today).inDays > maxAdvanceDays) return false;
    return !blockedDates.contains(dateKeyOf(day));
  }

  /// '2026-08-20' — 슬롯 문서 id와 예약 문서의 날짜 필드에 쓰는 표기.
  static String dateKeyOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// '1830' — 슬롯 문서 id의 시각 부분.
  static String slotKeyOf(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}';

  /// 슬롯 문서 id — 날짜와 시각이 한 문서를 가리키게 한다.
  static String slotDocId(DateTime date, TimeOfDay time) =>
      '${dateKeyOf(date)}_${slotKeyOf(time)}';

  static TimeOfDay? parseHhmm(String? raw) {
    if (raw == null || !raw.contains(':')) return null;
    final parts = raw.split(':');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h % 24, minute: m % 60);
  }

  static String formatHhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  /// '오후 7:00' — 사람이 읽는 표기(플레이스 필터와 같은 형식).
  static String formatTimeLabel(TimeOfDay t) {
    final ampm = t.hour < 12 ? '오전' : '오후';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$ampm $h:${t.minute.toString().padLeft(2, '0')}';
  }

  /// '8월 20일 (수)'.
  static String formatDateLabel(DateTime d) =>
      '${d.month}월 ${d.day}일 (${_weekdayLabels[d.weekday - 1]})';

  static const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];
}

/// 예약 화면에 뿌리는 시간 한 칸.
class VisitSlot {
  final TimeOfDay time;

  /// 이 시각에 이미 잡힌 인원.
  final int reservedPeople;

  /// 이 시각에 받을 수 있는 총 인원.
  final int capacity;

  /// 지금 신청할 수 있는지(마감 시간·정원까지 반영).
  final bool selectable;

  /// 못 고르는 이유 — 칩 아래 회색 문구로 그대로 보여준다.
  final String? blockedReason;

  const VisitSlot({
    required this.time,
    required this.reservedPeople,
    required this.capacity,
    required this.selectable,
    this.blockedReason,
  });

  int get remaining => (capacity - reservedPeople).clamp(0, capacity);

  /// 이 인원이 들어갈 자리가 남았는지.
  bool hasRoomFor(int people) => remaining >= people;

  String get label => PlaceVisitReservationConfig.formatHhmm(time);
}

/// 방문 예약 1건 — `placeVisitReservations/{id}`.
class PlaceVisitReservation {
  final String id;
  final String placeId;
  final String placeName;
  final String hostId;
  final String requesterId;
  final String requesterName;
  final String requesterPhone;
  final int peopleCount;

  /// 방문 일시(시작). 종료는 `visitAt + stayMinutes`.
  final DateTime visitAt;
  final DateTime? endAt;

  final VisitReservationStatus status;

  /// 이용자가 남긴 요청사항.
  final String requestMessage;

  /// 업주가 승인·거절하면서 남긴 한마디(거절 사유 등).
  final String hostMessage;

  final DateTime? createdAt;
  final DateTime? decidedAt;

  /// 승인 대기 응답 기한 — 지나면 서버가 만료 처리한다.
  final DateTime? respondBy;

  /// 서버가 계산한 예약금(원). 0이면 무료 예약이다.
  final int depositAmount;

  /// 결제 정보 — 무료 예약과 예약금이 생기기 전의 예약에는 없다(null).
  /// 예약 진행 상태([status])와 **다른 축**이다: 확정(approved)인데 입금대기일
  /// 수 있고, 그 반대는 없다.
  final PaymentInfo? payment;

  /// 입장 QR에 실리는 토큰 — 예약이 **확정된 뒤에** 서버가 발급한다
  /// (functions/reservationCheckIn.js). 취소·거절·만료되면 서버가 이 필드를
  /// 지우고 토큰도 함께 죽인다.
  ///
  /// 비어 있으면 아직(또는 더 이상) 보여줄 QR이 없다는 뜻이다. 화면은 이
  /// 값의 유무만 보고, 실제로 통과하는지는 판단하지 않는다 — 그 판정은 호스트가
  /// 스캔하는 순간 서버가 원본을 다시 읽어서 한다.
  final String checkInToken;

  /// 현장에서 호스트가 체크인한 시각. 없으면 아직 안 왔다는 뜻이다.
  final DateTime? checkedInAt;

  const PlaceVisitReservation({
    required this.id,
    required this.placeId,
    required this.placeName,
    required this.hostId,
    required this.requesterId,
    required this.requesterName,
    required this.requesterPhone,
    required this.peopleCount,
    required this.visitAt,
    required this.status,
    this.endAt,
    this.requestMessage = '',
    this.hostMessage = '',
    this.createdAt,
    this.decidedAt,
    this.respondBy,
    this.depositAmount = 0,
    this.payment,
    this.checkInToken = '',
    this.checkedInAt,
  });

  factory PlaceVisitReservation.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    DateTime? at(String key) {
      final v = d[key];
      return v is Timestamp ? v.toDate().toLocal() : null;
    }

    return PlaceVisitReservation(
      id: doc.id,
      placeId: d['placeId'] as String? ?? '',
      placeName: d['placeName'] as String? ?? '',
      hostId: d['hostId'] as String? ?? '',
      requesterId: d['requesterId'] as String? ?? '',
      requesterName: d['requesterName'] as String? ?? '',
      requesterPhone: d['requesterPhone'] as String? ?? '',
      peopleCount: (d['peopleCount'] as num?)?.toInt() ?? 1,
      visitAt: at('visitAt') ?? DateTime.now(),
      endAt: at('endAt'),
      status: VisitReservationStatus.fromKey(d['status'] as String?),
      requestMessage: d['requestMessage'] as String? ?? '',
      hostMessage: d['hostMessage'] as String? ?? '',
      createdAt: at('createdAt'),
      decidedAt: at('decidedAt'),
      respondBy: at('respondBy'),
      depositAmount: (d['depositAmount'] as num?)?.toInt() ?? 0,
      payment: PaymentInfo.fromMap(
        (d['payment'] as Map?)?.cast<String, dynamic>(),
      ),
      checkInToken: d['checkInToken'] as String? ?? '',
      checkedInAt: at('checkedInAt'),
    );
  }

  /// '8월 20일 (수) 오후 7:00 · 4명'.
  String get summaryLabel {
    final t = TimeOfDay(hour: visitAt.hour, minute: visitAt.minute);
    return '${PlaceVisitReservationConfig.formatDateLabel(visitAt)} '
        '${PlaceVisitReservationConfig.formatTimeLabel(t)} · $peopleCount명';
  }

  /// 이용자가 아직 취소할 수 있는 예약인지 — 방문 시각이 지나면 못 만진다.
  bool canCancel(DateTime now) => status.isLive && visitAt.isAfter(now);

  /// 게스트에게 보여줄 QR 한 벌 — 파티·이용권과 **같은 카드**가 그린다.
  ///
  /// 토큰이 없으면([checkInToken]이 빈 문자열) 화면이 QR 버튼을 띄우지 않는다.
  CheckInPass get checkInPass => CheckInPass(
    domain: CheckInDomain.reservation,
    token: checkInToken,
    title: placeName.isEmpty ? '방문 예약' : placeName,
    at: visitAt,
    endAt: endAt,
    personName: requesterName,
    itemLabel: '$peopleCount명',
    statusLabel: checkedInAt != null ? '체크인 완료' : status.label,
    state: checkedInAt != null
        ? CheckInPassState.used
        : CheckInPassState.ready,
    notice: _paymentNotice,
  );

  /// 결제가 아직 안 끝난 건에만 붙는 한 줄 — 서버 판정과 같은 뜻을 손님 말로
  /// 옮긴 것이다(판정 자체는 스캔 시점에 서버가 한다).
  String? get _paymentNotice {
    final p = payment;
    if (p == null || p.status == PaymentStatus.paid) return null;
    return p.method == PaymentMethod.onSite
        ? '현장에서 결제한 뒤에 입장할 수 있어요.'
        : '입금이 확인된 뒤에 입장할 수 있어요.';
  }
}

/// 가능한 시간 칸 계산 — **화면과 서버가 같은 규칙을 쓰도록** 여기 하나에만 둔다.
///
/// 규칙: (그날 영업시간 ∩ 예약 접수 시간) 안에서 [PlaceVisitReservationConfig.
/// slotMinutes] 간격으로 칸을 만들고, 마감 시간(leadTime)이 지났거나 정원이 찬
/// 칸은 고를 수 없게 표시한다. 브레이크 타임은 그 시간 자체가 영업 중이 아니므로
/// 제외한다.
///
/// [reservedBySlot]은 `visitSlots` 문서에서 읽은 "슬롯키 → 예약 인원" 맵이다.
class VisitSlotCalculator {
  const VisitSlotCalculator._();

  static List<VisitSlot> slotsFor({
    required PlaceVisitReservationConfig config,
    required PlaceWeeklyHours? weeklyHours,
    required Map<String, dynamic> placeData,
    required DateTime date,
    required DateTime now,
    Map<String, int> reservedBySlot = const {},
    int people = 1,
  }) {
    if (!config.enabled) return const [];
    if (!config.acceptsDate(date, now: now)) return const [];

    final open = _openWindow(weeklyHours, placeData, date);
    if (open == null) return const [];

    // 예약 접수 시간이 따로 있으면 영업시간과 겹치는 부분만 남긴다.
    var start = open.start;
    var end = open.end;
    if (config.openFrom != null) {
      final from = _minutesOf(config.openFrom!);
      if (from > start) start = from;
    }
    if (config.openTo != null) {
      var to = _minutesOf(config.openTo!);
      // 접수 종료가 시작보다 이르면 자정을 넘겨 받는다는 뜻(22:00~02:00).
      if (to <= (config.openFrom == null ? 0 : _minutesOf(config.openFrom!))) {
        to += 1440;
      }
      if (to < end) end = to;
    }
    if (end <= start) return const [];

    final breakWindow = _breakWindow(weeklyHours, date);
    final dayMidnight = DateTime(date.year, date.month, date.day);
    final slots = <VisitSlot>[];

    for (var m = start; m < end; m += config.slotMinutes) {
      // 브레이크 타임에 걸리는 칸은 아예 만들지 않는다(문을 닫는 시간이라
      // "예약 마감"이 아니라 존재하지 않는 시간이다).
      if (breakWindow != null &&
          m >= breakWindow.start &&
          m < breakWindow.end) {
        continue;
      }
      final time = TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60);
      final slotAt = dayMidnight.add(Duration(minutes: m));
      final key = PlaceVisitReservationConfig.slotKeyOf(time);
      final reserved = reservedBySlot[key] ?? 0;
      final remaining = config.capacityPerSlot - reserved;

      String? blocked;
      if (!slotAt.isAfter(now)) {
        blocked = '지난 시간';
      } else if (slotAt.difference(now).inMinutes < config.leadTimeMinutes) {
        blocked = '예약 마감';
      } else if (remaining <= 0) {
        blocked = '예약 마감';
      } else if (remaining < people) {
        blocked = '남은 자리 $remaining명';
      }

      slots.add(
        VisitSlot(
          time: time,
          reservedPeople: reserved,
          capacity: config.capacityPerSlot,
          selectable: blocked == null,
          blockedReason: blocked,
        ),
      );
    }
    return slots;
  }

  /// 그날의 영업 구간(자정 기준 분). 24시간 영업이면 하루 전체.
  static ({int start, int end})? _openWindow(
    PlaceWeeklyHours? weekly,
    Map<String, dynamic> placeData,
    DateTime date,
  ) {
    if (placeData['isOpen24Hours'] == true) return (start: 0, end: 1440);
    final day = weekly?.get(PlaceWeeklyHours.weekdayKeyOf(date));
    if (day == null || day.isClosed) return null;
    if (day.is24Hours) return (start: 0, end: 1440);
    final open = _minutesOf(day.open);
    return (start: open, end: open + day.businessMinutes);
  }

  static ({int start, int end})? _breakWindow(
    PlaceWeeklyHours? weekly,
    DateTime date,
  ) {
    final day = weekly?.get(PlaceWeeklyHours.weekdayKeyOf(date));
    if (day == null || !day.hasEffectiveBreak) return null;
    final midnight = DateTime(date.year, date.month, date.day);
    final w = day.breakWindowOn(date);
    if (w == null) return null;
    return (
      start: w.start.difference(midnight).inMinutes,
      end: w.end.difference(midnight).inMinutes,
    );
  }

  static int _minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;
}
