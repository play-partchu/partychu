// ─────────────────────────────────────────────────────────────────────────────
// 등록을 시작하기 **전에** 한 번 보여주는 파티츄 호스트 안내.
//
// ── 왜 등록 유형 화면 앞에 두는가 ────────────────────────────────────────────
// 하단 '등록' 탭을 누르면 곧장 "무엇을 등록할까요?"(유형 카드 목록)가 떴다.
// 처음 오는 사장님에게 그 화면은 **이미 등록하기로 마음먹은 사람용**이라,
// "파티츄에 올리면 나에게 뭐가 좋은데?"라는 앞 단계 질문에는 아무 답도 하지
// 않는다. 그 한 걸음을 여기서 채운다.
//
// ── 노출 자리는 하나뿐이다 ───────────────────────────────────────────────────
// **최상위 '등록' 탭**([MainScreen._goToRegisterScreen])에서만 뜬다. 등록 유형
// 화면·이벤트/파티 선택·플레이스 등록·수정 화면은 이 함수를 거치지 않으므로,
// 등록 과정 안에 들어와 있는 사람에게 같은 안내가 다시 뜨는 일이 없다.
//
// ── 생김새는 새로 만들지 않았다 ──────────────────────────────────────────────
// 알림 권한 안내 시트([PushPermissionSheet])와 **같은 모양**이다 — 흰 바텀시트,
// 위 모서리 20, 동그란 아이콘 배지, 제목·설명, 핑크 주 버튼.
// 이 앱에서 "설명하고 한 번 물어보는 시트"는 이미 그 모양이라, 여기서 다른
// 모양을 만들면 같은 성격의 팝업이 화면마다 달라진다.
//
// 버튼은 '등록 시작하기' **하나뿐**이다. 예전에는 그 아래 '다음에 할게요'
// 텍스트 버튼이 하나 더 있었는데, 시트를 그냥 닫는 길(뒤로가기·스와이프·바깥
// 탭)이 이미 있어서 같은 행동으로 가는 문이 둘이었다. 문을 하나로 줄여도
// 닫는 방법은 하나도 줄지 않는다 — 닫으면 [show]가 false를 돌려주는 것도
// 그대로다.
//
// ⚠️ 문구는 **지금 정책 그대로**만 적는다.
//    · 비용 — "등록비·중개 수수료 없이". '수수료 0원'처럼 영구 무료를 약속하는
//      말은 쓰지 않는다(등록 화면의 [kPartychuOpenEventNoCharge]와 같은 톤).
//    · 결제 — 무통장입금·현장결제뿐이다. 카드·간편결제가 되는 것처럼 읽히는
//      말을 넣지 않는다([ProductRefundFeature] 상단 주석과 같은 사실).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

const Color _kPink = Color(0xFFFF6FA0);
const Color _kPinkBg = Color(0xFFFFE0EE);

/// 안내 시트에 한 줄로 서는 혜택 하나.
class _Benefit {
  const _Benefit(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

class HostRegisterInviteSheet extends StatelessWidget {
  const HostRegisterInviteSheet({super.key});

  /// 핵심 혜택 — **넷까지**다. 더 늘리면 한눈에 읽히지 않고, 그 순간 이 시트는
  /// 등록으로 가는 길이 아니라 읽을거리가 된다.
  ///
  /// 순서에 뜻이 있다: 먼저 "돈이 안 든다"로 문턱을 치우고, 무엇을 할 수 있는지
  /// 둘(매장·파티)을 보여준 뒤, 마지막에 "혼자 알리는 게 아니다"로 닫는다.
  static const List<_Benefit> _benefits = [
    _Benefit(Icons.payments_outlined, '수수료 없이 등록', '등록비·중개 수수료 없이 시작할 수 있어요.'),
    _Benefit(
      Icons.storefront_outlined,
      '매장 홍보 & 이벤트 운영',
      '매장 정보와 혜택을 알리고 다양한 이벤트를 등록할 수 있어요.',
    ),
    _Benefit(
      Icons.celebration_outlined,
      '파티·공연으로 손님 모집',
      '참가자를 모집하거나 공연·행사 티켓을 판매할 수 있어요.',
    ),
    _Benefit(
      Icons.campaign_outlined,
      '파티츄가 함께 홍보해요',
      '등록한 매장과 파티를 파티츄가 다양한 채널을 통해 함께 알려드려요.',
    ),
  ];

  /// 사용자가 '등록 시작하기'를 눌렀으면 true — 시트를 그냥 닫으면(뒤로가기·
  /// 스와이프·바깥 탭) 결과가 null이라 false다.
  ///
  /// 호출부는 true일 때만 기존 등록 흐름으로 넘어간다 — 이 시트는 **묻기만**
  /// 하고 등록 로직에는 관여하지 않는다.
  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const HostRegisterInviteSheet(),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // 아래 여백 20 — 보조 버튼('다음에 할게요')이 쓰던 자리를 그대로
        // 비워 두면 주 버튼 아래가 휑하고, 16 그대로면 화면 끝에 붙는다.
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
        // 작은 화면·큰 글꼴 설정에서도 버튼이 화면 밖으로 밀리지 않게 한다.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: _kPinkBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    size: 30,
                    color: _kPink,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '🎉 파티츄에서 손님을 만나보세요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                '등록비·중개 수수료 없이 매장을 알리고, 이벤트와 파티를 열어 '
                '새로운 손님을 모아보세요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.black54,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 20),
              for (final b in _benefits) _benefitRow(b),
              const SizedBox(height: 14),
              _paymentNote(),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '등록 시작하기',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _benefitRow(_Benefit b) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _kPinkBg,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(b.icon, size: 18, color: _kPink),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                b.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                b.body,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  /// 결제 방식은 혜택이 아니라 **사실 안내**라 혜택 줄과 다르게, 작게 둔다.
  /// 지금 되는 것만 적는다 — 여기에 다른 수단을 적으면 등록을 마친 호스트가
  /// 있지도 않은 결제수단을 기다리게 된다.
  Widget _paymentNote() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F7FA),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              size: 15,
              color: Colors.black45,
            ),
            const SizedBox(width: 5),
            Text(
              '현재 결제 방식',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '무통장입금 · 현장결제를 지원해요.',
          style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.5),
        ),
      ],
    ),
  );
}
