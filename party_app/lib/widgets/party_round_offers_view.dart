import 'package:flutter/material.dart';

import 'package:party_app/models/party_round_offer.dart';
import 'package:party_app/utils/format_utils.dart';

/// 차수·패키지 판매 목록을 그리는 공용 위젯 두 개.
///
///  · [PartyRoundOfferSection] — 파티 상세의 "차수 및 참가비"(읽기 전용 정본)
///  · [PartyRoundOfferPicker]  — 신청 시트의 선택 UI + 결제 예정 금액
///
/// 두 위젯이 **같은 [PartyRoundOffer] 목록**을 받아 같은 줄(제목 · 시간 ·
/// 금액)을 그리므로, 상세에서 본 금액과 신청 화면에서 고른 금액이 어긋날 수
/// 없다. 금액 표기는 앱 공통 [formatPrice]("3만원"·"무료")를 쓴다.
const _kAccent = Color(0xFFFF6FA0);
const _kAccentBg = Color(0xFFFFF0F5);

/// 상세 화면 "차수 및 참가비" — 신청 버튼을 누르기 전에 차수별 시간·참가비와
/// 패키지 할인까지 여기서 다 보이게 하는 것이 목적이다.
class PartyRoundOfferSection extends StatelessWidget {
  final List<PartyRoundOffer> offers;

  /// 화면마다 카드 바깥 여백이 달라 호출하는 쪽에서 넘긴다.
  final EdgeInsets margin;

  /// 모집 상태(종료·마감)를 드러낼지. **비로그인 사용자에게는 false**를 넘긴다.
  ///
  /// 참가비와 같은 규칙이다 — 로그인 전에는 끝난 파티도 다른 파티와 똑같이
  /// 보이고, 상태는 로그인한 뒤에 드러난다. 배지·취소선·흐린 글씨를 **한꺼번에**
  /// 끄는 이유는, 셋 중 하나만 남아도 그것이 곧 "이 차수는 끝났다"는 신호가 되기
  /// 때문이다. 대신 상태를 숨겼다는 사실 자체는 안내 문구로 알린다.
  final bool revealStatus;

  const PartyRoundOfferSection({
    super.key,
    required this.offers,
    this.margin = const EdgeInsets.only(top: 16),
    this.revealStatus = true,
  });

  @override
  Widget build(BuildContext context) {
    if (offers.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F0F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🎫', style: TextStyle(fontSize: 16)),
              SizedBox(width: 6),
              Text(
                '차수 및 참가비',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 상태를 감췄다는 사실은 숨기지 않는다 — 문구는 마감 여부와 무관하게
          // 로그인 전이면 **항상** 같아서, 있다는 것만으로는 아무것도 알려주지
          // 않는다.
          if (!revealStatus)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                '🔒 차수별 모집 상태는 로그인 후 확인할 수 있어요.',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ),
          for (final offer in offers)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: _OfferLine(offer: offer, revealStatus: revealStatus),
            ),
        ],
      ),
    );
  }
}

/// 한 판매 단위의 세 줄 — 제목(+배지) / 시간 / 금액(+패키지 할인 안내).
class _OfferLine extends StatelessWidget {
  final PartyRoundOffer offer;

  /// false면 모집 상태를 아예 그리지 않는다([PartyRoundOfferSection.revealStatus]).
  final bool revealStatus;

  const _OfferLine({required this.offer, this.revealStatus = true});

