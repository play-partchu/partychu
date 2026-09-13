import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:party_app/login.dart';
import 'package:party_app/models/listing_inquiry.dart';
import 'package:party_app/screens/chat_room_screen.dart';
import 'package:party_app/services/chat_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/login_required_dialog.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 상세 페이지의 **문의하기** — 파티·플레이스·장소대여가 함께 쓰는 하나.
///
/// 호스트가 [ListingInquiry]로 켜고 끄는 값에 따라 있거나 없다.
///
///   · ON  — 💬 문의하기 버튼. 신청·예약 **전에도** 호스트와 대화를 시작한다.
///   · OFF — **아무것도 그리지 않는다.** 하단 CTA에서 이 자리가 비면 신청·예약
///           버튼이 전체 폭을 쓴다([shouldShow]로 호출부가 미리 판단한다).
///
/// ── 채팅방에 들어가기 전에 안내를 먼저 보여준다 ──────────────────────────
/// 호스트가 [ListingInquiry.guideField]에 적어 둔 글이 있으면 바텀시트로 먼저
/// 띄우고, '채팅 시작하기'를 눌렀을 때만 방을 연다. 안내가 비어 있으면 빈
/// 팝업을 띄우지 않고 곧장 채팅으로 간다.
///
/// ── 방은 예약 채팅과 같은 방이다 ────────────────────────────────────────
/// 채팅방 id는 `{guestId}_{relatedType}_{relatedId}`라, 문의로 연 방과 나중에
/// 신청·예약으로 이어지는 방이 **자동으로 같은 방**이 된다([InquiryTarget]).
/// 문의하다 신청한 게스트가 갑자기 빈 방으로 옮겨지지 않는다.
///
/// ── 호스트에게 알림은 따로 만들지 않는다 ────────────────────────────────
/// 새 문의는 곧 새 메시지이고, 메시지 푸시는 이미 서버가 보낸다
/// (functions/pushDispatch.js `onChatMessageCreated` — 방 참가자 중 보낸 사람을
/// 뺀 나머지에게 발송). 여기서 알림을 한 번 더 만들면 문의 하나에 알림이 둘
/// 간다.
/// 게시글 채팅방을 열고(없으면 만들고) 대화 화면으로 보낸다 — **문의하기와
/// 신청하기가 함께 쓰는 하나**.
///
/// 방 id는 `{guestId}_{relatedType}_{relatedId}`라, 같은 게시글이면 문의로 연
/// 방과 신청으로 연 방이 **자동으로 같은 방**이다([InquiryTarget]). 그래서
/// 문의하다 신청한 게스트가 빈 방으로 옮겨지지 않는다 — 이 함수를 복제해
/// 신청용 경로를 따로 만들면 그 성질이 곧바로 깨진다.
///
/// [openingMessage]가 있으면 방에 들어가기 전에 게스트 이름으로 한 줄 보낸다.
/// 신청하기가 이 자리를 쓴다 — "신청 버튼을 눌렀다"는 사실이 대화에 남아야
/// 호스트가 문의와 신청을 구분할 수 있다. 문의하기는 비워 둔다(할 말이 없다).
Future<void> openListingChat(
  BuildContext context, {
  required InquiryTarget target,
  required String listingId,
  required String hostId,
  required String hostName,
  required String listingTitle,
  String guide = '',
  String? openingMessage,
  String loginMessage = '문의하려면 로그인이 필요합니다.',
  String hostMissingMessage = '호스트 정보를 찾을 수 없어 문의를 열 수 없어요.',
  required void Function(BuildContext context, String message) onFailure,
  Future<bool?> Function(BuildContext context, String guide)? showGuideSheet,
}) async {
  if (!UserSession.isLoggedIn) {
    final shouldLogin = await showLoginRequiredDialog(
      context,
      message: loginMessage,
    );
    if (!shouldLogin || !context.mounted) return;
    await Navigator.push(context, webFramedRoute((_) => LoginPage()));
    return;
  }
  if (hostId.trim().isEmpty) {
    // 호스트를 모르면 서버도 방을 열 수 없다 — createChatRoom이
    // failed-precondition('호스트 정보를 찾을 수 없어요')으로 막는다.
    //
    // 예전에는 여기서 **말없이 돌아갔다.** 그래서 이 경우 버튼은 눌러도 아무
    // 일도 일어나지 않는 버튼이 됐고, 로그도 남지 않아 제보를 받아도 무엇이
    // 막았는지 알 길이 없었다.
    onFailure(context, hostMissingMessage);
    return;
  }

  // 호스트가 안내를 적어 뒀으면 채팅방에 들어가기 **전에** 먼저 보여준다.
  // 비어 있으면 빈 팝업을 띄우지 않고 그대로 채팅으로 간다.
  if (guide.trim().isNotEmpty && showGuideSheet != null) {
    final start = await showGuideSheet(context, guide.trim());
    if (start != true || !context.mounted) return;
  }

  // 여기서부터 네트워크다. **기다리는 것은 방 하나뿐**이다 — 방이 열리면
  // 곧장 대화로 보낸다.
  //
  // 그동안 화면이 아무 말도 하지 않으면 사용자에게는 **눌러도 안 되는
  // 버튼**이다. 운영 로그(2026-08-30)에 같은 문의가 6초 동안 열 번 찍혀
  // 있었던 것이 그 모습이다 — 방은 첫 번째 호출에 이미 만들어졌는데, 뒤이어
  // 기다리던 자동 안내 예약이 콜드 스타트로 11.4초를 끌었다. 그 대기는
  // 아래에서 없앴고, 남은 대기(방 열기) 동안에는 진행 표시를 띄운다 — 그
  // 막이 중복 탭도 함께 막는다.
  final progress = _ChatOpenProgress.show(context);
  String? roomId;
  try {
    roomId = await ChatService.getOrCreateRoom(
      hostId: hostId,
      hostName: hostName,
      guestId: UserSession.userId,
      guestName: UserSession.displayName,
      relatedType: target.relatedType,
      relatedId: listingId,
      relatedTitle: listingTitle,
    );
    // 자동 안내 예약은 **입장의 선행조건이 아니다** — 띄워만 두고 결과를
    // 기다리지 않는다([_scheduleAutoMessageInBackground]).
    _scheduleAutoMessageInBackground(
      relatedType: target.relatedType,
      roomId: roomId,
      listingId: listingId,
    );

    final opening = openingMessage?.trim() ?? '';
    if (opening.isNotEmpty) {
      await ChatService.sendMessage(
        roomId: roomId,
        senderId: UserSession.userId,
        senderName: UserSession.displayName,
        text: opening,
      );
    }
  } catch (e, st) {
    // 원인을 **삼키지 않는다.** 프로젝트 공용 로그가 code/message/stack을 나눠
    // 찍는다 — 서버 로그의 HttpsError와 그대로 맞춰 볼 수 있는 형태다.
    logFirestoreStreamError(
      'ListingChat(${target.relatedType}/$listingId)',
      e,
      st,
    );
    roomId = null;
    // 안내를 띄우기 전에 막을 걷는다 — 진행 표시 위에 실패 안내가 얹히면
    // 사용자가 확인을 눌러도 한 겹이 더 남은 것처럼 보인다.
    progress.close();
    if (!context.mounted) return;
    onFailure(
      context,
      GuestInquiryButton.failureMessageFor(
        code: e is FirebaseFunctionsException ? e.code : null,
        message: e is FirebaseFunctionsException ? e.message : null,
      ),
    );
  } finally {
    progress.close();
  }

  if (roomId == null || !context.mounted) return;
  await Navigator.push(
    context,
    webFramedRoute(
      (_) => ChatRoomScreen(
        roomId: roomId!,
        otherName: hostName,
        relatedTitle: listingTitle,
      ),
    ),
  );
}

