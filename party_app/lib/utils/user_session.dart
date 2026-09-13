import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:party_app/utils/social_session.dart';
import 'package:party_app/services/push_notification_service.dart';

/// 사용자 프로필(`users/{uid}`) 읽기 상태.
///
/// 본인확인 여부를 "아직 못 읽었다"와 "읽어보니 미인증"으로 확실히 구분하기
/// 위해 둔다. 예전에는 둘 다 `identityVerified == false`로 보여서, 로그인 직후
/// 프로필이 아직 로딩 중이거나 읽기에 실패한 순간에 이미 본인확인을 마친
/// 사용자에게도 본인확인 화면이 떴다.
enum UserProfileLoad {
  /// 아직 한 번도 읽지 않음(로그아웃 직후 포함).
  none,

  /// 읽는 중.
  loading,

  /// 서버 값으로 채워짐 — 이때의 [UserSession.identityVerified]만 믿을 수 있다.
  loaded,

  /// 읽기 실패(네트워크/권한 등). 값은 이전 상태 그대로 두고 상태만 남긴다.
  failed,
}

/// **서버 기준** 본인확인 상태 — 루트 게이트가 첫 화면을 고르는 근거.
///
/// [UserProfileLoad]와 나눠 두는 이유: 게이트가 알고 싶은 것은 "프로필을
/// 읽었는가"가 아니라 "본인확인을 마쳤는가"이고, 그 둘 사이에는 캐시라는
/// 함정이 하나 더 있다([UserSession._loadedFromServer] 참고).
enum IdentityStatus {
  /// **확인하는 중** — 아직 읽어보지 않았거나 읽고 있다.
  ///
  /// [unknown]과 반드시 나눠야 한다. 로그인 버튼을 누른 직후가 정확히 이
  /// 상태인데(세션에 uid만 들어가고 프로필은 이제부터 읽는다), 이걸 '확인
  /// 실패'로 뭉뚱그리면 **정상 로그인 중에 실패 화면이 한 번 번쩍이고** 그
  /// 위에 떠 있던 로그인 화면까지 걷어내진다.
  checking,

  /// 확인하지 못했다 — 읽기 실패, 또는 오프라인 캐시로만 읽은 '미인증'.
  ///
  /// **인증으로도, 미인증으로도 취급하면 안 된다.** 인증으로 보면 미인증
  /// 계정이 네트워크를 끊는 것만으로 들어오고, 미인증으로 보면 인증을 마친
  /// 사용자가 일시적인 오류로 본인확인 화면에 갇힌다. 루트 게이트는 이 값을
  /// '확인 실패 화면(재시도·로그아웃)'으로 다룬다.
  unknown,

  /// 서버 값이 본인확인 완료.
  verified,

  /// **서버에서 읽어봤더니** 미완료.
  unverified,
}

class UserSession {
  static String _userId = '';
  // FirebaseAuth.instance.currentUser!.uid — setter를 통해서만 바뀌므로
  // 로그인/로그아웃 시 항상 revision이 함께 갱신된다(화면이 뒤로 갔다
  // 다시 들어오지 않아도 즉시 반영되는 이유).
  static String get userId => _userId;
  static set userId(String value) {
    if (_userId == value) return;
    _userId = value;
    _bump();
  }

  /// 로그인 상태나 프로필(닉네임/본인인증 등)이 바뀔 때마다 증가하는
  /// 카운터 — [AuthRebuilder]처럼 로그인 상태에 의존하는 화면이 이 값을
  /// 구독해서 setState 없이도, 그리고 화면을 벗어났다 다시 들어오지
  /// 않아도 즉시 다시 그려지게 한다.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static void _bump() => revision.value++;

  static bool isVerified = false; // backward-compat alias for identityVerified
  static bool identityVerified = false;
  static DateTime? identityVerifiedAt;
  static bool profileCompleted = false;
  static String name = '';
  static String gender = ''; // 'male' | 'female'
  static int? birthYear; // 본인확인 시 저장된 출생연도
  static String role = ''; // 'admin' 이면 관리자 (firestore.rules의 isAdmin()과 동일 기준)

  // ── 프로필(닉네임/프로필 사진) ──────────────────────────────────────
  // name은 본인인증으로 확인된 실명(파티장에게만 공개)이라 공개 표시용으로
  // 쓰면 안 된다. 앱 전체 공개 표시(파티장/채팅/참여자 등)는 nickname을
  // 우선 쓰고, 아직 설정하지 않았으면 name으로 폴백한다.
  static String nickname = '';
  static String profileImageUrl = '';

