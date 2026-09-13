import 'package:flutter/material.dart';

import 'package:party_app/models/host_offering.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/screens/place_party_link_screen.dart'
    show MySpaceTile;
import 'package:party_app/services/party_create_eligibility.dart';
import 'package:party_app/services/place_event_entry.dart';
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/host_offering_choice.dart';
import 'package:party_app/widgets/web_frame.dart';

// ══════════════════════════════════════════════════════════════════════════
// 파티 등록 진입 — "기존 공간과 연결되는 파티인가?"를 먼저 묻는다
//
// 매장·파티룸을 이미 올려둔 호스트는 새 파티의 열에 아홉이 그 공간에서 열린다.
// 그런데 지금까지 등록 진입은 곧장 빈 폼이라, 주소를 손으로 다시 치고 나서
// 폼 중간의 "플레이스 연결" 줄을 우연히 발견해야만 연결이 됐다. 그래서 같은
// 매장의 파티가 연결된 것과 안 된 것으로 갈려 쌓였다.
//
// ── 새로 만들지 않은 것 ───────────────────────────────────────────────────
// 연결 스키마도, 연결 절차도 하나도 새로 만들지 않았다. 이 화면이 하는 일은
// **이미 있는 [PartyPrelinkTarget]을 고르는 것뿐**이고, 그 값은 등록 폼의
// 연결 항목 초기 선택([PartyRegisterScreen.withSpace])으로 들어간다. 실제
// 쓰기는 예전과 똑같이 파티 문서가 만들어진 뒤 [PlacePartyLink.linkParties]가
// `linkedEventId`(events) / `linkedPlaceId`(places)에 한다.
//
// ── 노출 조건 ─────────────────────────────────────────────────────────────
// 내 소유의 events/places가 **하나라도** 있을 때만 이 화면이 낀다. 하나도
// 없으면 [openPartyRegisterEntry]가 곧장 등록 폼을 연다 — 공간을 안 가진
// 호스트에게는 진입 경로가 조금도 달라지지 않는다.
// ══════════════════════════════════════════════════════════════════════════

const Color _kAccent = Color(0xFFFF6FA0);

/// **새 파티 등록 진입의 단일 창구.**
///
/// 자격을 먼저 확인하고([PartyCreateEligibility.ensure] — 개인 호스트는 여기서
/// 안내만 받고 되돌아간다), 통과하면 내 공간을 읽어 (1) 하나도 없으면
/// 지금까지와 똑같이 등록 폼으로, (2) 하나라도 있으면
/// [PartyRegisterEntryChoiceScreen]으로 보낸다.
///
/// 임시저장 이어쓰기(`autoRestoreDraft`), 재등록, 플레이스 연결 화면의 "새 파티
/// 만들기"는 이 함수를 타지 않는다 — 셋 다 "무엇을 만들지"가 이미 정해진
/// 진입이라 공간을 물어볼 것이 없다. 대신 **자격 확인은 그쪽도 똑같이 한다**
/// (각 호출부가 [PartyCreateEligibility.ensure]를 먼저 부른다) — 관문을 이
/// 함수에만 두면 그 셋이 그대로 우회로가 된다.
Future<void> openPartyRegisterEntry(BuildContext context) async {
  if (!await PartyCreateEligibility.ensure(context)) return;
  if (!context.mounted) return;
  final spaces = await PlacePartyLink.loadMySpaces(hostId: UserSession.userId);
  if (!context.mounted) return;
  await Navigator.push(
    context,
    webFramedRoute((_) => partyRegisterEntryScreen(spaces)),
  );
}

/// **노출 조건의 정본** — 내 공간이 하나라도 있으면 선택 화면, 하나도 없으면
/// 지금까지와 똑같은 등록 폼.
///
/// [openPartyRegisterEntry]에서 떼어 둔 이유는 이 한 줄이 "기존 사용자의
/// 동작이 하나도 안 바뀐다"는 약속 그 자체이기 때문이다 — 조회 없이 그대로
/// 검증할 수 있어야 한다.
Widget partyRegisterEntryScreen(List<PartyPrelinkTarget> spaces) =>
    spaces.isEmpty
    ? const PartyRegisterScreen()
    : PartyRegisterEntryChoiceScreen(spaces: spaces);

/// 파티 등록 진입 선택 — "내 플레이스에서 여는 파티" vs "독립적인 파티".
///
/// [spaces]를 주입받는다(직접 조회하지 않는다) — 노출 여부를 정하려면 어차피
/// 호출부가 먼저 읽어야 하고, 같은 목록을 두 번 읽을 이유가 없다.
class PartyRegisterEntryChoiceScreen extends StatefulWidget {
  /// 내가 소유한 연결 가능한 공간 — 비어 있지 않은 목록만 들어온다.
  final List<PartyPrelinkTarget> spaces;

