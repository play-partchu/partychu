import 'package:flutter/material.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/widgets/party_form/custom_time_picker_sheet.dart';
import 'package:party_app/widgets/party_form/date_time_sheet.dart' show formatPartyDate, formatPartyTime;

class FeeDraft {
  final int? maleFee;
  final int? femaleFee;
  final bool earlyBirdEnabled;
  final int? earlyBirdPercent;
  final DateTime? earlyBirdEndDate;
  final TimeOfDay? earlyBirdEndTime;

  const FeeDraft({
    this.maleFee,
    this.femaleFee,
    this.earlyBirdEnabled = false,
    this.earlyBirdPercent,
    this.earlyBirdEndDate,
    this.earlyBirdEndTime,
  });
}

/// 참가비(+얼리버드 할인) 바텀시트. [genderLimit]에 따라 남/여 참가비 필드
/// 중 필요한 것만 보여준다(등록 화면의 기존 `_genderLimit != 'female'` 등과 동일 조건).
Future<FeeDraft?> showFeeSheet(
  BuildContext context, {
  required String genderLimit,
  required FeeDraft initial,
}) {
  return showModalBottomSheet<FeeDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _FeeSheetBody(genderLimit: genderLimit, initial: initial),
  );
}

class _FeeSheetBody extends StatefulWidget {
  final String genderLimit;
  final FeeDraft initial;

  const _FeeSheetBody({required this.genderLimit, required this.initial});

  @override
  State<_FeeSheetBody> createState() => _FeeSheetBodyState();
}

class _FeeSheetBodyState extends State<_FeeSheetBody> {
  late final _maleFeeController =
      TextEditingController(text: widget.initial.maleFee?.toString() ?? '');
  late final _femaleFeeController =
      TextEditingController(text: widget.initial.femaleFee?.toString() ?? '');
  late final _percentController =
      TextEditingController(text: widget.initial.earlyBirdPercent?.toString() ?? '');
  late bool _earlyBirdEnabled = widget.initial.earlyBirdEnabled;
  late DateTime? _earlyBirdEndDate = widget.initial.earlyBirdEndDate;
  late TimeOfDay? _earlyBirdEndTime = widget.initial.earlyBirdEndTime;

  @override
  void dispose() {
    _maleFeeController.dispose();
    _femaleFeeController.dispose();
    _percentController.dispose();
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

  Future<void> _pickEarlyBirdEndDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = (_earlyBirdEndDate != null && !_earlyBirdEndDate!.isBefore(today))
        ? _earlyBirdEndDate!
        : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _earlyBirdEndDate = picked);
  }

  Future<void> _pickEarlyBirdEndTime() async {
    final picked = await showCustomTimePicker(
      context,
      initial: _earlyBirdEndTime ?? const TimeOfDay(hour: 18, minute: 0),
      title: '얼리버드 종료 시간',
    );
    if (picked != null) setState(() => _earlyBirdEndTime = picked);
  }

  Widget _earlyBirdPickerTile({
    required IconData icon,
    required String label,
    required bool hasValue,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: hasValue ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: hasValue ? const Color(0xFFFF6FA0) : Colors.black38),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                  color: hasValue ? Colors.black87 : Colors.black38,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirm() {
    Navigator.pop(
      context,
      FeeDraft(
        maleFee: int.tryParse(_maleFeeController.text.trim()),
        femaleFee: int.tryParse(_femaleFeeController.text.trim()),
        earlyBirdEnabled: _earlyBirdEnabled,
        earlyBirdPercent: int.tryParse(_percentController.text.trim()),
        earlyBirdEndDate: _earlyBirdEndDate,
        earlyBirdEndTime: _earlyBirdEndTime,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showMale = widget.genderLimit != 'female';
    final showFemale = widget.genderLimit != 'male';
    final maleFee = showMale ? (int.tryParse(_maleFeeController.text.trim()) ?? 0) : 0;
    final femaleFee = showFemale ? (int.tryParse(_femaleFeeController.text.trim()) ?? 0) : 0;
    final previewFee = maleFee > 0 ? maleFee : femaleFee;
    final pct = int.tryParse(_percentController.text.trim());

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
              const Text('참가비 설정',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 18),
              if (showMale) ...[
                _label('남자 참가비'),
                TextField(
                  controller: _maleFeeController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration('예: 5000 (0원 = 무료, 1,000원 단위)'),
                  onChanged: (_) => setState(() {}),
                ),
                if (showFemale) const SizedBox(height: 12),
              ],
              if (showFemale) ...[
                _label('여자 참가비'),
                TextField(
                  controller: _femaleFeeController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration('예: 5000 (0원 = 무료, 1,000원 단위)'),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text('🎉 얼리버드 할인',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Switch(
                    value: _earlyBirdEnabled,
                    onChanged: (v) => setState(() => _earlyBirdEnabled = v),
                    activeThumbColor: const Color(0xFFFF6FA0),
                  ),
                ],
              ),
              if (_earlyBirdEnabled) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('할인율', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _percentController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: _inputDecoration('예: 20').copyWith(suffixText: '%'),
                      ),
                      const SizedBox(height: 16),
                      const Text('얼리버드 종료일',
                          style: TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _earlyBirdPickerTile(
                              icon: Icons.calendar_today_outlined,
                              label: formatPartyDate(_earlyBirdEndDate),
                              hasValue: _earlyBirdEndDate != null,
                              onTap: _pickEarlyBirdEndDate,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _earlyBirdPickerTile(
                              icon: Icons.access_time,
                              label: formatPartyTime(_earlyBirdEndTime),
                              hasValue: _earlyBirdEndTime != null,
                              onTap: _pickEarlyBirdEndTime,
                            ),
                          ),
                        ],
                      ),
                      if (previewFee > 0 && pct != null && pct >= 1 && pct <= 99) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('할인 미리보기',
                                  style: TextStyle(fontSize: 11, color: Colors.black45)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    EarlyBird.formatPrice(previewFee),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black38,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward, size: 14, color: Colors.black38),
                                  const SizedBox(width: 8),
                                  Text(
                                    EarlyBird.formatPrice((previewFee * (100 - pct) / 100).round()),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFF6FA0),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
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
