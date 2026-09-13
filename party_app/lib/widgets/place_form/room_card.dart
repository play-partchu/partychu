import 'package:party_app/models/payment_policy.dart';
import 'package:party_app/widgets/payment_policy_section.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:party_app/models/place_rental_reservation.dart';
import 'package:party_app/models/reservation_modes.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/widgets/place_form/package_list_editor.dart';
import 'package:party_app/widgets/refund_policy_editor.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 장소대여 객실(룸) 편집 카드 — 등록 화면(place_register_screen.dart)과 수정
// 화면(place_edit_screen.dart)이 공유하는 위젯. roomId/initialData가 있으면
// 기존 룸을 그대로 불러와 수정 가능하고, 없으면 신규 룸으로 동작한다.
// ─────────────────────────────────────────────────────────────────────────────

class RoomCard extends StatefulWidget {
  final int index;
  final VoidCallback onRemove;
  final Map<String, dynamic>? Function()? getPreviousData;

  /// 기존 룸이면 그 문서 ID, 신규 룸이면 null. 저장 시 이 값의 유무로
  /// update(기존)/add(신규)를 구분한다.
  final String? roomId;

  /// 기존 룸 문서 데이터(Firestore 저장 형식) — 있으면 이 값으로 모든
  /// 입력값을 초기화한다.
  final Map<String, dynamic>? initialData;

  const RoomCard({
    super.key,
    required this.index,
    required this.onRemove,
    this.getPreviousData,
    this.roomId,
    this.initialData,
  });

  @override
  State<RoomCard> createState() => RoomCardState();
}

class RoomCardState extends State<RoomCard> {
  bool _expanded = true;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _capacityMinCtrl = TextEditingController(text: '1');
  final _capacityMaxCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  // 환불 규정 — 파티 등록과 동일한 구조(RefundTier 구간 목록). 기존 자유
  // 입력(cancelPolicy 문자열)을 대체한다. 옛 문서에 refundPolicy가 없고
  // cancelPolicy 문자열만 있으면 안내용으로만 보관한다(_legacyCancelPolicy).
  List<RefundTier> _refundTiers = [];
  String? _legacyCancelPolicy;

  final List<XFile> _images = [];
  // 기존(이미 업로드되어 있던) 룸 사진 URL — 신규 파일(_images)과 구분해서
  // 관리하고, 둘 다 미리보기 그리드에서 삭제할 수 있다.
  final List<String> _existingImages = [];
  final _picker = ImagePicker();
  final Set<String> _availableDays = {};
  final Set<String> _facilities = {};
  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;
  bool _isOpen24Hours = false;
  int _bookingUnitMinutes = 60;
  int _minBookingMinutes = 60;
  int? _maxBookingMinutes;
  bool _isActive = true;

  // ── 예약 방식 (복수 선택) ────────────────────────────────────────────────
  // 숙박 / 시간제 / 패키지를 동시에 켤 수 있고, 켠 방식의 입력 섹션만 펼쳐
  // 진다. 기존 룸(필드 자체가 없음)은 이미 시간제 필드만 쓰고 있었으므로
  // parseReservationModes가 시간제로 해석한다.
  Set<ReservationMode> _modes = {ReservationMode.hourly};
  final List<PlacePackageDraft> _packages = [];
  bool _showPackageError = false;
  bool _showPackageIncompleteError = false;

  bool get _hasStay => _modes.contains(ReservationMode.stay);
  bool get _hasHourly => _modes.contains(ReservationMode.hourly);
  bool get _hasPackage => _modes.contains(ReservationMode.package);

  // ── 승인 방식 ────────────────────────────────────────────────────────────
  // 설정한 적 없는 기존 룸은 자동승인이다 — 지금까지 장소대여에는 승인 단계가
  // 아예 없었으므로 그 동작을 그대로 지킨다.
  RoomApprovalMode _approvalMode = RoomApprovalMode.auto;

  /// 결제 방식 — null이면 필드를 남기지 않아 기존 룸과 똑같이 동작한다
  /// (예약자가 무통장입금·현장결제를 자유롭게 선택, 금액은 전액).
  PaymentPolicy? _paymentPolicy;

  // ── 숙박(1박) ────────────────────────────────────────────────────────────
  final _stayPriceCtrl = TextEditingController();
  TimeOfDay _checkInTime = const TimeOfDay(hour: 16, minute: 0);
  TimeOfDay _checkOutTime = const TimeOfDay(hour: 11, minute: 0);
  int _minNights = 1;
  int? _maxNights;
  bool _showStayPriceError = false;

  // 룸 편의시설 직접 입력
  final Set<String> _customFacilities = {};
  final _customFacilityCtrl = TextEditingController();
  // build마다 새로 만들면 포커스가 끊기므로 State가 하나만 들고 있는다.
  final _customFacilityFocus = FocusNode(debugLabel: 'room-facility-input');
  bool _showCustomFacilityInput = false;

  // 추가 옵션 (옵션명 + 추가 금액)
  final List<TextEditingController> _optionNameCtrls = [];
  final List<TextEditingController> _optionPriceCtrls = [];

  bool _showNameError = false;
  // 환불 규정 최소 1개 — 파티와 **같은 규칙**([RefundPolicyRule])을 쓴다.
  // 옛 룸(구간 없이 저장된 문서)도 화면 진입은 그대로 되고 저장에서만 막힌다.
  bool _showRefundError = false;
  bool _showCapacityError = false;
  bool _showPriceError = false;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  static const List<int> _unitOptions = [30, 60, 120, 180, 240, 1440];
  static const List<String> _unitLabels = [
    '30분',
    '1시간',
    '2시간',
    '3시간',
    '4시간',
    '하루',
  ];
  static const List<int> _minOptions = [30, 60, 120, 180, 240, 1440];
  static const List<String> _minLabels = [
    '30분 이상',
    '1시간 이상',
    '2시간 이상',
    '3시간 이상',
    '4시간 이상',
    '하루 이상',
  ];
  static const _facilityOptions = [
    '에어컨',
    '냉장고',
    '마이크',
    '빔프로젝터',
    '스피커',
    'TV',
    '조명',
    '음향장비',
    '드레스룸',
    '파티용품',
    '케이터링',
    '테이블/의자',
  ];

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    if (d == null) return;

