import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/models/place_product.dart';
import 'package:party_app/models/product_refund_feature.dart';
import 'package:party_app/widgets/party_form/register_field_anchor.dart';
import 'package:party_app/widgets/party_form/wheel_time_picker_sheet.dart';

/// "이 상품의 취소·환불 규정을 펼쳐라" 신호.
///
/// 값은 상품 인덱스 하나뿐이지만, **같은 상품을 연달아 가리켜도 다시**
/// 펼쳐져야 한다 — 안내를 눌러 이동한 뒤 사용자가 카드를 도로 접고 같은 줄을
/// 다시 누르면, 값이 그대로라 [ValueNotifier]가 알림을 보내지 않아 두 번째
/// 탭이 통째로 먹히지 않았다. [request]는 한 번 비운 뒤 세워 그 구멍을 막는다.
class ProductRefundReveal extends ValueNotifier<int?> {
  ProductRefundReveal() : super(null);

  void request(int index) {
    value = null;
    value = index;
  }
}

/// 플레이스 등록·수정 화면의 "상품·이용권 판매" 섹션.
///
/// 술집·바·카페와 공간대여·숙박이 **같은 위젯 하나**를 쓴다 — 두 유형의
/// 차이는 상품 문서의 `placeCollection` 값뿐이라([PlaceProduct]) UI를 나눌
/// 이유가 없다.
///
/// 유형별 입력칸은 여기서 하드코딩하지 않고 [kProductTypeFields] 명세를 읽어
/// 그린다. 판매 유형이 늘어나도 이 파일은 그대로다 — 모델 쪽 명세만 늘리면
/// 등록 폼·검증·상세 표시가 함께 따라온다.
///
/// 상태 소유는 [RoundListEditor]와 같은 방식이다 — 부모가 [products] 목록을
/// 들고 있고, 이 위젯은 그 목록을 직접 고친 뒤 [onChanged]로 알린다. 그래야
/// 등록 화면의 기존 임시저장 흐름(payload에 목록을 통째로 담기)이 그대로
/// 동작한다.
class PlaceProductEditor extends StatefulWidget {
  const PlaceProductEditor({
    super.key,
    required this.products,
    required this.onChanged,
    required this.accent,
    this.showAddonChannel = true,
    this.revealRefundOf,
    this.refundAnchorKey,
    this.refundFocusNode,
  });

  /// 부모가 소유하는 상품 목록 — 이 위젯이 직접 추가/삭제/재정렬한다.
  final List<PlaceProduct> products;

  final VoidCallback onChanged;

  /// 유형별 강조색(술집=핑크, 숙박=보라).
  final Color accent;

  /// "예약 시 추가 옵션" 판매 방식을 고를 수 있는지.
  /// 예약 기능이 없는 플레이스(술집·바·카페 중 예약 미사용)에서는 끈다.
  final bool showAddonChannel;

  /// **"이 상품의 취소·환불 규정을 보여줘"** 신호 — 값은 상품 인덱스다.
  ///
  /// 필수항목 안내에서 '상품의 취소·환불 규정을 입력해주세요.'를 눌렀을 때
  /// 쓰인다. 상품 카드는 한 번에 하나만 펼쳐지므로, 규정이 비어 있는 카드를
  /// **먼저 펼치지 않으면** 그 입력칸은 트리에 존재하지도 않는다.
  ///
  /// 화면이 소유하는 값이라, 이 위젯이 아직 만들어지지 않았어도(ListView는
  /// 화면 밖을 만들지 않는다) 먼저 신호를 세워 둘 수 있다 — 카드가 만들어지는
  /// 순간 그 값을 읽어 스스로 펼친다.
  final ValueNotifier<int?>? revealRefundOf;

  /// 위 신호가 가리키는 상품의 **취소·환불 규정 입력칸**에 붙는 앵커.
  /// 화면의 [RegisterFieldCheck.anchorKey]가 이 키를 그대로 가리킨다.
  final GlobalKey? refundAnchorKey;

