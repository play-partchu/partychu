import 'package:flutter/material.dart';

import 'package:party_app/models/pet_policy.dart';

/// "애견동반" 섹션 — 등록/수정 화면이 함께 쓰는 공용 편집기.
///
/// 장소 등록 화면(place_register_screen)의 인라인 구현과 완전히 같은 UI·동작을
/// 위젯 하나로 묶은 것이다. 상태는 밖에서 [value]로 넘기고 변경은 [onChanged]로
/// 돌려주므로, 저장 시점의 값은 늘 호출부가 들고 있다.
class PetPolicySection extends StatelessWidget {
  final PetPolicy value;
  final ValueChanged<PetPolicy> onChanged;

  /// 섹션 카드 제목 — 화면마다 다르게 쓸 수 있게 열어둔다.
  final String title;

  const PetPolicySection({
    super.key,
    required this.value,
    required this.onChanged,
    this.title = '애견동반',
  });

  static const _accent = Color(0xFFFF6FA0);

  bool get _showDetails =>
      value.status == PetPolicyStatus.possible ||
      value.status == PetPolicyStatus.conditional;

  static const _sizeOptions = ['제한 없음', '소형견만', '중형견까지', '직접 입력'];
  static const _fixedSizes = ['제한 없음', '소형견만', '중형견까지'];

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF7F7FA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          const Text(
            '반려동물 동반 가능 여부를 선택해주세요.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusOption('불가', PetPolicyStatus.notAllowed),
              _statusOption('가능', PetPolicyStatus.possible),
              _statusOption('조건부 가능', PetPolicyStatus.conditional),
            ],
          ),
          if (_showDetails) ...[
            const SizedBox(height: 16),
            _heading('동반 가능한 반려동물'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['강아지', '고양이', '기타'].map((animal) {
                final selected = value.allowedAnimals.contains(animal);
                return GestureDetector(
                  onTap: () {
                    final next = {...value.allowedAnimals};
                    selected ? next.remove(animal) : next.add(animal);
                    onChanged(value.copyWith(allowedAnimals: next));
                  },
                  child: _chip(animal, selected),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            _heading('크기 제한'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _sizeOptions.map((option) {
                final isCustom = option == '직접 입력';
                final selected =
                    value.sizeLimit == option ||
                    (isCustom &&
                        value.sizeLimit != null &&
                        !_fixedSizes.contains(value.sizeLimit));
                return GestureDetector(
                  onTap: () => onChanged(
                    value.copyWith(
                      sizeLimit: isCustom
                          ? (value.sizeLimit ?? '소형견만')
                          : option,
                    ),
                  ),
                  child: _chip(option, selected),
                );
              }).toList(),
            ),
            if (value.sizeLimit != null &&
                !_fixedSizes.contains(value.sizeLimit)) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _syncedController(value.sizeLimit!),
                decoration: _deco('예: 대형견 제외, 10kg 이하만'),
                onChanged: (v) => onChanged(
                  value.copyWith(sizeLimit: v.trim().isEmpty ? null : v.trim()),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _heading('최대 동반 가능 수'),
            const SizedBox(height: 8),
            TextField(
              keyboardType: TextInputType.number,
              decoration: _deco('예: 2'),
              controller: _syncedController(value.maxCount?.toString() ?? ''),
              onChanged: (v) =>
                  onChanged(value.copyWith(maxCount: int.tryParse(v.trim()))),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: value.extraFeeEnabled,
                  onChanged: (v) =>
                      onChanged(value.copyWith(extraFeeEnabled: v ?? false)),
                ),
                const Expanded(child: Text('추가 비용 있음')),
              ],
            ),
            if (value.extraFeeEnabled) ...[
              const SizedBox(height: 8),
              TextField(
                keyboardType: TextInputType.number,
                decoration: _deco('예: 5000'),
                controller: _syncedController(
                  (value.extraFeeAmount ?? 0).toString(),
                ),
                onChanged: (v) => onChanged(
                  value.copyWith(extraFeeAmount: int.tryParse(v.trim())),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _heading('이용 조건'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['매너벨트 필수', '케이지 필수', '실내 이동 제한', '예방접종 완료', '기타'].map((
                item,
              ) {
                final selected = value.requiredConditions.contains(item);
                return GestureDetector(
                  onTap: () {
                    final next = {...value.requiredConditions};
                    selected ? next.remove(item) : next.add(item);
                    onChanged(value.copyWith(requiredConditions: next));
                  },
                  child: _chip(item, selected),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            _heading('추가 안내 문구'),
            const SizedBox(height: 8),
            TextField(
              maxLines: 3,
              decoration: _deco('예: 실외 산책은 가능하나 실내는 제외됩니다.'),
              controller: _syncedController(value.notes ?? ''),
              onChanged: (v) => onChanged(
                value.copyWith(notes: v.trim().isEmpty ? null : v.trim()),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 값이 밖(부모 상태)에 있는 입력칸용 — 매 빌드마다 컨트롤러를 새로 만들되
  /// 커서를 항상 끝으로 붙인다(등록 화면의 기존 방식 그대로).
  TextEditingController _syncedController(String text) =>
      TextEditingController(text: text)
        ..selection = TextSelection.collapsed(offset: text.length);

  Widget _heading(String text) => Text(
    text,
    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
  );

  Widget _statusOption(String label, PetPolicyStatus status) => GestureDetector(
    onTap: () => onChanged(value.copyWith(status: status)),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: value.status == status ? _accent : const Color(0xFFFFF4F8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: value.status == status ? Colors.white : Colors.black87,
        ),
      ),
    ),
  );

  Widget _chip(String label, bool selected) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFFFFE8F2) : const Color(0xFFF7F7FA),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: selected ? _accent : const Color(0xFFE8EBF2)),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        color: selected ? _accent : Colors.black87,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    ),
  );
}
