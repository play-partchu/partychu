import 'package:flutter/material.dart';

import 'package:party_app/models/party_gender_recruit.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 호스트가 **남성 모집 / 여성 모집을 따로 열고 닫는** 공용 입력 위젯.
///
/// 파티 수정 화면과 내 파티 목록의 '모집 상태 변경' 시트가 이 하나를 함께
/// 쓴다 — 두 자리에 따로 만들면 같은 설정이 화면마다 다른 뜻을 갖게 된다.
///
/// ## 전체 모집마감은 여기가 아니다
///
/// '전체 모집중 / 전체 모집마감'은 기존 모집 상태(`recruitStatus`)가 그대로
/// 담당한다. 이 위젯은 그 위에 얹히는 **성별별 예외**만 다룬다:
///
///   · 전체 모집중 + 남·여 모두 켬   → 전체 모집중
///   · 전체 모집중 + 남성만 끔       → 남성 모집마감 · 여성 모집중
///   · 전체 모집중 + 여성만 끔       → 남성 모집중 · 여성 모집마감
///   · 전체 마감(recruitStatus)      → 성별과 무관하게 전체 모집마감
///
/// 그래서 전체 상태가 모집중이 아닐 때는 [enabled]를 false로 받아 잠근다 —
/// 이미 전부 닫힌 파티에서 성별 스위치를 만지면 "무엇이 이겼는지"가 화면마다
/// 달라 보인다(판정은 언제나 전체 상태가 먼저다: PartyCard.effectiveStatusFor).
///
/// ## 성별 제한 파티
///
/// [genderLimit]이 'male'/'female'이면 받지 않는 성별의 스위치는 아예 그리지
/// 않는다 — 남자만 받는 파티의 '여성 모집'은 뜻이 없다.
class GenderRecruitStatusField extends StatelessWidget {
  const GenderRecruitStatusField({
    super.key,
    required this.maleOpen,
    required this.femaleOpen,
    required this.onChanged,
    this.genderLimit = 'all',
    this.enabled = true,
    this.disabledNote,
  });

  /// 남성 모집을 받는가(= 스위치 켬).
  final bool maleOpen;

  /// 여성 모집을 받는가(= 스위치 켬).
  final bool femaleOpen;

  /// 파티 문서의 `genderLimit` — 'all' / 'male' / 'female'.
  final String genderLimit;

  /// 전체 모집 상태가 '모집중'이 아닐 때 false로 넘겨 잠근다.
  final bool enabled;

  /// 잠긴 이유 한 줄(예: '전체 모집마감 상태예요').
  final String? disabledNote;

  final ValueChanged<({bool maleOpen, bool femaleOpen})> onChanged;

  bool get _showsMale => genderLimit != PartyGenderRecruit.female;
  bool get _showsFemale => genderLimit != PartyGenderRecruit.male;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '성별별 모집',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          enabled
              ? '한쪽 성별만 마감할 수 있어요. 끈 성별은 신청을 받지 않아요.'
              : (disabledNote ?? '전체 모집 상태가 우선이에요.'),
          style: TextStyle(
            fontSize: 12,
            color: enabled ? Colors.black54 : PartyChuColors.primaryDeep,
          ),
        ),
        const SizedBox(height: 4),
        if (_showsMale)
          _row(
            label: '남성 모집',
            open: maleOpen,
            onChanged: (v) => onChanged((maleOpen: v, femaleOpen: femaleOpen)),
          ),
        if (_showsFemale)
          _row(
            label: '여성 모집',
            open: femaleOpen,
            onChanged: (v) => onChanged((maleOpen: maleOpen, femaleOpen: v)),
          ),
      ],
    );
  }

  Widget _row({
    required String label,
    required bool open,
    required ValueChanged<bool> onChanged,
  }) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    value: open,
    onChanged: enabled ? onChanged : null,
    title: Text(label, style: const TextStyle(fontSize: 14)),
    subtitle: Text(
      open ? '모집중' : '모집마감',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: open ? const Color(0xFF2E7D32) : PartyChuColors.primaryDeep,
      ),
    ),
  );
}