    _nameCtrl.text = d['roomName'] as String? ?? '';
    _descCtrl.text = d['roomDescription'] as String? ?? '';
    _capacityMinCtrl.text = ((d['capacityMin'] as num?)?.toInt() ?? 1)
        .toString();
    _capacityMaxCtrl.text = ((d['capacityMax'] as num?)?.toInt() ?? 0)
        .toString();
    _priceCtrl.text = ((d['pricePerHour'] as num?)?.toInt() ?? 0).toString();
    _refundTiers = RefundTier.listFromDynamic(d['refundPolicy']);
    // 구 스키마(자유 입력) 문서 하위호환 — 구조화된 refundPolicy가 없을 때만
    // 옛 cancelPolicy 문자열을 안내용으로 보관한다.
    if (_refundTiers.isEmpty) {
      final legacy = d['cancelPolicy'] as String?;
      if (legacy != null && legacy.trim().isNotEmpty) {
        _legacyCancelPolicy = legacy.trim();
      }
    }
    _existingImages.addAll((d['roomImages'] as List?)?.cast<String>() ?? []);
    _availableDays.addAll((d['availableDays'] as List?)?.cast<String>() ?? []);

    // 저장 시 프리셋+커스텀 편의시설을 한 리스트로 합쳐서 저장하므로, 불러올
    // 때는 프리셋 목록에 있는지 여부로 다시 나눈다.
    final loadedFacilities = (d['facilities'] as List?)?.cast<String>() ?? [];
    for (final f in loadedFacilities) {
      if (_facilityOptions.contains(f)) {
        _facilities.add(f);
      } else {
        _customFacilities.add(f);
      }
    }

    _bookingUnitMinutes = (d['bookingUnitMinutes'] as num?)?.toInt() ?? 60;
    _minBookingMinutes = (d['minBookingMinutes'] as num?)?.toInt() ?? 60;
    _maxBookingMinutes = (d['maxBookingMinutes'] as num?)?.toInt();

    final loadedPackages = (d['packages'] as List?) ?? [];
    _packages.addAll(
      loadedPackages.map(
        (p) => PlacePackageDraft.fromMap(Map<String, dynamic>.from(p as Map)),
      ),
    );
    _modes = parseReservationModes(d);
    _approvalMode = RoomApprovalMode.of(d);
    _paymentPolicy = PaymentPolicy.fromMap(d);

    final stay = StayConfig.fromMap(d);
    _stayPriceCtrl.text = stay.pricePerNight == 0
        ? ''
        : stay.pricePerNight.toString();
    _checkInTime = _timeOfDay(stay.checkInMinutes);
    _checkOutTime = _timeOfDay(stay.checkOutMinutes);
    _minNights = stay.minNights;
    _maxNights = stay.maxNights;

    _isOpen24Hours = d['isOpen24Hours'] as bool? ?? false;
    if (!_isOpen24Hours) {
      _openTime = _parseTimeString(d['openTime'] as String?);
      _closeTime = _parseTimeString(d['closeTime'] as String?);
    }
    _isActive = d['isActive'] as bool? ?? true;

