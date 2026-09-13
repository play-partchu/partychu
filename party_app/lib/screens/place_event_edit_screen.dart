// ─────────────────────────────────────────────────────────────────────────────
// 이벤트·혜택 한 건을 추가/수정하는 화면.
//
// **원본 장소를 다시 입력시키지 않는다** — 장소명·주소·좌표·지도·호스트·시설은
// 이미 원본 문서에 있고, 이 화면은 [placeId]/[placeCollection]/[hostId]를
// 받아 그대로 붙인다. 그래서 입력란은 "이번 이벤트에만 해당하는 것"뿐이다.
//
// 미디어는 새로 만들지 않고 기존 경로를 그대로 쓴다 —
//   사진·동영상: [PartyMediaEditor] + [MediaUploadService.uploadNewMedia]
//   (대표 지정·크롭·트리밍·압축이 이미 들어 있는 파티/플레이스 공용 경로)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:party_app/models/event_apply.dart';
import 'package:party_app/models/event_inquiry_notice.dart';
import 'package:party_app/models/host_offering.dart';
import 'package:party_app/models/listing_inquiry.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/models/place_event_time.dart';
import 'package:party_app/models/place_product.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/screens/party_register_entry_choice_screen.dart';
import 'package:party_app/services/media_upload_service.dart';
import 'package:party_app/services/party_event_source.dart';
import 'package:party_app/services/place_event_entry.dart';
import 'package:party_app/services/place_product_service.dart';
import 'package:party_app/services/place_promotion_service.dart';
import 'package:party_app/widgets/event_inquiry_off_notice_picker.dart';
import 'package:party_app/widgets/guest_inquiry_section.dart';
import 'package:party_app/widgets/host_offering_choice.dart';
import 'package:party_app/widgets/party_form/wheel_time_picker_sheet.dart';
import 'package:party_app/widgets/party_media_editor.dart';
import 'package:party_app/widgets/partychu_event_perk_banner.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 이벤트 사진 상한 — 상세 시트에서 넘겨 보는 양으로 충분하다.
const int kEventMaxImages = 6;

class PlaceEventEditScreen extends StatefulWidget {
  const PlaceEventEditScreen({
    super.key,
    required this.placeId,
    required this.placeCollection,
    required this.hostId,
    required this.placeName,
    required this.accent,
    this.existing,
    this.placeAddress,
    this.initialTitle,
    this.sourcePartyId,
    this.sourcePartyTitle,
    this.requirePeriod = false,
  });

  final String placeId;

  /// 'events'(플레이스) 또는 'places'(장소대여·숙박).
  final String placeCollection;
  final String hostId;
  final String placeName;
  final Color accent;

  /// null이면 새 이벤트, 있으면 그 이벤트를 고친다.
  final PlacePromotion? existing;

  /// 가게 주소 — 머리말에만 쓴다. 이벤트 문서에는 넣지 않는다(주소는 가게
  /// 문서가 정본이고, 복사해 두면 가게가 이사했을 때 갈라진다).
  final String? placeAddress;

  // ── 파티에서 넘어온 등록 ───────────────────────────────────────────────
  // "이 파티를 기반으로 이벤트 등록"으로 들어왔을 때만 채워진다
  // ([PartyEventSource]). 그 외 경로에서는 전부 null/false라 화면이 지금과
  // 똑같이 동작한다.

  /// 제목 초안 — 새 이벤트일 때만 쓰고, 호스트가 지우거나 고칠 수 있다.
  final String? initialTitle;

  final String? sourcePartyId;
  final String? sourcePartyTitle;

  /// 기간을 **반드시** 정하게 한다.
  ///
  /// 파티에서 만드는 이벤트는 "9월 1일 ~ 9월 30일 주류 할인"처럼 기간이 성격
  /// 자체다. 상시 진행을 열어 두면 파티와 구분이 사라지므로 그 스위치를 감추고
  /// 시작일·종료일을 필수로 받는다.
  final bool requirePeriod;

  @override
  State<PlaceEventEditScreen> createState() => _PlaceEventEditScreenState();
}

