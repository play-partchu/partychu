import 'package:flutter/material.dart';
import 'package:party_app/models/place_area.dart';
import 'package:party_app/models/listing_inquiry.dart';
import 'package:party_app/widgets/guest_inquiry_button.dart';
import 'package:party_app/models/payment_policy.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:party_app/models/payment_order_summary.dart';
import 'package:party_app/models/payment_status.dart';
import 'package:party_app/models/pet_policy.dart';
import 'package:party_app/models/custom_amenity.dart';
import 'package:party_app/models/place_facility_options.dart';
import 'package:party_app/widgets/custom_amenity_view.dart';
import 'package:party_app/models/place_rental_reservation.dart';
import 'package:party_app/models/reservation_modes.dart';
import 'package:party_app/screens/payment_method_screen.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/models/report_reason.dart';
import 'package:party_app/widgets/user_safety_actions.dart';
import 'package:party_app/utils/place_owner.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/widgets/refund_policy_editor.dart'
    show RefundPolicyView;
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/widgets/favorite_star_button.dart';
import 'package:party_app/widgets/partychu_perk.dart';
import 'package:party_app/widgets/place_address_row.dart';
import 'package:party_app/widgets/linked_party_card.dart';
import 'package:party_app/widgets/media_gallery.dart';
import 'package:party_app/widgets/place_facility_options_view.dart';
import 'package:party_app/services/chat_service.dart';
import 'package:party_app/services/analytics_service.dart';
import 'package:party_app/screens/chat_room_screen.dart';
import 'package:party_app/widgets/place_product/place_product_list_section.dart';
import 'package:party_app/widgets/place_offering_board.dart';
import 'package:party_app/screens/package_booking_screen.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/screens/place_edit_screen.dart';
import 'package:party_app/models/place_weekly_hours.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/place_weekly_hours_view.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 룸 조회의 진행 상태 — 화면이 **어떤 스키마인지 판정되기 전에** 한쪽
/// 스키마의 UI를 먼저 그렸다가 갈아끼우지 않도록, 세 가지를 서로 다른 값으로
/// 구분한다(룸이 있는지 없는지는 [_PlaceDetailScreenState._rooms]가 답한다).
///
/// 특히 **실패는 "룸이 없다"가 아니다** — 둘을 같은 값으로 뭉치면 조회에
/// 실패했을 뿐인 룸 스키마 장소에 구 스키마 기본값(최대 50명 / 0원 / 1시간)이
/// 사실인 것처럼 표시된다.
enum _RoomsLoad { loading, ready, failed }

class PlaceDetailScreen extends StatefulWidget {
  final String placeId;
  final Map<String, dynamic> data;

  const PlaceDetailScreen({
    super.key,
    required this.placeId,
    required this.data,
  });

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  // ── 장소 문서 ─────────────────────────────────────────────────────────────
  /// 화면에 그릴 장소 데이터 — 넘겨받은 스냅샷으로 시작하고, 소유자가 수정
  /// 화면에서 돌아오면 여기만 새로 읽어 교체한다(호출부의 맵은 그대로 둔다).
  late Map<String, dynamic> _data = Map<String, dynamic>.from(widget.data);

  /// 이 장소를 수정할 수 있는 사용자인지 — 첫 프레임 전에 확정해두고 true일
  /// 때만 앱바에 수정 버튼을 그린다(확인 전 노출 방지).
  late bool _canEdit = canEditPlace(_data);

  bool _isRefreshing = false;

  /// 이 공간대여에 연결된 파티 조회 — initState에서 한 번, 새 파티가 붙은
  /// 뒤에 한 번 더 만든다([_reloadLinkedParties]).
  late Future<QuerySnapshot<Map<String, dynamic>>> _linkedPartiesFuture;

  // ── 룸 ───────────────────────────────────────────────────────────────────
  /// 이 장소의 룸 목록. **null은 "아직 못 읽었다"**는 뜻이고, 빈 리스트는
  /// "룸이 없는 구 스키마 장소"라는 뜻이다 — 둘을 같은 값(빈 리스트)으로 두면
  /// 조회가 끝나기 전 첫 프레임에 구 스키마 화면이 **기본값으로** 한 번
  /// 그려졌다가 사라진다(정원 50명·요금 0원·예약 단위 1시간 …). 주소 바로
  /// 아래 지하철 정보 자리에서 정체불명의 문구가 깜빡이던 원인이 이것이다.
  List<Map<String, dynamic>> _rooms = const [];
  Map<String, dynamic>? _selectedRoom;

  /// 룸 조회 상태 — 이 값이 [_RoomsLoad.ready]가 되기 전에는 예약 관련 영역을
  /// **하나도 그리지 않는다**. 판정 전에 그리면 어느 쪽을 그리든 곧바로 반대쪽
  /// 스키마 UI로 갈아끼워져, 상세 진입 직후 제목·가격·룸 선택이 나타났다
  /// 사라지는 깜빡임이 된다.
  _RoomsLoad _roomsLoad = _RoomsLoad.loading;

  // ── 예약 상태 ─────────────────────────────────────────────────────────────
  DateTime? _selectedDate;
  // 선택된 슬롯들의 시작 분(자정 기준, _unitMinutes 단위) — 다중 선택이라
  // 연속이 아니어도(예: 10시대 + 14시대) 자유롭게 담을 수 있게 Set을 쓴다.
  final Set<int> _selectedSlots = {};
  int _peopleCount = 1;

  // ── 예약 방식(숙박/시간제/패키지) ──────────────────────────────────────────
  // 룸이 여러 방식을 함께 받을 때만 의미 있는 사용자의 탭 선택 — 한 가지만
  // 받는 룸이면 _effectiveMode가 그 방식을 그대로 쓴다.
  ReservationMode? _bookingTypeChoice;

  /// 숙박 모드에서 선택한 숙박일 수(박). 체크인 날짜는 _selectedDate.
  int _nights = 1;
  // 시간제 선택 UI 두 가지 — 시작~종료 선택(빠름, 연속 1구간) / 체크박스
  // (세밀함, 비연속 가능). 같은 _selectedSlots를 공유해 전환해도 선택이
  // 사라지지 않는다.
  bool _useRangePicker = true;
  int? _rangeStart;
  int? _rangeEnd;
  Map<String, dynamic>? _selectedPackage;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _requestCtrl = TextEditingController();

  List<({int start, int end})> _bookedRanges = [];
  Set<String> _bookedDays = {};
  bool _isLoadingBookings = false;
  bool _isSubmitting = false;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  // ── 활성 데이터 (룸 선택 시 룸 데이터, 미선택 시 place 데이터 — 구 스키마 호환) ──

  Map<String, dynamic> get _activeData => _selectedRoom ?? _data;

  // ── 게터 ─────────────────────────────────────────────────────────────────

  int get _openMinutes {
    final t = _activeData['openTime'] as String?;
    if (t != null && t.contains(':')) return _parseTimeStr(t);
    return ((_activeData['openHour'] as num?)?.toInt() ?? 9) * 60;
  }

  int get _closeMinutes {
    final t = _activeData['closeTime'] as String?;
    if (t != null && t.contains(':')) return _parseTimeStr(t);
    return ((_activeData['closeHour'] as num?)?.toInt() ?? 23) * 60;
  }

  int get _unitMinutes =>
      (_activeData['bookingUnitMinutes'] as num?)?.toInt() ?? 60;

  int get _minBookingMinutes {
    final v = (_activeData['minBookingMinutes'] as num?)?.toInt();
    if (v != null) return v;
    return ((_activeData['minHours'] as num?)?.toInt() ?? 1) * 60;
  }

  int? get _maxBookingMinutes =>
      (_activeData['maxBookingMinutes'] as num?)?.toInt();

  // 룸 스키마: capacityMax, 구 스키마: capacity / maxCapacity
  int get _capacity =>
      (_activeData['capacityMax'] as num?)?.toInt() ??
      (_activeData['capacity'] as num?)?.toInt() ??
      (_activeData['maxCapacity'] as num?)?.toInt() ??
      50;

  int get _pricePerHour => (_activeData['pricePerHour'] as num?)?.toInt() ?? 0;

  int get _totalMinutes => _selectedSlots.length * _unitMinutes;

  int get _totalPrice => (_pricePerHour * _totalMinutes / 60).round();

  /// 선택된 슬롯들을 시간 순으로 정렬해 연속 구간끼리 묶는다 — 예: 14/15/16시
  /// 슬롯을 고르면 [(14:00,17:00)] 하나로, 10시대+14시대처럼 떨어져 있으면
  /// [(10:00,11:00),(14:00,15:00)] 두 구간으로 묶여 요약 문구·예약 저장에 쓰인다.
  List<({int start, int end})> get _selectedRanges {
    final sorted = _selectedSlots.toList()..sort();
    final ranges = <({int start, int end})>[];
    for (final s in sorted) {
      if (ranges.isNotEmpty && ranges.last.end == s) {
        final last = ranges.removeLast();
        ranges.add((start: last.start, end: s + _unitMinutes));
      } else {
        ranges.add((start: s, end: s + _unitMinutes));
      }
    }
    return ranges;
  }

  // 예약 시 사용할 roomId (구 스키마는 null)
  String? get _selectedRoomId => _selectedRoom?['id'] as String?;

  /// 호스트 결제 방식 — **룸 설정을 먼저 보고 없으면 장소 문서를 본다.**
  /// 서버 `roomAvailability.loadReservationConfig`와 같은 순서다(순서가 갈리면
  /// 화면이 보여준 방식과 서버가 적용한 방식이 달라진다).
  ///
  /// 둘 다 없으면 null이고, 그때는 지금까지처럼 예약자가 결제수단을 자유롭게
  /// 고르고 금액은 전액이다.
  PaymentPolicy? _paymentPolicy() =>
      PaymentPolicy.fromMap(_selectedRoom) ?? PaymentPolicy.fromMap(_data);

  /// 최종 이용요금 기준 금액 분해. **비율 예약금은 숙박일수·패키지가 모두
  /// 반영된 뒤의 금액으로 계산된다** — 호출부가 넘기는 price가 그 값이다.
  PaymentBreakdown _paymentBreakdown(int total) =>
      PaymentBreakdown.of(_paymentPolicy(), total);

  /// **조회에 성공했고** 룸이 있는 신규 스키마 장소인지.
  bool get _hasRooms => _roomsLoad == _RoomsLoad.ready && _rooms.isNotEmpty;

