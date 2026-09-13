import 'package:flutter/material.dart';

import 'package:party_app/models/party_capacity_status.dart';

const _kAccent = Color(0xFFFF6FA0);
const _kConfirmed = Color(0xFF047857);

/// "🎉 파티 확정" / "최소 모집 달성" 배지.
///
/// 최소 인원을 채우는 순간 붙는다 — 참가자에게 "이 파티는 취소될 걱정이
/// 없다"는 신호다. 다만 목록 카드에서는 최소 달성 여부 자체를 감추기로 해서
/// 상세 화면(과 호스트용 신청자 화면)에서만 노출한다.
class PartyConfirmedBadge extends StatelessWidget {
  final PartyCapacityStatus status;

  /// 카드처럼 좁은 곳은 작게. 상세는 기본 크기.
  final bool compact;

  /// 자동 취소 파티인지 — 확정의 의미가 더 크므로 문구를 달리한다.
  final bool autoCancelPolicy;

  const PartyConfirmedBadge({
    super.key,
    required this.status,
    this.compact = false,
    this.autoCancelPolicy = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!status.minReached) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kConfirmed.withValues(alpha: 0.35)),
      ),
      child: Text(
        autoCancelPolicy ? '🎉 파티 확정' : '🎉 최소 모집 달성',
        style: TextStyle(
          fontSize: compact ? 10.5 : 12,
          fontWeight: FontWeight.w700,
          color: _kConfirmed,
        ),
      ),
    );
  }
}

/// 모집 현황 한 덩어리 — '모집 현황: 8 / 20명', '최소 모집: 10명', 진행 막대,
/// 확정 배지를 함께 그린다. 상세 화면용(카드는 [PartyCapacityLine]).
class PartyCapacityMeter extends StatelessWidget {
  final PartyCapacityStatus status;

  /// 최소 미달 시 자동 취소로 설정된 파티인지 — 안내 문구가 달라진다.
  final bool autoCancelPolicy;

  /// 현재 모집된 인원을 드러낼지. **비로그인 사용자에게는 false**를 넘긴다.
  ///
  /// 참가비·모집 상태와 같은 규칙이다 — 로그인 전에는 얼마나 모였는지가
  /// 보이지 않는다. 숫자·진행 막대·확정 배지·'N명 더 모이면 확정'을 **한꺼번에**
  /// 끄는 이유는, 넷 중 하나만 남아도 거기서 현재 인원이나 잔여 자리를 그대로
  /// 역산할 수 있기 때문이다(막대 길이도 current/max 그 자체다).
  ///
  /// 정원·최소 모집 인원처럼 호스트가 정해 둔 **설정값**은 그대로 남긴다 —
  /// 지금 몇 명이 왔는지를 알려주지 않는다.
  final bool revealCounts;

  const PartyCapacityMeter({
    super.key,
    required this.status,
    this.autoCancelPolicy = false,
    this.revealCounts = true,
  });

  @override
  Widget build(BuildContext context) {
    final progress = revealCounts ? status.progress : null;
    final marker = status.minMarker;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              revealCounts
                  ? '모집 현황: ${status.countLabel}'
                  // 감췄다는 사실 자체는 숨기지 않는다. 이 문구는 마감·정원
                  // 여부와 무관하게 로그인 전이면 **항상** 같아서, 있다는
                  // 것만으로는 아무것도 알려주지 않는다.
                  : '모집 현황: 🔒 로그인 후 확인',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            if (revealCounts) ...[
              const SizedBox(width: 8),
              PartyConfirmedBadge(
                status: status,
                autoCancelPolicy: autoCancelPolicy,
              ),
            ],
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: 8),
          // 막대 위에 최소 인원선을 눈금으로 얹어 "얼마나 더 오면 확정인지"를
          // 숫자를 읽지 않고도 알 수 있게 한다.
          LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F1F5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      decoration: BoxDecoration(
                        color: status.minReached ? _kConfirmed : _kAccent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  if (marker != null && marker < 1)
                    Positioned(
                      left: (constraints.maxWidth * marker).clamp(
                        0.0,
                        constraints.maxWidth - 2,
                      ),
                      child: Container(
                        width: 2,
                        height: 8,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (status.minLabel != null) ...[
          const SizedBox(height: 6),
          Text(
            // 로그인 전에는 최소 인원 **숫자만** 남긴다 — 호스트가 정해 둔
            // 설정값이라 현재 인원을 알려주지 않는다. 반대로 '달성'/'N명 더
            // 모이면 확정'은 둘 다 지금 몇 명인지를 그대로 말해준다(글자
            // 색까지 달성 여부를 드러낸다).
            !revealCounts
                ? status.minLabel!
                : status.minReached
                ? '${status.minLabel} · 달성'
                : '${status.minLabel} · ${status.remainingToMin}명 더 모이면 확정',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: revealCounts && status.minReached
                  ? _kConfirmed
                  : Colors.black45,
            ),
          ),
          // 자동 취소 안내는 파티의 **규정**이라 로그인 전에도 그대로 알린다.
          // 다만 로그인 전에는 최소 달성 여부로 껐다 켰다 하지 않는다 — 문구가
          // 사라지는 것만으로 "최소 인원을 이미 채웠다"가 드러나기 때문이다.
          if (autoCancelPolicy && (!revealCounts || !status.minReached))
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '모집 마감까지 최소 인원을 못 채우면 파티가 자동 취소되고 전액 환불돼요.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Color(0xFFB45309),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// 목록 카드용 한 줄 — '8 / 20명'.
///
/// 최소 모집 관련 정보는 목록에서 일부러 전부 감춘다(로그인 여부와 무관).
/// 최소 인원 숫자뿐 아니라 최소 달성 여부를 드러내는 확정 배지도 붙이지
/// 않는다 — 카드만 보고는 달성 여부를 알 수 없어야 한다. 최소 인원·확정
/// 배지·잔여 인원은 상세 화면의 [PartyCapacityMeter]에서만 풀어준다.
class PartyCapacityLine extends StatelessWidget {
  final PartyCapacityStatus status;
  final TextStyle? textStyle;

  const PartyCapacityLine({super.key, required this.status, this.textStyle});

  @override
  Widget build(BuildContext context) {
    return Text(
      status.countLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textStyle ?? const TextStyle(fontSize: 12, color: Colors.black54),
    );
  }
}
