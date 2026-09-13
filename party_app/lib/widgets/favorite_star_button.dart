import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:party_app/login.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/services/ui_sound_service.dart';
import 'package:party_app/widgets/favorite_pop_feedback.dart';
import 'package:party_app/widgets/login_required_dialog.dart';
import 'package:party_app/widgets/partychu_ui.dart' show PartyChuColors;
import 'package:party_app/widgets/web_frame.dart';

/// 파티/장소/플레이스/파티샵/파트너의 카드와 상세 화면에 **공통으로** 붙는
/// 찜(관심) 토글 버튼 — 앱 안의 찜 버튼은 이 위젯 하나뿐이다.
///
/// 아이콘은 마이페이지 "관심 목록"이 쓰는 것과 **같은 고양이 발바닥**
/// ([Icons.pets])이다. 관심 목록 메뉴([MyPageScreen])와 빈 상태 화면
/// ([MyFavoritesScreen])이 이미 이 아이콘을 쓰고 있어서, 새 아이콘을 만들지
/// 않고 그대로 가져다 쓴다 — 찜 버튼과 관심 목록이 서로 다른 그림이면 같은
/// 기능인 줄 모른다.
///
/// 상태는 **같은 고양이의 투명/채움**으로 구분한다.
/// · 미찜 → 흐린(투명한) 고양이
/// · 찜   → 같은 고양이가 꽉 찬 색으로 칠해지고 살짝 팝(pop)
///
/// `Icons.pets_outlined`를 쓰지 않는 이유: 발바닥은 속이 빈 모양이 없어
/// outlined 변형이 채움과 사실상 같게 보인다 — 그러면 두 상태가 구분되지
/// 않는다. 투명도는 어떤 배경에서도 확실히 달라 보인다.
///
/// 저장은 [FavoritesService] 하나만 쓴다(로컬 상태로 색만 바꾸지 않는다).
class FavoriteStarButton extends StatefulWidget {
  final String itemType;
  final String itemId;
  final double size;
  // 목록 카드처럼 줄 높이가 작은 곳에 쓸 때 true — 기본 44dp 터치 영역 대신
  // 좁은 터치 영역을 써서 카드 높이가 늘어나지 않게 한다.
  final bool dense;
  // 사진/동영상 위에 오버레이로 올릴 때(대비가 낮아지므로) 배경에 맞는
  // 색을 지정할 수 있게 한다 — 미찜 상태(투명한 고양이) 색.
  final Color unfavoritedColor;
  // 찜 상태(색칠된 고양이) 색.
  final Color favoritedColor;
  // false면 아이콘 뒤 그림자/글로우 없이 고양이 자체만 남긴다(사진·동영상
  // 위 오버레이처럼 다른 버튼과 나란히 놓여 그림자가 지저분해 보이는 곳).
  final bool glow;

  const FavoriteStarButton({
    super.key,
    required this.itemType,
    required this.itemId,
    this.size = 25,
    this.dense = false,
    this.unfavoritedColor = PartyChuColors.primary,
    this.favoritedColor = PartyChuColors.primary,
    this.glow = true,
  });

  @override
  State<FavoriteStarButton> createState() => _FavoriteStarButtonState();
}

