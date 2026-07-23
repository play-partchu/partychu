import 'dart:convert';
import 'dart:html' as html;

import 'package:cloud_functions/cloud_functions.dart';

const _functionsRegion = 'asia-northeast3';

/// "Google Sheets 내보내기" 버튼 — parties/places를 읽기 전용으로 조회해
/// 만든 영업 CRM용 .xlsx/.csv를 adminExportCrmData(Cloud Functions onCall,
/// crmExport.js/crmExportWriters.js)에서 받아 브라우저 다운로드로 바로
/// 저장한다. Firestore에는 어떤 쓰기도 하지 않는다(서버 함수가 .get()만 호출).
class CrmExportService {
  /// 반환값: 실제로 포함된 행 수(0이면 현재 실사용자 파티/플레이스가 없다는
  /// 뜻 — 버튼을 누른 쪽에서 안내 메시지로 보여줄 수 있게 그대로 돌려준다).
  static Future<int> exportAndDownload() async {
    final result = await FirebaseFunctions.instanceFor(region: _functionsRegion)
        .httpsCallable('adminExportCrmData')
        .call();
    final data = Map<String, dynamic>.from(result.data as Map);

    final xlsxBytes = base64Decode(data['xlsxBase64'] as String);
    final csvBytes = base64Decode(data['csvBase64'] as String);

    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    _downloadBytes(
      xlsxBytes,
      'partychu_crm_$stamp.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    _downloadBytes(csvBytes, 'partychu_crm_$stamp.csv', 'text/csv;charset=utf-8');

    return (data['rowCount'] as num?)?.toInt() ?? 0;
  }

  static void _downloadBytes(List<int> bytes, String filename, String mimeType) {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
    anchor.remove();
  }

  /// partychu-crm-sheets 서비스 계정으로 실행되는 Cloud Function이
  /// partner@partychu.co.kr Workspace의 공유 드라이브 안에 "PartyChu CRM"
  /// 시트를 생성하거나(없으면) 갱신한다(있으면 — 사람이 입력한 영업 기록은
  /// 보존됨). 사람의 Google 로그인/동의 절차가 필요 없다(서비스 계정 인증).
  /// 반환값의 url을 그대로 "구글시트 열기" 버튼에 연결하면 된다.
  static Future<Map<String, dynamic>> generateGoogleSheet() async {
    final result = await FirebaseFunctions.instanceFor(region: _functionsRegion)
        .httpsCallable('adminGenerateCrmGoogleSheet')
        .call();
    return Map<String, dynamic>.from(result.data as Map);
  }

  static void openUrl(String url) => html.window.open(url, '_blank');
}
