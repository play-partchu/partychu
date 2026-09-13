import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/models/payment_order_summary.dart';
import 'package:party_app/models/payment_status.dart';
import 'package:party_app/models/place_rental_reservation.dart';
import 'package:party_app/models/reservation_modes.dart';
import 'package:party_app/screens/payment_method_screen.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 숙박+파티 패키지 예약 — `places.packageBookingEnabled == true`인 콤보에서만
/// 진입하는 통합 예약/결제 화면. 방(또는 패키지) + 인원 + 예약자 정보를
/// 입력받아 createPendingPackageBooking 한 번으로 방 시간과 파티 정원을 함께
/// 잡는다.
///
/// 결제는 장소대여·방문예약·파티 신청과 **같은 화면·같은 규칙**을 쓴다
/// ([PaymentMethodScreen] → 무통장입금/현장결제). PG 계약 전이라 카드·간편결제·
/// 실시간계좌이체·가상계좌는 그 화면에서 '준비중'으로만 보이고 고를 수 없다.
/// 방 시간과 파티 자리는 서버 트랜잭션 하나에서 함께 잡히고 함께 풀린다
/// (packageBookings.js의 applyBundleRelease 참고).
///
/// 콤보 v1은 파티 날짜 = 숙박 날짜로 고정돼 있으므로(party_place_combo_
/// register_screen.dart 참고) 이 화면에는 날짜 선택 UI가 없다 — 서버
/// (createPendingPackageBooking)도 파티의 partyDateTime을 그대로 숙박
/// 날짜로 쓴다.
class PackageBookingScreen extends StatefulWidget {
  final String placeId;
  final String partyId;

  const PackageBookingScreen({
    super.key,
    required this.placeId,
    required this.partyId,
  });

  @override
  State<PackageBookingScreen> createState() => _PackageBookingScreenState();
}

class _PackageBookingScreenState extends State<PackageBookingScreen> {
  bool _loading = true;
  String? _loadError;

  Map<String, dynamic>? _placeData;
  Map<String, dynamic>? _partyData;
  List<Map<String, dynamic>> _rooms = [];
  Map<String, dynamic>? _selectedRoom;

  /// 사용자가 고른 예약 방식 — 룸이 한 가지만 받으면 그 방식으로 고정된다.
  ReservationMode _bookingMode = ReservationMode.hourly;
  Map<String, dynamic>? _selectedPackage;
  int? _startMinutes;
  int? _durationMinutes;
  int _nights = 1;
  int _peopleCount = 1;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _requestCtrl = TextEditingController();

