import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/screens/party_shop_manage_screen.dart';

// ── 옵션 항목 (이름 + 추가금액) ────────────────────────────────────
class _OptionEntry {
  final TextEditingController nameCtrl  = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
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

  const PartyShopProductRegisterScreen({
    super.key,
    required this.shopId,
    required this.shopName,
    this.shopData,
  });

  @override
  State<PartyShopProductRegisterScreen> createState() =>
      _PartyShopProductRegisterScreenState();
}

class _PartyShopProductRegisterScreenState
    extends State<PartyShopProductRegisterScreen> {
  final _nameCtrl  = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '0');

  List<XFile> _images = [];
  bool _isActive           = true;
  bool _isSameDayAvailable = false;
  bool _isCouponApplicable = false;
  bool _isSubmitting       = false;

  String _category = ListingConstants.shopCategories.first;
  bool   _isOnSale = false;

  final Set<String> _deliveryOpts = {};
  final List<_OptionEntry> _options = [];

  // 배송 옵션별 자동 안내 문구
  final Map<String, TextEditingController> _autoMsgCtrls = {
    'sameDay':   TextEditingController(),
    'pickup':    TextEditingController(),
    'delivery':  TextEditingController(),
    'scheduled': TextEditingController(),
  };

  static const _allDelivery = [
    ('sameDay',   Icons.bolt_outlined,           '당일 퀵',  '당일 퀵 배송'),
    ('pickup',    Icons.store_outlined,           '방문수령', '직접 방문 수령'),
    ('delivery',  Icons.local_shipping_outlined,  '택배',     '택배 배송'),
    ('scheduled', Icons.calendar_today_outlined,  '지정일',   '날짜 지정 배송'),
  ];

  static const _delivLabels = <String, String>{
    'sameDay':   '당일 퀵',
    'pickup':    '방문수령',
    'delivery':  '택배',
    'scheduled': '지정일',
  };

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    for (final o in _options) { o.dispose(); }
    for (final c in _autoMsgCtrls.values) { c.dispose(); }
    super.dispose();
  }

  // ── 이미지 선택 ──────────────────────────────────────────────────
  Future<void> _pickImages() async {
    if (_images.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미지는 최대 5장까지 등록할 수 있어요.')));
      return;
    }
    final picked = await ImagePicker().pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) { return; }
    setState(() {
      _images = [..._images, ...picked].take(5).toList();
    });
  }

  void _addOption() {
    setState(() => _options.add(_OptionEntry()));
  }

  void _removeOption(int idx) {
    final o = _options.removeAt(idx);
    o.dispose();
    setState(() {});
  }

  // ── 저장 ────────────────────────────────────────────────────────
  Future<void> _submit() async {
    final name  = _nameCtrl.text.trim();
    final desc  = _descCtrl.text.trim();
    final price = int.tryParse(_priceCtrl.text.trim()) ?? 0;
    final stock = int.tryParse(_stockCtrl.text.trim()) ?? 0;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('상품명을 입력해주세요.')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final imgUrls = <String>[];
      for (final x in _images) {
        final url = await CloudflareService.uploadImage(File(x.path));
        imgUrls.add(url);
      }

      final optList = _options
          .where((o) => o.nameCtrl.text.trim().isNotEmpty)
          .map((o) => {
                'name':            o.nameCtrl.text.trim(),
                'additionalPrice': int.tryParse(o.priceCtrl.text.trim()) ?? 0,
              })
          .toList();

      final autoMsgs = <String, String>{};
      for (final k in _deliveryOpts) {
        final txt = _autoMsgCtrls[k]?.text.trim() ?? '';
        if (txt.isNotEmpty) { autoMsgs[k] = txt; }
      }

      final doc = {
        'name':                name,
        'description':         desc,
        'price':               price,
        'imageUrls':           imgUrls,
        'stock':               stock,
        'options':             optList,
        'deliveryOptions':     _deliveryOpts.toList(),
        'isSameDayAvailable':  _isSameDayAvailable,
        'isCouponApplicable':  _isCouponApplicable,
        'category':            _category,
        'isOnSale':            _isOnSale,
        'autoMessages':        autoMsgs,
        'isActive':            _isActive,
        'hostId':              UserSession.userId,
        'shopId':              widget.shopId,
        'createdAt':           FieldValue.serverTimestamp(),
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
      final hasDiscount =
          allProducts.docs.any((d) => d.data()['isOnSale'] == true);
      final hasStock = allProducts.docs
          .any((d) => ((d.data()['stock'] as num?)?.toInt() ?? 0) > 0);
      await shopRef.update({
        'categories':  categories,
        'priceFrom':   priceFrom,
        'hasDiscount': hasDiscount,
        'hasStock':    hasStock,
      });

      if (!mounted) { return; }
      if (widget.shopData != null) {
        // 샵 등록 직후 → 관리화면으로 이동
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PartyShopManageScreen(
              shopId:   widget.shopId,
              shopData: widget.shopData!,
            ),
          ),
        );
      } else {
        Navigator.pop(context);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상품이 등록되었습니다!')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    } finally {
      if (mounted) { setState(() => _isSubmitting = false); }
    }
  }

  // ── UI ──────────────────────────────────────────────────────────
  InputDecoration _inputDeco(String hint, {String? prefix}) => InputDecoration(
        hintText: hint,
        prefixText: prefix,
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Color(0xFFFF6FA0), width: 1.5)),
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
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
                ])),
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
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text('상품 등록',
            style: TextStyle(fontFamily: 'SeoulHangang', fontSize: 17, fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: widget.shopData != null
            ? [
                TextButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PartyShopManageScreen(
                        shopId:   widget.shopId,
                        shopData: widget.shopData!,
                      ),
                    ),
                  ),
                  child: const Text('건너뛰기',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.black45,
                          fontWeight: FontWeight.w500)),
                ),
              ]
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
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
                    width: 84, height: 84,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      const Icon(Icons.add_photo_alternate_outlined,
                          color: Color(0xFFFF6FA0), size: 28),
                      const SizedBox(height: 2),
                      Text('${_images.length}/5',
                          style:
                              const TextStyle(fontSize: 11, color: Colors.black38)),
                    ]),
                  ),
                ),
                ..._images.asMap().entries.map((e) => Stack(children: [
                      Container(
                        width: 84, height: 84,
                        margin: const EdgeInsets.only(right: 10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child:
                              Image.file(File(e.value.path), fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        top: 2, right: 12,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _images.removeAt(e.key)),
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
          const SizedBox(height: 20),

          // ── 상품명 ────────────────────────────────────────────
          _sectionLabel('상품명 *'),
          TextField(
            controller: _nameCtrl,
            decoration: _inputDeco('상품명을 입력해주세요'),
            maxLength: 40,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
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
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _sectionLabel('판매가 (원)'),
                TextField(
                  controller: _priceCtrl,
                  decoration: _inputDeco('0', prefix: '₩ '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _sectionLabel('재고 수량'),
                TextField(
                  controller: _stockCtrl,
                  decoration: _inputDeco('0', prefix: '재고 '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ]),
            ),
          ]),
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
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFFFF6FA0) : const Color(0xFFF7F7FA),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
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
          const SizedBox(height: 12),
          _card(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('할인 상품으로 표시',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('상세검색의 "할인 상품" 필터에 노출돼요.',
                  style: TextStyle(fontSize: 12, color: Colors.black38)),
              value: _isOnSale,
              activeThumbColor: const Color(0xFFFF6FA0),
              onChanged: (v) => setState(() => _isOnSale = v),
            ),
          ),
          const SizedBox(height: 20),

          // ── 상품 옵션 ──────────────────────────────────────────
          Row(children: [
            const Text('상품 옵션',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            const Spacer(),
            TextButton.icon(
              onPressed: _addOption,
              icon: const Icon(Icons.add, size: 15, color: Color(0xFFFF6FA0)),
              label: const Text('옵션 추가',
                  style: TextStyle(
                      fontSize: 12, color: Color(0xFFFF6FA0))),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
            ),
          ]),
          const SizedBox(height: 4),
          if (_options.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '선택 옵션과 추가금액을 등록할 수 있어요.\n예) 레터링 추가 +5,000원',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.38),
                    height: 1.5),
              ),
            ),
          ..._options.asMap().entries.map((e) {
            final idx = e.key;
            final o   = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
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
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: () => _removeOption(idx),
                  icon: const Icon(Icons.remove_circle_outline,
                      color: Colors.black38, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            );
          }),
          const SizedBox(height: 20),

          // ── 배송·수령 가능 옵션 ────────────────────────────────
          _sectionLabel('배송·수령 가능 옵션'),
          _card(
            child: Column(
              children: _allDelivery.map((t) {
                final key   = t.$1;
                final icon  = t.$2;
                final label = t.$3;
                final desc  = t.$4;
                final sel   = _deliveryOpts.contains(key);
                return Column(children: [
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
                      child: Row(children: [
                        Icon(icon,
                            size: 20,
                            color: sel
                                ? const Color(0xFFFF6FA0)
                                : Colors.black26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(label,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: sel
                                        ? const Color(0xFFFF6FA0)
                                        : Colors.black87)),
                            Text(desc,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.black38)),
                          ]),
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
                              borderRadius: BorderRadius.circular(4)),
                        ),
                      ]),
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
                        hintStyle:
                            const TextStyle(fontSize: 12, color: Colors.black38),
                        filled: true,
                        fillColor: const Color(0xFFFFF9FB),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFFFD6E7))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFFFD6E7))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFFFF6FA0), width: 1.5)),
                        prefixIcon: const Icon(Icons.auto_awesome,
                            size: 15, color: Color(0xFFFF6FA0)),
                      ),
                      style: const TextStyle(fontSize: 13),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 8),
                  ],
                ]);
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          // ── 당일구매 가능 여부 ─────────────────────────────────
          _card(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('당일구매 가능',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('오늘 바로 구매·수령 가능 여부',
                  style: TextStyle(fontSize: 12, color: Colors.black38)),
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
              title: const Text('쿠폰 적용 가능',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('샵 방문 할인쿠폰 적용 허용 여부',
                  style: TextStyle(fontSize: 12, color: Colors.black38)),
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
              title: const Text('판매 활성화',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(
                _isActive ? '현재 판매 중' : '숨김 상태',
                style:
                    const TextStyle(fontSize: 12, color: Colors.black38)),
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
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Text('상품 등록',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
