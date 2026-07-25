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
import 'package:party_app/widgets/party_form/party_title_field.dart';
import 'package:party_app/widgets/party_media_editor.dart' show PartyCoverPick;
import 'package:party_app/widgets/place_form/room_card.dart';
import 'package:party_app/widgets/web_frame.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 장소 수정 화면 — 진행중 상태에서 "수정"으로 열 때도, 숨김 상태에서
// "재등록"으로 열 때도 이 화면 하나를 그대로 재사용한다. 저장하면 항상
// isActive:true로 돌아오므로(숨김 상태였다면 재등록, 진행중이었다면 그대로
// 진행중 유지) 별도의 "재등록 모드" 분기가 필요 없다.
// ─────────────────────────────────────────────────────────────────────────────

class PlaceEditScreen extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;

  const PlaceEditScreen({super.key, required this.docId, required this.data});

  @override
  State<PlaceEditScreen> createState() => _PlaceEditScreenState();
}

class _PlaceEditScreenState extends State<PlaceEditScreen> {
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
  // PartyMediaPickerScreen)을 그대로 재사용한다. 기존 장소 데이터가 있으면
  // initState에서 existing* 필드를 채워 그대로 보여준다.
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

  // ── 룸 목록 — 세 리스트를 같은 인덱스로 나란히 관리한다.
  // _roomIds[i] == null 이면 이번에 새로 추가한 룸(저장 시 add()),
  // 아니면 기존 룸 문서 ID(저장 시 update()).
  final List<GlobalKey<RoomCardState>> _roomKeys = [];
  final List<String?> _roomIds = [];
  final List<Map<String, dynamic>?> _roomInitialData = [];

  // 최초에 불러온 룸 ID 전체(삭제 여부 판단용) + 룸별 원본 데이터(삭제된
  // 룸의 사진을 R2에서 지우기 위해 목록에서 빠진 뒤에도 참조할 수 있게 별도
  // 보관 — _roomInitialData는 _removeRoom 시 같이 사라지기 때문).
  final Set<String> _originalRoomIds = {};
  final Map<String, Map<String, dynamic>> _roomDataById = {};
  bool _loadingRooms = true;

  // 업로드 상태 — Stack 오버레이 방식으로 표시 (Form 위젯을 트리에 유지)
  bool _isUploading = false;
  String _uploadStatus = '';

  @override
  void initState() {
    super.initState();
    _loadFromData(widget.data);
    _loadRooms();
  }

  void _loadFromData(Map<String, dynamic> d) {
    _nameCtrl.text = d['name'] as String? ?? '';
    _detailAddressCtrl.text = d['detailAddress'] as String? ?? '';
    _descCtrl.text = d['description'] as String? ?? '';

    final address = d['address'] as String? ?? '';
    if (address.isNotEmpty) {
      _selectedAddress = AddressResult(
        placeName: '',
        address: address,
        roadAddress: address,
        jibunAddress: '',
        latitude: (d['lat'] as num?)?.toDouble() ?? 0.0,
        longitude: (d['lng'] as num?)?.toDouble() ?? 0.0,
      );
    }

    _placeType = d['type'] as String? ?? ListingConstants.placeTypes.first;

    final facilities = (d['commonFacilities'] as List?)?.cast<String>() ?? [];
    for (final f in facilities) {
      if (_commonFacilityOptions.contains(f)) {
        _commonFacilities.add(f);
      } else {
        _customCommonFacilities.add(f);
      }
    }

    _placeIsOpen24Hours = d['isOpen24Hours'] as bool? ?? false;
    if (!_placeIsOpen24Hours) {
      _placeOpenTime = _parsePlaceTime(d['openTime'] as String?);
      _placeCloseTime = _parsePlaceTime(d['closeTime'] as String?);
    }

    final payout = d['payoutAccount'] as Map<String, dynamic>?;
    _bankCtrl.text = payout?['bank'] as String? ?? '';
    _accountCtrl.text = payout?['accountNumber'] as String? ?? '';
    _holderCtrl.text = payout?['accountHolder'] as String? ?? '';
    _autoMsgCtrl.text = d['autoMessage'] as String? ?? '';

    // 미디어 — 파티 수정 화면과 동일하게 coverMediaType/coverImageUrl로
    // 대표 선택 상태를 복원한다.
    _mediaExistingImageUrls = ((d['imageUrls'] as List?)?.cast<String>() ?? [])
        .toList();
    _mediaExistingVideoUrl = d['videoUrl'] as String?;
    _mediaExistingVideoUid = d['videoUid'] as String?;
    _mediaExistingVideoThumbnailUrl = d['videoThumbnailUrl'] as String?;
    final coverMediaType = d['coverMediaType'] as String?;
    final coverImageUrl = d['coverImageUrl'] as String?;
    if (coverMediaType == 'video') {
      _mediaCoverPick = const PartyCoverPick(isExistingVideo: true);
    } else if (coverMediaType == 'image' && coverImageUrl != null) {
      _mediaCoverPick = PartyCoverPick(existingImageUrl: coverImageUrl);
    }
  }

