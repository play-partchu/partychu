import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// ══════════════════════════════════════════════════════════════════════════
// Firestore 저장 payload 정규화 · 검사 · 로깅
//
// 등록 화면들은 컨트롤러/enum/Set/TimeOfDay 같은 "화면 쪽 값"을 모아 하나의
// Map으로 조립한다. 그중 하나라도 Firestore가 모르는 타입이면 set/update가
// 통째로 실패하는데, 그때 올라오는 예외는 평범한 TypeError/ArgumentError라
// 화면에서는 "등록 중 문제가 발생했습니다"로만 보인다 — 어떤 필드가 문제인지
// 알 방법이 없었다.
//
// 여기서 하는 일은 세 가지다.
//   1. [normalize]  — 변환 가능한 값은 저장 가능한 형태로 바꾼다
//                     (Set→List, enum→name, DateTime→Timestamp,
//                      Map<dynamic,dynamic>→Map<String,dynamic>).
//   2. [describeIssues] — 그래도 남은 저장 불가 값의 **경로와 타입**을 뽑는다
//                     (예: `detailBlocks[0].controller: TextEditingController`).
//   3. [sanitizeForLog] — 통째로 debugPrint 할 수 있는 JSON 형태로 만든다.
//
// 이 파일은 Firebase 초기화 없이도 동작한다(순수 함수) — 단위 테스트에서
// 등록 payload를 그대로 검사할 수 있다.
// ══════════════════════════════════════════════════════════════════════════

/// Firestore가 저장할 수 없는 값이 payload에 섞여 있을 때 던진다.
///
/// 메시지에 **필드 경로와 실제 타입**이 들어 있어, 로그만 보고 어느 입력이
/// 문제인지 바로 알 수 있다.
class FirestorePayloadException implements Exception {
  /// 어느 저장을 하려다 걸렸는지(예: 'party-register').
  final String tag;

  /// `경로: 타입` 형태의 문제 목록.
  final List<String> issues;

  FirestorePayloadException(this.tag, this.issues);

  @override
  String toString() =>
      'FirestorePayloadException($tag): 저장할 수 없는 값 ${issues.length}개 — '
      '${issues.join(', ')}';
}

class FirestorePayload {
  FirestorePayload._();

  /// 저장 가능한 형태로 바꿀 수 있는 값은 바꾼 **새 맵**을 돌려준다.
  ///
  /// 이미 올바른 payload에는 아무 영향이 없다(같은 값이 그대로 나온다).
  /// 변환 규칙:
  ///   - `Set`            → `List`
  ///   - `Enum`           → `.name` 문자열
  ///   - `DateTime`       → [Timestamp]
  ///   - `Map`(키가 String이 아님) → 키를 `toString()` 한 `Map<String, dynamic>`
  ///   - `Iterable`       → `List`(원소도 재귀적으로 정규화)
  /// 그 밖의 알 수 없는 타입은 **그대로 둔다** — 조용히 문자열로 바꿔버리면
  /// 잘못된 값이 저장되므로, [describeIssues]/[assertSafe]가 잡도록 남긴다.
  static Map<String, dynamic> normalize(Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    data.forEach((key, value) => out[key] = _normalizeValue(value));
    return out;
  }

