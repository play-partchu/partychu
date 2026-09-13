import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/models/party_round_package.dart';
import 'package:party_app/utils/format_utils.dart';

/// "차수 패키지 판매" 입력 — 등록/수정 화면 세 곳(일반 파티 등록,
/// 플레이스+파티 등록, 파티 수정)이 **이 위젯 하나**를 쓴다.
///
/// 차수가 2개 이상이고 **차수별 정원·참가비 모드**일 때만 의미가 있다. 통합
/// 정원 모드는 차수별 카운터가 없어 "포함 차수마다 정원 1명씩"을 지킬 수 없고,
/// 서버(`partyCapacity.js`)도 같은 이유로 패키지 신청을 거부한다 — 그래서
/// 호출부가 그 조건에서만 이 위젯을 그린다.
///
/// 1+2차를 하드코딩하지 않는다. 포함 차수는 [PartyRoundPackage.roundNumbers]
/// 배열이라 2+3차·1+2+3차도 그대로 만들 수 있다.
class RoundPackageEditor extends StatelessWidget {
  /// 지금 화면에 있는 차수들 — (차수번호, 표시이름, 남/여 참가비).
  final List<RoundPackageRoundInfo> rounds;

  final List<PartyRoundPackage> packages;

  /// 남녀 참가비를 따로 받는 모드인지 — 입력칸이 1개/2개로 갈린다.
  final bool separateGenderFee;

  /// 패키지별 검증 문구(패키지 id → 문구). 카드 아래에 붉게 표시한다.
  final Map<String, String> errors;

  final ValueChanged<List<PartyRoundPackage>> onChanged;

  const RoundPackageEditor({
    super.key,
    required this.rounds,
    required this.packages,
    required this.separateGenderFee,
    required this.onChanged,
    this.errors = const {},
  });

  static const _accent = Color(0xFFFF6FA0);
  static const _boxFill = Color(0xFFF7F7FA);

  bool get _enabled => packages.isNotEmpty;

  void _toggle(bool on) {
    if (!on) {
      onChanged(const []);
      return;
    }
    // 처음 켜면 "모든 차수를 묶은" 패키지 하나를 기본으로 만들어 준다 —
    // 가장 흔한 구성이고, 포함 차수는 바로 아래에서 고칠 수 있다.
    final numbers = rounds.map((r) => r.roundNumber).toList()..sort();
    onChanged([
      PartyRoundPackage(
        id: PartyRoundPackage.newId(),
        roundNumbers: numbers,
        roundIds: [
          for (final r in rounds)
            if (numbers.contains(r.roundNumber)) r.roundId,
        ],
      ),
    ]);
  }

