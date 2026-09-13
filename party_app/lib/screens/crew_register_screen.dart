import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:party_app/models/address_result.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/models/crew_area.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/screens/address_search_screen.dart';
import 'package:party_app/services/media_upload_service.dart';
import 'package:party_app/services/content_delete_service.dart'
    show DeletableContent;
import 'package:party_app/models/draft_type.dart';
import 'package:party_app/utils/draftable_register.dart';
import 'package:party_app/utils/register_form_mode.dart';
import 'package:party_app/utils/register_return_signal.dart';
import 'package:party_app/utils/register_validation.dart';
import 'package:party_app/widgets/party_form/register_field_anchor.dart';
import 'package:party_app/widgets/party_form/register_missing_fields_banner.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/delete_content_action.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 파티크루(구인·구직) 폼의 **정본**.
///
/// 등록과 수정이 이 화면 하나를 공유한다. 파티크루는 원래 수정 화면이 아예
/// 없어서 한 번 올린 글을 고칠 수 없었다(모집 상태 토글과 삭제뿐이었다).
/// 수정 화면을 새로 만들면서, 파티·플레이스에서 겪은 "등록 화면을 복붙해
/// 수정 화면을 만들고 둘이 갈라지는" 문제를 처음부터 차단했다.
///
/// 모드가 바꾸는 것은 아래뿐이다.
///
///   1. 화면 제목·제출 버튼 문구 ([RegisterFormMode])
///   2. 진입 시 기존 문서를 불러오는지 / 임시저장을 쓰는지
///   3. 저장이 `add`인지 `update`인지
///   4. 수정에만 있는 삭제 버튼과, 완료 후 이동 방식
///
/// 정체성 필드(`hostId`/`hostName`/`createdAt`)는 수정에서 건드리지 않고,
/// `updatedAt`만 갱신한다.
class CrewRegisterScreen extends StatefulWidget {
  /// 등록인지 수정인지 — 자세한 계약은 [RegisterFormMode] 참고.
  final RegisterFormMode mode;

  /// 수정 모드에서 갱신할 `crews` 문서 id.
  final String? docId;

  /// 수정 모드에서 불러올 기존 문서.
  final Map<String, dynamic>? sourceData;

  /// 마이페이지 "임시저장" 목록에서 "이어서 작성"으로 열 때 true.
  final bool autoRestoreDraft;

  /// 구인/구직은 별도 임시저장이라, 목록에서 특정 유형을 이어서 작성할 때
  /// 그 유형('구인'/'구직')으로 시작하도록 지정한다.
  final String? initialCrewType;

  const CrewRegisterScreen({
    super.key,
    this.autoRestoreDraft = false,
    this.initialCrewType,
  }) : mode = RegisterFormMode.create,
       docId = null,
       sourceData = null;

  /// 파티크루 글 수정 진입 — 마이페이지 "내 파트너" 목록의 수정 버튼이 쓴다.
  const CrewRegisterScreen.edit({
    super.key,
    required String this.docId,
    required Map<String, dynamic> this.sourceData,
  }) : mode = RegisterFormMode.edit,
       autoRestoreDraft = false,
       initialCrewType = null;

  @override
  State<CrewRegisterScreen> createState() => _CrewRegisterScreenState();
}

