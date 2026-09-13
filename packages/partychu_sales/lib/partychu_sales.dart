// ─────────────────────────────────────────────────────────────────────────────
// partychu_sales — **결제 상태와 매출 계산의 정본**.
//
// 호스트 앱(party_app)과 관리자 웹(admin_app)이 이 패키지 하나를 함께 쓴다.
// 두 화면이 같은 신청/예약 문서를 보고 **반드시 같은 숫자**를 내야 하기
// 때문이다 — 호스트 화면의 이번 달 총수익이 320,000원이면 관리자가 같은
// 호스트·같은 기간을 조회했을 때도 정확히 320,000원이어야 한다.
//
// 그래서 여기에는 계산에 필요한 것만 들어온다:
//   payment_method / payment_status  결제수단·결제상태 (네 도메인 공용)
//   payment_policy                   예약금 결제의 금액 분해·스냅샷
//   host_sales_stats                 매출 포함 판정과 일자별 집계
//   sales_entry_mapper               문서 → 집계 입력 변환 (금액 정본 선택)
//
// **의존성은 flutter 하나뿐이다.** cloud_firestore를 넣지 않는다 — 관리자
// 웹은 문서를 콜러블로 받아 오므로 Firestore 타입을 몰라야 하고, 계산 규칙을
// 어느 앱의 데이터 접근 방식에도 묶지 않기 위해서다.
//
// party_app의 기존 경로(`package:party_app/models/payment_status.dart` 등)는
// 이 패키지를 다시 내보내는 한 줄짜리 shim으로 남겨 뒀다 — 호출부 수십 곳을
// 건드리지 않으면서 정의는 한 곳에만 있게 하기 위한 것이다.
// ─────────────────────────────────────────────────────────────────────────────

export 'src/host_sales_stats.dart';
export 'src/payment_method.dart';
export 'src/payment_policy.dart';
export 'src/payment_status.dart';
export 'src/sales_entry_mapper.dart';