  void _replace(int index, PartyRoundPackage next) {
    final list = [...packages];
    list[index] = next;
    onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '차수 패키지 판매',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '여러 차수를 묶어 별도 가격으로 팔 수 있어요. '
                    '패키지 신청자는 포함된 차수의 정원을 각각 1명씩 차지합니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _enabled,
              onChanged: rounds.length < 2 ? null : _toggle,
              activeThumbColor: _accent,
            ),
          ],
        ),
        if (rounds.length < 2)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '차수를 2개 이상 추가하면 패키지를 만들 수 있어요.',
              style: TextStyle(fontSize: 12, color: Colors.black38),
            ),
          ),
        if (_enabled) ...[
          for (var i = 0; i < packages.length; i++)
            _PackageCard(
              key: ValueKey(packages[i].id),
              package: packages[i],
              rounds: rounds,
              separateGenderFee: separateGenderFee,
              error: errors[packages[i].id],
              onChanged: (next) => _replace(i, next),
              onRemove: packages.length == 1
                  ? null
                  : () => onChanged([...packages]..removeAt(i)),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                final numbers = rounds.map((r) => r.roundNumber).toList()
                  ..sort();
                onChanged([
                  ...packages,
                  PartyRoundPackage(
                    id: PartyRoundPackage.newId(),
                    roundNumbers: numbers,
                    roundIds: [for (final r in rounds) r.roundId],
                  ),
                ]);
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('패키지 추가'),
              style: TextButton.styleFrom(
                foregroundColor: _accent,
                backgroundColor: const Color(0xFFFFF0F5),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 패키지 편집기가 차수에서 필요로 하는 값만 담은 뷰 모델 — 화면마다 차수를
/// 들고 있는 방식이 달라(등록은 PartyRoundDraft, 수정은 문서 맵) 여기서 형태를
/// 하나로 맞춘다.
@immutable
class RoundPackageRoundInfo {
  final int roundNumber;
  final String roundId;
  final String label;
  final int maleFee;
  final int femaleFee;

  const RoundPackageRoundInfo({
    required this.roundNumber,
    required this.roundId,
    required this.label,
    required this.maleFee,
    required this.femaleFee,
  });
}

class _PackageCard extends StatefulWidget {
  final PartyRoundPackage package;
  final List<RoundPackageRoundInfo> rounds;
  final bool separateGenderFee;
  final String? error;
  final ValueChanged<PartyRoundPackage> onChanged;
  final VoidCallback? onRemove;

  const _PackageCard({
    super.key,
    required this.package,
    required this.rounds,
    required this.separateGenderFee,
    required this.onChanged,
    this.error,
    this.onRemove,
  });

  @override
  State<_PackageCard> createState() => _PackageCardState();
}

class _PackageCardState extends State<_PackageCard> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.package.name,
  );
  late final TextEditingController _maleCtrl = TextEditingController(
    text: widget.package.maleFee == 0 ? '' : '${widget.package.maleFee}',
  );
  late final TextEditingController _femaleCtrl = TextEditingController(
    text: widget.package.femaleFee == 0 ? '' : '${widget.package.femaleFee}',
  );
  late final TextEditingController _ebMaleCtrl = TextEditingController(
    text: widget.package.earlyBirdMaleFee == 0
        ? ''
        : '${widget.package.earlyBirdMaleFee}',
  );
  late final TextEditingController _ebFemaleCtrl = TextEditingController(
    text: widget.package.earlyBirdFemaleFee == 0
        ? ''
        : '${widget.package.earlyBirdFemaleFee}',
  );

  @override
  void dispose() {
    _nameCtrl.dispose();
    _maleCtrl.dispose();
    _femaleCtrl.dispose();
    _ebMaleCtrl.dispose();
    _ebFemaleCtrl.dispose();
    super.dispose();
  }

  PartyRoundPackage get _pkg => widget.package;

  int _parse(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  /// 남녀 같은 금액 모드에서는 남자 칸 하나만 쓰고 여자 금액도 같은 값으로
  /// 저장한다 — 읽는 쪽(서버·상세)이 성별 분기를 그대로 쓸 수 있게 한다.
  void _commitFees() {
    final male = _parse(_maleCtrl);
    final female = widget.separateGenderFee ? _parse(_femaleCtrl) : male;
    final ebMale = _parse(_ebMaleCtrl);
    final ebFemale = widget.separateGenderFee ? _parse(_ebFemaleCtrl) : ebMale;
    widget.onChanged(
      _pkg.copyWith(
        name: _nameCtrl.text,
        maleFee: male,
        femaleFee: female,
        earlyBirdMaleFee: ebMale,
        earlyBirdFemaleFee: ebFemale,
      ),
    );
  }

  /// 포함 차수를 개별로 신청했을 때의 합계 — 할인액을 보여주기 위한 참고값이다
  /// (저장은 하지 않는다. 패키지 가격은 별도 판매가다).
  ///
  /// 남녀 금액이 다른 모드에서는 남자 금액 기준으로만 비교한다 — 아래 할인액
  /// 안내가 패키지 남자 금액과 짝을 이뤄야 숫자가 서로 맞는다.
  int get _individualTotal {
    final numbers = _pkg.normalizedRoundNumbers;
    return widget.rounds
        .where((r) => numbers.contains(r.roundNumber))
        .fold<int>(0, (total, r) => total + r.maleFee);
  }

  @override
  Widget build(BuildContext context) {
    final numbers = _pkg.normalizedRoundNumbers;
    final individual = _individualTotal;
    final discount = individual - _pkg.maleFee;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.error != null
              ? const Color(0xFFE53935)
              : const Color(0xFFE8EBF2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  onChanged: (_) => _commitFees(),
                  decoration: _deco(
                    '패키지명',
                    hint: PartyRoundPackage.defaultNameFor(numbers),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (widget.onRemove != null)
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.black38,
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '포함 차수 (2개 이상)',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in widget.rounds)
                _roundChip(
                  r,
                  selected: numbers.contains(r.roundNumber),
                  onTap: () {
                    final next = [...numbers];
                    if (!next.remove(r.roundNumber)) next.add(r.roundNumber);
                    next.sort();
                    widget.onChanged(
                      _pkg.copyWith(
                        roundNumbers: next,
                        roundIds: [
                          for (final x in widget.rounds)
                            if (next.contains(x.roundNumber)) x.roundId,
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          _feeRow(
            label: '패키지 참가비',
            maleCtrl: _maleCtrl,
            femaleCtrl: _femaleCtrl,
          ),
          const SizedBox(height: 6),
          // 개별 합계와 할인액은 입력값에서 바로 계산해 보여준다(저장 X).
          Text(
            individual <= 0
                ? '포함 차수의 참가비를 먼저 입력하면 할인액이 계산돼요.'
                : discount > 0
                ? '개별 신청 금액 합계 ${formatPrice(individual)} → '
                      '패키지 할인 ${formatAmount(discount)}'
                : '개별 신청 금액 합계 ${formatPrice(individual)} (할인 없음)',
            style: const TextStyle(fontSize: 11.5, color: Colors.black45),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '패키지 얼리버드',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: _pkg.earlyBirdEnabled,
                onChanged: (v) =>
                    widget.onChanged(_pkg.copyWith(earlyBirdEnabled: v)),
                activeThumbColor: RoundPackageEditor._accent,
              ),
            ],
          ),
          if (_pkg.earlyBirdEnabled) ...[
            const Text(
              '개별 차수 얼리버드를 합산하지 않고, 패키지 얼리버드 금액을 그대로 '
              '판매가로 씁니다. 종료 시각은 포함된 첫 차수 시작 기준입니다.',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.black45,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            _feeRow(
              label: '얼리버드 참가비',
              maleCtrl: _ebMaleCtrl,
              femaleCtrl: _ebFemaleCtrl,
            ),
          ],
          if (widget.error != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.error!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFE53935)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _feeRow({
    required String label,
    required TextEditingController maleCtrl,
    required TextEditingController femaleCtrl,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: maleCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => _commitFees(),
            decoration: _deco(
              widget.separateGenderFee ? '$label (남)' : label,
              hint: '0',
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (widget.separateGenderFee) ...[
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: femaleCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => _commitFees(),
              decoration: _deco('$label (여)', hint: '0'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }

  Widget _roundChip(
    RoundPackageRoundInfo r, {
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF0F5) : RoundPackageEditor._boxFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? RoundPackageEditor._accent
              : const Color(0xFFE8EBF2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected ? Icons.check_box : Icons.check_box_outline_blank,
            size: 16,
            color: selected ? RoundPackageEditor._accent : Colors.black38,
          ),
          const SizedBox(width: 4),
          Text(
            r.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? RoundPackageEditor._accent : Colors.black54,
            ),
          ),
        ],
      ),
    ),
  );

  InputDecoration _deco(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(fontSize: 12, color: Colors.black45),
    hintStyle: const TextStyle(fontSize: 12.5, color: Colors.black26),
    isDense: true,
    filled: true,
    fillColor: RoundPackageEditor._boxFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE8EBF2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(
        color: RoundPackageEditor._accent,
        width: 1.4,
      ),
    ),
  );
}
