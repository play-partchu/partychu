import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';

/// 사전등록 기간의 **임시 노출 정책** — 외부 호스트가 새로 등록한 콘텐츠는
/// 본인과 관리자에게만 보이고, 다른 사용자에게는 목록·지도·연결 카드에서
/// 빠진다. 운영 계정([publicOwnerUids])이 올린 콘텐츠는 계속 모두에게 보인다.
///
/// ── 켜고 끄기 ────────────────────────────────────────────────────────────────
///
/// `appConfig/policy.preRegistrationContentPrivate` 하나로 정한다
/// ([HostOpenPolicyService]와 같은 문서). **값이 `false`일 때만 해제**이고,
/// 문서·필드가 없거나 읽지 못하면 비공개로 본다. 해제하면 앱 재배포 없이
/// 외부 호스트 콘텐츠가 한꺼번에 공개된다(목록은 다음에 다시 그릴 때 반영).
///
/// 사전등록이 끝나 해제한 뒤에는 이 파일과 호출부를 지워도 된다 — 호출부는
/// 모두 `PreRegistrationVisibility.isHidden` 으로 검색된다.
///
/// ── 한계 ────────────────────────────────────────────────────────────────────
///
/// 화면에서 빼는 것이지 권한 차단이 아니다. 콘텐츠 컬렉션은 규칙상 공개 읽기라
/// Firestore를 직접 조회하면 읽힌다. 링크(딥링크·공유 페이지)로 상세를 직접
/// 여는 경로도 막지 않는다 — 목록에서 빠지면 그 링크는 주인이 공유해야만 생긴다.
class PreRegistrationVisibility {
  PreRegistrationVisibility._();

  /// 사전등록 전부터 콘텐츠를 올려 둔 계정 — 이들의 콘텐츠는 항상 공개다.
  ///
  /// 기존 운영 데이터(2026-09-18 기준 전부 이 두 계정 소유)가 지금과 똑같이
  /// 보이도록 둔다. 데이터에 표시를 새로 남기지 않고 소유자로만 가른다.
  @visibleForTesting
  static const Set<String> publicOwnerUids = {
    'ws3COMBLLXPlI4IyhLnwtGF1evS2', // 운영 계정(유타) — 운영 콘텐츠 전부
    '81xjkLVVDlY0Rjw2L01kuRqCoKo1', // host@test.com — 기존 QA 파티
  };

  static const _docPath = 'appConfig/policy';
  static const _flagKey = 'preRegistrationContentPrivate';

  /// 지금 비공개 정책이 켜져 있는가. 읽기 전에는 켜진 것으로 본다.
  static final ValueNotifier<bool> active = ValueNotifier<bool>(true);

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  /// Firestore 자체를 쓸 수 없는 환경인가(Firebase 초기화 없이 판정 함수만
  /// 부르는 단위 테스트). 앱은 항상 초기화 뒤에 화면을 그리므로 여기 오지
  /// 않는다 — 이때는 정책을 걸지 않아 기존 판정 결과가 그대로 나온다.
  static bool _unavailable = false;

  static void _ensureWatching() {
    if (_sub != null || _unavailable) return;
    try {
      _sub = FirebaseFirestore.instance
          .doc(_docPath)
          .snapshots()
          .listen(
            (snap) => active.value = snap.data()?[_flagKey] != false,
            onError: (Object e, StackTrace st) => logFirestoreStreamError(
              'PreRegistrationVisibility.watch',
              e,
              st,
            ),
          );
    } catch (_) {
      _unavailable = true;
    }
  }

  /// 이 콘텐츠를 지금 보는 사람에게서 숨겨야 하는가.
  ///
  /// 소유자 필드는 컬렉션마다 `hostId`(파티는 `hostUid`도)다. 소유자를 알 수
  /// 없는 문서는 숨기지 않는다 — 이 정책 이전의 옛 데이터일 뿐이다.
  static bool isHidden(Map<String, dynamic> data) {
    _ensureWatching();
    if (_unavailable || !active.value) return false;
    final owner = (data['hostId'] as String?) ?? (data['hostUid'] as String?);
    if (owner == null || owner.isEmpty) return false;
    if (publicOwnerUids.contains(owner)) return false;
    if (owner == UserSession.userId) return false;
    if (UserSession.isAdmin) return false;
    return true;
  }

  /// 문서 목록에서 숨길 것을 뺀다([BlockService.withoutBlocked]와 같은 모양).
  static List<T> withoutHidden<T extends DocumentSnapshot>(List<T> docs) {
    return docs.where((doc) {
      final data = doc.data();
      return data is! Map<String, dynamic> || !isHidden(data);
    }).toList();
  }
}
