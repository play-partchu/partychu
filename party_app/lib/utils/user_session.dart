import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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

  static bool isVerified = false;  // backward-compat alias for identityVerified
  static bool identityVerified = false;
  static DateTime? identityVerifiedAt;
  static bool profileCompleted = false;
  static String name = '';
  static String gender = ''; // 'male' | 'female'
  static int? birthYear;     // 본인확인 시 저장된 출생연도
  static String role = '';   // 'admin' 이면 관리자 (firestore.rules의 isAdmin()과 동일 기준)

  // ── 프로필(닉네임/프로필 사진) ──────────────────────────────────────
  // name은 본인인증으로 확인된 실명(파티장에게만 공개)이라 공개 표시용으로
  // 쓰면 안 된다. 앱 전체 공개 표시(파티장/채팅/참여자 등)는 nickname을
  // 우선 쓰고, 아직 설정하지 않았으면 name으로 폴백한다.
  static String nickname = '';
  static String profileImageUrl = '';

  static bool get isAdmin => role == 'admin';

  /// 로그인 여부 — 참가비 등 "로그인 사용자에게만 공개" 정보의 노출 여부를
  /// 판단하는 데 쓴다.
  static bool get isLoggedIn => userId.isNotEmpty;

  /// 닉네임을 "설정했다"고 볼 수 있는 상태 — null/빈 문자열/"기본닉네임"이면
  /// 아직 설정하지 않은 것으로 간주해 파티 참여 시 자동 팝업을 띄운다.
  static bool get hasNickname => nickname.isNotEmpty && nickname != '기본닉네임';

  /// 앱 전체 공개 표시용 이름 — 닉네임이 있으면 닉네임, 없으면 실명 폴백.
  static String get displayName => hasNickname ? nickname : name;

  static void clear() {
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
  }

  /// Firebase Auth + Firestore 세션 초기화 (로그아웃)
  static Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    clear();
  }

  /// 앱 시작 시 또는 로그인 후 Firestore에서 사용자 상태를 로드합니다.
  static Future<void> loadFromFirestore() async {
    if (userId.isEmpty) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    if (doc.exists) {
      final data = doc.data()!;
      // 신규 필드 우선, 구버전 isVerified 폴백
      identityVerified = (data['identityVerified'] as bool?) ??
          (data['isVerified'] as bool?) ?? false;
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
      // 관리자 웹의 "활성 사용자" 통계용 — 세션 로드(앱 시작/로그인) 시점마다
      // 1회 갱신. 실패해도 로그인 자체를 막지 않도록 fire-and-forget으로 둔다.
      unawaited(FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set({'lastActiveAt': FieldValue.serverTimestamp()}, SetOptions(merge: true)));
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
    }
    // 닉네임/본인인증 등 프로필 필드는 userId setter가 아니라 여기서
    // 채워지므로, 로그인 직후 화면이 곧바로 최신 프로필까지 반영하도록
    // 로드가 끝난 시점에 한 번 더 알린다.
    _bump();
  }
}
