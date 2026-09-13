// ─────────────────────────────────────────────────────────────────────────────
// "무엇을 만들까요?" — 🎪 매장 이벤트 / 🎉 파티 **선택 UI 하나**.
//
// ── 왜 위젯 하나인가 ─────────────────────────────────────────────────────────
// 이 질문이 나오는 자리는 둘이다 — 등록 화면([RegisterTypeScreen])과 플레이스를
// 막 등록한 직후의 후속 시트([PlaceFollowupEntry]). 두 곳이 각자 카드를 그리고
// 있으면 문구가 갈라지고, 갈라지는 순간 "이벤트와 파티가 어떻게 다른지"라는
// 가장 중요한 안내가 화면마다 달라진다. 그래서 그리는 것은 여기 하나뿐이고,
// 문구의 정본은 [HostOffering]이다.
//
// ── 고른 뒤는 기존 흐름 그대로 ───────────────────────────────────────────────
// 이 위젯은 **무엇을 고를지만** 묻는다. 고른 뒤 어디로 가는지는 호출부가
// 정하고, 그 끝은 예전과 같은 등록 시스템이다.
//
//   🎪 매장 이벤트 → [PlaceEventEntry.startRegister]  (placePromotions)
//   🎉 파티        → [openPartyRegisterEntry]         (parties)
//
// 두 저장 구조를 합치지 않는다 — 합칠 수 없다. 파티에는 신청·승인·참가비가
// 달려 있고 매장 이벤트에는 없다.
//
// ── 3초 안에 고르게 한다 ─────────────────────────────────────────────────────
// 안내는 두 조각뿐이다. ① 무엇으로 고르는지 한 문장([criterionHeadline]),
// ② 카드 두 장(부제가 곧 판단 기준). 약관처럼 길어지면 아무도 안 읽고 결국
// 아무 카드나 누른다.
//
// 기준은 **누가 여는가**이지 신청을 받는지가 아니다 — 사전 신청을 받는 매장
// 이벤트(생일 이벤트 등)도 있다([HostOffering]).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:party_app/models/host_offering.dart';

const Color _kAccent = Color(0xFFFF6FA0);
const Color _kAccentBg = Color(0xFFFFF0F5);

/// 🎪 / 🎉 선택 블록 — 머리말 + 카드 두 장 + 예시.
class HostOfferingChoice extends StatelessWidget {
  const HostOfferingChoice({
    super.key,
    required this.onSelect,
    this.loading,
    this.onHelp,
    this.dense = false,
    this.showTitle = true,
  });

  /// 카드를 고른 뒤 — 호출부가 기존 등록 흐름으로 분기한다.
  final ValueChanged<HostOffering> onSelect;

  /// 지금 "확인 중"인 카드(내 플레이스 조회·파티 개수 확인처럼 누른 뒤
  /// 잠깐 걸리는 단계). null이면 둘 다 평소 상태다.
  final HostOffering? loading;

  /// 카드 제목 옆 '?' — 준 종류에만 생긴다(매장 이벤트는 "내 플레이스가
  /// 있어야 한다"는 전제가 있어 도움말이 따로 있다).
  final Map<HostOffering, VoidCallback>? onHelp;

  /// 바텀시트처럼 자리가 좁은 곳 — 여백과 글자를 한 단계 줄인다.
  final bool dense;