/// 서버가 자동 안내를 붙일 수 있는 글 종류 — chatAutoMessages.js의
/// `SUPPORTED_TYPES`와 **같은 값**이다(둘이 어긋나지 않게
/// guest_inquiry_test.dart가 서버 파일에서 직접 읽어 맞춰 본다).
///
/// 여기 없는 종류에는 예약할 안내가 아예 없다 — 부르면 서버가
/// `source-missing`만 돌려주므로 왕복 한 번이 통째로 헛걸음이다. 매장
/// 이벤트('event')와 파티('party')가 그렇다.
@visibleForTesting
const Set<String> kAutoMessageRelatedTypes = {'crew', 'shop', 'place'};

/// 자동 안내 예약을 **띄워만 둔다** — 결과를 기다리지 않는다.
///
/// 방은 이미 열렸고 이건 인사말을 준비하는 곁가지인데, 콜드 스타트가 끼면
/// 십수 초가 걸린다(운영 로그에서 11.4초). 그 시간을 사용자가 빈 화면으로
/// 기다릴 이유가 없다 — 채팅방 화면이 들어가면서 부르는
/// [ChatService.flushPendingAutoMessages]가 발송을 맡고, 그때 아직 예약이
/// 안 끝났으면 다음 입장에서 나간다.
///
/// **문의 경로에서는 사실 예약될 것이 없다.** 이 함수를 지나는 대상은
/// party·place·rental·event 넷뿐인데, party·event는 위 표 밖이고, place는
/// 이용일 없이 부르면 서버가 발송 시각을 못 정해(`no-send-time`) 예약하지
/// 않는다 — 실제 예약은 예약·주문 화면이 이용일·상품과 함께 따로 부른다
/// (place_detail_screen · party_shop_detail_screen · crew_detail_screen).
/// 그래도 표에 있는 종류는 그대로 불러 둔다: 서버가 나중에 안내를 붙이면
/// 이 경로도 함께 살아나야 한다.
void _scheduleAutoMessageInBackground({
  required String relatedType,
  required String roomId,
  required String listingId,
}) {
  if (!kAutoMessageRelatedTypes.contains(relatedType)) return;
  unawaited(
    ChatService.scheduleAutoMessage(roomId: roomId).catchError((
      Object e,
      StackTrace st,
    ) {
      // 실패해도 대화는 이미 열려 있다 — 원인만 남긴다(채팅방 입장의
      // flush와 같은 방침).
      logFirestoreStreamError(
        'ChatAutoMessage($relatedType/$listingId)',
        e,
        st,
      );
    }),
  );
}

