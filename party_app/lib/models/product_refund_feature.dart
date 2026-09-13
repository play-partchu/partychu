/// 상품·이용권(placeProducts)의 **환불 UX를 사용자에게 보일지**를 정하는
/// 단 하나의 스위치.
///
/// ── 왜 지우지 않고 감추는가 ───────────────────────────────────────────────
/// 지금 받을 수 있는 결제수단은 무통장입금·현장결제뿐이고, 그 돈은 파티츄가
/// 아니라 **호스트 계좌로 바로** 들어간다. 그런데 상품 주문 쪽에는 돌려주는
/// 절차가 아직 없다 — `cancelProductOrder`가 상태를 `refunded`로 바꾸기만 하고
/// (functions/placeProductOrders.js), 파티 취소와 달리
///
///   · `refundRequests` 문서를 만들지 않고,
///   · 게스트의 환불계좌를 받지 않고,
///   · 호스트에게 알림도, 처리할 목록도 주지 않는다.
///
/// 그래서 지금 이 UX를 열어 두면 "취소·환불 규정을 적게 하고, 그 규정대로
/// 처리된다고 안내한 뒤, 아무도 시작하지 않는" 상태가 된다. 기능이 틀린 게
/// 아니라 **아직 완성되지 않았을 뿐**이라 코드·필드·서버 경로는 그대로 두고
/// 화면에서만 내린다.
///
/// ── 무엇을 건드리지 않는가 (중요) ─────────────────────────────────────────
///   · `placeProducts.refundPolicy` 필드 — 읽지도 쓰지도 지우지도 않는다.
///     이미 값이 있는 문서는 그대로 저장되고 그대로 되살아난다.
///   · `placeProductOrders`의 `refunded` 상태와 서버의 취소 경로 — 그대로.
///   · `refundRequests` / `HostRefundService` / 파티 환불 흐름 — 그대로.
///     그쪽은 계좌 수집·호스트 알림·처리 목록까지 **완성된 흐름**이라 이
///     스위치의 범위가 아니다([enabled] 주석의 목록 참고).
///
/// ── 다시 켤 때 ────────────────────────────────────────────────────────────
/// [enabled]를 true로 바꾸면 아래 네 자리가 한 번에 돌아온다. 화면마다
/// `false`를 적어 두지 않은 이유가 이것이다 — 켜는 곳도 한 곳이어야 한다.
///
///   ① 상품 등록/수정 폼의 '취소·환불 규정' 입력칸
///      ([PlaceProductEditor])
///   ② 그 규정을 **필수로 요구하는 저장 게이트**
///      (event_register_screen · place_register_screen의 RegisterFieldCheck)
///   ③ 상품 구매 시트의 '취소·환불 규정' 안내
///      ([showPlaceProductPurchaseSheet])
///   ④ **결제가 끝난** 이용권의 '취소 요청' 버튼([VoucherCard])
///
/// ④만 조건이 하나 더 붙는다 — 아직 돈을 내지 않은 주문(입금대기·입금확인중·
/// 현장결제 예정)의 취소는 환불과 아무 상관이 없고, 막으면 게스트가 잘못 넣은
/// 주문을 물릴 방법이 사라지고 재고도 묶인다. 그래서 **미결제 취소는 항상
/// 열려 있다**([allowsCancel]).
library;

import 'package:party_app/models/place_product.dart';

class ProductRefundFeature {
  ProductRefundFeature._();

  /// 상품·이용권의 환불 UX를 사용자에게 보일지. **여기 한 곳만 바꾼다.**
  static const bool enabled = false;

  /// 결제가 끝난 이용권을 게스트가 스스로 취소할 수 있는가.
  ///
  /// 취소 = 환불 시작이므로 [enabled]를 그대로 따른다. 미결제 주문은 이
  /// 판정에 들어오지 않는다([allowsCancel]).
  static bool get allowsPaidCancel => enabled;

  /// 이 주문에 '취소 요청' 버튼을 보일지.
  ///
  ///   · 결제 전(payment_pending) — 언제나 보인다. 환불이 아니라 **주문 물리기**다.
  ///   · 결제 후(paid·usable)     — [allowsPaidCancel]일 때만.
  ///   · 그 밖(used·cancelled·refunded·expired) — 이미 끝난 주문이라 없다.
  static bool allowsCancel(PlaceProductOrderStatus status) {
    if (status == PlaceProductOrderStatus.paymentPending) return true;
    return allowsPaidCancel && status.isAlive;
  }

  /// 결제가 끝난 이용권에서 취소 버튼을 내렸을 때 대신 적는 한 줄.
  ///
  /// 버튼만 조용히 사라지면 게스트는 "취소할 방법이 없는" 화면을 보게 된다 —
  /// 실제로 취소·환불을 하려면 매장과 이야기해야 하므로 그렇게 말해 준다.
  static const String cancelHiddenGuide = '취소·환불은 매장에 문의해주세요.';
}
