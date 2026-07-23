import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:party_app/models/address_result.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/screens/address_search_screen.dart';
import 'package:party_app/screens/party_media_picker_screen.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/utils/register_return_signal.dart';
import 'package:party_app/widgets/party_form/party_title_field.dart';
import 'package:party_app/widgets/party_media_editor.dart' show PartyCoverPick;
import 'package:party_app/widgets/place_form/room_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 장소 등록 화면
// ─────────────────────────────────────────────────────────────────────────────

class PlaceRegisterScreen extends StatefulWidget {
  const PlaceRegisterScreen({super.key});

  @override
  State<PlaceRegisterScreen> createState() => _PlaceRegisterScreenState();
}

class _PlaceRegisterScreenState extends State<PlaceRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();

  // 섹션별 스크롤 앵커
  final _basicInfoKey = GlobalKey();
  final _photosKey = GlobalKey();
  final _roomsKey = GlobalKey();

  // 기본 장소 정보
  final _nameCtrl = PartyTitleController();
  final _detailAddressCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  AddressResult? _selectedAddress;

  // ── 사진/동영상 미디어 — 파티 등록과 동일한 공용 위젯(PartyMediaEditor/
  // PartyMediaPickerScreen)을 그대로 재사용한다. 장소 등록은 신규 생성만
  // 지원하므로 existing* 필드는 항상 빈 값으로 시작한다.
  List<String> _mediaExistingImageUrls = [];
  String? _mediaExistingVideoUrl;
  String? _mediaExistingVideoUid;
  String? _mediaExistingVideoThumbnailUrl;
  List<XFile> _mediaNewFiles = [];
  PartyCoverPick? _mediaCoverPick;

  // 인라인 에러 플래그
  bool _showAddressError = false;
  bool _showImageError = false;
  bool _showRoomError = false;

  // 장소 유형 (상세검색에서 필터링 가능하도록 등록 시점에 선택)
  String _placeType = ListingConstants.placeTypes.first;

  // 공용 편의시설 (프리셋 선택)
  final Set<String> _commonFacilities = {};
  // 공용 편의시설 (직접 입력)
  final Set<String> _customCommonFacilities = {};
  final _customFacilityCtrl = TextEditingController();
  bool _showCustomFacilityInput = false;

  static const _commonFacilityOptions = ListingConstants.placeFacilities;

  // 장소 전체 운영 시간
  TimeOfDay? _placeOpenTime;
  TimeOfDay? _placeCloseTime;
  bool _placeIsOpen24Hours = false;

  // 정산 계좌
  final _bankCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();

  // 예약자 자동발송 문구
  final _autoMsgCtrl = TextEditingController();

  // 룸 목록 (GlobalKey로 각 룸의 state에 접근)
  final List<GlobalKey<RoomCardState>> _roomKeys = [];

  // 업로드 상태 — Stack 오버레이 방식으로 표시 (Form 위젯을 트리에 유지)
  bool _isUploading = false;
  String _uploadStatus = '';

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _nameCtrl.dispose();
    _detailAddressCtrl.dispose();
    _descCtrl.dispose();
    _bankCtrl.dispose();
    _accountCtrl.dispose();
    _holderCtrl.dispose();
    _customFacilityCtrl.dispose();
    _autoMsgCtrl.dispose();
    super.dispose();
  }

  void _addRoom() => setState(() {
    _roomKeys.add(GlobalKey<RoomCardState>());
    _showRoomError = false;
  });

  void _removeRoom(int index) => setState(() => _roomKeys.removeAt(index));

  bool _isVideoFile(XFile f) {
    final p = f.path.toLowerCase();
    return p.endsWith('.mp4') || p.endsWith('.mov');
  }

  bool get _mediaHasVideo =>
      _mediaExistingVideoUrl != null || _mediaNewFiles.any(_isVideoFile);

  String? _mediaSummary() {
    final photoCount =
        _mediaExistingImageUrls.length +
        _mediaNewFiles.where((f) => !_isVideoFile(f)).length;
    final parts = <String>[];
    if (photoCount > 0) parts.add('사진 $photoCount장');
    if (_mediaHasVideo) parts.add('동영상 1개');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  // 파티 등록과 동일한 공용 미디어 편집 화면(PartyMediaEditor)을 그대로
  // 재사용한다 — 사진 여러 장 + 동영상 1개, 대표 미디어 선택까지 동일하게
  // 지원된다. 장소에는 배경음악(Spotify) 개념이 없으므로 그 섹션만 끈다.
  Future<void> _openMediaPicker() async {
    final result = await Navigator.push<PartyMediaSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => PartyMediaPickerScreen(
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

  // 첫 번째 오류 섹션으로 스크롤
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

  Future<void> _save() async {
    // ── 1. 전체 필수값 검증 (저장 전에 모두 확인) ─────────────────────
    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();

    debugPrint('─── [장소 등록] 필드 검증 시작 ───');
    debugPrint('  name       : "$name"');
    debugPrint('  address    : ${_selectedAddress?.roadAddress ?? "null"}');
    debugPrint(
      '  lat/lng    : ${_selectedAddress?.latitude} / ${_selectedAddress?.longitude}',
    );
    debugPrint('  desc len   : ${desc.length}');
    debugPrint(
      '  mediaCount : photos=${_mediaExistingImageUrls.length + _mediaNewFiles.where((f) => !_isVideoFile(f)).length} '
      'video=${_mediaHasVideo ? 1 : 0}',
    );
    debugPrint('  roomCount  : ${_roomKeys.length}');
    debugPrint(
      '  uid        : ${FirebaseAuth.instance.currentUser?.uid ?? "null"}',
    );

    bool hasError = false;
    GlobalKey? firstErrorKey;

    // Form 필드 (이름·설명) 유효성 — validator 호출
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid) {
      hasError = true;
      firstErrorKey ??= _basicInfoKey;
      debugPrint('  ❌ Form validation failed (이름 또는 설명 미입력)');
    }

    // 주소 선택 여부
    if (_selectedAddress == null) {
      setState(() => _showAddressError = true);
      hasError = true;
      firstErrorKey ??= _basicInfoKey;
      debugPrint('  ❌ 주소 미선택');
    }

    // 대표 사진/동영상 (최소 1개)
    if (_mediaExistingImageUrls.isEmpty && _mediaNewFiles.isEmpty) {
      setState(() => _showImageError = true);
      hasError = true;
      firstErrorKey ??= _photosKey;
      debugPrint('  ❌ 사진/동영상 없음 (최소 1개 필요)');
    }

    // 룸 존재 여부
    if (_roomKeys.isEmpty) {
      setState(() => _showRoomError = true);
      hasError = true;
      firstErrorKey ??= _roomsKey;
      debugPrint('  ❌ 룸 없음 (최소 1개 필요)');
    }

    if (hasError) {
      _scrollToKey(firstErrorKey!);
      return;
    }

    // 룸별 개별 유효성 검사
    bool roomsValid = true;
    for (int i = 0; i < _roomKeys.length; i++) {
      final state = _roomKeys[i].currentState;
      if (state == null) {
        debugPrint('  ❌ 룸[$i] currentState == null');
        roomsValid = false;
        continue;
      }
      if (!state.validate()) {
        debugPrint('  ❌ 룸[$i] 필수항목 미입력');
        roomsValid = false;
      }
    }
    if (!roomsValid) {
      _scrollToKey(_roomsKey);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('  ❌ uid == null — 로그인 필요');
      _msg('로그인이 필요합니다');
      return;
    }

    debugPrint('  ✅ 검증 통과 — 업로드 시작');

    // ── 2. 업로드 (Stack 오버레이 — Form·RoomCard 위젯을 트리에 유지) ──
    // _isUploading = true 여도 Scaffold body 가 교체되지 않으므로
    // _roomKeys[i].currentState 는 절대 null 이 되지 않음.
    setState(() {
      _isUploading = true;
      _uploadStatus = '장소 사진 업로드 중...';
    });

    try {
      // 장소 사진/동영상 업로드 — 파티 등록과 동일한 방식(사진 여러 장 +
      // 동영상 1개, 압축·30초 제한은 PartyMediaEditor에서 이미 처리됨).
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
            () => _uploadStatus = '장소 사진 업로드 중... ($done/${newMedia.length})',
          );
          newImageUrls.add(
            await CloudflareService.uploadImage(File(file.path)),
          );
        }
      }

      final imageUrls = [..._mediaExistingImageUrls, ...newImageUrls];
      final finalVideoUrl = newVideoUrl ?? _mediaExistingVideoUrl;
      final finalVideoUid = newVideoUid ?? _mediaExistingVideoUid;
      final finalVideoThumbnailUrl =
          newVideoThumbnailUrl ?? _mediaExistingVideoThumbnailUrl;

      // 대표 미디어 — 사용자가 명시적으로 골랐으면 그 값을 그대로 신뢰하고,
      // 고르지 않았다면(coverPick == null) 첫 번째 업로드 미디어를 기본값으로
      // 쓴다(이미지가 있으면 이미지 우선, 없으면 동영상) — 파티 등록과 동일.
      final coverPick = _mediaCoverPick;
      String coverMediaType = 'image';
      String? coverImageUrl;
      String? coverVideoUid;
      String? coverVideoUrl;
      String? coverThumbnailUrl;
      if (coverPick?.isExistingVideo == true || coverPick?.isNewVideo == true) {
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

      // 대표로 고른 사진을 실제 저장 배열의 맨 앞(index 0)으로 재정렬한다 —
      // 상세페이지 갤러리가 항상 index 0부터 열리므로, 저장 순서 자체를
      // 바꿔야 대표 미디어가 첫 화면에 온다(파티 등록과 동일한 규칙).
      if (coverMediaType == 'image' && coverImageUrl != null) {
        imageUrls.remove(coverImageUrl);
        imageUrls.insert(0, coverImageUrl);
      }

      // 룸 데이터 먼저 수집(이미지 업로드 포함) — 장소 문서에 최저가/최대인원을
      // 집계해 넣기 위해 placeRef.set() 보다 먼저 수행한다.
      final placeRef = FirebaseFirestore.instance.collection('places').doc();
      final roomDataList = <Map<String, dynamic>>[];
      for (int i = 0; i < _roomKeys.length; i++) {
        setState(
          () => _uploadStatus = '룸 ${i + 1}/${_roomKeys.length} 정보 준비 중...',
        );
        final state = _roomKeys[i].currentState;
        if (state == null) {
          throw Exception('룸[$i] state == null — 예상치 못한 위젯 트리 제거');
        }
        roomDataList.add(await state.uploadAndGetData(uid, placeRef.id));
      }

      // 상세검색용 집계값 — 룸별 최저 시간당 가격 / 최대 수용 인원
      final prices = roomDataList
          .map((r) => (r['pricePerHour'] as num?)?.toInt() ?? 0)
          .where((p) => p > 0);
      final capacities = roomDataList
          .map((r) => (r['capacityMax'] as num?)?.toInt() ?? 0)
          .where((c) => c > 0);
      final minPrice = prices.isEmpty
          ? 0
          : prices.reduce((a, b) => a < b ? a : b);
      final maxCapacity = capacities.isEmpty
          ? 0
          : capacities.reduce((a, b) => a > b ? a : b);

      setState(() => _uploadStatus = '장소 정보 저장 중...');

      // 장소 문서 생성
      await placeRef.set({
        'hostId': uid,
        'name': name,
        'type': _placeType,
        'address': _selectedAddress?.roadAddress ?? '',
        'detailAddress': _detailAddressCtrl.text.trim(),
        'lat': _selectedAddress?.latitude ?? 0.0,
        'lng': _selectedAddress?.longitude ?? 0.0,
        'imageUrls': imageUrls,
        if (finalVideoUrl != null) 'videoProvider': 'cloudflare',
        if (finalVideoUid != null) 'videoUid': finalVideoUid,
        if (finalVideoUrl != null) 'videoUrl': finalVideoUrl,
        if (finalVideoThumbnailUrl != null)
          'videoThumbnailUrl': finalVideoThumbnailUrl,
        // 대표 미디어 — 등록자가 직접 고른 사진/동영상(파티와 동일한 필드
        // 형태). 기존 장소 데이터에는 이 필드들이 없으므로, 읽는 쪽
        // (getPartyCoverMedia)이 imageUrls.first로 폴백해 하위호환된다.
        'coverMediaType': coverMediaType,
        'coverImageUrl': coverImageUrl,
        'coverVideoUid': coverVideoUid,
        'coverVideoUrl': coverVideoUrl,
        'coverThumbnailUrl': coverThumbnailUrl,
        'description': desc,
        'commonFacilities': {
          ..._commonFacilities,
          ..._customCommonFacilities,
        }.toList(),
        // 룸별 최저가/최대인원 집계 — 상세검색(가격범위/수용인원) 필터에 사용
        'pricePerHour': minPrice,
        'capacityMax': maxCapacity,
        'payoutAccount': {
          'bank': _bankCtrl.text.trim(),
          'accountNumber': _accountCtrl.text.trim(),
          'accountHolder': _holderCtrl.text.trim(),
        },
        'autoMessage': _autoMsgCtrl.text.trim(),
        'isActive': true,
        if (_placeIsOpen24Hours) ...{
          'openTime': '00:00',
          'closeTime': '24:00',
          'isOpen24Hours': true,
        } else if (_placeOpenTime != null && _placeCloseTime != null) ...{
          'openTime': _fmtPlaceTime(_placeOpenTime!),
          'closeTime': _fmtPlaceTime(_placeCloseTime!),
          'isOpen24Hours': false,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 룸 문서 생성
      for (int i = 0; i < roomDataList.length; i++) {
        setState(
          () => _uploadStatus = '룸 ${i + 1}/${roomDataList.length} 등록 중...',
        );
        await FirebaseFirestore.instance
            .collection('placeRooms')
            .add(roomDataList[i]);
      }

      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _uploadStatus = '';
      });

      // ── 3. 성공 다이얼로그 ───────────────────────────────────────────
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF7C5CBF)),
              SizedBox(width: 8),
              Text('등록 완료', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
            ],
          ),
          content: const Text(
            '장소가 성공적으로 등록되었습니다.',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C5CBF),
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
      // 등록 화면이 몇 단계 깊이 열려 있었든(모바일: RegisterTypeScreen 경유,
      // 데스크톱: MainScreen에서 바로) 곧장 메인화면 장소대여 탭으로 복귀한다.
      pendingTopTabAfterRegister.value = 2;
      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e, st) {
      debugPrint('❌ 장소 등록 실패: $e');
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

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );

  // 장소 운영 시간 헬퍼
  String _fmtPlaceTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtPlaceTimeDisplay(TimeOfDay t) {
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    if (h == 0) return '오전 12:$m';
    if (h < 12) return '오전 $h:$m';
    if (h == 12) return '오후 12:$m';
    return '오후 ${h - 12}:$m';
  }

  Future<void> _pickPlaceTime(bool isOpen) async {
    final current = isOpen ? _placeOpenTime : _placeCloseTime;
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
        _placeOpenTime = picked;
      } else {
        _placeCloseTime = picked;
      }
    });
  }

  // ── UI 헬퍼 ──────────────────────────────────────────────────────────────

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF7F7FA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 16),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );

  Widget _sectionCard({required String title, required Widget child}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
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
            child,
          ],
        ),
      );

  // ── 빌드 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Stack 오버레이 방식 — _isUploading 중에도 Form·RoomCard 를 트리에 유지
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          appBar: AppBar(
            title: const Text('파티 장소 등록', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
            centerTitle: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              children: [
                // 섹션 앵커 — 오류 발생 시 스크롤 대상
                SizedBox(key: _basicInfoKey, height: 0),
                _buildBasicInfo(),
                _buildPlaceType(),
                SizedBox(key: _photosKey, height: 0),
                _buildPhotos(),
                _buildDescription(),
                _buildPlaceHours(),
                _buildCommonFacilities(),
                SizedBox(key: _roomsKey, height: 0),
                _buildRoomsSection(),
                _buildPayoutAccount(),
                _buildAutoMessageSection(),
                const SizedBox(height: 8),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isUploading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C5CBF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: const Text('장소 등록하기'),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),

        // 업로드 중 반투명 오버레이
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
                  Text(
                    _uploadStatus,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── 섹션 빌드 ─────────────────────────────────────────────────────────────

  Widget _buildBasicInfo() => _sectionCard(
    title: '기본 정보',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('장소명 *'),
        PartyTitleField(
          controller: _nameCtrl,
          decoration: _inputDeco('예: 한강뷰 루프탑 파티룸'),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? '장소명을 입력해주세요' : null,
        ),
        _label('주소 *'),
        GestureDetector(
          onTap: () async {
            final result = await Navigator.push<AddressResult>(
              context,
              MaterialPageRoute(builder: (_) => const AddressSearchScreen()),
            );
            if (result != null) {
              setState(() {
                _selectedAddress = result;
                _showAddressError = false;
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                Icon(
                  Icons.search,
                  size: 18,
                  color: _showAddressError
                      ? Colors.redAccent
                      : const Color(0xFFFF6FA0),
                ),
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
            child: Text(
              '주소를 검색해주세요',
              style: TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
          ),
        _label('상세주소'),
        TextFormField(
          controller: _detailAddressCtrl,
          decoration: _inputDeco('동/호수, 층수 등'),
        ),
      ],
    ),
  );

  Widget _buildPlaceType() => _sectionCard(
    title: '장소 유형',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('상세검색에서 노출될 장소 유형을 선택해주세요'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ListingConstants.placeTypes.map((t) {
            final sel = _placeType == t;
            return GestureDetector(
              onTap: () => setState(() => _placeType = t),
              child: _facilityChip(t, selected: sel),
            );
          }).toList(),
        ),
      ],
    ),
  );

  // 파티 등록과 동일한 공용 미디어 편집 화면(PartyMediaEditor)을 재사용한다 —
  // 사진 여러 장 + 동영상 1개(길이/용량 제한·압축 동일), 대표 미디어 선택(핑크
  // 테두리·체크·'대표' 배지)까지 동일하게 지원된다.
  Widget _buildPhotos() => _sectionCard(
    title: '장소 대표 사진·동영상',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('사진 최대 10장 · 동영상 1개(최대 30초) *'),
        if (_mediaSummary() != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _mediaSummary()!,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _openMediaPicker,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: Text(_mediaSummary() == null ? '사진/동영상 등록' : '사진/동영상 수정'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _showImageError
                ? Colors.redAccent
                : const Color(0xFF7C5CBF),
            side: BorderSide(
              color: _showImageError
                  ? Colors.redAccent
                  : const Color(0xFF7C5CBF),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        if (_showImageError)
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 4),
            child: Text(
              '대표 사진 또는 동영상을 최소 1개 등록해주세요',
              style: TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
          ),
      ],
    ),
  );

  Widget _buildDescription() => _sectionCard(
    title: '장소 소개',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('장소 설명 *'),
        TextFormField(
          controller: _descCtrl,
          maxLines: 5,
          decoration: _inputDeco('장소의 특징, 분위기, 접근 방법 등을 소개해주세요'),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? '장소 설명을 입력해주세요' : null,
        ),
      ],
    ),
  );

  Widget _buildCommonFacilities() => _sectionCard(
    title: '공용 편의시설',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('전체 장소에 해당하는 시설을 선택해주세요'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // ── 프리셋 옵션 칩 ──────────────────────────────────
            ..._commonFacilityOptions.map((f) {
              final selected = _commonFacilities.contains(f);
              return GestureDetector(
                onTap: () => setState(() {
                  if (selected) {
                    _commonFacilities.remove(f);
                  } else {
                    _commonFacilities.add(f);
                  }
                }),
                child: _facilityChip(f, selected: selected),
              );
            }),
            // ── 직접 입력한 항목 칩 (삭제 버튼 포함) ──────────
            ..._customCommonFacilities.map(
              (f) => _customChip(
                f,
                onDelete: () =>
                    setState(() => _customCommonFacilities.remove(f)),
              ),
            ),
            // ── 직접 입력 버튼 ──────────────────────────────────
            GestureDetector(
              onTap: () => setState(() => _showCustomFacilityInput = true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7FA),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFDDE1EC),
                    style: BorderStyle.solid,
                  ),
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
        // ── 인라인 입력 필드 ────────────────────────────────────
        if (_showCustomFacilityInput) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customFacilityCtrl,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: '편의시설 이름 입력 (예: 루프탑, 수영장)',
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
                  onSubmitted: (_) => _addCustomFacility(),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _addCustomFacility,
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
                onPressed: () => setState(() {
                  _showCustomFacilityInput = false;
                  _customFacilityCtrl.clear();
                }),
                tooltip: '취소',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  void _addCustomFacility() {
    final text = _customFacilityCtrl.text.trim();
    if (text.isEmpty) return;
    // 이미 프리셋에 있는 값이면 프리셋 선택으로 처리
    if (_commonFacilityOptions.contains(text)) {
      setState(() {
        _commonFacilities.add(text);
        _customFacilityCtrl.clear();
        _showCustomFacilityInput = false;
      });
      return;
    }
    setState(() {
      _customCommonFacilities.add(text);
      _customFacilityCtrl.clear();
      _showCustomFacilityInput = false;
    });
  }

  Widget _facilityChip(String label, {required bool selected}) => Container(
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
        color: selected ? const Color(0xFF7C5CBF) : Colors.black54,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
    ),
  );

  Widget _customChip(String label, {required VoidCallback onDelete}) =>
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

  Widget _buildRoomsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 룸 카드들
        ...List.generate(
          _roomKeys.length,
          (i) => RoomCard(
            key: _roomKeys[i],
            index: i,
            onRemove: () => _removeRoom(i),
            getPreviousData: i > 0
                ? () => _roomKeys[i - 1].currentState?.getRoomData()
                : null,
          ),
        ),

        // 룸 추가 버튼
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: OutlinedButton.icon(
            onPressed: _addRoom,
            icon: const Icon(Icons.add_circle_outline, size: 20),
            label: Text(
              _roomKeys.isEmpty ? '룸 추가하기' : '룸 추가하기 (${_roomKeys.length}개)',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF7C5CBF),
              side: const BorderSide(color: Color(0xFF7C5CBF), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        if (_roomKeys.isEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _showRoomError
                  ? const Color(0xFFFFF0F0)
                  : const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _showRoomError
                    ? Colors.redAccent
                    : const Color(0xFFFFE082),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _showRoomError ? Icons.error_outline : Icons.info_outline,
                  size: 16,
                  color: _showRoomError
                      ? Colors.redAccent
                      : const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _showRoomError
                        ? '룸을 최소 1개 이상 추가해주세요.'
                        : '룸을 1개 이상 추가해야 장소를 등록할 수 있습니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: _showRoomError
                          ? Colors.redAccent
                          : const Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceHours() => _sectionCard(
    title: '장소 운영 시간',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            '장소 전체 기본 운영 시간입니다. 룸별로 다른 시간이 있으면 룸에서 직접 설정하세요.',
            style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.5),
          ),
        ),
        // 24시간 운영 체크박스
        Row(
          children: [
            Checkbox(
              value: _placeIsOpen24Hours,
              onChanged: (v) =>
                  setState(() => _placeIsOpen24Hours = v ?? false),
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
        if (!_placeIsOpen24Hours) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: _placeTimePicker(isOpen: true)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('~', style: TextStyle(fontSize: 16)),
              ),
              Expanded(child: _placeTimePicker(isOpen: false)),
            ],
          ),
        ] else ...[
          Container(
            margin: const EdgeInsets.only(top: 4),
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
      ],
    ),
  );

  Widget _placeTimePicker({required bool isOpen}) {
    final time = isOpen ? _placeOpenTime : _placeCloseTime;
    final hasTime = time != null;
    return GestureDetector(
      onTap: () => _pickPlaceTime(isOpen),
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
                  hasTime ? _fmtPlaceTimeDisplay(time) : '선택하세요',
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

  Widget _buildAutoMessageSection() => _sectionCard(
    title: '예약자 자동 안내 문구',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.notifications_outlined,
              size: 14,
              color: Color(0xFF7C5CBF),
            ),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                '예약 시간 2시간 전에 예약자에게 자동으로 발송돼요.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7C5CBF)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _autoMsgCtrl,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: '예: 안녕하세요! 예약해주셔서 감사합니다.\n오늘 이용 시 준비물 안내드립니다...',
            hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE8EBF2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE8EBF2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF7C5CBF)),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildPayoutAccount() => _sectionCard(
    title: '호스트 정산 계좌',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            '결제 수수료 정산에 사용되는 계좌입니다.\n정확하게 입력해주세요.',
            style: TextStyle(fontSize: 13, color: Colors.black45, height: 1.5),
          ),
        ),
        _label('은행명'),
        TextFormField(
          controller: _bankCtrl,
          decoration: _inputDeco('예: 카카오뱅크'),
        ),
        _label('계좌번호'),
        TextFormField(
          controller: _accountCtrl,
          keyboardType: TextInputType.number,
          decoration: _inputDeco('숫자만 입력'),
        ),
        _label('예금주'),
        TextFormField(
          controller: _holderCtrl,
          decoration: _inputDeco('예금주 이름'),
        ),
      ],
    ),
  );
}
