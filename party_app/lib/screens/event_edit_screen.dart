import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/models/address_result.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/screens/address_search_screen.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/widgets/single_video_picker.dart';
import 'package:party_app/widgets/web_frame.dart';

class EventEditScreen extends StatefulWidget {
  final String eventId;
  final Map<String, dynamic> data;

  const EventEditScreen({super.key, required this.eventId, required this.data});

  @override
  State<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends State<EventEditScreen> {
  // ── 기본 정보 ─────────────────────────────────────────────────────
  late final _nameCtrl = TextEditingController(text: widget.data['name'] as String? ?? '');
  late final _descCtrl = TextEditingController(text: widget.data['description'] as String? ?? '');
  late bool  _isActive = widget.data['isActive'] as bool? ?? true;
  // 업종이 아니라 플레이스의 특징(테마) — 다중 선택. 예전에 단일 'category'로
  // 등록된 문서는 그 값을 태그 하나짜리 집합으로 취급해 하위호환한다.
  late final Set<String> _themeTags = () {
    final tags = (widget.data['themeTags'] as List?)?.cast<String>();
    if (tags != null && tags.isNotEmpty) return Set<String>.from(tags);
    final legacy = widget.data['category'] as String?;
    return legacy != null && legacy.isNotEmpty ? {legacy} : <String>{};
  }();

  // ── 매장 주소 ─────────────────────────────────────────────────────
  AddressResult? _selectedAddress;
  late String _existingAddress = widget.data['address'] as String? ?? '';
  late final _detailAddressCtrl =
      TextEditingController(text: widget.data['detailAddress'] as String? ?? '');

  // ── 이미지 ───────────────────────────────────────────────────────
  String? _existingMainImageUrl;
  XFile? _newMainImage;
  late final List<String> _existingIntroImageUrls =
      (widget.data['introImageUrls'] as List?)?.cast<String>().toList() ?? [];
  final List<XFile> _newIntroImages = [];
  final _picker = ImagePicker();

  // ── 동영상 ───────────────────────────────────────────────────────
  final _videoKey = GlobalKey<SingleVideoPickerState>();
  bool _isCompressingVideo = false;

  // ── 진행 기간 ────────────────────────────────────────────────────
  late bool _isOngoing = widget.data['isOngoing'] as bool? ?? true;
  DateTime? _startDate;
  DateTime? _endDate;

  // ── 이용 시간 (선택) ─────────────────────────────────────────────
  late bool _hasTimeRange = widget.data['hasTimeRange'] as bool? ?? false;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  // ── 유효성 ────────────────────────────────────────────────────────
  bool _showNameError = false;
  bool _isSubmitting  = false;

  @override
  void initState() {
    super.initState();
    _existingMainImageUrl = widget.data['mainImageUrl'] as String?;
    if (_existingMainImageUrl?.isEmpty == true) _existingMainImageUrl = null;
    final start = widget.data['startDate'] as Timestamp?;
    final end = widget.data['endDate'] as Timestamp?;
    _startDate = start?.toDate();
    _endDate = end?.toDate();
    _startTime = _parseTime24(widget.data['startTime'] as String?);
    _endTime = _parseTime24(widget.data['endTime'] as String?);
  }

  TimeOfDay? _parseTime24(String? s) {
    if (s == null || !s.contains(':')) return null;
    final p = s.split(':');
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _detailAddressCtrl.dispose();
    super.dispose();
  }

  // ── 이미지 선택 ──────────────────────────────────────────────────
  Future<void> _pickMain() async {
    final f = await _picker.pickImage(source: ImageSource.gallery);
    if (f != null && mounted) {
      setState(() {
        _newMainImage = f;
        _existingMainImageUrl = null;
      });
    }
  }

  Future<void> _pickIntro() async {
    final remain = 6 - _existingIntroImageUrls.length - _newIntroImages.length;
    if (remain <= 0) return;
    final picked = await _picker.pickMultiImage(limit: remain);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (_existingIntroImageUrls.length + _newIntroImages.length < 6) {
          _newIntroImages.add(f);
        }
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
      String mainUrl = _existingMainImageUrl ?? '';
      if (_newMainImage != null) {
        mainUrl = await CloudflareService.uploadImage(File(_newMainImage!.path));
      }
      final introUrls = [..._existingIntroImageUrls];
      for (final img in _newIntroImages) {
        introUrls.add(await CloudflareService.uploadImage(File(img.path)));
      }

      // 동영상 — 새로 고른 파일이 있으면 업로드, 없으면 기존 값을 그대로
      // 유지(혹은 사용자가 지웠으면 null로 남아 아래서 필드를 삭제한다).
      final videoState = _videoKey.currentState;
      String? videoUid = videoState?.existingVideoUid;
      String? videoUrl = videoState?.existingVideoUrl;
      String? videoThumbnailUrl = videoState?.existingVideoThumbnailUrl;
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
        // 예전 단일 카테고리 필드는 새 다중 태그로 완전히 대체한다.
        'category':        FieldValue.delete(),
        'mainImageUrl':    mainUrl,
        'introImageUrls':  introUrls,
        'videoProvider':      videoUrl != null ? 'cloudflare' : FieldValue.delete(),
        'videoUid':           videoUid ?? FieldValue.delete(),
        'videoUrl':           videoUrl ?? FieldValue.delete(),
        'videoThumbnailUrl':  videoThumbnailUrl ?? FieldValue.delete(),
        'detailAddress':   _detailAddressCtrl.text.trim(),
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
        'updatedAt':  FieldValue.serverTimestamp(),
      };
      if (_selectedAddress != null) {
        doc['address'] = _selectedAddress!.address;
        doc['roadAddress'] = _selectedAddress!.roadAddress;
        doc['jibunAddress'] = _selectedAddress!.jibunAddress;
        doc['latitude'] = _selectedAddress!.latitude;
        doc['longitude'] = _selectedAddress!.longitude;
        doc['location'] =
            '${_selectedAddress!.address}'
            '${_detailAddressCtrl.text.trim().isNotEmpty ? ' ${_detailAddressCtrl.text.trim()}' : ''}';
      }

      await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .update(doc);

      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (mounted) _msg('수정 중 오류가 발생했습니다. 다시 시도해주세요.');
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
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text('플레이스 수정',
            style: TextStyle(fontFamily: 'SeoulHangang', fontSize: 17, fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          _label('플레이스 제목', required: true),
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _showNameError = false),
            decoration: _deco('예: 키워드 1호점 여성 무료입장', error: _showNameError),
          ),
          const SizedBox(height: 22),

          _label('특징 태그 (다중 선택 가능)'),
          _buildThemeTagChips(),
          const SizedBox(height: 22),

          _label('대표 이미지'),
          _buildMainImagePicker(),
          const SizedBox(height: 4),
          const Text('동영상 최대 1개 · 사진 최대 6장',
              style: TextStyle(fontSize: 11, color: Colors.black38)),
          const SizedBox(height: 22),

          _label('동영상 (선택, 최대 1개)'),
          SingleVideoPicker(
            key: _videoKey,
            initialVideoUrl: widget.data['videoUrl'] as String?,
            initialVideoUid: widget.data['videoUid'] as String?,
            initialVideoThumbnailUrl: widget.data['videoThumbnailUrl'] as String?,
            onCompressingChanged: (v) => setState(() => _isCompressingVideo = v),
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 22),

          _label('소개 이미지 (최대 6장)'),
          _buildIntroImagePicker(),
          const SizedBox(height: 22),

          _label('플레이스 안내'),
          TextField(
            controller: _descCtrl,
            maxLines: 5,
            textInputAction: TextInputAction.newline,
            decoration: _deco('진행 시간대, 혜택 내용 등을 자유롭게 적어주세요.'),
          ),
          const SizedBox(height: 22),

          _label('매장 위치'),
          _buildLocationSection(),
          const SizedBox(height: 22),

          _label('진행 기간'),
          _buildPeriodSection(),
          const SizedBox(height: 22),

          _label('이용 시간 (선택)'),
          _buildTimeRangeSection(),
          const SizedBox(height: 14),

          _buildToggleRow(
            icon: Icons.visibility_outlined,
            title: '노출 중',
            desc: '플레이스를 목록에 지금 노출할지 설정해요.',
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
          ),
          const SizedBox(height: 32),

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
                  : const Text('수정 완료',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }

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

  Widget _buildLocationSection() {
    final displayAddress = _selectedAddress?.address ?? _existingAddress;
    final hasAddress = displayAddress.isNotEmpty;
    return Column(
      children: [
        GestureDetector(
          onTap: () async {
            final result = await Navigator.push<AddressResult>(
              context,
              webFramedRoute((_) => const AddressSearchScreen()),
            );
            if (result != null) {
              setState(() {
                _selectedAddress = result;
                _existingAddress = result.address;
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: hasAddress ? const Color(0xFFFFF0F5) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasAddress ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: hasAddress ? const Color(0xFFFF6FA0) : Colors.black38,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasAddress ? displayAddress : '주소 검색',
                    style: TextStyle(
                      fontSize: 14,
                      color: hasAddress ? Colors.black87 : Colors.black38,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.search, size: 18, color: Colors.black38),
              ],
            ),
          ),
        ),
        if (hasAddress) ...[
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

  Widget _buildMainImagePicker() {
    final hasExisting = _existingMainImageUrl != null;
    if (_newMainImage != null || hasExisting) {
      return Stack(clipBehavior: Clip.none, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _newMainImage != null
              ? Image.file(File(_newMainImage!.path),
                  width: double.infinity, height: 180, fit: BoxFit.cover)
              : Image.network(_existingMainImageUrl!,
                  width: double.infinity, height: 180, fit: BoxFit.cover),
        ),
        Positioned(
          top: 8, right: 8,
          child: GestureDetector(
            onTap: () => setState(() {
              _newMainImage = null;
              _existingMainImageUrl = null;
            }),
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

  Widget _buildIntroImagePicker() {
    final total = _existingIntroImageUrls.length + _newIntroImages.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (total > 0) ...[
        SizedBox(
          height: 104,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ..._existingIntroImageUrls.asMap().entries.map((e) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          image: DecorationImage(
                              image: NetworkImage(e.value), fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        top: -4, right: 4,
                        child: GestureDetector(
                          onTap: () => setState(
                              () => _existingIntroImageUrls.removeAt(e.key)),
                          child: Container(
                            width: 20, height: 20,
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle, color: Colors.black54),
                            child: const Icon(Icons.close, size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  )),
              ..._newIntroImages.asMap().entries.map((e) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          image: DecorationImage(
                              image: FileImage(File(e.value.path)), fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        top: -4, right: 4,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _newIntroImages.removeAt(e.key)),
                          child: Container(
                            width: 20, height: 20,
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle, color: Colors.black54),
                            child: const Icon(Icons.close, size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  )),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (total < 6)
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
              Text('소개 이미지 추가 ($total/6)',
                  style: const TextStyle(fontSize: 13, color: Colors.black38)),
            ]),
          ),
        ),
    ]);
  }

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