  bool _isSubmitting = false;
  String _submitStatus = '';

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = UserSession.displayName;
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _requestCtrl.dispose();
    super.dispose();
  }

  // ── 데이터 로드 ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final placeSnap = await FirebaseFirestore.instance
          .collection('places')
          .doc(widget.placeId)
          .get();
      final partySnap = await FirebaseFirestore.instance
          .collection('parties')
          .doc(widget.partyId)
          .get();
      if (!placeSnap.exists || !partySnap.exists) {
        if (!mounted) return;
        setState(() {
          _loadError = '정보를 불러오지 못했어요.';
          _loading = false;
        });
        return;
      }
      final roomsSnap = await FirebaseFirestore.instance
          .collection('placeRooms')
          .where('placeId', isEqualTo: widget.placeId)
          .get();
      final rooms = roomsSnap.docs
          .map((d) => {...d.data(), 'id': d.id})
          .where((r) => r['isActive'] != false)
          .toList();

      final partyData = partySnap.data() ?? const <String, dynamic>{};
      // 콤보는 "파티 날짜 = 숙박 날짜"라, 어느 회차에 가느냐가 곧 어느 날
      // 묵느냐다. 정기 파티는 회차가 여럿이므로 결제 전에 고르게 한다.
      // 회차 하나당 날짜 하나이므로 **숙박 날짜와 연결될 수 없는 회차는
      // 애초에 목록에 없다**(PartySchedule.selectableOccurrences가 이미 지난·
      // 마감된 회차를 걸러낸다).
      final occurrences = PartySchedule.isRecurring(partyData)
          ? PartySchedule.selectableOccurrences(partyData)
          : const <PartyOccurrence>[];

      if (!mounted) return;
      setState(() {
        _placeData = placeSnap.data();
        _partyData = partyData;
        _occurrences = occurrences;
        // 고를 것이 하나뿐이면 선택 UI를 띄우지 않고 그대로 정한다.
        _selectedOccurrence = occurrences.length == 1
            ? occurrences.first
            : null;
        _rooms = rooms;
        _selectedRoom = rooms.length == 1 ? rooms.first : null;
        _bookingMode = _defaultMode;
        _nights = _stay.minNights;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = '정보를 불러오지 못했어요.';
        _loading = false;
      });
    }
  }

  // ── 활성 데이터(선택된 룸, 없으면 장소 구스키마 필드로 폴백) ─────────────────

  Map<String, dynamic> get _activeData =>
      _selectedRoom ?? _placeData ?? const {};

  List<Map<String, dynamic>> get _packages =>
      ((_activeData['packages'] as List?) ?? [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .where((p) => p['isActive'] != false)
          .toList();

  /// 이 룸(룸이 없으면 장소 구 스키마)이 받는 예약 방식 전체.
  List<ReservationMode> get _modes =>
      sortedModes(parseReservationModes(_activeData));

  StayConfig get _stay => StayConfig.fromMap(_activeData);

  /// 룸을 새로 고르면 그 룸이 받는 방식 중 첫 번째로 맞춘다 — 숙박을 받는
  /// 숙소면 숙박이, 파티룸이면 시간제/패키지가 기본으로 잡힌다.
  ReservationMode get _defaultMode => _modes.first;

  int get _nightsClamped {
    final stay = _stay;
    final max = stay.maxNights;
    var n = _nights < stay.minNights ? stay.minNights : _nights;
    if (max != null && n > max) n = max;
    return n;
  }

  int get _capacity =>
      (_activeData['capacityMax'] as num?)?.toInt() ??
      (_activeData['capacity'] as num?)?.toInt() ??
      (_activeData['maxCapacity'] as num?)?.toInt() ??
      50;

  // 기준인원 — 예약 화면 인원 섹션에 "기준 X인 / 최대 Y인" 안내로 표시.
  int get _baseCapacity => (_activeData['capacityMin'] as num?)?.toInt() ?? 1;

  int get _pricePerHour => (_activeData['pricePerHour'] as num?)?.toInt() ?? 0;

  static int _parseTimeStr(String t) {
    final p = t.split(':');
    final h = int.tryParse(p[0]) ?? 0;
    final m = p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
    return h * 60 + m;
  }

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

  /// 이 예약이 대상으로 하는 파티 회차들(정기 파티만). 비어 있으면 회차 개념이
  /// 없는 일회성 파티다.
  List<PartyOccurrence> _occurrences = const [];

  /// 사용자가 고른 회차. 회차가 하나뿐이면 [_load]에서 자동으로 정해진다.
  PartyOccurrence? _selectedOccurrence;

  /// 이 예약의 파티 날짜.
  ///
  /// 정기 파티에서 저장된 `partyDateTime`은 **첫 회차 캐시**라 그대로 쓰면 이미
  /// 지난 날짜로 숙박을 잡게 된다 — 고른 회차의 시작 시각이 정답이다.
  DateTime? get _partyDateTime {
    final picked = _selectedOccurrence;
    if (picked != null) return picked.start;
    final ts = _partyData?['partyDateTime'];
    return ts is Timestamp ? ts.toDate() : null;
  }

  String get _partyWeekdayLabel {
    final d = _partyDateTime;
    if (d == null) return '';
    return _weekdays[d.weekday - 1];
  }

  List<Map<String, dynamic>> get _availablePackages => _packages.where((p) {
    final days = (p['days'] as List?)?.cast<String>() ?? const [];
    return days.isEmpty || days.contains(_partyWeekdayLabel);
  }).toList();

  List<int> get _startOptions {
    final options = <int>[];
    for (
      var m = _openMinutes;
      m + _minBookingMinutes <= _closeMinutes;
      m += _unitMinutes
    ) {
      options.add(m);
    }
    return options;
  }

  List<int> get _durationOptions {
    final start = _startMinutes ?? _openMinutes;
    final maxByClose = _closeMinutes - start;
    final maxAllowed = _maxBookingMinutes != null
        ? (_maxBookingMinutes! < maxByClose ? _maxBookingMinutes! : maxByClose)
        : maxByClose;
    final options = <int>[];
    for (var d = _minBookingMinutes; d <= maxAllowed; d += _unitMinutes) {
      options.add(d);
    }
    return options;
  }

  String _fmtMinutes(int m) {
    final h = (m ~/ 60) % 24;
    final mm = m % 60;
    return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }

  // ── 가격 미리보기 ────────────────────────────────────────────────────────
  // 실제 청구액은 서버(createPendingPackageBooking)가 최종 계산해서 돌려주는
  // totalPrice — 여기 표시되는 값은 결제 전 참고용 추정치다(얼리버드 등은
  // 신청 시점 기준으로 서버가 다시 계산).

  int get _roomPriceEstimate {
    if (_bookingMode == ReservationMode.stay) {
      return _stay.priceForNights(_nightsClamped);
    }
    if (_bookingMode == ReservationMode.package) {
      return (_selectedPackage?['price'] as num?)?.toInt() ?? 0;
    }
    if (_startMinutes == null || _durationMinutes == null) return 0;
    return (_pricePerHour * _durationMinutes! / 60).round();
  }

  int get _partyFeeEstimate {
    final party = _partyData;
    if (party == null) return 0;
    // 미리보기 금액. 확정 금액은 서버(createPendingPackageBooking)가 같은
    // 규칙으로 다시 계산한다.
    final baseFee = PartyPricing.fromMap(party).priceFor(UserSession.gender);
    return EarlyBird.effectivePrice(baseFee, party);
  }

  int get _totalEstimate => _roomPriceEstimate + _partyFeeEstimate;

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );

  // ── 제출 ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    // 파티 회차 = 숙박 날짜다. 고를 회차가 여럿인데 안 골랐으면 여기서 멈춘다
    // (하나뿐이면 _load에서 이미 정해져 있어 이 분기에 걸리지 않는다).
    if (_occurrences.isNotEmpty && _selectedOccurrence == null) {
      _msg('참가할 파티 날짜를 선택해주세요');
      return;
    }
    if (_rooms.isNotEmpty && _selectedRoom == null) {
      _msg('숙박 객실을 선택해주세요');
      return;
    }
    if (_bookingMode == ReservationMode.package && _selectedPackage == null) {
      _msg('패키지를 선택해주세요');
      return;
    }
    if (_bookingMode == ReservationMode.hourly &&
        (_startMinutes == null || _durationMinutes == null)) {
      _msg('이용 시간을 선택해주세요');
      return;
    }
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      _msg('예약자 이름과 연락처를 입력해주세요');
      return;
    }

    // ── 결제수단 ──────────────────────────────────────────────────────────
    // 무통장입금·현장결제만 실제로 고를 수 있다(PG 수단은 '준비중' 표시).
    // 여기서 고르는 건 **수단뿐**이고, 금액(방 요금 + 파티 참가비)과 결제 상태는
    // 서버가 파티 정원을 선점하면서 다시 계산한다.
    PaymentInfo? payment;
    if (_totalEstimate > 0) {
      payment = await Navigator.push<PaymentInfo>(
        context,
        webFramedRoute(
          (_) => PaymentMethodScreen(
            summary: PaymentOrderSummary.placeRental(
              placeName: _placeData?['name'] as String? ?? '숙박',
              useText: '${_partyData?['title'] ?? '파티'} · $_peopleCount명',
              roomText: _selectedRoom?['roomName'] as String? ?? '숙박+파티 패키지',
              amount: _totalEstimate,
            ),
            defaultDepositorName: name,
            // 돈을 받는 사람 = 이 숙소(장소)의 호스트.
            hostId: _placeData?['hostId'] as String? ?? '',
          ),
        ),
      );
      if (payment == null || !mounted) return;
    }

    setState(() {
      _isSubmitting = true;
      _submitStatus = '예약 확인 중...';
    });

    try {
      final payload = <String, dynamic>{
        if (payment != null) 'payment': payment.toMap(),
        'placeId': widget.placeId,
        if (_selectedRoom != null) 'roomId': _selectedRoom!['id'],
        'partyId': widget.partyId,
        // 참가 회차 — 서버가 저장된 정기 일정으로 **다시 계산해서** 실제로
        // 열리는 회차인지 검증한다(이 값을 그대로 믿지 않는다).
        'occurrenceId': ?_selectedOccurrence?.id,
        'bookingType': _bookingMode.key,
        'peopleCount': _peopleCount,
        'requesterName': name,
        'requesterPhone': phone,
        'requestMessage': _requestCtrl.text.trim(),
        if (_bookingMode == ReservationMode.stay) 'nights': _nightsClamped,
        if (_bookingMode == ReservationMode.package)
          'packageId': _selectedPackage!['id'],
        if (_bookingMode == ReservationMode.hourly)
          'ranges': [
            {'start': _startMinutes, 'end': _startMinutes! + _durationMinutes!},
          ],
      };

      final createCallable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('createPendingPackageBooking');
      final createResult = await createCallable.call<Map<Object?, Object?>>(
        payload,
      );
      final resultData = createResult.data;
      final totalPrice = (resultData['totalPrice'] as num).toInt();
      final status = PlaceRentalStatus.fromKey(resultData['status'] as String?);
      final paymentStatus = PaymentStatus.fromKey(
        resultData['paymentStatus'] as String?,
      );

      // 결제창(PG)이 없다 — 서버가 방 시간과 파티 자리를 이미 함께 잡고
      // 승인 여부·결제 상태까지 정해 돌려줬으므로 그대로 안내하면 끝이다.
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitStatus = '';
      });

      final awaitingApproval = status == PlaceRentalStatus.requested;
      final body = awaitingApproval
          ? '업주가 승인하면 알림으로 알려드려요. 승인된 뒤에 입금 안내가 나가요.\n'
                '진행 상황은 마이페이지 > 내 패키지 예약에서 볼 수 있어요.'
          : totalPrice <= 0
          ? '무료 예약이라 결제 없이 확정됐어요.'
          : paymentStatus == PaymentStatus.awaitingDeposit
          ? '기한 안에 입금하시면 숙박과 파티 자리가 그대로 유지돼요.\n'
                '계좌와 입금기한은 마이페이지 > 내 패키지 예약에서 확인할 수 있어요.'
          : '이용 당일 현장에서 결제하시면 돼요.';

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: PartyChuColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(awaitingApproval ? '예약을 신청했어요' : '예약이 확정됐어요'),
              ),
            ],
          ),
          content: Text(body, style: const TextStyle(height: 1.5)),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: PartyChuColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitStatus = '';
      });
      _msg(e.message ?? '예약 중 오류가 발생했어요.');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitStatus = '';
      });
      _msg('예약 중 오류가 발생했어요.');
    }
  }

  // ── 빌드 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          appBar: AppBar(
            title: const Text('숙박+파티 패키지 예약'),
            centerTitle: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
          ),
          body: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: PartyChuColors.primary,
                  ),
                )
              : _loadError != null
              ? Center(
                  child: Text(
                    _loadError!,
                    style: const TextStyle(color: Colors.black45),
                  ),
                )
              : _buildContent(),
        ),
        if (_isSubmitting)
          IgnorePointer(
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 20),
                  Text(
                    _submitStatus,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContent() {
    final party = _partyData!;
    final place = _placeData!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PartyChuCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                place['name'] as String? ?? '',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                party['title'] as String? ?? '',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Text(
                '일정 : ${PartyCard.formatDate(party)}',
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 참가 회차 = 숙박 날짜. 정기 파티는 회차가 여럿이라 결제 전에 고른다.
        // **고를 것이 하나뿐이면 이 영역 자체를 그리지 않는다** — 선택지가
        // 하나인 화면을 한 번 더 거치게 만들 이유가 없고, _load에서 이미
        // 그 회차로 정해져 있다.
        if (_occurrences.length > 1) ...[
          _sectionTitle('참가할 파티 날짜'),
          const SizedBox(height: 4),
          const Text(
            '고른 날짜의 파티에 참가하고, 숙박도 그 날짜로 잡혀요.',
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _occurrences.map((o) {
              return _chip(
                _occurrenceLabel(o),
                selected: _selectedOccurrence?.id == o.id,
                onTap: () => setState(() => _selectedOccurrence = o),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
        if (_rooms.length > 1) ...[
          _sectionTitle('객실 선택'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _rooms.map((r) {
              final selected =
                  _selectedRoom != null && _selectedRoom!['id'] == r['id'];
              return _chip(
                r['roomName'] as String? ?? '객실',
                selected: selected,
                onTap: () => setState(() {
                  _selectedRoom = r;
                  _selectedPackage = null;
                  _startMinutes = null;
                  _durationMinutes = null;
                  // 객실마다 받는 예약 방식이 다르므로 함께 초기화한다.
                  _bookingMode = _defaultMode;
                  _nights = _stay.minNights;
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
        if (_modes.length > 1) ...[
          _sectionTitle('예약 방식'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _modes
                .map(
                  (m) => _chip(
                    m.chipLabel,
                    selected: _bookingMode == m,
                    onTap: () => setState(() {
                      _bookingMode = m;
                      _selectedPackage = null;
                      _startMinutes = null;
                      _durationMinutes = null;
                      _nights = _stay.minNights;
                    }),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
        ],
        if (_bookingMode == ReservationMode.stay) ...[
          _sectionTitle('숙박 기간'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _stay
                .nightOptions(fallbackMax: 7)
                .map(
                  (n) => _chip(
                    '$n박',
                    selected: _nightsClamped == n,
                    onTap: () => setState(() => _nights = n),
                  ),
                )
                .toList(),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '체크인 ${_stay.checkInTime} · 체크아웃 ${_stay.checkOutTime}',
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ),
          const SizedBox(height: 16),
        ] else if (_bookingMode == ReservationMode.package) ...[
          _sectionTitle('패키지 선택'),
          const SizedBox(height: 8),
          if (_availablePackages.isEmpty)
            const Text(
              '선택 가능한 패키지가 없어요.',
              style: TextStyle(color: Colors.black45),
            )
          else
            Column(
              children: _availablePackages.map((p) {
                final selected =
                    _selectedPackage != null &&
                    _selectedPackage!['id'] == p['id'];
                return _packageTile(p, selected);
              }).toList(),
            ),
          const SizedBox(height: 16),
        ] else ...[
          _sectionTitle('이용 시간'),
          const SizedBox(height: 8),
          Text(
            '시작 시간',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _startOptions.map((m) {
              return _chip(
                _fmtMinutes(m),
                selected: _startMinutes == m,
                onTap: () => setState(() {
                  _startMinutes = m;
                  _durationMinutes = null;
                }),
              );
            }).toList(),
          ),
          if (_startMinutes != null) ...[
            const SizedBox(height: 14),
            const Text(
              '이용 시간(분)',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _durationOptions.map((d) {
                return _chip(
                  '${d ~/ 60}시간${d % 60 > 0 ? ' ${d % 60}분' : ''}',
                  selected: _durationMinutes == d,
                  onTap: () => setState(() => _durationMinutes = d),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 16),
        ],
        _sectionTitle('인원'),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 4),
          child: Text(
            '기준 $_baseCapacity인 / 최대 $_capacity인',
            style: const TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              onPressed: _peopleCount > 1
                  ? () => setState(() => _peopleCount--)
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text(
              '$_peopleCount명',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            IconButton(
              onPressed: _peopleCount < _capacity
                  ? () => setState(() => _peopleCount++)
                  : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionTitle('예약자 정보'),
        const SizedBox(height: 8),
        TextField(controller: _nameCtrl, decoration: _inputDeco('예약자 이름')),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: _inputDeco('연락처 (예: 010-1234-5678)'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _requestCtrl,
          maxLines: 2,
          decoration: _inputDeco('호스트에게 전달할 요청사항 (선택)'),
        ),
        const SizedBox(height: 20),
        PartyChuCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _priceRow('숙박 예상 금액', _roomPriceEstimate),
              const SizedBox(height: 4),
              _priceRow('파티 참가비(예상)', _partyFeeEstimate),
              const Divider(height: 20),
              _priceRow('합계(예상)', _totalEstimate, emphasize: true),
              const SizedBox(height: 6),
              const Text(
                '실제 결제 금액은 다음 화면(결제 확인) 및 결제창에서 최종 확정돼요.',
                style: TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: PartyChuColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            child: const Text('결제하고 예약 확정하기'),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _packageTile(Map<String, dynamic> p, bool selected) {
    final start = p['startTime'] as String? ?? '';
    final end = p['endTime'] as String? ?? '';
    final price = (p['price'] as num?)?.toInt() ?? 0;
    return GestureDetector(
      onTap: () => setState(() => _selectedPackage = p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF0F5) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? PartyChuColors.primary : const Color(0xFFEAEAEA),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['name'] as String? ?? '패키지',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (start.isNotEmpty && end.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '$start ~ $end',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              formatPrice(price),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: PartyChuColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceRow(String label, int amount, {bool emphasize = false}) {
    final style = TextStyle(
      fontSize: emphasize ? 16 : 13,
      fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
      color: emphasize ? PartyChuColors.primary : Colors.black87,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: style.copyWith(
            color: emphasize ? PartyChuColors.primary : Colors.black54,
          ),
        ),
        Text(formatPrice(amount), style: style),
      ],
    );
  }

  /// '8월 15일(금)' — 회차 칩에 쓰는 짧은 표기.
  static String _occurrenceLabel(PartyOccurrence o) {
    const week = ['월', '화', '수', '목', '금', '토', '일'];
    return '${o.start.month}월 ${o.start.day}일(${week[o.start.weekday - 1]})';
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
  );

  Widget _chip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFF3EFFA) : const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? PartyChuColors.primary : const Color(0xFFDDE1EC),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: selected ? PartyChuColors.primary : Colors.black54,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    ),
  );

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF7F7FA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}