/// 방을 여는 동안 화면을 덮는 진행 표시.
///
/// 라우트를 직접 들고 있다가 [close]에서 **그 라우트만** 걷는다 — 그 사이에
/// 다른 화면이 위에 얹혀도 엉뚱한 것을 닫지 않는다.
class _ChatOpenProgress {
  _ChatOpenProgress._(this._navigator, this._route);

  static _ChatOpenProgress show(BuildContext context) {
    final navigator = Navigator.of(context);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (_) => const _ChatOpenProgressBody(),
    );
    navigator.push(route);
    return _ChatOpenProgress._(navigator, route);
  }

  final NavigatorState _navigator;
  final DialogRoute<void> _route;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    if (_navigator.mounted) _navigator.removeRoute(_route);
  }
}

class _ChatOpenProgressBody extends StatelessWidget {
  const _ChatOpenProgressBody();

  @override
  Widget build(BuildContext context) => const PopScope(
    // 여는 중에 뒤로 가기로 막만 걷히면, 진행은 계속되는데 화면은 다시
    // 조용해진다 — 고치려던 그 모습으로 돌아간다.
    canPop: false,
    child: Center(
      child: Card(
        color: Colors.white,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              SizedBox(width: 14),
              Text(
                '채팅방을 여는 중…',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class GuestInquiryButton extends StatelessWidget {
  /// 호스트가 켜 둔 값 — [ListingInquiry.isEnabled]로 읽은 결과를 그대로 준다.
  final bool enabled;

  final InquiryTarget target;

  /// 원본 문서 id — 채팅방의 `relatedId`가 된다.
  final String listingId;

  final String hostId;
  final String hostName;

  /// 채팅 목록에 표시될 대상 이름(파티 제목·플레이스 이름 등).
  final String listingTitle;

  /// 호스트가 적어 둔 "문의 전 안내" — [ListingInquiry.guideOf]로 읽은 값.
  /// 비어 있으면 안내 없이 곧장 채팅으로 보낸다.
  final String guide;

  final EdgeInsets margin;

  /// 하단 고정 CTA 안에서 주 버튼과 나란히 놓일 때 true.
  /// 이때는 바깥 여백을 스스로 두지 않고 폭도 부모가 정한다.
  final bool compact;

  /// 흑백 톤 변형 — 흰 배경·검정 테두리·검정 글자/아이콘에 라벨은 '채팅 문의'.
  ///
  /// 파티 상세 하단 CTA는 주 버튼이 브랜드 핑크라, 옆에 선 문의 버튼까지
  /// 색을 쓰면 두 버튼이 서로 경쟁한다. 기본값(false)은 기존 보라 톤
  /// '문의하기'로, 플레이스·장소대여 상세는 그대로 둔다.
  final bool mono;

  const GuestInquiryButton({
    super.key,
    required this.enabled,
    required this.target,
    required this.listingId,
    required this.hostId,
    required this.hostName,
    required this.listingTitle,
    this.guide = '',
    this.margin = const EdgeInsets.only(top: 12),
    this.compact = false,
    this.mono = false,
  });

  /// 이 게시글에 문의 버튼을 그려야 하는가.
  ///
  /// 하단 CTA가 "문의 + 신청" 두 칸인지 "신청" 한 칸인지를 **버튼을 만들기
  /// 전에** 알아야 해서 밖으로 뺐다. 여기가 false면 호출부는 주 CTA를 전체
  /// 폭으로 그린다.
  static bool shouldShow({required bool enabled, required String hostId}) {
    if (!enabled) return false;
    // 내 게시글에는 문의 버튼을 두지 않는다 — 자기 자신과의 채팅방이 생긴다.
    if (UserSession.isLoggedIn && UserSession.userId == hostId) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // 호스트가 꺼 뒀거나 내 글이면 **아무것도 그리지 않는다.** 예전에는 대신
    // 안내 박스를 띄웠지만, 지금은 자리를 비워 주 CTA가 전체 폭을 쓴다.
    if (!shouldShow(enabled: enabled, hostId: hostId)) {
      return const SizedBox.shrink();
    }
    if (compact) return _button(context);
    return Padding(padding: margin, child: _button(context));
  }

  Widget _button(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 48,
    child: mono
        ? _monoButton(context)
        : OutlinedButton.icon(
            onPressed: () => _open(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF4F46E5),
              side: const BorderSide(color: Color(0xFF4F46E5), width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Text('💬', style: TextStyle(fontSize: 15)),
            label: const Text(
              '문의하기',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
            ),
          ),
  );

  /// [mono] 변형 — 흰 배경·검정 테두리·검정 글자/아이콘.
  ///
  /// 라벨은 좁은 칸(파티 상세는 108px)에서도 **반드시 한 줄**이어야 한다 —
  /// 그냥 두면 "채팅 / 문의"로 접혀 두 줄이 된다. 그래서 아이콘과 글자를 한
  /// Row에 담아 [FittedBox]로 통째로 감싼다: 폭이 모자라면 줄바꿈 대신 전체가
  /// 조금 작아진다. 이모지(💬) 대신 [Icons.chat_bubble_outline]을 쓰는 것도
  /// 같은 이유다 — 이모지는 색을 검정으로 지정할 수 없다.
  Widget _monoButton(BuildContext context) => OutlinedButton(
    onPressed: () => _open(context),
    style: OutlinedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      side: const BorderSide(color: Colors.black, width: 1.2),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    child: const FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 16, color: Colors.black),
          SizedBox(width: 6),
          Text(
            '채팅 문의',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _open(BuildContext context) => openListingChat(
    context,
    target: target,
    listingId: listingId,
    hostId: hostId,
    hostName: hostName,
    listingTitle: listingTitle,
    guide: guide,
    onFailure: _notifyFailure,
    showGuideSheet: _showGuideSheet,
  );

  /// 화면에 내놓을 실패 문구 — 예외 객체 없이 code/message만으로 판정한다.
  ///
  /// 서버가 이미 **사람이 읽을 한국어**로 돌려주는 코드(functions/chatRooms.js의
  /// HttpsError)는 그 말을 그대로 보여주고, 나머지는 재시도 안내에 **오류 코드만**
  /// 덧붙인다. stack trace나 내부 메시지는 내놓지 않지만, 코드 한 낱말이 있어야
  /// 제보를 받은 쪽이 서버 로그와 맞춰 볼 수 있다.
  ///
  /// 콜러블 예외는 테스트에서 만들 수 없어(생성자가 @protected) 규칙만 따로
  /// 떼어 둔다. 이 문구가 조용히 "잠시 후 다시 시도" 하나로 되돌아가면 원인이
  /// 다시 화면에서 사라지므로, 규칙은 테스트로 못박는다.
  @visibleForTesting
  static String failureMessageFor({
    required String? code,
    required String? message,
  }) {
    const spoken = {
      'failed-precondition',
      'not-found',
      'permission-denied',
      'unauthenticated',
    };
    final spokenMessage = message?.trim() ?? '';
    if (code != null && spoken.contains(code) && spokenMessage.isNotEmpty) {
      return spokenMessage;
    }
    const retry = '문의 채팅을 열지 못했어요. 잠시 후 다시 시도해주세요.';
    return code == null ? retry : '$retry ($code)';
  }

  /// 실패를 **보이는 자리에** 알린다.
  ///
  /// 매장 이벤트 문의 버튼은 상세 바텀시트 안에 있다
  /// (place_promotion_detail_sheet.dart). 스낵바는 화면 아래 Scaffold 안에
  /// 그려지므로 그 시트에 그대로 **가려진다** — 서버가 또박또박 거절하고
  /// 있는데도 사용자 눈에는 "눌러도 아무 반응 없는 버튼"이 된다.
  ///
  /// 그래서 팝업 라우트(바텀시트·다이얼로그) 위에서는 다이얼로그로 알린다.
  /// 페이지 위(파티·플레이스·장소대여 상세)에서는 예전처럼 스낵바다.
  void _notifyFailure(BuildContext context, String message) {
    final route = ModalRoute.of(context);
    // 페이지 라우트는 불투명하고, 바텀시트·다이얼로그 같은 팝업 라우트는 아니다.
    final coveredByPopup = route != null && !route.opaque;
    if (coveredByPopup) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(message, style: const TextStyle(fontSize: 14.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// 문의 전 안내 바텀시트. '채팅 시작하기'를 눌렀을 때만 true를 돌려준다.
  Future<bool?> _showGuideSheet(BuildContext context, String text) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Text('💬', style: TextStyle(fontSize: 17)),
                  SizedBox(width: 7),
                  Text(
                    '채팅문의',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                '호스트가 남긴 안내',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 7),
              // 안내문이 상한(300자)에 가까워도 화면 절반을 넘지 않게 하고,
              // 그 안에서는 스크롤로 전부 읽을 수 있게 한다.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.38,
                ),
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.6,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black54,
                          side: const BorderSide(color: Color(0xFFE2E4EC)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          '닫기',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          '채팅 시작하기',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