  const PartyRegisterEntryChoiceScreen({super.key, required this.spaces});

  @override
  State<PartyRegisterEntryChoiceScreen> createState() =>
      _PartyRegisterEntryChoiceScreenState();
}

class _PartyRegisterEntryChoiceScreenState
    extends State<PartyRegisterEntryChoiceScreen> {
  /// 공간 목록을 펼친 단계인지. 공간이 하나뿐이어도 자동으로 넘기지 않는다 —
  /// 어디에 붙는지 한 번은 눈으로 보고 고르는 편이, 나중에 "왜 이 매장에
  /// 붙었지"를 되짚는 것보다 싸다.
  bool _pickingSpace = false;

  void _openForm(Widget screen) {
    // pushReplacement — 뒤로가기가 이 선택 화면이 아니라 등록 유형 화면으로
    // 가야 한다. 고르고 나면 되돌아올 이유가 없는 갈림길이다.
    Navigator.pushReplacement(context, webFramedRoute((_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text(
          '파티 등록',
          style: TextStyle(
            fontFamily: 'SeoulHangang',
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        // 공간 목록 단계에서는 뒤로가기가 선택지 화면으로 돌아온다.
        leading: _pickingSpace
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _pickingSpace = false),
              )
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: _pickingSpace ? _buildSpaceList() : _buildChoices(),
      ),
    );
  }

  Widget _buildChoices() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '어떤 파티인가요?',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          '등록해둔 공간이 있어서 먼저 여쭤봐요',
          style: TextStyle(fontSize: 14, color: Colors.black45),
        ),
        const SizedBox(height: 20),
        _ChoiceCard(
          emoji: '🏪',
          title: '내 플레이스에서 여는 파티',
          description: '등록한 플레이스 또는 대여 공간과 연결해서 파티를 등록해요.',
          footnote: '등록한 공간 ${widget.spaces.length}개',
          onTap: () => setState(() => _pickingSpace = true),
        ),
        const SizedBox(height: 14),
        // '새 파티 만들기'는 **연결 없는 등록**이다 — 여기서 여는 폼은
        // 지금까지의 독립 파티 등록 그대로이고, `linkedEventId`/`linkedPlaceId`
        // 를 자동으로 넣지 않는다(그 필드는 [PartyRegisterScreen.withSpace]로
        // 들어온 공간이 있을 때만 [PlacePartyLink.linkParties]가 쓴다).
        _ChoiceCard(
          emoji: '🎉',
          title: '새 파티 만들기',
          description: '내 플레이스와 연결하지 않고 새로운 파티를 등록해요.',
          onTap: () => _openForm(const PartyRegisterScreen()),
        ),
        const SizedBox(height: 16),
        // 🎪 여기가 아닌 사람에게 주는 길 — 이 화면은 **공간을 가진 호스트**
        // 에게만 뜨므로(위 [openPartyRegisterEntry] 주석), 여기 온 사람은
        // 매장 이벤트를 만들 수 있는 사람이기도 하다. 파티는 참가자를
        // 모집하는 글이라, 그럴 생각이 없다면 매장 이벤트가 맞다.
        //
        // 저장 구조는 서로 남남이다(신청·승인·참가비는 parties에만 있다) —
        // 그래서 "옮겨 담기"가 아니라 **다른 등록으로 보내는 것**이다.
        HostOfferingCrossLink(
          to: HostOffering.placeEvent,
          onTap: () => PlaceEventEntry.startRegister(context),
        ),
      ],
    );
  }

  Widget _buildSpaceList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '어느 공간에서 여나요?',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          '고른 공간의 주소·좌표를 파티에 그대로 가져와요',
          style: TextStyle(fontSize: 14, color: Colors.black45),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final space in widget.spaces)
                MySpaceTile(
                  space: space,
                  onTap: () =>
                      _openForm(PartyRegisterScreen.withSpace(space: space)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // 여기까지 와서 마음이 바뀔 수도 있다 — 뒤로 두 번 누르게 하지 않는다.
        TextButton(
          onPressed: () => _openForm(const PartyRegisterScreen()),
          style: TextButton.styleFrom(foregroundColor: Colors.black54),
          child: const Text('연결하지 않고 등록할래요'),
        ),
      ],
    );
  }
}

/// 선택지 카드 — 등록 유형 화면(_TypeCard)과 같은 결의 카드를 이 화면 안에서만
/// 쓴다. 그쪽 카드는 로딩·도움말 버튼까지 달고 있어 여기 필요한 것보다 무겁다.
class _ChoiceCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String description;

  /// 없으면 그 줄과 위 여백을 통째로 빼서 카드가 내용만큼만 높아진다.
  final String? footnote;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.emoji,
    required this.title,
    required this.description,
    this.footnote,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: Colors.black54,
                      ),
                    ),
                    if (footnote != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        footnote!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _kAccent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }
}