  @override
  Widget build(BuildContext context) {
    // 상태를 감출 때는 배지뿐 아니라 흐린 글씨·취소선까지 함께 사라진다 —
    // 아래 두 값이 그 스위치다.
    final blocked = revealStatus ? offer.blockedReason : null;
    final ended = revealStatus && offer.ended;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              offer.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: blocked == null
                    ? const Color(0xFF2D3748)
                    : Colors.black38,
                // 끝난 차수는 회차명 위에 줄을 긋는다 — 옆의 '종료' 배지보다
                // 먼저 눈에 들어온다. 아래 시간·참가비 줄은 건드리지 않아
                // 레이아웃(줄 수·높이)은 그대로다.
                decoration: ended ? TextDecoration.lineThrough : null,
                decorationColor: ended ? Colors.black38 : null,
                decorationThickness: ended ? 1.5 : null,
              ),
            ),
            if (offer.isPackage) ...[
              const SizedBox(width: 6),
              _miniBadge('패키지', bg: _kAccentBg, fg: _kAccent),
            ],
            if (offer.earlyBirdOn) ...[
              const SizedBox(width: 6),
              _miniBadge(
                '얼리버드',
                bg: const Color(0xFFFFF3E8),
                fg: const Color(0xFFC2410C),
              ),
            ],
            if (blocked != null) ...[
              const SizedBox(width: 6),
              _miniBadge(
                blocked,
                bg: const Color(0xFFF3F4F6),
                fg: Colors.black54,
              ),
            ]
            // 남은 자리 — 정기 파티는 **고른 회차**의 잔여다(차수 정원이
            // 회차별로 독립이라 8/15 1차가 차도 8/22 1차는 그대로 남는다).
            // 못 고르는 판매 단위에는 이미 '정원 마감' 배지가 붙으므로
            // 잔여를 겹쳐 적지 않는다.
            else if (revealStatus && offer.remainingLabel.isNotEmpty) ...[
              const SizedBox(width: 6),
              _miniBadge(
                offer.remainingLabel,
                bg: const Color(0xFFEAF7F1),
                fg: const Color(0xFF2E9E7B),
              ),
            ],
          ],
        ),
        if (offer.timeLabel.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            offer.timeLabel,
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
        ],
        const SizedBox(height: 2),
        // 성별 참가비가 다르면 금액 한 줄 대신 '남 3만원 · 여 2만원'.
        Text(
          offer.hasGenderedFee ? offer.genderedFeeLabel : offer.feeLabel,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _kAccent,
          ),
        ),
        if (offer.isPackage && offer.discount > 0) ...[
          const SizedBox(height: 2),
          Text(
            '개별 신청 시 ${formatPrice(offer.individualTotal!)} '
            '→ ${formatAmount(offer.discount)} 할인',
            style: const TextStyle(fontSize: 11.5, color: Colors.black45),
          ),
        ],
      ],
    );
  }
}

Widget _miniBadge(String label, {required Color bg, required Color fg}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );

/// 신청 시트 — 차수는 여러 개 고를 수 있고, 패키지는 하나만 고른다.
///
/// 패키지를 고르면 차수 선택이 비워진다(그 반대도 같다). 패키지가 포함 차수의
/// 자리를 이미 차지하므로, 같이 고르면 같은 차수를 두 번 신청하는 꼴이 된다 —
/// 서버도 같은 이유로 둘을 동시에 받지 않는다.
class PartyRoundOfferPicker extends StatefulWidget {
  final List<PartyRoundOffer> offers;

  const PartyRoundOfferPicker({super.key, required this.offers});

  @override
  State<PartyRoundOfferPicker> createState() => _PartyRoundOfferPickerState();
}

/// 신청 시트가 돌려주는 선택 결과 — 서버 호출 인자와 1:1로 맞춰 둔다.
@immutable
class PartyRoundSelection {
  /// 고른 차수 번호들(패키지를 골랐으면 그 패키지의 포함 차수).
  final List<int> roundNumbers;

  /// 패키지를 골랐을 때만 값이 있다.
  final String? packageId;

  /// 화면에 보여준 결제 예정 금액 — 확정 금액은 서버가 다시 계산한다.
  /// 차수·패키지에 얼리버드가 걸려 있으면 **이미 할인된** 금액이다
  /// ([PartyRoundOffer.effectiveFee] 합계).
  final int expectedFee;

  /// 할인 **전** 정상가 합계([PartyRoundOffer.fee] 합계). null이면 할인 정보를
  /// 모르는 예전 경로다(화면은 [expectedFee] 하나만 그린다).
  ///
  /// 얼리버드 적용 여부는 차수마다 다를 수 있어(차수별로 따로 켠다) 여기서
  /// 다시 판정하지 않고, 정본이 계산해둔 두 합계를 그대로 들고 다닌다.
  final int? originalFee;

