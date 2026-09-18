// 동일인(실제 회원 1명) 판별 — 계정 수가 아니라 사람 수로 세고 보여주기 위한 순수 로직.
//
// ── 무엇으로 같은 사람이라고 판단하나 ─────────────────────────────────────
//
// NICE 본인확인의 **CI(연계정보)** 하나뿐이다. CI는 실사용자 1명당 전 기관
// 공통으로 같은 값이 나온다. 서버는 본인확인이 끝나면 같은 트랜잭션에서
// `users/{uid}.ci`(원문)와 `users/{uid}.identityCiHash`(= sha256(ci))를 함께
// 기록한다(functions/identityLink.js의 linkIdentityAndSaveVerification).
//
// [personKeyOf]는 서버의 `ciHashOfUserData`와 **같은 규칙**이다:
//   identityCiHash가 있으면 그 값, 없으면 sha256(ci), 둘 다 없으면 null.
// identityCiHash가 없는 계정은 해시 필드 도입 전에 인증한 회원이다(운영에
// 실제로 있다) — 그래서 원문 해시 폴백이 빠지면 그 사람이 둘로 갈라진다.
//
// ── 하지 않는 것 ──────────────────────────────────────────────────────────
//
//  · 이름·생년월일·전화번호가 같다고 합치지 않는다. 동명이인·가족 번호가 있다.
//  · CI가 없는 계정(본인확인 전, 탈퇴로 CI가 지워진 계정)은 누구와도 합치지
//    않는다 — 각자 1명이다.
//  · CI 원문과 해시는 **화면에 그리지 않는다.** 이 파일 밖으로는 불투명한 키로만
//    쓰인다.
//  · 문서를 합치거나 지우지 않는다. 표시와 집계만 묶는다 — 신청·채팅·게시글이
//    가리키는 uid는 그대로다.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

/// 동일인 묶음 키 — 같은 값이면 같은 사람이다. 판별 근거가 없으면 null.
String? personKeyOf(Map<String, dynamic> data) {
  final hash = data['identityCiHash'];
  if (hash is String && hash.isNotEmpty) return hash;
  final ci = data['ci'];
  // 서버와 같이 빈칸 판정만 trim으로 하고, 해시는 원문 그대로 계산한다.
  if (ci is String && ci.trim().isNotEmpty) {
    return sha256.convert(utf8.encode(ci)).toString();
  }
  return null;
}

/// 로그인 수단 코드 → 화면 표기.
const memberProviderLabels = <String, String>{
  'google': '구글',
  'kakao': '카카오',
  'naver': '네이버',
  'apple': 'Apple',
  'email': '이메일(테스트)',
};

/// 한 사람이 가진 계정 하나(= Firebase UID 하나)의 표시용 요약.
class MemberAccount {
  final String uid;

  /// google / kakao / naver / apple / email, 알 수 없으면 null.
  final String? provider;

  /// 그 로그인 수단의 이메일 — 없으면 null.
  final String? email;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  final DateTime? lastActiveAt;
  final String accountStatus;
  final bool isTestAccount;

  const MemberAccount({
    required this.uid,
    this.provider,
    this.email,
    this.createdAt,
    this.lastLoginAt,
    this.lastActiveAt,
    this.accountStatus = 'active',
    this.isTestAccount = false,
  });

  /// 로그인 수단은 서버가 매 로그인마다 쓰는 `socialAccount.provider`를 먼저
  /// 믿고, 없으면 앱이 최초 1회 쓰는 `signupProvider`, 그것도 없으면
  /// 카카오·네이버 커스텀 토큰 uid 접두사(functions/socialAuth.js)로 판단한다.
  factory MemberAccount.fromUserDoc(String uid, Map<String, dynamic> d) {
    final social = d['socialAccount'];
    final socialMap = social is Map ? social : const {};
    String? provider = _nonEmpty(socialMap['provider']) ?? _nonEmpty(d['signupProvider']);
    if (provider == null) {
      if (uid.startsWith('kakao:')) {
        provider = 'kakao';
      } else if (uid.startsWith('naver:')) {
        provider = 'naver';
      } else if (d['isTestAccount'] == true) {
        provider = 'email';
      }
    }
    return MemberAccount(
      uid: uid,
      provider: provider,
      email: _nonEmpty(socialMap['email']) ?? _nonEmpty(d['email']),
      createdAt: _date(d['createdAt']),
      lastLoginAt: _date(d['lastLoginAt']),
      lastActiveAt: _date(d['lastActiveAt']),
      accountStatus: _nonEmpty(d['accountStatus']) ?? 'active',
      isTestAccount: d['isTestAccount'] == true,
    );
  }

  String get providerLabel =>
      provider == null ? '알 수 없음' : (memberProviderLabels[provider] ?? provider!);

  static String? _nonEmpty(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

  static DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;
}

/// 실제 회원 1명 — 같은 CI를 가진 계정 전부.
class PersonGroup {
  /// 동일인 키. null이면 판별 근거가 없는 단독 계정이다.
  final String? key;

