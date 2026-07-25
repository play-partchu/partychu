import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/widgets/favorite_star_button.dart';
import 'package:party_app/widgets/media_gallery.dart';
import 'package:party_app/services/chat_service.dart';
import 'package:party_app/services/analytics_service.dart';
import 'package:party_app/screens/chat_room_screen.dart';
import 'package:party_app/screens/portone_checkout_screen.dart';
import 'package:party_app/screens/package_booking_screen.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/web_frame.dart';

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
  // ── 룸 ───────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _rooms = [];
  Map<String, dynamic>? _selectedRoom;
  bool _isLoadingRooms = false;

  // ── 예약 상태 ─────────────────────────────────────────────────────────────
  DateTime? _selectedDate;
  // 선택된 슬롯들의 시작 분(자정 기준, _unitMinutes 단위) — 다중 선택이라
  // 연속이 아니어도(예: 10시대 + 14시대) 자유롭게 담을 수 있게 Set을 쓴다.
  final Set<int> _selectedSlots = {};
  int _peopleCount = 1;

  // ── 예약 방식(시간제/패키지) ────────────────────────────────────────────────
  // reservationMode가 'both'일 때만 의미 있는 사용자의 탭 선택 — 단일
  // 모드('hourly'|'package')면 _effectiveBookingType이 그 값을 그대로 쓴다.
  String _bookingType = 'hourly';
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

  Map<String, dynamic> get _activeData => _selectedRoom ?? widget.data;

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

  // 룸 있는 신규 스키마인지 여부
  bool get _hasRooms => _rooms.isNotEmpty;

  // ── 예약 방식 (시간제/패키지/둘 다) ────────────────────────────────────────

  /// 'hourly' | 'package' | 'both'. 저장된 값이 없는 기존 룸/장소는 이미
  /// 시간제 필드만 쓰고 있었으므로 'hourly'로, 저장된 값은 없는데 패키지
  /// 데이터가 있으면(과거 데이터) 'package'로 추론한다.
  String get _reservationMode {
    final v = _activeData['reservationMode'] as String?;
    if (v != null) return v;
    return _packages.isNotEmpty ? 'package' : 'hourly';
  }

  /// 지금 실제로 보여줄 예약 방식 — 'both'가 아니면 그 값 그대로, 'both'면
  /// 사용자가 탭으로 고른 [_bookingType].
  String get _effectiveBookingType =>
      _reservationMode == 'both' ? _bookingType : _reservationMode;

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

  /// 지금 선택 상태(시간제 슬롯 또는 패키지)의 총 이용 시간 — 하루 단위
  /// 대여(unitMinutes==1440)는 기존 동작을 그대로 둔다(별도 흐름).
  int get _effectiveTotalMinutes {
    if (_unitMinutes == 1440) return _totalMinutes;
    if (_effectiveBookingType == 'package') {
      final p = _selectedPackage;
      return p != null ? _packageMinutes(p) : 0;
    }
    return _totalMinutes;
  }

  int get _effectiveTotalPrice {
    if (_unitMinutes == 1440) return _totalPrice;
    if (_effectiveBookingType == 'package') {
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

  // ── 룸 로드 ───────────────────────────────────────────────────────────────

  Future<void> _loadRooms() async {
    setState(() => _isLoadingRooms = true);
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
        _isLoadingRooms = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingRooms = false);
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

      if (_unitMinutes == 1440) {
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
        // 넉넉히 조회한다.
        final queryStart = Timestamp.fromDate(
          selectedMidnight.subtract(const Duration(days: 1)),
        );
        final queryEnd = Timestamp.fromDate(
          selectedMidnight.add(const Duration(days: 1)),
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
          if (endMin <= 0 || startMin >= 1440 || startMin >= endMin) continue;
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

    final isDaily = _unitMinutes == 1440;
    final bookingType = isDaily ? 'daily' : _effectiveBookingType;

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

    setState(() => _isSubmitting = true);
    try {
      // 최종 겹침 재확인(클라이언트 프리체크) — 진짜 확정 판정은 서버
      // 트랜잭션(createPendingReservation)에서 한 번 더 한다.
      await _loadBooked(_selectedDate!);
      if (!mounted) return;

      final payload = <String, dynamic>{
        'placeId': widget.placeId,
        if (_selectedRoomId != null) 'roomId': _selectedRoomId,
        'date': _dateStr(_selectedDate!),
        'bookingType': bookingType,
        'peopleCount': _peopleCount,
        'requesterName': _nameCtrl.text.trim(),
        'requesterPhone': _phoneCtrl.text.trim(),
        'requestMessage': _requestCtrl.text.trim(),
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
      final orderName = widget.data['name'] as String? ?? '장소 예약';

      if (!mounted) return;

      if (totalPrice <= 0) {
        // 무료 예약 — 결제창 없이 바로 검증(=확정) 호출.
        await _verifyAndFinish(groupId);
        return;
      }

      final paid = await Navigator.push<bool>(
        context,
        webFramedRoute((_) => PortoneCheckoutScreen(
            paymentId: groupId,
            orderName: orderName,
            amount: totalPrice,
            buyerName: _nameCtrl.text.trim(),
            buyerPhone: _phoneCtrl.text.trim(),
          ),
          fullscreenDialog: true,
        ),
      );
      if (!mounted) return;

      if (paid != true) {
        // 결제 취소/실패 — 잡아둔 pending 예약을 만료를 기다리지 않고 즉시 반납.
        await _cancelPending(groupId);
        _msg('결제가 완료되지 않아 예약이 취소됐어요.');
        return;
      }
      await _verifyAndFinish(groupId);
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

  Future<void> _verifyAndFinish(String groupId) async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-northeast3',
    ).httpsCallable('verifyAndConfirmReservation');
    await callable.call<Map<Object?, Object?>>({'groupId': groupId});
    if (!mounted) return;
    _showSuccessDialog(groupId);
  }

  Future<void> _cancelPending(String groupId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('cancelReservation');
      await callable.call<Map<Object?, Object?>>({'groupId': groupId});
    } catch (_) {
      // 취소 호출이 실패해도 만료 스케줄러가 나중에 정리해준다.
    }
  }

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );

  Future<void> _showSuccessDialog(String bookingId) async {
    final hostId = widget.data['hostId'] as String? ?? '';
    final hostName = widget.data['hostName'] as String? ?? '호스트';
    final placeName = widget.data['name'] as String? ?? '파티 장소';

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

      // 자동발송 등록: 장소에 autoMessage가 설정된 경우
      final autoText = widget.data['autoMessage'] as String?;
      if (autoText != null && autoText.isNotEmpty && _selectedDate != null) {
        final appt = _selectedDate!;
        final sendAt = DateTime(
          appt.year,
          appt.month,
          appt.day,
          10,
          0,
        ).subtract(const Duration(hours: 2));
        await ChatService.schedulePendingAutoMessage(
          roomId: roomId,
          hostId: hostId,
          hostName: hostName,
          message: autoText,
          sendAt: sendAt,
        );
      }
    } catch (_) {
      // 채팅방 생성 실패해도 예약 완료는 유지
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFFFF6FA0), size: 26),
            SizedBox(width: 10),
            Text(
              '예약 완료',
              style: TextStyle(
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
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('결제가 완료되어 예약이 확정됐어요.'),
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
                  webFramedRoute((_) => ChatRoomScreen(
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
    final name = widget.data['name'] as String? ?? '장소';
    final imageUrls =
        ((widget.data['imageUrls'] as List?)?.cast<String>() ?? []).toList();
    final videoUrl = widget.data['videoUrl'] as String?;
    final videoThumbnailUrl = widget.data['videoThumbnailUrl'] as String?;
    final hasVideo = videoUrl != null && videoUrl.isNotEmpty;

    // 대표 미디어 — 등록/수정 시 이미 imageUrls 맨 앞(index 0)으로 재정렬해
    // 저장하므로 갤러리는 항상 index 0부터 연다(파티 상세페이지와 동일한
    // 규칙). 재정렬 전에 저장된 과거 장소 데이터도 방어적으로 여기서 한 번
    // 더 맞춰준다(대표 사진이 index 0이 아니면 이 화면에서만 맨 앞으로
    // 옮기고, Firestore에 다시 쓰지는 않는다).
    final cover = getPartyCoverMedia(widget.data, tag: 'PlaceDetailHero');
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
                  if ((widget.data['description'] as String?)?.isNotEmpty ==
                      true) ...[
                    _descCard(),
                    const SizedBox(height: 12),
                  ],
                  if (widget.data['linkedPartyId'] != null) _linkedPartyCard(),
                  // 룸 선택 섹션 (신규 스키마)
                  if (_hasRooms || _isLoadingRooms) ...[
                    _roomsSection(),
                    const SizedBox(height: 12),
                  ],
                  // 환불 정책 (구 스키마 호환)
                  if (!_hasRooms &&
                      (widget.data['cancelPolicy'] as String?)?.isNotEmpty ==
                          true) ...[
                    _policyCard(widget.data['cancelPolicy'] as String),
                    const SizedBox(height: 12),
                  ],
                  // 예약 섹션 (신규: 룸 선택 후 표시 / 구: 항상 표시)
                  if (!_hasRooms || _selectedRoom != null) _reservationCard(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  // ── 장소 정보 카드 ────────────────────────────────────────────────────────

  Widget _infoCard() {
    final d = widget.data;
    // 공용 편의시설 (신규 스키마)
    final commonFacilities =
        (d['commonFacilities'] as List?)?.cast<String>() ?? [];
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
          if ((d['address'] as String?)?.isNotEmpty == true)
            _infoRow(Icons.location_on_outlined, d['address'] as String),
          // 구 스키마에만 있는 장소 단위 정보
          if (!_hasRooms) ...[
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
        ],
      ),
    );
  }

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

  /// "숙박+파티" 콤보로 등록된 장소(`linkedPartyId` 있음)에서만 렌더링되는
  /// "파티 정보 함께보기" 카드 — 연결된 `parties/{id}` 문서를 1회 조회해
  /// 날짜/참가비/모집상태를 보여주고, 파티 상세로 이동하는 버튼을 제공한다.
  /// 필드가 없는(일반) 장소는 아무것도 그리지 않는다.
  Widget _linkedPartyCard() {
    final linkedPartyId = widget.data['linkedPartyId'] as String?;
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
        final status = PartyCard.effectiveStatus(partyData);
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
                Text('일정 : $date', style: const TextStyle(fontSize: 13, color: Colors.black87)),
              if (fee > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('참가비 : ${formatPrice(fee)}',
                      style: const TextStyle(fontSize: 13, color: Colors.black87)),
                ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  webFramedRoute((_) => PartyDetailScreen(docId: linkedPartyId),
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: const Color(0xFFD94F7A),
                ),
                child: const Text('파티 상세 보기 →',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (widget.data['packageBookingEnabled'] == true) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      webFramedRoute((_) => PackageBookingScreen(
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          widget.data['description'] as String,
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
          if (_isLoadingRooms)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF7C5CBF),
                ),
              ),
            )
          else
            ...(_rooms.map((room) => _roomCard(room)).toList()),
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
                        '$capMin ~ $capMax명  ·  ${_fmtPrice(price)} / 시간',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
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
            // 룸 취소 정책
            if ((room['cancelPolicy'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              _policyCard(room['cancelPolicy'] as String),
            ],
          ],
        ),
      ),
    );
  }

  // ── 예약 섹션 ─────────────────────────────────────────────────────────────

  Widget _reservationCard() {
    // 선택된 룸 정보 헤더 (신규 스키마)
    final selectedRoomName = _selectedRoom?['roomName'] as String?;
    final isDaily = _unitMinutes == 1440;
    final showModeTabs = !isDaily && _reservationMode == 'both';

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

          _fieldLabel('이용 날짜'),
          _dateSelector(),
          const SizedBox(height: 20),

          if (showModeTabs) ...[_bookingTypeTabs(), const SizedBox(height: 16)],

          if (isDaily) ...[
            if (_selectedDate != null) ...[
              _dayAvailabilityBadge(),
              const SizedBox(height: 20),
            ],
          ] else if (_effectiveBookingType == 'package') ...[
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

          if (_effectiveTotalMinutes > 0) ...[
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

  // 예약 방식이 'both'일 때만 보이는 "시간제로 예약 / 패키지로 예약" 탭.
  Widget _bookingTypeTabs() {
    return Row(
      children: [
        Expanded(child: _modeTabButton('시간제로 예약', 'hourly')),
        const SizedBox(width: 8),
        Expanded(child: _modeTabButton('패키지로 예약', 'package')),
      ],
    );
  }

  Widget _modeTabButton(String label, String type) {
    final selected = _bookingType == type;
    return GestureDetector(
      onTap: () => setState(() {
        _bookingType = type;
        // 모드를 바꾸면 이전 모드에서 고른 선택은 의미가 없으니 비운다.
        _selectedSlots.clear();
        _rangeStart = null;
        _rangeEnd = null;
        _selectedPackage = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF6FA0) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? const Color(0xFFFF6FA0)
                : const Color(0xFFE8EBF2),
          ),
        ),
        child: Text(
          label,
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
            color: selected
                ? const Color(0xFF7C5CBF)
                : const Color(0xFFDDE1EC),
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
        Expanded(
          child: _rangeTimeBox('시작', _rangeStart, _pickRangeStart),
        ),
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
    final isDaily = _unitMinutes == 1440;
    final isPackage = !isDaily && _effectiveBookingType == 'package';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          if (!isPackage) ...[
            _priceRow('시간당 금액', _fmtPrice(_pricePerHour)),
            const SizedBox(height: 6),
          ],
          _priceRow('이용 시간', _fmtMinutes(_effectiveTotalMinutes)),
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

  Widget _bottomBar() => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: (_isSubmitting || (_hasRooms && _selectedRoom == null))
              ? null
              : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6FA0),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
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
                  _hasRooms && _selectedRoom == null ? '룸을 선택해주세요' : '예약하기',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
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