class _CrewRegisterScreenState extends State<CrewRegisterScreen>
    with WidgetsBindingObserver, DraftableRegister<CrewRegisterScreen> {
  bool get _isEdit => widget.mode.isEdit;

  /// 수정 모드에서 불러온 원본 문서 — 등록 모드에서는 빈 맵이다.
  Map<String, dynamic> get _source => widget.sourceData ?? const {};

  @override
  void setState(VoidCallback fn) {
    // 수정 모드에서는 임시저장을 쓰지 않아 markDraftDirty가 아무 일도 하지
    // 않는다(autosaver가 없다). 두 모드가 같은 setState를 타도 안전하다.
    markDraftDirty();
    super.setState(fn);
  }

  // 구인/구직에 따라 임시저장 종류가 갈린다(사용자별·유형별 1개씩).
  @override
  DraftType get draftType =>
      _crewType == '구인' ? DraftType.crewRecruit : DraftType.crewSeek;

  @override
  bool get draftAutoRestore => widget.autoRestoreDraft;

  @override
  String get draftTitle => _titleCtrl.text;

  @override
  String? get draftCoverImageUrl => null;

  @override
  Map<String, dynamic> buildDraftPayload() {
    return <String, dynamic>{
      'crewType': _crewType,
      'recruitType': _recruitType,
      'startDateMs': _startDate?.millisecondsSinceEpoch,
      'endDateMs': _endDate?.millisecondsSinceEpoch,
      'startTime': DraftableRegister.timeToMap(_startTime),
      'endTime': DraftableRegister.timeToMap(_endTime),
      'title': _titleCtrl.text,
      'content': _contentCtrl.text,
      'role': _roleCtrl.text,
      'pay': _payCtrl.text,
      'autoMsg': _autoMsgCtrl.text,
      'recruitCount': _recruitCountCtrl.text,
      'detailAddress': _detailAddressCtrl.text,
      'selectedRoles': _selectedRoles.toList(),
      'beginnerFriendly': _beginnerFriendly,
      'experiencedPreferred': _experiencedPreferred,
      // "서울 강남구" / "서울 전체" 형태로 저장한다(광역만 담던 예전 키
      // selectedRegions는 아래 복원 쪽에서 계속 읽어준다).
      'selectedAreas': _selectedAreas.map((a) => a.label).toList(),
      'payType': _payType,
      'profileImagePath': _profileImage == null
          ? null
          : LocalMedia.remember(_profileImage!).path,
      'address': _selectedAddress == null
          ? null
          : {
              'placeName': _selectedAddress!.placeName,
              'address': _selectedAddress!.address,
              'roadAddress': _selectedAddress!.roadAddress,
              'jibunAddress': _selectedAddress!.jibunAddress,
              'latitude': _selectedAddress!.latitude,
              'longitude': _selectedAddress!.longitude,
            },
    };
  }

  @override
  void applyDraftPayload(Map<String, dynamic> p) {
    _crewType = p['crewType'] as String? ?? '구인';
    _recruitType = p['recruitType'] as String? ?? '항시';
    final sMs = (p['startDateMs'] as num?)?.toInt();
    final eMs = (p['endDateMs'] as num?)?.toInt();
    _startDate = sMs != null ? DateTime.fromMillisecondsSinceEpoch(sMs) : null;
    _endDate = eMs != null ? DateTime.fromMillisecondsSinceEpoch(eMs) : null;
    _startTime = DraftableRegister.timeFromMap(p['startTime']);
    _endTime = DraftableRegister.timeFromMap(p['endTime']);
    _titleCtrl.text = (p['title'] as String?) ?? '';
    _contentCtrl.text = (p['content'] as String?) ?? '';
    _roleCtrl.text = (p['role'] as String?) ?? '';
    _payCtrl.text = (p['pay'] as String?) ?? '';
    _autoMsgCtrl.text = (p['autoMsg'] as String?) ?? '';
    _recruitCountCtrl.text = (p['recruitCount'] as String?) ?? '';
    _detailAddressCtrl.text = (p['detailAddress'] as String?) ?? '';
    _selectedRoles
      ..clear()
      ..addAll((p['selectedRoles'] as List?)?.cast<String>() ?? const []);
    _beginnerFriendly = p['beginnerFriendly'] as bool? ?? false;
    _experiencedPreferred = p['experiencedPreferred'] as bool? ?? false;
    // 예전 임시저장(광역만 담긴 selectedRegions)도 그대로 복원된다 —
    // CrewArea.parse가 "서울"을 "서울 전체"로 읽는다.
    final draftAreas =
        (p['selectedAreas'] as List?) ?? (p['selectedRegions'] as List?);
    _setSelectedAreas(
      (draftAreas ?? const [])
          .whereType<String>()
          .map(CrewArea.parse)
          .whereType<CrewArea>(),
    );
    _payType = p['payType'] as String? ?? '협의';
    final addr = p['address'] as Map?;
    _selectedAddress = addr == null
        ? null
        : AddressResult(
            placeName: addr['placeName'] as String? ?? '',
            address: addr['address'] as String? ?? '',
            roadAddress: addr['roadAddress'] as String? ?? '',
            jibunAddress: addr['jibunAddress'] as String? ?? '',
            latitude: (addr['latitude'] as num?)?.toDouble() ?? 0,
            longitude: (addr['longitude'] as num?)?.toDouble() ?? 0,
          );
    final profilePath = p['profileImagePath'] as String?;
    if (profilePath != null) {
      if (LocalMedia.exists(profilePath)) {
        _profileImage = LocalMedia.resolve(profilePath);
      } else {
        draftMediaNeedsReselect = true;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialCrewType != null) {
      _crewType = widget.initialCrewType!;
    }
    for (final c in [
      _titleCtrl,
      _contentCtrl,
      _roleCtrl,
      _payCtrl,
      _autoMsgCtrl,
      _recruitCountCtrl,
      _detailAddressCtrl,
    ]) {
      c.addListener(markDraftDirty);
    }
    if (_isEdit) {
      _loadFromData(_source);
    } else {
      // 임시저장은 "빈 화면에서 새로 등록하는 경우"에만 동작한다 — 수정은 이미
      // 문서 내용을 불러온 상태라 임시저장이 그걸 덮어쓰는 사고만 생긴다.
      initDraft();
    }
  }

  /// 수정 모드 진입 — 기존 문서 값으로 폼을 채운다.
  ///
  /// 등록이 저장하는 필드를 **그대로 되읽는다**. 등록 폼에 항목이 추가되면
  /// 저장 코드도 한 곳뿐이라, 여기 한 줄만 따라 붙이면 수정에도 반영된다.
  void _loadFromData(Map<String, dynamic> d) {
    _crewType = d['crewType'] as String? ?? '구인';
    _recruitType = d['recruitType'] as String? ?? '항시';
    _titleCtrl.text = d['title'] as String? ?? '';
    _contentCtrl.text = d['content'] as String? ?? '';
    _autoMsgCtrl.text = d['autoMessage'] as String? ?? '';

    // 역할 — 저장은 프리셋 목록과 '기타' 직접 입력을 하나로 합쳐 두므로,
    // 되읽을 때 다시 갈라놓는다(프리셋에 없는 값 = 직접 입력한 역할).
    final roles = (d['roles'] as List?)?.cast<String>() ?? const <String>[];
    _selectedRoles.clear();
    for (final r in roles) {
      if (ListingConstants.crewRoles.contains(r)) {
        _selectedRoles.add(r);
      } else {
        _selectedRoles.add('기타');
        _roleCtrl.text = r;
      }
    }

    // regionAreas(신규) → regions/region(구버전) 순으로 읽는다 — 광역만
    // 저장돼 있던 옛 글도 "서울 전체"처럼 선택된 채로 열린다.
    _setSelectedAreas(CrewArea.fromCrewData(d));
    _payType = d['payType'] as String? ?? '협의';
    final payAmount = (d['payAmount'] as num?)?.toInt() ?? 0;
    if (payAmount > 0) _payCtrl.text = '$payAmount';
    final recruitCount = (d['recruitCount'] as num?)?.toInt() ?? 0;
    if (recruitCount > 0) _recruitCountCtrl.text = '$recruitCount';
    _beginnerFriendly = d['beginnerFriendly'] as bool? ?? false;
    _experiencedPreferred = d['experiencedPreferred'] as bool? ?? false;

    _startDate = (d['startDate'] as Timestamp?)?.toDate();
    _endDate = (d['endDate'] as Timestamp?)?.toDate();
    _startTime = _parseTime24(d['startTime'] as String?);
    _endTime = _parseTime24(d['endTime'] as String?);

    // 구인 전용: 주소
    final address = d['address'] as String? ?? '';
    if (address.isNotEmpty) {
      _selectedAddress = AddressResult(
        placeName: '',
        address: address,
        roadAddress: d['roadAddress'] as String? ?? address,
        jibunAddress: d['jibunAddress'] as String? ?? '',
        latitude: (d['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (d['longitude'] as num?)?.toDouble() ?? 0.0,
      );
    }
    _detailAddressCtrl.text = d['detailAddress'] as String? ?? '';

    // 구직 전용: 프로필 사진 — 이미 올라간 URL은 파일이 아니라 URL로 들고
    // 있다가, 사용자가 새로 고르거나 지우지 않으면 그대로 유지한다.
    final profileUrl = d['profileImageUrl'] as String?;
    _existingProfileImageUrl = (profileUrl == null || profileUrl.isEmpty)
        ? null
        : profileUrl;
  }

  TimeOfDay? _parseTime24(String? hhmm) {
    if (hhmm == null || !hhmm.contains(':')) return null;
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h >= 24) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  // ── 글 유형 / 모집 기간 ────────────────────────────────────────────
  String _crewType = '구인';
  String _recruitType = '항시';

  // ── 날짜 ─────────────────────────────────────────────────────────
  DateTime? _startDate;
  DateTime? _endDate;

  // ── 시간 ─────────────────────────────────────────────────────────
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  // ── 텍스트 입력 ──────────────────────────────────────────────────
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();

  // 필수항목 안내는 다른 등록 화면과 **같은 공용 구조**를 쓴다 —
  // 화면마다 따로 스크롤·강조 로직을 만들지 않기 위해서다
  // ([RegisterFieldCheck] / [RegisterFieldAnchor]).
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _titleKey = GlobalKey();
  final GlobalKey _contentKey = GlobalKey();
  final GlobalKey _startDateKey = GlobalKey();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _contentFocus = FocusNode();
  List<RegisterFieldCheck> _missingFields = const [];
  final _roleCtrl = TextEditingController(); // '기타' 선택 시 직접 입력
  final _payCtrl = TextEditingController();
  final _autoMsgCtrl = TextEditingController(); // 구인 전용 자동 안내 문구
  final _recruitCountCtrl = TextEditingController();

  // ── 모집 역할 (다중 선택, 상세검색에서 필터링 가능) ─────────────────
  final Set<String> _selectedRoles = {};

  // ── 모집 조건 (상세검색 필터용) ─────────────────────────────────────
  bool _beginnerFriendly = false;
  bool _experiencedPreferred = false;

  // ── 구직 전용: 프로필 사진 ─────────────────────────────────────────
  // 새로 고른 로컬 파일과, 수정 모드에서 이미 올라가 있는 URL을 나란히 둔다.
  // 등록 모드에서는 URL 쪽이 항상 null이다.
  XFile? _profileImage;
  String? _existingProfileImageUrl;

  /// 화면에 보여줄 프로필 사진이 하나라도 있는지.
  bool get _hasProfileImage =>
      _profileImage != null || _existingProfileImageUrl != null;

  // ── 활동 지역 선택 (시/도 → 구/군, 최대 3개) ───────────────────────
  // 목록은 앱 공용 RegionData를 쓰는 CrewArea가 들고 있다(파티/장소 상세검색과
  // 같은 데이터). 고른 순서가 그대로 보이도록 Set이 아니라 List로 둔다.
  final List<CrewArea> _selectedAreas = [];

  /// 지역 선택 칩에서 지금 펼쳐 보고 있는 시/도.
  String _areaCity = CrewArea.regions.first;

  static const _maxAreas = 3;

  /// 불러온 값(수정 진입·임시저장 복원)으로 선택을 통째로 바꾼다.
  /// 이미 고른 지역이 있으면 그 시/도를 펼쳐 둬야 화면을 열자마자 무엇이
  /// 선택돼 있는지 보인다.
  void _setSelectedAreas(Iterable<CrewArea> areas) {
    _selectedAreas
      ..clear()
      ..addAll(areas.take(_maxAreas));
    if (_selectedAreas.isNotEmpty) {
      final first = _selectedAreas.first.region;
      if (CrewArea.regions.contains(first)) _areaCity = first;
    }
  }

  /// 구/군 칩 하나를 켜고 끈다. [district]가 null이면 '전체'.
  ///
  /// 같은 시/도 안에서 '전체'와 개별 구/군은 함께 고를 수 없다 — '전체'를
  /// 고르면 그 시/도의 개별 선택을 걷어내고, 개별 구/군을 고르면 '전체'를
  /// 뺀다(같은 지역을 두 번 저장하는 값을 만들지 않기 위해서다).
  void _toggleArea(String region, String? district) {
    final area = CrewArea(region, district);
    setState(() {
      if (_selectedAreas.contains(area)) {
        _selectedAreas.remove(area);
        return;
      }
      if (district == null) {
        _selectedAreas.removeWhere((a) => a.region == region);
      } else {
        _selectedAreas.removeWhere(
          (a) => a.region == region && a.isWholeRegion,
        );
      }
      if (_selectedAreas.length >= _maxAreas) return;
      _selectedAreas.add(area);
    });
  }

  // ── 구인 전용: 실제 주소 ──────────────────────────────────────────
  AddressResult? _selectedAddress;
  final _detailAddressCtrl = TextEditingController();

  // ── 급여/페이 ────────────────────────────────────────────────────
  String _payType = '협의';
  static const _payTypes = ['협의', '시급', '건당', '무료', '기타'];
  // 상세검색 "보수" 필터('유료'/'협의'/'무료')와 매핑: 협의·무료를 제외한 나머지는 모두 유료로 취급.

  bool _isSubmitting = false;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  void dispose() {
    disposeDraft();
    _scrollCtrl.dispose();
    _titleFocus.dispose();
    _contentFocus.dispose();
    // 이 화면을 떠나면 강조도 함께 끈다 — 타이머가 화면보다 오래 남지 않게.
    RegisterValidation.clearHighlight();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _roleCtrl.dispose();
    _payCtrl.dispose();
    _recruitCountCtrl.dispose();
    _autoMsgCtrl.dispose();
    _detailAddressCtrl.dispose();
    super.dispose();
  }

  // ── 프로필 사진 선택 (구직) ──────────────────────────────────────
  Future<void> _pickProfileImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) {
      return;
    }
    setState(() => _profileImage = picked);
  }

  // ── 날짜 선택 ─────────────────────────────────────────────────────
  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final first = isStart ? now : (_startDate ?? now);
    final init = isStart
        ? (_startDate ?? now)
        : (_endDate ?? first.add(const Duration(days: 1)));

    final picked = await showDatePicker(
      context: context,
      initialDate: init.isBefore(first) ? first : init,
      firstDate: first,
      lastDate: DateTime(now.year + 2),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFFFF6FA0)),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = null;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  // ── 시간 선택 ─────────────────────────────────────────────────────
  Future<void> _pickTime(bool isStart) async {
    final init = isStart
        ? (_startTime ?? const TimeOfDay(hour: 18, minute: 0))
        : (_endTime ?? const TimeOfDay(hour: 22, minute: 0));

    final picked = await showTimePicker(
      context: context,
      initialTime: init,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFF6FA0),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        ),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  // ── 포맷 헬퍼 ────────────────────────────────────────────────────
  String _fmtDate(DateTime d) {
    final w = _weekdays[d.weekday - 1];
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} ($w)';
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    if (h == 0) {
      return '오전 12:$m';
    }
    if (h < 12) {
      return '오전 $h:$m';
    }
    if (h == 12) {
      return '오후 12:$m';
    }
    return '오후 ${h - 12}:$m';
  }

  String _timeStr(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ── 제출 ─────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (UserSession.userId.isEmpty) {
      _msg('로그인이 필요합니다.');
      return;
    }
    // 필수값 검증 — 조건·문구는 그대로다. 안내만 다른 등록 화면과 같은
    // 공용 경로를 타서, 배너의 각 줄을 눌러도 그 입력칸으로 가게 한다.
    // 순서는 **화면에 보이는 순서**(모집 기간 → 제목 → 내용)다.
    final checks = [
      RegisterFieldCheck(
        missing: _recruitType == '날짜지정' && _startDate == null,
        message: '시작 날짜를 선택해주세요.',
        anchorKey: _startDateKey,
        scrollController: _scrollCtrl,
      ),
      RegisterFieldCheck(
        missing: _titleCtrl.text.trim().isEmpty,
        message: '제목을 입력해주세요.',
        anchorKey: _titleKey,
        focusNode: _titleFocus,
        scrollController: _scrollCtrl,
      ),
      RegisterFieldCheck(
        missing: _contentCtrl.text.trim().isEmpty,
        message: '내용을 입력해주세요.',
        anchorKey: _contentKey,
        focusNode: _contentFocus,
        scrollController: _scrollCtrl,
      ),
    ];
    setState(() => _missingFields = RegisterValidation.missingFields(checks));
    if (!RegisterValidation.check(context, checks) || !mounted) return;

    setState(() {
      _missingFields = const [];
      _isSubmitting = true;
    });
    try {
      // 구직: 프로필 사진 — 새로 고른 파일이 있으면 올리고, 없으면 이미 올라가
      // 있던 URL을 그대로 유지한다(수정에서 사진을 지웠으면 둘 다 null이라
      // 아래에서 필드를 삭제한다).
      String? profileImageUrl = _existingProfileImageUrl;
      if (_crewType == '구직' && _profileImage != null) {
        // 다른 등록 화면들과 **같은 공용 업로더**를 쓴다. 사진이 한 장뿐이라
        // 예전에는 CloudflareService를 직접 불렀는데, 그러면 올리기 전 검사가
        // 없어서 임시저장 복원 뒤 파일이 사라진 경우("경로만 남음") 원인을 알
        // 수 없는 실패로 끝났다. 공용 업로더는 경로·존재·크기를 먼저 보고
        // 어떤 파일이 왜 실패했는지를 담아 던진다.
        final upload = await MediaUploadService.uploadNewMedia(
          media: [_profileImage!],
          logTag: 'crew-profile',
        );
        profileImageUrl = upload.imageUrls.isEmpty
            ? null
            : upload.imageUrls.first;
      }

      // '기타' 선택 시 직접 입력한 역할명을 함께 포함
      final customRole = _roleCtrl.text.trim();
      final roles = {
        ..._selectedRoles.where((r) => r != '기타'),
        if (_selectedRoles.contains('기타') && customRole.isNotEmpty) customRole,
      }.toList();

      final doc = <String, dynamic>{
        'crewType': _crewType,
        'recruitType': _recruitType,
        'title': _titleCtrl.text.trim(),
        'content': _contentCtrl.text.trim(),
        'roles': roles,
        'role': roles.join(' · '), // 구버전 호환용 표시 문자열
        // regionAreas(정본, "서울 강남구") + regions(광역) + districts(구/군)를
        // 한꺼번에 만든다 — 기존 광역 단위 상세검색이 그대로 동작한다.
        ...CrewArea.toCrewFields(_selectedAreas),
        'payType': _payType,
        'payAmount': (_payType == '협의' || _payType == '무료')
            ? 0
            : int.tryParse(_payCtrl.text.trim().replaceAll(',', '')) ?? 0,
        'recruitCount': int.tryParse(_recruitCountCtrl.text.trim()) ?? 0,
        'beginnerFriendly': _beginnerFriendly,
        'experiencedPreferred': _experiencedPreferred,
        // 정체성 필드(소유자·생성일)는 **등록할 때만** 쓴다. 수정에서 다시
        // 쓰면 hostId가 지금 로그인한 사람으로 덮이고 생성일이 리셋된다.
        if (!_isEdit) ...{
          'hostId': UserSession.userId,
          'hostName': UserSession.displayName,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 조건부 필드 — 등록은 "값이 있을 때만" 넣으면 되지만, 수정은 값이
      // 빠졌을 때 **문서에서 지워야** 한다(그대로 두면 글 유형을 구인↔구직으로
      // 바꾸거나 주소·사진을 뺐을 때 옛 값이 남는다). update()라 이 차이가
      // 실제로 드러나므로 헬퍼 하나로 규칙을 통일한다.
      void put(String key, Object? value) {
        if (value != null) {
          doc[key] = value;
        } else if (_isEdit) {
          doc[key] = FieldValue.delete();
        }
      }

      // 구인 전용 필드
      final isRecruit = _crewType == '구인';
      put('autoMessage', isRecruit ? _autoMsgCtrl.text.trim() : null);
      final addr = isRecruit ? _selectedAddress : null;
      put('address', addr?.address);
      put('roadAddress', addr?.roadAddress);
      put('jibunAddress', addr?.jibunAddress);
      put('latitude', addr?.latitude);
      put('longitude', addr?.longitude);
      final detail = _detailAddressCtrl.text.trim();
      put('detailAddress', addr != null && detail.isNotEmpty ? detail : null);

      // 구직 전용 필드
      put('profileImageUrl', _crewType == '구직' ? profileImageUrl : null);

      final dated = _recruitType == '날짜지정';
      put('startDate', dated ? Timestamp.fromDate(_startDate!) : null);
      put(
        'endDate',
        dated && _endDate != null ? Timestamp.fromDate(_endDate!) : null,
      );
      put('startTime', _startTime == null ? null : _timeStr(_startTime!));
      put('endTime', _endTime == null ? null : _timeStr(_endTime!));

      final crews = FirebaseFirestore.instance.collection('crews');
      if (_isEdit) {
        await crews.doc(widget.docId).update(doc);
        if (!mounted) {
          return;
        }
        _msg('수정되었습니다');
        Navigator.pop(context, true);
        return;
      }

      await crews.add(doc);
      if (!mounted) {
        return;
      }
      // 최종 등록 완료 — 이 유형(구인/구직)의 임시저장은 자동 삭제.
      await deleteCurrentDraft();
      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.check_circle,
                color: Color(0xFFFF6FA0),
                size: 26,
              ),
              const SizedBox(width: 10),
              Text(
                _crewType == '구인' ? '구인 등록 완료' : '구직 등록 완료',
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
            ],
          ),
          content: Text(
            _crewType == '구인' ? '파티크루 구인 글이 등록되었습니다.' : '파티크루 구직 글이 등록되었습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // 다이얼로그 닫기
                // 등록 화면이 몇 단계 깊이 열려 있었든(모바일:
                // RegisterTypeScreen 경유, 데스크톱: MainScreen에서 바로)
                // 곧장 메인화면 파티크루 탭으로 복귀한다.
                pendingTopTabAfterRegister.value = 3;
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              child: const Text(
                '확인',
                style: TextStyle(
                  color: Color(0xFFFF6FA0),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      // 원인을 삼키지 않는다 — 사진 문제인지(그 사진을 빼면 된다) 인증·네트워크
      // 문제인지(사진을 지워도 소용없다)를 가려서 안내한다. 다른 등록 화면과
      // 같은 함수를 쓴다.
      MediaUploadService.logUploadError(
        e,
        StackTrace.current,
        logTag: 'crew-profile',
        label: _isEdit ? '❌ 파티크루 글 수정 실패' : '❌ 파티크루 글 등록 실패',
      );
      if (mounted) {
        _msg(
          RegisterValidation.failureMessage(e, stage: _isEdit ? '수정' : '등록'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );

  // ── 빌드 ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !draftDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await confirmLeaveWithDraftSave();
        // context.mounted로 확인한다 — State의 mounted만 보면 이 build의
        // BuildContext가 이미 트리에서 빠진 경우를 놓친다.
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF4F8),
        appBar: AppBar(
          title: Text(
            widget.mode.screenTitle('파티크루'),
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
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          actions: _isEdit ? null : [draftSaveAction()],
          bottom: _isEdit ? null : buildAutoSaveIndicator(),
        ),
        body: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (draftMediaNeedsReselect) buildMediaReselectBanner(),
              RegisterMissingFieldsBanner(fields: _missingFields),
              // ── 1. 글 유형 ───────────────────────────────────────────
              _label('글 유형'),
              _segment(
                options: ['구인', '구직'],
                selected: _crewType,
                accent: const Color(0xFFFF6FA0),
                onTap: (v) => setState(() => _crewType = v),
              ),
              const SizedBox(height: 22),

              // ── 2. 구직 전용: 프로필 사진 ────────────────────────────
              if (_crewType == '구직') ...[
                _label('프로필 사진 (선택)'),
                _buildProfileImagePicker(),
                const SizedBox(height: 22),
              ],

              // ── 3. 모집 기간 ─────────────────────────────────────────
              _label('모집 기간'),
              _segment(
                options: ['항시', '날짜지정'],
                displayValues: ['항시 모집', '날짜 지정'],
                selected: _recruitType,
                accent: const Color(0xFF7C5CBF),
                onTap: (v) => setState(() => _recruitType = v),
              ),
              const SizedBox(height: 12),

              if (_recruitType == '날짜지정') ...[
                RegisterFieldAnchor(
                  key: _startDateKey,
                  child: Row(
                    children: [
                      Expanded(
                        child: _dateTile(
                          '시작 날짜',
                          _startDate,
                          () => _pickDate(true),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '~',
                          style: TextStyle(fontSize: 16, color: Colors.black45),
                        ),
                      ),
                      Expanded(
                        child: _dateTile(
                          '종료 날짜 (선택)',
                          _endDate,
                          () => _pickDate(false),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else
                const SizedBox(height: 6),

              // ── 4. 모집 시간 ─────────────────────────────────────────
              _label('모집 시간 (선택)'),
              Row(
                children: [
                  Expanded(
                    child: _timeTile(
                      '시작 시간',
                      _startTime,
                      () => _pickTime(true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '~',
                      style: TextStyle(fontSize: 16, color: Colors.black45),
                    ),
                  ),
                  Expanded(
                    child: _timeTile('종료 시간', _endTime, () => _pickTime(false)),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // ── 5. 역할/직종 (다중 선택 — 상세검색 필터와 매칭) ────────
              _label(_crewType == '구인' ? '모집 역할' : '지원 가능 역할'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ListingConstants.crewRoles.map((r) {
                  final sel = _selectedRoles.contains(r);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (sel) {
                        _selectedRoles.remove(r);
                      } else {
                        _selectedRoles.add(r);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 130),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFFFF6FA0) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel
                              ? const Color(0xFFFF6FA0)
                              : const Color(0xFFE8EBF2),
                          width: sel ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        r,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : Colors.black54,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_selectedRoles.contains('기타')) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _roleCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: _deco('기타 역할을 직접 입력해주세요'),
                ),
              ],
              const SizedBox(height: 22),

              // ── 6. 제목 ──────────────────────────────────────────────
              _label('제목'),
              RegisterFieldAnchor(
                key: _titleKey,
                child: TextField(
                  controller: _titleCtrl,
                  focusNode: _titleFocus,
                  textInputAction: TextInputAction.next,
                  decoration: _deco(
                    _crewType == '구인'
                        ? '예: 10월 할로윈 파티 DJ 구인합니다'
                        : '예: 파티 MC 경력 3년, 활동 가능합니다',
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // ── 7. 상세 내용 ─────────────────────────────────────────
              _label('상세 내용'),
              RegisterFieldAnchor(
                key: _contentKey,
                child: TextField(
                  controller: _contentCtrl,
                  focusNode: _contentFocus,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  decoration: _deco(
                    _crewType == '구인'
                        ? '파티 일정, 장소, 조건, 페이 등을 자세히 입력해주세요.'
                        : '경력, 보유 장비, 가능한 역할, 희망 조건 등을 입력해주세요.',
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // ── 8. 구인 전용: 실제 주소 ──────────────────────────────
              if (_crewType == '구인') ...[
                _label('실제 주소 (선택)'),
                _buildAddressSection(),
                const SizedBox(height: 22),
              ],

              // ── 9. 활동 지역 (시/도 → 구/군, 최대 3개) ────────────────
              Row(
                children: [
                  Expanded(child: _label('활동 지역 (최대 $_maxAreas개)')),
                  Text(
                    '${_selectedAreas.length}/$_maxAreas개 선택',
                    style: TextStyle(
                      fontSize: 12,
                      color: _selectedAreas.length >= _maxAreas
                          ? const Color(0xFFFF6FA0)
                          : Colors.black38,
                    ),
                  ),
                ],
              ),
              _buildRegionSelector(),
              const SizedBox(height: 22),

              // ── 9. 급여/페이 ─────────────────────────────────────────
              _label('급여 / 페이'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _payTypes.map((t) {
                  final sel = _payType == t;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _payType = t;
                      if (t == '협의' || t == '무료') {
                        _payCtrl.clear();
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFFFF6FA0) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel
                              ? const Color(0xFFFF6FA0)
                              : const Color(0xFFE8EBF2),
                          width: sel ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        t,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : Colors.black54,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_payType != '협의' && _payType != '무료') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _payCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: _deco(_payType == '시급' ? '시급 금액 (원)' : '금액 (원)'),
                ),
              ],
              const SizedBox(height: 22),

              // ── 9-1. 모집 인원 (선택) ────────────────────────────────
              _label('모집 인원 (선택)'),
              TextField(
                controller: _recruitCountCtrl,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: _deco('예: 2 (인원 미정이면 비워두세요)'),
              ),
              const SizedBox(height: 22),

              // ── 9-2. 모집 조건 (상세검색 필터용) ─────────────────────
              _label('모집 조건'),
              Row(
                children: [
                  Expanded(
                    child: _conditionToggle(
                      label: '초보 가능',
                      value: _beginnerFriendly,
                      onChanged: (v) => setState(() => _beginnerFriendly = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _conditionToggle(
                      label: '경력 우대',
                      value: _experiencedPreferred,
                      onChanged: (v) =>
                          setState(() => _experiencedPreferred = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // ── 10. 구인 전용: 지원자 자동 안내 문구 ─────────────────
              if (_crewType == '구인') ...[
                _label('지원자 자동 안내 문구'),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFFD6E4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.notifications_outlined,
                            size: 14,
                            color: Color(0xFFFF6FA0),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '근무 시작 2시간 전에 지원자에게 자동으로 발송돼요.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFFF6FA0),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _autoMsgCtrl,
                        maxLines: 4,
                        decoration: _deco(
                          '예: 안녕하세요! 오늘 근무 관련 안내드립니다.\n집합 장소는 ...',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
              ],

              // ── 제출 버튼 ────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
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
                          _isEdit
                              ? '수정 완료'
                              : (_crewType == '구인' ? '구인 글 등록하기' : '구직 글 등록하기'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              // 삭제는 앱 전체가 같은 흐름을 쓴다(공용 DeleteContentButton) —
              // 마이페이지 목록의 삭제와 문구·확인창·권한 검사가 완전히 같다.
              // 등록 중에는 지울 대상이 아직 없다.
              if (_isEdit)
                DeleteContentButton(
                  type: DeletableContent.crew,
                  id: widget.docId!,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 프로필 사진 picker (구직) ─────────────────────────────────────
  Widget _buildProfileImagePicker() {
    return GestureDetector(
      onTap: _pickProfileImage,
      child: !_hasProfileImage
          ? Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFE8EBF2),
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.add_a_photo_outlined,
                    size: 32,
                    color: Color(0xFFFF6FA0),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '프로필 사진 추가 (선택)',
                    style: TextStyle(fontSize: 13, color: Colors.black45),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '1:1 비율 권장',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  // 새로 고른 로컬 파일이 우선이고, 없으면 이미 올라가 있는 URL을
                  // 보여준다(수정 진입 직후가 이 경우다).
                  child: _profileImage != null
                      ? LocalMedia.image(
                          _profileImage!,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                        )
                      : Image.network(
                          _existingProfileImageUrl!,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                        ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _profileImage = null;
                      _existingProfileImageUrl = null;
                    }),
                    child: Container(
                      width: 28,
                      height: 28,
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
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: _pickProfileImage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '변경',
                        style: TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ── 구인 전용: 주소 검색 섹션 ────────────────────────────────────
  Widget _buildAddressSection() {
    return Column(
      children: [
        GestureDetector(
          onTap: () async {
            final result = await Navigator.push<AddressResult>(
              context,
              webFramedRoute((_) => const AddressSearchScreen()),
            );
            if (result != null) {
              setState(() => _selectedAddress = result);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: _selectedAddress != null
                  ? const Color(0xFFFFF0F5)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _selectedAddress != null
                    ? const Color(0xFFFF6FA0)
                    : const Color(0xFFE8EBF2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: _selectedAddress != null
                      ? const Color(0xFFFF6FA0)
                      : Colors.black38,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedAddress != null
                        ? _selectedAddress!.address
                        : '주소 검색',
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedAddress != null
                          ? Colors.black87
                          : Colors.black38,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_selectedAddress != null)
                  GestureDetector(
                    onTap: () => setState(() => _selectedAddress = null),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.black38,
                    ),
                  )
                else
                  const Icon(Icons.search, size: 18, color: Colors.black38),
              ],
            ),
          ),
        ),
        if (_selectedAddress != null) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _detailAddressCtrl,
            textInputAction: TextInputAction.next,
            decoration: _deco('상세 주소 (동/호수 등, 선택)'),
          ),
        ],
      ],
    );
  }

  // ── 지역 선택 (1단계 시/도 → 2단계 구/군) ────────────────────────
  // 파티 상세검색·장소 필터와 같은 2단계 구조이고, 데이터도 같은 RegionData를
  // 쓴다(CrewArea 경유). 구/군 목록 맨 앞의 '전체'는 그 시/도 전 지역을 뜻한다.
  Widget _buildRegionSelector() {
    final districts = CrewArea.districtsOf(_areaCity);
    final full = _selectedAreas.length >= _maxAreas;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1단계 — 시/도 (가로 스크롤)
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: CrewArea.regions.map((city) {
                final active = _areaCity == city;
                final picked = _selectedAreas.any((a) => a.region == city);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _areaCity = city),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 130),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFFFF6FA0)
                            : picked
                            ? const Color(0xFFFFF0F5)
                            : const Color(0xFFF5F5F7),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: active
                              ? const Color(0xFFFF6FA0)
                              : picked
                              ? const Color(0xFFFFD6E4)
                              : const Color(0xFFE8EBF2),
                        ),
                      ),
                      child: Text(
                        city,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: active
                              ? Colors.white
                              : picked
                              ? const Color(0xFFFF6FA0)
                              : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          // 2단계 — '전체' + 구/군
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _areaChip(CrewArea.allLabel, null, full),
              ...districts.map((d) => _areaChip(d, d, full)),
            ],
          ),
          // 선택 결과 — "서울 전체 / 부산 해운대구"처럼 시/도까지 붙여 보여줘
          // 다른 시/도로 넘어가도 무엇을 골랐는지 한눈에 보이게 한다.
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF0F0F4)),
          const SizedBox(height: 12),
          if (_selectedAreas.isEmpty)
            const Text(
              '선택한 지역이 없어요 — 시/도를 고른 뒤 전체 또는 구/군을 선택해주세요.',
              style: TextStyle(fontSize: 12, color: Colors.black38),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedAreas.map((a) {
                return GestureDetector(
                  onTap: () => _toggleArea(a.region, a.district),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6FA0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          a.label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.close, size: 14, color: Colors.white),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  /// 2단계(구/군) 칩 하나. [district]가 null이면 '전체'.
  /// 최대 개수를 채운 뒤에는 이미 고른 칩만 누를 수 있다(해제용).
  Widget _areaChip(String text, String? district, bool full) {
    final sel = _selectedAreas.contains(CrewArea(_areaCity, district));
    final disabled = !sel && full;
    return GestureDetector(
      onTap: disabled ? null : () => _toggleArea(_areaCity, district),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: sel
              ? const Color(0xFFFF6FA0)
              : disabled
              ? const Color(0xFFF7F7FA)
              : const Color(0xFFFFF0F5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: sel
                ? const Color(0xFFFF6FA0)
                : disabled
                ? const Color(0xFFE8EBF2)
                : const Color(0xFFFFD6E4),
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: sel
                ? Colors.white
                : disabled
                ? Colors.black26
                : const Color(0xFFFF6FA0),
          ),
        ),
      ),
    );
  }

  Widget _conditionToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => GestureDetector(
    onTap: () => onChanged(!value),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: value ? const Color(0xFFFFF0F5) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
          width: value ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            value ? Icons.check_circle : Icons.circle_outlined,
            size: 18,
            color: value ? const Color(0xFFFF6FA0) : Colors.black26,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: value ? const Color(0xFFFF6FA0) : Colors.black54,
            ),
          ),
        ],
      ),
    ),
  );

  // ── 공통 위젯 ────────────────────────────────────────────────────
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    ),
  );

  Widget _segment({
    required List<String> options,
    required String selected,
    required Color accent,
    required void Function(String) onTap,
    List<String>? displayValues,
  }) => Row(
    children: List.generate(options.length, (i) {
      final val = options[i];
      final display = displayValues?[i] ?? val;
      final isSel = selected == val;
      return Expanded(
        child: GestureDetector(
          onTap: () => onTap(val),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: EdgeInsets.only(right: i < options.length - 1 ? 8 : 0),
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: isSel ? accent : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSel ? accent : const Color(0xFFE8EBF2),
                width: isSel ? 1.5 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              display,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSel ? Colors.white : Colors.black54,
              ),
            ),
          ),
        ),
      );
    }),
  );

  Widget _dateTile(String label, DateTime? date, VoidCallback onTap) {
    final has = date != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: has ? const Color(0xFFFFF0F5) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: has ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.black38),
            ),
            const SizedBox(height: 3),
            Text(
              has ? _fmtDate(date) : '날짜 선택',
              style: TextStyle(
                fontSize: 12,
                fontWeight: has ? FontWeight.w600 : FontWeight.normal,
                color: has ? const Color(0xFFFF6FA0) : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeTile(String label, TimeOfDay? time, VoidCallback onTap) {
    final has = time != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: has ? const Color(0xFFFFF0F5) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: has ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.black38),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 13,
                  color: has ? const Color(0xFFFF6FA0) : Colors.black26,
                ),
                const SizedBox(width: 4),
                Text(
                  has ? _fmtTime(time) : '시간 선택',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: has ? FontWeight.w600 : FontWeight.normal,
                    color: has ? const Color(0xFFFF6FA0) : Colors.black38,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
