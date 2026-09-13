import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:party_app/models/party_application_form.dart';

/// 파티의 **승인 방식 + 사전질문** 저장.
///
/// 이 두 필드만은 파티 문서의 다른 값들과 달리 앱이 Firestore에 직접 쓰지
/// 못한다(firestore.rules에서 막혀 있다). "개인정보를 요구하는 질문은 등록을
/// 막는다"가 UI 검사만으로는 성립하지 않기 때문이다 — 앱을 거치지 않고 문서에
/// 직접 쓰면 그만이라, 금지 판정이 실제 강제력을 가지려면 쓰기 경로 자체가
/// 서버여야 한다. (openState → openPartyRecruiting과 같은 패턴)
///
/// 등록 화면과 수정 화면이 같은 함수를 쓴다 — 한쪽만 고쳐서 두 화면의 저장
/// 동작이 갈라지는 일이 없게.
class PartyApplicationFormService {
  const PartyApplicationFormService._();

  /// 여러 날짜 문서에 같은 설정을 저장한다.
  ///
  /// 파티 문서는 이미 저장된 뒤에 불린다 — 여기서 실패해도 "등록 실패"로
  /// 되돌리지 않는다(사용자가 같은 파티를 또 등록하게 된다). 실패한 사유만
  /// 돌려주고, 호출부가 안내한다.
  ///
  /// 되돌려주는 값이 null이면 전부 성공이다.
  static Future<String?> save({
    required List<String> partyIds,
    required PartyApprovalMode mode,
    required List<PartyApplicationQuestion> questions,
    required bool requirePhotos,
  }) async {
    if (partyIds.isEmpty) return null;
    // 즉시확정이면 질문을 보내지 않는다 — 서버도 같은 판단으로 정의를 비운다.
    final payloadQuestions = mode == PartyApprovalMode.manual
        ? [for (var i = 0; i < questions.length; i++) questions[i].toMap(i)]
        : const <Map<String, dynamic>>[];

    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-northeast3',
    ).httpsCallable('setPartyApplicationForm');

    for (final id in partyIds) {
      try {
        await callable.call({
          'partyId': id,
          'approvalMode': mode.key,
          'questions': payloadQuestions,
          // 즉시확정이면 사진 요청도 꺼진다 — 서버도 같은 판단을 한다.
          kRequireApplicantPhotosField:
              mode == PartyApprovalMode.manual && requirePhotos,
        });
      } on FirebaseFunctionsException catch (e) {
        debugPrint(
          '[ApplicationForm] 저장 실패 partyId=$id: ${e.code} ${e.message}',
        );
        return e.message ?? '신청 방식을 저장하지 못했어요.';
      } catch (e) {
        debugPrint('[ApplicationForm] 저장 실패 partyId=$id: $e');
        return '신청 방식을 저장하지 못했어요.';
      }
    }
    return null;
  }
}
