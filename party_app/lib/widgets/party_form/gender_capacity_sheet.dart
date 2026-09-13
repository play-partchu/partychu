import 'package:flutter/material.dart';

import 'package:party_app/models/participant_gender_visibility.dart';
import 'package:party_app/models/party_capacity_status.dart';

/// 성별/인원 제한 선택지 — 등록 화면의 기존 `_genderCapacityOptions`.
const List<Map<String, String>> genderCapacityOptions = [
  {
    'label': '남녀무관 (선착순)',
    'genderLimit': 'all',
    'mode': 'unlimited',
    'genderMode': '',
  },
  {
    'label': '남성만',
    'genderLimit': 'male',
    'mode': 'unlimited',
    'genderMode': '',
  },
  {
    'label': '여성만',
    'genderLimit': 'female',
    'mode': 'unlimited',
    'genderMode': '',
  },
  {
    'label': '성비 맞춤',
    'genderLimit': 'all',
    'mode': 'separate',
    'genderMode': 'balanced',
  },
];

class GenderCapacityDraft {
  final String genderLimit;
  final String genderCapacityMode;
  final String genderMode;
  final int? capacity;
  final int? maleCapacity;
  final int? femaleCapacity;

  /// 최소 모집 인원(전체 기준). null/0이면 정하지 않은 것.
  final int? minCapacity;

  /// 최소 인원에 못 미친 채 모집이 마감됐을 때의 처리.
  final PartyMinCapacityPolicy minCapacityPolicy;

  /// 게스트에게 현재 참가자의 남/여 인원을 보여줄지
  /// ([ParticipantGenderVisibility]). 기본은 공개.
  final bool revealParticipantGenderRatio;

  const GenderCapacityDraft({
    required this.genderLimit,
    required this.genderCapacityMode,
    required this.genderMode,
    this.capacity,
    this.maleCapacity,
    this.femaleCapacity,
    this.minCapacity,
    this.minCapacityPolicy = PartyMinCapacityPolicy.proceed,
    this.revealParticipantGenderRatio =
        ParticipantGenderVisibility.defaultValue,
  });
}

/// 성별/인원 제한 바텀시트. [allowGenderLimitChange]가 false면(수정 화면)
/// 성별 제한 라디오 그룹을 숨기고 인원 필드만 보여준다 — 수정 화면은
/// 현재도 성별 제한을 바꾸는 기능 자체가 없으므로 새로 추가하지 않는다.
///
/// [isRecurring]은 이제 자동 취소를 막지 않는다 — 취소 단위가 파티 문서
/// 전체가 아니라 **미달된 그 회차 하나**라서 정기 파티에서도 성립한다.
/// 문구만 "회차 단위로 취소된다"로 달라진다.
///
/// [totalCapacity]는 차수별 정원 파티처럼 이 시트가 최대 인원을 직접 받지
/// 않을 때(=[showCapacityFields]가 false) "최소 ≤ 최대"를 검사하려고 호출부가
/// 넘겨주는 총 정원이다. 모르면 null이고, 그때는 검사를 건너뛴다.
Future<GenderCapacityDraft?> showGenderCapacitySheet(
  BuildContext context, {
  required GenderCapacityDraft initial,
  bool allowGenderLimitChange = true,
  bool isRecurring = false,
  bool showCapacityFields = true,
  int? totalCapacity,
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
      isRecurring: isRecurring,
      showCapacityFields: showCapacityFields,
      totalCapacity: totalCapacity,
    ),
  );
}

class _GenderCapacitySheetBody extends StatefulWidget {
  final GenderCapacityDraft initial;
  final bool allowGenderLimitChange;
  final bool isRecurring;

  /// false면 **최대** 인원 입력을 감춘다 — 라운드 진행 파티는 최대 인원을
  /// 차수마다 정하므로(라운드 설정 영역) 여기서 또 받으면 입력 위치가 둘이 된다.
  ///
  /// 최소 모집 인원은 이 값과 무관하게 **항상** 보여준다. 파티 전체에 하나뿐인
  /// 값이라 차수 설정이 대신할 수 없기 때문이다([PartyMinCapacity]).
  final bool showCapacityFields;

  /// [showCapacityFields]가 false일 때 "최소 ≤ 최대"를 검사할 총 정원.
  final int? totalCapacity;

  const _GenderCapacitySheetBody({
    required this.initial,
    required this.allowGenderLimitChange,
    required this.isRecurring,
    this.showCapacityFields = true,
    this.totalCapacity,
  });

