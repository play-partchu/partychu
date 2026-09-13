// ─────────────────────────────────────────────────────────────────────────────
// 🎉 "이벤트 / 파티" 등록 — **무엇을 만들지 고르는 한 칸**.
//
// ── 왜 카드를 하나로 줄였나 ──────────────────────────────────────────────────
// 등록 메인에는 🎪 매장 이벤트와 🎉 파티가 큰 카드 두 장으로 나란히 있었다.
// 둘은 "행사를 올린다"는 같은 일이고 갈리는 지점은 **참가 신청을 받는가** 하나
// 뿐인데, 카드 두 장이 나란히 있으면 그 하나뿐인 기준이 다른 등록 유형
// (플레이스·파티샵·파티크루)과 같은 무게로 읽힌다. 그래서 메인에는
// '🎉 이벤트 / 파티' 한 칸만 두고, 고르는 일은 이 화면으로 미룬다.
//
// ── 합친 것은 진입뿐이다 ─────────────────────────────────────────────────────
// `placePromotions`(매장 이벤트)와 `parties`(파티)는 그대로 둘이다. 고른 뒤
// 가는 곳도 예전 그대로다 — 이 화면은 기존 두 진입 함수를 부르기만 한다.
//
//   🎪 매장 이벤트 → [PlaceEventEntry.startRegister]
//   🎉 파티        → [openPartyRegisterEntry] (등록 개수 관문을 먼저 지난다)
//
// ── 시트가 아니라 화면인 이유 ────────────────────────────────────────────────
// 등록 폼에서 뒤로 나오면 **여기로 돌아와야** 한다("아, 이쪽이 아니었네"를
// 만난 사람이 등록 메인부터 다시 시작하지 않게). 바텀시트는 등록 폼을 열기
// 전에 닫히므로 그 자리가 남지 않는다. 등록을 마치면 파티 등록 화면이
// 뿌리까지 스택을 걷어내므로([PartyRegisterScreen] 저장 성공 경로), 이 화면이
// 끼어도 완료 후 되돌아오는 자리는 예전과 같다.
//
// ── 문구는 여기서 짓지 않는다 ────────────────────────────────────────────────
// 카드도 판단 기준 한 줄도 [HostOfferingChoice]가 그린다 — 플레이스 등록 직후의
// 후속 시트([PlaceFollowupEntry])와 **같은 위젯**이라, 두 자리에서 같은 질문이
// 다르게 설명될 수 없다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:party_app/models/host_offering.dart';
import 'package:party_app/screens/party_register_entry_choice_screen.dart';
import 'package:party_app/services/place_event_entry.dart';
import 'package:party_app/widgets/host_offering_choice.dart';

class RegisterOfferingChoiceScreen extends StatefulWidget {
  const RegisterOfferingChoiceScreen({
    super.key,
    this.onPlaceEventHelp,
    this.onPartyHelp,
  });

  /// 🎪 매장 이벤트 카드 제목 옆 '?' — 등록 메인이 자기 도움말 시트를
  /// 그대로 넘겨준다. 주지 않으면 '?'가 생기지 않는다.
  final void Function(BuildContext context)? onPlaceEventHelp;

  /// 🎉 파티 카드 제목 옆 '?' — 위와 **같은 시트 컴포넌트**를 쓰고 문구만
  /// 다르다.
  ///
  /// 파티에 도움말이 필요한 이유는 이름 때문이다. "파티"를 친목 모임으로만
  /// 읽으면 공연·티켓 행사를 여는 호스트가 이 카드를 자기 것이 아니라고
  /// 지나친다.
  final void Function(BuildContext context)? onPartyHelp;

  @override
  State<RegisterOfferingChoiceScreen> createState() =>
      _RegisterOfferingChoiceScreenState();
}

class _RegisterOfferingChoiceScreenState
    extends State<RegisterOfferingChoiceScreen> {
  bool _isCheckingParty = false;
  bool _isCheckingEvent = false;

  /// 🎪 매장 이벤트 — 내 플레이스를 확인하는 동안만 카드가 "확인 중..."이 된다.
  ///
  /// 확인 → (없으면) 안내 → (여러 개면) 선택 → 폼까지의 흐름은 전부
  /// [PlaceEventEntry.startRegister] 안에 있다. 마이 > 파티츄 호스트도 같은
  /// 함수를 부르므로 두 입구가 갈라질 수 없다.
  Future<void> _goToEventRegister() async {
    if (_isCheckingEvent) return;
    setState(() => _isCheckingEvent = true);
    try {
      await PlaceEventEntry.startRegister(context);
    } finally {
      if (mounted) setState(() => _isCheckingEvent = false);
    }
  }

  // 파티 등록 가능 여부 확인 후 화면 이동
  // Source.server 를 사용해 로컬 캐시를 우회하고 최신 데이터로 판단
  Future<void> _checkAndGoToPartyRegister() async {
    if (_isCheckingParty) return;
    setState(() => _isCheckingParty = true);

    try {
      // 개수 관문은 여기 없다 — [PartyCreateEligibility.ensure]가 사업자 자격과
      // 함께 본다([RegistrationLimits]). 예전에는 이 화면만 개수를 셌고, 그것도
      // **날짜 문서 단위**라 날짜를 여러 개 고른 파티 두 개만으로 한도에 걸렸다
      // (저장 직전 검사는 게시글 단위라 통과했다 — 두 기준이 어긋나 있었다).
      // 파티 등록 폼을 여는 일곱 갈래가 전부 그 관문을 지나므로 여기서 따로
      // 셀 이유가 없다.
      if (!mounted) return;
      // 내 플레이스/공간대여가 있으면 "그 공간에서 여는 파티인지"를 먼저
      // 묻고, 없으면 지금까지와 똑같이 곧장 등록 폼을 연다.
      await openPartyRegisterEntry(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류가 발생했습니다: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingParty = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventHelp = widget.onPlaceEventHelp;
    final partyHelp = widget.onPartyHelp;
    // 준 것만 '?'가 생긴다 — 둘 다 없으면 예전처럼 물음표 없는 카드다.
    final helpMap = <HostOffering, VoidCallback>{
      if (eventHelp != null) HostOffering.placeEvent: () => eventHelp(context),
      if (partyHelp != null) HostOffering.party: () => partyHelp(context),
    };
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text(
          '이벤트 / 파티 등록',
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: HostOfferingChoice(
          // 제목은 앱바가 이미 달고 있다 — 화면 위쪽에 남기는 글은 판단 기준
          // 한 줄뿐이고, 그것은 이 위젯이 그린다.
          showTitle: false,
          loading: _isCheckingParty
              ? HostOffering.party
              : _isCheckingEvent
              ? HostOffering.placeEvent
              : null,
          // 두 카드 모두 제목 옆 '?'를 단다 — 같은 컴포넌트, 다른 문구다.
          onHelp: helpMap.isEmpty ? null : helpMap,
          onSelect: (kind) => switch (kind) {
            HostOffering.placeEvent => _goToEventRegister(),
            HostOffering.party => _checkAndGoToPartyRegister(),
          },
        ),
      ),
    );
  }
}
