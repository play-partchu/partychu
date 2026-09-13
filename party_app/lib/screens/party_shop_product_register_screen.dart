import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/models/made_to_order.dart';
import 'package:party_app/models/draft_type.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/utils/draftable_register.dart';
import 'package:party_app/utils/register_validation.dart';
import 'package:party_app/widgets/party_form/register_field_anchor.dart';
import 'package:party_app/widgets/party_form/register_missing_fields_banner.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/screens/party_shop_manage_screen.dart';
import 'package:party_app/widgets/web_frame.dart';

// ── 옵션 항목 (이름 + 추가금액) ────────────────────────────────────
class _OptionEntry {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  _OptionEntry({VoidCallback? onChanged}) {
    if (onChanged != null) {
      nameCtrl.addListener(onChanged);
      priceCtrl.addListener(onChanged);
    }
  }
  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
  }
}

class PartyShopProductRegisterScreen extends StatefulWidget {
  final String shopId;
  final String shopName;

  /// null이면 관리화면에서 진입 (저장 후 pop),
  /// non-null이면 샵 등록 직후 진입 (저장 후 관리화면으로 pushReplacement)
  final Map<String, dynamic>? shopData;

  /// 마이페이지 "임시저장" 목록에서 "이어서 작성"으로 열 때 true.
  final bool autoRestoreDraft;

  const PartyShopProductRegisterScreen({
    super.key,
    required this.shopId,
    required this.shopName,
    this.shopData,
    this.autoRestoreDraft = false,
  });

  @override
  State<PartyShopProductRegisterScreen> createState() =>
      _PartyShopProductRegisterScreenState();
}

