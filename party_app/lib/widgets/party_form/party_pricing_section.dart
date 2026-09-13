import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:party_app/models/party_pricing.dart';

const _kAccent = Color(0xFFFF6FA0);
const _kBoxFill = Color(0xFFF7F7FA);
const _kBorder = Color(0xFFE8EBF2);

/// 파티 참가비 입력 — 일반 파티 등록과 플레이스+파티 등록이 함께 쓰는 섹션.
///
/// 무료 / 같은 금액 / 남녀 다른 금액 세 가지를 한 곳에서 고르게 해서, 어느
/// 화면에서 등록하든 저장되는 [PartyPricing] 구조가 동일해진다.
class PartyPricingSection extends StatefulWidget {
  final PartyPricing value;
  final ValueChanged<PartyPricing> onChanged;

  /// 성별 제한이 걸린 파티(남자만/여자만)에서는 "남녀 다른 금액"이 의미가
  /// 없으므로 숨긴다. 'all' | 'male' | 'female'.
  final String genderLimit;

  const PartyPricingSection({
    super.key,
    required this.value,
    required this.onChanged,
    this.genderLimit = 'all',
  });

  @override
  State<PartyPricingSection> createState() => _PartyPricingSectionState();
}

class _PartyPricingSectionState extends State<PartyPricingSection> {
  late final _sameCtrl = TextEditingController(
    text: _initialText(
      widget.value.type == PartyPricingType.same ? widget.value.price : null,
    ),
  );
  late final _maleCtrl = TextEditingController(
    text: _initialText(widget.value.malePrice),
  );
  late final _femaleCtrl = TextEditingController(
    text: _initialText(widget.value.femalePrice),
  );

  static String _initialText(int? value) =>
      (value == null || value <= 0) ? '' : '$value';

  @override
  void dispose() {
    _sameCtrl.dispose();
    _maleCtrl.dispose();
    _femaleCtrl.dispose();
    super.dispose();
  }

  bool get _genderedAllowed => widget.genderLimit == 'all';

  /// 사용자가 고른 유형은 화면 상태로 따로 들고 있는다.
  /// [PartyPricing]은 0원을 무료로 정규화하기 때문에, 금액을 지웠다가 다시
  /// 입력하는 도중에 칩이 "무료"로 튀는 것을 막기 위함이다.
  late PartyPricingType _selectedType = widget.value.type;

  void _setType(PartyPricingType type) {
    setState(() => _selectedType = type);
    _emit();
  }

  /// 현재 고른 유형 + 입력값으로 [PartyPricing]을 만들어 올려보낸다.
  void _emit() {
    switch (_selectedType) {
      case PartyPricingType.free:
        widget.onChanged(const PartyPricing.free());
      case PartyPricingType.same:
        widget.onChanged(
          PartyPricing.same(int.tryParse(_sameCtrl.text.trim())),
        );
      case PartyPricingType.gendered:
        widget.onChanged(
          PartyPricing.gendered(
            male: int.tryParse(_maleCtrl.text.trim()),
            female: int.tryParse(_femaleCtrl.text.trim()),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 남녀 다른 금액을 고를 수 없는 상황(성별 제한 파티)에서는 같은 금액으로
    // 보이게 한다.
    final effectiveType =
        !_genderedAllowed && _selectedType == PartyPricingType.gendered
        ? PartyPricingType.same
        : _selectedType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _typeChip('무료', PartyPricingType.free, effectiveType),
            _typeChip('같은 금액', PartyPricingType.same, effectiveType),
            if (_genderedAllowed)
              _typeChip('남녀 다른 금액', PartyPricingType.gendered, effectiveType),
          ],
        ),
        const SizedBox(height: 12),
        if (effectiveType == PartyPricingType.same)
          _amountField(
            controller: _sameCtrl,
            label: '참가비',
            onChanged: (_) => _emit(),
          )
        else if (effectiveType == PartyPricingType.gendered) ...[
          _amountField(
            controller: _maleCtrl,
            label: '남성 참가비',
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 8),
          _amountField(
            controller: _femaleCtrl,
            label: '여성 참가비',
            onChanged: (_) => _emit(),
          ),
        ] else
          const Text(
            '참가비 없이 무료로 진행돼요.',
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
      ],
    );
  }

  Widget _typeChip(
    String label,
    PartyPricingType type,
    PartyPricingType current,
  ) {
    final selected = type == current;
    return GestureDetector(
      onTap: () => _setType(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFE8F2) : _kBoxFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? _kAccent : _kBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: selected ? _kAccent : Colors.black87,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _amountField({
    required TextEditingController controller,
    required String label,
    required ValueChanged<String> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            onChanged: onChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText: '0',
              suffixText: '원',
              hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              filled: true,
              fillColor: _kBoxFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}