  static Object? _normalizeValue(Object? value) {
    if (value == null) return null;
    if (_isScalar(value)) return value;
    if (value is DateTime) return Timestamp.fromDate(value);
    if (value is Enum) return value.name;
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((k, v) => out['$k'] = _normalizeValue(v));
      return out;
    }
    // Set도 Iterable이라 여기서 List로 펴진다.
    if (value is Iterable) return value.map(_normalizeValue).toList();
    return value;
  }

  /// Firestore가 그대로 저장할 수 있는 단일 값인지.
  static bool _isScalar(Object? value) =>
      value == null ||
      value is bool ||
      value is num ||
      value is String ||
      value is Timestamp ||
      value is GeoPoint ||
      value is Blob ||
      value is DocumentReference ||
      value is FieldValue;

  /// 저장할 수 없는 값들의 `경로: 타입` 목록. 비어 있으면 안전한 payload다.
  ///
  /// [normalize]를 먼저 통과시킨 맵에 쓰는 것을 전제로 한다 — 그래야 남은
  /// 항목이 "정말 손쓸 수 없는 값"뿐이다.
  static List<String> describeIssues(Map<String, dynamic> data) {
    final issues = <String>[];
    data.forEach((key, value) => _collect(key, value, issues));
    return issues;
  }

  static void _collect(String path, Object? value, List<String> issues) {
    if (_isScalar(value)) return;
    if (value is Map) {
      value.forEach((k, v) {
        if (k is! String) {
          issues.add('$path.<key ${k.runtimeType}>: 키는 String이어야 합니다');
        }
        _collect('$path.$k', v, issues);
      });
      return;
    }
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        _collect('$path[$i]', value[i], issues);
      }
      return;
    }
    // DateTime/Enum/Set은 normalize가 이미 걸렀어야 한다 — 여기까지 왔다면
    // 정규화를 건너뛴 경로이므로 그대로 문제로 보고한다.
    issues.add('$path: ${value.runtimeType}');
  }

  /// [normalize] → [describeIssues] 를 한 번에. 문제가 있으면
  /// [FirestorePayloadException]을 던지고, 없으면 정규화된 맵을 돌려준다.
  ///
  /// 저장 직전에 호출한다 — 여기서 걸리면 네트워크를 타기 전에 멈추므로
  /// 반쪽만 저장되는 상태가 생기지 않는다.
  static Map<String, dynamic> assertSafe(
    Map<String, dynamic> data, {
    required String tag,
  }) {
    final normalized = normalize(data);
    final issues = describeIssues(normalized);
    if (issues.isNotEmpty) {
      throw FirestorePayloadException(tag, issues);
    }
    return normalized;
  }

  /// payload를 통째로 debugPrint 할 수 있는 JSON 문자열로 만든다.
  ///
  /// Timestamp/FieldValue처럼 jsonEncode가 모르는 값은 사람이 읽을 수 있는
  /// 표시로 바꾸고, 아주 긴 문자열(사진 URL 목록·상세 소개 등)은 잘라낸다 —
  /// 로그가 잘려서 정작 뒤쪽 필드를 못 보는 일을 막기 위해서다.
  static String sanitizeForLogJson(Map<String, dynamic> data) {
    try {
      return jsonEncode(_forLog(data));
    } catch (e) {
      return '<payload 직렬화 실패: $e>';
    }
  }

  /// jsonEncode 가능한 형태로 바꾼 사본(테스트/로그용).
  static Map<String, dynamic> sanitizeForLog(Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    data.forEach((key, value) => out[key] = _forLog(value));
    return out;
  }

  static const int _maxStringLength = 120;

  static Object? _forLog(Object? value) {
    if (value == null || value is bool || value is num) return value;
    if (value is String) {
      return value.length <= _maxStringLength
          ? value
          : '${value.substring(0, _maxStringLength)}…(${value.length}자)';
    }
    if (value is Timestamp) {
      return 'Timestamp(${value.toDate().toIso8601String()})';
    }
    if (value is DateTime) return 'DateTime(${value.toIso8601String()})';
    if (value is GeoPoint)
      return 'GeoPoint(${value.latitude},${value.longitude})';
    if (value is DocumentReference) return 'DocumentReference(${value.path})';
    if (value is FieldValue) return '<FieldValue>';
    if (value is Enum) return 'Enum(${value.name})';
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((k, v) => out['$k'] = _forLog(v));
      return out;
    }
    if (value is Iterable) return value.map(_forLog).toList();
    // 저장 불가 타입 — 값 내용이 아니라 "무슨 타입인지"가 중요하다.
    return '<${value.runtimeType}>';
  }

  /// 등록/수정 화면 공통 실패 로그 — 예외 타입·메시지·stackTrace·payload를
  /// 한 번에 남긴다. [stage]는 실패 단계('upload' | 'firestore' | 'post').
  static void logFailure({
    required String tag,
    required String stage,
    required Object error,
    required StackTrace stackTrace,
    Map<String, dynamic>? payload,
  }) {
    debugPrint('[$tag:$stage] error(${error.runtimeType}): $error');
    debugPrint('[$tag:$stage] stack: $stackTrace');
    if (payload != null) {
      debugPrint('[$tag:$stage] payload: ${sanitizeForLogJson(payload)}');
    }
  }
}
