import 'package:flutter/material.dart';
import 'package:party_app/utils/age_range_utils.dart';
import 'package:party_app/widgets/party_form/age_picker_sheet.dart';

/// 파티 등록 화면과 주고받는 값은 그대로 출생연도(`minYear`/`maxYear`,
/// Firestore `minBirthYear`/`maxBirthYear` 스키마와 1:1)로 유지한다 — 내부
/// 저장/비교 로직(`party_eligibility.dart`)을 바꾸지 않기 위함이다. 이
/// 시트 내부 UI만 사용자에게 "몇 세"로 보이도록 나이 기준으로 동작하고,
/// 화면을 나갈 때만 나이를 출생연도로 변환한다.
class AgeRestrictionDraft {
  final bool enabled;
  final int minYear;
  final int maxYear;

  const AgeRestrictionDraft({
    required this.enabled,
    required this.minYear,
    required this.maxYear,
  });
}

/// [audienceType]에 따라 고를 수 있는 나이 범위가 달라진다(`partyAgeRangeFor`
/// 참고). 지금 유일한 호출부인 `party_register_screen.dart`는 아직
/// audienceType을 고르는 UI가 없어 항상 기본값([PartyAudienceType.adult])으로
/// 연다 — 나중에 청소년 전용 파티 유형 선택이 등록 화면에 생기면 그 값을
/// 그대로 여기 넘기기만 하면 된다.
Future<AgeRestrictionDraft?> showAgeRestrictionSheet(
  BuildContext context, {
  required AgeRestrictionDraft initial,
  PartyAudienceType audienceType = PartyAudienceType.adult,
}) {
  return showModalBottomSheet<AgeRestrictionDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AgeRestrictionSheetBody(initial: initial, audienceType: audienceType),
  );
}

class _AgeRestrictionSheetBody extends StatefulWidget {
  final AgeRestrictionDraft initial;
  final PartyAudienceType audienceType;

  const _AgeRestrictionSheetBody({required this.initial, required this.audienceType});

  @override
  State<_AgeRestrictionSheetBody> createState() => _AgeRestrictionSheetBodyState();
}

class _AgeRestrictionSheetBodyState extends State<_AgeRestrictionSheetBody> {
  late bool _enabled = widget.initial.enabled;
  late final PartyAgeRange _range = partyAgeRangeFor(widget.audienceType);

  // 출생연도가 클수록(최근일수록) 나이는 어리다 — minYear(더 이른 출생연도)는
  // 가장 나이 많은 쪽(_maxAge), maxYear(더 늦은 출생연도)는 가장 어린 쪽
  // (_minAge)에 대응한다.
  late int _minAge =
      ageFromBirthYear(widget.initial.maxYear).clamp(_range.minAge, _range.maxAge);
  late int _maxAge =
      ageFromBirthYear(widget.initial.minYear).clamp(_range.minAge, _range.maxAge);

  Future<void> _pickAge(int current, ValueChanged<int> onChanged) async {
    final picked = await showAgePickerSheet(
      context,
      currentAge: current,
      audienceType: widget.audienceType,
    );
    if (picked != null) onChanged(picked);
  }

  Widget _agePickerButton(String label, int currentAge, ValueChanged<int> onChanged) {
    return GestureDetector(
      onTap: () => _pickAge(currentAge, onChanged),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.indigo.shade200),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.black45)),
            const SizedBox(height: 4),
            Text('$currentAge세',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
          ],
        ),
      ),
    );
  }

  void _confirm() {
    Navigator.pop(
      context,
      AgeRestrictionDraft(
        enabled: _enabled,
        // 나이가 많을수록(=_maxAge) 출생연도는 이르다(=minYear).
        minYear: birthYearFromAge(_maxAge),
        maxYear: birthYearFromAge(_minAge),
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
              const Text('연령대 설정',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text('연령 제한', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Switch(
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                    activeThumbColor: Colors.indigo,
                  ),
                ],
              ),
              if (_enabled) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF3FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '참여 가능 나이 범위 (대한민국 기준 · ${_range.minAge}세 ~ ${_range.maxAge}세 사이)',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _agePickerButton('최소 나이', _minAge, (age) {
                              setState(() {
                                _minAge = age;
                                if (_minAge > _maxAge) _maxAge = age;
                              });
                            }),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text('~', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            child: _agePickerButton('최대 나이', _maxAge, (age) {
                              setState(() {
                                _maxAge = age;
                                if (_maxAge < _minAge) _minAge = age;
                              });
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_minAge세 ~ $_maxAge세 참여 가능',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.indigo, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('연령 제한 없음',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ),
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