class _PartyShopProductRegisterScreenState
    extends State<PartyShopProductRegisterScreen>
    with
        WidgetsBindingObserver,
        DraftableRegister<PartyShopProductRegisterScreen> {
  @override
  void setState(VoidCallback fn) {
    markDraftDirty();
    super.setState(fn);
  }

  @override
  DraftType get draftType => DraftType.shop;

  @override
  bool get draftAutoRestore => widget.autoRestoreDraft;

  @override
  String get draftTitle => _nameCtrl.text;

  @override
  String? get draftCoverImageUrl => null;

  @override
  Map<String, dynamic> buildDraftPayload() {
    return <String, dynamic>{
      // 목록 표시/이어서 작성 시 어느 샵의 상품인지 식별용.
      'shopId': widget.shopId,
      'shopName': widget.shopName,
      'name': _nameCtrl.text,
      'description': _descCtrl.text,
      'price': _priceCtrl.text,
      'stock': _stockCtrl.text,
      kMadeToOrderField: _madeToOrder,
      'isActive': _isActive,
      'isSameDayAvailable': _isSameDayAvailable,
      'isCouponApplicable': _isCouponApplicable,
      'isOnSale': _isOnSale,
      'category': _category,
      'deliveryOpts': _deliveryOpts.toList(),
      'options': _options
          .map((o) => {'name': o.nameCtrl.text, 'price': o.priceCtrl.text})
          .toList(),
      'autoMsgs': {for (final e in _autoMsgCtrls.entries) e.key: e.value.text},
      'imagePaths': [for (final f in _images) LocalMedia.remember(f).path],
    };
  }

  @override
  void applyDraftPayload(Map<String, dynamic> p) {
    _nameCtrl.text = (p['name'] as String?) ?? '';
    _descCtrl.text = (p['description'] as String?) ?? '';
    _priceCtrl.text = (p['price'] as String?) ?? '';
    _stockCtrl.text = (p['stock'] as String?) ?? '0';
    _madeToOrder = p[kMadeToOrderField] as bool? ?? false;
    _isActive = p['isActive'] as bool? ?? true;
    _isSameDayAvailable = p['isSameDayAvailable'] as bool? ?? false;
    _isCouponApplicable = p['isCouponApplicable'] as bool? ?? false;
    _isOnSale = p['isOnSale'] as bool? ?? false;
    _category =
        p['category'] as String? ?? ListingConstants.shopCategories.first;
    _deliveryOpts
      ..clear()
      ..addAll((p['deliveryOpts'] as List?)?.cast<String>() ?? const []);
    // 옵션 목록 재구성(기존 것 dispose 후).
    for (final o in _options) {
      o.dispose();
    }
    _options.clear();
    for (final raw in (p['options'] as List?) ?? const []) {
      final m = raw as Map;
      final entry = _OptionEntry(onChanged: markDraftDirty);
      entry.nameCtrl.text = m['name'] as String? ?? '';
      entry.priceCtrl.text = m['price'] as String? ?? '';
      _options.add(entry);
    }
    final autoMsgs = p['autoMsgs'] as Map?;
    if (autoMsgs != null) {
      for (final e in _autoMsgCtrls.entries) {
        e.value.text = autoMsgs[e.key] as String? ?? '';
      }
    }
    // 로컬 이미지 복원(파일이 남아 있을 때만).
    _images = [];
    bool anyMissing = false;
    for (final path in (p['imagePaths'] as List?)?.cast<String>() ?? const []) {
      if (LocalMedia.exists(path)) {
        _images.add(LocalMedia.resolve(path));
      } else {
        anyMissing = true;
      }
    }
    draftMediaNeedsReselect = anyMissing;
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_nameCtrl, _descCtrl, _priceCtrl, _stockCtrl]) {
      c.addListener(markDraftDirty);
    }
    for (final c in _autoMsgCtrls.values) {
      c.addListener(markDraftDirty);
    }
    initDraft();
  }

  final _nameCtrl = TextEditingController();

  // 필수항목 안내는 다른 등록 화면과 **같은 공용 구조**를 쓴다 —
  // 화면마다 따로 스크롤·강조 로직을 만들지 않기 위해서다
  // ([RegisterFieldCheck] / [RegisterFieldAnchor]). 본문이 [ListView]라
  // 상품명 칸도 화면 밖이면 만들어지지 않으므로 컨트롤러가 꼭 필요하다.
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _nameKey = GlobalKey();
  final FocusNode _nameFocus = FocusNode();
  List<RegisterFieldCheck> _missingFields = const [];
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '0');

  List<XFile> _images = [];
  bool _isActive = true;
  bool _isSameDayAvailable = false;
  bool _isCouponApplicable = false;
  bool _isSubmitting = false;

  String _category = ListingConstants.shopCategories.first;
  bool _isOnSale = false;

  /// 🛠 주문제작 — 켜면 재고 수량을 묻지 않는다. 저장되는 것은
  /// [kMadeToOrderField] 불리언 하나뿐이고, 주문 상태·결제·환불 흐름은
  /// 아무것도 달라지지 않는다.
  bool _madeToOrder = false;

  final Set<String> _deliveryOpts = {};
  final List<_OptionEntry> _options = [];

  // 배송 옵션별 자동 안내 문구
  final Map<String, TextEditingController> _autoMsgCtrls = {
    'sameDay': TextEditingController(),
    'pickup': TextEditingController(),
    'delivery': TextEditingController(),
    'scheduled': TextEditingController(),
  };

  static const _allDelivery = [
    ('sameDay', Icons.bolt_outlined, '당일 퀵', '당일 퀵 배송'),
    ('pickup', Icons.store_outlined, '방문수령', '직접 방문 수령'),
    ('delivery', Icons.local_shipping_outlined, '택배', '택배 배송'),
    ('scheduled', Icons.calendar_today_outlined, '지정일', '날짜 지정 배송'),
  ];

  static const _delivLabels = <String, String>{
    'sameDay': '당일 퀵',
    'pickup': '방문수령',
    'delivery': '택배',
    'scheduled': '지정일',
  };

  @override
  void dispose() {
    disposeDraft();
    _scrollCtrl.dispose();
    _nameFocus.dispose();
    // 이 화면을 떠나면 강조도 함께 끈다 — 타이머가 화면보다 오래 남지 않게.
    RegisterValidation.clearHighlight();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    for (final o in _options) {
      o.dispose();
    }
    for (final c in _autoMsgCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── 이미지 선택 ──────────────────────────────────────────────────
  Future<void> _pickImages() async {
    if (_images.length >= 5) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이미지는 최대 5장까지 등록할 수 있어요.')));
      return;
    }
    final picked = await ImagePicker().pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) {
      return;
    }
    setState(() {
      _images = [..._images, ...picked].take(5).toList();
    });
  }

  void _addOption() {
    setState(() => _options.add(_OptionEntry(onChanged: markDraftDirty)));
  }

  void _removeOption(int idx) {
    final o = _options.removeAt(idx);
    o.dispose();
    setState(() {});
  }

  // ── 저장 ────────────────────────────────────────────────────────
  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final price = int.tryParse(_priceCtrl.text.trim()) ?? 0;
    final stock = int.tryParse(_stockCtrl.text.trim()) ?? 0;

    // 필수값 검증 — 조건·문구는 그대로다. 안내만 다른 등록 화면과 같은
    // 공용 경로를 타서, 배너의 줄을 눌러도 그 입력칸으로 가게 한다.
    final checks = [
      RegisterFieldCheck(
        missing: name.isEmpty,
        message: '상품명을 입력해주세요.',
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
      final imgUrls = <String>[];
      for (final x in _images) {
        final url = await CloudflareService.uploadImage(x);
        imgUrls.add(url);
      }

      final optList = _options
          .where((o) => o.nameCtrl.text.trim().isNotEmpty)
          .map(
            (o) => {
              'name': o.nameCtrl.text.trim(),
              'additionalPrice': int.tryParse(o.priceCtrl.text.trim()) ?? 0,
            },
          )
          .toList();

      final autoMsgs = <String, String>{};
      for (final k in _deliveryOpts) {
        final txt = _autoMsgCtrls[k]?.text.trim() ?? '';
        if (txt.isNotEmpty) {
          autoMsgs[k] = txt;
        }
      }

      final doc = {
        'name': name,
        'description': desc,
        'price': price,
        'imageUrls': imgUrls,
        // 주문제작이면 재고는 세지 않는다 — 입력칸이 비활성이라 예전 값이
        // 남아 있어도 0으로 적는다(읽는 쪽은 madeToOrder 하나만 본다).
        'stock': _madeToOrder ? 0 : stock,
        kMadeToOrderField: _madeToOrder,
        'options': optList,
        'deliveryOptions': _deliveryOpts.toList(),
        'isSameDayAvailable': _isSameDayAvailable,
        'isCouponApplicable': _isCouponApplicable,
        'category': _category,
        'isOnSale': _isOnSale,
        'autoMessages': autoMsgs,
        'isActive': _isActive,
        'hostId': UserSession.userId,
        'shopId': widget.shopId,
        'createdAt': FieldValue.serverTimestamp(),
      };

      final shopRef = FirebaseFirestore.instance
          .collection('partyShops')
          .doc(widget.shopId);
      await shopRef.collection('products').add(doc);

      // 상세검색용 집계값 갱신 — 이 샵의 전체 상품을 다시 조회해 재계산
      final allProducts = await shopRef.collection('products').get();
      final categories = allProducts.docs
          .map((d) => d.data()['category'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final positivePrices = allProducts.docs
          .map((d) => (d.data()['price'] as num?)?.toInt() ?? 0)
          .where((p) => p > 0);
      final priceFrom = positivePrices.isEmpty
          ? 0
          : positivePrices.reduce((a, b) => a < b ? a : b);
      final hasDiscount = allProducts.docs.any(
        (d) => d.data()['isOnSale'] == true,
      );
      // 🛠 주문제작 상품은 재고를 세지 않는다 — 여기서 빼면 주문제작만 파는
      // 샵이 '재고 있음' 검색에서 통째로 사라진다([shopProductInStock]).
      final hasStock = allProducts.docs.any(
        (d) => shopProductInStock(
          stock: (d.data()['stock'] as num?)?.toInt() ?? 0,
          madeToOrder: isMadeToOrderProduct(d.data()),
        ),
      );
      await shopRef.update({
        'categories': categories,
        'priceFrom': priceFrom,
        'hasDiscount': hasDiscount,
        'hasStock': hasStock,
      });

      if (!mounted) {
        return;
      }
      // 최종 등록 완료 — 파티샵 상품 임시저장은 자동 삭제.
      await deleteCurrentDraft();
      if (!mounted) {
        return;
      }
      if (widget.shopData != null) {
        // 샵 등록 직후 → 관리화면으로 이동
        Navigator.pushReplacement(
          context,
          webFramedRoute(
            (_) => PartyShopManageScreen(
              shopId: widget.shopId,
              shopData: widget.shopData!,
            ),
          ),
        );
      } else {
        Navigator.pop(context);
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('상품이 등록되었습니다!')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  // ── UI ──────────────────────────────────────────────────────────
  InputDecoration _inputDeco(String hint, {String? prefix}) => InputDecoration(
    hintText: hint,
    prefixText: prefix,
    filled: true,
    fillColor: const Color(0xFFFAFAFA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFFF6FA0), width: 1.5),
    ),
  );

  // ── 🛠 주문제작 ────────────────────────────────────────────────────
  //
  // 재고 수량 칸 아래의 체크란과, 켰을 때만 뜨는 안내. 파티샵 등록 화면의
  // 상품 추가 시트와 **같은 문구**를 쓴다([kMadeToOrderNotice] 등) — 같은
  // 상품을 두 입구에서 만드는데 설명이 갈리면 안 된다.

  /// 재고 수량 아래의 '주문제작' 체크란.
  Widget _madeToOrderCheck() => InkWell(
    onTap: () => setState(() => _madeToOrder = !_madeToOrder),
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: _madeToOrder,
              onChanged: (v) => setState(() => _madeToOrder = v ?? false),
              activeColor: const Color(0xFFFF6FA0),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 6),
          // 폭 절반짜리 칸이라 긴 글꼴 설정에서도 넘치지 않게 Flexible.
          const Flexible(
            child: Text(
              kMadeToOrderLabel,
              style: TextStyle(
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
      children: const [
        Text(
          kMadeToOrderBadge,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFFFF6FA0),
          ),
        ),
        SizedBox(height: 4),
        Text(
          kMadeToOrderNotice,
          style: TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.5),
        ),
        Text(
          kMadeToOrderHostNotice,
          style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.5),
        ),
      ],
    ),
  );

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: 'SeoulHangang',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.black87,
        shadows: [
          Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
          Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
          Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
          Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
        ],
      ),
    ),
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE8EBF2)),
    ),
    child: child,
  );

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
            '상품 등록',
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
          actions: [
            if (widget.shopData != null)
              TextButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  webFramedRoute(
                    (_) => PartyShopManageScreen(
                      shopId: widget.shopId,
                      shopData: widget.shopData!,
                    ),
                  ),
                ),
                child: const Text(
                  '건너뛰기',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            draftSaveAction(),
          ],
          bottom: buildAutoSaveIndicator(),
        ),
        body: ListView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            if (draftMediaNeedsReselect) buildMediaReselectBanner(),
            RegisterMissingFieldsBanner(fields: _missingFields),
            // ── 상품 이미지 ────────────────────────────────────────
            _sectionLabel('상품 이미지 (최대 5장)'),
            SizedBox(
              height: 90,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  GestureDetector(
                    onTap: _pickImages,
                    child: Container(
                      width: 84,
                      height: 84,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: Color(0xFFFF6FA0),
                            size: 28,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_images.length}/5',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black38,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ..._images.asMap().entries.map(
                    (e) => Stack(
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          margin: const EdgeInsets.only(right: 10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
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
                                setState(() => _images.removeAt(e.key)),
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
            const SizedBox(height: 20),

            // ── 상품명 ────────────────────────────────────────────
            _sectionLabel('상품명 *'),
            RegisterFieldAnchor(
              key: _nameKey,
              child: TextField(
                controller: _nameCtrl,
                focusNode: _nameFocus,
                decoration: _inputDeco('상품명을 입력해주세요'),
                maxLength: 40,
                buildCounter:
                    (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
              ),
            ),
            const SizedBox(height: 16),

            // ── 상품 설명 ──────────────────────────────────────────
            _sectionLabel('상품 설명'),
            TextField(
              controller: _descCtrl,
              decoration: _inputDeco('상품에 대한 설명을 입력해주세요'),
              minLines: 3,
              maxLines: 6,
            ),
            const SizedBox(height: 16),

            // ── 판매가 + 재고 ──────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('판매가 (원)'),
                      TextField(
                        controller: _priceCtrl,
                        decoration: _inputDeco('0', prefix: '₩ '),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('재고 수량'),
                      // 🛠 주문제작은 재고를 세지 않는다 — 칸을 숨기지 않고
                      // 비활성으로 남긴다(체크를 껐을 때 폼이 튀지 않게).
                      TextField(
                        controller: _stockCtrl,
                        enabled: !_madeToOrder,
                        decoration: _inputDeco(
                          _madeToOrder ? '재고 없음' : '0',
                          prefix: '재고 ',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                      _madeToOrderCheck(),
                    ],
                  ),
                ),
              ],
            ),
            // 체크한 순간에만, 바로 아래 한 줄.
            if (_madeToOrder) _madeToOrderHostNote(),
            const SizedBox(height: 20),

            // ── 카테고리 ───────────────────────────────────────────
            _sectionLabel('카테고리'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ListingConstants.shopCategories.map((c) {
                final sel = _category == c;
                return GestureDetector(
                  onTap: () => setState(() => _category = c),
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
                        color: sel ? Colors.white : Colors.black54,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _card(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '할인 상품으로 표시',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  '상세검색의 "할인 상품" 필터에 노출돼요.',
                  style: TextStyle(fontSize: 12, color: Colors.black38),
                ),
                value: _isOnSale,
                activeThumbColor: const Color(0xFFFF6FA0),
                onChanged: (v) => setState(() => _isOnSale = v),
              ),
            ),
            const SizedBox(height: 20),

            // ── 상품 옵션 ──────────────────────────────────────────
            Row(
              children: [
                const Text(
                  '상품 옵션',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addOption,
                  icon: const Icon(
                    Icons.add,
                    size: 15,
                    color: Color(0xFFFF6FA0),
                  ),
                  label: const Text(
                    '옵션 추가',
                    style: TextStyle(fontSize: 12, color: Color(0xFFFF6FA0)),
                  ),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_options.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '선택 옵션과 추가금액을 등록할 수 있어요.\n예) 레터링 추가 +5,000원',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.38),
                    height: 1.5,
                  ),
                ),
              ),
            ..._options.asMap().entries.map((e) {
              final idx = e.key;
              final o = e.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: o.nameCtrl,
                        decoration: _inputDeco('옵션명 (예: 레터링 추가)'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: o.priceCtrl,
                        decoration: _inputDeco('추가금액', prefix: '+₩ '),
                        style: const TextStyle(fontSize: 13),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () => _removeOption(idx),
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
            const SizedBox(height: 20),

            // ── 배송·수령 가능 옵션 ────────────────────────────────
            _sectionLabel('배송·수령 가능 옵션'),
            _card(
              child: Column(
                children: _allDelivery.map((t) {
                  final key = t.$1;
                  final icon = t.$2;
                  final label = t.$3;
                  final desc = t.$4;
                  final sel = _deliveryOpts.contains(key);
                  return Column(
                    children: [
                      InkWell(
                        onTap: () => setState(() {
                          if (sel) {
                            _deliveryOpts.remove(key);
                          } else {
                            _deliveryOpts.add(key);
                          }
                        }),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Icon(
                                icon,
                                size: 20,
                                color: sel
                                    ? const Color(0xFFFF6FA0)
                                    : Colors.black26,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: sel
                                            ? const Color(0xFFFF6FA0)
                                            : Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      desc,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.black38,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Checkbox(
                                value: sel,
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    _deliveryOpts.add(key);
                                  } else {
                                    _deliveryOpts.remove(key);
                                  }
                                }),
                                activeColor: const Color(0xFFFF6FA0),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 배송 옵션 선택 시 자동발송 문구 입력
                      if (sel) ...[
                        const SizedBox(height: 6),
                        TextField(
                          controller: _autoMsgCtrls[key],
                          decoration: InputDecoration(
                            hintText:
                                '${_delivLabels[key] ?? label} 자동 안내 문구 (선택)',
                            hintStyle: const TextStyle(
                              fontSize: 12,
                              color: Colors.black38,
                            ),
                            filled: true,
                            fillColor: const Color(0xFFFFF9FB),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFFFFD6E7),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFFFFD6E7),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFFFF6FA0),
                                width: 1.5,
                              ),
                            ),
                            prefixIcon: const Icon(
                              Icons.auto_awesome,
                              size: 15,
                              color: Color(0xFFFF6FA0),
                            ),
                          ),
                          style: const TextStyle(fontSize: 13),
                          minLines: 2,
                          maxLines: 4,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            // ── 당일구매 가능 여부 ─────────────────────────────────
            _card(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '당일구매 가능',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  '오늘 바로 구매·수령 가능 여부',
                  style: TextStyle(fontSize: 12, color: Colors.black38),
                ),
                value: _isSameDayAvailable,
                activeThumbColor: const Color(0xFFFF6FA0),
                onChanged: (v) => setState(() => _isSameDayAvailable = v),
              ),
            ),
            const SizedBox(height: 12),

            // ── 쿠폰 적용 가능 여부 ────────────────────────────────
            _card(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '쿠폰 적용 가능',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  '샵 할인쿠폰 적용 허용 여부',
                  style: TextStyle(fontSize: 12, color: Colors.black38),
                ),
                value: _isCouponApplicable,
                activeThumbColor: const Color(0xFFFF6FA0),
                onChanged: (v) => setState(() => _isCouponApplicable = v),
              ),
            ),
            const SizedBox(height: 12),

            // ── 판매 활성화 ───────────────────────────────────────
            _card(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '판매 활성화',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _isActive ? '현재 판매 중' : '숨김 상태',
                  style: const TextStyle(fontSize: 12, color: Colors.black38),
                ),
                value: _isActive,
                activeThumbColor: const Color(0xFFFF6FA0),
                onChanged: (v) => setState(() => _isActive = v),
              ),
            ),
            const SizedBox(height: 28),

            // ── 등록 버튼 ─────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6FA0),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.black12,
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
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        '상품 등록',
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
    );
  }
}
