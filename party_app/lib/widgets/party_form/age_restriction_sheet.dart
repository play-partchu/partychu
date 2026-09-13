import 'package:flutter/material.dart';
import 'package:party_app/models/party_age_restriction.dart';
import 'package:party_app/utils/age_range_utils.dart';
import 'package:party_app/widgets/party_form/age_picker_sheet.dart';

/// 연령대 설정 시트 — 연령 제한을 **성별마다 따로** 고른다.
///
/// 등록 화면과 주고받는 값은 [PartyAgeRestriction] 하나다(Firestore 스키마와
/// 1:1). 시트 내부 UI만 사용자에게 "몇 세"로 보이도록 나이 기준으로 동작하고,
/// 나갈 때 나이를 출생연도로 되돌린다.
///
/// ## 성별 모집 설정과의 연동
/// [genderLimit]이
///   · 'male'   → 남성 칸만
///   · 'female' → 여성 칸만
///   · 그 밖(제한 없음/남녀 모두) → 남성·여성 둘 다
/// 를 보여준다. 숨겨진 성별의 값은 저장 직전
/// [PartyAgeRestriction.toFields]에서 지워지므로, 호스트가 성별 모집을 바꿔도
/// 화면에 없던 옛 제한이 파티에 적용되는 일은 없다.
///
/// [audienceType]에 따라 고를 수 있는 나이 범위가 달라진다(`partyAgeRangeFor`
/// 참고). 지금 호출부는 모두 audienceType을 고르는 UI가 없어 기본값
/// ([PartyAudienceType.adult])으로 연다 — 나중에 청소년 전용 파티 유형 선택이
/// 등록 화면에 생기면 그 값을 그대로 여기 넘기기만 하면 된다.
Future<PartyAgeRestriction?> showAgeRestrictionSheet(
  BuildContext context, {
  required PartyAgeRestriction initial,
  String genderLimit = 'all',
  PartyAudienceType audienceType = PartyAudienceType.adult,
}) {
  return showModalBottomSheet<PartyAgeRestriction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AgeRestrictionSheetBody(
      initial: initial,
      genderLimit: genderLimit,
      audienceType: audienceType,
    ),
  );
}

class _AgeRestrictionSheetBody extends StatefulWidget {
  final PartyAgeRestriction initial;
  final String genderLimit;
  final PartyAudienceType audienceType;

  const _AgeRestrictionSheetBody({
    required this.initial,
    required this.genderLimit,
    required this.audienceType,
  });

  @override
  State<_AgeRestrictionSheetBody> createState() =>
      _AgeRestrictionSheetBodyState();
}

/// 한 성별의 편집 상태 — 나이 단위로만 들고 있다가 나갈 때 출생연도로 바꾼다.
class _GenderDraft {
  bool enabled;
  int minAge;
  int maxAge;

  _GenderDraft({
    required this.enabled,
    required this.minAge,
    required this.maxAge,
  });
}

class _AgeRestrictionSheetBodyState extends State<_AgeRestrictionSheetBody> {
  late bool _enabled = widget.initial.enabled;
  late final PartyAgeRange _range = partyAgeRangeFor(widget.audienceType);

  late final _GenderDraft _male = _draftOf(widget.initial.male);
  late final _GenderDraft _female = _draftOf(widget.initial.female);

  /// 저장돼 있던 제한 → 편집용 나이 값.
  ///
  /// 제한이 없던(또는 값이 비어 있던) 성별은 예전 기본값과 같은 23~31세로
  /// 연다 — 스위치를 켜자마자 뭔가 그럴듯한 범위가 보여야 고르기 쉽다.
  _GenderDraft _draftOf(GenderAgeLimit limit) {
    final minAge = (limit.minAge ?? 23).clamp(_range.minAge, _range.maxAge);
    final maxAge = (limit.maxAge ?? 31).clamp(_range.minAge, _range.maxAge);
    return _GenderDraft(
      enabled: limit.enabled,
      minAge: minAge,
      maxAge: maxAge < minAge ? minAge : maxAge,
    );
  }