  /// **조회에 성공했고** 룸이 하나도 없는 구 스키마 장소인지.
  ///
  /// 장소 단위 정원·운영시간·요금·예약 카드는 구 스키마에만 있는 값이라
  /// 이것으로만 그린다. `!_hasRooms`로 그리면 아직 조회 중일 때나 조회에
  /// 실패했을 때도 참이라, 값이 없는 자리를 기본값(50명 / 0원 / 09:00~23:00)
  /// 으로 채운 화면이 사실인 것처럼 표시된다.
  bool get _isLegacyPlace => _roomsLoad == _RoomsLoad.ready && _rooms.isEmpty;

  /// 룸을 읽지 못한 상태 — "룸이 없다"와 **다르다**. 이때는 어느 쪽 예약
  /// UI도 그리지 않고 다시 시도만 권한다.
  bool get _roomsFailed => _roomsLoad == _RoomsLoad.failed;

  // ── 예약 방식 (숙박/시간제/패키지 — 복수 지원) ─────────────────────────────

  /// 이 룸(구 스키마면 장소)이 받는 예약 방식 전체.
  Set<ReservationMode> get _modes => roomReservationModes(_activeData);

  /// 지금 실제로 보여줄 예약 방식 — 한 가지만 받으면 그 방식, 여러 가지면
  /// 사용자가 탭으로 고른 방식(아직 안 골랐으면 첫 번째).
  ReservationMode get _effectiveMode {
    final modes = _modes;
    final chosen = _bookingTypeChoice;
    if (chosen != null && modes.contains(chosen)) return chosen;
    return sortedModes(modes).first;
  }

  bool get _isStay => _effectiveMode == ReservationMode.stay;
  bool get _isPackageMode => _effectiveMode == ReservationMode.package;

  StayConfig get _stay => StayConfig.fromMap(_activeData);

  /// 옛 "하루 단위 대여"(bookingUnitMinutes == 1440) 흐름 — 숙박 방식이
  /// 생기기 전 데이터에서만 의미가 있으므로 시간제일 때만 적용한다.
  bool get _isLegacyDaily =>
      _unitMinutes == 1440 && _effectiveMode == ReservationMode.hourly;

  /// 숙박에서 고를 수 있는 숙박일 수 — 이미 잡힌 예약과 겹치면 제외한다.
  List<int> get _availableNightOptions => _stay
      .nightOptions()
      .where((n) => !_hasConflict(_stay.checkInMinutes, _stayMinutes(n)))
      .toList();

  int _stayMinutes(int nights) => _stay.minutesForNights(nights);

  DateTime? get _checkOutDate => _selectedDate?.add(Duration(days: _nights));

  List<Map<String, dynamic>> get _packages {
    final raw = (_activeData['packages'] as List?) ?? [];
    final list = raw
        .map((p) => Map<String, dynamic>.from(p as Map))
        .where((p) => p['isActive'] != false)
        .toList();
    list.sort(
      (a, b) => ((a['sortOrder'] as num?)?.toInt() ?? 0).compareTo(
        (b['sortOrder'] as num?)?.toInt() ?? 0,
      ),
    );
    return list;
  }

  int _packageStartMinute(Map<String, dynamic> pkg) =>
      _parseTimeStr(pkg['startTime'] as String? ?? '0:00');

  /// 종료가 시작보다 이르면(예: 22:00~08:00) 익일까지로 해석해 1440을 더한다.
  int _packageMinutes(Map<String, dynamic> pkg) {
    final s = _packageStartMinute(pkg);
    var e = _parseTimeStr(pkg['endTime'] as String? ?? '0:00');
    if (e <= s) e += 1440;
    return e - s;
  }

  bool _isPackageApplicableToday(Map<String, dynamic> pkg) {
    if (_selectedDate == null) return false;
    final days = (pkg['days'] as List?)?.cast<String>() ?? [];
    if (days.isEmpty) return true; // 비어있으면 매일
    return days.contains(_weekdays[_selectedDate!.weekday - 1]);
  }

  bool _isPackageDisabled(Map<String, dynamic> pkg) =>
      _hasConflict(_packageStartMinute(pkg), _packageMinutes(pkg));

  /// 지금 선택 상태(숙박·시간제 슬롯·패키지)의 총 이용 시간 — 하루 단위
  /// 대여(unitMinutes==1440)는 기존 동작을 그대로 둔다(별도 흐름).
  int get _effectiveTotalMinutes {
    if (_isStay) return _stayMinutes(_nights);
    if (_isLegacyDaily) return _totalMinutes;
    if (_isPackageMode) {
      final p = _selectedPackage;
      return p != null ? _packageMinutes(p) : 0;
    }
    return _totalMinutes;
  }

  int get _effectiveTotalPrice {
    if (_isStay) return _stay.priceForNights(_nights);
    if (_isLegacyDaily) return _totalPrice;
    if (_isPackageMode) {
      return (_selectedPackage?['price'] as num?)?.toInt() ?? 0;
    }
    return _totalPrice;
  }

  // ── 슬롯 목록 ─────────────────────────────────────────────────────────────

  List<int> get _slots {
    final result = <int>[];
    for (int m = _openMinutes; m < _closeMinutes; m += _unitMinutes) {
      result.add(m);
    }
    return result;
  }

  List<int> get _availableStarts =>
      _slots.where((s) => !_isRangeDisabled(s)).toList();

  /// [start]부터 연속으로 예약 가능한(막힘 없는) 슬롯이 끊기는 지점까지의
  /// 종료 시각 후보 목록 — maxBookingMinutes가 있으면 그 안에서만 제안한다.
  List<int> _availableEndsFor(int start) {
    final ends = <int>[];
    var cur = start;
    final max = _maxBookingMinutes;
    while (_slots.contains(cur) && !_isRangeDisabled(cur)) {
      cur += _unitMinutes;
      final duration = cur - start;
      if (max != null && duration > max) break;
      ends.add(cur);
    }
    return ends;
  }

  // ── 초기화 ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (UserSession.name.isNotEmpty) _nameCtrl.text = UserSession.name;
    _loadRooms();
    _linkedPartiesFuture = _queryLinkedParties();
    AnalyticsService.logEvent(
      AnalyticsEventType.placeView,
      placeId: widget.placeId,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _requestCtrl.dispose();
    super.dispose();
  }

  // ── 소유자 전용 수정 ──────────────────────────────────────────────────────