  /// 그 입력칸의 포커스 — 이동이 끝난 뒤 커서를 놓는다. 다른 필수 입력칸
  /// (이름·평수·소개)과 같은 마무리라, 여기만 커서 없이 남겨두지 않는다.
  /// 노드의 주인은 화면이다([RegisterFieldCheck.focusNode]에 같은 것을 준다).
  final FocusNode? refundFocusNode;

  @override
  State<PlaceProductEditor> createState() => PlaceProductEditorState();
}

class PlaceProductEditorState extends State<PlaceProductEditor> {
  /// 펼쳐진 카드의 인덱스 — 한 번에 하나만 펼쳐 폼이 끝없이 길어지지 않게 한다.
  int? _expanded;

  @override
  void initState() {
    super.initState();
    widget.revealRefundOf?.addListener(_onRevealRefund);
    // 이 위젯이 뒤늦게 만들어졌는데 신호가 이미 서 있는 경우(화면 밖이라
    // 나중에 만들어지는 ListView 항목) — 만들어지자마자 그 카드를 편다.
    final pending = widget.revealRefundOf?.value;
    if (pending != null) _expanded = pending;
  }

  @override
  void didUpdateWidget(PlaceProductEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealRefundOf != widget.revealRefundOf) {
      oldWidget.revealRefundOf?.removeListener(_onRevealRefund);
      widget.revealRefundOf?.addListener(_onRevealRefund);
    }
  }

  @override
  void dispose() {
    widget.revealRefundOf?.removeListener(_onRevealRefund);
    super.dispose();
  }

  void _onRevealRefund() {
    final index = widget.revealRefundOf?.value;
    if (!mounted) return;
    if (index == null || index < 0 || index >= widget.products.length) return;
    setState(() => _expanded = index);
  }

  void _notify() {
    widget.onChanged();
    setState(() {});
  }

  void addProduct() {
    widget.products.add(
      PlaceProduct.empty(
        // placeId·hostId는 등록이 끝나 문서가 생길 때 화면이 채워 넣는다 —
        // 신규 등록 시점에는 아직 플레이스 문서 id가 없기 때문.
        placeId: '',
        placeCollection: '',
        hostId: '',
        sortOrder: widget.products.length,
      ),
    );
    _expanded = widget.products.length - 1;
    _notify();
  }

  void _remove(int i) {
    widget.products.removeAt(i);
    if (_expanded == i) {
      _expanded = null;
    } else if (_expanded != null && _expanded! > i) {
      _expanded = _expanded! - 1;
    }
    _resequence();
    _notify();
  }

  void _move(int i, int delta) {
    final to = i + delta;
    if (to < 0 || to >= widget.products.length) return;
    final item = widget.products.removeAt(i);
    widget.products.insert(to, item);
    if (_expanded == i) _expanded = to;
    _resequence();
    _notify();
  }

  /// 화면 순서를 sortOrder에 그대로 반영한다 — 저장 시 이 값이 목록 순서다.
  void _resequence() {
    for (var i = 0; i < widget.products.length; i++) {
      widget.products[i] = widget.products[i].copyWith(sortOrder: i);
    }
  }

  void _update(int i, PlaceProduct next) {
    widget.products[i] = next;
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '파티 외에도 유료 좌석권·입장권·이용권 같은 상품을 팔 수 있어요. '
          '손님은 플레이스 상세에서 바로 결제해 구매합니다.\n'
          '결제 없이 자리만 잡아두는 무료 예약은 위쪽 "방문 예약 받기"에서 켜요.',
          style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < widget.products.length; i++) ...[
          _ProductCard(
            key: ValueKey('product_$i'),
            index: i,
            total: widget.products.length,
            product: widget.products[i],
            accent: widget.accent,
            expanded: _expanded == i,
            showAddonChannel: widget.showAddonChannel,
            // 필수항목 안내가 가리키는 상품에만 앵커를 붙인다 — 상품이 여럿일
            // 때 같은 GlobalKey가 두 곳에 달리면 안 되기 때문이다.
            refundAnchorKey: widget.revealRefundOf?.value == i
                ? widget.refundAnchorKey
                : null,
            refundFocusNode: widget.revealRefundOf?.value == i
                ? widget.refundFocusNode
                : null,
            onToggleExpand: () =>
                setState(() => _expanded = _expanded == i ? null : i),
            onChanged: (next) => _update(i, next),
            onRemove: () => _remove(i),
            onMoveUp: i == 0 ? null : () => _move(i, -1),
            onMoveDown: i == widget.products.length - 1
                ? null
                : () => _move(i, 1),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: addProduct,
            icon: const Icon(Icons.add, size: 18),
            label: Text(
              widget.products.isEmpty ? '상품 추가' : '상품 더 추가',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.accent,
              side: BorderSide(color: widget.accent.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 상품 카드 하나
// ─────────────────────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    super.key,
    required this.index,
    required this.total,
    required this.product,
    required this.accent,
    required this.expanded,
    required this.showAddonChannel,
    required this.onToggleExpand,
    required this.onChanged,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
    this.refundAnchorKey,
    this.refundFocusNode,
  });

  /// 필수항목 안내에서 이 카드의 취소·환불 규정으로 이동할 때 쓰는 앵커와,
  /// 도착한 뒤 커서를 놓을 포커스. 대상 카드에만 넘어온다(위
  /// [PlaceProductEditor] 주석 참고).
  final GlobalKey? refundAnchorKey;
  final FocusNode? refundFocusNode;

  final int index;
  final int total;
  final PlaceProduct product;
  final Color accent;
  final bool expanded;
  final bool showAddonChannel;
  final VoidCallback onToggleExpand;
  final ValueChanged<PlaceProduct> onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final stopped = product.manuallyStopped;
    return Container(
      decoration: BoxDecoration(
        color: stopped ? const Color(0xFFF4F4F6) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded ? accent : const Color(0xFFE8EBF2),
          width: expanded ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, stopped),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: _form(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool stopped) => InkWell(
    onTap: onToggleExpand,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      product.type.badgeLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    if (stopped) ...[
                      const SizedBox(width: 6),
                      const _Pill(text: '판매 중지'),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  product.name.isEmpty ? '(상품명 없음)' : product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: product.name.isEmpty
                        ? Colors.black38
                        : Colors.black87,
                  ),
                ),
                if (product.salePrice > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${_comma(product.salePrice)}원',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 순서 변경 — 드래그 대신 위/아래 버튼을 쓴다. 이 섹션은 스크롤이
          // 긴 등록 폼 한가운데 있어서, 드래그로 옮기면 화면이 함께 움직여
          // 오히려 다루기 어렵다.
          _IconBtn(icon: Icons.arrow_upward, onTap: onMoveUp),
          _IconBtn(icon: Icons.arrow_downward, onTap: onMoveDown),
          Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            color: Colors.black38,
          ),
          const SizedBox(width: 4),
        ],
      ),
    ),
  );

  Widget _form(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 판매 유형 ──
        _label('판매 유형'),
        DropdownButtonFormField<PlaceProductType>(
          initialValue: product.type,
          isExpanded: true,
          decoration: _deco(),
          items: [
            for (final t in PlaceProductType.values)
              DropdownMenuItem(value: t, child: Text(t.badgeLabel)),
          ],
          // 유형이 바뀌면 이전 유형의 부가 입력값은 의미가 없다 — typeData를
          // 비워, 화면에 안 보이는 값이 저장에 섞여 들어가지 않게 한다.
          onChanged: (t) => t == null
              ? null
              : onChanged(product.copyWith(type: t, typeData: const {})),
        ),
        const SizedBox(height: 14),

        // ── 판매 방식 ──
        if (showAddonChannel) ...[
          _label('판매 방식'),
          DropdownButtonFormField<PlaceProductSaleChannel>(
            initialValue: product.saleChannel,
            isExpanded: true,
            decoration: _deco(),
            items: [
              for (final c in PlaceProductSaleChannel.values)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: (c) =>
                c == null ? null : onChanged(product.copyWith(saleChannel: c)),
          ),
          const SizedBox(height: 14),
        ],

        // ── 공통 입력 ──
        _text(
          '상품명',
          product.name,
          (v) => onChanged(product.copyWith(name: v)),
          hint: '예: 웰컴드링크 1잔',
        ),
        _text(
          '상품 설명',
          product.description,
          (v) => onChanged(product.copyWith(description: v)),
          maxLines: 3,
        ),
        _text(
          '대표 이미지 주소',
          product.imageUrl,
          (v) => onChanged(product.copyWith(imageUrl: v)),
          hint: '비워두면 플레이스 대표 사진을 씁니다',
        ),
        Row(
          children: [
            Expanded(
              child: _money(
                '정상 가격',
                product.listPrice,
                (v) => onChanged(product.copyWith(listPrice: v)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _money(
                '판매 가격',
                product.salePrice,
                (v) => onChanged(product.copyWith(salePrice: v)),
              ),
            ),
          ],
        ),
        if (product.discountPercent > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${product.discountPercent}% 할인으로 표시돼요',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _count(
                '판매 수량',
                product.totalStock,
                (v) => onChanged(product.copyWith(totalStock: v)),
                hint: '0 = 제한 없음',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _count(
                '1인당 구매 수량',
                product.perPersonLimit,
                (v) => onChanged(product.copyWith(perPersonLimit: v)),
                hint: '0 = 제한 없음',
              ),
            ),
          ],
        ),
        _dateRow(
          context,
          '판매 기간',
          product.saleStartAt,
          product.saleEndAt,
          (s, e) => onChanged(product.copyWith(saleStartAt: s, saleEndAt: e)),
        ),
        _dateRow(
          context,
          '이용 가능 기간',
          product.useStartAt,
          product.useEndAt,
          (s, e) => onChanged(product.copyWith(useStartAt: s, useEndAt: e)),
        ),
        _text(
          '이용 안내',
          product.useGuide,
          (v) => onChanged(product.copyWith(useGuide: v)),
          maxLines: 3,
        ),
        // 취소·환불 규정 — 지금은 화면에서 내려 둔다.
        //
        // 필드([PlaceProduct.refundPolicy])도, 값이 들어 있는 기존 문서도
        // 그대로다. 이 칸이 없다고 저장에서 값을 지우지 않는다 —
        // `copyWith`가 손대지 않으므로 읽어 온 값이 그대로 다시 나간다.
        // 필수 게이트도 같은 스위치가 함께 내린다([ProductRefundFeature]).
        if (ProductRefundFeature.enabled)
          _text(
            PlaceProductRefundPolicyRule.fieldLabel,
            product.refundPolicy,
            (v) => onChanged(product.copyWith(refundPolicy: v)),
            maxLines: 3,
            required: true,
            validator: PlaceProductRefundPolicyRule.validateText,
            anchorKey: refundAnchorKey,
            focusNode: refundFocusNode,
          ),

        SwitchListTile(
          value: product.useQrCheck,
          onChanged: (v) => onChanged(product.copyWith(useQrCheck: v)),
          activeThumbColor: accent,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'QR 확인 사용',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            '결제하면 주문마다 QR 이용권이 발급되고, 매장에서 스캔해 사용 처리해요',
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ),
        SwitchListTile(
          value: product.manuallyStopped,
          onChanged: (v) => onChanged(product.copyWith(manuallyStopped: v)),
          activeThumbColor: Colors.redAccent,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '판매 중지',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            '켜면 손님에게 보이지 않아요. 이미 팔린 이용권은 그대로 사용할 수 있어요',
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ),

        // ── 유형별 부가 입력 (명세 기반) ──
        ...() {
          final fields = fieldsForProductType(product.type);
          if (fields.isEmpty) return <Widget>[];
          return [
            const SizedBox(height: 6),
            Divider(color: accent.withValues(alpha: 0.25)),
            const SizedBox(height: 10),
            Text(
              '${product.type.label} 상세 정보',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
            const SizedBox(height: 12),
            for (final f in fields)
              _TypeField(
                spec: f,
                value: product.typeData[f.key],
                accent: accent,
                onChanged: (v) {
                  final next = Map<String, dynamic>.from(product.typeData);
                  if (v == null) {
                    next.remove(f.key);
                  } else {
                    next[f.key] = v;
                  }
                  onChanged(product.copyWith(typeData: next));
                },
              ),
          ];
        }(),

        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _confirmRemove(context),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('이 상품 삭제'),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    // 이미 팔린 상품은 삭제할 수 없다 — 발급된 이용권이 가리킬 상품이
    // 사라지면 QR 검증이 불가능해진다(firestore.rules에서도 막혀 있다).
    if (product.soldCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 판매된 상품은 삭제할 수 없어요. "판매 중지"를 사용해주세요.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('상품을 삭제할까요?'),
        content: Text(
          product.name.isEmpty
              ? '작성 중인 상품이 지워져요.'
              : '"${product.name}" 상품이 목록에서 지워져요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) onRemove();
  }

  // ── 작은 입력 헬퍼들 ──────────────────────────────────────────────────

  Widget _label(String t, {bool required = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text.rich(
      TextSpan(
        text: t,
        children: [
          if (required)
            TextSpan(
              text: ' *',
              style: TextStyle(color: Colors.red.shade400),
            ),
        ],
      ),
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
  );

  InputDecoration _deco({String? hint}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: Colors.black26),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    filled: true,
    fillColor: const Color(0xFFF7F7FA),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
  );

  Widget _text(
    String label,
    String value,
    ValueChanged<String> onSet, {
    String? hint,
    int maxLines = 1,
    bool required = false,
    FormFieldValidator<String>? validator,
    // 필수항목 안내가 **이 입력칸 자체**를 가리킬 때만 붙는다.
    GlobalKey? anchorKey,
    FocusNode? focusNode,
  }) => _maybeAnchored(
    anchorKey,
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label, required: required),
          // key로 초기값을 붙인다 — 유형을 바꿔 필드가 재구성돼도 값이 섞이지
          // 않고, 부모가 값을 갱신해도 커서가 튀지 않는다.
          TextFormField(
            key: ValueKey('$label|$index'),
            focusNode: focusNode,
            initialValue: value,
            maxLines: maxLines,
            decoration: _deco(hint: hint),
            style: const TextStyle(fontSize: 14),
            onChanged: onSet,
            validator: validator,
            // 옛 상품을 열었을 때 바로 빨간 문구가 뜨지는 않게 한다 — 열람은
            // 그대로 되고, 손대거나 저장을 눌렀을 때부터 알려준다.
            autovalidateMode: validator == null
                ? null
                : AutovalidateMode.onUserInteraction,
          ),
        ],
      ),
    ),
  );

  /// 앵커가 있으면 그 영역을 [RegisterFieldAnchor]로 감싼다 — 필수항목 안내가
  /// 이 칸으로 데려온 뒤 잠깐 강조해 "여기다"를 보여줄 수 있게 된다.
  /// 앵커가 없으면(대부분의 칸) 예전과 똑같이 아무것도 감싸지 않는다.
  Widget _maybeAnchored(GlobalKey? anchorKey, Widget child) => anchorKey == null
      ? child
      : RegisterFieldAnchor(key: anchorKey, child: child);

  Widget _money(String label, int value, ValueChanged<int> onSet) =>
      _numeric(label, value, onSet, suffix: '원');

  Widget _count(
    String label,
    int value,
    ValueChanged<int> onSet, {
    String? hint,
  }) => _numeric(label, value, onSet, hint: hint);

  Widget _numeric(
    String label,
    int value,
    ValueChanged<int> onSet, {
    String? suffix,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        TextFormField(
          key: ValueKey('$label|$index'),
          initialValue: value == 0 ? '' : value.toString(),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _deco(hint: hint ?? '0').copyWith(suffixText: suffix),
          style: const TextStyle(fontSize: 14),
          onChanged: (v) => onSet(int.tryParse(v) ?? 0),
        ),
      ],
    ),
  );

  Widget _dateRow(
    BuildContext context,
    String label,
    DateTime? start,
    DateTime? end,
    void Function(DateTime?, DateTime?) onSet,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        Row(
          children: [
            Expanded(
              child: _DateBox(
                value: start,
                placeholder: '시작일',
                accent: accent,
                onPick: (d) => onSet(d, end),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('~'),
            ),
            Expanded(
              child: _DateBox(
                value: end,
                placeholder: '종료일',
                accent: accent,
                onPick: (d) => onSet(start, d),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '비워두면 제한 없음',
          style: TextStyle(fontSize: 11.5, color: Colors.black38),
        ),
      ],
    ),
  );

  static String _comma(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// 명세([ProductFieldSpec]) 하나를 그리는 위젯 — 유형별 분기의 유일한 지점.
class _TypeField extends StatelessWidget {
  const _TypeField({
    required this.spec,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final ProductFieldSpec spec;
  final dynamic value;
  final Color accent;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = spec.required ? '${spec.label} *' : spec.label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: switch (spec.kind) {
        ProductFieldKind.toggle => SwitchListTile(
          value: value == true,
          onChanged: onChanged,
          activeThumbColor: accent,
          contentPadding: EdgeInsets.zero,
          title: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: spec.hint == null
              ? null
              : Text(
                  spec.hint!,
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
        ),
        ProductFieldKind.date => _labelled(
          label,
          _DateBox(
            value: value is num
                ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
                : null,
            placeholder: '날짜 선택',
            accent: accent,
            onPick: (d) => onChanged(d?.millisecondsSinceEpoch),
          ),
        ),
        ProductFieldKind.time => _labelled(
          label,
          _TimeBox(value: value as String?, accent: accent, onPick: onChanged),
        ),
        ProductFieldKind.choice => _labelled(
          label,
          _ChoiceBox(spec: spec, value: value as String?, onChanged: onChanged),
        ),
        ProductFieldKind.itemList => _labelled(
          label,
          _ItemListBox(
            items: (value as List?)?.cast<String>() ?? const [],
            hint: spec.hint,
            accent: accent,
            onChanged: (list) => onChanged(list.isEmpty ? null : list),
          ),
        ),
        _ => _labelled(label, _textField(context)),
      },
    );
  }

  Widget _labelled(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
      child,
      if (spec.hint != null && spec.kind != ProductFieldKind.itemList)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            spec.hint!,
            style: const TextStyle(fontSize: 11.5, color: Colors.black38),
          ),
        ),
    ],
  );

  Widget _textField(BuildContext context) {
    final numeric =
        spec.kind == ProductFieldKind.count ||
        spec.kind == ProductFieldKind.money ||
        spec.kind == ProductFieldKind.minutes;
    return TextFormField(
      key: ValueKey(spec.key),
      initialValue: value?.toString() ?? '',
      maxLines: spec.kind == ProductFieldKind.multiline ? 3 : 1,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        filled: true,
        fillColor: const Color(0xFFF7F7FA),
        suffixText: switch (spec.kind) {
          ProductFieldKind.money => '원',
          ProductFieldKind.minutes => '분',
          _ => null,
        },
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (v) {
        if (v.trim().isEmpty) return onChanged(null);
        onChanged(numeric ? (int.tryParse(v) ?? 0) : v);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 공용 소품
// ─────────────────────────────────────────────────────────────────────────────

class _DateBox extends StatelessWidget {
  const _DateBox({
    required this.value,
    required this.placeholder,
    required this.accent,
    required this.onPick,
  });

  final DateTime? value;
  final String placeholder;
  final Color accent;
  final ValueChanged<DateTime?> onPick;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: value ?? now,
        firstDate: DateTime(now.year - 1),
        lastDate: DateTime(now.year + 3),
      );
      if (picked != null) onPick(picked);
    },
    onLongPress: () => onPick(null),
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today, size: 15, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value == null
                  ? placeholder
                  : '${value!.year}.${value!.month}.${value!.day}',
              style: TextStyle(
                fontSize: 13.5,
                color: value == null ? Colors.black26 : Colors.black87,
              ),
            ),
          ),
          if (value != null)
            GestureDetector(
              onTap: () => onPick(null),
              child: const Icon(Icons.close, size: 15, color: Colors.black26),
            ),
        ],
      ),
    ),
  );
}