  TimeOfDay? _parsePlaceTime(String? hhmm) {
    if (hhmm == null || !hhmm.contains(':')) return null;
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    if (h >= 24) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  Future<void> _loadRooms() async {
    final snap = await FirebaseFirestore.instance
        .collection('placeRooms')
        .where('placeId', isEqualTo: widget.docId)
        .get();
    if (!mounted) return;
    setState(() {
      for (final doc in snap.docs) {
        _roomKeys.add(GlobalKey<RoomCardState>());
        _roomIds.add(doc.id);
        _roomInitialData.add(doc.data());
        _originalRoomIds.add(doc.id);
        _roomDataById[doc.id] = doc.data();
      }
      _loadingRooms = false;
    });
  }

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
    _roomIds.add(null);
    _roomInitialData.add(null);
    _showRoomError = false;
  });

  void _removeRoom(int index) => setState(() {
    _roomKeys.removeAt(index);
    _roomIds.removeAt(index);
    _roomInitialData.removeAt(index);
  });

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

    debugPrint('─── [장소 수정] 필드 검증 시작 ───');
    debugPrint('  name       : "$name"');
    debugPrint('  address    : ${_selectedAddress?.roadAddress ?? "null"}');
    debugPrint('  roomCount  : ${_roomKeys.length}');

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

    if (_roomKeys.isEmpty) {
      setState(() => _showRoomError = true);
      hasError = true;
      firstErrorKey ??= _roomsKey;
    }

    if (hasError) {
      _scrollToKey(firstErrorKey!);
      return;
    }

    bool roomsValid = true;
    for (int i = 0; i < _roomKeys.length; i++) {
      final state = _roomKeys[i].currentState;
      if (state == null) {
        roomsValid = false;
        continue;
      }
      if (!state.validate()) roomsValid = false;
    }
    if (!roomsValid) {
      _scrollToKey(_roomsKey);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _msg('로그인이 필요합니다');
      return;
    }
    final hostId = widget.data['hostId'] as String?;
    if (hostId != uid) {
      _msg('작성자만 수정할 수 있습니다.');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = '장소 사진 업로드 중...';
    });

    try {
      // 장소 사진/동영상 업로드 — 등록 화면과 동일한 방식.
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

      // 대표 미디어 — 등록 화면과 동일한 규칙.
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

      // 대표로 고른 사진을 실제 저장 배열의 맨 앞(index 0)으로 재정렬한다.
      if (coverMediaType == 'image' && coverImageUrl != null) {
        imageUrls.remove(coverImageUrl);
        imageUrls.insert(0, coverImageUrl);
      }

      // ── 룸별 업로드 + 문서 반영 (기존 룸=update, 신규 룸=add) ──────
      final roomDataList = <Map<String, dynamic>>[];
      for (int i = 0; i < _roomKeys.length; i++) {
        setState(
          () => _uploadStatus = '룸 ${i + 1}/${_roomKeys.length} 저장 중...',
        );
        final state = _roomKeys[i].currentState;
        if (state == null) {
          throw Exception('룸[$i] state == null — 예상치 못한 위젯 트리 제거');
        }
        final roomData = await state.uploadAndGetData(uid, widget.docId);
        roomDataList.add(roomData);
        final roomId = _roomIds[i];
        if (roomId == null) {
          await FirebaseFirestore.instance
              .collection('placeRooms')
              .add(roomData);
        } else {
          await FirebaseFirestore.instance
              .collection('placeRooms')
              .doc(roomId)
              .update(roomData);
        }
      }

      // ── 목록에서 뺀(삭제된) 기존 룸 — 사진 정리 후 문서 삭제 ────────
      final remainingRoomIds = _roomIds.whereType<String>().toSet();
      final deletedRoomIds = _originalRoomIds.difference(remainingRoomIds);
      for (final roomId in deletedRoomIds) {
        setState(() => _uploadStatus = '삭제된 룸 정리 중...');
        final oldImages =
            (_roomDataById[roomId]?['roomImages'] as List?)?.cast<String>() ??
            [];
        for (final url in oldImages) {
          try {
            await CloudflareService.deleteImage(url);
          } catch (_) {}
        }
        await FirebaseFirestore.instance
            .collection('placeRooms')
            .doc(roomId)
            .delete();
      }

      // 상세검색용 집계값 — 남아있는 룸 기준 최저 시간당 가격 / 최대 수용 인원
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

      // 장소 문서 수정 — isActive:true/hiddenAt 삭제를 항상 포함해서, 숨김
      // 상태였다면 저장과 동시에 재등록(진행중 복귀)되고, 이미 진행중이었다면
      // 사실상 변화 없이 그대로 유지된다.
      await FirebaseFirestore.instance
          .collection('places')
          .doc(widget.docId)
          .update({
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
            'pricePerHour': minPrice,
            'capacityMax': maxCapacity,
            'payoutAccount': {
              'bank': _bankCtrl.text.trim(),
              'accountNumber': _accountCtrl.text.trim(),
              'accountHolder': _holderCtrl.text.trim(),
            },
            'autoMessage': _autoMsgCtrl.text.trim(),
            'isActive': true,
            'hiddenAt': FieldValue.delete(),
            if (_placeIsOpen24Hours) ...{
              'openTime': '00:00',
              'closeTime': '24:00',
              'isOpen24Hours': true,
            } else if (_placeOpenTime != null && _placeCloseTime != null) ...{
              'openTime': _fmtPlaceTime(_placeOpenTime!),
              'closeTime': _fmtPlaceTime(_placeCloseTime!),
              'isOpen24Hours': false,
            },
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _uploadStatus = '';
      });

      _msg('저장되었습니다');
      Navigator.pop(context);
    } catch (e, st) {
      debugPrint('❌ 장소 수정 실패: $e');
      debugPrint('StackTrace:\n$st');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatus = '';
        });
        _msg('저장 중 오류가 발생했습니다: $e');
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
    if (_loadingRooms) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          title: const Text('장소 수정', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Stack 오버레이 방식 — _isUploading 중에도 Form·RoomCard 를 트리에 유지
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          appBar: AppBar(
            title: const Text('장소 수정', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
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
                    child: const Text('저장하기'),
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
            roomId: _roomIds[i],
            initialData: _roomInitialData[i],
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
