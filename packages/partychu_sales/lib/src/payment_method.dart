import 'package:flutter/material.dart';

/// 파티츄가 다루는 **결제수단** — 파티 신청·플레이스 예약·장소대여·파티샵
/// 주문이 이 목록 하나를 함께 쓴다.
///
/// 지금은 PG 계약 전이라 **무통장입금·현장결제만** 실제로 고를 수 있고 나머지는
/// '준비중'으로 보여주기만 한다([available]). PG가 붙으면 해당 값의
/// `available`을 true로 바꾸는 것만으로 화면 네 곳이 동시에 열린다 — 화면 쪽에는
/// 어떤 수단이 켜져 있는지에 대한 분기를 두지 않는다.
///
/// ⚠ 준비중인 수단에는 **결제 로직이 아예 없다**. 가짜 성공 응답을 만들거나
///   PG를 흉내 내지 않는다(그렇게 하면 "결제됐다"는 잘못된 상태가 실제 주문에
///   남는다).
enum PaymentMethod {
  /// 계좌로 직접 입금 — 입금이 확인돼야 확정된다.
  bankTransfer(
    key: 'bank_transfer',
    label: '무통장입금',
    description: '계좌로 입금 후 확인되면 확정돼요',
    icon: Icons.account_balance_rounded,
    available: true,
  ),

  /// 현장에서 결제 — 방문해서 결제한다.
  onSite(
    key: 'on_site',
    label: '현장결제',
    description: '방문해서 현장에서 결제해요',
    icon: Icons.storefront_rounded,
    available: true,
  ),

  card(
    key: 'card',
    label: '카드결제',
    description: '신용·체크카드',
    icon: Icons.credit_card_rounded,
    available: false,
  ),

  transfer(
    key: 'transfer',
    label: '실시간 계좌이체',
    description: '은행 계좌에서 바로 이체',
    icon: Icons.swap_horiz_rounded,
    available: false,
  ),

  virtualAccount(
    key: 'virtual_account',
    label: '가상계좌',
    description: '1회용 계좌를 발급받아 입금',
    icon: Icons.receipt_long_rounded,
    available: false,
  ),

  easyPay(
    key: 'easy_pay',
    label: '간편결제',
    description: '카카오페이 · 네이버페이 · 토스페이 등',
    icon: Icons.bolt_rounded,
    available: false,
  );

  const PaymentMethod({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.available,
  });

  /// 문서에 저장하는 값 — 화면 표기(label)가 바뀌어도 데이터는 그대로다.
  final String key;

  final String label;

  /// 목록에서 라벨 아래 한 줄로 붙는 설명.
  final String description;

  final IconData icon;

  /// 지금 실제로 고를 수 있는지. false면 '준비중'으로만 보인다.
  final bool available;

  /// 준비중 안내 — 눌렀을 때 딱 이만큼만 알려준다.
  static const String notReadyMessage = '현재 준비 중인 결제수단입니다.';

  static PaymentMethod? fromKey(String? key) {
    if (key == null) return null;
    for (final m in values) {
      if (m.key == key) return m;
    }
    return null;
  }

  /// 지금 고를 수 있는 수단들 / 준비중인 수단들 — 화면은 이 두 묶음만 그린다.
  static List<PaymentMethod> get usable =>
      values.where((m) => m.available).toList();
  static List<PaymentMethod> get preparing =>
      values.where((m) => !m.available).toList();
}

/// 무통장입금 **기한**.
///
/// 예전에는 이 자리에 파티츄 공용 입금계좌 상수(카카오뱅크 3333-…)도 함께
/// 있었다. 그 계좌는 없앴다 — 참가비는 파티츄가 아니라 **그 콘텐츠 호스트가
/// 직접** 받고(users/{uid}.payoutAccount), 안내 계좌는 신청·예약·주문이 만들어질
/// 때 서버가 호스트의 인증된 계좌로 문서에 박아 준다
/// ([PaymentInfo.bankAccount] · functions/payoutAccounts.js).
///
/// 그래서 앱에는 계좌 상수가 **하나도 없어야 한다** — 상수가 남아 있으면 계좌를
/// 등록하지 않은 호스트의 결제에서 엉뚱한 계좌가 폴백으로 다시 뜬다.
class DepositWindow {
  DepositWindow._();

  /// 입금기한 — 신청 시각부터 이만큼 안에 입금해야 한다.
  static const Duration duration = Duration(days: 1);

  static DateTime deadlineFrom(DateTime now) => now.add(duration);
}
