import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/models/address_result.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/screens/address_search_screen.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/models/draft_type.dart';
import 'package:party_app/utils/draftable_register.dart';
import 'package:party_app/utils/register_return_signal.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/single_video_picker.dart';
import 'package:party_app/widgets/web_frame.dart';

class EventRegisterScreen extends StatefulWidget {
  /// 마이페이지 "임시저장" 목록에서 "이어서 작성"으로 열 때 true.
  final bool autoRestoreDraft;

  const EventRegisterScreen({super.key, this.autoRestoreDraft = false});

  @override
  State<EventRegisterScreen> createState() => _EventRegisterScreenState();
}

class _EventRegisterScreenState extends State<EventRegisterScreen>
    with WidgetsBindingObserver, DraftableRegister<EventRegisterScreen> {
  @override
  void setState(VoidCallback fn) {
    markDraftDirty();
    super.setState(fn);
  }

  @override
  DraftType get draftType => DraftType.event;

  @override
  bool get draftAutoRestore => widget.autoRestoreDraft;

  @override
  String get draftTitle => _nameCtrl.text;

  @override
  String? get draftCoverImageUrl => null;

  @override
  Map<String, dynamic> buildDraftPayload() {
    return <String, dynamic>{
      'name': _nameCtrl.text,
      'description': _descCtrl.text,
      'isActive': _isActive,
      'themeTags': _themeTags.toList(),
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
      'detailAddress': _detailAddressCtrl.text,
      'isOngoing': _isOngoing,
      'startDateMs': _startDate?.millisecondsSinceEpoch,
      'endDateMs': _endDate?.millisecondsSinceEpoch,
      'hasTimeRange': _hasTimeRange,
      'startTime': DraftableRegister.timeToMap(_startTime),
      'endTime': DraftableRegister.timeToMap(_endTime),
      // 로컬 미디어 경로(최선; 파일이 사라지면 복원 시 재선택 안내).
      'mainImagePath': _mainImage?.path,
      'introImagePaths': _introImages.map((f) => f.path).toList(),
      'videoNewFilePath': _videoKey.currentState?.newVideoFile?.path,
    };
  }

  @override
  void applyDraftPayload(Map<String, dynamic> p) {
    _nameCtrl.text = (p['name'] as String?) ?? '';
    _descCtrl.text = (p['description'] as String?) ?? '';
    _detailAddressCtrl.text = (p['detailAddress'] as String?) ?? '';
    _isActive = p['isActive'] as bool? ?? true;
    _themeTags
      ..clear()
      ..addAll((p['themeTags'] as List?)?.cast<String>() ?? const []);
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
    _isOngoing = p['isOngoing'] as bool? ?? true;
    final sMs = (p['startDateMs'] as num?)?.toInt();
    final eMs = (p['endDateMs'] as num?)?.toInt();
    _startDate = sMs != null ? DateTime.fromMillisecondsSinceEpoch(sMs) : null;
    _endDate = eMs != null ? DateTime.fromMillisecondsSinceEpoch(eMs) : null;
    _hasTimeRange = p['hasTimeRange'] as bool? ?? false;
    _startTime = DraftableRegister.timeFromMap(p['startTime']);
    _endTime = DraftableRegister.timeFromMap(p['endTime']);

    // 로컬 미디어 복원(파일이 남아 있을 때만). 동영상은 SingleVideoPicker에
    // 로컬 파일을 다시 주입할 방법이 없어 항상 재선택 안내 대상이다.
    bool anyMissing = false;
    final mainPath = p['mainImagePath'] as String?;
    if (mainPath != null) {
      if (File(mainPath).existsSync()) {
        _mainImage = XFile(mainPath);
      } else {
        anyMissing = true;
      }
    }
    _introImages.clear();
    for (final path
        in (p['introImagePaths'] as List?)?.cast<String>() ?? const []) {
      if (File(path).existsSync()) {
        _introImages.add(XFile(path));
      } else {
        anyMissing = true;
      }
    }
    if ((p['videoNewFilePath'] as String?) != null) anyMissing = true;
    draftMediaNeedsReselect = anyMissing;
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_nameCtrl, _descCtrl, _detailAddressCtrl]) {
      c.addListener(markDraftDirty);
    }
    initDraft();
  }
  // ── 기본 정보 ─────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool  _isActive = true;
  // 업종이 아니라 플레이스의 특징(테마) — 다중 선택 가능(선택 안 해도 됨).
  final Set<String> _themeTags = {};

  // ── 매장 주소 (검색 기반) ─────────────────────────────────────────
  AddressResult? _selectedAddress;
  final _detailAddressCtrl = TextEditingController();

  // ── 이미지 ───────────────────────────────────────────────────────
  XFile?       _mainImage;
  final List<XFile> _introImages = [];
  final _picker = ImagePicker();

  // ── 동영상 ───────────────────────────────────────────────────────
  final _videoKey = GlobalKey<SingleVideoPickerState>();
  bool _isCompressingVideo = false;

  // ── 진행 기간 ────────────────────────────────────────────────────
  bool _isOngoing = true;
  DateTime? _startDate;
  DateTime? _endDate;

  // ── 이용 시간 (선택) ─────────────────────────────────────────────
  bool _hasTimeRange = false;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  // ── 유효성 ────────────────────────────────────────────────────────
  bool _showNameError = false;
  bool _isSubmitting  = false;

  @override
  void dispose() {
    disposeDraft();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _detailAddressCtrl.dispose();
    super.dispose();
  }

  // ── 이미지 선택 ──────────────────────────────────────────────────
  Future<void> _pickMain() async {
    final f = await _picker.pickImage(source: ImageSource.gallery);
    if (f != null && mounted) setState(() => _mainImage = f);
  }

  Future<void> _pickIntro() async {
    final remain = 6 - _introImages.length;
    if (remain <= 0) return;
    final picked = await _picker.pickMultiImage(limit: remain);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (_introImages.length < 6) _introImages.add(f);
      }
    });
  }

  // ── 기간 선택 ────────────────────────────────────────────────────
  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? now,
      firstDate: isStart ? now : (_startDate ?? now),
      lastDate: DateTime(now.year + 2),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFFFF6FA0)),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        // 종료일이 시작일보다 빠르면 함께 밀어준다.
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  // ── 이용 시간 선택 ───────────────────────────────────────────────
  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _startTime : _endTime) ?? const TimeOfDay(hour: 20, minute: 0),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFFFF6FA0)),
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

  // ── 제출 ─────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (UserSession.userId.isEmpty) { _msg('로그인이 필요합니다.'); return; }
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _showNameError = true);
      _msg('플레이스 제목을 입력해주세요.');
      return;
    }
    if (!_isOngoing && (_startDate == null || _endDate == null)) {
      _msg('진행 기간을 선택하거나 상시 진행으로 설정해주세요.');
      return;
    }
    if (_hasTimeRange && (_startTime == null || _endTime == null)) {
      _msg('이용 시간을 선택하거나 시간 지정을 꺼주세요.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      // 대표 이미지 업로드
      String mainUrl = '';
      if (_mainImage != null) {
        mainUrl = await CloudflareService.uploadImage(File(_mainImage!.path));
      }
      // 소개 이미지 업로드
      final introUrls = <String>[];
      for (final img in _introImages) {
        introUrls.add(await CloudflareService.uploadImage(File(img.path)));
      }

      // 동영상 업로드 (선택, 최대 1개)
      final videoState = _videoKey.currentState;
      String? videoUid, videoUrl, videoThumbnailUrl;
      final newVideo = videoState?.newVideoFile;
      if (newVideo != null) {
        final result = await CloudflareService.uploadVideo(File(newVideo.path));
        videoUid = result['videoUid'];
        videoUrl = result['videoUrl'];
        videoThumbnailUrl = result['videoThumbnailUrl'];
      }

      final doc = <String, dynamic>{
        'name':            _nameCtrl.text.trim(),
        'description':     _descCtrl.text.trim(),
        'themeTags':       _themeTags.toList(),
        'mainImageUrl':    mainUrl,
        'introImageUrls':  introUrls,
        if (videoUrl != null) 'videoProvider': 'cloudflare',
        if (videoUid != null) 'videoUid': videoUid,
        if (videoUrl != null) 'videoUrl': videoUrl,
        if (videoThumbnailUrl != null) 'videoThumbnailUrl': videoThumbnailUrl,
        'address':         _selectedAddress?.address ?? '',
        'roadAddress':     _selectedAddress?.roadAddress ?? '',
        'jibunAddress':    _selectedAddress?.jibunAddress ?? '',
        'latitude':        _selectedAddress?.latitude ?? 0.0,
        'longitude':       _selectedAddress?.longitude ?? 0.0,
        'detailAddress':   _detailAddressCtrl.text.trim(),
        'location':        _selectedAddress != null
            ? '${_selectedAddress!.address}'
                '${_detailAddressCtrl.text.trim().isNotEmpty ? ' ${_detailAddressCtrl.text.trim()}' : ''}'
            : '',
        'isOngoing':  _isOngoing,
        'startDate':  _isOngoing || _startDate == null
            ? null
            : Timestamp.fromDate(_startDate!),
        'endDate':    _isOngoing || _endDate == null
            ? null
            : Timestamp.fromDate(_endDate!),
        'hasTimeRange': _hasTimeRange,
        'startTime': _hasTimeRange && _startTime != null ? _fmtTime24(_startTime!) : null,
        'endTime':   _hasTimeRange && _endTime != null ? _fmtTime24(_endTime!) : null,
        'isActive':   _isActive,
        'hostId':     UserSession.userId,
        'hostName':   UserSession.displayName,
        'createdAt':  FieldValue.serverTimestamp(),
        'updatedAt':  FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('events').add(doc);

      if (!mounted) return;
      // 최종 등록 완료 — 이 유형의 임시저장은 자동 삭제.
      await deleteCurrentDraft();
      if (!mounted) return;
      // 등록 화면이 몇 단계 깊이 열려 있었든(모바일: RegisterTypeScreen 경유,
      // 데스크톱: MainScreen에서 바로) 곧장 메인화면 플레이스 탭으로 복귀한다.
      pendingTopTabAfterRegister.value = 1;
      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (_) {
      if (mounted) _msg('등록 중 오류가 발생했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _msg(String t) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));

  String _fmtDate(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  // 저장용 24시간제("HH:mm")
  String _fmtTime24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // 화면 표시용 오전/오후 표기
  String _fmtTime(TimeOfDay t) {
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    if (h == 0) return '오전 12:$m';
    if (h < 12) return '오전 $h:$m';
    if (h == 12) return '오후 12:$m';
    return '오후 ${h - 12}:$m';
  }

  // ── 빌드 ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !draftDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await confirmLeaveWithDraftSave();
        if (leave && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text('플레이스 등록',
            style: TextStyle(fontFamily: 'SeoulHangang', fontSize: 17, fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [draftSaveAction()],
        bottom: buildAutoSaveIndicator(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (draftMediaNeedsReselect) buildMediaReselectBanner(),

          // ── 1. 플레이스 제목 ─────────────────────────────────────
          _label('플레이스 제목', required: true),
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _showNameError = false),
            decoration: _deco('예: 키워드 1호점 여성 무료입장', error: _showNameError),
          ),
          const SizedBox(height: 22),

          // ── 2. 특징 태그 ─────────────────────────────────────────
          // 업종이 아니라 플레이스의 특징(테마) — 여러 개 동시에 고를 수 있다.
          _label('특징 태그 (다중 선택 가능)'),
          _buildThemeTagChips(),
          const SizedBox(height: 22),

          // ── 3. 대표 이미지 ───────────────────────────────────────
          _label('대표 이미지'),
          _buildMainImagePicker(),
          const SizedBox(height: 4),
          const Text('동영상 최대 1개 · 사진 최대 6장',
              style: TextStyle(fontSize: 11, color: Colors.black38)),
          const SizedBox(height: 22),

          // ── 3-1. 동영상 (선택) ───────────────────────────────────
          _label('동영상 (선택, 최대 1개)'),
          SingleVideoPicker(
            key: _videoKey,
            onCompressingChanged: (v) => setState(() => _isCompressingVideo = v),
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 22),

          // ── 4. 소개 이미지 ───────────────────────────────────────
          _label('소개 이미지 (최대 6장)'),
          _buildIntroImagePicker(),
          const SizedBox(height: 22),

          // ── 5. 플레이스 안내 ─────────────────────────────────────
          _label('플레이스 안내'),
          TextField(
            controller: _descCtrl,
            maxLines: 5,
            textInputAction: TextInputAction.newline,
            decoration: _deco('진행 시간대, 혜택 내용 등을 자유롭게 적어주세요.\n예: 20:00~23:00 여성 무료입장, 칵테일 1잔 무료'),
          ),
          const SizedBox(height: 22),

          // ── 6. 매장 위치 ─────────────────────────────────────────
          _label('매장 위치'),
          _buildLocationSection(),
          const SizedBox(height: 22),

          // ── 7. 진행 기간 ─────────────────────────────────────────
          _label('진행 기간'),
          _buildPeriodSection(),
          const SizedBox(height: 22),

          // ── 7-1. 이용 시간 (선택) ────────────────────────────────
          _label('이용 시간 (선택)'),
          _buildTimeRangeSection(),
          const SizedBox(height: 14),

          // ── 8. 노출 여부 ─────────────────────────────────────────
          _buildToggleRow(
            icon: Icons.visibility_outlined,
            title: '노출 중',
            desc: '플레이스를 목록에 지금 노출할지 설정해요.',
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
          ),
          const SizedBox(height: 32),

          // ── 제출 버튼 ────────────────────────────────────────────
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: (_isSubmitting || _isCompressingVideo) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6FA0),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('플레이스 등록하기',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
      ),
    );
  }

  // ── 특징 태그 칩 (다중 선택) ────────────────────────────────────────
  Widget _buildThemeTagChips() {
    return Wrap(
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
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? const Color(0xFFFF6FA0) : const Color(0xFFF7F7FA),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: sel ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
              ),
            ),
            child: Text('$emoji $c',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : Colors.black54,
                )),
          ),
        );
      }).toList(),
    );
  }

  // ── 진행 기간 섹션 ───────────────────────────────────────────────
  Widget _buildPeriodSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildToggleRow(
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
              Expanded(child: _dateBox('시작일', _startDate, () => _pickDate(isStart: true))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('~'),
              ),
              Expanded(child: _dateBox('종료일', _endDate, () => _pickDate(isStart: false))),
            ],
          ),
        ],
      ],
    );
  }

  Widget _dateBox(String label, DateTime? date, VoidCallback onTap) {
    final hasVal = date != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hasVal ? const Color(0xFFFFF0F5) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasVal ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.black38)),
            const SizedBox(height: 2),
            Text(
              hasVal ? _fmtDate(date) : '선택',
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

  // ── 이용 시간 섹션 (선택) ────────────────────────────────────────
  Widget _buildTimeRangeSection() {
    final overnight = _startTime != null &&
        _endTime != null &&
        (_endTime!.hour * 60 + _endTime!.minute) <=
            (_startTime!.hour * 60 + _startTime!.minute);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildToggleRow(
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
              Expanded(child: _timeBox('시작 시간', _startTime, () => _pickTime(isStart: true))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('~'),
              ),
              Expanded(child: _timeBox('종료 시간', _endTime, () => _pickTime(isStart: false))),
            ],
          ),
          if (overnight)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '종료가 시작보다 이르므로 익일까지로 표시돼요 (예: 22:00~08:00)',
                style: TextStyle(fontSize: 11, color: Color(0xFFFF6FA0)),
              ),
            ),
        ],
      ],
    );
  }

  Widget _timeBox(String label, TimeOfDay? time, VoidCallback onTap) {
    final hasVal = time != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hasVal ? const Color(0xFFFFF0F5) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasVal ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.black38)),
            const SizedBox(height: 2),
            Text(
              hasVal ? _fmtTime(time) : '선택',
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

  // ── 매장 위치 검색 섹션 ──────────────────────────────────────────
  Widget _buildLocationSection() {
    return Column(
      children: [
        GestureDetector(
          onTap: () async {
            final result = await Navigator.push<AddressResult>(
              context,
              webFramedRoute((_) => const AddressSearchScreen()),
            );
            if (result != null) setState(() => _selectedAddress = result);
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
                    onTap: () =>
                        setState(() => _selectedAddress = null),
                    child: const Icon(Icons.close,
                        size: 16, color: Colors.black38),
                  )
                else
                  const Icon(Icons.search,
                      size: 18, color: Colors.black38),
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

  // ── 대표 이미지 피커 ─────────────────────────────────────────────
  Widget _buildMainImagePicker() {
    if (_mainImage != null) {
      return Stack(clipBehavior: Clip.none, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(File(_mainImage!.path),
              width: double.infinity, height: 180, fit: BoxFit.cover),
        ),
        Positioned(
          top: 8, right: 8,
          child: GestureDetector(
            onTap: () => setState(() => _mainImage = null),
            child: Container(
              width: 26, height: 26,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Colors.black54),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
        Positioned(
          bottom: 8, right: 8,
          child: GestureDetector(
            onTap: _pickMain,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('변경', style: TextStyle(fontSize: 12, color: Colors.white)),
            ),
          ),
        ),
      ]);
    }
    return GestureDetector(
      onTap: _pickMain,
      child: Container(
        width: double.infinity, height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8EBF2)),
        ),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_photo_alternate_outlined, size: 32, color: Colors.black38),
          SizedBox(height: 6),
          Text('대표 이미지 추가', style: TextStyle(fontSize: 13, color: Colors.black38)),
        ]),
      ),
    );
  }

  // ── 소개 이미지 피커 ─────────────────────────────────────────────
  Widget _buildIntroImagePicker() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_introImages.isNotEmpty) ...[
        SizedBox(
          height: 104,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _introImages.length,
            itemBuilder: (_, i) => Stack(clipBehavior: Clip.none, children: [
              Container(
                margin: const EdgeInsets.only(right: 8),
                width: 100, height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  image: DecorationImage(
                      image: FileImage(File(_introImages[i].path)),
                      fit: BoxFit.cover),
                ),
              ),
              Positioned(
                top: -4, right: 4,
                child: GestureDetector(
                  onTap: () => setState(() => _introImages.removeAt(i)),
                  child: Container(
                    width: 20, height: 20,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Colors.black54),
                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (_introImages.length < 6)
        GestureDetector(
          onTap: _pickIntro,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8EBF2)),
            ),
            child: Column(children: [
              const Icon(Icons.add_a_photo_outlined, size: 28, color: Colors.black38),
              const SizedBox(height: 6),
              Text('소개 이미지 추가 (${_introImages.length}/6)',
                  style: const TextStyle(fontSize: 13, color: Colors.black38)),
            ]),
          ),
        ),
    ]);
  }

  // ── 공통 위젯 ────────────────────────────────────────────────────
  Widget _buildToggleRow({
    required IconData icon,
    required String title,
    required String desc,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8EBF2)),
        ),
        child: Row(children: [
          Icon(icon, size: 20, color: const Color(0xFFFF6FA0)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87)),
              Text(desc,
                  style: const TextStyle(fontSize: 12, color: Colors.black45)),
            ]),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFFFF6FA0),
            activeTrackColor: const Color(0xFFFFB8D0),
          ),
        ]),
      );

  Widget _label(String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Text(text,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87)),
          if (required)
            const Text(' *',
                style: TextStyle(
                    fontSize: 14, color: Color(0xFFFF6FA0), fontWeight: FontWeight.bold)),
        ]),
      );

  InputDecoration _deco(String hint, {String? suffix, bool error = false}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
        suffixText: suffix,
        suffixStyle: const TextStyle(color: Colors.black45, fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: error ? Colors.redAccent : const Color(0xFFE8EBF2))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: error ? Colors.redAccent : const Color(0xFFE8EBF2))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFF6FA0))),
      );
}
