import 'package:flutter/material.dart';
import 'package:party_app/utils/refund_policy.dart';

/// 호스트가 파티별 환불 규정(기간 → 환불률)을 직접 등록/수정하는 위젯.
/// PartyChu는 환불률을 정하거나 권장하지 않는다 — 기본값 없이 빈 목록에서
/// 시작하며, 호스트가 직접 구간을 추가/삭제/순서 변경/환불률 입력한다.
class RefundPolicyEditor extends StatefulWidget {
  final List<RefundTier> initialTiers;
  final ValueChanged<List<RefundTier>> onChanged;

  const RefundPolicyEditor({
    super.key,
    required this.initialTiers,
    required this.onChanged,
  });

  @override
  State<RefundPolicyEditor> createState() => _RefundPolicyEditorState();
}

class _RefundPolicyEditorState extends State<RefundPolicyEditor> {
  late List<RefundTier> _tiers;

  @override
  void initState() {
    super.initState();
    _tiers = widget.initialTiers
        .map((t) => RefundTier(daysBefore: t.daysBefore, refundPercent: t.refundPercent))
        .toList();
  }

  void _notify() => widget.onChanged(_tiers);

  void _addTier() {
    setState(() => _tiers.add(RefundTier(daysBefore: 0, refundPercent: 0)));
    _notify();
  }

  void _removeTier(int index) {
    setState(() => _tiers.removeAt(index));
    _notify();
  }

  void _moveTier(int index, int delta) {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _tiers.length) return;
    setState(() {
      final item = _tiers.removeAt(index);
      _tiers.insert(newIndex, item);
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PartyChu는 환불률을 정하거나 권장하지 않습니다. 파티 시작 기준 며칠 전부터 '
          '몇 %를 환불할지 직접 구간을 등록해주세요. 참가자는 결제 전 이 규정을 확인할 수 '
          '있고, 구간이 없으면 참가자가 취소해도 환불이 계산되지 않습니다.',
          style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.5),
        ),
        const SizedBox(height: 12),
        if (_tiers.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7FA),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Text('등록된 환불 구간이 없어요',
                style: TextStyle(fontSize: 12, color: Colors.black38)),
          ),
        for (var i = 0; i < _tiers.length; i++) ...[
          if (i != 0) const SizedBox(height: 8),
          _tierRow(i),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _addTier,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFF6FA0),
            side: const BorderSide(color: Color(0xFFFF6FA0)),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('구간 추가'),
        ),
      ],
    );
  }

  Widget _tierRow(int index) {
    final tier = _tiers[index];
    return Container(
      key: ValueKey(tier.id),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE1EC)),
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: index == 0 ? null : () => _moveTier(index, -1),
                child: Icon(Icons.keyboard_arrow_up,
                    size: 18, color: index == 0 ? Colors.black26 : Colors.black54),
              ),
              InkWell(
                onTap: index == _tiers.length - 1 ? null : () => _moveTier(index, 1),
                child: Icon(Icons.keyboard_arrow_down,
                    size: 18,
                    color: index == _tiers.length - 1 ? Colors.black26 : Colors.black54),
              ),
            ],
          ),
          const SizedBox(width: 6),
          const Text('시작', style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(width: 4),
          SizedBox(
            width: 56,
            child: TextFormField(
              initialValue: tier.daysBefore.toString(),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                tier.daysBefore = int.tryParse(v) ?? 0;
                _notify();
              },
            ),
          ),
          const SizedBox(width: 4),
          const Text('일 전부터', style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: TextFormField(
              initialValue: tier.refundPercent.toString(),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                final n = int.tryParse(v) ?? 0;
                tier.refundPercent = n.clamp(0, 100);
                _notify();
              },
            ),
          ),
          const SizedBox(width: 4),
          const Text('%', style: TextStyle(fontSize: 12, color: Colors.black54)),
          const Spacer(),
          IconButton(
            onPressed: () => _removeTier(index),
            icon: const Icon(Icons.close, size: 18, color: Colors.black38),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/// 참가자에게 보여주는 읽기 전용 환불 규정 요약 — 파티 상세 화면과 취소
/// 확인창에서 재사용한다.
class RefundPolicyView extends StatelessWidget {
  final List<RefundTier> tiers;
  const RefundPolicyView({super.key, required this.tiers});

  @override
  Widget build(BuildContext context) {
    if (tiers.isEmpty) {
      return const Text(
        '호스트가 환불 규정을 등록하지 않았어요. 취소해도 환불되지 않을 수 있어요.',
        style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.5),
      );
    }
    final sorted = [...tiers]..sort((a, b) => b.daysBefore.compareTo(a.daysBefore));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '파티 시작 ${t.daysBefore}일 전부터: ${t.refundPercent}% 환불',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
      ],
    );
  }
}
