import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:party_app/login.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/login_required_dialog.dart';
import 'package:party_app/widgets/partychu_ui.dart' show PartyChuColors;
import 'package:party_app/widgets/web_frame.dart';

/// 파티/장소/파티샵/파트너 상세 화면에 공통으로 붙는 찜(관심) 토글 버튼.
/// 원형 배경 없이 하트 아이콘 하나로 표현한다 — 미찜은 테두리색만 있는 빈
/// 하트(Icons.favorite_border), 찜하면 같은 색으로 꽉 찬 하트(Icons.favorite)
/// 로 바뀌면서 살짝 팝(pop) 애니메이션이 재생된다.
class FavoriteStarButton extends StatefulWidget {
  final String itemType;
  final String itemId;
  final double size;
  // 목록 카드처럼 줄 높이가 작은 곳에 쓸 때 true — 기본 44dp 터치 영역 대신
  // 좁은 터치 영역을 써서 카드 높이가 늘어나지 않게 한다.
  final bool dense;
  // 사진/동영상 위에 오버레이로 올릴 때(대비가 낮아지므로) 배경에 맞는
  // 색을 지정할 수 있게 한다 — 미찜 상태 테두리 색.
  final Color unfavoritedColor;
  // 찜 상태(꽉 찬 하트) 색.
  final Color favoritedColor;
  // false면 아이콘 뒤 그림자/글로우 없이 하트 자체만 남긴다(사진·동영상
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
    with SingleTickerProviderStateMixin {
  bool _isProcessing = false;
  bool _pressed = false;
  // 찜을 "켤" 때만 짧게 팝(scale bounce)했다가 가라앉는 연출을 준다(찜
  // 해제 시에는 재생하지 않음).
  late final AnimationController _burstCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
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

        // ⚠️ 로그인 화면으로 이동만 하고 여기서 끝낸다 — 이전엔 여기서
        // Navigator.push(...)가 끝나기를 기다렸다가 곧바로 찜 토글까지 이어서
        // 실행했는데, 본인인증이 아직 안 된 계정이면 LoginPage._onLoginSuccess가
        // Navigator.pop이 아니라 pushReplacement로 IdentityVerificationScreen을
        // 띄운다 — 그러면 이 push의 Future가 "화면이 실제로 여기로 돌아온
        // 시점"이 아니라 "로그인 화면이 다른 화면으로 대체된 시점"에 이미
        // 끝나버려서, 사용자가 본인인증 화면을 보고 있는 동안 화면 밖에서
        // 조용히 찜이 걸렸다 풀렸다 했다(다음에 다시 눌렀을 때 "반응이 없는"
        // 것처럼 보이거나, 열어보면 누른 적 없는데 이미 찜된 것처럼 보이는
        // 원인). 자동으로 이어서 실행하지 않고 로그인/인증을 마치고 이 화면에
        // 실제로 돌아왔을 때 사용자가 다시 눌러야 찜이 걸리게 해서, 항상 이
        // 화면을 보고 있는 상태에서만 토글이 일어나게 한다.
        await Navigator.push(context, webFramedRoute((_) => LoginPage()));
        return;
      }

      final newState = await FavoritesService.toggleFavorite(
        widget.itemType,
        widget.itemId,
      );
      debugPrint('[FavoriteStarButton] toggle 성공: 새 상태=$newState');
      if (mounted) setState(() => _localOverride = newState);
      if (newState && mounted) _burstCtrl.forward(from: 0);
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
        final accentColor = isFav ? widget.favoritedColor : widget.unfavoritedColor;

        return Tooltip(
          message: isFav ? '관심 해제' : '관심 등록',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _isProcessing ? null : (_) => setState(() => _pressed = true),
            onTapUp: _isProcessing ? null : (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: _isProcessing ? null : _toggle,
            child: Padding(
              padding: widget.dense ? EdgeInsets.zero : const EdgeInsets.all(6),
              child: AnimatedBuilder(
                animation: _burstCtrl,
                builder: (context, _) {
                  final burstT = _burstCtrl.value;
                  final burstFade = 1 - burstT;
                  // 찜을 켠 직후에만 살짝 부풀었다 가라앉는 팝(pop) 곡선.
                  final popScale = isFav ? 1.0 + math.sin(burstT * math.pi) * 0.22 : 1.0;
                  final glowAlpha = (0.18 + (_pressed ? 0.35 : 0.0) + burstFade * 0.35 * burstT.sign)
                      .clamp(0.0, 0.9);
                  final glowBlur = 6.0 + (_pressed ? 6.0 : 0.0) + burstFade * 10.0 * burstT.sign;
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
                                  const BoxShadow(color: Color(0x1F000000), blurRadius: 2.5),
                                  BoxShadow(
                                    color: accentColor.withValues(alpha: glowAlpha),
                                    blurRadius: glowBlur,
                                    spreadRadius: 0.4,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          size: widget.size,
                          color: accentColor,
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
