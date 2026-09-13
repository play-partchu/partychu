import 'package:flutter/material.dart';
import 'package:party_app/screens/place_entry_register_screen.dart';
// 🎉 이벤트 / 파티 카드가 여는 선택 화면 — 매장 이벤트/파티 진입과 등록 개수
// 관문은 전부 그쪽이 들고 있다.
import 'package:party_app/screens/register_offering_choice_screen.dart';
import 'package:party_app/screens/crew_register_screen.dart';
import 'package:party_app/screens/party_market_register_screen.dart';
import 'package:party_app/widgets/web_frame.dart';
import 'package:party_app/screens/business_verification_screen.dart';
import 'package:party_app/models/business_verification.dart';
import 'package:party_app/models/combo_place_type.dart';
import 'package:party_app/models/host_offering.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/services/place_create_eligibility.dart';
import 'package:party_app/services/business_verification_service.dart';
import 'package:party_app/utils/user_session.dart';

class RegisterTypeScreen extends StatefulWidget {
  const RegisterTypeScreen({super.key});

  @override
  State<RegisterTypeScreen> createState() => _RegisterTypeScreenState();
}

class _RegisterTypeScreenState extends State<RegisterTypeScreen> {
  // 🎪 매장 이벤트 / 🎉 파티 진입(내 플레이스 확인·파티 등록 개수 관문)은
  // 이 화면에 없다 — '🎉 이벤트 / 파티' 카드가 여는
  // [RegisterOfferingChoiceScreen]이 그대로 들고 갔다. 확인 중 표시가 카드에
  // 뜨는데 그 카드가 거기 있기 때문이다.