  @override
  State<_GenderCapacitySheetBody> createState() =>
      _GenderCapacitySheetBodyState();
}

class _GenderCapacitySheetBodyState extends State<_GenderCapacitySheetBody> {
  late String _genderLimit = widget.initial.genderLimit;
  late String _genderCapacityMode = widget.initial.genderCapacityMode;
  late String _genderMode = widget.initial.genderMode;
  late final _capacityController = TextEditingController(
    text: widget.initial.capacity?.toString() ?? '',
  );
  late final _maleCapacityController = TextEditingController(
    text: widget.initial.maleCapacity?.toString() ?? '',
  );
  late final _femaleCapacityController = TextEditingController(
    text: widget.initial.femaleCapacity?.toString() ?? '',
  );
  late final _minCapacityController = TextEditingController(
    text: (widget.initial.minCapacity ?? 0) == 0
        ? ''
        : '${widget.initial.minCapacity}',
  );
  late PartyMinCapacityPolicy _minPolicy = widget.initial.minCapacityPolicy;
  late bool _revealGenderRatio = widget.initial.revealParticipantGenderRatio;

  @override
  void dispose() {
    _capacityController.dispose();
    _maleCapacityController.dispose();
    _femaleCapacityController.dispose();
    _minCapacityController.dispose();
    super.dispose();
  }

  int get _minCapacity => int.tryParse(_minCapacityController.text.trim()) ?? 0;

  /// 최대 모집 인원 — 남녀를 따로 받으면 두 칸의 합이다. 이 시트가 최대 인원을
  /// 받지 않는 차수별 정원 파티는 호출부가 넘겨준 총 정원을 쓴다.
  int get _maxCapacity {
    if (!widget.showCapacityFields) return widget.totalCapacity ?? 0;
    return _genderCapacityMode == 'unlimited'
        ? (int.tryParse(_capacityController.text.trim()) ?? 0)
        : (int.tryParse(_maleCapacityController.text.trim()) ?? 0) +
              (int.tryParse(_femaleCapacityController.text.trim()) ?? 0);
  }

