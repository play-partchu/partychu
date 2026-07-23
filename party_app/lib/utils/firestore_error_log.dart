import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// StreamBuilder/FutureBuilder의 Firestore 쿼리 에러를 원인 판단이 바로
/// 되도록 code/message/stack을 나눠서 찍는다.
///
/// 색인 누락(FAILED_PRECONDITION, 콘솔 색인 생성 링크가 message에 포함됨)과
/// 권한 거부(PERMISSION_DENIED)는 증상(빈 목록/무한 로딩)이 똑같아 보이지만
/// 원인은 완전히 다르므로, 매번 이 코드/메시지를 직접 봐야 구분할 수 있다.
void logFirestoreStreamError(String tag, Object? error, StackTrace? stack) {
  final code = error is FirebaseException ? error.code : 'unknown';
  final message = error is FirebaseException ? error.message : error?.toString();
  debugPrint(
    '[$tag]\n'
    'code: $code\n'
    'message: $message\n'
    'stack: $stack',
  );
}