  // ── 로그인 계정 표시용(마이페이지) — utils/login_account.dart가 쓴다 ──
  // 기록 주체가 다 다르다:
  //  · socialAccount — 서버(functions/socialAuth.js)가 카카오·네이버 로그인
  //    **매번** 소셜 계정 이메일을 기록한다. 카카오·네이버 표시의 1순위.
  //  · signupProvider — login.dart가 최초 1회. 제공자 판정 폴백.
  //  · email — onUserCreated(functions/index.js)가 가입 시 Auth에서 복사. 폴백.
  static String socialAccountProvider = '';
  static String socialAccountEmail = '';
  static String signupProvider = '';
  static String accountEmail = '';

  /// 서버가 정하는 계정 상태 — 'active' · 'withdrawal_pending' · 'withdrawn' 등.
  /// 탈퇴 대기 중이면 앱이 서비스 화면 대신 안내 화면을 띄운다. 이 값은
  /// 규칙상 클라이언트가 쓸 수 없어 앱에서는 읽기만 한다.
  ///
  /// 정적 변수가 아니라 [ValueNotifier]인 이유: 이 값으로 루트 게이트가 어떤
  /// 화면을 띄울지 고르는데, 값만 바꾸면 **이미 그려진 트리는 바뀐 줄 모른다.**
  /// 탈퇴를 취소해 서버가 active로 돌려놨는데도 앱이 대기 화면에 그대로 갇혀
  /// 있던 원인이 이것이었다. 이제 대입만 하면 게이트가 스스로 다시 평가한다.
  static final ValueNotifier<String> accountStatusListenable =
      ValueNotifier<String>('active');

  static String get accountStatus => accountStatusListenable.value;
  static set accountStatus(String value) =>
      accountStatusListenable.value = value;

  /// 완전 탈퇴 예정 시각 — 탈퇴 대기 중일 때만 값이 있다. 남은 일수를
  /// 보여주는 데만 쓰고, 실제 처리는 서버 스케줄러가 한다.
  static DateTime? withdrawalScheduledAt;

  /// **서버 기준** 본인확인 상태 — 루트 게이트가 첫 화면을 고르는 근거.
  ///
  /// 저장된 값이 아니라 **그때그때 계산한다.** 값을 따로 들고 있으면 그 값을
  /// 갱신하는 자리를 빠뜨리는 순간(예: 읽기를 시작만 하고 아직 끝나지 않은
  /// 구간) 게이트가 옛 판정으로 그려진다. 계산 재료는 모두 이 클래스 안에
  /// 있으므로 매번 새로 세는 편이 어긋날 여지가 없다.
  ///
  /// 게이트를 **다시 그리게 하는 신호**는 [revision]이다 — 로그인/로그아웃과
  /// 프로필 읽기 완료가 모두 [_bump]을 지나므로, 아래 판정이 바뀌는 모든
  /// 전이에 신호가 따라붙는다.
  static IdentityStatus get identityStatus {
    if (userId.isEmpty) return IdentityStatus.checking;
    // 아직 읽지 않았거나(none) 읽는 중(loading)이면 '확인 중'이다. 로그인
    // 직후가 이 구간이라, 여기서 실패로 단정하면 정상 로그인이 깨진다.
    if (_profileLoad == UserProfileLoad.none ||
        _profileLoad == UserProfileLoad.loading) {
      return IdentityStatus.checking;
    }
    // 읽기가 **최종 실패**했다.
    //
    // 이 상태는 [_loadOnce]가 서버 읽기 2회(400ms 간격)와 캐시 폴백까지
    // **전부** 실패했을 때만 된다 — 일시적인 오류 한 번으로는 오지 않으므로,
    // 여기서 실패로 확정해도 재시도 정책을 앞당기는 것이 아니다.
    //
    // 예전에는 이 값이 아래 `!isProfileLoaded`에 걸려 '확인 중'으로 떨어졌다.
    // 그러면 루트 게이트가 로딩 화면을 계속 그려 **무한 로딩**이 됐고, 화면에
    // 재시도 버튼도 없어서 앱을 껐다 켜는 것 말고는 빠져나올 길이 없었다.
    // 이제 '확인 못 함'으로 확정해 재시도·로그아웃이 있는 확인 실패 화면으로
    // 보낸다(IdentityCheckFailedScreen).
    if (_profileLoad == UserProfileLoad.failed) {
      // 다만 **이 계정에 대해 서버가 이미 '인증됨'이라고 답한 적이 있으면**
      // 그 사실은 이번 읽기 실패로 사라지지 않는다. 이 값은 false→true로만
      // 바뀌므로 나중에 뒤집힐 수 없다 — 판정을 새로 내리는 것이 아니라 이미
      // 확인된 값을 기억하는 것이다. 이게 없으면 인증을 마친 사용자가
      // 새로고침 한 번 실패했다는 이유로 서비스 화면에서 튕겨 나간다.
      //
      // 로그인 직후에는 [beginSession]이 [_loadedUserId]를 비우므로 이 가지를
      // 탈 수 없다 — 새 세션은 반드시 서버 답을 받아야 통과한다.
      if (identityVerified && _loadedUserId == userId) {
        return IdentityStatus.verified;
      }
      return IdentityStatus.unknown;
    }
    // 다른 계정의 값이 남아 있으면 이 계정에 대해서는 아직 아무것도 모른다.
    // (읽기는 [beginSession]이 이미 걸어 뒀으므로 곧 결론이 난다.)
    if (!isProfileLoaded) return IdentityStatus.checking;
    // '인증됨'은 캐시에서 읽었어도 믿는다 — 이 값은 false→true로만 바뀌므로
    // 캐시가 true인데 서버가 false일 수는 없다.
    if (identityVerified) return IdentityStatus.verified;
    // '미인증'은 서버에서 확인했을 때만 단정한다.
    if (_loadedFromServer) return IdentityStatus.unverified;
    // 캐시로만 읽은 '미인증' — 서버 값을 본 적이 없으므로 단정하지 않는다.
    return IdentityStatus.unknown;
  }

