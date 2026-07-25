import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/models/address_result.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/screens/address_search_screen.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/register_return_signal.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/single_video_picker.dart';
import 'package:party_app/widgets/web_frame.dart';

class PartyMarketRegisterScreen extends StatefulWidget {
  const PartyMarketRegisterScreen({super.key});

  @override
  State<PartyMarketRegisterScreen> createState() =>
      _PartyMarketRegisterScreenState();
}

class _PartyMarketRegisterScreenState
    extends State<PartyMarketRegisterScreen> {
  // ── 기본 정보 ─────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool  _isActive = true;

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

  // ── 배송/수령 옵션 ─────────────────────────────────────────────
  static const _allDeliveryOpts = ['sameDay', 'pickup', 'delivery', 'scheduled'];
  static const _deliveryLabels  = <String, String>{
    'sameDay':   '당일 퀵',
    'pickup':    '방문수령',
    'delivery':  '택배',
    'scheduled': '지정일 배송',
  };
  static const _deliveryIcons = <String, IconData>{
    'sameDay':   Icons.flash_on_outlined,
    'pickup':    Icons.store_outlined,
    'delivery':  Icons.local_shipping_outlined,
    'scheduled': Icons.calendar_today_outlined,
  };
  final Set<String> _deliveryOpts = {};

  // ── 쿠폰 ─────────────────────────────────────────────────────────
  bool   _hasCoupon     = false;
  String _couponDiscType = '퍼센트 할인';
  final  _couponMinCtrl   = TextEditingController();
  final  _couponValueCtrl = TextEditingController();

  // ── 자동발송 문구 ─────────────────────────────────────────────────
  final _autoMsgCtrls = <String, TextEditingController>{
    'sameDay':   TextEditingController(),
    'pickup':    TextEditingController(),
    'delivery':  TextEditingController(),
    'scheduled': TextEditingController(),
  };

  // ── 상품 목록 (등록 전 로컬 보관) ────────────────────────────────
  final List<Map<String, dynamic>> _localProducts = [];

  // ── 유효성 ────────────────────────────────────────────────────────
  bool _showNameError = false;
  bool _isSubmitting  = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _detailAddressCtrl.dispose();
    _couponMinCtrl.dispose();
    _couponValueCtrl.dispose();
    for (final c in _autoMsgCtrls.values) { c.dispose(); }
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

  // ── 제출 ─────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (UserSession.userId.isEmpty) { _msg('로그인이 필요합니다.'); return; }
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _showNameError = true);
      _msg('샵 이름을 입력해주세요.');
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
      final priceFrom =
          positivePrices.isEmpty ? 0 : positivePrices.reduce((a, b) => a < b ? a : b);
      final hasDiscount = _localProducts.any((p) => p['isOnSale'] == true);
      final hasStock = _localProducts.any((p) => ((p['stock'] as int?) ?? 0) > 0);

      final doc = <String, dynamic>{
        'name':            _nameCtrl.text.trim(),
        'description':     _descCtrl.text.trim(),
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
        'isActive':        _isActive,
        'deliveryOptions': _deliveryOpts.toList(),
        'autoMessages':    autoMsgs,
        'hasCoupon':       _hasCoupon,
        // 상세검색용 집계값 (상품 추가/변경 시 party_shop_product_register_screen.dart에서도 갱신)
        'categories':      categories,
        'priceFrom':       priceFrom,
        'hasDiscount':     hasDiscount,
        'hasStock':        hasStock,
        'hostId':          UserSession.userId,
        'hostName':        UserSession.displayName,
        'createdAt':       FieldValue.serverTimestamp(),
        'updatedAt':       FieldValue.serverTimestamp(),
      };
      if (_hasCoupon) {
        doc['couponMinAmount'] =
            int.tryParse(_couponMinCtrl.text.trim().replaceAll(',', '')) ?? 0;
        doc['couponDiscountType'] =
            _couponDiscType == '퍼센트 할인' ? 'percent' : 'amount';
        doc['couponDiscountValue'] =
            int.tryParse(_couponValueCtrl.text.trim().replaceAll(',', '')) ?? 0;
      }

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
          productImgUrls.add(await CloudflareService.uploadImage(File(img.path)));
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
          'hostId':             UserSession.userId,
          'shopId':             ref.id,
          'deliveryOptions':    _deliveryOpts.toList(),
          'isSameDayAvailable': _deliveryOpts.contains('sameDay'),
          'isCouponApplicable': _hasCoupon,
          'autoMessages':       <String, String>{},
          'createdAt':          FieldValue.serverTimestamp(),
        });
      }

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

  void _msg(String t) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));

  // ── 빌드 ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text('파티샵 등록',
            style: TextStyle(fontFamily: 'SeoulHangang', fontSize: 17, fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── 1. 샵 이름 ───────────────────────────────────────────
          _label('샵 이름', required: true),
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _showNameError = false),
            decoration: _deco('샵 이름을 입력해주세요', error: _showNameError),
          ),
          const SizedBox(height: 22),

          // ── 2. 대표 이미지 ───────────────────────────────────────
          _label('대표 이미지'),
          _buildMainImagePicker(),
          const SizedBox(height: 4),
          const Text('동영상 최대 1개 · 사진 최대 6장',
              style: TextStyle(fontSize: 11, color: Colors.black38)),
          const SizedBox(height: 22),

          // ── 2-1. 동영상 (선택) ───────────────────────────────────
          _label('동영상 (선택, 최대 1개)'),
          SingleVideoPicker(
            key: _videoKey,
            onCompressingChanged: (v) => setState(() => _isCompressingVideo = v),
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 22),

          // ── 3. 소개 이미지 ───────────────────────────────────────
          _label('소개 이미지 (최대 6장)'),
          _buildIntroImagePicker(),
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
                  : const Text('파티샵 등록하기',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
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
          final key     = _allDeliveryOpts[i];
          final sel     = _deliveryOpts.contains(key);
          final isLast  = i == _allDeliveryOpts.length - 1;
          return GestureDetector(
            onTap: () => setState(() {
              if (sel) { _deliveryOpts.remove(key); } else { _deliveryOpts.add(key); }
            }),
            child: Container(
              decoration: BoxDecoration(
                border: isLast ? null
                    : const Border(bottom: BorderSide(color: Color(0xFFF2F2F5))),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFFFF6FA0) : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: sel ? const Color(0xFFFF6FA0) : const Color(0xFFD0D0D8),
                      width: 1.5,
                    ),
                  ),
                  child: sel
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                Icon(_deliveryIcons[key]!, size: 18,
                    color: sel ? const Color(0xFFFF6FA0) : Colors.black38),
                const SizedBox(width: 10),
                Text(_deliveryLabels[key]!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: sel ? const Color(0xFFFF6FA0) : Colors.black87,
                    )),
              ]),
            ),
          );
        }),
      ),
    );
  }

  // ── 자동발송 문구 섹션 ────────────────────────────────────────────
  Widget _buildAutoMsgSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('자동 안내 문구 설정'),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFD6E4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.notifications_outlined, size: 14, color: Color(0xFFFF6FA0)),
            SizedBox(width: 6),
            Expanded(
              child: Text('예약/수령 시간 2시간 전에 구매자에게 자동 발송돼요.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFFF6FA0))),
            ),
          ]),
          const SizedBox(height: 12),
          ..._allDeliveryOpts
              .where(_deliveryOpts.contains)
              .map((key) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(_deliveryIcons[key]!, size: 14, color: Colors.black54),
                        const SizedBox(width: 6),
                        Text(_deliveryLabels[key]!,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        const Text(' 선택자용',
                            style: TextStyle(fontSize: 12, color: Colors.black45)),
                      ]),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _autoMsgCtrls[key],
                        maxLines: 3,
                        decoration: _deco('예: 수령 2시간 전 안내드립니다...'),
                      ),
                    ]),
                  )),
        ]),
      ),
    ]);
  }

  // ── 쿠폰 섹션 ────────────────────────────────────────────────────
  Widget _buildCouponSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('방문 할인쿠폰',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87)),
        const Spacer(),
        Switch(
          value: _hasCoupon,
          onChanged: (v) => setState(() => _hasCoupon = v),
          activeThumbColor: const Color(0xFFFF6FA0),
          activeTrackColor: const Color(0xFFFFB8D0),
        ),
      ]),
      if (_hasCoupon) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0F5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFD6E4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 최소 구매 금액
            const Text('최소 구매 금액',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _couponMinCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _deco('예: 30000 (0이면 조건 없음)', suffix: '원'),
            ),
            const SizedBox(height: 14),
            // 할인 방식
            const Text('할인 방식',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: ['퍼센트 할인', '금액 할인'].map((t) {
                final sel = _couponDiscType == t;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _couponDiscType = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: EdgeInsets.only(right: t == '퍼센트 할인' ? 8 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFFFF6FA0) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sel ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
                          width: sel ? 1.5 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(t,
                          style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : Colors.black54,
                          )),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Text(_couponDiscType == '퍼센트 할인' ? '할인율 (%)' : '할인 금액 (원)',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _couponValueCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _deco(
                _couponDiscType == '퍼센트 할인' ? '예: 10 (10% 할인)' : '예: 5000 (5,000원 할인)',
                suffix: _couponDiscType == '퍼센트 할인' ? '%' : '원',
              ),
            ),
          ]),
        ),
      ],
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

  String _fmtPrice(int p) => formatPrice(p);

  // ── 판매 상품 목록 섹션 ───────────────────────────────────────────
  Widget _buildProductSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _label('판매 상품 목록'),
          const Spacer(),
          TextButton.icon(
            onPressed: _showAddProductSheet,
            icon: const Icon(Icons.add, size: 15, color: Color(0xFFFF6FA0)),
            label: const Text('상품 추가',
                style: TextStyle(fontSize: 13, color: Color(0xFFFF6FA0))),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
        ]),
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
              child: Column(children: [
                const Icon(Icons.shopping_bag_outlined,
                    size: 32, color: Colors.black26),
                const SizedBox(height: 8),
                const Text('아직 추가된 상품이 없어요',
                    style: TextStyle(fontSize: 13, color: Colors.black38)),
                const SizedBox(height: 4),
                const Text('+ 상품 추가하기',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFF6FA0))),
              ]),
            ),
          )
        else ...[
          ..._localProducts.asMap().entries.map((e) {
            final p     = e.value;
            final name  = p['name']  as String? ?? '';
            final price = p['price'] as int?    ?? 0;
            final stock = p['stock'] as int?    ?? 0;
            final opts  = (p['options'] as List?)?.length ?? 0;
            final localImages = (p['_localImages'] as List<XFile>?) ?? const <XFile>[];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE8EBF2)),
              ),
              child: Row(children: [
                if (localImages.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(File(localImages.first.path),
                        width: 44, height: 44, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      '${_fmtPrice(price)} · 재고 $stock개'
                      '${opts > 0 ? ' · 옵션 $opts개' : ''}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black45),
                    ),
                  ]),
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => _localProducts.removeAt(e.key)),
                  icon: const Icon(Icons.remove_circle_outline,
                      color: Colors.black26, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
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
                  Text('상품 추가하기',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF6FA0))),
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
    final namec  = TextEditingController();
    final descc  = TextEditingController();
    final pricec = TextEditingController();
    final stockc = TextEditingController(text: '0');
    final optCtrls =
        <(TextEditingController, TextEditingController)>[];
    final List<XFile> images = [];
    String category = ListingConstants.shopCategories.first;
    bool isOnSale = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(children: [
              // 핸들
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(2)),
              ),
              // 헤더
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                child: Row(children: [
                  const Text('상품 추가',
                      style: TextStyle(
                          fontFamily: 'SeoulHangang',
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          shadows: [
                            Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                            Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                            Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                            Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                          ])),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ]),
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('이미지는 최대 5장까지 등록할 수 있어요.')));
                                  return;
                                }
                                final picked = await _picker.pickMultiImage(
                                    imageQuality: 80, limit: 5 - images.length);
                                if (picked.isEmpty) return;
                                ss(() => images
                                    .addAll(picked.take(5 - images.length)));
                              },
                              child: Container(
                                width: 84, height: 84,
                                margin: const EdgeInsets.only(right: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7F7FA),
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: const Color(0xFFE8EBF2)),
                                ),
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                  const Icon(Icons.add_photo_alternate_outlined,
                                      color: Color(0xFFFF6FA0), size: 28),
                                  const SizedBox(height: 2),
                                  Text('${images.length}/5',
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.black38)),
                                ]),
                              ),
                            ),
                            ...images.asMap().entries.map((e) => Stack(children: [
                                  Container(
                                    width: 84, height: 84,
                                    margin: const EdgeInsets.only(right: 10),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(File(e.value.path),
                                          fit: BoxFit.cover),
                                    ),
                                  ),
                                  Positioned(
                                    top: 2, right: 12,
                                    child: GestureDetector(
                                      onTap: () =>
                                          ss(() => images.removeAt(e.key)),
                                      child: Container(
                                        width: 20, height: 20,
                                        decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle),
                                        child: const Icon(Icons.close,
                                            size: 12, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ])),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 상품명
                      _label('상품명', required: true),
                      TextField(
                          controller: namec,
                          decoration: _deco('예: 생일 케이크')),
                      const SizedBox(height: 16),
                      // 상품 설명
                      _label('상품 설명'),
                      TextField(
                          controller: descc,
                          maxLines: 3,
                          decoration: _deco('상품 설명 (선택)')),
                      const SizedBox(height: 16),
                      // 판매가 + 재고
                      Row(children: [
                        Expanded(
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                            _label('판매가'),
                            TextField(
                              controller: pricec,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: _deco('0', suffix: '원'),
                            ),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                            _label('재고 수량'),
                            TextField(
                              controller: stockc,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: _deco('0'),
                            ),
                          ]),
                        ),
                      ]),
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
                                  horizontal: 12, vertical: 7),
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
                              child: Text(c,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: sel ? Colors.white : Colors.black54,
                                  )),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      // 할인 상품 여부
                      Row(children: [
                        Expanded(
                          child: Text('할인 상품으로 표시',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        Switch(
                          value: isOnSale,
                          onChanged: (v) => ss(() => isOnSale = v),
                          activeThumbColor: const Color(0xFFFF6FA0),
                          activeTrackColor: const Color(0xFFFFB8D0),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      // 옵션
                      Row(children: [
                        _label('상품 옵션'),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => ss(() => optCtrls.add((
                                TextEditingController(),
                                TextEditingController(),
                              ))),
                          icon: const Icon(Icons.add,
                              size: 15, color: Color(0xFFFF6FA0)),
                          label: const Text('옵션 추가',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFFF6FA0))),
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero),
                        ),
                      ]),
                      if (optCtrls.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '예) 레터링 추가 +5,000원',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.black
                                    .withValues(alpha: 0.38)),
                          ),
                        ),
                      ...optCtrls.asMap().entries.map((e) {
                        final idx = e.key;
                        final (nc, pc) = e.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: nc,
                                decoration: _deco('옵션명'),
                                style:
                                    const TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: pc,
                                decoration:
                                    _deco('추가금액', suffix: '원'),
                                style:
                                    const TextStyle(fontSize: 13),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter
                                      .digitsOnly
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: () => ss(() {
                                final (n, p) =
                                    optCtrls.removeAt(idx);
                                n.dispose();
                                p.dispose();
                              }),
                              icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.black38,
                                  size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ]),
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
                            const SnackBar(
                                content: Text('상품명을 입력해주세요.')));
                          return;
                        }
                        final optList = optCtrls
                            .where((o) =>
                                o.$1.text.trim().isNotEmpty)
                            .map((o) => {
                                  'name': o.$1.text.trim(),
                                  'additionalPrice':
                                      int.tryParse(
                                              o.$2.text.trim()) ??
                                          0,
                                })
                            .toList();
                        setState(() => _localProducts.add({
                              'name':        namec.text.trim(),
                              'description': descc.text.trim(),
                              'price':       int.tryParse(pricec.text.trim()) ?? 0,
                              'stock':       int.tryParse(stockc.text.trim()) ?? 0,
                              'options':     optList,
                              'imageUrls':   <String>[],
                              // 샵이 아직 생성되기 전이라 로컬 파일만 들고 있다가
                              // _submit()에서 샵 생성 직후 업로드해 imageUrls로 바꾼다.
                              '_localImages': List<XFile>.from(images),
                              'category':    category,
                              'isOnSale':    isOnSale,
                              'isActive':    true,
                            }));
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6FA0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 15),
                        elevation: 0,
                      ),
                      child: const Text('상품 추가',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    ).whenComplete(() {
      namec.dispose();
      descc.dispose();
      pricec.dispose();
      stockc.dispose();
      for (final (n, p) in optCtrls) {
        n.dispose();
        p.dispose();
      }
    });
  }
}