  /// 장소 수정 화면으로 이동한다. 콤보(숙박+파티)로 등록된 장소라도 여기서는
  /// **장소 수정 화면으로만** 보낸다 — 파티 수정 화면으로 보내지 않는다.
  /// `PlaceEditScreen`은 bundleId/linkedPartyId 같은 연결 필드를 건드리지
  /// 않으므로 콤보 연결은 그대로 유지된다.
  ///
  /// `PlaceEditScreen`은 저장 성공 여부를 pop 결과로 돌려주지 않으므로,
  /// 복귀 시 한 번만 재조회한다(수정 없이 뒤로 온 경우엔 같은 값이 다시
  /// 그려질 뿐이라 안전하다). 룸 목록도 함께 다시 읽는다.
  Future<void> _openEdit() async {
    await Navigator.push(
      context,
      webFramedRoute(
        (_) => PlaceEditScreen(docId: widget.placeId, data: _data),
      ),
    );
    if (!mounted) return;
    setState(() => _isRefreshing = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('places')
          .doc(widget.placeId)
          .get();
      final fresh = snap.data();
      if (!mounted) return;
      if (fresh != null) {
        setState(() {
          _data = fresh;
          _canEdit = canEditPlace(fresh);
          // 수정으로 룸이 바뀌었을 수 있어 선택 상태를 비운다.
          _selectedRoom = null;
        });
        await _loadRooms();
      }
    } catch (e) {
      debugPrint('[PlaceDetail] 수정 후 재조회 실패: $e');
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  // ── 룸 로드 ───────────────────────────────────────────────────────────────

  Future<void> _loadRooms() async {
    // 한 번 확정된 뒤의 재조회(수정 후 복귀 등)에서는 로딩으로 되돌리지 않는다 —
    // 되돌리면 잘 그려져 있던 예약 영역이 통째로 사라졌다 다시 나타난다.
    // 아직 판정 전이거나 실패해서 다시 시도하는 경우에만 로딩으로 둔다.
    if (_roomsLoad != _RoomsLoad.ready) {
      setState(() => _roomsLoad = _RoomsLoad.loading);
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('placeRooms')
          .where('placeId', isEqualTo: widget.placeId)
          .where('isActive', isEqualTo: true)
          .get();
      if (!mounted) return;
      final rooms = snap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();
      setState(() {
        _rooms = rooms;
        _roomsLoad = _RoomsLoad.ready;
      });
    } catch (_) {
      if (!mounted) return;
      // **실패는 "룸이 없다"가 아니다.** 구 스키마로 넘겨 버리면 이 장소에
      // 없는 값(정원·요금·운영시간)이 기본값으로 채워져 사실처럼 보인다.
      // 이미 읽어 둔 목록이 있으면 그것을 그대로 두고(재조회 실패), 처음부터
      // 못 읽었으면 실패 상태로 남겨 다시 시도만 권한다.
      setState(() {
        if (_roomsLoad != _RoomsLoad.ready) _roomsLoad = _RoomsLoad.failed;
      });
    }
  }

  void _selectRoom(Map<String, dynamic> room) {
    setState(() {
      _selectedRoom = room;
      _selectedDate = null;
      _selectedSlots.clear();
      _rangeStart = null;
      _rangeEnd = null;
      _selectedPackage = null;
      _bookedRanges = [];
      _bookedDays = {};
      _peopleCount = 1;
      // 룸마다 받는 예약 방식이 다르므로 방식 선택과 숙박일 수도 초기화한다.
      _bookingTypeChoice = null;
      _nights = _stay.minNights;
    });
  }

  // ── 헬퍼 ─────────────────────────────────────────────────────────────────

  int _parseTimeStr(String t) {
    final parts = t.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── 예약 현황 로드 ─────────────────────────────────────────────────────────

  /// 겹침 판정에 필요한 조회 폭(일). 숙박은 예약 하나가 여러 날에 걸쳐 있어서
  /// 선택한 날짜를 관통하는 장기 숙박까지 보려면 앞뒤로 더 넓게 읽어야 한다.
  bool get _supportsStay => _modes.contains(ReservationMode.stay);

  int get _bookedLookbackDays => _supportsStay ? 31 : 1;

  int get _bookedHorizonDays => _supportsStay ? (_stay.maxNights ?? 14) + 1 : 1;

  Future<void> _loadBooked(DateTime date) async {
    setState(() => _isLoadingBookings = true);
    try {
      // reservationSlots: 시간대·상태만 담은 공개 컬렉션(개인정보 없음) —
      // 다른 이용자의 예약자 이름/연락처가 담긴 placeReservationGroups와는
      // 분리돼 있다(자세한 설계는 functions/placeReservations.js 상단 주석).
      final slotsRef = FirebaseFirestore.instance
          .collection('places')
          .doc(widget.placeId)
          .collection('reservationSlots');
      final now = DateTime.now();

      if (_isLegacyDaily) {
        final snap = await slotsRef.get();
        final days = <String>{};
        for (final doc in snap.docs) {
          final d = doc.data();
          final status = d['status'] as String? ?? 'pending';
          if (status == 'cancelled' || status == 'expired') continue;
          if (status == 'pending') {
            final exp = (d['expiresAt'] as Timestamp?)?.toDate();
            if (exp != null && exp.isBefore(now)) continue;
          }
          if (_selectedRoomId != null && d['roomId'] != _selectedRoomId) {
            continue;
          }
          final startAt = (d['startAt'] as Timestamp?)?.toDate();
          if (startAt == null) continue;
          days.add(_dateStr(startAt));
        }
        if (!mounted) return;
        setState(() {
          _bookedDays = days;
          _isLoadingBookings = false;
        });
      } else {
        final selectedMidnight = DateTime(date.year, date.month, date.day);
        // 전날 밤부터 시작해 다음날로 넘어가는 예약(올나잇 패키지 등)도
        // 겹침 판정에 포함하기 위해 하루 앞선 시점부터 다음날 자정 전까지
        // 넉넉히 조회한다. 숙박을 받는 룸은 예약 하나가 여러 날을 덮으므로
        // 그만큼 앞뒤를 더 넓게 본다(_bookedLookbackDays/_bookedHorizonDays).
        final horizonDays = _bookedHorizonDays;
        final queryStart = Timestamp.fromDate(
          selectedMidnight.subtract(Duration(days: _bookedLookbackDays)),
        );
        final queryEnd = Timestamp.fromDate(
          selectedMidnight.add(Duration(days: horizonDays)),
        );
        final snap = await slotsRef
            .where('startAt', isGreaterThanOrEqualTo: queryStart)
            .where('startAt', isLessThan: queryEnd)
            .get();

        final ranges = <({int start, int end})>[];
        for (final doc in snap.docs) {
          final d = doc.data();
          final status = d['status'] as String? ?? 'pending';
          if (status == 'cancelled' || status == 'expired') continue;
          if (status == 'pending') {
            final exp = (d['expiresAt'] as Timestamp?)?.toDate();
            if (exp != null && exp.isBefore(now)) continue;
          }
          if (_selectedRoomId != null && d['roomId'] != _selectedRoomId) {
            continue;
          }
          final startAt = (d['startAt'] as Timestamp?)?.toDate();
          final endAt = (d['endAt'] as Timestamp?)?.toDate();
          if (startAt == null || endAt == null) continue;
          // 선택한 날짜 자정 기준 "분" 좌표로 통일 — 전날 시작/다음날로
          // 넘어가는 예약(시간제·패키지 구분 없이)도 음수 또는 1440 초과
          // 값으로 표현해 자정을 걸치는 구간까지 정확히 겹침 판정한다.
          final startMin = startAt.difference(selectedMidnight).inMinutes;
          final endMin = endAt.difference(selectedMidnight).inMinutes;
          if (endMin <= 0 ||
              startMin >= horizonDays * 1440 ||
              startMin >= endMin) {
            continue;
          }
          ranges.add((start: startMin, end: endMin));
        }
        if (!mounted) return;
        setState(() {
          _bookedRanges = ranges;
          _isLoadingBookings = false;
          // 새로고침한 예약 현황 기준으로 지금은 막힌 선택이 있으면(다른
          // 사용자가 그 사이 먼저 예약한 경우 등) 조용히 해제한다.
          _selectedSlots.removeWhere(_isRangeDisabled);
          if (_rangeStart != null &&
              _rangeEnd != null &&
              _hasConflict(_rangeStart!, _rangeEnd! - _rangeStart!)) {
            _rangeStart = null;
            _rangeEnd = null;
          }
          final pkg = _selectedPackage;
          if (pkg != null && _isPackageDisabled(pkg)) {
            _selectedPackage = null;
          }
          // 고른 숙박일 수가 막혔으면 예약 가능한 가장 짧은 일수로 되돌린다.
          if (_isStay &&
              _hasConflict(_stay.checkInMinutes, _stayMinutes(_nights))) {
            final options = _availableNightOptions;
            _nights = options.isNotEmpty ? options.first : _stay.minNights;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingBookings = false);
    }
  }

  bool _hasConflict(int startMinute, int durationMinutes) {
    final end = startMinute + durationMinutes;
    for (final r in _bookedRanges) {
      if (startMinute < r.end && end > r.start) return true;
    }
    return false;
  }

  bool _isRangeDisabled(int startMin) {
    final endMin = startMin + _unitMinutes;
    for (final r in _bookedRanges) {
      if (startMin < r.end && endMin > r.start) return true;
    }
    return false;
  }

  bool _isDayRangeBooked(DateTime startDate, int durationDays) {
    for (int i = 0; i < durationDays; i++) {
      if (_bookedDays.contains(_dateStr(startDate.add(Duration(days: i))))) {
        return true;
      }
    }
    return false;
  }

  // ── 날짜 선택 ─────────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFFFF6FA0)),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = picked;
      _selectedSlots.clear();
      _rangeStart = null;
      _rangeEnd = null;
      _selectedPackage = null;
      _bookedRanges = [];
      _bookedDays = {};
      _nights = _stay.minNights;
    });
    await _loadBooked(picked);
  }

  // ── 시간 범위 선택(시작~종료) ──────────────────────────────────────────────

  void _syncSlotsFromRange() {
    _selectedSlots.clear();
    if (_rangeStart == null || _rangeEnd == null) return;
    for (int m = _rangeStart!; m < _rangeEnd!; m += _unitMinutes) {
      _selectedSlots.add(m);
    }
  }

  Future<void> _pickRangeStart() async {
    final options = _availableStarts;
    if (options.isEmpty) {
      _msg('예약 가능한 시간이 없어요.');
      return;
    }
    final picked = await _showTimeSheet('시작 시간 선택', options);
    if (picked == null) return;
    setState(() {
      _rangeStart = picked;
      final ends = _availableEndsFor(picked);
      _rangeEnd = ends.isNotEmpty ? ends.first : null;
      _syncSlotsFromRange();
    });
  }

  Future<void> _pickRangeEnd() async {
    if (_rangeStart == null) {
      _msg('시작 시간을 먼저 선택해주세요.');
      return;
    }
    final options = _availableEndsFor(_rangeStart!);
    if (options.isEmpty) {
      _msg('선택 가능한 종료 시간이 없어요.');
      return;
    }
    final picked = await _showTimeSheet('종료 시간 선택', options);
    if (picked == null) return;
    setState(() {
      _rangeEnd = picked;
      _syncSlotsFromRange();
    });
  }

  Future<int?> _showTimeSheet(String title, List<int> options) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(_fmtSlotInline(options[i])),
                  onTap: () => Navigator.pop(ctx, options[i]),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── 예약 제출 ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_hasRooms && _selectedRoom == null) {
      _msg('먼저 룸을 선택해주세요.');
      return;
    }
    if (_selectedDate == null) {
      _msg('이용 날짜를 선택해주세요.');
      return;
    }

    final isDaily = _isLegacyDaily;
    final bookingType = isDaily ? 'daily' : _effectiveMode.key;

    if (bookingType == 'stay') {
      if (_hasConflict(_stay.checkInMinutes, _stayMinutes(_nights))) {
        _msg('선택한 기간에 이미 예약이 있어요. 다른 날짜를 선택해주세요.');
        return;
      }
    }
    if (!isDaily && bookingType == 'package' && _selectedPackage == null) {
      _msg('예약할 패키지를 선택해주세요.');
      return;
    }
    if (!isDaily && bookingType == 'hourly') {
      if (_selectedSlots.isEmpty) {
        _msg('예약 시간을 선택해주세요.');
        return;
      }
      if (_totalMinutes < _minBookingMinutes) {
        _msg('최소 ${_fmtMinutes(_minBookingMinutes)} 이상 선택해주세요.');
        return;
      }
      final max = _maxBookingMinutes;
      if (max != null && _totalMinutes > max) {
        _msg('최대 ${_fmtMinutes(max)}까지 예약할 수 있어요.');
        return;
      }
    }
    if (_nameCtrl.text.trim().isEmpty) {
      _msg('예약자 이름을 입력해주세요.');
      return;
    }
    if (_phoneCtrl.text.trim().isEmpty) {
      _msg('연락처를 입력해주세요.');
      return;
    }
    if (UserSession.userId.isEmpty) {
      _msg('로그인이 필요합니다.');
      return;
    }

    // ── 결제수단 ──────────────────────────────────────────────────────────
    // PG 계약 전이라 실제로 받을 수 있는 수단은 무통장입금·현장결제뿐이고,
    // 그 흐름은 파티 신청·방문예약과 같은 화면([PaymentMethodScreen])을 쓴다.
    // 여기서 고르는 건 **수단뿐**이고 금액과 결제 상태는 서버가 다시 정한다.
    // 무료 예약(0원)은 예전과 똑같이 결제 화면 없이 바로 잡힌다.
    PaymentInfo? payment;
    final price = _effectiveTotalPrice;
    if (price > 0) {
      payment = await Navigator.push<PaymentInfo>(
        context,
        webFramedRoute(
          (_) => PaymentMethodScreen(
            summary: PaymentOrderSummary.placeRental(
              placeName: _data['name'] as String? ?? '장소',
              useText: '${_dateStr(_selectedDate!)} · ${_bookingLabel()}',
              roomText: _selectedRoom?['roomName'] as String? ?? '전체 공간',
              amount: price,
            ),
            defaultDepositorName: _nameCtrl.text.trim(),
            // 호스트가 결제 방식을 정한 장소만 "지금 얼마 / 현장에서 얼마"를
            // 보여주고 수단을 좁힌다. 설정이 없으면 지금까지의 화면 그대로다.
            breakdown: _paymentPolicy() == null
                ? null
                : _paymentBreakdown(price),
            allowedMethods: _paymentPolicy()?.allowedMethods,
            // 돈을 받는 사람 = 이 장소의 호스트.
            hostId: _data['hostId'] as String? ?? '',
          ),
        ),
      );
      if (payment == null || !mounted) return;
    }

    setState(() => _isSubmitting = true);
    try {
      // 최종 겹침 재확인(클라이언트 프리체크) — 진짜 확정 판정은 서버
      // 트랜잭션(createPendingReservation)에서 한 번 더 한다.
      await _loadBooked(_selectedDate!);
      if (!mounted) return;

      final payload = <String, dynamic>{
        if (payment != null) 'payment': payment.toMap(),
        // 화면에 띄운 금액 — 서버가 자기 계산과 대조해 다르면 예약을 막는다.
        if (_paymentPolicy() != null)
          'amounts': _paymentBreakdown(price).toClaim(),
        'placeId': widget.placeId,
        if (_selectedRoomId != null) 'roomId': _selectedRoomId,
        'date': _dateStr(_selectedDate!),
        'bookingType': bookingType,
        'peopleCount': _peopleCount,
        'requesterName': _nameCtrl.text.trim(),
        'requesterPhone': _phoneCtrl.text.trim(),
        'requestMessage': _requestCtrl.text.trim(),
        if (bookingType == 'stay') 'nights': _nights,
        if (bookingType == 'package') 'packageId': _selectedPackage!['id'],
        if (bookingType == 'hourly')
          'ranges': [
            for (final r in _selectedRanges) {'start': r.start, 'end': r.end},
          ],
      };

      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('createPendingReservation');
      final result = await callable.call<Map<Object?, Object?>>(payload);
      final data = result.data;
      final groupId = data['groupId'] as String;
      final totalPrice = (data['totalPrice'] as num).toInt();

      if (!mounted) return;

      // 결제창(PG)이 없다 — 서버가 이미 시간 슬롯을 잡고 승인 여부·결제 상태까지
      // 정해 돌려줬으므로, 그 결과를 그대로 안내하면 끝이다. 무료 예약도 같은
      // 경로를 탄다(결제 정보가 없을 뿐 확정 절차는 같다).
      await _showReservationResultDialog(
        groupId: groupId,
        status: PlaceRentalStatus.fromKey(data['status'] as String?),
        paymentStatus: PaymentStatus.fromKey(data['paymentStatus'] as String?),
        totalPrice: totalPrice,
      );
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        _msg(e.message ?? '선택한 시간에 이미 예약이 있어요. 다른 시간을 선택해주세요.');
      }
    } catch (_) {
      if (mounted) _msg('예약 중 오류가 발생했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );

  /// '숙박 2박' / '시간제 예약' / 패키지명 — 결제 화면 요약에 쓰는 한 줄.
  /// 예약 목록의 [PlaceRentalReservation.bookingLabel]과 같은 문구를 쓴다.
  String _bookingLabel() {
    if (_isLegacyDaily) return '하루 단위 대여';
    if (_isStay) return '숙박 $_nights박';
    if (_isPackageMode) {
      return _selectedPackage?['name'] as String? ?? '패키지';
    }
    return '시간제 예약';
  }

  /// 무통장입금·현장결제 예약의 결과 안내.
  ///
  /// 예약 진행 상태(승인대기 ↔ 확정)와 결제 상태(입금대기 ↔ 현장결제 예정)가
  /// **다른 축**이라 문구를 둘 다 반영한다 — "확정됐어요"만 띄우면 아직 돈이
  /// 안 들어왔다는 사실이 가려진다.
  Future<void> _showReservationResultDialog({
    required String groupId,
    required PlaceRentalStatus status,
    required PaymentStatus? paymentStatus,
    required int totalPrice,
  }) async {
    final awaitingApproval = status == PlaceRentalStatus.requested;
    final body = awaitingApproval
        ? '업주가 승인하면 알림으로 알려드려요. 승인된 뒤에 입금 안내가 나가요.\n'
              '진행 상황은 마이페이지 > 내 장소대여 예약에서 볼 수 있어요.'
        : totalPrice <= 0
        ? '무료 예약이라 결제 없이 확정됐어요.'
        : paymentStatus == PaymentStatus.awaitingDeposit
        ? '기한 안에 입금하시면 예약이 유지돼요.\n'
              '계좌와 입금기한은 마이페이지 > 내 장소대여 예약에서 확인할 수 있어요.'
        : '이용 당일 현장에서 결제하시면 돼요.';
    await _showSuccessDialog(
      groupId,
      title: awaitingApproval ? '예약을 신청했어요' : '예약이 확정됐어요',
      body: body,
    );
  }

  Future<void> _showSuccessDialog(
    String bookingId, {
    String title = '예약 완료',
    String body = '결제가 완료되어 예약이 확정됐어요.',
  }) async {
    final hostId = _data['hostId'] as String? ?? '';
    final hostName = _data['hostName'] as String? ?? '호스트';
    final placeName = _data['name'] as String? ?? '파티 장소';

    // 채팅방 생성 (예약 시각 기준 자동발송 등록 포함)
    String? roomId;
    try {
      roomId = await ChatService.getOrCreateRoom(
        hostId: hostId,
        hostName: hostName,
        guestId: UserSession.userId,
        guestName: UserSession.displayName,
        relatedType: 'place',
        relatedId: widget.placeId,
        relatedTitle: placeName,
        appointmentAt: _selectedDate,
      );

      // 자동발송 등록 — 장소에 autoMessage가 설정돼 있으면 이용일 아침에 나간다.
      // 문구와 발송 시각 판단은 서버 몫이고, 앱은 이용일만 알려준다.
      await ChatService.scheduleAutoMessage(
        roomId: roomId,
        appointmentAt: _selectedDate,
      );
    } catch (_) {
      // 채팅방 생성 실패해도 예약 완료는 유지
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFFFF6FA0), size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'SeoulHangang',
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                    Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                    Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                    Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                  ],
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body, style: const TextStyle(fontSize: 13.5, height: 1.5)),
            const SizedBox(height: 10),
            Text(
              '예약번호: ${bookingId.substring(0, 8).toUpperCase()}',
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('확인', style: TextStyle(color: Colors.black45)),
          ),
          if (roomId != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
                Navigator.push(
                  context,
                  webFramedRoute(
                    (_) => ChatRoomScreen(
                      roomId: roomId!,
                      otherName: hostName,
                      relatedTitle: placeName,
                    ),
                  ),
                );
              },
              child: const Text(
                '채팅하기',
                style: TextStyle(
                  color: Color(0xFFFF6FA0),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── 포맷 헬퍼 ─────────────────────────────────────────────────────────────

  // "HH:MM" 또는 "24:00" 문자열 → "오전/오후 H:MM" 표시용
  String _fmtTimeStr(String t) {
    if (t == '24:00') return '자정 (24:00)';
    final parts = t.split(':');
    if (parts.length != 2) return t;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1];
    if (h == 0) return '오전 12:$m';
    if (h < 12) return '오전 $h:$m';
    if (h == 12) return '오후 12:$m';
    return '오후 ${h - 12}:$m';
  }

  String _fmtSlotInline(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final period = h < 12 ? '오전' : '오후';
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '$period $hh:${m.toString().padLeft(2, '0')}';
  }

  String _fmtSlotRange(int startMin) =>
      '${_fmtSlotInline(startMin)} ~ ${_fmtSlotInline(startMin + _unitMinutes)}';

  String _fmtPrice(int price) => formatPrice(price);

  String _fmtMinutes(int min) {
    if (min >= 1440 && min % 1440 == 0) return '${min ~/ 1440}일';
    if (min < 60) return '$min분';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '$h시간' : '$h시간 $m분';
  }

  // ── 빌드 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final name = _data['name'] as String? ?? '장소';
    final imageUrls = ((_data['imageUrls'] as List?)?.cast<String>() ?? [])
        .toList();
    final videoUrl = _data['videoUrl'] as String?;
    final videoThumbnailUrl = _data['videoThumbnailUrl'] as String?;
    final hasVideo = videoUrl != null && videoUrl.isNotEmpty;

    // 대표 미디어 — 등록/수정 시 이미 imageUrls 맨 앞(index 0)으로 재정렬해
    // 저장하므로 갤러리는 항상 index 0부터 연다(파티 상세페이지와 동일한
    // 규칙). 재정렬 전에 저장된 과거 장소 데이터도 방어적으로 여기서 한 번
    // 더 맞춰준다(대표 사진이 index 0이 아니면 이 화면에서만 맨 앞으로
    // 옮기고, Firestore에 다시 쓰지는 않는다).
    final cover = getPartyCoverMedia(_data, tag: 'PlaceDetailHero');
    final videoIsCover = cover?.isVideo ?? false;
    if (!videoIsCover && cover?.imageUrl != null) {
      final idx = imageUrls.indexOf(cover!.imageUrl!);
      if (idx > 0) {
        imageUrls
          ..removeAt(idx)
          ..insert(0, cover.imageUrl!);
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 0,
            title: Text(
              name,
              style: const TextStyle(
                fontFamily: 'SeoulHangang',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                shadows: [
                  Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                  Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                  Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                  Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                ],
              ),
            ),
            actions: [
              SafetyMenuButton(
                targetType: ReportTargetType.place,
                targetId: widget.placeId,
                targetUserId: _data['hostId'] as String? ?? '',
                targetUserName: _data['hostName'] as String? ?? '',
                targetTitle: _data['name'] as String? ?? '',
              ),
              // 소유자(또는 관리자)에게만 보이는 수정 진입점. 소유권을 확인한
              // 뒤에만 그려지므로 로딩 중 잠깐 노출되는 일이 없다.
              if (_canEdit)
                IconButton(
                  tooltip: '플레이스 수정',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _isRefreshing ? null : _openEdit,
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FavoriteStarButton(
                  itemType: FavoriteType.place,
                  itemId: widget.placeId,
                  glow: false,
                ),
              ),
            ],
          ),
          // ── 미디어 갤러리 (사진 + 동영상 통합, 파티 상세페이지와 동일한
          // MediaGallery 재사용) — 원본 비율로 표시되고, 동영상이면 여백 없이
          // 미디어 영역을 꽉 채운다. 사진/동영상 모두 좌우로 넘겨볼 수 있다.
          SliverToBoxAdapter(
            child: imageUrls.isNotEmpty || hasVideo
                ? MediaGallery(
                    images: imageUrls,
                    videoUrl: videoUrl,
                    videoThumbnailUrl: videoThumbnailUrl,
                    videoFirst: videoIsCover,
                  )
                : Container(
                    width: double.infinity,
                    height: 220,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF6FA0), Color(0xFFFFB3CC)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.home_outlined,
                        size: 56,
                        color: Colors.white,
                      ),
                    ),
                  ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoCard(),
                  const SizedBox(height: 12),
                  // 요일별 운영시간 — 휴무·브레이크 타임까지 등록 화면에 넣은
                  // 그대로 보여준다. 요일별 시간표가 없는 문서면 빈 위젯.
                  ..._weeklyHoursSection(),
                  // 문의하기는 본문이 아니라 **하단 고정 CTA**에 있다
                  // (_bottomBar) — 예약 버튼과 나란히 두어야 "물어보고
                  // 예약한다"는 흐름이 한자리에서 보인다.
                  // 파티츄 전용 혜택 — 있을 때만 그려진다(없으면 빈 위젯).
                  PartychuPerkCard.fromData(
                    _data,
                    margin: const EdgeInsets.only(bottom: 12),
                  ),
                  // 🎉 파티 | ✨ 이벤트 — 이 장소에서 열리는 것을 좌우 2열로
                  // **함께** 보여준다. 플레이스 상세와 **같은 위젯**
                  // ([PlaceOfferingBoard])이다 — 예전에는 여기만 이벤트가
                  // 가로 스크롤 단독 섹션, 파티는 상세 아래쪽 별도 목록으로
                  // 갈라져 있어 같은 질문("여기서 뭐 하지?")의 답이 두 군데
                  // 있었고, 가로 카드가 고정 높이를 넘겨 아래가 잘렸다.
                  //
                  // 데이터는 그대로다 — 파티는 `parties.linkedPlaceId`
                  // ([_queryLinkedParties]), 이벤트는 `placePromotions`.
                  PlaceOfferingBoard(
                    placeId: widget.placeId,
                    linkedPartiesFuture: _linkedPartiesFuture,
                    accent: const Color(0xFF7C5CBF),
                    // 호스트 본인일 때만 '🎉 파티 추가 / ✨ 매장 이벤트 추가'
                    // 진입점이 붙는다.
                    placeCollection: 'places',
                    hostId: _data['hostId'] as String?,
                    placeName: _data['name'] as String?,
                    // 파티 추가 시 이 공간대여가 연결 대상이 된다.
                    placeData: _data,
                    onPartyLinked: _reloadLinkedParties,
                    // 콤보 대표 파티는 아래 '파티 정보 함께보기' 카드가 이미
                    // 크게 보여준다(패키지 예약 버튼이 거기 붙어 있다).
                    excludedPartyIds: {
                      if (_data['linkedPartyId'] case final String id)
                        if (id.isNotEmpty) id,
                    },
                  ),
                  const SizedBox(height: 16),
                  PlaceProductListSection(
                    placeId: widget.placeId,
                    accent: const Color(0xFF7C5CBF),
                    fallbackImageUrl: _data['mainImageUrl'] as String?,
                  ),
                  const SizedBox(height: 12),
                  if ((_data['description'] as String?)?.isNotEmpty ==
                      true) ...[
                    _descCard(),
                    const SizedBox(height: 12),
                  ],
                  if (_data['linkedPartyId'] != null) _linkedPartyCard(),
                  // ── 예약 관련 영역 ────────────────────────────────────
                  // 룸 조회가 끝나기 전에는 **아무것도 그리지 않는다**. 예전에는
                  // 여기서 '룸 선택' 제목과 스피너를 먼저 띄웠는데, 구 스키마
                  // 장소에서는 그 섹션이 통째로 사라지고 대신 예약 카드가
                  // 나타나 UI가 갈아끼워지는 것처럼 보였다. 스키마가 정해진
                  // 뒤에 최종 모습을 한 번만 그린다(하단 버튼만 '불러오는 중…'
                  // 으로 진행 중임을 알린다).
                  if (_hasRooms) ...[
                    _roomsSection(),
                    const SizedBox(height: 12),
                  ],
                  // 룸을 읽지 못한 경우 — 구 스키마로 넘어가 기본값을 보여주는
                  // 대신, 못 읽었다는 사실과 다시 시도만 내놓는다.
                  if (_roomsFailed) ...[
                    _roomsErrorCard(),
                    const SizedBox(height: 12),
                  ],
                  // 환불 정책 (구 스키마 호환)
                  if (_isLegacyPlace &&
                      (_data['cancelPolicy'] as String?)?.isNotEmpty ==
                          true) ...[
                    _policyCard(_data['cancelPolicy'] as String),
                    const SizedBox(height: 12),
                  ],
                  // 예약 섹션 (신규: 룸 선택 후 표시 / 구: 항상 표시).
                  // 룸 조회 전에는 어느 쪽인지 모르므로 아무것도 그리지 않는다 —
                  // 예전에는 여기서 구 스키마 예약 카드가 기본 운영시간·요금으로
                  // 한 번 그려졌다가 사라졌다.
                  if (_isLegacyPlace || _selectedRoom != null)
                    _reservationCard(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  // ── 요일별 운영시간 ───────────────────────────────────────────────────────

  /// 요일별 운영시간 카드 — 저장된 시간표가 있을 때만 그린다.
  ///
  /// 등록 화면이 `placeWeeklyHours`와 `weeklyOperatingHours` 두 이름으로 같은
  /// 값을 저장해 왔으므로 둘 다 읽는다.
  List<Widget> _weeklyHoursSection() {
    final raw =
        (_data['placeWeeklyHours'] as Map?) ??
        (_data['weeklyOperatingHours'] as Map?);
    if (raw == null || raw.isEmpty) return const [];
    return [
      PlaceWeeklyHoursView(
        hours: PlaceWeeklyHours.fromMap(Map<String, dynamic>.from(raw)),
        isOpen24Hours: _data['isOpen24Hours'] as bool? ?? false,
      ),
      const SizedBox(height: 12),
    ];
  }

  // ── 장소 정보 카드 ────────────────────────────────────────────────────────

  Widget _infoCard() {
    final d = _data;
    final petPolicy = d['petPolicy'] is Map
        ? PetPolicy.fromMap(Map<String, dynamic>.from(d['petPolicy'] as Map))
        : PetPolicy.empty();
    final petConditionLines = <String>[];
    if (petPolicy.status == PetPolicyStatus.possible) {
      petConditionLines.add('🐶 애견동반 가능');
    } else if (petPolicy.status == PetPolicyStatus.conditional) {
      petConditionLines.add('🐶 애견동반 조건부 가능');
    }
    if (petPolicy.allowedAnimals.isNotEmpty) {
      petConditionLines.add(
        '동반 가능: ${petPolicy.allowedAnimals.toList().join(', ')}',
      );
    }
    if (petPolicy.sizeLimit != null && petPolicy.sizeLimit!.trim().isNotEmpty) {
      petConditionLines.add('크기 제한: ${petPolicy.sizeLimit!}');
    }
    if (petPolicy.maxCount != null) {
      petConditionLines.add('최대 동반 수: ${petPolicy.maxCount}마리');
    }
    if (petPolicy.requiredConditions.isNotEmpty) {
      petConditionLines.add(
        '필수 조건: ${petPolicy.requiredConditions.toList().join(', ')}',
      );
    }
    if (petPolicy.notes != null && petPolicy.notes!.trim().isNotEmpty) {
      petConditionLines.add('추가 안내: ${petPolicy.notes!}');
    }
    if (petPolicy.extraFeeEnabled && petPolicy.extraFeeAmount != null) {
      petConditionLines.add('추가비용: ${_fmtPrice(petPolicy.extraFeeAmount!)}');
    }
    // 공간 평수 — 필드가 없던 옛 문서는 null이라 줄이 통째로 빠진다.
    final areaLabel = PlaceArea.labelOf(d);
    // 공용 편의시설 (신규 스키마)
    final commonFacilities =
        (d['commonFacilities'] as List?)?.cast<String>() ?? [];
    final facilityOptions = d['facilityOptions'] is Map
        ? PlaceFacilityOptions.fromMap(
            Map<String, dynamic>.from(d['facilityOptions'] as Map),
          )
        : PlaceFacilityOptions.empty();
    // 구 스키마 필드 (rooms 없을 때)
    final availableDays = (d['availableDays'] as List?)?.cast<String>() ?? [];
    final openRaw =
        d['openTime'] as String? ??
        (d['openHour'] != null ? '${d['openHour']}:00' : '');
    final closeRaw =
        d['closeTime'] as String? ??
        (d['closeHour'] != null ? '${d['closeHour']}:00' : '');
    final isOpen24 = d['isOpen24Hours'] as bool? ?? false;
    final openLabel = openRaw.isNotEmpty ? _fmtTimeStr(openRaw) : '';
    final closeLabel = closeRaw.isNotEmpty ? _fmtTimeStr(closeRaw) : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d['name'] as String? ?? '',
            style: const TextStyle(
              fontFamily: 'SeoulHangang',
              fontSize: 18,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 주소 + 복사/길찾기 — events 상세와 같은 공용 위젯. 복사·검색에는
          // 도로명 주소와 상세주소를 합친 전체 주소를 쓴다.
          if (_fullAddress.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: PlaceAddressRow(
                address: _fullAddress,
                placeName: d['name'] as String?,
                latitude: (d['lat'] as num?)?.toDouble(),
                longitude: (d['lng'] as num?)?.toDouble(),
                leadingIconSize: 15,
                leadingIconColor: const Color(0xFFFF6FA0),
                gap: 8,
                textStyle: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ),
          // 공간 평수 — 이 필드가 없던 옛 문서에서는 줄 자체가 빠지므로
          // 예전과 똑같이 보인다([PlaceArea]). 호스트가 수정 화면에 한 번
          // 들어와 저장하면 그때부터 이 줄이 생긴다.
          if (areaLabel != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const Text(PlaceArea.emoji, style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 7),
                  Text(
                    areaLabel,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ],
              ),
            ),
          // 구 스키마에만 있는 장소 단위 정보 — **룸 조회가 끝난 뒤에만** 그린다.
          // 조회 중에 그리면 이 값들이 전부 게터 기본값(50명 / 0원 / 1시간)이라,
          // 바로 위 주소·지하철 줄 아래에 정체불명의 문구가 잠깐 찍혔다가
          // 사라진다.
          if (_isLegacyPlace) ...[
            _infoRow(Icons.people_outline, '최대 $_capacity명'),
            if (_unitMinutes == 1440)
              _infoRow(
                Icons.schedule_outlined,
                '하루 단위 대여 · 최소 ${_fmtMinutes(_minBookingMinutes)}',
              )
            else if (isOpen24)
              _infoRow(
                Icons.schedule_outlined,
                '24시간 운영 · 최소 ${_fmtMinutes(_minBookingMinutes)}',
              )
            else if (openLabel.isNotEmpty && closeLabel.isNotEmpty)
              _infoRow(
                Icons.schedule_outlined,
                '운영 $openLabel ~ $closeLabel · 최소 ${_fmtMinutes(_minBookingMinutes)}',
              ),
            _infoRow(
              Icons.monetization_on_outlined,
              '${_fmtPrice(_pricePerHour)} / 시간',
            ),
            _infoRow(
              Icons.timer_outlined,
              '예약 단위: ${_fmtMinutes(_unitMinutes)}',
            ),
            if (availableDays.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: availableDays.map((a) => _dayChip(a)).toList(),
              ),
            ],
          ],
          // 신규 스키마: 공용 편의시설
          if (commonFacilities.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: commonFacilities
                  .map((f) => _facilityChip(f, const Color(0xFF7C5CBF)))
                  .toList(),
            ),
          ],
          // 기타 편의 서비스 — 정식 편의시설 칩 아래에 항목명 그대로.
          if (CustomAmenities.of(d).isNotEmpty) ...[
            const SizedBox(height: 14),
            CustomAmenityView(data: d, accent: const Color(0xFF7C5CBF)),
          ],
          // 좌석·공간 + 이용 편의 옵션 — 등록 화면과 같은 카탈로그를 읽어
          // 아이콘/좌석별 최대 인원까지 함께 보여준다.
          // 좌석 그룹에서 고른 게 있을 때만 — facilityOptions에는 외부 음식도
          // 함께 들어 있어서 isNotEmpty로 판단하면 외부 음식만 고른 문서에서
          // 빈 "좌석·공간" 제목이 남는다.
          if (facilityOptions.hasAnyIn(
            PlaceFacilityCatalog.seatingSection,
          )) ...[
            const SizedBox(height: 14),
            Row(
              children: const [
                Text('🪑', style: TextStyle(fontSize: 14)),
                SizedBox(width: 6),
                Text(
                  '좌석·공간',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            PlaceFacilityOptionsView(options: facilityOptions),
          ],
          // 외부 음식 반입 — 고르지 않은 기존 문서에는 아무것도 늘지 않는다.
          if (facilityOptions.hasAnyIn(PlaceFacilityCatalog.foodSection)) ...[
            const SizedBox(height: 14),
            Row(
              children: const [
                Text('🍽', style: TextStyle(fontSize: 14)),
                SizedBox(width: 6),
                Text(
                  '외부 음식 반입',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            PlaceFacilityOptionsView(
              options: facilityOptions,
              groups: PlaceFacilityCatalog.foodSection,
            ),
          ],
          if (petConditionLines.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF7FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD9E8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🐶 반려동물 동반 정보',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7C5CBF),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...petConditionLines.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        line,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 도로명 주소 + 상세주소를 합친 전체 주소 — 화면 표시·복사·길찾기가
  /// 모두 같은 값을 쓴다. 둘 중 하나만 있어도 그대로 동작한다.
  String get _fullAddress => PlaceAddressRow.joinAddress(
    _data['address'] as String?,
    _data['detailAddress'] as String?,
  );

  Widget _infoRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFFFF6FA0)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
      ],
    ),
  );

  Widget _dayChip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F5F7),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 12, color: Colors.black54),
    ),
  );

  Widget _facilityChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
    ),
  );

  // ── 이 공간대여에 연결된 파티 ────────────────────────────────────────────
  //
  // 조회 기준은 파티 문서의 `linkedPlaceId`다 — 플레이스 상세가
  // `linkedEventId`로 같은 목록을 그리는 것과 정확히 같은 규칙이고,
  // "숙박+파티" 콤보로 함께 등록된 파티도 같은 필드라 함께 잡힌다
  // (자세한 배경은 place_party_link_service.dart 상단 주석).
  //
  // **빌드마다 새로 질의하지 않는다** — 이 화면은 날짜·룸을 고를 때마다 다시
  // 그려지므로, 그때마다 읽으면 조용히 읽기 비용만 쌓인다. 처음 한 번과
  // "파티 추가"로 새 파티가 붙은 뒤에만 다시 읽는다.
  Future<QuerySnapshot<Map<String, dynamic>>> _queryLinkedParties() =>
      FirebaseFirestore.instance
          .collection('parties')
          .where('linkedPlaceId', isEqualTo: widget.placeId)
          .get();

  void _reloadLinkedParties() {
    if (!mounted) return;
    setState(() => _linkedPartiesFuture = _queryLinkedParties());
  }

  /// "숙박+파티" 콤보로 등록된 장소(`linkedPartyId` 있음)에서만 렌더링되는
  /// "파티 정보 함께보기" 카드 — 연결된 `parties/{id}` 문서를 1회 조회해
  /// 날짜/참가비/모집상태를 보여주고, 파티 상세로 이동하는 버튼을 제공한다.
  /// 필드가 없는(일반) 장소는 아무것도 그리지 않는다.
  Widget _linkedPartyCard() {
    final linkedPartyId = _data['linkedPartyId'] as String?;
    if (linkedPartyId == null || linkedPartyId.isEmpty) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('parties')
          .doc(linkedPartyId)
          .get(),
      builder: (context, snapshot) {
        final partyData = snapshot.data?.data();
        if (partyData == null) return const SizedBox.shrink();
        // 파티 카드·상세와 같은 판정 — 호스트가 남/여 모집을 따로 닫아 둘 수
        // 있어서 모집 상태는 보는 사람 성별 기준이다(PartyGenderRecruit).
        final status = PartyCard.effectiveStatusFor(
          partyData,
          UserSession.gender,
        );
        final date = PartyCard.formatDate(partyData);
        final maleFee = (partyData['maleFee'] as num?)?.toInt();
        final femaleFee = (partyData['femaleFee'] as num?)?.toInt();
        final fee = maleFee ?? femaleFee ?? 0;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0F5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFD6E4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '🎉 파티 정보 함께보기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  PartyCard.statusChip(status),
                ],
              ),
              const SizedBox(height: 10),
              if (date.isNotEmpty)
                Text(
                  '일정 : $date',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              if (fee > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '참가비 : ${formatPrice(fee)}',
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ),
              const SizedBox(height: 12),
              // 이 카드는 상세 본문 **전체 폭**을 쓰는 콤보 대표 카드라, 아래
              // 패키지 예약 버튼과 같은 급의 full-width CTA를 쓴다. 위 🎉 파티
              // 열([PlaceOfferingBoard])의 요약 카드는 반 폭이라 이벤트 카드와
              // 같은 '자세히 보기 >' 줄로 끝난다 — 자리 크기가 달라 버튼도
              // 다르지만, 눌러서 가는 곳(파티 상세)은 같다.
              LinkedPartyDetailButton(
                onPressed: () => Navigator.push(
                  context,
                  webFramedRoute(
                    (_) => PartyDetailScreen(docId: linkedPartyId),
                  ),
                ),
              ),
              if (_data['packageBookingEnabled'] == true) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      webFramedRoute(
                        (_) => PackageBookingScreen(
                          placeId: widget.placeId,
                          partyId: linkedPartyId,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.card_giftcard, size: 18),
                    label: const Text('📦 패키지로 예약하기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD94F7A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _descCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '장소 소개',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          _data['description'] as String,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black87,
            height: 1.65,
          ),
        ),
      ],
    ),
  );

  Widget _policyCard(String policy) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '환불/취소 규정',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          policy,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black54,
            height: 1.65,
          ),
        ),
      ],
    ),
  );

  // ── 룸 선택 섹션 ──────────────────────────────────────────────────────────

  Widget _roomsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '룸 선택',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            '예약할 룸을 선택해주세요',
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
          const SizedBox(height: 14),
          // 이 섹션은 룸이 **있다고 확정된 뒤에만** 그려지므로 로딩 분기가
          // 없다 — 스피너를 여기 두면 구 스키마 장소에서 '룸 선택' 제목이
          // 잠깐 떴다 사라진다.
          ..._rooms.map((room) => _roomCard(room)),
        ],
      ),
    );
  }

  /// 룸을 읽지 못했을 때 예약 영역 자리에 놓는 카드 — 구 스키마 기본값을
  /// 대신 보여주는 대신, 못 읽었다는 사실과 다시 시도만 내놓는다.
  Widget _roomsErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.wifi_off_rounded, size: 18, color: Colors.black38),
              SizedBox(width: 8),
              Text(
                '예약 정보를 불러오지 못했어요',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '네트워크 상태를 확인한 뒤 다시 시도해주세요.',
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loadRooms,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('다시 시도'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF7C5CBF),
                side: const BorderSide(color: Color(0xFFD9CCF0)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomCard(Map<String, dynamic> room) {
    final isSelected = _selectedRoom?['id'] == room['id'];
    final roomName = room['roomName'] as String? ?? '룸';
    final capMin = (room['capacityMin'] as num?)?.toInt() ?? 1;
    final capMax = (room['capacityMax'] as num?)?.toInt() ?? 0;
    final price = (room['pricePerHour'] as num?)?.toInt() ?? 0;
    final unit = (room['bookingUnitMinutes'] as num?)?.toInt() ?? 60;
    final openT = room['openTime'] as String? ?? '';
    final closeT = room['closeTime'] as String? ?? '';
    final roomOpen24 = room['isOpen24Hours'] as bool? ?? false;
    final facilities = (room['facilities'] as List?)?.cast<String>() ?? [];
    final images = (room['roomImages'] as List?)?.cast<String>() ?? [];
    // 룸이 받는 예약 방식 — 요금 표기(1박/시간당)와 방식 배지에 함께 쓴다.
    final roomModes = sortedModes(roomReservationModes(room));
    final roomStay = StayConfig.fromMap(room);
    final priceLabel = roomModes.contains(ReservationMode.stay)
        ? '${_fmtPrice(roomStay.pricePerNight)} / 박'
        : '${_fmtPrice(price)} / 시간';

    return GestureDetector(
      onTap: () => _selectRoom(room),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF0F5) : const Color(0xFFF8F8FB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFF6FA0)
                : const Color(0xFFE8EBF2),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 룸 썸네일
                if (images.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      images[0],
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, e, st) => Container(
                        width: 56,
                        height: 56,
                        color: const Color(0xFFFFE0EE),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3EFFA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.door_front_door_outlined,
                      size: 28,
                      color: Color(0xFF7C5CBF),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        roomName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '기준 $capMin인 / 최대 $capMax인  ·  $priceLabel',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: roomModes
                            .map(
                              (m) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3EFFA),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  m.chipLabel,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF7C5CBF),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      if (roomOpen24)
                        Text(
                          '24시간 운영  ·  ${_fmtMinutes(unit)} 단위',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                        )
                      else if (openT.isNotEmpty && closeT.isNotEmpty)
                        Text(
                          '${_fmtTimeStr(openT)} ~ ${_fmtTimeStr(closeT)}  ·  ${_fmtMinutes(unit)} 단위',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFFFF6FA0),
                    size: 22,
                  ),
              ],
            ),
            if (facilities.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: facilities
                    .take(6)
                    .map((f) => _facilityChip(f, const Color(0xFF7C5CBF)))
                    .toList(),
              ),
            ],
            // 룸 환불 규정 — 파티 등록과 동일한 구조(refundPolicy 구간)로 표시.
            // 구조화된 값이 있으면 그걸 우선하고, 없고 옛 자유입력(cancelPolicy)만
            // 있는 기존 문서는 하위호환으로 그 문자열을 그대로 보여준다.
            ...(() {
              final tiers = RefundTier.listFromDynamic(room['refundPolicy']);
              if (tiers.isNotEmpty) {
                return [
                  const SizedBox(height: 10),
                  const Text(
                    '환불 규정',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  RefundPolicyView(tiers: tiers, subjectLabel: '이용'),
                ];
              }
              final legacy = room['cancelPolicy'] as String?;
              if (legacy != null && legacy.isNotEmpty) {
                return [const SizedBox(height: 10), _policyCard(legacy)];
              }
              return const <Widget>[];
            })(),
          ],
        ),
      ),
    );
  }

  // ── 예약 섹션 ─────────────────────────────────────────────────────────────

  Widget _reservationCard() {
    // 선택된 룸 정보 헤더 (신규 스키마)
    final selectedRoomName = _selectedRoom?['roomName'] as String?;
    final isDaily = _isLegacyDaily;
    final modes = sortedModes(_modes);
    final showModeTabs = modes.length > 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selectedRoomName != null) ...[
            Row(
              children: [
                const Icon(
                  Icons.door_front_door_outlined,
                  size: 16,
                  color: Color(0xFF7C5CBF),
                ),
                const SizedBox(width: 6),
                Text(
                  selectedRoomName,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7C5CBF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          const Text(
            '예약하기',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // 예약 방식 탭을 먼저 고르게 한다 — 숙박이면 아래 날짜 라벨이
          // "체크인 날짜"로 바뀌는 등 이후 입력이 방식에 따라 달라지기 때문.
          if (showModeTabs) ...[
            _bookingTypeTabs(modes),
            const SizedBox(height: 16),
          ],

          _fieldLabel(_isStay ? '체크인 날짜' : '이용 날짜'),
          _dateSelector(),
          const SizedBox(height: 20),

          if (_isStay) ...[
            _fieldLabel('숙박 기간'),
            _nightsPicker(),
            const SizedBox(height: 20),
          ] else if (isDaily) ...[
            if (_selectedDate != null) ...[
              _dayAvailabilityBadge(),
              const SizedBox(height: 20),
            ],
          ] else if (_isPackageMode) ...[
            _fieldLabel('패키지 선택'),
            _packageList(),
            const SizedBox(height: 20),
          ] else ...[
            _fieldLabel('예약 시간'),
            _hourlyModeToggle(),
            const SizedBox(height: 10),
            _selectionSummary(),
            _useRangePicker ? _rangePicker() : _slotGrid(),
            const SizedBox(height: 20),
          ],

          // 숙박은 위 "숙박 기간"에서 체크인~체크아웃을 이미 보여줬으므로
          // 분 단위 이용 시간을 다시 적지 않는다.
          if (!_isStay && _effectiveTotalMinutes > 0) ...[
            _fieldLabel('이용 시간'),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _fmtMinutes(_effectiveTotalMinutes),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF6FA0),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          _fieldLabel('이용 인원'),
          _peoplePicker(),
          const SizedBox(height: 20),

          _priceSummary(),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(),
          ),

          const Text(
            '예약자 정보',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          _fieldLabel('이름'),
          TextField(controller: _nameCtrl, decoration: _inputDeco('예약자 이름')),
          const SizedBox(height: 12),
          _fieldLabel('연락처'),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _inputDeco('연락처 (숫자만)'),
          ),
          const SizedBox(height: 12),
          _fieldLabel('요청사항 (선택)'),
          TextField(
            controller: _requestCtrl,
            maxLines: 3,
            decoration: _inputDeco('호스트에게 전달할 내용을 입력해주세요'),
          ),
        ],
      ),
    );
  }

  // 룸이 여러 예약 방식을 받을 때 보이는 "🛏 숙박 / ⏱ 시간제 / 📦 패키지" 탭.
  Widget _bookingTypeTabs(List<ReservationMode> modes) {
    return Row(
      children: [
        for (int i = 0; i < modes.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _modeTabButton(modes[i])),
        ],
      ],
    );
  }

  Widget _modeTabButton(ReservationMode mode) {
    final selected = _effectiveMode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        _bookingTypeChoice = mode;
        // 모드를 바꾸면 이전 모드에서 고른 선택은 의미가 없으니 비운다.
        _selectedSlots.clear();
        _rangeStart = null;
        _rangeEnd = null;
        _selectedPackage = null;
        _nights = _stay.minNights;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF6FA0) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
          ),
        ),
        child: Text(
          mode.chipLabel,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }

  /// 숙박일 수 선택 — 고른 박수만큼 체크아웃 날짜가 함께 계산돼 보인다.
  /// 이미 예약된 기간과 겹치는 박수는 아예 후보에서 빠진다.
  Widget _nightsPicker() {
    if (_selectedDate == null) {
      return const Text(
        '체크인 날짜를 먼저 선택해주세요.',
        style: TextStyle(fontSize: 13, color: Colors.black38),
      );
    }
    if (_isLoadingBookings) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFFFF6FA0),
          ),
        ),
      );
    }
    final options = _availableNightOptions;
    if (options.isEmpty) {
      return const Text(
        '이 날짜에는 예약 가능한 숙박 기간이 없어요. 다른 날짜를 선택해주세요.',
        style: TextStyle(fontSize: 13, color: Colors.redAccent),
      );
    }
    final checkOut = _checkOutDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options
              .map(
                (n) => GestureDetector(
                  onTap: () => setState(() => _nights = n),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _nights == n
                          ? const Color(0xFFFF6FA0)
                          : const Color(0xFFF7F7FA),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _nights == n
                            ? const Color(0xFFFF6FA0)
                            : const Color(0xFFDDE1EC),
                      ),
                    ),
                    child: Text(
                      '$n박',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _nights == n
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: _nights == n ? Colors.white : Colors.black54,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        if (checkOut != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3EFFA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '체크인 ${_fmtDateShort(_selectedDate!)} ${_fmtTimeStr(_stay.checkInTime)}'
              '  →  체크아웃 ${_fmtDateShort(checkOut)} ${_fmtTimeStr(_stay.checkOutTime)}',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF7C5CBF),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _fmtDateShort(DateTime d) =>
      '${d.month}.${d.day.toString().padLeft(2, '0')}(${_weekdays[d.weekday - 1]})';

  // 시간제 모드 안에서 "시간 범위로 선택"과 "직접 체크" 중 어떤 UI를 쓸지.
  Widget _hourlyModeToggle() {
    return Row(
      children: [
        _toggleChip(
          '시간 범위로 선택',
          _useRangePicker,
          () => setState(() => _useRangePicker = true),
        ),
        const SizedBox(width: 8),
        _toggleChip(
          '직접 체크',
          !_useRangePicker,
          () => setState(() => _useRangePicker = false),
        ),
      ],
    );
  }

  Widget _toggleChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF3EFFA) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF7C5CBF) : const Color(0xFFDDE1EC),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
            color: selected ? const Color(0xFF7C5CBF) : Colors.black54,
          ),
        ),
      ),
    );
  }

  Widget _dateSelector() {
    final has = _selectedDate != null;
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: has ? const Color(0xFFFFF0F5) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: has ? Border.all(color: const Color(0xFFFF6FA0)) : null,
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: has ? const Color(0xFFFF6FA0) : Colors.black38,
            ),
            const SizedBox(width: 10),
            Text(
              has
                  ? '${_selectedDate!.year}.${_selectedDate!.month.toString().padLeft(2, '0')}.${_selectedDate!.day.toString().padLeft(2, '0')} (${_weekdays[_selectedDate!.weekday - 1]})'
                  : '날짜를 선택해주세요',
              style: TextStyle(
                fontSize: 14,
                color: has ? const Color(0xFFFF6FA0) : Colors.black38,
                fontWeight: has ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayAvailabilityBadge() {
    if (_isLoadingBookings) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFFFF6FA0),
          ),
        ),
      );
    }
    final booked = _isDayRangeBooked(_selectedDate!, 1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: booked ? const Color(0xFFFFF0F0) : const Color(0xFFF0FFF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: booked ? const Color(0xFFFFB3B3) : const Color(0xFFB3E6C8),
        ),
      ),
      child: Row(
        children: [
          Icon(
            booked ? Icons.cancel_outlined : Icons.check_circle_outline,
            size: 18,
            color: booked ? Colors.redAccent : const Color(0xFF2E7D32),
          ),
          const SizedBox(width: 8),
          Text(
            booked ? '선택한 날짜에 이미 예약이 있습니다' : '예약 가능한 날짜입니다',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: booked ? Colors.redAccent : const Color(0xFF2E7D32),
            ),
          ),
        ],
      ),
    );
  }

  // 지금 고른 시간 슬롯들을 한눈에 보여주는 요약 배너 — 여러 구간을 골라도
  // (예: 10~11시 + 14~15시) 각 구간을 쉼표로 나열하고 총 이용시간을 함께
  // 보여준다. 최소 이용시간 미달이면 안내 색으로 바뀐다. 범위 선택/체크박스
  // 어느 쪽으로 골랐든 같은 _selectedSlots를 보고 있어서 항상 정확하다.
  Widget _selectionSummary() {
    if (_selectedSlots.isEmpty) return const SizedBox.shrink();
    final ranges = _selectedRanges;
    final rangeText = ranges
        .map((r) => '${_fmtSlotInline(r.start)} ~ ${_fmtSlotInline(r.end)}')
        .join(', ');
    final belowMin = _totalMinutes < _minBookingMinutes;
    final overMax =
        _maxBookingMinutes != null && _totalMinutes > _maxBookingMinutes!;
    final warn = belowMin || overMax;
    final color = warn ? const Color(0xFFE65100) : const Color(0xFFFF6FA0);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: warn ? const Color(0xFFFFF3E0) : const Color(0xFFFFF0F5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: warn ? const Color(0xFFFFCC80) : const Color(0xFFFFD6E4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            warn ? Icons.info_outline : Icons.event_available,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              belowMin
                  ? '선택된 시간: $rangeText (${_fmtMinutes(_totalMinutes)}) · 최소 ${_fmtMinutes(_minBookingMinutes)} 이상 선택해주세요'
                  : overMax
                  ? '선택된 시간: $rangeText (${_fmtMinutes(_totalMinutes)}) · 최대 ${_fmtMinutes(_maxBookingMinutes!)}까지 가능해요'
                  : '선택된 시간: $rangeText (${_fmtMinutes(_totalMinutes)})',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // "시작~종료" 두 상자를 눌러 시트에서 고르는 방식 — 빠르게 연속 구간
  // 하나를 예약하고 싶을 때 체크박스를 여러 번 누르지 않아도 된다.
  Widget _rangePicker() {
    if (_selectedDate == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.access_time_outlined, size: 16, color: Colors.black26),
            SizedBox(width: 8),
            Text(
              '날짜를 먼저 선택해주세요',
              style: TextStyle(fontSize: 13, color: Colors.black26),
            ),
          ],
        ),
      );
    }
    if (_isLoadingBookings) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFFFF6FA0),
          ),
        ),
      );
    }
    return Row(
      children: [
        Expanded(child: _rangeTimeBox('시작', _rangeStart, _pickRangeStart)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('~', style: TextStyle(fontSize: 16)),
        ),
        Expanded(child: _rangeTimeBox('종료', _rangeEnd, _pickRangeEnd)),
      ],
    );
  }

  Widget _rangeTimeBox(String label, int? minute, VoidCallback onTap) {
    final hasVal = minute != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hasVal ? const Color(0xFFFFF0F5) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: hasVal ? Border.all(color: const Color(0xFFFF6FA0)) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.black38),
            ),
            const SizedBox(height: 2),
            Text(
              hasVal ? _fmtSlotInline(minute) : '선택',
              style: TextStyle(
                fontSize: 14,
                fontWeight: hasVal ? FontWeight.w600 : FontWeight.normal,
                color: hasVal ? const Color(0xFFFF6FA0) : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slotGrid() {
    if (_selectedDate == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.access_time_outlined, size: 16, color: Colors.black26),
            SizedBox(width: 8),
            Text(
              '날짜를 먼저 선택해주세요',
              style: TextStyle(fontSize: 13, color: Colors.black26),
            ),
          ],
        ),
      );
    }
    if (_isLoadingBookings) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFFFF6FA0),
          ),
        ),
      );
    }

    final slots = _slots;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...slots.map((slotMin) {
          final disabled = _isRangeDisabled(slotMin);
          final selected = _selectedSlots.contains(slotMin);
          return GestureDetector(
            onTap: disabled
                ? null
                : () => setState(() {
                    if (!_selectedSlots.remove(slotMin)) {
                      _selectedSlots.add(slotMin);
                    }
                    // 체크박스로 직접 고르면 범위 선택 상자는 더 이상 그
                    // 선택을 대표하지 못하므로 비워 혼동을 막는다.
                    _rangeStart = null;
                    _rangeEnd = null;
                  }),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: disabled
                    ? const Color(0xFFEEEEEE)
                    : selected
                    ? const Color(0xFFFF6FA0)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: disabled
                      ? const Color(0xFFDDDDDD)
                      : selected
                      ? const Color(0xFFFF6FA0)
                      : const Color(0xFFFF6FA0).withValues(alpha: 0.35),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _fmtSlotRange(slotMin),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: disabled
                            ? Colors.black26
                            : selected
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                  ),
                  if (disabled)
                    const Text(
                      '예약됨',
                      style: TextStyle(fontSize: 11, color: Colors.black38),
                    )
                  else if (selected)
                    const Icon(
                      Icons.check_circle,
                      size: 18,
                      color: Colors.white,
                    ),
                ],
              ),
            ),
          );
        }),
        if (_bookedRanges.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEEEEE),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  '예약됨',
                  style: TextStyle(fontSize: 11, color: Colors.black38),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // 패키지 목록 — 선택한 날짜 요일에 맞는(days) 활성 패키지만 카드로
  // 보여준다. 이미 그 시간대가(시간제든 패키지든) 예약돼 있으면 회색 처리.
  Widget _packageList() {
    if (_selectedDate == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.event_busy_outlined, size: 16, color: Colors.black26),
            SizedBox(width: 8),
            Text(
              '날짜를 먼저 선택해주세요',
              style: TextStyle(fontSize: 13, color: Colors.black26),
            ),
          ],
        ),
      );
    }
    if (_isLoadingBookings) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFFFF6FA0),
          ),
        ),
      );
    }
    final pkgs = _packages.where(_isPackageApplicableToday).toList();
    if (pkgs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '선택한 날짜에 이용 가능한 패키지가 없어요.',
          style: TextStyle(fontSize: 13, color: Colors.black45),
        ),
      );
    }
    return Column(
      children: pkgs.map((pkg) {
        final disabled = _isPackageDisabled(pkg);
        final selected =
            !disabled &&
            _selectedPackage != null &&
            _selectedPackage!['id'] == pkg['id'];
        return GestureDetector(
          onTap: disabled ? null : () => setState(() => _selectedPackage = pkg),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: disabled
                  ? const Color(0xFFEEEEEE)
                  : selected
                  ? const Color(0xFFFF6FA0)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: disabled
                    ? const Color(0xFFDDDDDD)
                    : selected
                    ? const Color(0xFFFF6FA0)
                    : const Color(0xFFFF6FA0).withValues(alpha: 0.35),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pkg['name'] as String? ?? '패키지',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: disabled
                              ? Colors.black26
                              : selected
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_fmtTimeStr(pkg['startTime'] as String? ?? '')} ~ ${_fmtTimeStr(pkg['endTime'] as String? ?? '')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: disabled
                              ? Colors.black26
                              : selected
                              ? Colors.white70
                              : Colors.black54,
                        ),
                      ),
                      if ((pkg['description'] as String?)?.isNotEmpty ==
                          true) ...[
                        const SizedBox(height: 4),
                        Text(
                          pkg['description'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: disabled
                                ? Colors.black26
                                : selected
                                ? Colors.white70
                                : Colors.black45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _fmtPrice((pkg['price'] as num?)?.toInt() ?? 0),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: disabled
                            ? Colors.black26
                            : selected
                            ? Colors.white
                            : const Color(0xFFFF6FA0),
                      ),
                    ),
                    if (disabled)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          '예약됨',
                          style: TextStyle(fontSize: 11, color: Colors.black38),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _peoplePicker() {
    return Row(
      children: [
        IconButton(
          onPressed: _peopleCount > 1
              ? () => setState(() => _peopleCount--)
              : null,
          icon: const Icon(Icons.remove_circle_outline, size: 28),
          color: const Color(0xFFFF6FA0),
          disabledColor: Colors.black26,
        ),
        Expanded(
          child: Center(
            child: Text(
              '$_peopleCount명',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        IconButton(
          onPressed: _peopleCount < _capacity
              ? () => setState(() => _peopleCount++)
              : null,
          icon: const Icon(Icons.add_circle_outline, size: 28),
          color: const Color(0xFFFF6FA0),
          disabledColor: Colors.black26,
        ),
      ],
    );
  }

  Widget _priceSummary() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          if (_isStay) ...[
            _priceRow('1박 요금', _fmtPrice(_stay.pricePerNight)),
            const SizedBox(height: 6),
            _priceRow('숙박 기간', '$_nights박'),
          ] else ...[
            if (!_isPackageMode) ...[
              _priceRow('시간당 금액', _fmtPrice(_pricePerHour)),
              const SizedBox(height: 6),
            ],
            _priceRow('이용 시간', _fmtMinutes(_effectiveTotalMinutes)),
          ],
          const Divider(height: 18, color: Color(0xFFFFD6E4)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '총 금액',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              Text(
                _fmtPrice(_effectiveTotalPrice),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF6FA0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54)),
      Text(value, style: const TextStyle(fontSize: 13, color: Colors.black87)),
    ],
  );

  Widget _bottomBar() {
    // 호스트가 문의를 열어 뒀고 내 장소가 아닐 때만 문의 버튼이 자리를
    // 차지한다. 아니면 예약 버튼이 예전처럼 전체 폭을 그대로 쓴다.
    final showInquiry = GuestInquiryButton.shouldShow(
      enabled: ListingInquiry.isEnabled(_data),
      hostId: _data['hostId'] as String? ?? '',
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            if (showInquiry) ...[
              SizedBox(
                width: 108,
                height: 52,
                child: GuestInquiryButton(
                  enabled: true,
                  compact: true,
                  target: InquiryTarget.rental,
                  listingId: widget.placeId,
                  hostId: _data['hostId'] as String? ?? '',
                  hostName: _data['hostName'] as String? ?? '호스트',
                  listingTitle: _data['name'] as String? ?? '장소',
                  guide: ListingInquiry.guideOf(_data),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(child: _reserveButton()),
          ],
        ),
      ),
    );
  }

  Widget _reserveButton() => SizedBox(
    height: 52,
    child: ElevatedButton(
      // 룸 조회 전·실패 상태에서는 어느 스키마인지 모르거나 예약 정보를
      // 못 읽은 것이라 누를 수 없다 — 여기서 '예약하기'로 활성해 두면 첫
      // 프레임에 눌러 버릴 수 있고, 곧바로 '룸을 선택해주세요'(비활성)로
      // 바뀌어 버튼이 깜빡인다.
      onPressed:
          (_isSubmitting ||
              _roomsLoad != _RoomsLoad.ready ||
              (_hasRooms && _selectedRoom == null))
          ? null
          : _submit,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFFF6FA0),
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey.shade300,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      child: _isSubmitting
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              // 조회 전에는 '예약하기'/'룸을 선택해주세요' 중 어느 쪽도
              // 사실이 아니라, 어느 쪽을 골라도 한쪽 스키마에서 문구가
              // 한 번 뒤집힌다. 확정 전에는 지금 상태를 그대로 적는다.
              switch (_roomsLoad) {
                _RoomsLoad.loading => '불러오는 중…',
                _RoomsLoad.failed => '예약 정보를 불러오지 못했어요',
                _RoomsLoad.ready =>
                  _hasRooms && _selectedRoom == null ? '룸을 선택해주세요' : '예약하기',
              },
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
    ),
  );

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.black54,
      ),
    ),
  );

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE8EBF2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE8EBF2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFFF6FA0)),
    ),
  );
}