    final opts = (d['options'] as List?) ?? [];
    for (final o in opts) {
      final m = o as Map;
      _optionNameCtrls.add(
        TextEditingController(text: m['name'] as String? ?? ''),
      );
      _optionPriceCtrls.add(
        TextEditingController(text: (m['price'])?.toString() ?? ''),
      );
    }
  }

  static TimeOfDay _timeOfDay(int minutes) =>
      TimeOfDay(hour: (minutes ~/ 60) % 24, minute: minutes % 60);

  TimeOfDay? _parseTimeString(String? hhmm) {
    if (hhmm == null || !hhmm.contains(':')) return null;
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    if (h >= 24) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _capacityMinCtrl.dispose();
    _capacityMaxCtrl.dispose();
    _priceCtrl.dispose();
    _stayPriceCtrl.dispose();
    _customFacilityCtrl.dispose();
    _customFacilityFocus.dispose();
    for (final c in _optionNameCtrls) {
      c.dispose();
    }
    for (final c in _optionPriceCtrls) {
      c.dispose();
    }
    for (final p in _packages) {
      p.dispose();
    }
    super.dispose();
  }

  /// 기준인원/최대 수용 가능 인원 검증 오류 메시지(정상이면 null).
  /// 기준인원은 비워두면 1로 간주한다(컨트롤러 기본값 '1').
  String? _capacityErrorText() {
    final maxText = _capacityMaxCtrl.text.trim();
    if (maxText.isEmpty) return '최대 수용 가능 인원을 입력해주세요';
    final minVal = int.tryParse(_capacityMinCtrl.text.trim()) ?? 1;
    final maxVal = int.tryParse(maxText) ?? 0;
    if (maxVal < minVal) {
      return '최대 수용 가능 인원은 기준인원($minVal명)보다 작을 수 없어요';
    }
    return null;
  }

  // 부모가 저장 전 유효성 검사 시 호출
  bool validate() {
    bool ok = true;
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _showNameError = true);
      ok = false;
    }
    if (_capacityErrorText() != null) {
      setState(() => _showCapacityError = true);
      ok = false;
    }
    if (_hasStay && _stayPriceCtrl.text.trim().isEmpty) {
      setState(() => _showStayPriceError = true);
      ok = false;
    }
    if (_hasHourly && _priceCtrl.text.trim().isEmpty) {
      setState(() => _showPriceError = true);
      ok = false;
    }
    if (_hasPackage && _packages.isEmpty) {
      setState(() => _showPackageError = true);
      ok = false;
    }
    if (RefundPolicyRule.isMissing(_refundTiers)) {
      setState(() => _showRefundError = true);
      ok = false;
    }
    if (_hasPackage &&
        _packages.isNotEmpty &&
        _packages.any(
          (p) =>
              p.nameCtrl.text.trim().isEmpty ||
              p.startTime == null ||
              p.endTime == null,
        )) {
      setState(() => _showPackageIncompleteError = true);
      ok = false;
    }
    if (!ok) setState(() => _expanded = true);
    return ok;
  }

  /// 결제 방식 계산 예시에 쓸 기준 금액 — 숙박을 받으면 1박 요금, 아니면
  /// 시간당 요금을 쓴다. 실제 예약금은 예약 당시 최종 이용요금(숙박일수·
  /// 옵션 포함)으로 서버가 다시 계산하므로 여기 값은 어디까지나 예시다.
  int? _sampleTotalForPreview() {
    final stay = int.tryParse(_stayPriceCtrl.text.trim()) ?? 0;
    if (_hasStay && stay > 0) return stay;
    final hourly = int.tryParse(_priceCtrl.text.trim()) ?? 0;
    return hourly > 0 ? hourly : null;
  }

  /// 예약 방식 + 숙박 설정 필드 — 저장/임시저장/룸 복사가 모두 같은 형태를
  /// 쓰도록 한곳에서 만든다. `reservationMode`(단수)는 아직 업데이트되지 않은
  /// 앱을 위한 하위호환 미러다.
  Map<String, dynamic> _reservationFields() => {
    'reservationModes': reservationModeKeys(_modes),
    'reservationMode': legacyReservationMode(_modes),
    // 승인 방식 — 서버(placeReservationFlow.js)가 같은 키를 읽어 "승인 전에는
    // 입금을 요구하지 않는다"를 판단한다.
    'reservationApprovalMode': _approvalMode.key,
    // 결제 방식 — 설정했을 때만 남긴다. 없으면 서버가 기존 동작을 태운다.
    if (_paymentPolicy != null) ..._paymentPolicy!.toMap(),
    ...StayConfig(
      pricePerNight: int.tryParse(_stayPriceCtrl.text.trim()) ?? 0,
      checkInTime: _fmtTime(_checkInTime),
      checkOutTime: _fmtTime(_checkOutTime),
      minNights: _minNights,
      maxNights: _maxNights,
    ).toMap(),
  };

  // 부모가 저장 시 호출: 이미지 업로드 후 룸 데이터 맵 반환
  Future<Map<String, dynamic>> uploadAndGetData(
    String uid,
    String placeId,
  ) async {
    final newRoomImageUrls = <String>[];
    for (final img in _images) {
      newRoomImageUrls.add(await CloudflareService.uploadImage(img));
    }
    final roomImageUrls = [..._existingImages, ...newRoomImageUrls];
    return {
      'placeId': placeId,
      'hostId': uid,
      'roomName': _nameCtrl.text.trim(),
      'roomDescription': _descCtrl.text.trim(),
      'roomImages': roomImageUrls,
      'capacityMin': int.tryParse(_capacityMinCtrl.text.trim()) ?? 1,
      'capacityMax': int.tryParse(_capacityMaxCtrl.text.trim()) ?? 0,
      'pricePerHour': int.tryParse(_priceCtrl.text.trim()) ?? 0,
      ..._reservationFields(),
      'bookingUnitMinutes': _bookingUnitMinutes,
      'minBookingMinutes': _minBookingMinutes,
      'maxBookingMinutes': _maxBookingMinutes,
      'packages': [
        for (int i = 0; i < _packages.length; i++) _packages[i].toMap(i),
      ],
      'availableDays': _availableDays.toList(),
      'isOpen24Hours': _isOpen24Hours,
      if (_isOpen24Hours) ...{
        'openTime': '00:00',
        'closeTime': '24:00',
      } else ...{
        if (_openTime != null) 'openTime': _fmtTime(_openTime!),
        if (_closeTime != null) 'closeTime': _fmtTime(_closeTime!),
      },
      'facilities': {..._facilities, ..._customFacilities}.toList(),
      'options': [
        for (int i = 0; i < _optionNameCtrls.length; i++)
          if (_optionNameCtrls[i].text.trim().isNotEmpty)
            {
              'name': _optionNameCtrls[i].text.trim(),
              'price': int.tryParse(_optionPriceCtrls[i].text.trim()) ?? 0,
            },
      ],
      'refundPolicy': RefundTier.listToMaps(_refundTiers),
      'isActive': _isActive,
      // 신규 룸(roomId == null)일 때만 createdAt을 새로 찍는다 — 기존 룸을
      // 수정할 때는 이 키 자체를 넣지 않아 update() 호출 시 원래 생성 시각이
      // 그대로 보존된다.
      if (widget.roomId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// 임시저장용 — 업로드 없이 현재 룸 상태를 [initialData]와 같은 Firestore
  /// 형태의 순수 JSON 맵으로 반환한다. 아직 업로드되지 않은 새 로컬 사진
  /// (_images)은 담지 못하므로 기존 URL(_existingImages)만 넣고, 새 로컬
  /// 사진이 있었으면 `_hasUnsavedImages: true`로 알려 호출측이 "다시 선택"
  /// 안내를 띄우게 한다(이 키는 initialData 복원 시 무시된다).
  Map<String, dynamic> getDraftData() => {
    'roomName': _nameCtrl.text,
    'roomDescription': _descCtrl.text,
    'roomImages': [..._existingImages],
    '_hasUnsavedImages': _images.isNotEmpty,
    'capacityMin': int.tryParse(_capacityMinCtrl.text.trim()) ?? 1,
    'capacityMax': int.tryParse(_capacityMaxCtrl.text.trim()) ?? 0,
    'pricePerHour': int.tryParse(_priceCtrl.text.trim()) ?? 0,
    ..._reservationFields(),
    'bookingUnitMinutes': _bookingUnitMinutes,
    'minBookingMinutes': _minBookingMinutes,
    'maxBookingMinutes': _maxBookingMinutes,
    'packages': [
      for (int i = 0; i < _packages.length; i++) _packages[i].toMap(i),
    ],
    'availableDays': _availableDays.toList(),
    'isOpen24Hours': _isOpen24Hours,
    if (!_isOpen24Hours) ...{
      if (_openTime != null) 'openTime': _fmtTime(_openTime!),
      if (_closeTime != null) 'closeTime': _fmtTime(_closeTime!),
    } else ...{
      'openTime': '00:00',
      'closeTime': '24:00',
    },
    'facilities': {..._facilities, ..._customFacilities}.toList(),
    'options': [
      for (int i = 0; i < _optionNameCtrls.length; i++)
        {
          'name': _optionNameCtrls[i].text,
          'price': int.tryParse(_optionPriceCtrls[i].text.trim()) ?? 0,
        },
    ],
    'refundPolicy': RefundTier.listToMaps(_refundTiers),
    'isActive': _isActive,
  };

  // ── 헬퍼 ─────────────────────────────────────────────────────────────────

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtTimeDisplay(TimeOfDay t) {
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    if (h == 0) return '오전 12:$m';
    if (h < 12) return '오전 $h:$m';
    if (h == 12) return '오후 12:$m';
    return '오후 ${h - 12}:$m';
  }

  // 직전 룸 내용 복사용 — 현재 상태를 맵으로 반환
  Map<String, dynamic> getRoomData() => {
    'desc': _descCtrl.text,
    'capacityMin': _capacityMinCtrl.text,
    'capacityMax': _capacityMaxCtrl.text,
    'price': _priceCtrl.text,
    'stayPrice': _stayPriceCtrl.text,
    ..._reservationFields(),
    'bookingUnitMinutes': _bookingUnitMinutes,
    'minBookingMinutes': _minBookingMinutes,
    'maxBookingMinutes': _maxBookingMinutes,
    // packages는 컨트롤러를 직접 공유하면 두 룸이 같은 객체를 수정하게
    // 되므로, Firestore와 같은 맵 형태로 스냅샷만 떠서 넘긴다 —
    // applyFromData에서 PlacePackageDraft.fromMap으로 새로 만든다.
    'packages': [
      for (int i = 0; i < _packages.length; i++) _packages[i].toMap(i),
    ],
    'availableDays': Set<String>.from(_availableDays),
    'facilities': Set<String>.from(_facilities),
    'customFacilities': Set<String>.from(_customFacilities),
    'openTime': _openTime,
    'closeTime': _closeTime,
    'isOpen24Hours': _isOpen24Hours,
    'refundPolicy': RefundTier.listToMaps(_refundTiers),
    'options': [
      for (int i = 0; i < _optionNameCtrls.length; i++)
        {'name': _optionNameCtrls[i].text, 'price': _optionPriceCtrls[i].text},
    ],
  };

  // 직전 룸 데이터를 현재 폼에 적용
  void applyFromData(Map<String, dynamic> data) {
    setState(() {
      _descCtrl.text = data['desc'] as String? ?? '';
      _capacityMinCtrl.text = data['capacityMin'] as String? ?? '1';
      _capacityMaxCtrl.text = data['capacityMax'] as String? ?? '';
      _priceCtrl.text = data['price'] as String? ?? '';
      _stayPriceCtrl.text = data['stayPrice'] as String? ?? '';
      _modes = parseReservationModes(data);
      _approvalMode = RoomApprovalMode.of(data);
      _paymentPolicy = PaymentPolicy.fromMap(data);
      final stay = StayConfig.fromMap(data);
      _checkInTime = _timeOfDay(stay.checkInMinutes);
      _checkOutTime = _timeOfDay(stay.checkOutMinutes);
      _minNights = stay.minNights;
      _maxNights = stay.maxNights;
      _bookingUnitMinutes = data['bookingUnitMinutes'] as int? ?? 60;
      _minBookingMinutes = data['minBookingMinutes'] as int? ?? 60;
      _maxBookingMinutes = data['maxBookingMinutes'] as int?;
      for (final p in _packages) {
        p.dispose();
      }
      _packages.clear();
      final pkgs = data['packages'] as List? ?? [];
      for (final p in pkgs) {
        _packages.add(
          PlacePackageDraft.fromMap(Map<String, dynamic>.from(p as Map)),
        );
      }
      _showPackageError = false;
      _availableDays
        ..clear()
        ..addAll((data['availableDays'] as Set<String>? ?? {}));
      _facilities
        ..clear()
        ..addAll((data['facilities'] as Set<String>? ?? {}));
      _customFacilities
        ..clear()
        ..addAll((data['customFacilities'] as Set<String>? ?? {}));
      _openTime = data['openTime'] as TimeOfDay?;
      _closeTime = data['closeTime'] as TimeOfDay?;
      _isOpen24Hours = data['isOpen24Hours'] as bool? ?? false;
      _refundTiers = RefundTier.listFromDynamic(data['refundPolicy']);
      // 옵션 복사
      for (final c in _optionNameCtrls) {
        c.dispose();
      }
      for (final c in _optionPriceCtrls) {
        c.dispose();
      }
      _optionNameCtrls.clear();
      _optionPriceCtrls.clear();
      final opts = data['options'] as List? ?? [];
      for (final o in opts) {
        final m = o as Map;
        _optionNameCtrls.add(
          TextEditingController(text: m['name'] as String? ?? ''),
        );
        _optionPriceCtrls.add(
          TextEditingController(text: m['price'] as String? ?? ''),
        );
      }
      _showNameError = _showCapacityError = _showPriceError = false;
      _showStayPriceError = false;
      _showRefundError = false;
    });
  }

  void _addOption() {
    setState(() {
      _optionNameCtrls.add(TextEditingController());
      _optionPriceCtrls.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    setState(() {
      _optionNameCtrls.removeAt(index).dispose();
      _optionPriceCtrls.removeAt(index).dispose();
    });
  }

  void _openRoomCustomFacility() {
    setState(() => _showCustomFacilityInput = true);
    // autofocus 대신 한 번만 요청한다 — autofocus는 rebuild마다 다시 걸려
    // 포커스/키보드가 깜빡이는 원인이 된다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showCustomFacilityInput) {
        _customFacilityFocus.requestFocus();
      }
    });
  }

  /// 입력칸을 닫는다. 순서가 중요하다 — **먼저 포커스를 놓고** 트리에서
  /// 없앤다. 포커스를 가진 채로 사라지면 Flutter가 스코프의 직전 포커스
  /// 대상(보통 화면 위쪽 입력칸)으로 포커스를 되돌리고, 그 입력칸이
  /// showOnScreen()을 부르면서 등록 화면이 위로 튀어 오른다.
  void _closeRoomCustomFacility() {
    _customFacilityFocus.unfocus(); // 기본 scope 처분 — 포커스 이력까지 비운다
    _customFacilityCtrl.clear();
    setState(() => _showCustomFacilityInput = false);
  }

  void _addRoomCustomFacility() {
    final text = _customFacilityCtrl.text.trim();
    if (text.isEmpty) {
      _closeRoomCustomFacility();
      return;
    }
    // 프리셋에 있는 이름이면 프리셋 선택으로 처리하고, 이미 추가된 항목이면
    // 중복 추가하지 않는다.
    if (_facilityOptions.contains(text)) {
      _facilities.add(text);
    } else if (!_customFacilities.contains(text)) {
      _customFacilities.add(text);
    }
    _closeRoomCustomFacility();
  }

  Widget _roomCustomChip(String label, {required VoidCallback onDelete}) =>
      Container(
        padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF3EFFA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF7C5CBF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF7C5CBF),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: onDelete,
              child: const Icon(
                Icons.close,
                size: 14,
                color: Color(0xFF7C5CBF),
              ),
            ),
          ],
        ),
      );

  // ── 예약 방식 토글 ────────────────────────────────────────────────────────

  static const List<int> _nightOptions = [1, 2, 3, 5, 7, 14, 30];

  /// 예약 방식 칩 토글. 마지막 하나는 끌 수 없다 — 예약 방식이 하나도 없는
  /// 룸은 아무도 예약할 수 없어서 저장할 이유가 없기 때문.
  void _toggleMode(ReservationMode mode) {
    if (_modes.contains(mode)) {
      if (_modes.length == 1) return;
      setState(() => _modes = {..._modes}..remove(mode));
    } else {
      setState(() => _modes = {..._modes, mode});
    }
  }

  Future<void> _pickStayTime(bool isCheckIn) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isCheckIn ? _checkInTime : _checkOutTime,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF7C5CBF)),
          ),
          child: child!,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isCheckIn) {
        _checkInTime = picked;
      } else {
        _checkOutTime = picked;
      }
    });
  }

  Widget _stayTimePicker({required bool isCheckIn}) {
    final time = isCheckIn ? _checkInTime : _checkOutTime;
    return GestureDetector(
      onTap: () => _pickStayTime(isCheckIn),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF3EFFA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF7C5CBF).withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isCheckIn ? '체크인' : '체크아웃',
                  style: const TextStyle(fontSize: 11, color: Colors.black38),
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtTimeDisplay(time),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7C5CBF),
                  ),
                ),
              ],
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 20,
              color: Color(0xFF7C5CBF),
            ),
          ],
        ),
      ),
    );
  }

  bool _isMinValid(int m) {
    if (_bookingUnitMinutes == 1440) return m == 1440;
    return m >= _bookingUnitMinutes && m % _bookingUnitMinutes == 0;
  }

  void _onUnitChanged(int newUnit) {
    setState(() {
      _bookingUnitMinutes = newUnit;
      if (newUnit == 1440) {
        _minBookingMinutes = 1440;
      } else if (!_isMinValid(_minBookingMinutes)) {
        _minBookingMinutes = _minOptions.firstWhere(
          (m) => m >= newUnit && m % newUnit == 0,
          orElse: () => newUnit,
        );
      }
    });
  }

  Future<void> _pickImages() async {
    final total = _existingImages.length + _images.length;
    final picked = await _picker.pickMultiImage(limit: 10 - total);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (_existingImages.length + _images.length < 10) _images.add(f);
      }
    });
  }

  Future<void> _pickTime(bool isOpen) async {
    final current = isOpen ? _openTime : _closeTime;
    final picked = await showTimePicker(
      context: context,
      initialTime:
          current ??
          (isOpen
              ? const TimeOfDay(hour: 9, minute: 0)
              : const TimeOfDay(hour: 23, minute: 0)),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF7C5CBF)),
          ),
          child: child!,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isOpen) {
        _openTime = picked;
      } else {
        _closeTime = picked;
      }
    });
  }

  // ── 빌드 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EBF2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 헤더 (탭으로 접기/펼치기)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C5CBF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${widget.index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _nameCtrl.text.trim().isEmpty
                          ? '룸 ${widget.index + 1}'
                          : _nameCtrl.text.trim(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onRemove,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.black38,
                  ),
                ],
              ),
            ),
          ),

          if (_expanded) ...[
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: _buildRoomForm(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoomForm() {
    final hasPrev = widget.getPreviousData != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 이전 룸 내용 복사 버튼 (룸2 이상일 때만 표시) ──────────────────
        if (hasPrev) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              final prev = widget.getPreviousData!();
              if (prev != null) applyFromData(prev);
            },
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: Text('룸${widget.index} 내용 불러오기'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF7C5CBF),
              side: const BorderSide(color: Color(0xFF7C5CBF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        _label('룸 이름 *'),
        TextField(
          controller: _nameCtrl,
          onChanged: (_) => setState(() => _showNameError = false),
          decoration: _inputDeco('예: VIP 룸, 루프탑, 1번 룸').copyWith(
            errorText: _showNameError ? '룸 이름을 입력해주세요' : null,
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
          ),
        ),
        _label('룸 설명'),
        TextField(
          controller: _descCtrl,
          maxLines: 3,
          decoration: _inputDeco('룸의 특징, 분위기, 포함 물품을 소개해주세요'),
        ),
        _label('룸 사진 (최대 10장)'),
        _buildRoomPhotos(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('기준인원 *'),
                  TextField(
                    controller: _capacityMinCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) =>
                        setState(() => _showCapacityError = false),
                    decoration: _inputDeco('예: 2'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('최대 수용 가능 인원 *'),
                  TextField(
                    controller: _capacityMaxCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) =>
                        setState(() => _showCapacityError = false),
                    decoration: _inputDeco('예: 4'),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_showCapacityError && _capacityErrorText() != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              _capacityErrorText()!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        _label('예약 방식 * (복수 선택 가능)'),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            '이 룸이 받을 예약 방식을 모두 골라주세요. 선택한 방식의 요금 입력만 아래에 나타납니다.',
            style: TextStyle(fontSize: 12, color: Colors.black38, height: 1.4),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in ReservationMode.values)
              _chip(
                label: mode.chipLabel,
                selected: _modes.contains(mode),
                enabled: true,
                onTap: () => _toggleMode(mode),
                selectedColor: const Color(0xFF7C5CBF),
              ),
          ],
        ),
        _label('예약 승인 방식 *'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${_approvalMode.description}. 어느 쪽이든 승인 전에는 입금을 요구하지 않고, '
            '입금기한이 지나면 예약이 자동 취소되면서 그 시간이 다시 열려요.',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black38,
              height: 1.4,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in RoomApprovalMode.values)
              _chip(
                label: mode.label,
                selected: _approvalMode == mode,
                enabled: true,
                onTap: () => setState(() => _approvalMode = mode),
                selectedColor: const Color(0xFF7C5CBF),
              ),
          ],
        ),
        // ── 결제 방식 ────────────────────────────────────────────────
        // 숙박·시간제 모두 예약 시점에 최종 이용요금이 확정되므로 비율
        // 예약금까지 전부 쓸 수 있다(totalKnown: true).
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: PaymentPolicySection.modes(
            policy: _paymentPolicy ?? PaymentPolicy.initial,
            sampleTotal: _sampleTotalForPreview(),
            totalKnown: true,
            modes: const [
              PaymentMode.prepaid,
              PaymentMode.partial,
              PaymentMode.onsite,
            ],
            accent: const Color(0xFF7C5CBF),
            description:
                '이용요금을 언제 받을지 정해요. 비율 예약금은 숙박일수·옵션이 모두 반영된 '
                '최종 이용요금을 기준으로 계산돼요.',
            onChanged: (v) => setState(() => _paymentPolicy = v),
          ),
        ),
        if (_hasStay) ...[
          _label('1박 요금 (원) *'),
          TextField(
            controller: _stayPriceCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() => _showStayPriceError = false),
            decoration: _inputDeco('예: 120000').copyWith(
              errorText: _showStayPriceError ? '1박 요금을 입력해주세요' : null,
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.redAccent),
              ),
            ),
          ),
          _label('체크인 / 체크아웃'),
          Row(
            children: [
              Expanded(child: _stayTimePicker(isCheckIn: true)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('~', style: TextStyle(fontSize: 16)),
              ),
              Expanded(child: _stayTimePicker(isCheckIn: false)),
            ],
          ),
          _label('최소 숙박일'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              _nightOptions.length,
              (i) => _chip(
                label: '${_nightOptions[i]}박 이상',
                selected: _minNights == _nightOptions[i],
                enabled: true,
                onTap: () => setState(() {
                  _minNights = _nightOptions[i];
                  // 최대가 최소보다 작아지면 함께 끌어올린다.
                  if (_maxNights != null && _maxNights! < _minNights) {
                    _maxNights = _minNights;
                  }
                }),
                selectedColor: const Color(0xFFFF6FA0),
              ),
            ),
          ),
          _label('최대 숙박일'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                label: '제한 없음',
                selected: _maxNights == null,
                enabled: true,
                onTap: () => setState(() => _maxNights = null),
                selectedColor: const Color(0xFFFF6FA0),
              ),
              ...List.generate(_nightOptions.length, (i) {
                final n = _nightOptions[i];
                return _chip(
                  label: '$n박',
                  selected: _maxNights == n,
                  enabled: n >= _minNights,
                  onTap: n >= _minNights
                      ? () => setState(() => _maxNights = n)
                      : null,
                  selectedColor: const Color(0xFFFF6FA0),
                );
              }),
            ],
          ),
        ],
        if (_hasHourly) ...[
          _label('시간당 가격 (원) *'),
          TextField(
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() => _showPriceError = false),
            decoration: _inputDeco('예: 50000').copyWith(
              errorText: _showPriceError ? '가격을 입력해주세요' : null,
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.redAccent),
              ),
            ),
          ),
          _label('예약 시간 단위'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              _unitOptions.length,
              (i) => _chip(
                label: _unitLabels[i],
                selected: _bookingUnitMinutes == _unitOptions[i],
                enabled: true,
                onTap: () => _onUnitChanged(_unitOptions[i]),
                selectedColor: const Color(0xFF7C5CBF),
              ),
            ),
          ),
          _label('최소 예약 시간'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_minOptions.length, (i) {
              final valid = _isMinValid(_minOptions[i]);
              return _chip(
                label: _minLabels[i],
                selected: _minBookingMinutes == _minOptions[i],
                enabled: valid,
                onTap: valid
                    ? () => setState(() => _minBookingMinutes = _minOptions[i])
                    : null,
                selectedColor: const Color(0xFFFF6FA0),
              );
            }),
          ),
          _label('최대 예약 시간'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                label: '제한 없음',
                selected: _maxBookingMinutes == null,
                enabled: true,
                onTap: () => setState(() => _maxBookingMinutes = null),
                selectedColor: const Color(0xFFFF6FA0),
              ),
              ...List.generate(_minOptions.length, (i) {
                final valid = _isMinValid(_minOptions[i]);
                return _chip(
                  label: _minLabels[i].replaceAll(' 이상', ''),
                  selected: _maxBookingMinutes == _minOptions[i],
                  enabled: valid,
                  onTap: valid
                      ? () =>
                            setState(() => _maxBookingMinutes = _minOptions[i])
                      : null,
                  selectedColor: const Color(0xFFFF6FA0),
                );
              }),
            ],
          ),
        ],
        if (_hasPackage) ...[
          _label('패키지 관리 *'),
          if (_showPackageError)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '패키지를 하나 이상 추가해주세요',
                style: TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ),
          if (_showPackageIncompleteError)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '각 패키지의 이름과 시작/종료 시간을 입력해주세요',
                style: TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ),
          PackageListEditor(
            packages: _packages,
            onChanged: () => setState(() {
              _showPackageError = false;
              _showPackageIncompleteError = false;
            }),
          ),
        ],
        _label('운영 요일'),
        Builder(
          builder: (context) {
            final isAllDays = _weekdays.every(_availableDays.contains);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => setState(() {
                    if (isAllDays) {
                      _availableDays.clear();
                    } else {
                      _availableDays
                        ..clear()
                        ..addAll(_weekdays);
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isAllDays
                          ? const Color(0xFF7C5CBF)
                          : const Color(0xFFF7F7FA),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isAllDays
                            ? const Color(0xFF7C5CBF)
                            : const Color(0xFFDDE1EC),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isAllDays) ...[
                          const Icon(
                            Icons.check,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          '연중무휴',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isAllDays ? Colors.white : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _weekdays.map((day) {
                    final selected = _availableDays.contains(day);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (selected) {
                          _availableDays.remove(day);
                        } else {
                          _availableDays.add(day);
                        }
                      }),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? const Color(0xFF7C5CBF)
                              : const Color(0xFFF7F7FA),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF7C5CBF)
                                : const Color(0xFFDDE1EC),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            day,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: selected ? Colors.white : Colors.black54,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            );
          },
        ),
        if (_hasHourly) ...[
          _label('룸별 운영 시간 (선택)'),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '미입력 시 장소 기본 운영 시간이 적용됩니다.',
              style: TextStyle(fontSize: 12, color: Colors.black38),
            ),
          ),
          Row(
            children: [
              Checkbox(
                value: _isOpen24Hours,
                onChanged: (v) => setState(() => _isOpen24Hours = v ?? false),
                activeColor: const Color(0xFF7C5CBF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Text(
                '24시간 운영',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          if (!_isOpen24Hours)
            Row(
              children: [
                Expanded(child: _timePicker(isOpen: true)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('~', style: TextStyle(fontSize: 16)),
                ),
                Expanded(child: _timePicker(isOpen: false)),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3EFFA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: Color(0xFF7C5CBF)),
                  SizedBox(width: 8),
                  Text(
                    '오전 12:00 ~ 자정 (24:00)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF7C5CBF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
        _label('편의시설'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // 프리셋 편의시설 칩
            ..._facilityOptions.map((f) {
              final selected = _facilities.contains(f);
              return GestureDetector(
                onTap: () => setState(() {
                  if (selected) {
                    _facilities.remove(f);
                  } else {
                    _facilities.add(f);
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFF3EFFA)
                        : const Color(0xFFF7F7FA),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF7C5CBF)
                          : const Color(0xFFDDE1EC),
                    ),
                  ),
                  child: Text(
                    f,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected
                          ? const Color(0xFF7C5CBF)
                          : Colors.black54,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }),
            // 직접 입력한 편의시설 칩 (삭제 버튼 포함)
            ..._customFacilities.map(
              (f) => _roomCustomChip(
                f,
                onDelete: () => setState(() => _customFacilities.remove(f)),
              ),
            ),
            // + 직접 입력 버튼
            GestureDetector(
              onTap: _openRoomCustomFacility,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7FA),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFDDE1EC)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 13, color: Colors.black45),
                    SizedBox(width: 3),
                    Text(
                      '직접 입력',
                      style: TextStyle(fontSize: 12, color: Colors.black45),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // 인라인 입력 필드
        if (_showCustomFacilityInput) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customFacilityCtrl,
                  focusNode: _customFacilityFocus,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: '편의시설 이름 입력 (예: 노래방 기계, 보드게임)',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: Colors.black38,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFDDE1EC)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF7C5CBF)),
                    ),
                  ),
                  onSubmitted: (_) => _addRoomCustomFacility(),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _addRoomCustomFacility,
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF7C5CBF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('추가', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.black38),
                onPressed: _closeRoomCustomFacility,
                tooltip: '취소',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ],
        _label('추가 옵션'),
        if (_optionNameCtrls.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '등록자가 원하는 옵션을 자유롭게 추가할 수 있어요.',
              style: const TextStyle(fontSize: 12, color: Colors.black38),
            ),
          ),
        ...List.generate(
          _optionNameCtrls.length,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: _optionNameCtrls[i],
                    textInputAction: TextInputAction.next,
                    decoration: _inputDeco('옵션명 (예: 바베큐 이용)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: TextField(
                    controller: _optionPriceCtrls[i],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.done,
                    decoration: _inputDeco('추가 금액 (원)'),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _removeOption(i),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.remove_circle_outline,
                      size: 20,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: _addOption,
          child: Container(
            margin: const EdgeInsets.only(top: 4, bottom: 4),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDDE1EC)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 15, color: Colors.black45),
                SizedBox(width: 4),
                Text(
                  '옵션 추가',
                  style: TextStyle(fontSize: 13, color: Colors.black45),
                ),
              ],
            ),
          ),
        ),
        _label('환불 규정 *'),
        _buildRefundPolicyRow(),
        if (_showRefundError) ...[
          const SizedBox(height: 6),
          const Text(
            RefundPolicyRule.requiredMessage,
            style: TextStyle(fontSize: 12, color: Color(0xFFE53935)),
          ),
        ],
        if (_legacyCancelPolicy != null && _refundTiers.isEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '이전 안내: $_legacyCancelPolicy\n(구간을 추가하면 위 안내는 대체됩니다)',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black38,
              height: 1.4,
            ),
          ),
        ],
        _label('예약 가능 여부'),
        Row(
          children: [
            Switch(
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              activeThumbColor: const Color(0xFFFF6FA0),
              activeTrackColor: const Color(0xFFFFB8D0),
            ),
            const SizedBox(width: 8),
            Text(
              _isActive ? '예약 가능' : '예약 불가',
              style: TextStyle(
                fontSize: 14,
                color: _isActive ? const Color(0xFFFF6FA0) : Colors.black45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRoomPhotos() {
    final total = _existingImages.length + _images.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 0) ...[
          SizedBox(
            height: 104,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: total,
              itemBuilder: (_, i) {
                final isExisting = i < _existingImages.length;
                final ImageProvider image = isExisting
                    ? NetworkImage(_existingImages[i])
                    : LocalMedia.imageProvider(
                        _images[i - _existingImages.length],
                      );
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        image: DecorationImage(image: image, fit: BoxFit.cover),
                      ),
                    ),
                    if (i == 0)
                      Positioned(
                        bottom: 4,
                        left: 0,
                        right: 8,
                        child: Container(
                          color: Colors.black45,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: const Text(
                            '대표',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ),
                      ),
                    Positioned(
                      top: -4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          if (isExisting) {
                            _existingImages.removeAt(i);
                          } else {
                            _images.removeAt(i - _existingImages.length);
                          }
                        }),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: total < 10 ? _pickImages : null,
          icon: const Icon(Icons.add_a_photo_outlined, size: 18),
          label: Text('사진 추가 ($total/10)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF7C5CBF),
            side: const BorderSide(color: Color(0xFF7C5CBF)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _timePicker({required bool isOpen}) {
    if (_isOpen24Hours) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF3EFFA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isOpen ? '시작 시간' : '종료 시간',
              style: const TextStyle(fontSize: 11, color: Colors.black38),
            ),
            const SizedBox(height: 2),
            Text(
              isOpen ? '오전 12:00' : '자정 (24:00)',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF7C5CBF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    final time = isOpen ? _openTime : _closeTime;
    final hasTime = time != null;
    return GestureDetector(
      onTap: () => _pickTime(isOpen),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hasTime ? const Color(0xFFF3EFFA) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: hasTime
              ? Border.all(
                  color: const Color(0xFF7C5CBF).withValues(alpha: 0.4),
                )
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isOpen ? '시작 시간' : '종료 시간',
                  style: const TextStyle(fontSize: 11, color: Colors.black38),
                ),
                const SizedBox(height: 2),
                Text(
                  hasTime ? _fmtTimeDisplay(time) : '선택하세요',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: hasTime ? FontWeight.w600 : FontWeight.normal,
                    color: hasTime ? const Color(0xFF7C5CBF) : Colors.black38,
                  ),
                ),
              ],
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 20,
              color: hasTime ? const Color(0xFF7C5CBF) : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback? onTap,
    required Color selectedColor,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: !enabled
              ? const Color(0xFFEEEEEE)
              : selected
              ? selectedColor
              : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: !enabled
                ? const Color(0xFFDDDDDD)
                : selected
                ? selectedColor
                : const Color(0xFFDDE1EC),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: !enabled
                ? Colors.black26
                : selected
                ? Colors.white
                : Colors.black87,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // 파티 등록과 동일한 환불 규정 컴포넌트(RefundPolicyEditor)를 그대로
  // 재사용한다 — 요약 행을 누르면 시트에서 구간(N일 전 → X% 환불)을 편집한다.
  Widget _buildRefundPolicyRow() {
    return InkWell(
      onTap: _openRefundPolicy,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _showRefundError
                ? const Color(0xFFE53935)
                : const Color(0xFFE0E0E0),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                RefundPolicyRule.summaryLabel(_refundTiers) ?? '환불 규정 설정 (필수)',
                style: TextStyle(
                  fontSize: 14,
                  color: RefundPolicyRule.isMissing(_refundTiers)
                      ? Colors.black38
                      : Colors.black87,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.black38),
          ],
        ),
      ),
    );
  }

  Future<void> _openRefundPolicy() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final media = MediaQuery.of(sheetCtx);
        final keyboard = media.viewInsets.bottom;
        // 키보드가 가린 높이를 뺀 "실제로 보이는 영역" 안에서만 시트를 그린다.
        // 시트에 높이를 고정해줘야 안쪽 목록이 스크롤 가능한 뷰포트를 갖고,
        // 구간을 아무리 추가해도 시트가 화면 밖으로 밀려나지 않는다.
        final available = media.size.height - media.padding.top - keyboard;
        return Padding(
          // 키보드 위로 시트 전체를 밀어 올린다.
          padding: EdgeInsets.only(bottom: keyboard),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: available * 0.9,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
                    child: Text(
                      '환불 규정',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    // 위에서 이미 키보드 높이만큼 올렸으므로, 에디터가 아래
                    // 여백을 한 번 더 넣지 않도록 인셋을 지워서 넘긴다.
                    child: MediaQuery.removeViewInsets(
                      context: sheetCtx,
                      removeBottom: true,
                      child: RefundPolicyEditor(
                        initialTiers: _refundTiers,
                        introText:
                            'PartyChu는 환불률을 정하거나 권장하지 않습니다. 이용(체크인) 기준 '
                            '며칠 전부터 몇 %를 환불할지 직접 구간을 등록해주세요. 예약자는 예약 전 '
                            '이 규정을 확인할 수 있어요.',
                        onChanged: (tiers) => setState(() {
                          _refundTiers = tiers;
                          // 채우자마자 오류 표시를 거둔다 — 저장을 다시 눌러야
                          // 풀리면 고쳤는데도 잘못된 것처럼 보인다.
                          if (RefundPolicyRule.isSatisfied(tiers)) {
                            _showRefundError = false;
                          }
                        }),
                        scrollable: true,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C5CBF),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('완료'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (mounted) setState(() {}); // 요약 문구 갱신
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 16),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
