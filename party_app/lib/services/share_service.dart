import 'package:intl/intl.dart';
import 'package:party_app/services/analytics_service.dart';
import 'package:party_app/utils/early_bird.dart';

/// 모임 공유 공통 로직 — 공유 URL/문구를 만들고 공유 이벤트를 기록한다.
/// 실제 공유 실행(카카오톡/문자/이메일/링크복사/더보기)은
/// `widgets/share_bottom_sheet.dart`에서 처리하고, 이 서비스는 "무엇을
/// 공유할지"만 담당한다.
class ShareService {
  ShareService._();

  /// 딥링크가 아직 없어 이 함수 하나로 URL 생성을 분리해둔다 — 나중에 실제
  /// 딥링크(Firebase Dynamic Links 등)로 바꿀 때 이 함수만 고치면 된다.
  ///
  /// ⚠️ 주의: 지금은 website에 이 경로에 대응하는 페이지가 없어 실제로는
  /// 열리지 않는다. 배포 전에 최소한 리다이렉트 페이지나 서버 라우트를
  /// 추가해야 한다.
  static String buildPartyShareUrl(String partyId) {
    return 'https://partychu.co.kr/party/$partyId';
  }

  static String _addressLabel(Map<String, dynamic> data) {
    final roadAddress = data['roadAddress'] as String? ?? '';
    final base = roadAddress.isNotEmpty
        ? roadAddress
        : (data['address'] as String?)?.isNotEmpty == true
        ? data['address'] as String
        : data['location'] as String? ?? '';
    if (base.isEmpty) return '';
    // 공유받는 사람이 실제로 찾아와야 하므로, 목록 카드와 달리 상세주소까지 붙여
    // 전체 주소를 그대로 보여준다(주소 비공개 기능이 없어 항상 노출됨).
    final detailAddress = data['detailAddress'] as String? ?? '';
    return detailAddress.isNotEmpty ? '$base $detailAddress' : base;
  }

  static String _feeLabel(Map<String, dynamic> data) {
    final maleFee = (data['maleFee'] as num?)?.toInt();
    final femaleFee = (data['femaleFee'] as num?)?.toInt();
    final fee = (data['fee'] as num?)?.toInt();
    if (maleFee != null && femaleFee != null && maleFee != femaleFee) {
      return '여성 ${EarlyBird.formatPrice(femaleFee)} · 남성 ${EarlyBird.formatPrice(maleFee)}';
    }
    return EarlyBird.formatPrice(maleFee ?? femaleFee ?? fee ?? 0);
  }

  /// 카카오톡/문자/이메일/더보기 공유에 공통으로 쓰는 텍스트.
  static String buildShareText(Map<String, dynamic> partyData, String url) {
    final title = partyData['title'] as String? ?? '파티';
    final address = _addressLabel(partyData);
    final partyDateTime = partyData['partyDateTime'];
    final dateLabel = partyDateTime != null && partyDateTime is! String
        ? _formatDateTime(partyDateTime)
        : (partyData['date'] as String? ?? '');
    final feeLabel = _feeLabel(partyData);

    final buffer = StringBuffer()
      ..writeln('🎉 $title')
      ..writeln();
    if (address.isNotEmpty) buffer.writeln('📍 $address');
    if (dateLabel.isNotEmpty) buffer.writeln('📅 $dateLabel');
    buffer
      ..writeln('💰 $feeLabel')
      ..writeln()
      ..writeln('PartyChu에서 확인하기')
      ..write(url);
    return buffer.toString();
  }

  /// 카카오톡 Feed 템플릿처럼 한 줄 요약이 필요한 곳에서 쓰는 짧은 설명.
  static String buildShortDescription(Map<String, dynamic> partyData) {
    final address = _addressLabel(partyData);
    final partyDateTime = partyData['partyDateTime'];
    final dateLabel = partyDateTime != null && partyDateTime is! String
        ? _formatDateTime(partyDateTime)
        : (partyData['date'] as String? ?? '');
    final parts = [
      if (dateLabel.isNotEmpty) dateLabel,
      if (address.isNotEmpty) address,
      _feeLabel(partyData),
    ];
    return parts.join(' · ');
  }

  static String _formatDateTime(dynamic timestamp) {
    try {
      final date = (timestamp as dynamic).toDate();
      return DateFormat(
        'yyyy.MM.dd (E) a h:mm',
        'ko_KR',
      ).format(date as DateTime);
    } catch (_) {
      return '';
    }
  }

  static void logShareEvent(String partyId) {
    AnalyticsService.logEvent(AnalyticsEventType.partyShare, partyId: partyId);
  }
}
