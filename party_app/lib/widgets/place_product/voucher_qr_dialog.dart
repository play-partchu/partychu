import 'package:flutter/material.dart';

import 'package:party_app/models/check_in_pass.dart';
import 'package:party_app/models/check_in_result.dart' show CheckInDomain;
import 'package:party_app/models/place_product.dart';
import 'package:party_app/services/place_product_service.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/check_in_qr_card.dart';
import 'package:party_app/widgets/place_product/place_product_card.dart'
    show comma;

/// 구매자에게 보여주는 QR 이용권.
///
/// 그리는 것은 **파티·예약과 같은 공용 카드**다([CheckInQrCard]) — 예전에는
/// 이용권만 전용 다이얼로그를 갖고 있었는데, 파티·예약에도 QR이 생긴 이상
/// 세 벌을 유지하면 "한 번 쓰면 끝" 같은 안내가 한쪽에만 붙는다. 이 함수는
/// 주문 문서를 [CheckInPass] 한 벌로 옮기는 일만 한다.
///
/// ── QR에 실리는 값 ─────────────────────────────────────────────────────────
/// [PlaceProductOrder.checkInToken]이 있으면 그것, 없으면 예전처럼
/// `voucherCode`다. 두 값의 뜻은 섞이지 않는다 —
///
///   · checkInToken  이 이용 건을 조회하기 위한 QR 식별자. 현장결제 주문은
///                   **결제 전에도** 갖는다(functions/productCheckIn.js).
///   · voucherCode   결제가 확인된 뒤 생기는 이용권 코드. 무통장입금·옛 주문은
///                   지금도 이 값이 QR이다(통합 스캐너가 그 코드로도 주문을
///                   찾아 주므로 이미 뿌린 QR을 다시 뿌리지 않아도 된다).
///
/// 토큰을 앞에 두는 덕에 **결제 전후로 QR이 바뀌지 않는다** — 호스트가 스캔하고,
/// 결제를 확인하고, 같은 화면에서 다시 조회해 사용 처리까지 가는 동안 손님은
/// 화면을 새로 열 필요가 없다.
///
/// **QR 캡처본으로는 두 번 쓸 수 없다.** 사용 처리는 서버 트랜잭션 안에서
/// 상태를 `usable → used`로 한 번만 바꾸므로, 같은 이미지를 다시 보여줘도
/// 두 번째 스캔은 "이미 사용한 이용권"으로 막힌다. 즉 이 화면은 코드를
/// 보여주기만 할 뿐 유효성을 스스로 판단하지 않는다.
Future<void> showVoucherQrDialog(
  BuildContext context,
  PlaceProductOrder order,
) => showCheckInQrSheet(context, voucherPass(order));

/// 이용권 주문 → 공용 QR 한 벌.
CheckInPass voucherPass(PlaceProductOrder order) {
  final used = order.status == PlaceProductOrderStatus.used;
  // 결제가 남아 있으면 QR은 "조회용"이다 — 보여줘도 아직 통과하지 않는다.
  final unpaid = !used && !order.isPaid;
  return CheckInPass(
    domain: CheckInDomain.voucher,
    token: order.checkInToken.isNotEmpty
        ? order.checkInToken
        : order.voucherCode,
    title: order.productName,
    subtitle: order.placeName,
    // 좌석권·입장권은 이용 예정일이 있고, 기간제 이용권은 만료일만 있다.
    at: order.useAt,
    endAt: order.useEndAt,
    personName: UserSession.name,
    itemLabel: '${order.quantity}개',
    statusLabel: used
        ? '사용 완료'
        : unpaid
        ? '현장결제 예정'
        : order.status.label,
    state: used
        ? CheckInPassState.used
        : unpaid
        ? CheckInPassState.pending
        : CheckInPassState.ready,
    notice: unpaid
        ? '이 QR을 보여주고 ${comma(order.totalPrice)}원을 결제하면 이용권이 발급돼요.'
        : '한 번 사용하면 다시 사용할 수 없어요.',
  );
}