class _FavoriteStarButtonState extends State<FavoriteStarButton>
    with TickerProviderStateMixin {
  bool _isProcessing = false;
  bool _pressed = false;
  // 찜을 "켤" 때 고양이발이 통통 튀는 연출 — 1.0 → 1.25 → 1.0.
  late final AnimationController _burstCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  // 찜을 "끌" 때는 반대로 살짝 움츠렸다 돌아온다 — 1.0 → 0.88 → 1.0.
  // 켤 때보다 짧고 작아서 "취소했구나" 정도로만 읽힌다.
  late final AnimationController _dipCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  // toggleFavorite()이 성공한 직후 즉시 반영하는 낙관적(optimistic) 상태 —
  // Firestore 실시간 스트림이 몇 프레임 늦게 따라와도(네트워크 지연 등)
  // 버튼을 누르는 순간 바로 아이콘이 바뀌어야 "눌러도 반응이 없다"는
  // 느낌이 들지 않는다. 스트림이 이 값과 같아지면(서버에도 반영 확인)
  // 다시 스트림에 맡기고 비워서, 다른 기기에서 바뀐 상태도 계속 반영된다.
  bool? _localOverride;

  Future<void> _toggle() async {
    if (_isProcessing) return; // 중복 클릭/로딩 중 재진입 방지
    debugPrint(
      '[FavoriteStarButton] tap: type=${widget.itemType} itemId=${widget.itemId} '
      'userId=${UserSession.userId}',
    );
    setState(() => _isProcessing = true);

    try {
      if (UserSession.userId.isEmpty) {
        final shouldLogin = await showLoginRequiredDialog(
          context,
          message: '찜 기능을 사용하려면 로그인이 필요합니다.',
        );
        if (!shouldLogin || !mounted) return;

        // ⚠️ 로그인 화면으로 이동만 하고 여기서 끝낸다 — 이전엔 이 push가
        // 끝나기를 기다렸다가 곧바로 찜 토글까지 이어서 실행했는데, 로그인
        // 화면의 Future는 "사용자가 이 화면으로 실제로 돌아온 시점"과 다를 수
        // 있다. 미인증 계정이면 로그인 직후 루트 게이트가 본인확인 화면으로
        // 갈아끼우며 쌓여 있던 화면을 통째로 걷어내는데(main.dart), 그때
        // 이어서 실행하면 사용자가 본인확인 화면을 보고 있는 동안 화면 밖에서
        // 조용히 찜이 걸렸다 풀렸다 한다(다음에 다시 눌렀을 때 "반응이 없는"
        // 것처럼 보이거나, 열어보면 누른 적 없는데 이미 찜된 것처럼 보이는
        // 원인). 자동으로 이어서 실행하지 않고, 이 화면에 실제로 돌아왔을 때
        // 사용자가 다시 눌러야 찜이 걸리게 한다.
        await Navigator.push(context, webFramedRoute((_) => LoginPage()));
        return;
      }

      final newState = await FavoritesService.toggleFavorite(
        widget.itemType,
        widget.itemId,
      );
      debugPrint('[FavoriteStarButton] toggle 성공: 새 상태=$newState');
      if (mounted) setState(() => _localOverride = newState);
      // 시각·소리 피드백은 **저장이 끝난 이 지점에서만** 낸다 — 위 await가
      // 예외 없이 돌아왔다는 것은 Firestore 쓰기가 끝났다는 뜻이고, 실패하면
      // catch로 빠져 여기까지 오지 않는다.
      if (!mounted) return;
      if (newState) {
        _burstCtrl.forward(from: 0);
        FavoritePopFeedback.showFavorited(
          context,
          color: widget.favoritedColor,
        );
        // 찜 등록에만 소리를 낸다(해제는 시각 효과만).
        UiSound.favoritePop();
      } else {
        _dipCtrl.forward(from: 0);
        FavoritePopFeedback.showUnfavorited(context);
      }
    } catch (e, st) {
      logFirestoreStreamError(
        'FavoriteStarButton.toggle(${widget.itemType}, ${widget.itemId})',
        e,
        st,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('찜 처리에 실패했어요. 다시 시도해주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _burstCtrl.dispose();
    _dipCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: FavoritesService.watchFavorited(widget.itemType, widget.itemId),
      builder: (context, snapshot) {
        // 스트림이 로컬에서 방금 토글한 값을 따라잡았으면 override는 더 이상
        // 필요 없다 — 다음 프레임에 비워서 이후엔 다시 스트림을 그대로 신뢰한다.
        if (_localOverride != null && snapshot.data == _localOverride) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _localOverride = null);
          });
        }
        final isFav = _localOverride ?? snapshot.data ?? false;
        final accentColor = isFav
            ? widget.favoritedColor
            : widget.unfavoritedColor;

        return Tooltip(
          message: isFav ? '관심 해제' : '관심 등록',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _isProcessing
                ? null
                : (_) => setState(() => _pressed = true),
            onTapUp: _isProcessing
                ? null
                : (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: _isProcessing ? null : _toggle,
            child: Padding(
              padding: widget.dense ? EdgeInsets.zero : const EdgeInsets.all(6),
              child: AnimatedBuilder(
                animation: Listenable.merge([_burstCtrl, _dipCtrl]),
                builder: (context, _) {
                  final burstT = _burstCtrl.value;
                  final burstFade = 1 - burstT;
                  // 찜을 켠 직후: 1.0에서 시작해 한 번 1.25까지 부풀었다가
                  // 다시 1.0으로 — sin 반주기라 시작과 끝이 정확히 1.0이다.
                  // 끌 때는 같은 곡선을 반대 방향으로 더 작게 쓴다(0.88).
                  final popScale = isFav
                      ? 1.0 + math.sin(burstT * math.pi) * 0.25
                      : 1.0 - math.sin(_dipCtrl.value * math.pi) * 0.12;
                  final glowAlpha =
                      (0.18 +
                              (_pressed ? 0.35 : 0.0) +
                              burstFade * 0.35 * burstT.sign)
                          .clamp(0.0, 0.9);
                  final glowBlur =
                      6.0 +
                      (_pressed ? 6.0 : 0.0) +
                      burstFade * 10.0 * burstT.sign;
                  return AnimatedScale(
                    scale: _pressed ? 0.9 : popScale,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    child: Opacity(
                      opacity: _isProcessing ? 0.6 : 1.0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: widget.glow
                              ? [
                                  const BoxShadow(
                                    color: Color(0x1F000000),
                                    blurRadius: 2.5,
                                  ),
                                  BoxShadow(
                                    color: accentColor.withValues(
                                      alpha: glowAlpha,
                                    ),
                                    blurRadius: glowBlur,
                                    spreadRadius: 0.4,
                                  ),
                                ]
                              : null,
                        ),
                        // 관심 목록과 같은 고양이 발바닥 — 미찜은 투명하게,
                        // 찜하면 같은 자리에서 색이 꽉 찬다.
                        child: Icon(
                          Icons.pets,
                          size: widget.size,
                          // 미찜은 0.55 — 더 흐리게 하면 사진 위 오버레이
                          // (흰 고양이, glow:false라 그림자도 없다)에서 밝은
                          // 사진을 만났을 때 버튼이 있는지조차 안 보인다.
                          color: accentColor.withValues(
                            alpha: isFav ? 1.0 : 0.55,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
