import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/utils/profanity_filter.dart';
import 'package:party_app/utils/user_session.dart';

/// 닉네임 유효성 검사 + Firestore 저장.
/// 규칙: 2~12자, 앞뒤 공백 제거, 연속 공백은 1개로 축소, 욕설 필터 통과.
/// 중복 닉네임은 허용한다(중복 검사하지 않음).
class NicknameService {
  NicknameService._();

  static const int minLength = 2;
  static const int maxLength = 12;

  /// 앞뒤 공백 제거 + 연속 공백을 1개로 축소.
  static String sanitize(String input) =>
      input.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// 유효하면 null, 아니면 사용자에게 보여줄 에러 메시지를 반환한다.
  static String? validate(String raw) {
    final v = sanitize(raw);
    if (v.length < minLength || v.length > maxLength) {
      return '닉네임은 $minLength~$maxLength자로 입력해주세요.';
    }
    if (ProfanityFilter.containsProfanity(v)) {
      return '사용할 수 없는 표현이 포함되어 있어요.';
    }
    return null;
  }

  /// 검증 후 Firestore users/{uid} 문서에 저장하고 UserSession도 갱신한다.
  /// 유효하지 않으면 [validate]가 반환한 메시지로 [StateError]를 던진다.
  static Future<void> save(String raw) async {
    final error = validate(raw);
    if (error != null) throw StateError(error);
    final nickname = sanitize(raw);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(UserSession.userId)
        .set({'nickname': nickname}, SetOptions(merge: true));
    UserSession.nickname = nickname;
  }
}