  /// 먼저 가입한 계정부터.
  final List<MemberAccount> accounts;

  const PersonGroup({required this.key, required this.accounts});

  int get accountCount => accounts.length;
  bool get hasMultipleAccounts => accounts.length > 1;

  /// 로그인 수단 표기 — 중복 없이 가입 순서대로. `구글 · 네이버 · Apple`.
  String get providersLabel {
    final seen = <String>[];
    for (final a in accounts) {
      final l = a.providerLabel;
      if (!seen.contains(l)) seen.add(l);
    }
    return seen.join(' · ');
  }
}

/// 계정들을 사람별로 묶는다. 순서는 **각 사람이 처음 나타난 순서**를 따르고,
/// 한 사람 안의 계정은 가입일 순이다(가입일이 없으면 뒤로).
List<PersonGroup> groupAccountsByPerson(Iterable<(String uid, Map<String, dynamic> data)> docs) {
  final order = <Object>[];
  final byKey = <Object, List<MemberAccount>>{};
  final keys = <Object, String?>{};
  for (final (uid, data) in docs) {
    final key = personKeyOf(data);
    // 키가 없는 계정은 uid 자체를 자리 표시로 써서 절대 다른 계정과 섞이지 않게 한다.
    final Object slot = key ?? _Solo(uid);
    if (!byKey.containsKey(slot)) {
      order.add(slot);
      byKey[slot] = [];
      keys[slot] = key;
    }
    final list = byKey[slot]!;
    if (list.every((a) => a.uid != uid)) list.add(MemberAccount.fromUserDoc(uid, data));
  }
  return [
    for (final slot in order)
      PersonGroup(key: keys[slot], accounts: _byCreatedAt(byKey[slot]!)),
  ];
}

List<MemberAccount> _byCreatedAt(List<MemberAccount> list) {
  final sorted = [...list];
  sorted.sort((a, b) {
    final x = a.createdAt, y = b.createdAt;
    if (x == null && y == null) return a.uid.compareTo(b.uid);
    if (x == null) return 1;
    if (y == null) return -1;
    final c = x.compareTo(y);
    return c != 0 ? c : a.uid.compareTo(b.uid);
  });
  return sorted;
}

/// uid로만 같은 [_Solo] — 판별 근거가 없는 계정의 자리.
class _Solo {
  final String uid;
  const _Solo(this.uid);
  @override
  bool operator ==(Object other) => other is _Solo && other.uid == uid;
  @override
  int get hashCode => uid.hashCode;
}

/// 계정 수에서 빼야 할 "같은 사람의 두 번째 이후 계정" 수.
///
/// 사람 수 = 계정 수 − 이 값. [docs]에는 **세고 있는 조건을 이미 통과한 계정만**
/// 넣어야 한다 — 조건 밖 계정까지 넣으면 조건 안에 한 계정만 있는 사람도
/// 중복으로 빠진다.
int duplicateAccountCount(Iterable<Map<String, dynamic>> docs) {
  var keyed = 0;
  final distinct = <String>{};
  for (final d in docs) {
    final key = personKeyOf(d);
    if (key == null) continue;
    keyed++;
    distinct.add(key);
  }
  return keyed - distinct.length;
}

/// 목록 한 페이지를 사람 단위 행으로 줄인다.
///
/// 같은 사람의 계정은 **먼저 나온 한 줄만** 남긴다. [alreadyShownKeys]는 앞
/// 페이지에서 이미 그린 사람들이다 — 그 사람의 다른 계정이 이 페이지에 또
/// 나오면 감춘다.
///
/// [peopleByKey]는 전체 본인확인 계정을 사람별로 묶은 것이다. 행에 "계정 N개"를
/// 붙이고 상세에서 모두 보여주기 위해, 현재 페이지·필터 밖의 계정까지 담는다.
({List<T> rows, Map<T, PersonGroup> groups, int collapsed, Set<String> shownKeys})
    collapsePageByPerson<T>(
  List<T> docs, {
  required (String, Map<String, dynamic>) Function(T) read,
  required Map<String, PersonGroup> peopleByKey,
  Set<String> alreadyShownKeys = const {},
}) {
  final rows = <T>[];
  final groups = <T, PersonGroup>{};
  final shown = <String>{};
  var collapsed = 0;
  for (final doc in docs) {
    final (uid, data) = read(doc);
    final key = personKeyOf(data);
    if (key != null && (alreadyShownKeys.contains(key) || shown.contains(key))) {
      collapsed++;
      continue;
    }
    rows.add(doc);
    if (key != null) {
      shown.add(key);
      groups[doc] = peopleByKey[key] ??
          PersonGroup(key: key, accounts: [MemberAccount.fromUserDoc(uid, data)]);
    }
  }
  return (rows: rows, groups: groups, collapsed: collapsed, shownKeys: shown);
}