  // ── 탈퇴 상태 반영 ──────────────────────────────────────────────────
  //
  // 탈퇴 신청·취소는 콜러블이 처리하고 결과를 그대로 돌려준다. 그 응답이 곧
  // 서버가 확정한 상태이므로, 화면이 users 문서를 다시 읽지 않고 여기에 바로
  // 반영한다(다시 읽으면 Firestore가 오프라인 캐시로 대체할 수 있어 방금 바꾼
  // 값이 안 보일 수 있다 — [_loadedFromServer] 주석 참고).
  //
  // 두 메서드 모두 [withdrawalScheduledAt]을 **먼저** 맞추고 [accountStatus]를
  // 마지막에 바꾼다. 상태 대입이 게이트를 다시 평가시키는 신호라, 순서가
  // 반대면 게이트가 아직 옛 예정 시각을 들고 그려진다.

  /// 탈퇴 신청이 접수됐을 때 — [scheduledAt]은 서버가 정한 완료 예정 시각.
  static void applyWithdrawalRequested(DateTime? scheduledAt) {
    withdrawalScheduledAt = scheduledAt;
    accountStatus = 'withdrawal_pending';
  }

  /// 탈퇴가 취소돼 계정이 복구됐을 때.
  static void applyWithdrawalCancelled() {
    withdrawalScheduledAt = null;
    accountStatus = 'active';
  }

  static bool get isAdmin => role == 'admin';

  /// 로그인 여부 — 참가비 등 "로그인 사용자에게만 공개" 정보의 노출 여부를
  /// 판단하는 데 쓴다.
  static bool get isLoggedIn => userId.isNotEmpty;

  /// 닉네임을 "설정했다"고 볼 수 있는 상태 — null/빈 문자열/"기본닉네임"이면
  /// 아직 설정하지 않은 것으로 간주해 파티 참여 시 자동 팝업을 띄운다.
  static bool get hasNickname => nickname.isNotEmpty && nickname != '기본닉네임';

  /// 앱 전체 공개 표시용 이름 — 닉네임이 있으면 닉네임, 없으면 실명 폴백.
  static String get displayName => hasNickname ? nickname : name;

  // ── 프로필 로드 상태 ────────────────────────────────────────────────
  static UserProfileLoad _profileLoad = UserProfileLoad.none;
  static UserProfileLoad get profileLoad => _profileLoad;

  /// 프로필을 다 읽어 둔 사용자 — 다른 계정으로 바뀌면 다시 읽어야 한다.
  static String _loadedUserId = '';

  /// 지금 진행 중인 읽기. 로그인 화면·메인 화면·authStateChanges가 동시에
  /// 불러도 요청은 하나만 나가고 모두 같은 Future를 기다린다.
  static Future<void>? _inFlight;

