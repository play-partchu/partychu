import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/models/address_result.dart';
import 'package:party_app/models/made_to_order.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/draft_type.dart';
import 'package:party_app/models/shop_coupon.dart';
import 'package:party_app/screens/address_search_screen.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/utils/draftable_register.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/register_return_signal.dart';
import 'package:party_app/utils/register_validation.dart';
import 'package:party_app/widgets/party_form/register_field_anchor.dart';
import 'package:party_app/widgets/party_form/register_missing_fields_banner.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/screens/party_media_picker_screen.dart';
import 'package:party_app/services/media_upload_service.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/utils/video_crop.dart';
import 'package:party_app/widgets/party_media_editor.dart';
import 'package:party_app/widgets/web_frame.dart';

class PartyMarketRegisterScreen extends StatefulWidget {
  /// 마이페이지 "임시저장" 목록에서 "이어서 작성"으로 열 때 true.
  final bool autoRestoreDraft;

  const PartyMarketRegisterScreen({super.key, this.autoRestoreDraft = false});

  @override
  State<PartyMarketRegisterScreen> createState() =>
      _PartyMarketRegisterScreenState();
}

class _PartyMarketRegisterScreenState extends State<PartyMarketRegisterScreen>
    with WidgetsBindingObserver, DraftableRegister<PartyMarketRegisterScreen> {
  @override
  void setState(VoidCallback fn) {
    markDraftDirty();
    super.setState(fn);
  }

  @override
  DraftType get draftType => DraftType.market;

  @override
  bool get draftAutoRestore => widget.autoRestoreDraft;

  @override
  String get draftTitle => _nameCtrl.text;

  /// 대표 이미지가 아직 로컬 파일이라 목록에 보여줄 원격 URL이 없다.
  @override
  String? get draftCoverImageUrl => null;

  @override
  Map<String, dynamic> buildDraftPayload() {
    return <String, dynamic>{
      'name': _nameCtrl.text,
      'description': _descCtrl.text,
      'isActive': _isActive,
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
      'deliveryOpts': _deliveryOpts.toList(),
      'autoMessages': {
        for (final e in _autoMsgCtrls.entries) e.key: e.value.text,
      },
      'hasCoupon': _hasCoupon,
      'couponCondition': _couponCondition.key,
      'couponDiscType': _couponDiscType,
      'couponMin': _couponMinCtrl.text,
      'couponQty': _couponQtyCtrl.text,
      'couponValue': _couponValueCtrl.text,
      // 상품 목록 — XFile은 JSON으로 못 담으므로 경로만 남긴다.
      'products': _localProducts.map((p) {
        final copy = Map<String, dynamic>.from(p)..remove('_localImages');
        copy['_localImagePaths'] = [
          for (final f in (p['_localImages'] as List<XFile>?) ?? const <XFile>[])
            LocalMedia.remember(f).path,
        ];
        return copy;
      }).toList(),
      // 사진/동영상 — 공용 픽커의 스냅샷을 그대로 담는다(플레이스와 같은 모양).
      // 로컬 파일은 경로만 남긴다(파일이 사라지면 복원 시 재선택 안내).
      'coverExistingImageUrls': _coverExistingImageUrls,
      'coverExistingVideoUrl': _coverExistingVideoUrl,
      'coverExistingVideoUid': _coverExistingVideoUid,
      'coverExistingVideoThumbnailUrl': _coverExistingVideoThumbnailUrl,
      'coverNewFilePaths': [
        for (final f in _coverNewFiles) LocalMedia.remember(f).path,
      ],
      'coverBasicCardFocalX': _coverBasicCardFocalX,
      'coverBasicCardFocalY': _coverBasicCardFocalY,
      'coverBasicCardScale': _coverBasicCardScale,
      'coverPhotoCrops': _coverPhotoCrops,
      'coverVideoCropConfirmed': _coverVideoCropConfirmed,
      'coverPick': _coverPick == null
          ? null
          : {
              'existingImageUrl': _coverPick!.existingImageUrl,
              'isExistingVideo': _coverPick!.isExistingVideo,
              'newImageOrdinal': _coverPick!.newImageOrdinal,
              'isNewVideo': _coverPick!.isNewVideo,
            },
    };
  }

  @override
  void applyDraftPayload(Map<String, dynamic> p) {
    _nameCtrl.text = (p['name'] as String?) ?? '';
    _descCtrl.text = (p['description'] as String?) ?? '';
    _detailAddressCtrl.text = (p['detailAddress'] as String?) ?? '';
    _isActive = p['isActive'] as bool? ?? true;

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

    _deliveryOpts
      ..clear()
      ..addAll((p['deliveryOpts'] as List?)?.cast<String>() ?? const []);
    final msgs = p['autoMessages'] as Map?;
    for (final entry in _autoMsgCtrls.entries) {
      entry.value.text = (msgs?[entry.key] as String?) ?? '';
    }

    _hasCoupon = p['hasCoupon'] as bool? ?? false;
    _couponMinCtrl.text = (p['couponMin'] as String?) ?? '';
    _couponQtyCtrl.text = (p['couponQty'] as String?) ?? '';
    // 조건 필드가 없던 시절의 임시저장 — 최소 금액이 적혀 있으면 금액 조건이었다.
    _couponCondition =
        ShopCouponCondition.fromKey(p['couponCondition'] as String?) ??
        ((int.tryParse(_couponMinCtrl.text.trim()) ?? 0) > 0
            ? ShopCouponCondition.minAmount
            : ShopCouponCondition.visit);
    _couponDiscType = p['couponDiscType'] as String? ?? kShopCouponPercentLabel;
    _couponValueCtrl.text = (p['couponValue'] as String?) ?? '';

    bool anyMissing = false;

    // 상품 — 이미지 경로가 살아있는 것만 되살린다.
    _localProducts.clear();
    for (final raw in (p['products'] as List?) ?? const []) {
      final m = Map<String, dynamic>.from(raw as Map);
      final paths =
          (m.remove('_localImagePaths') as List?)?.cast<String>() ?? const [];
      final files = <XFile>[];
      for (final path in paths) {
        if (LocalMedia.exists(path)) {
          files.add(LocalMedia.resolve(path));
        } else {
          anyMissing = true;
        }
      }
      m['_localImages'] = files;
      _localProducts.add(m);
    }

    // 사진/동영상 — 공용 픽커 스냅샷 되돌리기(플레이스 등록과 같은 모양).
    _coverExistingImageUrls = [
      ...((p['coverExistingImageUrls'] as List?)?.cast<String>() ?? const []),
    ];
    _coverExistingVideoUrl = p['coverExistingVideoUrl'] as String?;
    _coverExistingVideoUid = p['coverExistingVideoUid'] as String?;
    _coverExistingVideoThumbnailUrl =
        p['coverExistingVideoThumbnailUrl'] as String?;
    _coverNewFiles = [];
    for (final path
        in (p['coverNewFilePaths'] as List?)?.cast<String>() ?? const []) {
      if (LocalMedia.exists(path)) {
        _coverNewFiles.add(LocalMedia.resolve(path));
      } else {
        anyMissing = true;
      }
    }
    _coverBasicCardFocalX =
        (p['coverBasicCardFocalX'] as num?)?.toDouble() ?? 0.5;
    _coverBasicCardFocalY =
        (p['coverBasicCardFocalY'] as num?)?.toDouble() ?? 0.5;
    _coverBasicCardScale =
        (p['coverBasicCardScale'] as num?)?.toDouble() ?? 1.0;
    _coverPhotoCrops = photoCropsFromRaw(p['coverPhotoCrops']);
    _coverVideoCropConfirmed = p['coverVideoCropConfirmed'] as bool? ?? false;
    final coverPick = p['coverPick'] as Map?;
    _coverPick = coverPick == null
        ? null
        : PartyCoverPick(
            existingImageUrl: coverPick['existingImageUrl'] as String?,
            isExistingVideo: coverPick['isExistingVideo'] as bool? ?? false,
            newImageOrdinal: (coverPick['newImageOrdinal'] as num?)?.toInt(),
            isNewVideo: coverPick['isNewVideo'] as bool? ?? false,
          );
    draftMediaNeedsReselect = anyMissing;
  }

  @override
  void initState() {
    super.initState();
    for (final c in [
      _nameCtrl,
      _descCtrl,
      _detailAddressCtrl,
      _couponMinCtrl,
      _couponQtyCtrl,
      _couponValueCtrl,
      ..._autoMsgCtrls.values,
    ]) {
      c.addListener(markDraftDirty);
    }
    initDraft();
  }

  // ── 기본 정보 ─────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isActive = true;

  // ── 매장 주소 (검색 기반) ─────────────────────────────────────────
  AddressResult? _selectedAddress;
  final _detailAddressCtrl = TextEditingController();

  // ── 사진 / 동영상 ────────────────────────────────────────────────
  // 상태는 아래 '사진 / 동영상 — 공용 픽커 하나' 구획에 모여 있다
  // ([_coverExistingImageUrls] 등). 예전의 `_mainImage` / `_introImages` /
  // [SingleVideoPicker]는 그 픽커 하나로 합쳐져 사라졌다.
  final _picker = ImagePicker();

  /// 동영상 압축 중에는 등록 버튼을 막는다. 압축은 이제 공용 픽커 화면 안에서
  /// 끝나므로 이 화면이 압축 중일 일은 없지만, 버튼 조건은 그대로 둔다.
  final bool _isCompressingVideo = false;

  // ── 배송/수령 옵션 ─────────────────────────────────────────────
  static const _allDeliveryOpts = [
    'sameDay',
    'pickup',
    'delivery',
    'scheduled',
  ];
  static const _deliveryLabels = <String, String>{
    'sameDay': '당일 퀵',
    'pickup': '방문수령',
    'delivery': '택배',
    'scheduled': '지정일 배송',
  };
  static const _deliveryIcons = <String, IconData>{
    'sameDay': Icons.flash_on_outlined,
    'pickup': Icons.store_outlined,
    'delivery': Icons.local_shipping_outlined,
    'scheduled': Icons.calendar_today_outlined,
  };
  final Set<String> _deliveryOpts = {};

  // ── 쿠폰 ─────────────────────────────────────────────────────────
  bool _hasCoupon = false;
  ShopCouponCondition _couponCondition = ShopCouponCondition.visit;
  String _couponDiscType = kShopCouponPercentLabel;
  final _couponMinCtrl = TextEditingController();
  final _couponQtyCtrl = TextEditingController();
  final _couponValueCtrl = TextEditingController();

  // ── 자동발송 문구 ─────────────────────────────────────────────────
  final _autoMsgCtrls = <String, TextEditingController>{
    'sameDay': TextEditingController(),
    'pickup': TextEditingController(),
    'delivery': TextEditingController(),
    'scheduled': TextEditingController(),
  };

  // ── 상품 목록 (등록 전 로컬 보관) ────────────────────────────────
  final List<Map<String, dynamic>> _localProducts = [];

  // ── 유효성 ────────────────────────────────────────────────────────
  bool _showNameError = false;

  // 필수항목 안내는 다른 등록 화면과 **같은 공용 구조**를 쓴다 —
  // 화면마다 따로 스크롤·강조 로직을 만들지 않기 위해서다
  // ([RegisterFieldCheck] / [RegisterFieldAnchor]).
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _nameKey = GlobalKey();
  final FocusNode _nameFocus = FocusNode();
  List<RegisterFieldCheck> _missingFields = const [];
  bool _isSubmitting = false;

  @override
  void dispose() {
    disposeDraft();
    _scrollCtrl.dispose();
    _nameFocus.dispose();
    // 이 화면을 떠나면 강조도 함께 끈다 — 타이머가 화면보다 오래 남지 않게.
    RegisterValidation.clearHighlight();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _detailAddressCtrl.dispose();
    _couponMinCtrl.dispose();
    _couponQtyCtrl.dispose();
    _couponValueCtrl.dispose();
    for (final c in _autoMsgCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 쿠폰 입력칸의 숫자 읽기 — 비었거나 숫자가 아니면 0.
  static int _couponInt(String text) =>
      int.tryParse(text.trim().replaceAll(',', '')) ?? 0;

  // ── 제출 ─────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (UserSession.userId.isEmpty) {
      _msg('로그인이 필요합니다.');
      return;
    }
    // 필수값 검증 — 조건·문구는 그대로다. 안내만 다른 등록 화면과 같은
    // 공용 경로를 타서, 배너의 줄을 눌러도 그 입력칸으로 가게 한다.
    final nameMissing = _nameCtrl.text.trim().isEmpty;
    setState(() => _showNameError = nameMissing);
    final checks = [
      RegisterFieldCheck(
        missing: nameMissing,
        message: '샵 이름을 입력해주세요.',
        anchorKey: _nameKey,
        focusNode: _nameFocus,
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
      // ── 사진 / 동영상 — 공용 업로더 하나 ─────────────────────────
      // 파티·플레이스와 **같은 함수**를 쓴다([MediaUploadService]). 올리기
      // 전에 경로·존재·크기를 확인하고, 실패하면 어떤 파일이 왜 실패했는지를
      // 담아 던진다.
      final coverUpload = await MediaUploadService.uploadNewMedia(
        media: _coverNewFiles,
        logTag: 'shop-cover',
      );
      // 화면에 보이던 순서 그대로 — 남겨둔 기존 사진 뒤에 새로 고른 것.
      final coverImageUrls = [
        ..._coverExistingImageUrls,
        ...coverUpload.imageUrls,
      ];
      final videoUid = coverUpload.videoUid ?? _coverExistingVideoUid;
      final videoUrl = coverUpload.videoUrl ?? _coverExistingVideoUrl;
      final videoThumbnailUrl =
          coverUpload.videoThumbnailUrl ?? _coverExistingVideoThumbnailUrl;

      // 대표 계약 — 읽는 쪽이 하나뿐이라([getPartyCoverMedia]) 쓰는 쪽도
      // 하나여야 한다. 파티샵 전용 대표 규칙을 따로 만들지 않는다.
      final coverFields = MediaUploadService.resolveCoverFields(
        coverPick: _coverPick,
        imageUrls: coverImageUrls,
        uploadedImageUrls: coverUpload.imageUrls,
        videoUrl: videoUrl,
        videoUid: videoUid,
        videoThumbnailUrl: videoThumbnailUrl,
      );
      final coverPhotoCrops = MediaUploadService.resolvePhotoCropKeys(
        crops: _coverPhotoCrops,
        existingImageUrls: _coverExistingImageUrls,
        newMedia: _coverNewFiles,
        uploadedImageUrls: coverUpload.imageUrls,
      );

      // 예전 필드로 옮겨 적기 — 대표 사진이 `mainImageUrl`, 나머지가
      // `introImageUrls`다. 상세 화면이 이미 둘을 이어 붙여 한 갤러리로
      // 그리므로([PartyShopDetailScreen]) 보이는 모습은 그대로다.
      // 대표가 동영상이면 사진 순서는 건드리지 않고 첫 장이 `mainImageUrl`이
      // 된다 — 대표 계약을 읽지 못하는 옛 화면도 빈 카드가 되지 않는다.
      final coverImageUrl = coverFields['coverImageUrl'] as String?;
      final orderedPhotos = <String>[
        if (coverImageUrl != null && coverImageUrls.contains(coverImageUrl))
          coverImageUrl,
        for (final u in coverImageUrls)
          if (u != coverImageUrl) u,
      ];
      final mainUrl = orderedPhotos.isEmpty ? '' : orderedPhotos.first;
      final introUrls = orderedPhotos.skip(1).toList();

      final autoMsgs = <String, String>{
        for (final key in _deliveryOpts)
          if ((_autoMsgCtrls[key]?.text.trim() ?? '').isNotEmpty)
            key: _autoMsgCtrls[key]!.text.trim(),
      };

      // 상세검색용 집계값 — 등록된 상품들의 카테고리/최저가/할인여부/재고여부
      final categories = _localProducts
          .map((p) => p['category'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final positivePrices = _localProducts
          .map((p) => (p['price'] as int?) ?? 0)
          .where((p) => p > 0);
      final priceFrom = positivePrices.isEmpty
          ? 0
          : positivePrices.reduce((a, b) => a < b ? a : b);
      final hasDiscount = _localProducts.any((p) => p['isOnSale'] == true);
      // 🛠 주문제작 상품은 재고를 세지 않는다 — 여기서 빼면 주문제작만 파는
      // 샵이 '재고 있음' 검색에서 통째로 사라진다([shopProductInStock]).
      final hasStock = _localProducts.any(
        (p) => shopProductInStock(
          stock: (p['stock'] as int?) ?? 0,
          madeToOrder: p[kMadeToOrderField] == true,
        ),
      );

      final doc = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'mainImageUrl': mainUrl,
        'introImageUrls': introUrls,
        if (videoUrl != null) 'videoProvider': 'cloudflare',
        if (videoUid != null) 'videoUid': videoUid,
        if (videoUrl != null) 'videoUrl': videoUrl,
        if (videoThumbnailUrl != null) 'videoThumbnailUrl': videoThumbnailUrl,
        // ── 대표 미디어 계약 — 카드·상세가 읽는 키 그대로 ────────────
        // 파티샵 전용 키가 아니다. 파티·플레이스·이벤트가 쓰는 그 이름이고,
        // 읽는 쪽도 [getPartyCoverMedia] 하나뿐이다. 이 필드가 없던 옛
        // 문서는 예전처럼 레거시 분기로 읽히므로 보이는 모습이 달라지지
        // 않는다(대표였던 사진을 지웠을 때의 되돌림도 그 공용 규칙이 맡는다).
        ...coverFields,
        'basicCardVideoFocalX': _coverBasicCardFocalX,
        'basicCardVideoFocalY': _coverBasicCardFocalY,
        'basicCardVideoScale': _coverBasicCardScale,
        'basicCardPhotoCrops': coverPhotoCrops,
        'address': _selectedAddress?.address ?? '',
        'roadAddress': _selectedAddress?.roadAddress ?? '',
        'jibunAddress': _selectedAddress?.jibunAddress ?? '',
        'latitude': _selectedAddress?.latitude ?? 0.0,
        'longitude': _selectedAddress?.longitude ?? 0.0,
        'detailAddress': _detailAddressCtrl.text.trim(),
        'location': _selectedAddress != null
            ? '${_selectedAddress!.address}'
                  '${_detailAddressCtrl.text.trim().isNotEmpty ? ' ${_detailAddressCtrl.text.trim()}' : ''}'
            : '',
        'isActive': _isActive,
        'deliveryOptions': _deliveryOpts.toList(),
        'autoMessages': autoMsgs,
        ..._draftCoupon.toShopFields(),
        // 상세검색용 집계값 (상품 추가/변경 시 party_shop_product_register_screen.dart에서도 갱신)
        'categories': categories,
        'priceFrom': priceFrom,
        'hasDiscount': hasDiscount,
        'hasStock': hasStock,
        'hostId': UserSession.userId,
        'hostName': UserSession.displayName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final ref = await FirebaseFirestore.instance
          .collection('partyShops')
          .add(doc);

      // 로컬에 미리 추가한 상품들 저장 — 상품별 이미지는 샵이 생성된 지금
      // 업로드하고 _localImages(로컬 파일 목록)는 Firestore에 저장하지 않는다.
      for (final product in _localProducts) {
        final localImages =
            (product['_localImages'] as List<XFile>?) ?? const <XFile>[];
        final productImgUrls = <String>[];
        for (final img in localImages) {
          productImgUrls.add(
            await CloudflareService.uploadImage(img),
          );
        }
        final productData = Map<String, dynamic>.from(product)
          ..remove('_localImages')
          ..['imageUrls'] = productImgUrls;

        await FirebaseFirestore.instance
            .collection('partyShops')
            .doc(ref.id)
            .collection('products')
            .add(<String, dynamic>{
              ...productData,
              'hostId': UserSession.userId,
              'shopId': ref.id,
              'deliveryOptions': _deliveryOpts.toList(),
              'isSameDayAvailable': _deliveryOpts.contains('sameDay'),
              'isCouponApplicable': _hasCoupon,
              'autoMessages': <String, String>{},
              'createdAt': FieldValue.serverTimestamp(),
            });
      }

      // 최종 등록 완료 — 파티샵 임시저장은 자동 삭제.
      await deleteCurrentDraft();

      if (!mounted) return;
      // 등록 화면이 몇 단계 깊이 열려 있었든(모바일: RegisterTypeScreen 경유,
      // 데스크톱: MainScreen에서 바로) 곧장 메인화면 플레이스 탭의 파티샵
      // 카테고리로 복귀한다(파티샵은 더 이상 독립 탭이 아님).
      pendingTopTabAfterRegister.value = 1;
      pendingPlaceShopCategoryAfterRegister.value = true;
      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (_) {
      if (mounted) _msg('등록 중 오류가 발생했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(t), behavior: SnackBarBehavior.floating),
  );

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
          title: const Text(
            '파티샵 등록',
            style: TextStyle(
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
          actions: [draftSaveAction()],
          bottom: buildAutoSaveIndicator(),
        ),
        body: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (draftMediaNeedsReselect) buildMediaReselectBanner(),
              RegisterMissingFieldsBanner(fields: _missingFields),

              // ── 1. 샵 이름 ───────────────────────────────────────────
              _label('샵 이름', required: true),
              RegisterFieldAnchor(
                key: _nameKey,
                child: TextField(
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _showNameError = false),
                  decoration: _deco('샵 이름을 입력해주세요', error: _showNameError),
                ),
              ),
              const SizedBox(height: 22),

              // ── 2. 사진 / 동영상 ─────────────────────────────────────
              //
              // 파티·플레이스·장소대여와 **같은 공용 픽커** 하나를 연다
              // ([PartyMediaPickerScreen] → [PartyMediaEditor]). 예전에는
              // '대표 이미지 1장' 피커와 '소개 이미지' 피커와
              // [SingleVideoPicker]가 따로 서 있어서
              //  · 사진과 동영상 중 무엇이 대표인지 고를 수 없었고,
              //  · 어느 사진이 대표인지 화면에 표시되지 않았으며,
              //  · 순서 변경·크롭이 아예 없었다.
              _label('사진 / 동영상'),
              _buildCoverMediaPicker(),
              const SizedBox(height: 4),
              const Text(
                '사진 최대 $_coverMaxImages장 · 동영상 1개 · 대표로 고른 것이 카드에 뜹니다',
                style: TextStyle(fontSize: 11, color: Colors.black38),
              ),
              const SizedBox(height: 22),

              // ── 4. 샵 설명 ───────────────────────────────────────────
              _label('샵 설명'),
              TextField(
                controller: _descCtrl,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: _deco('샵을 소개해주세요.'),
              ),
              const SizedBox(height: 22),

              // ── 5. 매장 위치 ─────────────────────────────────────────
              _label('매장 위치'),
              _buildLocationSection(),
              const SizedBox(height: 22),

              // ── 6. 운영 여부 ─────────────────────────────────────────
              _buildToggleRow(
                icon: Icons.storefront_outlined,
                title: '운영 중',
                desc: '샵이 현재 운영 중인지 설정해요.',
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              const SizedBox(height: 14),

              // ── 7. 구매/수령 가능 옵션 ───────────────────────────────
              _label('구매/수령 가능 옵션'),
              _buildDeliveryCheckboxes(),
              const SizedBox(height: 22),

              // ── 8. 자동발송 문구 ─────────────────────────────────────
              if (_deliveryOpts.isNotEmpty) ...[
                _buildAutoMsgSection(),
                const SizedBox(height: 22),
              ],

              // ── 9. 방문 할인쿠폰 ─────────────────────────────────────
              _buildCouponSection(),
              const SizedBox(height: 22),

              // ── 10. 판매 상품 목록 ────────────────────────────────────
              _buildProductSection(),
              const SizedBox(height: 32),

              // ── 제출 버튼 ────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_isSubmitting || _isCompressingVideo)
                      ? null
                      : _submit,
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
                      : const Text(
                          '파티샵 등록하기',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
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

  // ── 사진 / 동영상 — 공용 픽커 하나 ───────────────────────────────
  //
  // 파티·플레이스·장소대여가 쓰는 그 화면을 그대로 연다. 그 안에서
  //   사진/동영상 선택 → (동영상이면) 트림·압축 → **대표 지정** →
  //   순서 변경 → 사진 크롭 / 카드 노출 위치 조정 → 선택 완료
  // 까지 끝난다. 이 화면은 결과 스냅샷만 들고 있다가 저장할 때 옮겨 적는다.
  //
  // 저장 필드는 **예전 그대로**다(새 필드를 만들지 않았다):
  //   · 대표로 고른 사진 → `mainImageUrl`
  //   · 나머지 사진      → `introImageUrls` (고른 순서 그대로)
  //   · 동영상           → `videoUid` / `videoUrl` / `videoThumbnailUrl`
  // 상세 화면은 이미 `[mainImageUrl, ...introImageUrls]`를 **한 줄의 갤러리**로
  // 그리고 있었다([PartyShopDetailScreen]) — 그래서 이 매핑으로 기존 문서의
  // 보이는 모습이 달라지지 않는다.
  //
  // 여기에 더해 앱 전체가 읽는 **대표 계약**(`coverMediaType`/`coverImageUrl`/
  // `coverVideoUid`/`coverVideoUrl`/`coverThumbnailUrl`)을 함께 적는다 —
  // 이 키들은 파티샵 전용이 아니라 [getPartyCoverMedia]가 읽는 공용 정본이다.

  /// 사진 최대 장수 — 예전 저장 구조가 담을 수 있던 만큼 그대로다
  /// (대표 1장 + 소개 6장). 늘리지도 줄이지도 않았다.
  static const int _coverMaxImages = 7;

  /// 이미 올라가 있는 사진들 — `[mainImageUrl, ...introImageUrls]` 순서.
  List<String> _coverExistingImageUrls = [];
  String? _coverExistingVideoUrl;
  String? _coverExistingVideoUid;
  String? _coverExistingVideoThumbnailUrl;
  List<XFile> _coverNewFiles = [];
  PartyCoverPick? _coverPick;
  double _coverBasicCardFocalX = 0.5;
  double _coverBasicCardFocalY = 0.5;
  double _coverBasicCardScale = 1.0;
  Map<String, Map<String, double>> _coverPhotoCrops = {};
  bool _coverVideoCropConfirmed = false;

  bool get _coverHasVideo =>
      (_coverExistingVideoUrl ?? '').isNotEmpty ||
      _coverNewFiles.any(MediaUploadService.isVideoFile);

  int get _coverPhotoCount =>
      _coverExistingImageUrls.length +
      _coverNewFiles.where((f) => !MediaUploadService.isVideoFile(f)).length;

  String? _coverSummary() {
    final parts = <String>[
      if (_coverPhotoCount > 0) '사진 $_coverPhotoCount장',
      if (_coverHasVideo) '동영상 1개',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<void> _openCoverMediaPicker() async {
    final result = await Navigator.push<PartyMediaSelection>(
      context,
      webFramedRoute(
        (_) => PartyMediaPickerScreen(
          existingImageUrls: _coverExistingImageUrls,
          existingVideoUrl: _coverExistingVideoUrl,
          existingVideoUid: _coverExistingVideoUid,
          existingVideoThumbnailUrl: _coverExistingVideoThumbnailUrl,
          newMedia: _coverNewFiles,
          coverPick: _coverPick,
          basicCardFocalX: _coverBasicCardFocalX,
          basicCardFocalY: _coverBasicCardFocalY,
          basicCardScale: _coverBasicCardScale,
          photoCrops: _coverPhotoCrops,
          videoCropConfirmed: _coverVideoCropConfirmed,
          maxImages: _coverMaxImages,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _coverExistingImageUrls = result.existingImageUrls;
      _coverExistingVideoUrl = result.existingVideoUrl;
      _coverExistingVideoUid = result.existingVideoUid;
      _coverExistingVideoThumbnailUrl = result.existingVideoThumbnailUrl;
      _coverNewFiles = result.newMedia;
      _coverPick = result.coverPick;
      _coverBasicCardFocalX = result.basicCardFocalX;
      _coverBasicCardFocalY = result.basicCardFocalY;
      _coverBasicCardScale = result.basicCardScale;
      _coverPhotoCrops = result.photoCrops;
      _coverVideoCropConfirmed = result.videoCropConfirmed;
    });
  }

  Widget _buildCoverMediaPicker() {
    final summary = _coverSummary();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              summary,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _openCoverMediaPicker,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: Text(summary == null ? '사진 / 동영상 등록' : '사진 / 동영상 수정'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFF6FA0),
            side: const BorderSide(color: Color(0xFFFF6FA0)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  // ── 배송/수령 옵션 체크박스 ──────────────────────────────────────
  Widget _buildDeliveryCheckboxes() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        children: List.generate(_allDeliveryOpts.length, (i) {
          final key = _allDeliveryOpts[i];
          final sel = _deliveryOpts.contains(key);
          final isLast = i == _allDeliveryOpts.length - 1;
          return GestureDetector(
            onTap: () => setState(() {
              if (sel) {
                _deliveryOpts.remove(key);
              } else {
                _deliveryOpts.add(key);
              }
            }),
            child: Container(
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : const Border(
                        bottom: BorderSide(color: Color(0xFFF2F2F5)),
                      ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFFFF6FA0) : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: sel
                            ? const Color(0xFFFF6FA0)
                            : const Color(0xFFD0D0D8),
                        width: 1.5,
                      ),
                    ),
                    child: sel
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    _deliveryIcons[key]!,
                    size: 18,
                    color: sel ? const Color(0xFFFF6FA0) : Colors.black38,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _deliveryLabels[key]!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: sel ? const Color(0xFFFF6FA0) : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── 자동발송 문구 섹션 ────────────────────────────────────────────
  Widget _buildAutoMsgSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('자동 안내 문구 설정'),
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
                      '예약/수령 시간 2시간 전에 구매자에게 자동 발송돼요.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFFF6FA0)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._allDeliveryOpts
                  .where(_deliveryOpts.contains)
                  .map(
                    (key) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _deliveryIcons[key]!,
                                size: 14,
                                color: Colors.black54,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _deliveryLabels[key]!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Text(
                                ' 선택자용',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black45,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _autoMsgCtrls[key],
                            maxLines: 3,
                            decoration: _deco('예: 수령 2시간 전 안내드립니다...'),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 쿠폰 섹션 ────────────────────────────────────────────────────
  /// 지금 입력 중인 값으로 만든 쿠폰 — 미리보기 문구와 실제 저장이 같은
  /// 규칙을 쓰도록 한 곳에서 만든다.
  ShopCoupon get _draftCoupon => ShopCoupon(
    enabled: _hasCoupon,
    condition: _couponCondition,
    discountType: _couponDiscType == kShopCouponPercentLabel
        ? kShopCouponPercent
        : kShopCouponAmount,
    discountValue: _couponInt(_couponValueCtrl.text),
    minAmount: _couponInt(_couponMinCtrl.text),
    minQuantity: _couponInt(_couponQtyCtrl.text),
  );

  /// 할인 조건 한 줄 — 라디오처럼 하나만 고른다.
  Widget _couponConditionTile(ShopCouponCondition c) {
    final sel = _couponCondition == c;
    return GestureDetector(
      onTap: () => setState(() => _couponCondition = c),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFFFE6EF) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: sel ? const Color(0xFFFF6FA0) : Colors.black26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                c.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sel ? const Color(0xFFD6437A) : Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCouponSection() {
    final isPercent = _couponDiscType == kShopCouponPercentLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '할인쿠폰',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            Switch(
              value: _hasCoupon,
              onChanged: (v) => setState(() => _hasCoupon = v),
              activeThumbColor: const Color(0xFFFF6FA0),
              activeTrackColor: const Color(0xFFFFB8D0),
            ),
          ],
        ),
        if (_hasCoupon) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFD6E4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 할인 조건
                const Text(
                  '할인 조건',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...ShopCouponCondition.values.map(_couponConditionTile),

                // 고른 조건에 필요한 입력칸만 나온다.
                if (_couponCondition == ShopCouponCondition.minAmount) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '최소 구매 금액',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _couponMinCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _deco('예: 30000 (3만원 이상 구매 시)', suffix: '원'),
                  ),
                ],
                if (_couponCondition == ShopCouponCondition.minQuantity) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '최소 수량',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _couponQtyCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _deco('예: 2 (2개 이상 구매 시)', suffix: '개'),
                  ),
                ],
                const SizedBox(height: 14),
                // 할인 방식
                const Text(
                  '할인 방식',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [kShopCouponPercentLabel, kShopCouponAmountLabel]
                      .map((t) {
                        final sel = _couponDiscType == t;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _couponDiscType = t),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: EdgeInsets.only(
                                right: t == kShopCouponPercentLabel ? 8 : 0,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: sel
                                    ? const Color(0xFFFF6FA0)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: sel
                                      ? const Color(0xFFFF6FA0)
                                      : const Color(0xFFE8EBF2),
                                  width: sel ? 1.5 : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                t,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: sel ? Colors.white : Colors.black54,
                                ),
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(),
                ),
                const SizedBox(height: 14),
                Text(
                  isPercent ? '할인율 (%)' : '할인 금액 (원)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _couponValueCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _deco(
                    isPercent ? '예: 10 (10% 할인)' : '예: 5000 (5,000원 할인)',
                    suffix: isPercent ? '%' : '원',
                  ),
                ),
                const SizedBox(height: 14),
                // 손님에게 보이는 문구 미리보기 — 조건까지 그대로 읽힌다.
                AnimatedBuilder(
                  animation: Listenable.merge([
                    _couponMinCtrl,
                    _couponQtyCtrl,
                    _couponValueCtrl,
                  ]),
                  builder: (_, _) => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF9E6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFE08A)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.local_offer_outlined,
                          size: 14,
                          color: Color(0xFFE89200),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '손님에게 이렇게 보여요 — ${_draftCoupon.guestLabel}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFE89200),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_couponCondition == ShopCouponCondition.minQuantity) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '수량 조건은 주문 화면에서 자동으로 깎이지 않고 조건만 안내돼요 '
                    '— 온라인 주문에는 수량 개념이 없어서예요.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black45,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── 공통 위젯 ────────────────────────────────────────────────────
  Widget _buildToggleRow({
    required IconData icon,
    required String title,
    required String desc,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE8EBF2)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFFFF6FA0)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              Text(
                desc,
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: const Color(0xFFFF6FA0),
          activeTrackColor: const Color(0xFFFFB8D0),
        ),
      ],
    ),
  );

  // ── 🛠 주문제작 ────────────────────────────────────────────────────
  //
  // 재고 수량 칸 아래 붙는 체크란과, 켰을 때만 뜨는 안내 한 줄.
  // 저장되는 것은 불리언 하나뿐이고([kMadeToOrderField]), 주문 상태·결제·환불
  // 흐름은 아무것도 달라지지 않는다.

  /// 재고 수량 아래의 '주문제작' 체크란.
  Widget _madeToOrderCheck({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: const Color(0xFFFF6FA0),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 6),
          // 좁은 칸(폭 절반)이라 긴 화면에서도 접히지 않게 Flexible로 둔다.
          Flexible(
            child: Text(
              kMadeToOrderLabel,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  /// 체크했을 때만 뜨는 안내 — 무엇인지 한 줄 + 호스트가 할 일 한 줄.
  ///
  /// 문구의 정본은 [kMadeToOrderNotice]/[kMadeToOrderHostNotice]다. 게스트
  /// 화면도 같은 상수를 쓰므로 호스트가 여기서 읽은 말과 손님이 보는 말이
  /// 갈라지지 않는다.
  Widget _madeToOrderHostNote() => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0F5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFD6E4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kMadeToOrderBadge,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFFFF6FA0),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          kMadeToOrderNotice,
          style: TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.5),
        ),
        const Text(
          kMadeToOrderHostNotice,
          style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.5),
        ),
      ],
    ),
  );

  Widget _label(String text, {bool required = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFFFF6FA0),
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    ),
  );

  InputDecoration _deco(String hint, {String? suffix, bool error = false}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
        suffixText: suffix,
        suffixStyle: const TextStyle(color: Colors.black45, fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: error ? Colors.redAccent : const Color(0xFFE8EBF2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: error ? Colors.redAccent : const Color(0xFFE8EBF2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF6FA0)),
        ),
      );

  String _fmtPrice(int p) => formatPrice(p);

  // ── 판매 상품 목록 섹션 ───────────────────────────────────────────
  Widget _buildProductSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _label('판매 상품 목록'),
            const Spacer(),
            TextButton.icon(
              onPressed: _showAddProductSheet,
              icon: const Icon(Icons.add, size: 15, color: Color(0xFFFF6FA0)),
              label: const Text(
                '상품 추가',
                style: TextStyle(fontSize: 13, color: Color(0xFFFF6FA0)),
              ),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
            ),
          ],
        ),
        if (_localProducts.isEmpty)
          GestureDetector(
            onTap: _showAddProductSheet,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7FA),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE8EBF2)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.shopping_bag_outlined,
                    size: 32,
                    color: Colors.black26,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '아직 추가된 상품이 없어요',
                    style: TextStyle(fontSize: 13, color: Colors.black38),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '+ 상품 추가하기',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFF6FA0),
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          ..._localProducts.asMap().entries.map((e) {
            final p = e.value;
            final name = p['name'] as String? ?? '';
            final price = p['price'] as int? ?? 0;
            final stock = p['stock'] as int? ?? 0;
            final opts = (p['options'] as List?)?.length ?? 0;
            final madeToOrder = p[kMadeToOrderField] == true;
            final localImages =
                (p['_localImages'] as List<XFile>?) ?? const <XFile>[];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE8EBF2)),
              ),
              child: Row(
                children: [
                  if (localImages.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LocalMedia.image(
                        localImages.first,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_fmtPrice(price)} · '
                          '${madeToOrder ? kMadeToOrderLabel : '재고 $stock개'}'
                          '${opts > 0 ? ' · 옵션 $opts개' : ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        setState(() => _localProducts.removeAt(e.key)),
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: Colors.black26,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            );
          }),
          GestureDetector(
            onTap: _showAddProductSheet,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFD6E4)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 16, color: Color(0xFFFF6FA0)),
                  SizedBox(width: 4),
                  Text(
                    '상품 추가하기',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF6FA0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── 상품 추가 바텀시트 ────────────────────────────────────────────
  void _showAddProductSheet() {
    final namec = TextEditingController();
    final descc = TextEditingController();
    final pricec = TextEditingController();
    final stockc = TextEditingController(text: '0');
    final optCtrls = <(TextEditingController, TextEditingController)>[];
    final List<XFile> images = [];
    String category = ListingConstants.shopCategories.first;
    bool isOnSale = false;
    // 🛠 주문제작 — 켜면 재고 수량을 묻지 않는다. 저장은 불리언 하나뿐이고
    // (`madeToOrder`), 주문 상태·결제·환불 흐름은 아무것도 달라지지 않는다.
    bool madeToOrder = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // ⚠️ 컨트롤러는 **시트 위젯이 사라질 때** 버린다([_DisposeOnUnmount]).
      // 예전에는 `.whenComplete()`에서 버렸는데, 그 future는 `Navigator.pop`이
      // 불린 **순간** 끝난다 — 시트는 아직 닫히는 애니메이션 중이라 매 프레임
      // 다시 그려지고, 그 사이 TextField가 이미 버려진 컨트롤러를 다시 듣는다
      // ("A TextEditingController was used after being disposed"). 그 예외로
      // 빌드가 중간에 끊기면 InheritedWidget이 자기 의존자를 남긴 채 비활성화돼
      // 곧바로 빨간 화면이 떴다('_dependents.isEmpty': is not true).
      builder: (ctx) => _DisposeOnUnmount(
        onDispose: () {
          namec.dispose();
          descc.dispose();
          pricec.dispose();
          stockc.dispose();
          for (final (n, p) in optCtrls) {
            n.dispose();
            p.dispose();
          }
        },
        child: StatefulBuilder(
          builder: (ctx, ss) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              // 시트의 context로 재야 한다 — 바깥 화면의 context를 쓰면 화면
              // 전체가 이 시트의 의존자가 되어, 키보드가 오르내릴 때마다 등록
              // 화면이 통째로 다시 그려진다.
              height: MediaQuery.of(ctx).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // 핸들
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // 헤더
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                    child: Row(
                      children: [
                        const Text(
                          '상품 추가',
                          style: TextStyle(
                            fontFamily: 'SeoulHangang',
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            shadows: [
                              Shadow(
                                color: Colors.black87,
                                offset: Offset(0.3, 0),
                              ),
                              Shadow(
                                color: Colors.black87,
                                offset: Offset(-0.3, 0),
                              ),
                              Shadow(
                                color: Colors.black87,
                                offset: Offset(0, 0.3),
                              ),
                              Shadow(
                                color: Colors.black87,
                                offset: Offset(0, -0.3),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // 폼
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 상품 이미지
                          _label('상품 이미지 (최대 5장)'),
                          SizedBox(
                            height: 90,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    if (images.length >= 5) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            '이미지는 최대 5장까지 등록할 수 있어요.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    final picked = await _picker.pickMultiImage(
                                      imageQuality: 80,
                                      limit: 5 - images.length,
                                    );
                                    if (picked.isEmpty) return;
                                    ss(
                                      () => images.addAll(
                                        picked.take(5 - images.length),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    width: 84,
                                    height: 84,
                                    margin: const EdgeInsets.only(right: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF7F7FA),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFE8EBF2),
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.add_photo_alternate_outlined,
                                          color: Color(0xFFFF6FA0),
                                          size: 28,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${images.length}/5',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black38,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                ...images.asMap().entries.map(
                                  (e) => Stack(
                                    children: [
                                      Container(
                                        width: 84,
                                        height: 84,
                                        margin: const EdgeInsets.only(
                                          right: 10,
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: LocalMedia.image(
                                            e.value,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 2,
                                        right: 12,
                                        child: GestureDetector(
                                          onTap: () =>
                                              ss(() => images.removeAt(e.key)),
                                          child: Container(
                                            width: 20,
                                            height: 20,
                                            decoration: const BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close,
                                              size: 12,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // 상품명
                          _label('상품명', required: true),
                          TextField(
                            controller: namec,
                            decoration: _deco('예: 생일 케이크'),
                          ),
                          const SizedBox(height: 16),
                          // 상품 설명
                          _label('상품 설명'),
                          TextField(
                            controller: descc,
                            maxLines: 3,
                            decoration: _deco('상품 설명 (선택)'),
                          ),
                          const SizedBox(height: 16),
                          // 판매가 + 재고
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _label('판매가'),
                                    TextField(
                                      controller: pricec,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      decoration: _deco('0', suffix: '원'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _label('재고 수량'),
                                    // 🛠 주문제작은 재고를 세지 않는다 — 칸을
                                    // 숨기지 않고 **비활성**으로 남긴다. 사라지면
                                    // 체크를 껐을 때 자리가 다시 생기면서 폼이
                                    // 위아래로 튀고, 방금 적은 수량도 눈앞에서
                                    // 없어져 지워진 것처럼 보인다.
                                    TextField(
                                      controller: stockc,
                                      enabled: !madeToOrder,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      decoration: _deco(
                                        madeToOrder ? '재고 없음' : '0',
                                      ),
                                    ),
                                    _madeToOrderCheck(
                                      value: madeToOrder,
                                      onChanged: (v) =>
                                          ss(() => madeToOrder = v),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          // 체크한 순간에만, 바로 아래 한 줄. 무엇인지(게스트에게도
                          // 같은 말로 보인다) + 호스트가 할 일 하나.
                          if (madeToOrder) _madeToOrderHostNote(),
                          const SizedBox(height: 16),
                          // 카테고리
                          _label('카테고리'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ListingConstants.shopCategories.map((c) {
                              final sel = category == c;
                              return GestureDetector(
                                onTap: () => ss(() => category = c),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: sel
                                        ? const Color(0xFFFF6FA0)
                                        : const Color(0xFFF7F7FA),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: sel
                                          ? const Color(0xFFFF6FA0)
                                          : const Color(0xFFE8EBF2),
                                    ),
                                  ),
                                  child: Text(
                                    c,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: sel
                                          ? Colors.white
                                          : Colors.black54,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          // 할인 상품 여부
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '할인 상품으로 표시',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Switch(
                                value: isOnSale,
                                onChanged: (v) => ss(() => isOnSale = v),
                                activeThumbColor: const Color(0xFFFF6FA0),
                                activeTrackColor: const Color(0xFFFFB8D0),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          // 옵션
                          Row(
                            children: [
                              _label('상품 옵션'),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () => ss(
                                  () => optCtrls.add((
                                    TextEditingController(),
                                    TextEditingController(),
                                  )),
                                ),
                                icon: const Icon(
                                  Icons.add,
                                  size: 15,
                                  color: Color(0xFFFF6FA0),
                                ),
                                label: const Text(
                                  '옵션 추가',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFFF6FA0),
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                          if (optCtrls.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '예) 레터링 추가 +5,000원',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black.withValues(alpha: 0.38),
                                ),
                              ),
                            ),
                          ...optCtrls.asMap().entries.map((e) {
                            final idx = e.key;
                            final (nc, pc) = e.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: nc,
                                      decoration: _deco('옵션명'),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: pc,
                                      decoration: _deco('추가금액', suffix: '원'),
                                      style: const TextStyle(fontSize: 13),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    onPressed: () => ss(() {
                                      final (n, p) = optCtrls.removeAt(idx);
                                      n.dispose();
                                      p.dispose();
                                    }),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                      color: Colors.black38,
                                      size: 20,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  // 확인 버튼
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (namec.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('상품명을 입력해주세요.')),
                              );
                              return;
                            }
                            final optList = optCtrls
                                .where((o) => o.$1.text.trim().isNotEmpty)
                                .map(
                                  (o) => {
                                    'name': o.$1.text.trim(),
                                    'additionalPrice':
                                        int.tryParse(o.$2.text.trim()) ?? 0,
                                  },
                                )
                                .toList();
                            setState(
                              () => _localProducts.add({
                                'name': namec.text.trim(),
                                'description': descc.text.trim(),
                                'price': int.tryParse(pricec.text.trim()) ?? 0,
                                // 주문제작이면 재고는 세지 않는다 — 입력칸이
                                // 비활성이라 예전 값이 남아 있어도 0으로 적는다
                                // (읽는 쪽의 판정은 madeToOrder 하나만 본다).
                                'stock': madeToOrder
                                    ? 0
                                    : int.tryParse(stockc.text.trim()) ?? 0,
                                kMadeToOrderField: madeToOrder,
                                'options': optList,
                                'imageUrls': <String>[],
                                // 샵이 아직 생성되기 전이라 로컬 파일만 들고 있다가
                                // _submit()에서 샵 생성 직후 업로드해 imageUrls로 바꾼다.
                                '_localImages': List<XFile>.from(images),
                                'category': category,
                                'isOnSale': isOnSale,
                                'isActive': true,
                              }),
                            );
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6FA0),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            elevation: 0,
                          ),
                          child: const Text(
                            '상품 추가',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 🧹 **위젯이 사라질 때** 정리하는 껍데기.
//
// 바텀시트 안에서 만든 컨트롤러를 언제 버려야 하는가 — 답은 "시트 위젯이
// 트리에서 빠질 때"뿐이다.
//
// ── 왜 `showModalBottomSheet(...).whenComplete()`가 아닌가 ───────────────────
// 그 future는 [Navigator.pop]이 불린 **순간** 끝난다. 시트는 그때부터 닫히는
// 애니메이션을 시작하므로 **아직 화면에 있고, 매 프레임 다시 그려진다.** 그
// 사이에 컨트롤러를 버리면 다음 리빌드에서 TextField가 버려진 컨트롤러를 다시
// 구독하려다 터진다:
//
//     A TextEditingController was used after being disposed.
//       ↳ _AnimatedState.didUpdateWidget → _MergingListenable.addListener
//
// 그리고 그 예외로 빌드가 중간에 끊기면, 의존자를 등록해 둔 채 죽은 자식이
// 남아 라우트가 비활성화될 때 두 번째 예외가 뜬다 — 사용자가 본 빨간 화면이다:
//
//     framework.dart:6268 '_dependents.isEmpty': is not true
//       ↳ InheritedElement.debugDeactivated
//
// [State.dispose]는 그 반대다 — 엘리먼트가 트리에서 완전히 빠진 **뒤에** 불리고,
// 그 뒤로는 이 서브트리가 다시 그려질 일이 없다.
//
// ⚠️ 시트 본문을 통째로 StatefulWidget으로 옮기지 않은 이유: 고쳐야 할 것은
// **수명 하나**이고, 500줄짜리 본문을 옮기면 고친 곳보다 옮긴 곳이 많아진다.
// ─────────────────────────────────────────────────────────────────────────────

class _DisposeOnUnmount extends StatefulWidget {
  const _DisposeOnUnmount({required this.onDispose, required this.child});

  /// 이 위젯이 트리에서 빠질 때 **한 번** 불린다.
  final VoidCallback onDispose;

  final Widget child;

  @override
  State<_DisposeOnUnmount> createState() => _DisposeOnUnmountState();
}

class _DisposeOnUnmountState extends State<_DisposeOnUnmount> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