  /// 최소가 최대를 넘으면 저장을 막고 문구를 띄운다.
  String? get _minError =>
      PartyCapacityStatus.validate(min: _minCapacity, max: _maxCapacity);

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF7F7FA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );

  Widget _genderCapacitySelector() {
    return Column(
      children: genderCapacityOptions.map((option) {
        final selected =
            option['genderLimit'] == _genderLimit &&
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
                color: selected
                    ? const Color(0xFFEFF3FF)
                    : const Color(0xFFF7F7FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? Colors.indigo.shade300 : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 18,
                    color: selected ? Colors.indigo : Colors.black38,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    option['label']!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.normal,
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
    // 최소 인원은 이제 라운드 파티에서도 이 시트가 받는다. 최대와 견줄 수
    // 있을 때만 검사한다(총 정원을 모르면 _maxCapacity가 0이라 통과).
    final error = _minError;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    Navigator.pop(
      context,
      GenderCapacityDraft(
        genderLimit: _genderLimit,
        genderCapacityMode: _genderCapacityMode,
        genderMode: _genderMode,
        capacity: int.tryParse(_capacityController.text.trim()),
        maleCapacity: int.tryParse(_maleCapacityController.text.trim()),
        femaleCapacity: int.tryParse(_femaleCapacityController.text.trim()),
        minCapacity: _minCapacity,
        // 최소 인원을 안 정했으면 미달 처리라는 개념 자체가 없다.
        minCapacityPolicy: _minCapacity > 0
            ? _minPolicy
            : PartyMinCapacityPolicy.proceed,
        revealParticipantGenderRatio: _revealGenderRatio,
      ),
    );
  }

  /// 참가자 현황 공개 — 게스트에게 현재 참가자의 남/여 인원을 보여줄지.
  ///
  /// 성별 모드와 무관하게 **항상** 보여준다. '남녀무관' 파티도 참가자에는
  /// 남녀가 섞여 있고 상세 화면이 그 내역을 보여주기 때문이다 — 성비 분리
  /// 모집일 때만 뜨게 하면 호스트가 설정 자체를 찾지 못한다.
  Widget _genderRatioVisibilitySection() {
    Widget option({
      required bool value,
      required String title,
      required String desc,
    }) {
      final selected = _revealGenderRatio == value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () => setState(() => _revealGenderRatio = value),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFEFF3FF)
                  : const Color(0xFFF7F7FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? Colors.indigo.shade300 : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: selected ? Colors.indigo : Colors.black38,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.normal,
                          color: selected ? Colors.black87 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('👥 참가자 현황 공개'),
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            '현재 참가자의 남녀 성비를 게스트에게 보여줄까요?',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
        ),
        option(value: true, title: '공개', desc: '현재 참가 인원과 남/여 참가 현황을 표시'),
        option(
          value: false,
          title: '성비 숨기기',
          desc: '현재 총 참가 인원은 그대로 표시하고 남/여 인원만 숨김',
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF3FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            '성비를 숨겨도 현재 참가 인원과 모집 정원은 게스트에게 표시됩니다.',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.indigo,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  /// 파티 전체 최소 모집 인원 + 미달 시 처리.
  ///
  /// **파티(정기 파티는 회차) 하나에 대한 값이다.** 성별 모드와도, 차수와도
  /// 무관하다 — 차수마다 따로 정하는 '차수 최소 인원'은 차수 카드에 있고,
  /// 그 값들은 이 값에 합산되지 않는다([PartyMinCapacity]).
  Widget _minCapacitySection() {
    final error = _minError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('최소 모집 인원 (선택)'),
        TextField(
          controller: _minCapacityController,
          keyboardType: TextInputType.number,
          decoration: _inputDecoration('예: 6 (비우면 제한 없음)'),
          onChanged: (_) => setState(() {}),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              error,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFE53935),
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.isRecurring
                  ? '회차 하나마다 적용되는 인원이에요(8/22 회차에 6명, 8/24 회차에 6명). '
                        '차수별 최소 인원과는 별개이고, 차수 값을 더해서 정해지지 않아요.\n'
                        '최소 인원을 채우면 참가자에게 "파티 확정" 배지가 보여요.'
                  : '파티 하나 전체에 적용되는 인원이에요. 차수별 최소 인원과는 별개이고, '
                        '차수 값을 더해서 정해지지 않아요.\n'
                        '최소 인원을 채우면 참가자에게 "파티 확정" 배지가 보여요.',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black45,
                height: 1.4,
              ),
            ),
          ),
        if (_minCapacity > 0) ...[
          const SizedBox(height: 16),
          _label('최소 인원 미달 시'),
          for (final policy in PartyMinCapacityPolicy.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => setState(() => _minPolicy = policy),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _minPolicy == policy
                        ? const Color(0xFFEFF3FF)
                        : const Color(0xFFF7F7FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _minPolicy == policy
                          ? Colors.indigo.shade300
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _minPolicy == policy
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                        color: _minPolicy == policy
                            ? Colors.indigo
                            : Colors.black38,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              policy.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: _minPolicy == policy
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                                color: _minPolicy == policy
                                    ? Colors.black87
                                    : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              // 정기 파티는 취소 단위가 **미달된 그 회차
                              // 하나**다 — 다른 날짜 회차는 그대로 열린다.
                              widget.isRecurring
                                  ? policy.recurringDescription
                                  : policy.description,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black45,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
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
                '성별 및 모집 인원',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 18),
              if (widget.allowGenderLimitChange) ...[
                _label('성별 / 인원 제한'),
                _genderCapacitySelector(),
                const SizedBox(height: 16),
              ],
              if (!widget.showCapacityFields)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF3FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '라운드 진행 파티는 모집 인원을 차수마다 정합니다 — '
                    '인원 숫자는 위 "라운드 진행" 설정에서 입력해주세요.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.indigo,
                      height: 1.45,
                    ),
                  ),
                )
              else if (_genderCapacityMode == 'unlimited') ...[
                _label('전체 최대 모집 인원'),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF3FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '총 모집 인원: ${(int.tryParse(_maleCapacityController.text) ?? 0) + (int.tryParse(_femaleCapacityController.text) ?? 0)}명 (자동 계산)',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.indigo,
                      ),
                    ),
                  ),
                ],
              ],
              // 최소 모집 인원은 **항상** 여기 있다. 차수별 정원 파티라
              // 최대 인원 칸이 숨겨져 있어도 마찬가지다 — 파티 전체에 하나뿐인
              // 값이라 차수 설정이 대신할 수 없다.
              const SizedBox(height: 20),
              _minCapacitySection(),
              // 참가자 현황 공개 — 인원을 정하는 자리 바로 다음에 둔다.
              // "몇 명을 모으나" 다음에 "그 현황을 어디까지 보여주나"가 오는
              // 순서라, 호스트가 인원 설정을 마친 흐름에서 자연스럽게 읽힌다.
              const SizedBox(height: 20),
              _genderRatioVisibilitySection(),
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
