import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:party_app/models/address_result.dart';
import 'package:party_app/models/draft_type.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/party_auto_description_style.dart';
import 'package:party_app/models/party_description_mode.dart';
import 'package:party_app/models/party_detail_decoration_intensity.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/screens/address_search_screen.dart';
import 'package:party_app/screens/party_media_picker_screen.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/utils/age_range_utils.dart';
import 'package:party_app/utils/draftable_register.dart';
import 'package:party_app/utils/register_return_signal.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/combo_intro_card.dart';
import 'package:party_app/widgets/party_form/age_restriction_sheet.dart';
import 'package:party_app/widgets/party_form/date_time_sheet.dart';
import 'package:party_app/widgets/party_form/party_title_field.dart';
import 'package:party_app/widgets/party_form/section_summary_row.dart';
import 'package:party_app/widgets/party_media_editor.dart' show PartyCoverPick;
import 'package:party_app/widgets/web_frame.dart';

const _kAccent = Color(0xFFFF6FA0);

/// 플레이스+파티 콤보 등록 — 혼술바·펍·와인바·라운지처럼 매장을 운영하면서
/// 파티/이벤트도 함께 여는 사장님이 한 번의 입력으로 `events` 문서(플레이스
/// 탭에 노출)와 `parties` 문서(파티 탭에 노출)를 함께 만든다.
///
/// [PartyPlaceComboRegisterScreen](party_place_combo_register_screen.dart)
/// ("숙박+파티")와 같은 패턴이다 — 화면상으로는 하나의 통합 등록이지만
/// 내부적으로는 기존 "플레이스 등록"(`event_register_screen.dart`)과 "파티
/// 등록"(`party_register_screen.dart`)이 만드는 것과 동일한 셰이프의 문서
/// 2개를 만들고 `bundleId`/`linkedPartyId`/`linkedEventId`로 서로 연결한다.
/// 숙박 콤보와 달리 객실(룸)이 없는 매장이라 룸 섹션·체크인/체크아웃·
/// 패키지 예약은 없다 — 대신 "플레이스 등록"에 있는 특징 태그/진행 기간/
/// 이용 시간을 그대로 가져온다.
///
/// `linkedPlaceId`(파티→`places`)와는 다른 필드명(`linkedEventId`,
/// 파티→`events`)을 쓴다 — 파티 상세화면의 기존 "숙박 정보 함께보기" 카드가
/// `places` 컬렉션을 하드코딩해서 조회하므로, 같은 필드명을 재사용하면
/// 엉뚱한 컬렉션을 조회하게 된다.
class PlacePartyComboRegisterScreen extends StatefulWidget {
  /// 마이페이지 "임시저장" 목록에서 "이어서 작성"으로 열 때 true.
  final bool autoRestoreDraft;

  const PlacePartyComboRegisterScreen({
    super.key,
    this.autoRestoreDraft = false,
  });

  @override
  State<PlacePartyComboRegisterScreen> createState() =>
      _PlacePartyComboRegisterScreenState();
}