class _PlaceEventEditScreenState extends State<PlaceEventEditScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _benefitCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _conditionsCtrl = TextEditingController();
  final _audienceCtrl = TextEditingController();

  /// 사진·동영상·대표 지정·크롭을 한꺼번에 들고 있는 공용 편집기.
  final _mediaKey = GlobalKey<PartyMediaEditorState>();

  PromotionType _type = PromotionType.event;
  bool _isAlways = false;
  DateTime? _startAt;
  DateTime? _endAt;
  final Set<int> _weekdays = {};
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _reservationRequired = false;

  /// 예약을 어떻게 잡으면 되는지 — 사전 예약이 켜졌을 때만 쓰는 안내 문구.
  final _reservationGuideCtrl = TextEditingController();
  bool _isVisible = true;
  final Set<String> _linkedProductIds = {};

  // ── 채팅 문의 받기 ─────────────────────────────────────────────────────
  // ON/OFF는 파티·플레이스와 같은 공용 필드(inquiryEnabled)다. 끈 경우에
  // 대신 보여줄 안내만 이벤트 전용이다([EventInquiryNotice]).
  bool _inquiryEnabled = ListingInquiry.defaultEnabled;

  /// 신청 받기 — 필드가 없는 옛 이벤트는 [EventApplyMode.none]으로 열린다.
  EventApplyMode _applyMode = EventApplyMode.defaultMode;

  /// 스위치를 껐다 켤 때 돌아갈 방식. 매번 처음부터 고르게 하지 않는다.
  EventApplyMode _lastPickedApplyMode = EventApplyMode.applyOnly;
  EventInquiryNotice _inquiryOffNotice = EventInquiryNotice.defaultNotice;
  final _inquiryOffTextCtrl = TextEditingController();

  List<PlaceProduct> _products = const [];
  bool _isCompressingVideo = false;
  bool _saving = false;
  String? _uploadNote;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = e.title;
      _descCtrl.text = e.description;
      _benefitCtrl.text = e.benefit;
      _priceCtrl.text = e.priceText;
      _conditionsCtrl.text = e.conditions;
      _audienceCtrl.text = e.audience;
      _type = e.type;
      _isAlways = e.isAlways;
      _startAt = e.startAt;
      _endAt = e.endAt;
      _weekdays.addAll(e.weekdays);
      _startTime = _parseTime(e.startTime);
      _endTime = _parseTime(e.endTime);
      _reservationRequired = e.reservationRequired;
      _reservationGuideCtrl.text = e.reservationGuide;
      _isVisible = e.isVisible;
      _linkedProductIds.addAll(e.linkedProductIds);
      // 문의 설정 — 필드가 없던 옛 이벤트는 모델이 안전한 기본값
      // (문의 켜짐 · 기본 안내)으로 읽어 준다.
      _inquiryEnabled = e.inquiryEnabled;
      // 사전 예약이 필요한 이벤트는 문의가 예약을 잡는 유일한 길이라 문의를
      // 켠 상태로 연다 — 아래 카드가 잠긴 채로 'OFF'를 보여주면 그 잠금이
      // 거짓말이 된다. 저장하기 전까지 문서는 그대로다.
      if (e.reservationRequired) _inquiryEnabled = true;
      _applyMode = e.applyMode;
      if (e.applyMode.receivesApplications) _lastPickedApplyMode = e.applyMode;
      _inquiryOffNotice = e.inquiryOffNotice;
      _inquiryOffTextCtrl.text = e.inquiryOffNoticeText;
    } else {
      // 제목 초안만 미리 채운다. 나머지(설명·혜택·기간)는 이벤트용으로 새로
      // 받는다 — 파티 소개를 그대로 옮기면 "며칠짜리 혜택"이 아니라 파티
      // 안내문이 이벤트 자리에 앉는다.
      final draft = widget.initialTitle?.trim() ?? '';
      if (draft.isNotEmpty) _titleCtrl.text = draft;
    }
    _loadProducts();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _benefitCtrl.dispose();
    _priceCtrl.dispose();
    _conditionsCtrl.dispose();
    _audienceCtrl.dispose();
    _reservationGuideCtrl.dispose();
    _inquiryOffTextCtrl.dispose();
    super.dispose();
  }

  /// 연결할 수 있는 상품 — 결제가 필요한 내용은 여기에 걸어 홍보만 한다.
  Future<void> _loadProducts() async {
    try {
      final list = await PlaceProductService.listForPlace(widget.placeId);
      if (!mounted) return;
      setState(() => _products = list);
    } catch (_) {
      // 상품 조회 실패는 이벤트 등록을 막을 이유가 없다 — 연결 영역만 빠진다.
    }
  }

  /// 지금 화면이 영업중(전시간)인가 — 저장 규칙과 **같은 판정**이다
  /// (시각을 하나도 안 정한 상태). 화면 전용 플래그를 따로 두면 저장된 값과
  /// 어긋날 수 있어서 값에서 바로 읽는다.
  bool get _isBusinessHours => _startTime == null && _endTime == null;

  static TimeOfDay? _parseTime(String? hhmm) {
    if (hhmm == null || hhmm.isEmpty) return null;
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final base = (isStart ? _startAt : _endAt) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startAt = picked;
        // 시작일이 종료일을 넘으면 종료일을 끌어올린다 — 저장 후 곧바로
        // '종료' 상태가 되는 이벤트가 만들어지는 걸 막는다.
        if (_endAt != null && _endAt!.isBefore(picked)) _endAt = picked;
      } else {
        _endAt = picked;
        if (_startAt != null && picked.isBefore(_startAt!)) _startAt = picked;
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    // 앱 전체가 쓰는 공용 휠 선택기(오전/오후 · 시 · 분)를 그대로 쓴다 —
    // 파티 폼·플레이스 상품과 같은 것이라 시간 고르는 방식이 하나다.
    // 돌려받는 값은 24시간제 TimeOfDay라 저장 포맷('HH:mm')은 그대로다.
    final picked = await showWheelTimePicker(
      context,
      initial:
          (isStart ? _startTime : _endTime) ??
          const TimeOfDay(hour: 20, minute: 0),
      title: isStart ? '시작 시간' : '종료 시간',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  String? _validate() {
    if (_titleCtrl.text.trim().isEmpty) return '이벤트 제목을 입력해주세요.';
    if (widget.requirePeriod && (_startAt == null || _endAt == null)) {
      return '이벤트 시작일과 종료일을 모두 정해주세요.';
    }
    if (!_isAlways &&
        _startAt != null &&
        _endAt != null &&
        _endAt!.isBefore(_startAt!)) {
      return '종료일이 시작일보다 빠릅니다.';
    }
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      _toast(err);
      return;
    }
    if (_isCompressingVideo) {
      _toast('동영상 처리가 끝난 뒤에 저장해주세요.');
      return;
    }

    setState(() {
      _saving = true;
      _uploadNote = null;
    });

    try {
      // ── 사진·동영상 업로드 ───────────────────────────────────────────
      //
      // 파티·플레이스 등록과 **같은 공용 업로더 한 번**으로 끝낸다. 예전에는
      // 사진은 MediaUploadService로, 영상은 CloudflareService로 따로 올려서
      // 실패했을 때 어느 쪽이 문제인지 안내가 갈렸다.
      final media = _mediaKey.currentState;
      final existingImageUrls = media?.existingImageUrls ?? const <String>[];
      final newMedia = media?.newMediaFiles ?? const <XFile>[];

      final imageUrls = [...existingImageUrls];
      String? videoUid = media?.existingVideoUid;
      String? videoUrl = media?.existingVideoUrl;
      String? videoThumbnailUrl = media?.existingVideoThumbnailUrl;

      MediaUploadResult upload = const MediaUploadResult();
      if (newMedia.isNotEmpty) {
        setState(() => _uploadNote = '사진 올리는 중...');
        upload = await MediaUploadService.uploadNewMedia(
          media: newMedia,
          logTag: 'place-event',
          onVideoStart: () {
            if (mounted) setState(() => _uploadNote = '동영상 올리는 중...');
          },
          onImageProgress: (done, total) {
            if (mounted) {
              setState(() => _uploadNote = '사진 $done/$total 올리는 중...');
            }
          },
        );
        imageUrls.addAll(upload.imageUrls);
        // 새 영상을 올렸을 때만 갈아끼운다 — 안 올렸으면 기존 영상이 남는다.
        if (upload.hasVideo) {
          videoUid = upload.videoUid;
          videoUrl = upload.videoUrl;
          videoThumbnailUrl = upload.videoThumbnailUrl;
        }
      }

      // ── 대표 미디어 ─────────────────────────────────────────────────
      // 필드를 만드는 규칙은 파티·플레이스와 같은 함수 하나를 지난다.
      final cover = MediaUploadService.resolveCoverFields(
        coverPick: media?.coverPick,
        imageUrls: imageUrls,
        uploadedImageUrls: upload.imageUrls,
        videoUrl: videoUrl,
        videoUid: videoUid,
        videoThumbnailUrl: videoThumbnailUrl,
      );
      // 크롭 값의 키는 로컬 경로 → 최종 URL로 옮겨 담는다.
      final photoCrops = MediaUploadService.resolvePhotoCropKeys(
        crops: media?.photoCrops ?? const {},
        existingImageUrls: existingImageUrls,
        newMedia: newMedia,
        uploadedImageUrls: upload.imageUrls,
      );

      if (mounted) setState(() => _uploadNote = '저장 중...');

      final base =
          widget.existing ??
          PlacePromotion.empty(
            placeId: widget.placeId,
            placeCollection: widget.placeCollection,
            hostId: widget.hostId,
            sortOrder: 0,
          );

      final next = base.copyWith(
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        benefit: _benefitCtrl.text.trim(),
        priceText: _priceCtrl.text.trim(),
        conditions: _conditionsCtrl.text.trim(),
        audience: _audienceCtrl.text.trim(),
        type: _type,
        imageUrls: imageUrls,
        videoUrl: videoUrl,
        videoUid: videoUid,
        videoThumbnailUrl: videoThumbnailUrl,
        clearVideo: videoUrl == null,
        isAlways: _isAlways,
        // 상시 진행이면 날짜를 아예 비운다 — 나중에 상시를 꺼도 낡은 날짜가
        // 되살아나 갑자기 '종료'로 보이는 일이 없게 한다.
        startAt: _isAlways ? null : _startAt,
        endAt: _isAlways ? null : _endAt,
        weekdays: _weekdays.toList()..sort(),
        startTime: _startTime == null ? null : _fmtTime(_startTime!),
        endTime: _endTime == null ? null : _fmtTime(_endTime!),
        clearTime: _startTime == null && _endTime == null,
        reservationRequired: _reservationRequired,
        reservationGuide: _reservationGuideCtrl.text,
        isVisible: _isVisible,
        linkedProductIds: _linkedProductIds.toList(),
        // 문의 받기 — 켜면 OFF 안내 두 필드는 toMap이 지운다.
        applyMode: _applyMode,
        inquiryEnabled: _inquiryEnabled,
        inquiryOffNotice: _inquiryOffNotice,
        inquiryOffNoticeText: _inquiryOffTextCtrl.text,
        // 대표 미디어 — 파티·플레이스와 같은 필드명·같은 결정 규칙.
        coverMediaType: cover['coverMediaType'] as String?,
        coverImageUrl: cover['coverImageUrl'] as String?,
        coverVideoUrl: cover['coverVideoUrl'] as String?,
        coverVideoUid: cover['coverVideoUid'] as String?,
        coverThumbnailUrl: cover['coverThumbnailUrl'] as String?,
        basicCardPhotoCrops: photoCrops,
      );

      // 상시 진행은 copyWith(`??`)로 날짜를 null로 되돌릴 수 없어 한 번 더 만든다.
      final toSave = _isAlways
          ? PlacePromotion.fromMap(next.id, {
              ...next.toMap(),
              'startAt': null,
              'endAt': null,
            })
          : next;

      // 원본 파티는 **출처 표시**로만 남는다 — 이벤트가 파티에 종속되지 않는다
      // (파티가 지워져도 이 이벤트는 그대로다).
      final saved = widget.sourcePartyId == null
          ? toSave
          : toSave.copyWith(
              sourcePartyId: widget.sourcePartyId,
              sourcePartyTitle: widget.sourcePartyTitle,
            );

      if (_isEdit) {
        await PlacePromotionService.update(saved);
      } else {
        await PlacePromotionService.create(
          placeId: widget.placeId,
          placeCollection: widget.placeCollection,
          hostId: widget.hostId,
          promotion: saved,
        );
      }

      // 프로모션 문서만 만들면 "플레이스 > 이벤트" 목록에는 뜨지 않는다 —
      // 그 목록의 정본은 플레이스 본체의 themeTags/eventSubtype이다
      // ([PartyEventSource.syncPlaceExposure] 주석 참고).
      //
      // 실패해도 저장을 되돌리지 않는다. 이벤트는 이미 가게 상세에 떠 있고,
      // 노출 값은 이 가게의 이벤트를 다음에 저장·숨김·삭제할 때 전체 목록에서
      // 다시 계산된다. 여기서 예외를 올리면 **저장이 끝난 뒤에 "저장 실패"라고
      // 말하는** 더 나쁜 상태가 된다.
      // (예전에는 "플레이스 수정 화면에서 손으로 켤 수 있다"가 여기 적혀
      //  있었지만, 그 특징 태그 입력은 없어졌다 — 노출은 이제 이벤트 정본에서
      //  자동으로만 정해진다.)
      try {
        await PartyEventSource.syncPlaceExposure(
          placeId: widget.placeId,
          placeCollection: widget.placeCollection,
          promotion: saved,
        );
      } catch (_) {}

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _uploadNote = null;
      });
      // 예전에는 permission-denied가 아니면 전부 "저장에 실패했어요"로 뭉갰다.
      // 그래서 사진 업로드가 막힌 것도, 사업자 권한이 없는 것도 같은 문장으로
      // 나왔고 호스트는 무엇을 고쳐야 하는지 알 수 없었다. 판정은
      // [PlaceEventEntry.saveFailureMessage] 하나가 한다 — 이 화면과 앞으로
      // 생길 다른 저장 경로가 서로 다른 문구를 지어내지 않도록.
      final msg = await PlaceEventEntry.saveFailureMessage(
        e,
        placeId: widget.placeId,
        placeCollection: widget.placeCollection,
      );
      if (!mounted) return;
      _toast(msg);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0.5,
        title: Text(
          _isEdit ? '매장 이벤트 수정' : '매장 이벤트 추가',
          style: const TextStyle(
            fontFamily: PartyChuTitleFont.family,
            fontWeight: PartyChuTitleFont.medium,
            fontSize: 18,
            color: Colors.black87,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 120),
          children: [
            // 맨 위는 **파티츄가 지금 돌리는 공식 혜택** 안내다. 호스트가 쓰는
            // 칸이 아니라 읽는 칸이라 아래 폼과 시각적으로 갈라 둔다. 운영이
            // 켜 두지 않았으면 통째로 사라진다(빈 카드가 남지 않는다).
            const PartychuEventPerkBanner(),

            // 어느 장소에 붙는 이벤트인지 — 다시 입력할 필요가 없다는 걸
            // 첫 화면에서 분명히 보여준다.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 17, color: accent),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          widget.placeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                      const Text(
                        '이 장소의 매장 이벤트',
                        style: TextStyle(fontSize: 11.5, color: Colors.black45),
                      ),
                    ],
                  ),
                  if ((widget.placeAddress ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 24),
                      child: Text(
                        widget.placeAddress!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                  // 파티에서 넘어왔을 때만 — 어디서 시작한 등록인지 남긴다.
                  // 사진은 일부러 가져오지 않는다(아래 안내 문구 참고).
                  if ((widget.sourcePartyTitle ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 24),
                      child: Text(
                        "'${widget.sourcePartyTitle!.trim()}' 파티에서 만드는 이벤트예요. "
                        '사진은 이벤트용으로 새로 올려주세요.',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.black45,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 🎪 무엇을 쓰는 자리인지 한 줄 — 그리고 여기가 아닌 사람에게는
            // 돌아갈 길. 새 이벤트를 만들 때만 보인다(고치러 온 사람에게는
            // 이미 정해진 이야기다).
            if (!_isEdit) ...[
              const SizedBox(height: 14),
              Text(
                '${HostOffering.placeEvent.emoji} '
                '${HostOffering.placeEvent.criterion}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 3),
              // 폼에 들어온 사람에게는 "어디까지 담을 수 있는가"를 말한다 —
              // 신청을 받는 이벤트도 여기서 만든다는 사실이 맨 위에 있어야
              // 아래 '신청 받기' 스위치를 찾는다([HostOffering] 정본).
              Text(
                HostOffering.placeEventFormSubtitle,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 10),
              // 참가자 모집이 중심이면 여기가 아니다 — 폼을 다 채우고 나서
              // 알아채는 것보다, 시작하기 전에 건너갈 길을 주는 편이 낫다.
              //
              // ⚠️ "신청을 받으면 파티"라는 뜻이 **아니다.** 매장 이벤트도
              //    신청을 받는다(위 '신청 받기'). 정원·승인·참가비가 달린
              //    모집이 중심일 때만 저장 구조가 다른 parties로 간다.
              HostOfferingCrossLink(
                to: HostOffering.party,
                onTap: () => openPartyRegisterEntry(context),
              ),
            ],
            const SizedBox(height: 20),

            _label('이벤트 유형'),
            // 호스트가 **왜 고르는지**를 먼저 말한다. 이 값은 손님 화면의
            // 이벤트 갈래 필터(eventKinds)를 채우는 유일한 입력인데
            // ([PlaceEventTaxonomy.kindsOfPromotion]), 지금까지 화면에는 그
            // 사실이 어디에도 없어서 아무거나 고르게 되어 있었다.
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '손님이 이벤트를 더 쉽게 찾을 수 있도록 가장 가까운 유형을 선택해주세요.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.black45,
                  height: 1.5,
                ),
              ),
            ),
            Row(
              children: [
                for (final t in PromotionType.values) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _type = t),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: _type == t
                              ? accent.withValues(alpha: 0.10)
                              : const Color(0xFFF7F7FA),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: _type == t
                                ? accent
                                : const Color(0xFFE8EBF2),
                            width: _type == t ? 1.4 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(t.emoji, style: const TextStyle(fontSize: 18)),
                            const SizedBox(height: 3),
                            Text(
                              t.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _type == t ? accent : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (t != PromotionType.values.last) const SizedBox(width: 8),
                ],
              ],
            ),
            // 세 카드가 각각 무엇을 뜻하는지 — 카드 안이 아니라 **아래 범례**로
            // 둔다. 카드는 셋이 가로를 나눠 쓰느라 한 칸이 100px 남짓이라,
            // 설명을 넣으면 줄바꿈으로 카드 높이가 서로 달라진다.
            const SizedBox(height: 10),
            for (final t in PromotionType.values) _typeMeaning(t),
            if (_type == PromotionType.package) ...[
              const SizedBox(height: 8),
              const Text(
                '가격·재고·결제가 필요한 묶음이면 "상품·이용권"으로 등록한 뒤\n'
                '아래 "연결 상품"에서 걸어주세요. 여기서는 홍보만 합니다.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.black45,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 20),

            _label('이벤트 제목'),
            _field(_titleCtrl, hint: '예) 금·토 샴페인 무제한'),
            const SizedBox(height: 20),

            // 사진·동영상 — 파티·플레이스 등록과 **같은 공용 편집기**다.
            // 대표 지정(사진을 눌러 대표로), 기본카드 크롭, 동영상 트리밍·
            // 압축이 전부 여기 들어 있어 이벤트만 다르게 동작하지 않는다.
            _label('사진 · 동영상'),
            const Text(
              '사진을 눌러 대표로 지정할 수 있어요. 대표는 목록과 상세 맨 앞에 보여요.',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.black45,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            PartyMediaEditor(
              key: _mediaKey,
              maxImages: kEventMaxImages,
              initialImageUrls: widget.existing?.allImageUrls ?? const [],
              initialVideoUrl: widget.existing?.videoUrl,
              initialVideoUid: widget.existing?.videoUid,
              initialVideoThumbnailUrl: widget.existing?.videoThumbnailUrl,
              initialCoverMediaType: widget.existing?.coverMediaType,
              initialCoverImageUrl: widget.existing?.coverImageUrl,
              initialPhotoCrops:
                  widget.existing?.basicCardPhotoCrops ?? const {},
              onCompressingChanged: (v) =>
                  setState(() => _isCompressingVideo = v),
              onMediaChanged: () => setState(() {}),
            ),
            const SizedBox(height: 20),

            _label('이벤트 설명'),
            _field(_descCtrl, hint: '어떤 이벤트인지 알려주세요', maxLines: 4),
            const SizedBox(height: 20),

            _label(widget.requirePeriod ? '이벤트 기간 (필수)' : '기간'),
            // 파티에서 만든 이벤트는 기간이 성격 자체라 상시 진행을 감춘다.
            if (!widget.requirePeriod)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('상시 진행', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '켜면 시작일·종료일 없이 계속 노출됩니다',
                  style: TextStyle(fontSize: 11.5, color: Colors.black45),
                ),
                value: _isAlways,
                activeThumbColor: accent,
                onChanged: (v) => setState(() => _isAlways = v),
              ),
            if (!_isAlways) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _pickerBox(
                      label: '시작일',
                      value: _startAt == null
                          ? null
                          : '${_startAt!.month}.${_startAt!.day}',
                      onTap: () => _pickDate(isStart: true),
                      onClear: _startAt == null
                          ? null
                          : () => setState(() => _startAt = null),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _pickerBox(
                      label: '종료일',
                      value: _endAt == null
                          ? null
                          : '${_endAt!.month}.${_endAt!.day}',
                      onTap: () => _pickDate(isStart: false),
                      onClear: _endAt == null
                          ? null
                          : () => setState(() => _endAt = null),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),

            _label('진행 요일 (선택)'),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (var d = 1; d <= 7; d++)
                  GestureDetector(
                    onTap: () => setState(() {
                      if (!_weekdays.remove(d)) _weekdays.add(d);
                    }),
                    child: Container(
                      width: 40,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _weekdays.contains(d)
                            ? accent
                            : const Color(0xFFF7F7FA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _weekdays.contains(d)
                              ? accent
                              : const Color(0xFFE8EBF2),
                        ),
                      ),
                      child: Text(
                        kWeekdayLabels[d - 1],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _weekdays.contains(d)
                              ? Colors.white
                              : Colors.black54,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '고르지 않으면 요일 표기 없이 노출됩니다.',
              style: TextStyle(fontSize: 11.5, color: Colors.black45),
            ),
            const SizedBox(height: 20),

            _label('이벤트 시간'),
            // 영업중(전시간)과 시간 지정은 **저장 상태가 곧 구분**이다 —
            // 시간을 비우면 전자, 적으면 후자다([PlaceEventTime.isBusinessHours]).
            // 그래서 이 선택기는 새 필드를 켜고 끄는 것이 아니라 시간을
            // 비우거나 채우는 버튼이다(저장 구조가 늘지 않는다).
            Row(
              children: [
                Expanded(
                  child: _timeModeChip(
                    label: PlaceEventTime.businessHoursLabel,
                    selected: _isBusinessHours,
                    onTap: () => setState(() {
                      _startTime = null;
                      _endTime = null;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _timeModeChip(
                    label: '시간 지정',
                    selected: !_isBusinessHours,
                    // 고를 때 기본값을 채워 둔다 — 빈 채로 두면 방금 고른
                    // '시간 지정'이 저장 시 다시 영업중(전시간)으로 되돌아간다.
                    onTap: () => setState(() {
                      _startTime ??= const TimeOfDay(hour: 20, minute: 0);
                      _endTime ??= const TimeOfDay(hour: 23, minute: 0);
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _isBusinessHours
                  ? '매장 영업시간 동안 계속 적용되는 이벤트예요. '
                        '24시간이라는 뜻은 아니에요.'
                  : '이벤트가 적용되는 시각을 정해요. 종료가 시작보다 이르면 '
                        '자정을 넘기는 것으로 봐요(22:00 ~ 02:00).',
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: Colors.black45,
              ),
            ),
            if (!_isBusinessHours) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _pickerBox(
                      label: '시작 시간',
                      // 보여줄 때는 앱 공통 표기('오후 8:00'). 저장은 아래
                      // _fmtTime이 만드는 'HH:mm' 그대로다.
                      value: _startTime == null
                          ? null
                          : formatKoreanTimeOfDay(_startTime!),
                      onTap: () => _pickTime(isStart: true),
                      onClear: _startTime == null
                          ? null
                          : () => setState(() => _startTime = null),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _pickerBox(
                      label: '종료 시간',
                      value: _endTime == null
                          ? null
                          : formatKoreanTimeOfDay(_endTime!),
                      onTap: () => _pickTime(isStart: false),
                      onClear: _endTime == null
                          ? null
                          : () => setState(() => _endTime = null),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),

            _label('혜택 내용'),
            _field(_benefitCtrl, hint: '예) 파티츄 보고 방문 시 샴페인 무제한', maxLines: 2),
            const SizedBox(height: 20),

            _label('가격 · 할인'),
            _field(_priceCtrl, hint: '예) 29,000원 / 1+1 / 20% 할인'),
            const SizedBox(height: 20),

            _label('이용 조건'),
            _field(_conditionsCtrl, hint: '예) 2인 이상 방문 시', maxLines: 2),
            const SizedBox(height: 20),

            _label('대상 (선택)'),
            _field(_audienceCtrl, hint: '예) 20~30대, 여성 고객'),
            const SizedBox(height: 20),

            // ── 사전 예약 필요 ───────────────────────────────────────────
            //
            // 이 스위치는 **예약 기능을 만들지 않는다.** 손님에게 "미리
            // 예약해야 한다"고 알릴 뿐이고, 실제 예약은 장소 쪽 기능이거나
            // 호스트에게 문의해서 잡는다. 그래서 켜는 순간 문의 받기를 함께
            // 켜고 잠근다 — 예약이 필요하다는 안내만 있고 물어볼 길이 없으면
            // 손님은 아무 데도 갈 수 없다.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('사전 예약 필요', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '이 이벤트 이용 전에 매장/장소 예약이 필요한 경우 켜주세요.',
                style: TextStyle(fontSize: 11.5, color: Colors.black45),
              ),
              value: _reservationRequired,
              activeThumbColor: accent,
              onChanged: (v) => setState(() {
                _reservationRequired = v;
                // 켜면 문의도 함께 켠다(아래 카드에서 잠긴다). 끌 때는
                // 되돌리지 않는다 — 호스트가 직접 켠 것일 수도 있는 값을
                // 말없이 끄지 않는다.
                if (v) _inquiryEnabled = true;
              }),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 4),
              child: Text(
                '이 설정은 별도의 예약 기능을 생성하지 않고, 게스트에게 예약 필요 '
                '여부를 안내합니다.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: Colors.black38,
                ),
              ),
            ),
            if (_reservationRequired) ...[
              const SizedBox(height: 10),
              _label('예약 안내'),
              _field(
                _reservationGuideCtrl,
                hint: '예) 방문 전 문의하기를 눌러 희망 날짜와 인원을 알려주세요.',
                maxLines: 2,
                maxLength: ListingInquiry.maxGuideLength,
              ),
              const SizedBox(height: 6),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('손님에게 노출', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '끄면 상세에서 감춰집니다(문서는 남아요)',
                style: TextStyle(fontSize: 11.5, color: Colors.black45),
              ),
              value: _isVisible,
              activeThumbColor: accent,
              onChanged: (v) => setState(() => _isVisible = v),
            ),

            // ── 신청 받기 ────────────────────────────────────────────────
            //
            // 매장 이벤트도 신청을 받을 수 있다([EventApplyMode]). 신청 여부는
            // 파티와 매장 이벤트를 가르는 기준이 **아니다** — 생일 이벤트처럼
            // 매장이 여는 행사인데 사전 신청을 받는 것이 얼마든지 있다.
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('신청 받기', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '켜면 손님이 이 이벤트에 직접 신청할 수 있어요',
                style: TextStyle(fontSize: 11.5, color: Colors.black45),
              ),
              value: _applyMode.receivesApplications,
              activeThumbColor: accent,
              // 껐다 켤 때 예전에 고른 방식으로 돌아온다 — 매번 처음부터
              // 다시 고르게 하지 않는다.
              onChanged: (v) => setState(
                () =>
                    _applyMode = v ? _lastPickedApplyMode : EventApplyMode.none,
              ),
            ),
            if (_applyMode.receivesApplications) ...[
              const SizedBox(height: 6),
              _label('신청 방식'),
              for (final m in EventApplyMode.pickable) ...[
                RadioListTile<EventApplyMode>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: m,
                  // ignore: deprecated_member_use
                  groupValue: _applyMode,
                  activeColor: accent,
                  title: Text(m.label, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                    m == EventApplyMode.applyOnly
                        ? '상세에 신청하기 버튼만 보여요'
                        : '상세에 문의하기와 신청하기가 함께 보여요',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.black45,
                    ),
                  ),
                  // ignore: deprecated_member_use
                  onChanged: (v) => setState(() {
                    _applyMode = v ?? _applyMode;
                    _lastPickedApplyMode = _applyMode;
                  }),
                ),
              ],
              // 문의는 아래 '채팅 문의 받기'가 정본이다. '문의 및 신청하기'를
              // 골라도 그 스위치가 꺼져 있으면 문의 버튼은 뜨지 않는다 —
              // 여기서 문의를 몰래 켜지 않는다는 약속을 화면에서도 말해 준다.
              if (_applyMode == EventApplyMode.inquiryAndApply &&
                  !_inquiryEnabled) ...[
                const SizedBox(height: 4),
                const Text(
                  '아래 "채팅 문의 받기"가 꺼져 있어 지금은 신청하기만 보여요.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: Color(0xFFB45309),
                  ),
                ),
              ],
            ],

            // 채팅 문의 받기 — 파티·플레이스·장소대여와 **같은 공용 카드**다.
            // 이벤트만 다른 점은 껐을 때 대신 보여줄 안내를 고르는 것이라,
            // 카드에 도메인 분기를 넣는 대신 offExtra 슬롯에 끼운다.
            const SizedBox(height: 16),
            GuestInquirySection(
              enabled: _inquiryEnabled,
              onChanged: (v) => setState(() => _inquiryEnabled = v),
              // 사전 예약이 필요한 이벤트에서는 문의가 예약을 잡는 유일한
              // 길이라 끄지 못한다.
              lockedNote: _reservationRequired
                  ? '사전 예약 안내를 위해 문의 받기가 함께 켜져 있어요.'
                  : null,
              offExtra: EventInquiryOffNoticePicker(
                notice: _inquiryOffNotice,
                onNoticeChanged: (n) => setState(() => _inquiryOffNotice = n),
                textController: _inquiryOffTextCtrl,
              ),
            ),

            if (_products.isNotEmpty) ...[
              const SizedBox(height: 16),
              _label('연결 상품 (선택)'),
              const Text(
                '결제가 필요한 내용은 상품으로 걸어두면, 손님이 이벤트에서 바로\n'
                '구매로 넘어갈 수 있어요.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.black45,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              for (final p in _products)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: accent,
                  value: _linkedProductIds.contains(p.id),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _linkedProductIds.add(p.id);
                    } else {
                      _linkedProductIds.remove(p.id);
                    }
                  }),
                  title: Text(
                    '${p.type.emoji} ${p.name}',
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 8, 18, 12),
        child: SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: accent.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: _saving
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _uploadNote ?? '저장 중...',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                : Text(
                    _isEdit ? '수정 완료' : '이벤트 등록',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ── 작은 조각들 ──────────────────────────────────────────────────────────

  /// 유형 한 줄이 무엇을 뜻하는지 — 카드 아래 범례.
  ///
  /// ⚠️ 여기 적는 것은 **설명뿐**이다. 저장값([PromotionType.key])도, 그 값이
  ///    손님 탐색 갈래로 번역되는 표
  ///    ([PlaceEventTaxonomy.kindsOfPromotion] — event→특별, benefit→할인·혜택,
  ///    package→증정)도 건드리지 않는다. 문구가 그 표와 어긋나지 않게 쓴다:
  ///    호스트가 읽은 뜻과 손님이 걸러 보는 갈래가 달라지면, 고른 대로 찾히지
  ///    않는다.
  static String _meaningOf(PromotionType t) => switch (t) {
    PromotionType.event => '공연·DJ·시즌 행사 등 특별한 매장 행사',
    PromotionType.benefit => '가격 할인·해피아워 등 할인 중심 혜택',
    PromotionType.package => '증정·1+1·웰컴드링크 등 묶음·증정 혜택',
  };

  Widget _typeMeaning(PromotionType t) {
    final selected = _type == t;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${t.emoji} ${t.label} ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                // 고른 유형만 색으로 세운다 — 어느 설명이 내 선택인지 범례에서
                // 바로 보인다.
                color: selected ? widget.accent : Colors.black54,
              ),
            ),
            TextSpan(text: '— ${_meaningOf(t)}'),
          ],
        ),
        style: const TextStyle(
          fontSize: 11.5,
          color: Colors.black45,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    ),
  );

  Widget _field(
    TextEditingController ctrl, {
    String? hint,
    int maxLines = 1,
    int? maxLength,
  }) => TextField(
    controller: ctrl,
    maxLines: maxLines,
    maxLength: maxLength,
    style: const TextStyle(fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13.5, color: Colors.black26),
      filled: true,
      fillColor: const Color(0xFFF7F7FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide.none,
      ),
    ),
  );

  /// 영업중(전시간) / 시간 지정 두 칸 — 앱의 다른 선택 칩과 같은 모양이다.
  Widget _timeModeChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final accent = widget.accent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accent : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : const Color(0xFFE8EBF2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF4A4A55),
          ),
        ),
      ),
    );
  }

  Widget _pickerBox({
    required String label,
    required String? value,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value ?? label,
              style: TextStyle(
                fontSize: 13.5,
                color: value == null ? Colors.black26 : Colors.black87,
                fontWeight: value == null ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ),
          if (onClear != null)
            GestureDetector(
              onTap: onClear,
              child: const Icon(Icons.close, size: 16, color: Colors.black38),
            )
          else
            const Icon(Icons.expand_more, size: 18, color: Colors.black38),
        ],
      ),
    ),
  );
}
