import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:party_app/screens/portone_checkout_screen.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 숙박+파티 패키지 예약 — `places.packageBookingEnabled == true`인 콤보에서만
/// 진입하는 통합 예약/결제 화면. 방(또는 패키지) + 인원 + 예약자 정보를
/// 입력받아 createPendingPackageBooking → (결제 필요 시 PortOne 체크아웃) →
/// verifyAndConfirmPackageBooking 순서로 방 예약과 파티 참가 신청을 하나의
/// 결제로 함께 확정한다.
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

  String _bookingType = 'hourly'; // 'hourly' | 'package'
  Map<String, dynamic>? _selectedPackage;
  int? _startMinutes;
  int? _durationMinutes;
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
      final placeSnap =
          await FirebaseFirestore.instance.collection('places').doc(widget.placeId).get();
      final partySnap =
          await FirebaseFirestore.instance.collection('parties').doc(widget.partyId).get();
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

      if (!mounted) return;
      setState(() {
        _placeData = placeSnap.data();
        _partyData = partySnap.data();
        _rooms = rooms;
        _selectedRoom = rooms.length == 1 ? rooms.first : null;
        _bookingType = _reservationMode == 'hourly' ? 'hourly' : 'package';
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

  Map<String, dynamic> get _activeData => _selectedRoom ?? _placeData ?? const {};

  List<Map<String, dynamic>> get _packages =>
      ((_activeData['packages'] as List?) ?? [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .where((p) => p['isActive'] != false)
          .toList();

  String get _reservationMode =>
      _activeData['reservationMode'] as String? ??
      (_packages.isNotEmpty ? 'package' : 'hourly');

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

  int get _unitMinutes => (_activeData['bookingUnitMinutes'] as num?)?.toInt() ?? 60;

  int get _minBookingMinutes {
    final v = (_activeData['minBookingMinutes'] as num?)?.toInt();
    if (v != null) return v;
    return ((_activeData['minHours'] as num?)?.toInt() ?? 1) * 60;
  }

  int? get _maxBookingMinutes => (_activeData['maxBookingMinutes'] as num?)?.toInt();

  DateTime? get _partyDateTime {
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
    for (var m = _openMinutes; m + _minBookingMinutes <= _closeMinutes; m += _unitMinutes) {
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
    if (_bookingType == 'package') {
      return (_selectedPackage?['price'] as num?)?.toInt() ?? 0;
    }
    if (_startMinutes == null || _durationMinutes == null) return 0;
    return (_pricePerHour * _durationMinutes! / 60).round();
  }

  int get _partyFeeEstimate {
    final party = _partyData;
    if (party == null) return 0;
    final gender = UserSession.gender;
    int baseFee;
    if (gender == 'male' && party['maleFee'] != null) {
      baseFee = (party['maleFee'] as num).toInt();
    } else if (gender == 'female' && party['femaleFee'] != null) {
      baseFee = (party['femaleFee'] as num).toInt();
    } else {
      baseFee = ((party['maleFee'] ?? party['femaleFee']) as num?)?.toInt() ?? 0;
    }
    return EarlyBird.effectivePrice(baseFee, party);
  }

  int get _totalEstimate => _roomPriceEstimate + _partyFeeEstimate;

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );

  // ── 제출 ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_rooms.isNotEmpty && _selectedRoom == null) {
      _msg('숙박 객실을 선택해주세요');
      return;
    }
    if (_bookingType == 'package' && _selectedPackage == null) {
      _msg('패키지를 선택해주세요');
      return;
    }
    if (_bookingType == 'hourly' && (_startMinutes == null || _durationMinutes == null)) {
      _msg('이용 시간을 선택해주세요');
      return;
    }
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      _msg('예약자 이름과 연락처를 입력해주세요');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitStatus = '예약 확인 중...';
    });

    String? bundleBookingId;
    try {
      final payload = <String, dynamic>{
        'placeId': widget.placeId,
        if (_selectedRoom != null) 'roomId': _selectedRoom!['id'],
        'partyId': widget.partyId,
        'bookingType': _bookingType,
        'peopleCount': _peopleCount,
        'requesterName': name,
        'requesterPhone': phone,
        'requestMessage': _requestCtrl.text.trim(),
        if (_bookingType == 'package') 'packageId': _selectedPackage!['id'],
        if (_bookingType == 'hourly')
          'ranges': [
            {'start': _startMinutes, 'end': _startMinutes! + _durationMinutes!},
          ],
      };

      final createCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('createPendingPackageBooking');
      final createResult = await createCallable.call<Map<Object?, Object?>>(payload);
      final resultData = createResult.data;
      bundleBookingId = resultData['bundleBookingId'] as String;
      final totalPrice = (resultData['totalPrice'] as num).toInt();

      if (totalPrice > 0) {
        setState(() => _submitStatus = '');
        if (!mounted) return;
        final paid = await Navigator.push<bool>(
          context,
          webFramedRoute((_) => PortoneCheckoutScreen(
              paymentId: bundleBookingId!,
              orderName: '숙박+파티 패키지',
              amount: totalPrice,
              buyerName: name,
              buyerPhone: phone,
            ),
            fullscreenDialog: true,
          ),
        );
        if (paid != true) {
          await _cancelPending(bundleBookingId);
          if (!mounted) return;
          setState(() {
            _isSubmitting = false;
            _submitStatus = '';
          });
          _msg('결제가 완료되지 않아 예약이 취소됐어요.');
          return;
        }
        setState(() => _submitStatus = '예약 확정 중...');
      }

      final verifyCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('verifyAndConfirmPackageBooking');
      await verifyCallable.call<Map<Object?, Object?>>({'bundleBookingId': bundleBookingId});

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitStatus = '';
      });
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: PartyChuColors.primary),
              SizedBox(width: 8),
              Text('예약 완료'),
            ],
          ),
          content: const Text(
            '숙박+파티 패키지 예약이 확정됐어요.\n마이페이지에서 확인할 수 있어요.',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: PartyChuColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  Future<void> _cancelPending(String bundleBookingId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('cancelPackageBooking');
      await callable.call<Map<Object?, Object?>>({'bundleBookingId': bundleBookingId});
    } catch (_) {
      // 결제가 애초에 실패/취소된 흐름이므로 이 취소 호출 실패는 조용히
      // 무시한다 — expireStalePackageBookings가 10분 뒤 자동으로 정리한다.
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
              ? const Center(child: CircularProgressIndicator(color: PartyChuColors.primary))
              : _loadError != null
                  ? Center(child: Text(_loadError!, style: const TextStyle(color: Colors.black45)))
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
                  Text(_submitStatus, style: const TextStyle(fontSize: 14, color: Colors.white)),
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
              Text(place['name'] as String? ?? '',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(party['title'] as String? ?? '',
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 8),
              Text('일정 : ${PartyCard.formatDate(party)}',
                  style: const TextStyle(fontSize: 13, color: Colors.black87)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_rooms.length > 1) ...[
          _sectionTitle('객실 선택'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _rooms.map((r) {
              final selected = _selectedRoom != null && _selectedRoom!['id'] == r['id'];
              return _chip(
                r['roomName'] as String? ?? '객실',
                selected: selected,
                onTap: () => setState(() {
                  _selectedRoom = r;
                  _selectedPackage = null;
                  _startMinutes = null;
                  _durationMinutes = null;
                  _bookingType = _reservationMode == 'hourly' ? 'hourly' : 'package';
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
        if (_reservationMode == 'both') ...[
          _sectionTitle('예약 방식'),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip('시간제', selected: _bookingType == 'hourly',
                  onTap: () => setState(() => _bookingType = 'hourly')),
              const SizedBox(width: 8),
              _chip('패키지', selected: _bookingType == 'package',
                  onTap: () => setState(() => _bookingType = 'package')),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (_bookingType == 'package') ...[
          _sectionTitle('패키지 선택'),
          const SizedBox(height: 8),
          if (_availablePackages.isEmpty)
            const Text('선택 가능한 패키지가 없어요.', style: TextStyle(color: Colors.black45))
          else
            Column(
              children: _availablePackages.map((p) {
                final selected = _selectedPackage != null && _selectedPackage!['id'] == p['id'];
                return _packageTile(p, selected);
              }).toList(),
            ),
          const SizedBox(height: 16),
        ] else ...[
          _sectionTitle('이용 시간'),
          const SizedBox(height: 8),
          Text('시작 시간', style: const TextStyle(fontSize: 13, color: Colors.black54)),
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
            const Text('이용 시간(분)', style: TextStyle(fontSize: 13, color: Colors.black54)),
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
              onPressed: _peopleCount > 1 ? () => setState(() => _peopleCount--) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$_peopleCount명', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            IconButton(
              onPressed: _peopleCount < _capacity ? () => setState(() => _peopleCount++) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionTitle('예약자 정보'),
        const SizedBox(height: 8),
        TextField(
          controller: _nameCtrl,
          decoration: _inputDeco('예약자 이름'),
        ),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                  Text(p['name'] as String? ?? '패키지',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  if (start.isNotEmpty && end.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('$start ~ $end', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ],
              ),
            ),
            Text(formatPrice(price),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: PartyChuColors.primary)),
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
        Text(label, style: style.copyWith(color: emphasize ? PartyChuColors.primary : Colors.black54)),
        Text(formatPrice(amount), style: style),
      ],
    );
  }

  Widget _sectionTitle(String text) =>
      Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold));

  Widget _chip(String label, {required bool selected, required VoidCallback onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF3EFFA) : const Color(0xFFF7F7FA),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? PartyChuColors.primary : const Color(0xFFDDE1EC)),
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