class _PlacePartyComboRegisterScreenState
    extends State<PlacePartyComboRegisterScreen>
    with
        WidgetsBindingObserver,
        DraftableRegister<PlacePartyComboRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();

  // ── 임시저장 ─────────────────────────────────────────────────────────
  // 파티 등록 화면과 동일한 방식(1초 debounce 자동저장 + 임시저장 버튼 +
  // 재진입 복구 팝업)을 공용 믹스인으로 붙인다.

  @override
  void setState(VoidCallback fn) {
    markDraftDirty();
    super.setState(fn);
  }

  @override
  DraftType get draftType => DraftType.placePartyCombo;

  @override
  bool get draftAutoRestore => widget.autoRestoreDraft;

  @override
  String get draftTitle => _nameCtrl.text;

  @override
  String? get draftCoverImageUrl =>
      _mediaExistingImageUrls.isNotEmpty ? _mediaExistingImageUrls.first : null;

  @override
  Map<String, dynamic> buildDraftPayload() {
    return <String, dynamic>{
      // 공통 정보
      'name': _nameCtrl.text,
      'detailAddress': _detailAddressCtrl.text,
      'contact': _contactCtrl.text,
      'description': _descCtrl.text,
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
      // 미디어 — 업로드된 URL은 그대로, 아직 업로드 안 된 로컬 파일은 경로만.
      'existingImageUrls': _mediaExistingImageUrls,
      'existingVideoUrl': _mediaExistingVideoUrl,
      'existingVideoUid': _mediaExistingVideoUid,
      'existingVideoThumbnailUrl': _mediaExistingVideoThumbnailUrl,
      'newFilePaths': _mediaNewFiles.map((f) => f.path).toList(),
      'coverPick': _mediaCoverPick == null
          ? null
          : {
              'existingImageUrl': _mediaCoverPick!.existingImageUrl,
              'isExistingVideo': _mediaCoverPick!.isExistingVideo,
              'newImageOrdinal': _mediaCoverPick!.newImageOrdinal,
              'isNewVideo': _mediaCoverPick!.isNewVideo,
            },
      // 플레이스 정보
      'themeTags': _themeTags.toList(),
      'isOngoing': _isOngoing,
      'startDateMs': _startDate?.millisecondsSinceEpoch,
      'endDateMs': _endDate?.millisecondsSinceEpoch,
      'hasTimeRange': _hasTimeRange,
      'startTime': DraftableRegister.timeToMap(_startTime),
      'endTime': DraftableRegister.timeToMap(_endTime),
      'isActive': _isActive,
      // 파티 정보
      'partyDateMs': _partyDate?.millisecondsSinceEpoch,
      'partyStartTime': DraftableRegister.timeToMap(_partyStartTime),
      'partyEndTime': DraftableRegister.timeToMap(_partyEndTime),
      'partyRecruitDeadlineTime':
          DraftableRegister.timeToMap(_partyRecruitDeadlineTime),
      'partyCapacity': _partyCapacityCtrl.text,
      'partyFee': _partyFeeCtrl.text,
      'partyDesc': _partyDescCtrl.text,
      'ageRestrictionEnabled': _ageRestrictionEnabled,
      'minBirthYear': _minBirthYear,
      'maxBirthYear': _maxBirthYear,
    };
  }

  @override
  void applyDraftPayload(Map<String, dynamic> p) {
    _nameCtrl.text = (p['name'] as String?) ?? '';
    _detailAddressCtrl.text = (p['detailAddress'] as String?) ?? '';
    _contactCtrl.text = (p['contact'] as String?) ?? '';
    _descCtrl.text = (p['description'] as String?) ?? '';
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

    _mediaExistingImageUrls =
        [...((p['existingImageUrls'] as List?)?.cast<String>() ?? const [])];
    _mediaExistingVideoUrl = p['existingVideoUrl'] as String?;
    _mediaExistingVideoUid = p['existingVideoUid'] as String?;
    _mediaExistingVideoThumbnailUrl = p['existingVideoThumbnailUrl'] as String?;
    bool anyMissing = false;
    _mediaNewFiles = [];
    for (final path
        in (p['newFilePaths'] as List?)?.cast<String>() ?? const []) {
      if (File(path).existsSync()) {
        _mediaNewFiles.add(XFile(path));
      } else {
        anyMissing = true;
      }
    }
    final coverPick = p['coverPick'] as Map?;
    _mediaCoverPick = coverPick == null
        ? null
        : PartyCoverPick(
            existingImageUrl: coverPick['existingImageUrl'] as String?,
            isExistingVideo: coverPick['isExistingVideo'] as bool? ?? false,
            newImageOrdinal: (coverPick['newImageOrdinal'] as num?)?.toInt(),
            isNewVideo: coverPick['isNewVideo'] as bool? ?? false,
          );

    _themeTags
      ..clear()
      ..addAll((p['themeTags'] as List?)?.cast<String>() ?? const []);
    _isOngoing = p['isOngoing'] as bool? ?? true;
    final sMs = (p['startDateMs'] as num?)?.toInt();
    final eMs = (p['endDateMs'] as num?)?.toInt();
    _startDate = sMs != null ? DateTime.fromMillisecondsSinceEpoch(sMs) : null;
    _endDate = eMs != null ? DateTime.fromMillisecondsSinceEpoch(eMs) : null;
    _hasTimeRange = p['hasTimeRange'] as bool? ?? false;
    _startTime = DraftableRegister.timeFromMap(p['startTime']);
    _endTime = DraftableRegister.timeFromMap(p['endTime']);
    _isActive = p['isActive'] as bool? ?? true;

    final pdMs = (p['partyDateMs'] as num?)?.toInt();
    _partyDate = pdMs != null ? DateTime.fromMillisecondsSinceEpoch(pdMs) : null;
    _partyStartTime = DraftableRegister.timeFromMap(p['partyStartTime']);
    _partyEndTime = DraftableRegister.timeFromMap(p['partyEndTime']);
    _partyRecruitDeadlineTime =
        DraftableRegister.timeFromMap(p['partyRecruitDeadlineTime']);
    _partyCapacityCtrl.text = (p['partyCapacity'] as String?) ?? '';
    _partyFeeCtrl.text = (p['partyFee'] as String?) ?? '';
    _partyDescCtrl.text = (p['partyDesc'] as String?) ?? '';
    _ageRestrictionEnabled = p['ageRestrictionEnabled'] as bool? ?? false;
    _minBirthYear =
        (p['minBirthYear'] as num?)?.toInt() ?? birthYearFromAge(31);
    _maxBirthYear =
        (p['maxBirthYear'] as num?)?.toInt() ?? birthYearFromAge(23);

    draftMediaNeedsReselect = anyMissing;
  }

  @override
  void initState() {
    super.initState();
    for (final c in [
      _nameCtrl,
      _detailAddressCtrl,
      _contactCtrl,
      _descCtrl,
      _partyCapacityCtrl,
      _partyFeeCtrl,
      _partyDescCtrl,
    ]) {
      c.addListener(markDraftDirty);
    }
    initDraft();
  }

  // 섹션별 스크롤 앵커
  final _basicInfoKey = GlobalKey();
  final _photosKey = GlobalKey();
  final _partyDateKey = GlobalKey();

  // ── 공통 정보 ────────────────────────────────────────────────────────
  final _nameCtrl = PartyTitleController();
  final _detailAddressCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  AddressResult? _selectedAddress;
  bool _showAddressError = false;

  // ── 사진/동영상 — 파티·플레이스 등록과 동일한 공용 위젯 재사용. 신규
  // 등록만 지원하므로 existing* 필드는 항상 빈 값으로 시작한다.
  List<String> _mediaExistingImageUrls = [];
  String? _mediaExistingVideoUrl;
  String? _mediaExistingVideoUid;
  String? _mediaExistingVideoThumbnailUrl;
  List<XFile> _mediaNewFiles = [];
  PartyCoverPick? _mediaCoverPick;
  bool _showImageError = false;

  // ── 플레이스 정보 ────────────────────────────────────────────────────
  // 업종이 아니라 매장의 특징(테마) — 다중 선택 가능(선택 안 해도 됨).
  final Set<String> _themeTags = {};
  bool _isOngoing = true;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _hasTimeRange = false;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isActive = true;

  // ── 파티 정보 ────────────────────────────────────────────────────────
  DateTime? _partyDate;
  TimeOfDay? _partyStartTime;
  TimeOfDay? _partyEndTime;
  TimeOfDay? _partyRecruitDeadlineTime;
  bool _showPartyDateError = false;
  final _partyCapacityCtrl = TextEditingController();
  final _partyFeeCtrl = TextEditingController();
  final _partyDescCtrl = TextEditingController();
  bool _ageRestrictionEnabled = false;
  int _minBirthYear = birthYearFromAge(31);
  int _maxBirthYear = birthYearFromAge(23);

  bool _isUploading = false;
  String _uploadStatus = '';

  @override
  void dispose() {
    disposeDraft();
    _scrollCtrl.dispose();
    _nameCtrl.dispose();
    _detailAddressCtrl.dispose();
    _contactCtrl.dispose();
    _descCtrl.dispose();
    _partyCapacityCtrl.dispose();
    _partyFeeCtrl.dispose();
    _partyDescCtrl.dispose();
    super.dispose();
  }

  // ── 미디어 ───────────────────────────────────────────────────────────

  bool _isVideoFile(XFile f) {
    final p = f.path.toLowerCase();
    return p.endsWith('.mp4') || p.endsWith('.mov');
  }

  bool get _mediaHasVideo =>
      _mediaExistingVideoUrl != null || _mediaNewFiles.any(_isVideoFile);

  String? _mediaSummary() {
    final photoCount = _mediaExistingImageUrls.length +
        _mediaNewFiles.where((f) => !_isVideoFile(f)).length;
    final parts = <String>[];
    if (photoCount > 0) parts.add('사진 $photoCount장');
    if (_mediaHasVideo) parts.add('동영상 1개');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<void> _openMediaPicker() async {
    final result = await Navigator.push<PartyMediaSelection>(
      context,
      webFramedRoute((_) => PartyMediaPickerScreen(
          existingImageUrls: _mediaExistingImageUrls,
          existingVideoUrl: _mediaExistingVideoUrl,
          existingVideoUid: _mediaExistingVideoUid,
          existingVideoThumbnailUrl: _mediaExistingVideoThumbnailUrl,
          newMedia: _mediaNewFiles,
          coverPick: _mediaCoverPick,
          showSpotifySection: false,
          showVideoCropButton: false,
          maxImages: 10,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _mediaExistingImageUrls = result.existingImageUrls;
      _mediaExistingVideoUrl = result.existingVideoUrl;
      _mediaExistingVideoUid = result.existingVideoUid;
      _mediaExistingVideoThumbnailUrl = result.existingVideoThumbnailUrl;
      _mediaNewFiles = result.newMedia;
      _mediaCoverPick = result.coverPick;
      _showImageError = false;
    });
  }

  // ── 진행 기간 ────────────────────────────────────────────────────────

  Future<void> _pickPeriodDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? now,
      firstDate: isStart ? now : (_startDate ?? now),
      lastDate: DateTime(now.year + 2),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _kAccent),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _pickUsageTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _startTime : _endTime) ??
          const TimeOfDay(hour: 20, minute: 0),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: _kAccent),
          ),
          child: child!,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  // ── 파티 날짜/시간 — 콤보 v1은 날짜 1개만 지원한다(다중 날짜/매주 반복은
  // 이 화면 범위 밖 — 일반 "파티 등록"에만 있는 기능).
  Future<void> _openPartyDateSheet() async {
    final result = await showPartyDateTimeSheet(
      context,
      initial: PartyDateTimeDraft(
        partyDate: _partyDate,
        startTime: _partyStartTime,
        endTime: _partyEndTime,
        recruitDeadlineTime: _partyRecruitDeadlineTime,
      ),
    );
    if (result == null) return;
    setState(() {
      _partyDate = result.partyDate;
      _partyStartTime = result.startTime;
      _partyEndTime = result.endTime;
      _partyRecruitDeadlineTime = result.recruitDeadlineTime;
      _showPartyDateError = false;
    });
  }

  String? _partyDateSummary() {
    if (_partyDate == null || _partyStartTime == null) return null;
    var s =
        '${formatPartyDate(_partyDate)} ${formatPartyTime(_partyStartTime)}';
    if (_partyEndTime != null) s += ' ~ ${formatPartyTime(_partyEndTime)}';
    return s;
  }

  Future<void> _openAgeRestrictionSheet() async {
    final result = await showAgeRestrictionSheet(
      context,
      initial: AgeRestrictionDraft(
        enabled: _ageRestrictionEnabled,
        minYear: _minBirthYear,
        maxYear: _maxBirthYear,
      ),
      audienceType: PartyAudienceType.adult,
    );
    if (result == null) return;
    setState(() {
      _ageRestrictionEnabled = result.enabled;
      _minBirthYear = result.minYear;
      _maxBirthYear = result.maxYear;
    });
  }

  String? _ageSummary() => _ageRestrictionEnabled
      ? '${ageFromBirthYear(_maxBirthYear)}세 ~ ${ageFromBirthYear(_minBirthYear)}세'
      : null;

  void _scrollToKey(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.05,
        );
      }
    });
  }

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );

  String _fmtTime24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ── 제출 ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    bool hasError = false;
    GlobalKey? firstErrorKey;

    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid) {
      hasError = true;
      firstErrorKey ??= _basicInfoKey;
    }
    if (_selectedAddress == null) {
      setState(() => _showAddressError = true);
      hasError = true;
      firstErrorKey ??= _basicInfoKey;
    }
    if (_mediaExistingImageUrls.isEmpty && _mediaNewFiles.isEmpty) {
      setState(() => _showImageError = true);
      hasError = true;
      firstErrorKey ??= _photosKey;
    }
    if (_partyDate == null || _partyStartTime == null) {
      setState(() => _showPartyDateError = true);
      hasError = true;
      firstErrorKey ??= _partyDateKey;
    }

    if (hasError) {
      _scrollToKey(firstErrorKey!);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _msg('로그인이 필요합니다');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = '사진 업로드 중...';
    });

    try {
      // ── 공유 미디어 업로드(플레이스·파티 등록과 동일한 방식) ─────────
      final newMedia = _mediaNewFiles;
      final newImageUrls = <String>[];
      String? newVideoUid;
      String? newVideoUrl;
      String? newVideoThumbnailUrl;

      int done = 0;
      for (final file in newMedia) {
        if (_isVideoFile(file)) {
          setState(() => _uploadStatus = '동영상을 올리는 중...');
          final result = await CloudflareService.uploadVideo(File(file.path));
          newVideoUid = result['videoUid'];
          newVideoUrl = result['videoUrl'];
          newVideoThumbnailUrl = result['videoThumbnailUrl'];
        } else {
          done++;
          setState(
            () => _uploadStatus = '사진 업로드 중... ($done/${newMedia.length})',
          );
          newImageUrls
              .add(await CloudflareService.uploadImage(File(file.path)));
        }
      }

      final imageUrls = [..._mediaExistingImageUrls, ...newImageUrls];
      final finalVideoUrl = newVideoUrl ?? _mediaExistingVideoUrl;
      final finalVideoUid = newVideoUid ?? _mediaExistingVideoUid;
      final finalVideoThumbnailUrl =
          newVideoThumbnailUrl ?? _mediaExistingVideoThumbnailUrl;

      final coverPick = _mediaCoverPick;
      String coverMediaType = 'image';
      String? coverImageUrl;
      String? coverVideoUid;
      String? coverVideoUrl;
      String? coverThumbnailUrl;
      if (coverPick?.isExistingVideo == true ||
          coverPick?.isNewVideo == true) {
        coverMediaType = 'video';
        coverVideoUid = finalVideoUid;
        coverVideoUrl = finalVideoUrl;
        coverThumbnailUrl = finalVideoThumbnailUrl;
      } else if (coverPick?.existingImageUrl != null) {
        coverImageUrl = coverPick!.existingImageUrl;
        coverThumbnailUrl = coverImageUrl;
      } else if (coverPick?.newImageOrdinal != null) {
        final ordinal = coverPick!.newImageOrdinal!;
        coverImageUrl = ordinal < newImageUrls.length
            ? newImageUrls[ordinal]
            : (imageUrls.isNotEmpty ? imageUrls.first : null);
        coverThumbnailUrl = coverImageUrl;
      } else if (imageUrls.isNotEmpty) {
        coverImageUrl = imageUrls.first;
        coverThumbnailUrl = coverImageUrl;
      } else if (finalVideoUrl != null) {
        coverMediaType = 'video';
        coverVideoUid = finalVideoUid;
        coverVideoUrl = finalVideoUrl;
        coverThumbnailUrl = finalVideoThumbnailUrl;
      }
      if (coverMediaType == 'image' && coverImageUrl != null) {
        imageUrls.remove(coverImageUrl);
        imageUrls.insert(0, coverImageUrl);
      }

      // ── 문서 참조 미리 발급 — 서로의 id로 연결해야 하므로 set() 전에
      // 확정해둔다. bundleId는 event 문서 자신의 id를 그대로 쓴다.
      final eventRef = FirebaseFirestore.instance.collection('events').doc();
      final partyRef = FirebaseFirestore.instance.collection('parties').doc();
      final bundleId = eventRef.id;

      setState(() => _uploadStatus = '등록 정보 저장 중...');

      final commonDesc = _descCtrl.text.trim();
      final partyCapacity = int.tryParse(_partyCapacityCtrl.text.trim()) ?? 0;
      final partyFee = int.tryParse(_partyFeeCtrl.text.trim()) ?? 0;
      final contactPhone = _contactCtrl.text.trim();
      final name = _nameCtrl.text.trim();
      final location = _selectedAddress != null
          ? '${_selectedAddress!.address}'
              '${_detailAddressCtrl.text.trim().isNotEmpty ? ' ${_detailAddressCtrl.text.trim()}' : ''}'
          : '';

      final partyDateTime = DateTime(
        _partyDate!.year,
        _partyDate!.month,
        _partyDate!.day,
        _partyStartTime!.hour,
        _partyStartTime!.minute,
      );
      final recruitDeadlineDateTime = _partyRecruitDeadlineTime != null
          ? DateTime(
              _partyDate!.year,
              _partyDate!.month,
              _partyDate!.day,
              _partyRecruitDeadlineTime!.hour,
              _partyRecruitDeadlineTime!.minute,
            )
          : null;

      // ── events 문서 — 기존 "플레이스 등록" 셰이프 + 콤보 연결 필드.
      final eventFields = <String, dynamic>{
        'name': name,
        'description': commonDesc,
        'themeTags': _themeTags.toList(),
        'mainImageUrl': coverImageUrl ?? '',
        'introImageUrls': imageUrls
            .where((u) => u != coverImageUrl)
            .toList(),
        if (finalVideoUrl != null) 'videoProvider': 'cloudflare',
        if (finalVideoUid != null) 'videoUid': finalVideoUid,
        if (finalVideoUrl != null) 'videoUrl': finalVideoUrl,
        if (finalVideoThumbnailUrl != null)
          'videoThumbnailUrl': finalVideoThumbnailUrl,
        'address': _selectedAddress?.address ?? '',
        'roadAddress': _selectedAddress?.roadAddress ?? '',
        'jibunAddress': _selectedAddress?.jibunAddress ?? '',
        'latitude': _selectedAddress?.latitude ?? 0.0,
        'longitude': _selectedAddress?.longitude ?? 0.0,
        'detailAddress': _detailAddressCtrl.text.trim(),
        'location': location,
        'isOngoing': _isOngoing,
        'startDate': _isOngoing || _startDate == null
            ? null
            : Timestamp.fromDate(_startDate!),
        'endDate': _isOngoing || _endDate == null
            ? null
            : Timestamp.fromDate(_endDate!),
        'hasTimeRange': _hasTimeRange,
        'startTime':
            _hasTimeRange && _startTime != null ? _fmtTime24(_startTime!) : null,
        'endTime':
            _hasTimeRange && _endTime != null ? _fmtTime24(_endTime!) : null,
        'isActive': _isActive,
        'contactPhone': contactPhone,
        'hostId': UserSession.userId,
        'hostName': UserSession.displayName,
        // ── 콤보(플레이스+파티) 전용 필드 ──────────────────────────────
        'bundleId': bundleId,
        'linkedPartyId': partyRef.id,
        'isCombo': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // ── parties 문서 — 기존 "파티 등록" 공유 필드 셰이프를 그대로 따르되
      // 이 화면에 없는 고급 기능(라운드/얼리버드/환불규정/상세블록/태그 등)은
      // 기존 렌더러가 정상 동작하도록 안전한 기본값을 채운다.
      final partyFields = <String, dynamic>{
        'title': name,
        'location': _selectedAddress?.displayAddress ?? '',
        'address': _selectedAddress?.address ?? '',
        'roadAddress': _selectedAddress?.roadAddress ?? '',
        'jibunAddress': _selectedAddress?.jibunAddress ?? '',
        'placeName': _selectedAddress?.placeName ?? '',
        if (_selectedAddress != null) 'latitude': _selectedAddress!.latitude,
        if (_selectedAddress != null) 'longitude': _selectedAddress!.longitude,
        'date':
            '${formatPartyDate(_partyDate)} ${formatPartyTime(_partyStartTime)}',
        'partyDateTime': Timestamp.fromDate(partyDateTime),
        if (recruitDeadlineDateTime != null)
          'recruitDeadlineAt': Timestamp.fromDate(recruitDeadlineDateTime),
        'people': '0/$partyCapacity명',
        'genderLimit': 'all',
        'genderCapacityMode': 'unlimited',
        'genderMode': '',
        'maleCapacity': 0,
        'femaleCapacity': 0,
        'currentMaleCount': 0,
        'currentFemaleCount': 0,
        'maxCapacity': partyCapacity,
        'maxParticipants': partyCapacity,
        'currentParticipants': 0,
        'hasMultipleRounds': false,
        'category': '플레이스+파티',
        'partyTypes': <String>[],
        'vibes': <String>[],
        'tags': <String>[],
        'region': RegionData.extractRegion(_selectedAddress?.address ?? ''),
        'district':
            RegionData.extractDistrict(_selectedAddress?.address ?? ''),
        'ageRestrictionEnabled': _ageRestrictionEnabled,
        if (_ageRestrictionEnabled) 'minBirthYear': _minBirthYear,
        if (_ageRestrictionEnabled) 'maxBirthYear': _maxBirthYear,
        'maleFee': partyFee,
        'femaleFee': partyFee,
        'refundPolicy': <Map<String, dynamic>>[],
        'earlyBirdEnabled': false,
        'images': imageUrls,
        if (finalVideoUrl != null) 'videoProvider': 'cloudflare',
        if (finalVideoUid != null) 'videoUid': finalVideoUid,
        if (finalVideoUrl != null) 'videoUrl': finalVideoUrl,
        if (finalVideoThumbnailUrl != null)
          'videoThumbnailUrl': finalVideoThumbnailUrl,
        'detailAddress': _detailAddressCtrl.text.trim(),
        'description': _partyDescCtrl.text.trim(),
        'detailBlocks': <Map<String, dynamic>>[],
        'detailTheme': PartyDetailThemeKey.partychu.name,
        'detailDecorationIntensity':
            PartyDetailDecorationIntensity.standard.name,
        'detailDecorationVariantSeed': 0,
        'detailDescriptionMode': PartyDescriptionMode.auto.name,
        'autoDescriptionStyle': const PartyAutoDescriptionStyle().toMap(),
        'recruitStatus': '모집중',
        'isRecurring': false,
        'lastUsedAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'isDeleted': false,
        'status': 'active',
        'mainImageUrl': imageUrls.isNotEmpty ? imageUrls.first : null,
        'coverMediaType': coverMediaType,
        'coverImageUrl': coverImageUrl,
        'coverVideoUid': coverVideoUid,
        'coverVideoUrl': coverVideoUrl,
        'coverThumbnailUrl': coverThumbnailUrl,
        'basicCardVideoFocalX': 0.5,
        'basicCardVideoFocalY': 0.5,
        'basicCardVideoScale': 1.0,
        'basicCardPhotoCrops': <String, dynamic>{},
        'hostId': UserSession.userId,
        'hostUid': uid,
        'contactPhone': contactPhone,
        'applicants': <String>[],
        'approvedApplicants': <String>[],
        'approved': true,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        // ── 콤보(플레이스+파티) 전용 필드 ──────────────────────────────
        'bundleId': bundleId,
        'linkedEventId': eventRef.id,
        'isCombo': true,
      };

      // ── event + party 두 문서는 배치로 한 번에 커밋한다 — 서로의 id를
      // 이미 참조하므로, 한쪽만 생기는 상황(원자성 깨짐)을 막는다.
      final batch = FirebaseFirestore.instance.batch();
      batch.set(eventRef, eventFields);
      batch.set(partyRef, partyFields);
      await batch.commit();

      // 최종 등록 완료 — 플레이스+파티 임시저장은 자동 삭제.
      await deleteCurrentDraft();

      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _uploadStatus = '';
      });

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: _kAccent),
              SizedBox(width: 8),
              Text(
                '등록 완료',
                style: TextStyle(
                  fontFamily: 'SeoulHangang',
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
          content: const Text(
            '플레이스+파티가 등록되었어요.\n"플레이스" 탭과 "파티" 탭 양쪽에서 확인할 수 있어요.',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('확인'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      pendingTopTabAfterRegister.value = 0;
      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e, st) {
      debugPrint('❌ 플레이스+파티 콤보 등록 실패: $e');
      debugPrint('StackTrace:\n$st');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatus = '';
        });
        _msg('등록 중 오류가 발생했습니다: $e');
      }
    }
  }

  // ── UI 헬퍼 ──────────────────────────────────────────────────────────

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF7F7FA),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 16),
        child: Text(text,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      );

  Widget _sectionCard(
          {required String title, String? subtitle, required Widget child}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontFamily: 'SeoulHangang',
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                      Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                      Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                      Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                    ])),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.black45)),
            ],
            child,
          ],
        ),
      );

  Widget _themeChip(String label, {required bool selected}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _kAccent : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? _kAccent : const Color(0xFFE8EBF2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black54,
          ),
        ),
      );

  Widget _toggleRow({
    required IconData icon,
    required String title,
    required String desc,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(icon, size: 20, color: _kAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87)),
                Text(desc,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black45)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: _kAccent,
          ),
        ]),
      );

  Widget _dateBox(String label, DateTime? date, VoidCallback onTap) {
    final hasVal = date != null;
    String fmt(DateTime d) =>
        '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: hasVal ? const Color(0xFFFFF0F5) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: hasVal ? _kAccent : const Color(0xFFE8EBF2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style:
                      const TextStyle(fontSize: 11, color: Colors.black38)),
              const SizedBox(height: 2),
              Text(
                hasVal ? fmt(date) : '선택',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: hasVal ? FontWeight.w600 : FontWeight.normal,
                  color: hasVal ? _kAccent : Colors.black38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _usageTimeBox(String label, TimeOfDay? time, VoidCallback onTap) {
    final hasVal = time != null;
    String fmt(TimeOfDay t) {
      final h = t.hour;
      final m = t.minute.toString().padLeft(2, '0');
      if (h == 0) return '오전 12:$m';
      if (h < 12) return '오전 $h:$m';
      if (h == 12) return '오후 12:$m';
      return '오후 ${h - 12}:$m';
    }

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: hasVal ? const Color(0xFFFFF0F5) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: hasVal ? _kAccent : const Color(0xFFE8EBF2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style:
                      const TextStyle(fontSize: 11, color: Colors.black38)),
              const SizedBox(height: 2),
              Text(
                hasVal ? fmt(time) : '선택',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: hasVal ? FontWeight.w600 : FontWeight.normal,
                  color: hasVal ? _kAccent : Colors.black38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 빌드 ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !draftDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await confirmLeaveWithDraftSave();
        if (leave && mounted) Navigator.of(context).pop();
      },
      child: Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          appBar: AppBar(
            title: const Text(
              '플레이스+파티 등록',
              style: TextStyle(
                fontFamily: 'SeoulHangang',
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
            actions: [draftSaveAction()],
            bottom: buildAutoSaveIndicator(),
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              children: [
                _buildIntroCard(),
                if (draftMediaNeedsReselect) buildMediaReselectBanner(),
                SizedBox(key: _basicInfoKey, height: 0),
                _buildCommonInfo(),
                SizedBox(key: _photosKey, height: 0),
                _buildPhotos(),
                _buildPlaceDetails(),
                SizedBox(key: _partyDateKey, height: 0),
                _buildPartyInfo(),
                const SizedBox(height: 8),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isUploading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    child: const Text('플레이스+파티 등록하기'),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
        if (_isUploading)
          IgnorePointer(
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 20),
                  Text(_uploadStatus,
                      style:
                          const TextStyle(fontSize: 14, color: Colors.white)),
                ],
              ),
            ),
          ),
      ],
      ),
    );
  }

  // ── 섹션: 안내 카드 ──────────────────────────────────────────────────

  /// 이 등록이 어떤 기능인지 알려주는 접이식 안내 — 숙박+파티 등록과 같은
  /// 컴포넌트를 써서 두 콤보 화면의 안내 모양을 통일한다.
  Widget _buildIntroCard() => const ComboIntroCard(
        summary: '🍻 혼술바·술집·카페 등 매장을 운영하면서 파티도 함께 진행하시나요?',
        sections: [
          ComboIntroSection(
            heading: '플레이스+파티 등록은 이런 분들을 위한 기능입니다.',
            lines: [
              '🍺 혼술바, 술집, 카페 등 매장을 운영하면서 파티도 함께 진행하는 사장님',
              '🎉 정기 모임, 번개 모임, 이벤트, DJ 파티 등을 함께 홍보하고 싶은 매장',
              '📍 플레이스 소개와 파티를 서로 연결하여 더 많은 고객에게 노출하고 싶은 경우',
            ],
          ),
          ComboIntroSection(
            heading: '이렇게 등록하면',
            lines: [
              '🏪 매장 정보와 파티를 한 번에 등록할 수 있어요.',
              '🔗 플레이스 상세와 파티 상세가 서로 연결되어 노출돼요.',
              '📈 매장을 홍보하면서 자연스럽게 파티 참가자도 모집할 수 있어요.',
            ],
          ),
        ],
      );

  // ── 섹션: 공통 정보 ──────────────────────────────────────────────────

  Widget _buildCommonInfo() => _sectionCard(
        title: '공통 정보',
        subtitle: '매장명·주소·사진 등은 플레이스와 파티에 함께 쓰여요',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('매장명 *'),
            PartyTitleField(
              controller: _nameCtrl,
              decoration: _inputDeco('예: 홍대 와인바 살롱'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '매장명을 입력해주세요' : null,
            ),
            _label('주소 *'),
            GestureDetector(
              onTap: () async {
                final result = await Navigator.push<AddressResult>(
                  context,
                  webFramedRoute((_) => const AddressSearchScreen()),
                );
                if (result != null) {
                  setState(() {
                    _selectedAddress = result;
                    _showAddressError = false;
                  });
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: _showAddressError
                      ? const Color(0xFFFFF0F0)
                      : const Color(0xFFF7F7FA),
                  borderRadius: BorderRadius.circular(12),
                  border: _showAddressError
                      ? Border.all(color: Colors.redAccent)
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(Icons.search,
                        size: 18,
                        color:
                            _showAddressError ? Colors.redAccent : _kAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedAddress?.roadAddress ?? '주소를 검색해주세요',
                        style: TextStyle(
                          fontSize: 14,
                          color: _selectedAddress == null
                              ? (_showAddressError
                                  ? Colors.redAccent
                                  : Colors.black38)
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showAddressError)
              const Padding(
                padding: EdgeInsets.only(top: 6, left: 4),
                child: Text('주소를 검색해주세요',
                    style: TextStyle(fontSize: 12, color: Colors.redAccent)),
              ),
            _label('상세주소'),
            TextFormField(
              controller: _detailAddressCtrl,
              decoration: _inputDeco('동/호수, 층수 등'),
            ),
            _label('연락처'),
            TextFormField(
              controller: _contactCtrl,
              keyboardType: TextInputType.phone,
              decoration: _inputDeco('예: 010-1234-5678'),
            ),
            _label('소개'),
            TextFormField(
              controller: _descCtrl,
              maxLines: 4,
              decoration: _inputDeco('매장 특징, 분위기, 오시는 길 등을 소개해주세요'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '소개를 입력해주세요' : null,
            ),
          ],
        ),
      );

  Widget _buildPhotos() => _sectionCard(
        title: '대표 사진·동영상',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('사진 최대 10장 · 동영상 1개(최대 30초) *'),
            if (_mediaSummary() != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_mediaSummary()!,
                    style:
                        const TextStyle(fontSize: 13, color: Colors.black54)),
              ),
            OutlinedButton.icon(
              onPressed: _openMediaPicker,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(_mediaSummary() == null ? '사진/동영상 등록' : '사진/동영상 수정'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _showImageError ? Colors.redAccent : _kAccent,
                side: BorderSide(
                    color: _showImageError ? Colors.redAccent : _kAccent),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (_showImageError)
              const Padding(
                padding: EdgeInsets.only(top: 6, left: 4),
                child: Text('대표 사진 또는 동영상을 최소 1개 등록해주세요',
                    style: TextStyle(fontSize: 12, color: Colors.redAccent)),
              ),
          ],
        ),
      );

  // ── 섹션: 플레이스 정보 ──────────────────────────────────────────────

  Widget _buildPlaceDetails() => _sectionCard(
        title: '플레이스 정보',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('특징 태그 (다중 선택 가능)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ListingConstants.placeThemeTags.map((c) {
                final sel = _themeTags.contains(c);
                final emoji = ListingConstants.placeThemeTagEmojis[c] ?? '';
                return GestureDetector(
                  onTap: () => setState(() {
                    if (sel) {
                      _themeTags.remove(c);
                    } else {
                      _themeTags.add(c);
                    }
                  }),
                  child: _themeChip('$emoji $c', selected: sel),
                );
              }).toList(),
            ),
            _label('진행 기간'),
            _toggleRow(
              icon: Icons.all_inclusive,
              title: '상시 진행',
              desc: '기간 제한 없이 계속 노출돼요.',
              value: _isOngoing,
              onChanged: (v) => setState(() => _isOngoing = v),
            ),
            if (!_isOngoing) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _dateBox(
                      '시작일', _startDate, () => _pickPeriodDate(isStart: true)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('~'),
                  ),
                  _dateBox(
                      '종료일', _endDate, () => _pickPeriodDate(isStart: false)),
                ],
              ),
            ],
            _label('이용 시간 (선택)'),
            _toggleRow(
              icon: Icons.access_time_outlined,
              title: '시간 지정',
              desc: '몇 시부터 몇 시까지인지 표시해요. (필수 아님)',
              value: _hasTimeRange,
              onChanged: (v) => setState(() => _hasTimeRange = v),
            ),
            if (_hasTimeRange) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _usageTimeBox(
                      '시작 시간', _startTime, () => _pickUsageTime(isStart: true)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('~'),
                  ),
                  _usageTimeBox(
                      '종료 시간', _endTime, () => _pickUsageTime(isStart: false)),
                ],
              ),
            ],
            const SizedBox(height: 14),
            _toggleRow(
              icon: Icons.visibility_outlined,
              title: '노출 중',
              desc: '플레이스를 목록에 지금 노출할지 설정해요.',
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
          ],
        ),
      );

  // ── 섹션: 파티 정보 ──────────────────────────────────────────────────

  Widget _buildPartyInfo() => _sectionCard(
        title: '파티 정보',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            SectionSummaryRow(
              title: '파티 날짜와 시간 *',
              summary: _partyDateSummary(),
              hasError: _showPartyDateError,
              errorText: _showPartyDateError ? '파티 날짜와 시작 시간을 선택해줘' : null,
              onTap: _openPartyDateSheet,
            ),
            _label('모집 인원 *'),
            TextFormField(
              controller: _partyCapacityCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDeco('예: 20'),
              validator: (v) => (v == null ||
                      int.tryParse(v.trim()) == null ||
                      int.parse(v.trim()) <= 0)
                  ? '모집 인원을 입력해주세요'
                  : null,
            ),
            _label('참가비 (원)'),
            TextFormField(
              controller: _partyFeeCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDeco('무료면 비워두세요'),
            ),
            _label('연령 및 성별 조건'),
            SectionSummaryRow(
              title: '연령 제한',
              summary: _ageSummary(),
              onTap: _openAgeRestrictionSheet,
            ),
            _label('파티 상세내용'),
            TextFormField(
              controller: _partyDescCtrl,
              maxLines: 5,
              decoration: _inputDeco('파티 진행 방식, 준비물, 주의사항 등을 적어주세요'),
            ),
          ],
        ),
      );
}