  /// 플레이스 등록 — 신규 플레이스는 **사업자 인증을 마친 호스트만** 만들 수
  /// 있다([PlaceCreateEligibility]). 여기를 열어 두면 개인 호스트가 폼을 다
  /// 채우고 저장 단계에서야 막힌다(firestore.rules의 events/places create가
  /// 같은 조건을 다시 본다).
  Future<void> _goToPlaceRegister() async {
    if (!await PlaceCreateEligibility.ensure(context)) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      webFramedRoute((_) => const PlaceEntryRegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text(
          '등록하기',
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
        actions: [
          IconButton(
            onPressed: () => _showRegisterHelpSheet(context),
            icon: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                color: Color(0xFFFFE3EE),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.question_mark_rounded,
                size: 15,
                color: Color(0xFFFF6FA0),
              ),
            ),
            tooltip: '등록 유형 안내',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '어떤 걸 등록할까요?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              '원하는 유형을 선택해주세요',
              style: TextStyle(fontSize: 14, color: Colors.black45),
            ),
            const SizedBox(height: 20),
            // 사업자 인증 상태 안내 — 인증 전에는 파티가 '오픈예정'으로만
            // 올라간다는 사실을 등록을 시작하기 **전에** 알려준다. 인증하러
            // 가는 길도 여기서 바로 연다.
            const _BusinessVerificationNotice(),
            const SizedBox(height: 20),
            // 🎉 이벤트 / 파티 — **다른 등록 유형과 같은 카드 한 칸**.
            //
            // 예전에는 🎪 매장 이벤트와 🎉 파티가 여기 큰 카드 두 장으로
            // 나란히 있었다. 둘은 "행사를 올린다"는 같은 일이고 갈리는 지점은
            // 참가 신청을 받는가 하나뿐인데, 카드 두 장이 나란히 서면 그
            // 하나뿐인 기준이 플레이스·파티샵·파티크루와 같은 무게로 읽혀
            // 이 화면이 "다섯 가지 중 고르기"가 됐다.
            //
            // 지금은 칸 하나로 들어가고, 둘 중 무엇인지는 다음 화면에서 판단
            // 기준 한 문장과 함께 고른다([RegisterOfferingChoiceScreen]) —
            // 거기 카드도 문구도 예전과 **같은 위젯**이고, 고른 뒤 가는 곳도
            // 예전 그대로다.
            //
            // 저장 구조는 하나도 합치지 않았다 — placePromotions와 parties는
            // 그대로다. 합친 것은 "등록으로 들어가는 입구"뿐이다.
            _TypeCard(
              emoji: '🎉',
              title: '이벤트 / 파티',
              description: '매장 행사부터 참가자 모집 파티까지',
              accentColor: const Color(0xFFFF6FA0),
              bgColor: const Color(0xFFFFF0F5),
              // 다른 카드와 같은 '?' — 이 카드 하나에 두 가지가 들어 있으니
              // 그 둘이 어떻게 다른지부터 말한다.
              onHelp: () => _showOfferingHelpSheet(context),
              onTap: () => Navigator.push(
                context,
                webFramedRoute(
                  // 두 카드의 '?'는 이 화면의 도움말 시트를 그대로 쓴다 —
                  // 안내를 다음 화면에 다시 짓지 않는다.
                  (_) => RegisterOfferingChoiceScreen(
                    onPlaceEventHelp: _showEventHelpSheet,
                    onPartyHelp: _showPartyHelpSheet,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 예전에는 "플레이스 등록"(매장)과 "파티 장소 등록"(대여 공간)이
            // 서로 다른 카드였다 — 둘 다 "내 공간을 올린다"라 어느 쪽을
            // 눌러야 하는지 알 수 없었고, 파티룸·대관 공간을 가진 사장님은
            // "플레이스 등록"을 자기 것이 아니라고 지나쳤다. 플레이스+파티
            // 등록이 이미 쓰던 방식대로, 진입을 하나로 합치고 어느 쪽인지는
            // 등록 화면 안에서 공간 유형으로 고른다.
            _TypeCard(
              emoji: '🥂',
              title: '플레이스 등록',
              description: '음식점·카페·술집부터 클럽·놀거리·체험, 공간대여·숙박까지 올려요',
              accentColor: const Color(0xFFFF6FA0),
              bgColor: const Color(0xFFFFF0F5),
              // 콤보 카드와 같은 '?' — 여기는 "플레이스만 먼저 올려도 된다"는
              // 이 카드만의 역할을 말한다.
              onHelp: () => _showPlaceHelpSheet(context),
              onTap: _goToPlaceRegister,
            ),
            const SizedBox(height: 16),
            // "플레이스+파티 등록"(콤보) 카드는 없앴다 — 플레이스와 파티를 한
            // 폼에서 동시에 만드는 등록 방식 자체를 최종 UX에서 뺐다. 대신
            // **플레이스를 먼저 등록하고**, 저장 직후 "이 플레이스에서 파티나
            // 이벤트를 여시나요?"([PlaceFollowupEntry])가 방금 만든 플레이스를
            // 그대로 물고 파티·이벤트 등록으로 이어준다. 같은 결과를 만들면서
            // 등록 유형이 하나 줄고, "어느 플레이스인지" 다시 묻지도 않는다.
            //
            // "파티 장소 등록" 카드도 위 "플레이스 등록"에 합쳐졌다 — 거기서
            // "공간대여·숙박"을 고르면 예전과 **같은 폼·같은 저장**
            // (places + placeRooms)으로 들어간다. 기존 장소대여 수정 화면과
            // 임시저장 "이어서 작성"도 그대로 그 폼을 연다.
            _TypeCard(
              emoji: '🛍️',
              title: '파티샵 등록',
              description: '파티샵을 등록하고 상품을 판매해요',
              accentColor: const Color(0xFFFF8C42),
              bgColor: const Color(0xFFFFF4EC),
              // 다른 카드와 같은 '?' — 어떤 상품을 파는 곳인지 말한다.
              onHelp: () => _showShopHelpSheet(context),
              onTap: () => Navigator.push(
                context,
                webFramedRoute((_) => const PartyMarketRegisterScreen()),
              ),
            ),
            const SizedBox(height: 16),
            _TypeCard(
              emoji: '🎤',
              title: '파티크루 글 등록',
              description: '구인·구직 글을 올리고 파티크루를 찾아요',
              accentColor: const Color(0xFFFF6FA0),
              bgColor: const Color(0xFFFFF0F5),
              // 다른 카드와 같은 '?' — 여기는 **구인·구직 전용**이라는 것부터
              // 말한다("크루"를 커뮤니티로 읽는 오해를 막는다).
              onHelp: () => _showCrewHelpSheet(context),
              onTap: () => Navigator.push(
                context,
                webFramedRoute((_) => const CrewRegisterScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String description;
  final Color accentColor;
  final Color bgColor;
  final VoidCallback? onTap;

  /// 제목 옆 '?' — 주면 버튼이 생기고, 없으면 제목만 그대로 보인다.
  /// 카드 자체를 누르는 것(등록 시작)과 겹치지 않게 탭을 여기서 삼킨다.
  final VoidCallback? onHelp;

  const _TypeCard({
    required this.emoji,
    required this.title,
    required this.description,
    required this.accentColor,
    required this.bgColor,
    required this.onTap,
    this.onHelp,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8EBF2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                      ),
                      // 제목과의 간격은 버튼이 자기 [Padding]으로 낸다 —
                      // 여기서 SizedBox로 한 번 더 띄우면 그만큼이 버튼
                      // 바깥이 되어 "?" 옆을 눌러도 안 열린다.
                      if (onHelp != null)
                        _TitleHelpButton(
                          accentColor: accentColor,
                          bgColor: bgColor,
                          onPressed: onHelp,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 13, color: Colors.black45),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: accentColor),
          ],
        ),
      ),
    );
  }
}

/// 카드 제목 옆의 '?' — '이벤트 등록'과 '플레이스 등록' 카드가 **같은 이
/// 위젯 하나**를 쓴다. 카드 전체가 눌리는 영역 안에 있으므로, 여기서 누른
/// 것은 등록 화면으로 넘어가지 않고 도움말만 연다.
///
/// ── 보이는 크기와 눌리는 크기를 따로 둔다 ─────────────────────────────────
/// 예전에는 22×22 원이 곧 터치 영역이라, 조금만 빗나가도 뒤에 있는 카드의
/// [GestureDetector]가 먼저 반응해 도움말 대신 등록 화면이 열렸다. 원은
/// [_circleSize]로 조금만 키우고, 그 둘레에 **투명한 [Padding]** 을 둘러
/// 손가락이 닿아야 하는 크기를 [_minTapTarget]까지 넓힌다 — 겉보기는 작은
/// '?' 그대로지만 그 주변 여백을 눌러도 열린다.
class _TitleHelpButton extends StatelessWidget {
  /// 눈에 보이는 원의 지름.
  static const double _circleSize = 27;

  /// 손가락이 닿아야 하는 최소 크기 — iOS·Android 접근성 권장치가 44다.
  static const double _minTapTarget = 44;

  /// 제목과 원 사이에 **보이는** 간격. 이 자리도 눌리는 영역에 들어간다
  /// (제목 바로 옆을 눌러도 도움말이 열린다).
  static const double _gapFromTitle = 10;

  final Color accentColor;
  final Color bgColor;
  final VoidCallback? onPressed;

  const _TitleHelpButton({
    required this.accentColor,
    required this.bgColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // 원을 뺀 나머지를 위아래·오른쪽에 투명 여백으로 두른다.
    const pad = (_minTapTarget - _circleSize) / 2;

    return Semantics(
      button: true,
      label: '설명 보기',
      child: GestureDetector(
        // opaque — 투명한 여백까지 이 버튼의 영역으로 잡아, 카드의
        // GestureDetector로 탭이 새어 나가지 않게 한다.
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Padding(
          // 왼쪽은 제목과의 간격을 겸한다 — 보이는 여백이 그대로 터치
          // 영역이 되도록 바깥에서 SizedBox로 띄우지 않는다.
          padding: const EdgeInsets.only(
            left: _gapFromTitle,
            right: pad,
            top: pad,
            bottom: pad,
          ),
          child: Container(
            width: _circleSize,
            height: _circleSize,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: Icon(
              Icons.question_mark_rounded,
              size: 15,
              color: onPressed == null ? Colors.black26 : accentColor,
            ),
          ),
        ),
      ),
    );
  }
}

// ── 등록 카드 '?' 도움말 ─────────────────────────────────────────────────
// 예전에는 두 콤보 등록 화면(매장/숙박) 상단의 접이식 안내 카드였다. 등록을
// 시작한 뒤에 읽는 자리라 실제로는 "이 등록이 나에게 맞나"를 판단하는 데
// 쓰이지 못해서, 유형을 **고르는** 이 화면의 제목 옆 '?'로 옮겼다.
//
// 카드마다 도움말을 따로 짓지 않고 아래 [_showTypeHelpSheet] 하나를 공유한다 —
// 시트의 모양(손잡이·제목줄·닫기·블록·꼬리 안내)은 한 곳에만 있고, 카드별
// 차이는 넘기는 **문구**뿐이다.
//
// 안내 UI 전용 — 등록 로직·저장 스키마와는 아무 관계가 없다.

/// 도움말 시트의 소제목 한 덩이.
class _HelpBlock {
  final String heading;
  final List<String> lines;

  const _HelpBlock(this.heading, this.lines);
}

/// 등록 카드 '?'가 여는 공통 도움말 BottomSheet.
///
/// [blocks]는 소제목 + 설명 문단들, [notes]는 본문 아래 별도 안내(작은 글씨).
void _showTypeHelpSheet(
  BuildContext context, {
  required String title,
  required List<_HelpBlock> blocks,
  List<String> notes = const [],
  double initialChildSize = 0.62,
}) {
  const accent = Color(0xFFFF6FA0);
  const text = Color(0xFF8A5A72);

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFFF7FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD6E4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.black45),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  for (var i = 0; i < blocks.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          blocks[i].heading,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final line in blocks[i].lines)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              line,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: text,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  for (final note in notes) ...[
                    const SizedBox(height: 16),
                    Text(
                      note,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: text,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// '🎪 매장 이벤트' — 이미 올려둔 플레이스에서 여는 행사 한 건을 더하는 길.
//
// 이 카드만 **전제 조건이 있다**(내 플레이스가 1개 이상). 그래서 도움말도
// "무엇을 등록하나"보다 "무엇과 연결되나"를 먼저 말한다 — 플레이스가 없는
// 사람은 여기서 이미 순서를 알고, 눌렀을 때 뜨는 안내가 낯설지 않다
// ([PlaceEventEntry.showNeedPlaceSheet]).
void _showEventHelpSheet(BuildContext context) {
  _showTypeHelpSheet(
    context,
    title: HostOffering.placeEvent.display,
    initialChildSize: 0.52,
    blocks: [
      _HelpBlock('${HostOffering.placeEvent.emoji} 어떤 행사를 등록하나요?', [
        HostOffering.placeEvent.registerDescription,
        // 갈리는 지점은 콘텐츠 종류가 아니라 모집 여부다 — 도움말에서도
        // 같은 기준을 같은 문장으로 말한다([HostOffering]).
        '${HostOffering.criterionHeadline} '
            '참가자를 모집하고 신청을 받는다면 ${HostOffering.party.display}로 등록해주세요.',
      ]),
      const _HelpBlock('🏪 등록된 플레이스와 연결해요', [
        '매장 이벤트는 등록된 플레이스와 연결해서 등록합니다.',
        '아직 플레이스가 없다면 플레이스를 먼저 등록한 뒤 언제든 매장 이벤트를 '
            '추가로 등록할 수 있어요.',
      ]),
    ],
    notes: const ['플레이스를 먼저 등록해두면 이후 새로운 매장 이벤트를 추가하거나 기존 연결을 수정할 수 있어요.'],
  );
}

// '🎉 파티' — 참가자를 모집하거나 티켓을 파는 행사를 여는 길.
//
// 이 도움말이 있는 이유는 이름 때문이다. "파티"라고 하면 친목 모임만 떠올려서,
// 공연이나 티켓 행사를 여는 호스트가 **자기 것이 아니라고 지나친다.** 그래서
// 첫 블록에서 "친목 모임만 뜻하지 않는다"를 먼저 못 박고, 모집형과 티켓형을
// 각각 한 덩이씩 보여준 뒤 예시로 닫는다.
//
// 시트의 모양은 매장 이벤트 '?'와 **같은 것**을 쓴다([_showTypeHelpSheet]) —
// 문구만 다르다.
void _showPartyHelpSheet(BuildContext context) {
  _showTypeHelpSheet(
    context,
    title: HostOffering.party.display,
    initialChildSize: 0.62,
    blocks: [
      _HelpBlock('${HostOffering.party.emoji} 어떤 행사를 등록하나요?', [
        HostOffering.party.registerDescription,
        '친목 모임만 뜻하는 게 아니에요. 참가자를 모집하는 행사도, 티켓을 파는 '
            '공연·행사도 모두 여기서 등록합니다.',
      ]),
      const _HelpBlock('🙋 참가자를 모집하는 모임', [
        '인원을 정해 신청을 받고, 필요하면 승인해서 참가자를 확정할 수 있어요.',
        '참가비를 받는 파티·모임도 여기에 해당해요.',
      ]),
      const _HelpBlock('🎫 티켓을 판매하는 공연·행사', [
        '공연처럼 티켓을 팔아 손님을 받는 행사도 파티로 등록해요.',
      ]),
      const _HelpBlock('📌 이런 것들이 파티예요', [
        '번개모임 · 생일파티 · 술모임 · 클럽모임 · 공연 · 티켓 행사',
      ]),
    ],
    notes: [
      '${HostOffering.criterionHeadline} '
          '매장이 여는 행사·혜택이라면 ${HostOffering.placeEvent.display}로 등록해주세요.',
    ],
  );
}

// '플레이스 등록' — 플레이스만 먼저 올리는 길. 어떤 공간을 올릴 수 있는지는
// 공간 유형 정본([ComboPlaceType])의 예시를 그대로 빌려 쓴다. 여기에 목록을
// 다시 적으면 등록 화면의 유형 선택 카드와 말이 갈라진다.
void _showPlaceHelpSheet(BuildContext context) {
  const venue = ComboPlaceType.venue;
  const stay = ComboPlaceType.stay;

  _showTypeHelpSheet(
    context,
    title: '🥂 플레이스 등록',
    initialChildSize: 0.52,
    blocks: [
      _HelpBlock('${venue.emoji} ${venue.label}', [
        '${venue.examples} 사람들이 방문해서 즐기는 플레이스를 등록할 수 있어요.',
      ]),
      _HelpBlock('${stay.emoji} ${stay.label}', [
        '${stay.examples} 예약형 공간도 등록할 수 있어요.',
      ]),
    ],
    // 파티를 함께 여는 사장님도 이 카드로 온다 — 등록을 마치면 후속
    // 질문([PlaceFollowupEntry])이 방금 만든 플레이스를 그대로 물고
    // 파티·이벤트 등록으로 이어준다(예전 "플레이스+파티 등록"의 대체).
    notes: const [
      '등록을 마치면 이 플레이스에서 여는 파티·이벤트를 바로 이어서 등록할 수 있어요.',
      '등록 후에도 새로운 파티·이벤트를 추가로 연결하거나 기존 연결을 수정할 수 있어요.',
    ],
  );
}

// '🎉 이벤트 / 파티 등록' — 이 카드 하나에 두 가지가 들어 있어서, 누르기 전에
// 그 둘이 어떻게 다른지 먼저 알려준다.
//
// ── 다음 화면의 '?'와 말이 갈리지 않게 하는 법 ───────────────────────────────
// 이 카드를 누르면 나오는 선택 화면에도 카드별 '?'가 있다
// ([_showEventHelpSheet] · [_showPartyHelpSheet]). 세 시트가 각자 정의를 적으면
// 같은 질문에 세 가지 답이 생긴다. 그래서 **정의 문장은 손으로 적지 않고**
// [HostOffering]의 정본([criterion] · [display])을 그대로 읽는다 — 거기 한 곳을
// 고치면 세 시트가 함께 바뀐다.
//
// 여기서는 "둘이 어떻게 다른가"까지만 말한다. 각 유형을 깊이 설명하는 것은
// 다음 화면의 '?'가 맡는다(같은 말을 두 번 하면 고르기 전에 읽을 것만 늘어난다).
void _showOfferingHelpSheet(BuildContext context) {
  const placeEvent = HostOffering.placeEvent;
  const party = HostOffering.party;

  _showTypeHelpSheet(
    context,
    title: '🎉 이벤트 / 파티 등록',
    initialChildSize: 0.52,
    blocks: [
      _HelpBlock(placeEvent.display, [
        // '매장에서 진행하는 이벤트·혜택' — 정의는 정본에서 온다.
        '${placeEvent.criterion}을 알려요.',
        '주류 할인·1+1·생일 이벤트·DJ·시음·시즌 행사 등 매장에서 진행하는 '
            '소식과 혜택을 등록할 수 있어요.',
      ]),
      _HelpBlock(party.display, [
        // '참가자를 모집하거나 티켓을 판매하는 행사' — 여기도 정본이다.
        '${party.criterion}를 열어요.',
        '참가 신청·승인을 받는 모임부터 파티·공연·행사 티켓 판매까지 등록할 수 '
            '있어요.',
      ]),
      // ⚠️ 여기에 [HostOffering.criterionHeadline]("매장이 여는 행사인지,
      //    참가자를 모집하는 모임인지")을 함께 놓지 않는다 — 그 줄은 티켓 판매를
      //    담기 전의 기준이라, 나란히 두면 한 시트에서 고르는 기준이 둘이 된다.
      const _HelpBlock('🤔 어떤 걸 선택해야 할까요?', [
        "매장의 행사·혜택을 알리는 것이 중심이면 '$kPlaceEventLabel', "
            "참가자를 모집하거나 티켓을 판매하는 것이 중심이면 '$kPartyLabel'를 "
            '선택해주세요.',
      ]),
    ],
  );
}

// '🛍️ 파티샵 등록' — 파티 준비물을 파는 샵과 그 안의 상품을 올리는 길.
//
// 카테고리를 여기 손으로 적지 않는다 — [ListingConstants.shopCategories]가
// 등록 폼의 선택지 정본이고, 도움말이 그것을 그대로 읽는다. 목록이 바뀌면
// 안내도 같이 바뀐다(둘이 갈라지면 "도움말에 있는 카테고리가 폼에는 없다"가
// 된다).
void _showShopHelpSheet(BuildContext context) {
  _showTypeHelpSheet(
    context,
    title: '🛍️ 파티샵 등록',
    initialChildSize: 0.55,
    blocks: [
      const _HelpBlock('🛍️ 어떤 것을 등록하나요?', [
        '파티 준비에 필요한 상품을 파는 내 샵을 열고, 그 안에 판매할 상품을 '
            '하나씩 등록하는 곳이에요.',
      ]),
      _HelpBlock('🎁 이런 상품을 올려요', [
        ListingConstants.shopCategories.join(' · '),
      ]),
      const _HelpBlock('📦 상품마다 정하는 것', [
        '상품 사진과 설명, 판매가·재고, 옵션을 정할 수 있어요.',
        '구매·수령 방법은 당일 퀵 · 방문수령 · 택배 · 지정일 배송 중에서 고릅니다.',
      ]),
    ],
    notes: const ['상품에 카테고리를 골라 두면 손님이 상세검색에서 그 카테고리로 찾을 수 있어요.'],
  );
}

// '🎤 파티크루 글 등록' — **구인·구직 전용**이다.
//
// 이 도움말이 있는 이유는 오해 때문이다. "크루"라는 이름을 커뮤니티나 동행
// 모집으로 읽으면 이 화면에 일자리 글이 아닌 것이 올라온다. 그래서 첫 줄에서
// "일자리 글"이라고 못 박고, 실제로 고를 수 있는 역할만 보여준다.
//
// ⚠️ 역할 목록은 [ListingConstants.crewRoles]를 그대로 읽는다 — 여기에 손으로
//    적으면 폼에 없는 직종을 안내하게 된다.
void _showCrewHelpSheet(BuildContext context) {
  // 목록 정본에서 '기타'만 뺀 실제 직종 — '기타'는 아래에서 따로 설명한다.
  final roles = ListingConstants.crewRoles
      .where((r) => r != '기타')
      .join(' · ');

  _showTypeHelpSheet(
    context,
    title: '🎤 파티크루 글 등록',
    initialChildSize: 0.58,
    blocks: [
      const _HelpBlock('🎤 구인·구직 글을 올리는 곳이에요', [
        '파티·행사에 필요한 사람을 구하거나, 파티·행사에서 일할 자리를 찾는 '
            '글을 올립니다.',
        '글 유형은 구인과 구직 두 가지예요.',
      ]),
      const _HelpBlock('🙋 구인 — 사람을 구해요', [
        '파티·공연·매장 행사에 필요한 스태프를 모집하는 글이에요.',
      ]),
      const _HelpBlock('💼 구직 — 일할 자리를 찾아요', [
        '파티·행사에서 일하고 싶은 분이 자기를 알리는 글이에요.',
      ]),
      _HelpBlock('🎧 이런 역할을 다뤄요', [
        roles,
        "목록에 없는 역할은 '기타'를 골라 직접 적을 수 있어요.",
      ]),
      const _HelpBlock('📝 함께 적는 것', [
        '모집 기간과 시간, 활동 지역, 급여·페이, 모집 인원, 모집 조건을 적어요.',
        '구인 글에는 실제 주소와 지원자 자동 안내 문구를, 구직 글에는 프로필 '
            '사진을 더할 수 있어요.',
      ]),
    ],
  );
}

// ── 등록 유형 안내 BottomSheet ────────────────────────────────────────────
// 위 등록 카드들이 서로 어떻게 다른지 헷갈려하는 이용자를 위한 도움말 —
// AppBar의 '?' 버튼에서만 진입하며, 실제 등록 로직에는 관여하지 않는다.

void _showRegisterHelpSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFFF7FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD6E4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '등록 유형 안내',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.black45),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: const [
                  // ✨와 🎉가 어떻게 갈리는지가 이 시트의 첫 두 칸이다 —
                  // 갈리는 기준은 콘텐츠 종류가 아니라 **누가 여는가**다
                  // ([HostOffering]). 등록 화면 위쪽 선택 블록과 같은 말을
                  // 같은 순서로 한다.
                  //
                  // ⚠️ 신청 여부로 가르지 않는다 — 생일 이벤트처럼 사전 신청을
                  //    받는 매장 이벤트도 있다.
                  _HelpTypeCard(
                    emoji: kPlaceEventEmoji,
                    title: '매장 이벤트',
                    description:
                        '매장에서 진행하는 이벤트·혜택이에요. 이미 등록해 둔 플레이스에서 진행하는 '
                        '주류 할인·1+1·생일 이벤트·공연·시음·시즌 행사를 올릴 때 이용해주세요. '
                        '그 플레이스에 연결돼 플레이스 상세와 ✨ 이벤트 탐색에 함께 보여요.',
                    examples: [
                      '주류 할인',
                      '1+1',
                      '생일 이벤트',
                      '공연',
                      'DJ 공연',
                      '시음회',
                      '클래스',
                      '체험',
                      '시즌 행사',
                      '방문 혜택',
                    ],
                    note:
                        '플레이스가 있어야 등록할 수 있어요. 아직 없다면 플레이스를 먼저 '
                        '등록한 뒤 언제든 매장 이벤트를 추가할 수 있어요.',
                    accentColor: Color(0xFFFF6FA0),
                    bgColor: Color(0xFFFFF0F5),
                  ),
                  SizedBox(height: 14),
                  _HelpTypeCard(
                    emoji: '🎉',
                    title: '파티',
                    description:
                        '참가자를 모집하고 신청을 받는 행사예요. 인원을 모집하고 신청·승인·참가비를 '
                        '받아 함께 즐기는 모임이라면 이쪽입니다. 같은 DJ 공연이라도 '
                        '"30명 모집"이면 파티예요.',
                    examples: ['번개 모임', '생일파티', '술모임', '클럽모임', '캠핑모임'],
                    accentColor: Color(0xFFFF6FA0),
                    bgColor: Color(0xFFFFF0F5),
                  ),
                  SizedBox(height: 14),
                  _HelpTypeCard(
                    emoji: '🥂',
                    title: '플레이스 등록',
                    description:
                        '내 공간을 올릴 때 이용해주세요. 등록 화면 맨 위에서 '
                        '방문형 플레이스인 "매장·즐길거리"와 예약형 공간인 "공간대여·숙박" 중 '
                        '하나를 고르면 그 유형에 맞는 입력 항목만 보여드려요 '
                        '(공간대여·숙박은 룸·요금·예약 입력이 함께 나옵니다).',
                    examples: [
                      '음식점',
                      '다이닝·파인다이닝',
                      '카페',
                      '술집·혼술바',
                      '클럽·댄스',
                      '라이브',
                      '놀거리',
                      '체험/클래스',
                      '파티룸·대관 공간',
                      '숙박',
                    ],
                    // 파티를 함께 여는 사장님도 여기로 온다 — 예전의
                    // "플레이스+파티 등록"이 하던 일을 등록 직후의 후속
                    // 질문([PlaceFollowupEntry])이 대신하므로, 이 안내가
                    // 그 다음 단계까지 미리 말해준다.
                    note:
                        '등록을 마치면 이 플레이스에서 여는 파티·이벤트를 바로 이어서 '
                        '등록할 수 있어요. 나중에 추가하거나 고쳐도 돼요.',
                    accentColor: Color(0xFFFF6FA0),
                    bgColor: Color(0xFFFFF0F5),
                  ),
                  SizedBox(height: 14),
                  _HelpTypeCard(
                    emoji: '🛍️',
                    title: '파티샵 등록',
                    description: '파티와 관련된 상품이나 서비스를 판매하는 경우 이용해주세요.',
                    examples: ['케이크', '풍선', '파티용품', '꽃', '선물', '이벤트 소품'],
                    accentColor: Color(0xFFFF8C42),
                    bgColor: Color(0xFFFFF4EC),
                  ),
                  SizedBox(height: 14),
                  _HelpTypeCard(
                    emoji: '🎤',
                    title: '파티크루 등록',
                    description: '파티 운영을 함께할 스태프를 모집하거나 파티 관련 구직을 하는 공간입니다.',
                    examples: ['DJ', 'MC', '사진작가', '바텐더', '스태프', '공연팀'],
                    accentColor: Color(0xFFFF6FA0),
                    bgColor: Color(0xFFFFF0F5),
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

class _HelpTypeCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String description;
  final List<String> examples;
  final String? note;
  final Color accentColor;
  final Color bgColor;

  const _HelpTypeCard({
    required this.emoji,
    required this.title,
    required this.description,
    required this.examples,
    this.note,
    required this.accentColor,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 17)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: examples
                .map(
                  (e) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      e,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: accentColor,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          if (note != null) ...[
            const SizedBox(height: 10),
            Text(
              note!,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black45,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 등록 유형 선택 화면 맨 위의 사업자 인증 안내.
///
/// 인증을 마쳤으면 짧게 "인증 완료"만 알리고, 아직이면 파티가 어떤 상태로
/// 올라가는지(오픈예정)와 인증하러 가는 길을 함께 보여준다.
class _BusinessVerificationNotice extends StatelessWidget {
  const _BusinessVerificationNotice();

  @override
  Widget build(BuildContext context) {
    if (UserSession.userId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<BusinessVerification>(
      stream: BusinessVerificationService.watch(),
      builder: (context, snap) {
        // 아직 못 읽었으면 아무것도 그리지 않는다 — 잠깐 "미인증"이라고
        // 말했다가 바꾸면 인증을 마친 사업자에게 불필요한 불안을 준다.
        if (!snap.hasData) return const SizedBox.shrink();
        final v = snap.data!;

        if (v.isVerified) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.verified_outlined,
                  size: 18,
                  color: Color(0xFF047857),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '사업자 인증 완료 — 등록 후 바로 모집을 열 수 있어요.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF047857)),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC7D2FE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.badge_outlined,
                    size: 18,
                    color: Color(0xFF4F46E5),
                  ),
                  SizedBox(width: 6),
                  Text(
                    '사업자 인증이 필요해요',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '인증 전에는 파티가 "오픈예정"으로 올라가요. 미리 알리고 오픈 알림은 받을 수 있지만, '
                '신청·예약·결제는 아직 받을 수 없어요.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFF3730A3),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    webFramedRoute((_) => const BusinessVerificationScreen()),
                  ),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('사업자 인증하기'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: const Color(0xFF4F46E5),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