  /// 마지막으로 채운 값이 **서버**에서 온 것인지(오프라인 캐시가 아니라).
  ///
  /// Firestore의 기본 `get()`은 서버에 닿지 못하면 조용히 오프라인 캐시로
  /// 대체된다. 본인확인을 막 마친 계정도 캐시에는 아직 "미인증"이 남아 있을 수
  /// 있어서, 그 값을 그대로 믿으면 인증을 마친 사용자에게 본인확인 화면이
  /// 다시 뜬다. 그래서 **'미인증' 판정은 서버에서 읽었을 때만** 내린다.
  static bool _loadedFromServer = false;

  static bool get isProfileLoaded =>
      _profileLoad == UserProfileLoad.loaded && _loadedUserId == userId;

  static bool get isProfileLoading => _profileLoad == UserProfileLoad.loading;

  /// **로그인 세션의 시작을 알린다 — uid를 세션에 넣는 유일한 통로.**
  ///
  /// `userId`만 대입하면 그 순간부터 세션은 "로그인했다"고 답하는데, 프로필은
  /// 아직 한 글자도 읽지 않은 상태다. 그 틈에 그려지는 화면은 [identityVerified]
  /// 같은 **기본값 false**를 그대로 보고 판단한다 — 이미 본인확인을 마친
  /// 사용자에게 본인확인/확인 실패 화면이 번쩍이던 원인이 이것이다.
  ///
  /// 그래서 uid 대입과 "아직 안 읽었다" 표시를 **같은 동기 블록**에서 함께
  /// 한다. 사이에 await가 없으므로 그 중간 상태로는 한 프레임도 그려질 수
  /// 없고, [identityStatus]는 로그인 직후 반드시 [IdentityStatus.checking]에서
  /// 출발한다(루트 게이트는 그 값을 로딩으로만 그린다).
  ///
  /// 로그인 경로마다 따로 처리하지 않는다 — 구글·카카오·네이버·이메일과
  /// 세션 복원(authStateChanges)이 모두 이 함수 하나를 거친다.
  static void beginSession(String uid) {
    if (uid.isEmpty) {
      clear();
      return;
    }
    // ⚠️ 순서가 핵심이다. userId setter가 revision을 올려 루트 게이트를 다시
    //    그리게 하므로, **그 전에** 읽기 상태를 되돌려 놔야 한다.
    _profileLoad = UserProfileLoad.loading;
    _loadedUserId = '';
    _loadedFromServer = false;
    // 이전 계정을 대상으로 돌던 읽기는 이 세션의 답이 아니다.
    _inFlight = null;
    userId = uid;
    // 같은 uid로 다시 로그인하면 위 setter가 값 변화를 못 느껴 신호를 안 보낸다
    // — 읽기 상태는 방금 바뀌었으므로 게이트에 직접 알린다.
    _bump();
    // 읽기를 **여기서 곧바로 건다.** 이렇게 해야 "로그인 상태면 프로필 읽기가
    // 진행 중이거나 이미 끝나 있다"가 구조적으로 보장된다 — 호출부가 읽기를
    // 거는 것을 잊거나(화면이 먼저 dispose되는 등) 그 사이에 다른 화면이
    // 끼어들어도 'loading'에 갇히지 않는다. 호출부가 다시 불러도
    // [loadFromFirestore]가 같은 읽기를 돌려주므로 요청은 하나뿐이다.
    unawaited(loadFromFirestore().catchError((_) {}));
  }

  static void clear() {
    _profileLoad = UserProfileLoad.none;
    _loadedUserId = '';
    _loadedFromServer = false;
    _inFlight = null;
    userId = '';
    isVerified = false;
    identityVerified = false;
    identityVerifiedAt = null;
    profileCompleted = false;
    name = '';
    gender = '';
    birthYear = null;
    role = '';
    nickname = '';
    profileImageUrl = '';
    socialAccountProvider = '';
    socialAccountEmail = '';
    signupProvider = '';
    accountEmail = '';
    accountStatus = 'active';
    withdrawalScheduledAt = null;
    // [identityStatus]는 위 값들로 그때그때 계산되므로 따로 되돌릴 것이 없다 —
    // _profileLoad가 none으로 돌아간 순간 직전 계정의 판정은 사라진다.
  }