  /// '무엇을 만들까요?' 제목을 그릴지. 이미 제목이 있는 시트에서는 끈다.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Text(
            HostOffering.choiceTitle,
            style: TextStyle(
              fontSize: dense ? 17 : 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: dense ? 4 : 6),
        ],
        // 판단 기준 한 문장 — 카드보다 **먼저** 읽혀야 한다.
        _criterionLine(),
        SizedBox(height: dense ? 10 : 14),
        _card(HostOffering.placeEvent),
        SizedBox(height: dense ? 8 : 12),
        _card(HostOffering.party),
        // ⚠️ 여기에 "예를 들어 DJ파티라도…" 예시를 다시 붙이지 않는다. 카드
        // 두 장이 이미 부제로 판단 기준을 말하고 있어서(누가 여는가), 같은
        // 말을 예시로 한 번 더 하면 3초 안에 고르라던 화면이 읽을거리가 된다.
      ],
    );
  }

  Widget _criterionLine() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.help_outline_rounded, size: 15, color: _kAccent),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          HostOffering.criterionHeadline,
          style: TextStyle(
            fontSize: dense ? 12.5 : 13,
            height: 1.4,
            fontWeight: FontWeight.w700,
            color: _kAccent,
          ),
        ),
      ),
    ],
  );

  Widget _card(HostOffering kind) {
    final isLoading = loading == kind;
    final help = onHelp?[kind];
    return _OfferingCard(
      kind: kind,
      isLoading: isLoading,
      dense: dense,
      onHelp: help,
      onTap: isLoading ? null : () => onSelect(kind),
    );
  }
}

class _OfferingCard extends StatelessWidget {
  const _OfferingCard({
    required this.kind,
    required this.isLoading,
    required this.dense,
    required this.onTap,
    this.onHelp,
  });

  final HostOffering kind;
  final bool isLoading;
  final bool dense;
  final VoidCallback? onTap;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    final box = dense ? 46.0 : 56.0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(dense ? 13 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8EBF2)),
          ),
          child: Row(
            children: [
              Container(
                width: box,
                height: box,
                decoration: BoxDecoration(
                  color: _kAccentBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: _kAccent,
                          ),
                        )
                      : Text(
                          kind.emoji,
                          style: TextStyle(fontSize: dense ? 22 : 26),
                        ),
                ),
              ),
              SizedBox(width: dense ? 12 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            kind.label,
                            style: TextStyle(
                              fontSize: dense ? 15 : 16.5,
                              fontWeight: FontWeight.bold,
                              color: isLoading ? Colors.black38 : _kAccent,
                            ),
                          ),
                        ),
                        if (onHelp != null)
                          _HelpDot(onPressed: isLoading ? null : onHelp),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // 부제가 곧 **판단 기준**이다 — 무엇을 하는 행사인지가
                    // 아니라 누가 여는지로 적는다([HostOffering.criterion]).
                    Text(
                      isLoading ? '확인 중...' : kind.criterion,
                      style: TextStyle(
                        fontSize: dense ? 12 : 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      kind.registerDescription,
                      style: TextStyle(
                        fontSize: dense ? 11.5 : 12.5,
                        height: 1.35,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: isLoading ? Colors.black26 : _kAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 제목 옆 '?' — 보이는 크기는 작게, 눌리는 크기는 접근성 기준(44)까지.
/// 카드 전체가 눌리는 영역 안이라 여기서 누른 것은 등록으로 넘어가지 않는다.
class _HelpDot extends StatelessWidget {
  const _HelpDot({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 9, 9, 9),
        child: Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: _kAccentBg,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.question_mark_rounded,
            size: 12,
            color: _kAccent,
          ),
        ),
      ),
    );
  }
}

/// 반대쪽으로 건너가는 안내 한 줄 — 등록 폼 안에서 "여긴 아닌 것 같은데"를
/// 만난 사람이 처음부터 다시 시작하지 않게 한다.
///
/// 눈에는 띄되 폼을 가리지 않는 크기다(한 줄 + 링크). 문구는 목적지가 정한다
/// ([HostOffering.crossPrompt]).
class HostOfferingCrossLink extends StatelessWidget {
  const HostOfferingCrossLink({
    super.key,
    required this.to,
    required this.onTap,
    this.padding = EdgeInsets.zero,
  });

  /// 건너갈 곳.
  final HostOffering to;

  final VoidCallback onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Material(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8EBF2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    to.crossPrompt,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Colors.black54,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${to.display} 만들기',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: _kAccent,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 17,
                  color: _kAccent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