class _TimeBox extends StatelessWidget {
  const _TimeBox({
    required this.value,
    required this.accent,
    required this.onPick,
  });

  /// 'HH:mm' 문자열.
  final String? value;
  final Color accent;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final parts = value?.split(':');
      final initial = parts != null && parts.length == 2
          ? TimeOfDay(
              hour: int.tryParse(parts[0]) ?? 12,
              minute: int.tryParse(parts[1]) ?? 0,
            )
          : const TimeOfDay(hour: 12, minute: 0);
      // 파티 폼과 같은 휠 선택기를 쓴다 — 앱 전체에서 시간 고르는 방식이 하나다.
      final picked = await showWheelTimePicker(
        context,
        initial: initial,
        title: '시간 선택',
      );
      if (picked != null) {
        onPick(
          '${picked.hour.toString().padLeft(2, '0')}:'
          '${picked.minute.toString().padLeft(2, '0')}',
        );
      }
    },
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 15, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value ?? '시간 선택',
              style: TextStyle(
                fontSize: 13.5,
                color: value == null ? Colors.black26 : Colors.black87,
              ),
            ),
          ),
          if (value != null)
            GestureDetector(
              onTap: () => onPick(null),
              child: const Icon(Icons.close, size: 15, color: Colors.black26),
            ),
        ],
      ),
    ),
  );
}

