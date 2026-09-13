import 'package:cloud_functions/cloud_functions.dart';
import 'package:party_app/utils/profanity_filter.dart';
import 'package:party_app/utils/user_session.dart';

/// 닉네임 규칙 + 저장.
///
/// ── 규칙은 서버(functions/nicknames.js)와 **글자 하나까지 같아야 한다** ────
/// 한쪽만 고치면 "앱에서는 저장되는데 서버가 거부하는"(또는 그 반대) 상태가 되고,
/// 사용자에게는 원인을 알 수 없는 실패로 보인다. 아래 상수·정규식·문구를 바꿀
/// 때는 반드시 nicknames.js의 같은 이름을 함께 바꾼다.
///
///   허용   : 완성형 한글(가-힣) · 영문 대소문자 · 숫자
///   불허   : 공백 · 특수문자 · 이모지 · 자모 단독(ㄱ, ㅏ …)
///   길이   : 2~12자 (코드포인트 기준)
///   정규화 : trim → NFC → (중복 판정용) 소문자
///
/// ── 저장은 **서버만 한다** ───────────────────────────────────────────────
/// 중복 방지는 `nicknames/{정규화}` 문서를 트랜잭션으로 선점해야 성립한다.
/// 앱이 users 문서를 직접 쓰면 두 사람이 동시에 같은 이름을 저장할 수 있어서,
/// firestore.rules가 users.nickname과 nicknames 컬렉션을 모두 잠갔다. 앱은
/// setNickname 콜러블만 부른다.
class NicknameService {
  NicknameService._();

  static const int minLength = 2;
  static const int maxLength = 12;

  /// 입력란 아래에 그대로 띄우는 안내.
  static const String charsetHint = '한글, 영문, 숫자만 사용할 수 있어요.';

  static const String takenMessage = '이미 사용 중인 닉네임이에요. 다른 닉네임을 입력해주세요.';

  /// 완성형 한글 + 영문 + 숫자만. 자모 단독(ㄱ-ㅎ, ㅏ-ㅣ)은 이 범위 밖이라
  /// 자연히 걸러진다 — 따로 검사할 필요가 없다.
  static final RegExp _allowed = RegExp(r'^[가-힣a-zA-Z0-9]+$');

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// 저장될 형태 — 앞뒤 공백만 제거하고 NFC로 맞춘다.
  ///
  /// **내부 공백을 지우거나 줄이지 않는다.** 예전에는 연속 공백을 하나로 줄여
  /// '냥 냥이'가 그대로 통과했다. 공백은 여기서 손보지 않고 [validate]가
  /// 거부한다 — 입력한 것과 다른 닉네임이 저장되면 안 된다.
  static String sanitize(String input) => input.trim();

  /// 중복 판정용 키. 대소문자를 구분하지 않으므로 `PartyChu` == `partychu`.
  /// 서버의 `normalize()`와 같은 값이어야 한다.
  static String normalize(String input) => sanitize(input).toLowerCase();

  /// 유효하면 null, 아니면 사용자에게 보여줄 메시지.
  ///
  /// 길이는 **코드포인트 기준**으로 센다(`runes`) — UTF-16 길이로 세면 이모지
  /// 하나가 2자로 잡혀 길이 규칙이 눈에 보이는 글자 수와 어긋난다.
  static String? validate(String raw) {
    final v = sanitize(raw);
    if (v.isEmpty) return '닉네임을 입력해주세요.';
    final len = v.runes.length;
    if (len < minLength || len > maxLength) {
      return '닉네임은 $minLength~$maxLength자로 입력해주세요.';
    }
    if (!_allowed.hasMatch(v)) return charsetHint;
    if (ProfanityFilter.containsProfanity(v)) {
      return '사용할 수 없는 표현이 포함되어 있어요.';
    }
    return null;
  }

  /// 입력 중 미리 확인 — 저장하지 않는다.
  ///
  /// 여기서 '사용 가능'이 나와도 저장 시점에 남이 먼저 가져갈 수 있다. 최종
  /// 판정은 언제나 [save]의 서버 트랜잭션이다.
  static Future<String?> checkAvailable(String raw) async {
    final error = validate(raw);
    if (error != null) return error;
    try {
      final res = await _fn
          .httpsCallable('checkNicknameAvailable')
          .call<Map<String, dynamic>>({'nickname': sanitize(raw)});
      final ok = res.data['available'] == true;
      return ok ? null : (res.data['reason'] as String? ?? takenMessage);
    } catch (_) {
      // 미리 확인에 실패했다고 입력을 막지는 않는다 — 저장 때 서버가 다시 본다.
      return null;
    }
  }

  /// 검증 후 서버에 저장하고 UserSession도 갱신한다.
  ///
  /// 규칙 위반이나 중복이면 사용자에게 보여줄 문구로 [StateError]를 던진다.
  static Future<void> save(String raw) async {
    final error = validate(raw);
    if (error != null) throw StateError(error);
    final nickname = sanitize(raw);
    try {
      await _fn.httpsCallable('setNickname').call<Map<String, dynamic>>({
        'nickname': nickname,
      });
    } on FirebaseFunctionsException catch (e) {
      // 서버가 돌려준 문구를 그대로 쓴다(중복·규칙 위반 모두 사용자용 문장이다).
      // 코드·stack trace는 화면에 내보내지 않는다.
      throw StateError(
        (e.message == null || e.message!.isEmpty)
            ? '닉네임을 저장하지 못했어요. 잠시 후 다시 시도해주세요.'
            : e.message!,
      );
    } catch (_) {
      throw StateError('닉네임을 저장하지 못했어요. 잠시 후 다시 시도해주세요.');
    }
    UserSession.nickname = nickname;
  }
}
