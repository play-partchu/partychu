import 'package:flutter/material.dart';

import '../services/admin_firestore_service.dart';
import '../services/crm_export_service.dart';
import '../theme/admin_theme.dart';
import '../widgets/stat_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _startOfWeek() {
    final today = _startOfToday();
    return today.subtract(Duration(days: today.weekday - 1));
  }

  DateTime _startOfMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final sections = <String, List<Widget>>{
      '회원': [
        StatCard(label: '전체 가입자', future: AdminFirestoreService.totalUsers()),
        StatCard(label: '본인확인 완료', future: AdminFirestoreService.verifiedUsers()),
        StatCard(
          label: '오늘 활성 사용자',
          future: AdminFirestoreService.activeUsersSince(_startOfToday()),
          caption: '앱을 연 시각 기준',
        ),
        StatCard(
          label: '이번 주 활성 사용자',
          future: AdminFirestoreService.activeUsersSince(_startOfWeek()),
        ),
        StatCard(
          label: '이번 달 활성 사용자',
          future: AdminFirestoreService.activeUsersSince(_startOfMonth()),
        ),
      ],
      '파티 · 참여': [
        StatCard(label: '등록된 파티 수', future: AdminFirestoreService.totalParties()),
        StatCard(label: '파티 신청 수', future: AdminFirestoreService.totalApplications()),
        StatCard(
          label: '승인 수',
          future: AdminFirestoreService.applicationsByStatus('approved'),
          caption: '집계 시작 이후 누적',
        ),
        StatCard(
          label: '실제 참여 수',
          future: AdminFirestoreService.applicationsByStatus('attended'),
          caption: '집계 시작 이후 누적',
        ),
        StatCard(
          label: '취소 수',
          future: AdminFirestoreService.applicationsByStatus('cancelled'),
          caption: '집계 시작 이후 누적',
        ),
        StatCard(
          label: '노쇼 수',
          future: AdminFirestoreService.applicationsByStatus('no_show'),
          caption: '집계 시작 이후 누적',
        ),
      ],
      '콘텐츠 · 운영': [
        StatCard(label: '장소 수', future: AdminFirestoreService.totalPlaces()),
        StatCard(label: '파티샵 수', future: AdminFirestoreService.totalPartyShops()),
        StatCard(
          label: '미처리 의견 및 신고 수',
          future: () async {
            final feedback = await AdminFirestoreService.pendingFeedbackCount();
            final reports = await AdminFirestoreService.pendingReportCount();
            return feedback + reports;
          }(),
        ),
        StatCard(
          label: '스케줄 함수 오류',
          future: AdminFirestoreService.recentSystemFunctionErrorsCount(),
          caption: '최근 24시간 — "시스템 오류" 메뉴에서 상세 확인',
        ),
      ],
    };

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('대시보드', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              const _CrmExportButton(),
            ],
          ),
          const SizedBox(height: 20),
          for (final entry in sections.entries) ...[
            Text(entry.key,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AdminTheme.textSecondary)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final card in entry.value) SizedBox(width: 220, child: card),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}

/// parties/places를 읽기 전용으로 조회해 영업 CRM을 만드는 버튼 모음 —
/// crm_export_service.dart(adminGenerateCrmGoogleSheet/adminExportCrmData
/// Cloud Function 호출) 참고. Firestore에는 어떤 쓰기도 하지 않는다(서버
/// 함수가 parties/places를 .get()만 호출). Google Sheets 쪽은 서비스 계정
/// 인증이라 사람의 로그인/동의 절차가 없다.
class _CrmExportButton extends StatefulWidget {
  const _CrmExportButton();

  @override
  State<_CrmExportButton> createState() => _CrmExportButtonState();
}

class _CrmExportButtonState extends State<_CrmExportButton> {
  bool _generating = false;
  bool _downloadingExcel = false;

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final result = await CrmExportService.generateGoogleSheet();
      if (!mounted) return;
      final url = result['url'] as String;
      final rowCount = (result['rowCount'] as num?)?.toInt() ?? 0;
      final isNew = result['isNew'] as bool? ?? false;
      final updated = (result['updatedCount'] as num?)?.toInt() ?? 0;
      final appended = (result['appendedCount'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isNew
              ? 'PartyChu CRM 시트를 새로 만들었습니다 — $rowCount개 행'
              : '갱신 완료 — 신규 $appended행, 기존 $updated행 업데이트(영업 기록은 보존됨)'),
          action: SnackBarAction(label: '구글시트 열기', onPressed: () => CrmExportService.openUrl(url)),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('생성 실패: $e')));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _downloadExcel() async {
    setState(() => _downloadingExcel = true);
    try {
      final rowCount = await CrmExportService.exportAndDownload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('엑셀 내보내기 완료 — $rowCount개 행 (.xlsx, .csv 다운로드됨)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('내보내기 실패: $e')));
    } finally {
      if (mounted) setState(() => _downloadingExcel = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          onPressed: _generating ? null : _generate,
          icon: _generating
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.table_chart_outlined, size: 18),
          label: Text(_generating ? '생성 중...' : 'Google Sheets 생성'),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: _downloadingExcel ? null : _downloadExcel,
          icon: _downloadingExcel
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.file_download_outlined, size: 16),
          label: const Text('엑셀로 다운로드(선택)', style: TextStyle(fontSize: 12.5)),
        ),
      ],
    );
  }
}
