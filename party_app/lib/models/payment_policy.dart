// 정의는 packages/partychu_sales로 옮겼다 — 호스트 앱과 관리자 웹이 매출
// 계산의 **같은 정본**을 쓰게 하기 위해서다(한쪽만 규칙이 바뀌는 일을 막는다).
//
// 이 파일은 기존 import 경로를 그대로 살려 두는 re-export shim이다. 호출부는
// 지금까지처럼 `package:party_app/models/payment_policy.dart`를 쓰면 된다.
export 'package:partychu_sales/src/payment_policy.dart';
