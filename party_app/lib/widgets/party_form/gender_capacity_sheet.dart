import 'package:flutter/material.dart';

/// 성별/인원 제한 선택지 — 등록 화면의 기존 `_genderCapacityOptions`.
const List<Map<String, String>> genderCapacityOptions = [
  {'label': '남녀무관 (선착순)', 'genderLimit': 'all', 'mode': 'unlimited', 'genderMode': ''},
  {'label': '남성만', 'genderLimit': 'male', 'mode': 'unlimited', 'genderMode': ''},
  {'label': '여성만', 'genderLimit': 'female', 'mode': 'unlimited', 'genderMode': ''},
  {'label': '성비 맞춤', 'genderLimit': 'all', 'mode': 'separate', 'genderMode': 'balanced'},
];

class GenderCapacityDraft {
  final String genderLimit;
  final String genderCapacityMode;
  final String genderMode;
  final int? capacity;
  final int? maleCapacity;
  final int? femaleCapacity;

  const GenderCapacityDraft({
    required this.genderLimit,
    required this.genderCapacityMode,
    required this.genderMode,
    this.capacity,
    this.maleCapacity,
    this.femaleCapacity,
  });
}

/// 성별/인원 제한 바텀시트. [allowGenderLimitChange]가 false면(수정 화면)
/// 성별 제한 라디오 그룹을 숨기고 인원 필드만 보여준다 — 수정 화면은
/// 현재도 성별 제한을 바꾸는 기능 자체가 없으므로 새로 추가하지 않는다.
Future<GenderCapacityDraft?> showGenderCapacitySheet(
  BuildContext context, {
  required GenderCapacityDraft initial,
  bool allowGenderLimitChange = true,
}) {
  return showModalBottomSheet<GenderCapacityDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _GenderCapacitySheetBody(
      initial: initial,
      allowGenderLimitChange: allowGenderLimitChange,
    ),
  );
}

class _GenderCapacitySheetBody extends StatefulWidget {
  final GenderCapacityDraft initial;
  final bool allowGenderLimitChange;

  const _GenderCapacitySheetBody({
    required this.initial,
    required this.allowGenderLimitChange,
  });

  @override
  State<_GenderCapacitySheetBody> createState() => _GenderCapacitySheetBodyState();
}

class _GenderCapacitySheetBodyState extends State<_GenderCapacitySheetBody> {
  late String _genderLimit = widget.initial.genderLimit;
  late String _genderCapacityMode = widget.initial.genderCapacityMode;
  late String _genderMode = widget.initial.genderMode;
  late final _capacityController =
      TextEditingController(text: widget.initial.capacity?.toString() ?? '');
  late final _maleCapacityController =
      TextEditingController(text: widget.initial.maleCapacity?.toString() ?? '');
  late final _femaleCapacityController =
      TextEditingController(text: widget.initial.femaleCapacity?.toString() ?? '');

  @override
  void dispose() {
    _capacityController.dispose();
    _maleCapacityController.dispose();
    _femaleCapacityController.dispose();
    super.dispose();
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF7F7FA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  Widget _genderCapacitySelector() {
    return Column(
      children: genderCapacityOptions.map((option) {
        final selected = option['genderLimit'] == _genderLimit &&
            option['mode'] == _genderCapacityMode &&
            option['genderMode'] == _genderMode;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => setState(() {
              _genderLimit = option['genderLimit']!;
              _genderCapacityMode = option['mode']!;
              _genderMode = option['genderMode']!;
            }),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFEFF3FF) : const Color(0xFFF7F7FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? Colors.indigo.shade300 : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 18,
                    color: selected ? Colors.indigo : Colors.black38,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    option['label']!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                      color: selected ? Colors.black87 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _confirm() {
    Navigator.pop(
      context,
      GenderCapacityDraft(
        genderLimit: _genderLimit,
        genderCapacityMode: _genderCapacityMode,
        genderMode: _genderMode,
        capacity: int.tryParse(_capacityController.text.trim()),
        maleCapacity: int.tryParse(_maleCapacityController.text.trim()),
        femaleCapacity: int.tryParse(_femaleCapacityController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('성별 및 모집 인원',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 18),
              if (widget.allowGenderLimitChange) ...[
                _label('성별 / 인원 제한'),
                _genderCapacitySelector(),
                const SizedBox(height: 16),
              ],
              if (_genderCapacityMode == 'unlimited') ...[
                _label('전체 최대 인원'),
                TextField(
                  controller: _capacityController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration('예: 40'),
                  onChanged: (_) => setState(() {}),
                ),
              ] else ...[
                _label('남자 모집 인원'),
                TextField(
                  controller: _maleCapacityController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration('예: 5'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _label('여자 모집 인원'),
                TextField(
                  controller: _femaleCapacityController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration('예: 5'),
                  onChanged: (_) => setState(() {}),
                ),
                if (_genderMode == 'balanced') ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF3FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '총 모집 인원: ${(int.tryParse(_maleCapacityController.text) ?? 0) + (int.tryParse(_femaleCapacityController.text) ?? 0)}명 (자동 계산)',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: Colors.indigo),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6FA0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('선택 완료',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