  /// Firebase Auth + 소셜 SDK + Firestore 세션 초기화 (로그아웃)
  ///
  /// 소셜 SDK에 남은 로그인 세션까지 함께 끊는다 — Firebase만 signOut하면
  /// 구글/카카오/네이버 SDK가 들고 있는 직전 계정으로 다음 로그인 때 계정
  /// 선택 없이 그대로 자동 재로그인된다([SocialSession] 참고).
  static Future<void> signOut() async {
    // 이 기기를 계정에서 먼저 떼어낸다 — **signOut보다 먼저** 해야 한다.
    // 해제는 로그인 상태에서만 부를 수 있는 onCall이라, Firebase 세션이 끊긴
    // 뒤에 부르면 unauthenticated로 실패해 토큰이 그대로 남는다(= 로그아웃한
    // 기기로 알림이 계속 간다).
    await PushNotificationService.unregisterForUser();
    await SocialSession.signOutAll();
    await FirebaseAuth.instance.signOut();
    clear();
  }

  /// 앱 시작 시 또는 로그인 후 Firestore에서 사용자 상태를 로드합니다.
  ///
  /// 같은 시점에 여러 곳에서 불러도 요청은 한 번만 나가고 모두 같은 결과를
  /// 기다린다 — 로그인 직후 로그인 화면과 authStateChanges 구독이 동시에
  /// 호출하던 경로가 서로를 앞질러 "아직 안 읽힌 상태"를 보던 문제를 없앤다.
  static Future<void> loadFromFirestore() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final future = _loadOnce();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  /// 아직 못 읽었거나(또는 실패했거나) 다른 계정의 값이 남아 있을 때만 읽는다.
  ///
  /// **읽는 중이면 이미 loaded 상태여도 그 읽기를 기다린다.** 로그인 직후가
  /// 딱 그 순간이다 — 로그인 처리가 `force` 읽기를 걸어 둔 사이에 다른 화면이
  /// 이걸 부르면, 예전에는 아직 갱신되지 않은 **옛 값**을 그대로 돌려줬다.
  /// 본인확인을 막 마쳤거나 다른 기기에서 마친 계정이 '미인증'으로 판정되던
  /// 경로가 이것이다.
  static Future<void> ensureLoaded() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    if (isProfileLoaded) return Future<void>.value();
    return loadFromFirestore();
  }

  /// **서버(users/{uid})에 저장된 값 기준**의 본인확인 여부.
  ///
  /// - `true`  : 본인확인 완료
  /// - `false` : **서버에서** 읽어봤더니 미완료
  /// - `null`  : 비로그인이거나 아직 확인하지 못함(읽기 실패, 캐시로만 읽음)
  ///
  /// null을 '미인증'으로 취급하면 안 된다 — 이미 본인확인을 마친 사용자가
  /// 네트워크 문제 하나로 본인확인 화면을 다시 보게 되는 원인이었다. (루트
  /// 게이트도 null을 미인증으로 보지 않는다. 대신 통과시키지도 않고 '확인
  /// 실패' 화면으로 보낸다 — root_gate.dart 참고.)
  ///
  /// 판정 자체는 [identityStatus]와 같은 값이다. 이 메서드가 따로 남아 있는
  /// 이유는 **읽기를 강제로 한 번 더 태우는 자리**이기 때문이다(로그인 직후,
  /// 확인 실패 화면의 '다시 시도').
  static Future<bool?> resolveIdentityVerified({bool force = false}) async {
    if (userId.isEmpty) return null;
    try {
      await (force ? loadFromFirestore() : ensureLoaded());
    } catch (_) {
      // 상태는 _loadOnce가 failed로 남겨 둔다 — 아래에서 null로 나간다.
    }
    var status = identityStatus;
    // 캐시로만 읽어 '모름'으로 남았으면 서버로 한 번 더 확인한다 — 앱을 켤 때
    // 네트워크가 늦어 캐시로 읽혔더라도, 실제로 물어보는 이 시점에는 서버
    // 값으로 바로잡히게 한다.
    if (status == IdentityStatus.unknown && !force && isProfileLoaded) {
      try {
        await loadFromFirestore();
      } catch (_) {}
      status = identityStatus;
    }
    return switch (status) {
      IdentityStatus.verified => true,
      IdentityStatus.unverified => false,
      // 여기까지 왔는데 아직 확인 중이면(다른 읽기가 겹친 드문 경우) 모르는
      // 것으로 답한다 — 호출부가 '통과'로 오해하지 않게.
      IdentityStatus.checking || IdentityStatus.unknown => null,
    };
  }

  static Future<void> _loadOnce() async {
    if (userId.isEmpty) return;
    final uid = userId;
    _profileLoad = UserProfileLoad.loading;
    try {
      // ① 서버에서 직접 읽는다. 커스텀 토큰 로그인(카카오/네이버) 직후에는
      //    토큰이 아직 퍼지지 않아 첫 읽기가 실패할 수 있어 한 번 더 시도한다.
      // ② 그래도 안 되면 마지막으로 기본 읽기(캐시 허용)로 값을 채우되,
      //    캐시에서 왔다는 사실을 남겨 '미인증' 판정에는 쓰지 않는다.
      DocumentSnapshot<Map<String, dynamic>> doc;
      try {
        doc = await _readUserDoc(uid, fromServer: true);
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        try {
          doc = await _readUserDoc(uid, fromServer: true);
        } catch (_) {
          doc = await _readUserDoc(uid, fromServer: false);
        }
      }
      // 읽는 사이에 계정이 바뀌었으면(로그아웃/재로그인) 그 결과는 버린다.
      if (uid != userId) return;
      _applyUserDoc(doc);
      _profileLoad = UserProfileLoad.loaded;
      _loadedUserId = uid;
      _loadedFromServer = !doc.metadata.isFromCache;
      debugPrint(
        '[UserSession] 프로필 로드 완료 uid=$uid '
        'identityVerified=$identityVerified fromServer=$_loadedFromServer '
        'docExists=${doc.exists}',
      );
    } catch (e) {
      // 실패했다고 해서 기존 값을 미인증으로 되돌리지 않는다. 상태만 남기고
      // 호출부가 "아직 모름"으로 다루게 한다.
      if (uid == userId) _profileLoad = UserProfileLoad.failed;
      debugPrint('[UserSession] 프로필 로드 실패: $e');
      // 실패는 '미인증'이 아니라 '모름'이다 — 아래 finally의 동기화가 그렇게
      // 계산한다(isProfileLoaded가 false가 되므로).
      rethrow;
    } finally {
      // 성공·실패 어느 쪽으로 끝나든 화면에 신호를 보낸다 — [identityStatus]는
      // 계산값이라 따로 갱신할 것이 없고, 이 bump가 루트 게이트를 다시
      // 그리게 한다. 읽기가 끝나는 모든 길목이 여기를 지난다.
      _bump();
    }
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> _readUserDoc(
    String uid, {
    required bool fromServer,
  }) => FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .get(fromServer ? const GetOptions(source: Source.server) : null);

  static void _applyUserDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (doc.exists) {
      final data = doc.data()!;
      // 신규 필드 우선, 구버전 isVerified 폴백
      identityVerified =
          (data['identityVerified'] as bool?) ??
          (data['isVerified'] as bool?) ??
          false;
      isVerified = identityVerified;
      final ts = data['identityVerifiedAt'] as Timestamp?;
      identityVerifiedAt = ts?.toDate();
      profileCompleted = data['profileCompleted'] as bool? ?? identityVerified;
      name = data['name'] as String? ?? '';
      gender = data['gender'] as String? ?? '';
      birthYear = (data['birthYear'] as num?)?.toInt();
      role = data['role'] as String? ?? '';
      nickname = data['nickname'] as String? ?? '';
      profileImageUrl = data['profileImageUrl'] as String? ?? '';
      signupProvider = data['signupProvider'] as String? ?? '';
      accountEmail = data['email'] as String? ?? '';
      final social = data['socialAccount'];
      socialAccountProvider = social is Map && social['provider'] is String
          ? social['provider'] as String
          : '';
      socialAccountEmail = social is Map && social['email'] is String
          ? social['email'] as String
          : '';
      accountStatus = data['accountStatus'] as String? ?? 'active';
      withdrawalScheduledAt = (data['withdrawalScheduledAt'] as Timestamp?)
          ?.toDate();
      // 관리자 웹의 "활성 사용자" 통계용 — 세션 로드(앱 시작/로그인) 시점마다
      // 1회 갱신. 실패해도 로그인 자체를 막지 않도록 fire-and-forget으로 둔다.
      unawaited(
        FirebaseFirestore.instance.collection('users').doc(userId).set({
          'lastActiveAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
      );
    } else {
      isVerified = false;
      identityVerified = false;
      identityVerifiedAt = null;
      profileCompleted = false;
      name = '';
      gender = '';
      role = '';
      nickname = '';
      profileImageUrl = '';
      socialAccountProvider = '';
      socialAccountEmail = '';
      signupProvider = '';
      accountEmail = '';
    }
  }
}
