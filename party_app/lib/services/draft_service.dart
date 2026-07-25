import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/models/draft_type.dart';
import 'package:party_app/utils/user_session.dart';

/// 로드된 임시저장 1건.
class DraftRecord {
  final DraftType type;
  final String title;
  final String? coverImageUrl;
  final Map<String, dynamic> payload;
  final DateTime? updatedAt;

  const DraftRecord({
    required this.type,
    required this.title,
    required this.coverImageUrl,
    required this.payload,
    required this.updatedAt,
  });
}

/// 등록 화면 작성 내용의 자동/수동 임시저장을 담당한다.
///
/// 저장 위치는 두 곳이다:
///  1. Firestore `drafts/{userId}__{type.key}` — 로그인 사용자 기준, 고정
///     문서 ID(유형별 1개, 덮어쓰기). 모바일 Firestore는 오프라인 퍼시스턴스가
///     기본 활성이라 네트워크가 끊겨도 쓰기가 로컬 큐에 쌓였다가 재연결 시
///     자동 동기화된다 — 그래서 별도 연결 감지/동기화 코드가 필요 없다.
///  2. SharedPreferences `draft_{type.key}` — 같은 payload의 로컬 미러.
///     Firestore 읽기/쓰기가 실패하는 상황(권한/네트워크)에서도 "이어서 작성"이
///     가능하도록 하는 안전망이자, 존재 여부를 즉시 판단하는 빠른 경로.
class DraftService {
  DraftService._();

  static const int schemaVersion = 1;

  static FirebaseFirestore get _fs => FirebaseFirestore.instance;

  static String _docId(DraftType type) => '${UserSession.userId}__${type.key}';
  static String _prefsKey(DraftType type) => 'draft_${type.key}';

  /// 로컬 미러(SharedPreferences)에 저장하는 JSON 형태.
  static String _encodeLocal({
    required DraftType type,
    required String title,
    required String? coverImageUrl,
    required Map<String, dynamic> payload,
    required int updatedAtMs,
  }) {
    return jsonEncode({
      'type': type.key,
      'title': title,
      'coverImageUrl': coverImageUrl,
      'payload': payload,
      'updatedAtMs': updatedAtMs,
      'schemaVersion': schemaVersion,
    });
  }