class _ChoiceBox extends StatelessWidget {
  const _ChoiceBox({
    required this.spec,
    required this.value,
    required this.onChanged,
  });

  final ProductFieldSpec spec;
  final String? value;
  final ValueChanged<String?> onChanged;

  static const String _customSentinel = '__custom__';

  @override
  Widget build(BuildContext context) {
    // 보기에 없는 값이면 "직접 입력"으로 본다 — 저장된 커스텀 값이 드롭다운
    // 항목에 없어 assert로 터지는 걸 막는다.
    final isCustom = value != null && !spec.choices.contains(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: isCustom ? _customSentinel : value,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true,
            fillColor: Color(0xFFF7F7FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide.none,
            ),
          ),
          items: [
            for (final c in spec.choices)
              DropdownMenuItem(value: c, child: Text(c)),
            if (spec.allowCustomChoice)
              const DropdownMenuItem(
                value: _customSentinel,
                child: Text('기타 직접 입력'),
              ),
          ],
          onChanged: (v) =>
              onChanged(v == _customSentinel ? (isCustom ? value : '') : v),
        ),
        if (isCustom || (spec.allowCustomChoice && value == '')) ...[
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('${spec.key}_custom'),
            initialValue: isCustom ? value : '',
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              hintText: '직접 입력',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              filled: true,
              fillColor: Color(0xFFF7F7FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: onChanged,
          ),
        ],
      ],
    );
  }
}

/// 자유 항목 목록(포함 항목·혜택·옵션 등).
class _ItemListBox extends StatelessWidget {
  const _ItemListBox({
    required this.items,
    required this.hint,
    required this.accent,
    required this.onChanged,
  });

  final List<String> items;
  final String? hint;
  final Color accent;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < items.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('item_${i}_${items[i]}'),
                  initialValue: items[i],
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    filled: true,
                    fillColor: Color(0xFFF7F7FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) {
                    final next = [...items]..[i] = v;
                    onChanged(next);
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                color: Colors.black38,
                onPressed: () => onChanged([...items]..removeAt(i)),
              ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => onChanged([...items, '']),
          icon: const Icon(Icons.add, size: 16),
          label: Text(hint ?? '항목 추가'),
          style: TextButton.styleFrom(
            foregroundColor: accent,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 32),
            textStyle: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    ],
  );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, size: 18),
    color: onTap == null ? Colors.black12 : Colors.black38,
    onPressed: onTap,
    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE3E3),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: Color(0xFFD64545),
      ),
    ),
  );
}
