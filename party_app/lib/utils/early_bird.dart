import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/utils/format_utils.dart' as fmt;

/// 얼리버드 할인 계산 공통 유틸.
/// 등록/수정/메인 리스트/상세/검색/결제 전 구간에서 동일한 로직을 사용해야
/// "표시 가격"과 "실제 결제 가격"이 항상 일치한다.
class EarlyBird {
  EarlyBird._();

  /// 얼리버드가 현재 시점에 유효한지 여부.
  /// enabled 플래그와 종료시각(earlyBirdEndAt)만으로 판단 — 별도 배치/스케줄러 없이
  /// 매 조회 시점에 자동으로 종료 처리된다.
  static bool isActive(Map<String, dynamic> data, {DateTime? now}) {
    if (data['earlyBirdEnabled'] != true) return false;
    final end = endAt(data);
    if (end == null) return false;
    return end.isAfter(now ?? DateTime.now());
  }

  static int discountPercent(Map<String, dynamic> data) =>
      (data['earlyBirdDiscountPercent'] as num?)?.toInt() ?? 0;

  static DateTime? endAt(Map<String, dynamic> data) {
    final ts = data['earlyBirdEndAt'];
    if (ts is Timestamp) return ts.toDate();
    return null;
  }

  /// 정상가 대비 얼리버드가 유효할 때만 할인된 가격을 반환 (0원 미만 불가).
  /// 무료(baseFee <= 0)인 경우 항상 그대로 반환.
  static int effectivePrice(int baseFee, Map<String, dynamic> data, {DateTime? now}) {
    if (baseFee <= 0) return baseFee;
    if (!isActive(data, now: now)) return baseFee;
    final pct = discountPercent(data);
    final discounted = (baseFee * (100 - pct) / 100).round();
    return discounted < 0 ? 0 : discounted;
  }

  /// "2일 13시간" 형태의 잔여시간 라벨. 이미 종료됐으면 빈 문자열.
  static String remainingLabel(Map<String, dynamic> data, {DateTime? now}) {
    final end = endAt(data);
    if (end == null) return '';
    final n = now ?? DateTime.now();
    final diff = end.difference(n);
    if (diff.isNegative) return '';
    final days = diff.inDays;
    final hours = diff.inHours.remainder(24);
    final minutes = diff.inMinutes.remainder(60);
    if (days > 0) return '$days일 $hours시간';
    if (hours > 0) return '$hours시간 $minutes분';
    return '$minutes분';
  }

  /// "D-2" 형태의 디데이 라벨 (달력일 기준). 이미 종료됐으면 빈 문자열.
  static String dDayLabel(Map<String, dynamic> data, {DateTime? now}) {
    final end = endAt(data);
    if (end == null) return '';
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final days = endDay.difference(today).inDays;
    if (days < 0) return '';
    return 'D-$days';
  }

  static String formatEndAt(DateTime end) {
    final m = end.month.toString().padLeft(2, '0');
    final d = end.day.toString().padLeft(2, '0');
    final h = end.hour.toString().padLeft(2, '0');
    final mi = end.minute.toString().padLeft(2, '0');
    return '${end.year}.$m.$d $h:$mi';
  }

  /// 앱 전체 공통 포맷(lib/utils/format_utils.dart)으로 위임 — 여기 있던
  /// 자체 구현은 다른 화면들의 중복 구현과 함께 통일했다.
  static String formatPrice(int price) => fmt.formatPrice(price);
}