  /// 임시저장 저장(자동/수동 공통). 로컬 미러는 항상 먼저 기록해 실패해도
  /// 작성 내용이 남게 하고, 그다음 Firestore에 기록한다.
  ///
  /// 반환값 false = Firestore 기록엔 실패했지만 로컬 미러에는 남아 있음
  /// (호출부가 "기기에 보관됨" 정도로 안내할 수 있게).
  static Future<bool> saveDraft(
    DraftType type, {
    required String title,
    String? coverImageUrl,
    required Map<String, dynamic> payload,
  }) async {
    if (UserSession.userId.isEmpty) return false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 1) 로컬 미러 — 실패해도 무시(핵심 경로는 아래 Firestore).
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey(type),
        _encodeLocal(
          type: type,
          title: title,
          coverImageUrl: coverImageUrl,
          payload: payload,
          updatedAtMs: nowMs,
        ),
      );
    } catch (e) {
      debugPrint('[DraftService] 로컬 미러 저장 실패: $e');
    }

    // 2) Firestore — 고정 문서 ID로 덮어쓰기.
    try {
      await _fs.collection('drafts').doc(_docId(type)).set({
        'userId': UserSession.userId,
        'type': type.key,
        'title': title,
        'coverImageUrl': coverImageUrl,
        'payload': payload,
        'updatedAt': FieldValue.serverTimestamp(),
        'schemaVersion': schemaVersion,
      });
      return true;
    } catch (e) {
      debugPrint('[DraftService] Firestore 저장 실패(로컬엔 보관됨): $e');
      return false;
    }
  }

  /// 해당 유형의 임시저장이 있는지 — 복구 프롬프트 판단용.
  /// 로컬 미러를 먼저 보고(즉시), 없으면 Firestore를 확인한다.
  static Future<bool> hasDraft(DraftType type) async {
    if (UserSession.userId.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_prefsKey(type)) != null) return true;
    } catch (_) {}
    try {
      final snap = await _fs.collection('drafts').doc(_docId(type)).get();
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  /// 임시저장 로드 — Firestore를 우선하고, 실패하면 로컬 미러로 폴백한다.
  static Future<DraftRecord?> loadDraft(DraftType type) async {
    if (UserSession.userId.isEmpty) return null;

    try {
      final snap = await _fs.collection('drafts').doc(_docId(type)).get();
      final data = snap.data();
      if (snap.exists && data != null) {
        return DraftRecord(
          type: type,
          title: (data['title'] as String?) ?? '',
          coverImageUrl: data['coverImageUrl'] as String?,
          payload: Map<String, dynamic>.from(
              (data['payload'] as Map?) ?? const {}),
          updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
        );
      }
    } catch (e) {
      debugPrint('[DraftService] Firestore 로드 실패, 로컬 폴백: $e');
    }

    // 로컬 미러 폴백
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey(type));
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return DraftRecord(
          type: type,
          title: (map['title'] as String?) ?? '',
          coverImageUrl: map['coverImageUrl'] as String?,
          payload: Map<String, dynamic>.from(
              (map['payload'] as Map?) ?? const {}),
          updatedAt: map['updatedAtMs'] is int
              ? DateTime.fromMillisecondsSinceEpoch(map['updatedAtMs'] as int)
              : null,
        );
      }
    } catch (e) {
      debugPrint('[DraftService] 로컬 미러 로드 실패: $e');
    }
    return null;
  }

  /// 임시저장 삭제 — 최종 등록 성공/‘새로 작성’/수동 삭제 시. Firestore와
  /// 로컬 미러 둘 다 지운다.
  static Future<void> deleteDraft(DraftType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey(type));
    } catch (_) {}
    if (UserSession.userId.isEmpty) return;
    try {
      await _fs.collection('drafts').doc(_docId(type)).delete();
    } catch (e) {
      debugPrint('[DraftService] Firestore 삭제 실패: $e');
    }
  }

  /// 마이페이지 임시저장 목록용 — 본인 draft만 최신순 스트림.
  static Stream<List<DraftRecord>> watchAllDrafts(String userId) {
    if (userId.isEmpty) return Stream.value(const []);
    return _fs
        .collection('drafts')
        .where('userId', isEqualTo: userId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) {
              final data = d.data();
              final type = DraftType.fromKey(data['type'] as String?);
              if (type == null) return null;
              return DraftRecord(
                type: type,
                title: (data['title'] as String?) ?? '',
                coverImageUrl: data['coverImageUrl'] as String?,
                payload: Map<String, dynamic>.from(
                    (data['payload'] as Map?) ?? const {}),
                updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
              );
            })
            .whereType<DraftRecord>()
            .toList());
  }
}

/// 마지막 변경 후 [debounce](기본 1초) 뒤에 한 번만 저장하도록 묶어주는
/// 헬퍼. 등록 화면 State가 하나씩 들고 쓴다.
class DraftAutosaver {
  DraftAutosaver({
    required this.type,
    this.debounce = const Duration(seconds: 1),
  });

  final DraftType type;
  final Duration debounce;
  Timer? _timer;
  bool _disposed = false;

  /// 마지막 저장 시각 — 화면의 "자동 저장됨 · HH:mm" 표시에 쓴다.
  final ValueNotifier<DateTime?> lastSavedAt = ValueNotifier<DateTime?>(null);

  /// 마지막 저장이 Firestore까지 성공했는지(false면 로컬에만 보관됨).
  final ValueNotifier<bool> lastSaveSynced = ValueNotifier<bool>(true);

  /// payload를 만드는 콜백을 받아 debounce 후 저장을 예약한다.
  /// (매 글자마다 payload 전체를 만들지 않도록, 실제 직렬화는 타이머가
  /// 만료될 때 콜백을 호출해 그 시점에 한 번만 수행한다.)
  void schedule(DraftSnapshot Function() build) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, () => _run(build));
  }

  /// 즉시 저장(임시저장 버튼·뒤로가기·앱 백그라운드 전환 시).
  Future<void> flushNow(DraftSnapshot Function() build) async {
    if (_disposed) return;
    _timer?.cancel();
    await _run(build);
  }

  Future<void> _run(DraftSnapshot Function() build) async {
    final snap = build();
    final ok = await DraftService.saveDraft(
      type,
      title: snap.title,
      coverImageUrl: snap.coverImageUrl,
      payload: snap.payload,
    );
    if (_disposed) return;
    lastSaveSynced.value = ok;
    lastSavedAt.value = DateTime.now();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    lastSavedAt.dispose();
    lastSaveSynced.dispose();
  }
}

/// 자동저장 시점에 화면이 만들어 넘기는 스냅샷.
class DraftSnapshot {
  final String title;
  final String? coverImageUrl;
  final Map<String, dynamic> payload;
  const DraftSnapshot({
    required this.title,
    required this.coverImageUrl,
    required this.payload,
  });
}