  bool get _showMale => widget.genderLimit != 'female';
  bool get _showFemale => widget.genderLimit != 'male';

  Future<void> _pickAge(int current, ValueChanged<int> onChanged) async {
    final picked = await showAgePickerSheet(
      context,
      currentAge: current,
      audienceType: widget.audienceType,
    );
    if (picked != null) onChanged(picked);
  }

  void _confirm() {
    // 화면에 없던 성별은 여기서 손대지 않는다 — 어차피 저장 직전
    // PartyAgeRestriction.toFields가 genderLimit에 맞춰 지운다.
    Navigator.pop(
      context,
      PartyAgeRestriction(
        enabled: _enabled,
        male: _limitOf(_male, shown: _showMale, previous: widget.initial.male),
        female: _limitOf(
          _female,
          shown: _showFemale,
          previous: widget.initial.female,
        ),
        perGender: true,
      ),
    );
  }

  GenderAgeLimit _limitOf(
    _GenderDraft draft, {
    required bool shown,
    required GenderAgeLimit previous,
  }) {
    if (!shown) return previous;
    if (!draft.enabled) return GenderAgeLimit.off;
    return GenderAgeLimit.fromAges(minAge: draft.minAge, maxAge: draft.maxAge);
  }

  Widget _agePickerButton(
    String label,
    int currentAge,
    ValueChanged<int> onChanged,
  ) {
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
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.black45),
            ),
            const SizedBox(height: 4),
            Text(
              '$currentAge세',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 성별 한 칸 — 자체 on/off 스위치 + 최소/최대 나이.
  Widget _genderBlock(String title, _GenderDraft draft) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Switch(
                value: draft.enabled,
                onChanged: (v) => setState(() => draft.enabled = v),
                activeThumbColor: Colors.indigo,
              ),
            ],
          ),
          if (!draft.enabled)
            Text(
              '이 성별은 연령 제한 없음',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            )
          else ...[
            Text(
              '참여 가능 나이 (대한민국 기준 · ${_range.minAge}세 ~ ${_range.maxAge}세 사이)',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _agePickerButton('최소 나이', draft.minAge, (age) {
                    setState(() {
                      draft.minAge = age;
                      if (draft.minAge > draft.maxAge) draft.maxAge = age;
                    });
                  }),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    '~',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: _agePickerButton('최대 나이', draft.maxAge, (age) {
                    setState(() {
                      draft.maxAge = age;
                      if (draft.maxAge < draft.minAge) draft.minAge = age;
                    });
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${draft.minAge}세 ~ ${draft.maxAge}세 참여 가능',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.indigo,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
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
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '연령대 설정',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text(
                    '연령 제한',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Switch(
                    value: _enabled,
                    onChanged: (v) => setState(() {
                      _enabled = v;
                      // 켜자마자 아무 성별도 제한되지 않은 상태로 두면 "연령
                      // 제한을 켰는데 아무도 안 걸린다"가 된다 — 보이는 성별을
                      // 함께 켜 준다(끄는 건 각 성별 스위치로).
                      if (v && !_male.enabled && !_female.enabled) {
                        if (_showMale) _male.enabled = true;
                        if (_showFemale) _female.enabled = true;
                      }
                    }),
                    activeThumbColor: Colors.indigo,
                  ),
                ],
              ),
              if (_enabled) ...[
                const SizedBox(height: 4),
                Text(
                  '성별마다 따로 정할 수 있어요. 한쪽만 제한하고 다른 성별은 '
                  '제한 없이 둘 수도 있습니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 10),
                if (_showMale) _genderBlock('남성 연령 제한', _male),
                if (_showMale && _showFemale) const SizedBox(height: 10),
                if (_showFemale) _genderBlock('여성 연령 제한', _female),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '연령 제한 없음',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '선택 완료',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
