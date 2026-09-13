import 'package:cloud_functions/cloud_functions.dart';

/// 대표자 위임 — **본인 명의가 아닌 사업자**를 대표자 승인으로 여는 경로.
///
/// 앱이 하는 일은 두 가지뿐이다: 승인 요청을 만들고, 받은 링크를 대표자에게
/// 전달하도록 돕는 것. **판정은 하나도 하지 않는다** — 승인 여부는 대표자가
/// NICE 본인확인을 마친 뒤 서버가 12개 검사를 거쳐 정한다
/// (functions/businessDelegation.js의 evaluateApproval).
///
/// ⚠️ **승인 링크를 가진 것은 권한이 아니다.** 링크는 "어느 요청인가"만
///    지시하고, 링크를 가로챈 사람이라도 국세청에 등록된 대표자명 그대로
///    NICE를 통과하지 못하면 아무것도 할 수 없다. 그래서 앱이 이 링크를
///    평범한 공유 링크처럼 다뤄도 안전하다.
class BusinessDelegationService {
  BusinessDelegationService._();

  static const _region = 'asia-northeast3';

  static HttpsCallable _fn(String name) =>
      FirebaseFunctions.instanceFor(region: _region).httpsCallable(name);

  /// 승인 요청을 만들고 **일회성 링크**를 받는다.
  ///
  /// 같은 계정의 이전 요청은 서버가 만료시킨다 — 살아 있는 링크는 항상 하나다.
  /// 실패 시 [FirebaseFunctionsException]을 그대로 던진다(서버가 한국어 안내
  /// 문구로 던지므로 화면은 message를 그대로 보여주면 된다).
  static Future<DelegationRequest> request() async {
    final res = await _fn(
      'requestBusinessDelegation',
    ).call<Map<String, dynamic>>({});
    return DelegationRequest(
      delegationId: res.data['delegationId'] as String? ?? '',
      approvalUrl: res.data['approvalUrl'] as String? ?? '',
      businessNumberMasked: res.data['businessNumberMasked'] as String? ?? '',
      expiresAt: _ms(res.data['expiresAtMs']),
    );
  }

  /// 가장 최근 요청의 진행 상태. **링크는 돌려주지 않는다** — 한 번 받은
  /// 링크를 잃어버렸으면 새로 요청해야 한다(그 편이 안전하다).
  static Future<DelegationStatusInfo> status() async {
    try {
      final res = await _fn(
        'getBusinessDelegationStatus',
      ).call<Map<String, dynamic>>({});
      if (res.data['exists'] != true) return DelegationStatusInfo.none;
      return DelegationStatusInfo(
        status: DelegationStatus.fromKey(res.data['status'] as String?),
        businessNumberMasked: res.data['businessNumberMasked'] as String? ?? '',
        expiresAt: _ms(res.data['expiresAtMs']),
      );
    } catch (_) {
      // 상태 조회 실패가 화면을 막지 않는다 — 요청 버튼은 그대로 쓸 수 있다.
      return DelegationStatusInfo.none;
    }
  }

  static DateTime? _ms(dynamic v) =>
      v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
}

/// 위임의 생애 — 서버(businessDelegation.js STATUS)와 같은 값이다.
enum DelegationStatus {
  /// 아직 요청한 적이 없다.
  none('', ''),

  /// 링크를 발급했고 대표자의 본인확인을 기다린다.
  requested('requested', '대표자 승인 대기 중'),

  /// 대표자가 승인했다 — 이 계정에 운영 권한이 열렸다.
  approved('approved', '승인 완료'),

  /// 대표자가 거절했다.
  rejected('rejected', '대표자가 거절했어요'),

  /// 유효기간이 지났거나 새 요청으로 대체됐다.
  expired('expired', '만료됨'),

  /// 대표자가 부여했던 권한을 취소했다.
  revoked('revoked', '대표자가 권한을 취소했어요');

  const DelegationStatus(this.key, this.label);

  final String key;
  final String label;

  static DelegationStatus fromKey(String? key) {
    for (final s in DelegationStatus.values) {
      if (s.key == key && s != DelegationStatus.none) return s;
    }
    return DelegationStatus.none;
  }
}

class DelegationRequest {
  const DelegationRequest({
    required this.delegationId,
    required this.approvalUrl,
    required this.businessNumberMasked,
    this.expiresAt,
  });

  final String delegationId;

  /// 대표자에게 전달할 승인 링크. **한 번만 내려온다** — 서버는 원문을
  /// 저장하지 않고 해시만 갖고 있다.
  final String approvalUrl;
  final String businessNumberMasked;
  final DateTime? expiresAt;
}

class DelegationStatusInfo {
  const DelegationStatusInfo({
    required this.status,
    this.businessNumberMasked = '',
    this.expiresAt,
  });

  final DelegationStatus status;
  final String businessNumberMasked;
  final DateTime? expiresAt;

  static const none = DelegationStatusInfo(status: DelegationStatus.none);

  bool get isWaiting => status == DelegationStatus.requested;
}