  const PartyRoundSelection({
    required this.roundNumbers,
    required this.expectedFee,
    this.packageId,
    this.originalFee,
  });
}

class _PartyRoundOfferPickerState extends State<PartyRoundOfferPicker> {
  /// 고른 차수들(패키지를 고르면 비운다).
  final Set<int> _rounds = {};

  /// 고른 패키지 key. null이면 차수 선택 모드.
  String? _packageKey;

  List<PartyRoundOffer> get _selected {
    final key = _packageKey;
    if (key != null) {
      return widget.offers.where((o) => o.key == key).toList();
    }
    return widget.offers
        .where((o) => !o.isPackage && _rounds.contains(o.roundNumbers.first))
        .toList();
  }

  int get _expectedFee =>
      _selected.fold<int>(0, (total, o) => total + o.effectiveFee);

  /// 고른 차수·패키지의 **정상가** 합계 — 할인 전 금액.
  int get _originalFee => _selected.fold<int>(0, (total, o) => total + o.fee);

  bool get _hasSelection => _selected.isNotEmpty;

  void _toggle(PartyRoundOffer offer) {
    setState(() {
      if (offer.isPackage) {
        // 패키지는 단일 선택 — 다시 누르면 해제된다.
        _packageKey = _packageKey == offer.key ? null : offer.key;
        _rounds.clear();
        return;
      }
      _packageKey = null;
      final n = offer.roundNumbers.first;
      if (!_rounds.remove(n)) _rounds.add(n);
    });
  }

  bool _isSelected(PartyRoundOffer offer) => offer.isPackage
      ? _packageKey == offer.key
      : _packageKey == null && _rounds.contains(offer.roundNumbers.first);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '차수는 여러 개 고를 수 있어요. 패키지는 하나만 고를 수 있고, '
          '고르면 차수 선택은 해제됩니다.',
          style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.4),
        ),
        const SizedBox(height: 6),
        for (final offer in widget.offers)
          _OfferChoiceTile(
            offer: offer,
            selected: _isSelected(offer),
            onTap: offer.selectable ? () => _toggle(offer) : null,
          ),
        const SizedBox(height: 8),
        // 결제 예정 금액 — 고른 것들의 실제 적용 금액(얼리버드 반영) 합계.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _kAccentBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '결제 예정 금액',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2D3748),
                ),
              ),
              Text(
                _hasSelection ? formatPrice(_expectedFee) : '-',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _kAccent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: !_hasSelection
                    ? null
                    : () {
                        final selected = _selected;
                        final pkg = selected.firstWhere(
                          (o) => o.isPackage,
                          orElse: () => selected.first,
                        );
                        Navigator.pop(
                          context,
                          PartyRoundSelection(
                            roundNumbers:
                                (selected
                                    .expand((o) => o.roundNumbers)
                                    .toSet()
                                    .toList()
                                  ..sort()),
                            packageId: pkg.isPackage ? pkg.packageId : null,
                            expectedFee: _expectedFee,
                            originalFee: _originalFee,
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('신청하기'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 선택 가능한 한 줄 — 체크 표시 + [_OfferLine]과 같은 정보 구성.
class _OfferChoiceTile extends StatelessWidget {
  final PartyRoundOffer offer;
  final bool selected;
  final VoidCallback? onTap;

  const _OfferChoiceTile({
    required this.offer,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _kAccentBg : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _kAccent : const Color(0xFFE8EBF2),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              offer.isPackage
                  ? (selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked)
                  : (selected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank),
              size: 20,
              color: onTap == null
                  ? Colors.black26
                  : (selected ? _kAccent : Colors.black38),
            ),
            const SizedBox(width: 8),
            Expanded(child: _OfferLine(offer: offer)),
          ],
        ),
      ),
    );
  }
}
