import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';

/// 스케줄 함수(만료 처리, 자동 삭제 등)가 실패했을 때
/// logScheduledFunctionError(memberActivityHelpers.js)가 남기는 기록을
/// 보여준다 — 지금까지는 gcloud logging으로만 확인 가능했던 실패를
/// 관리자 웹에서 바로 볼 수 있도록 한다.
class SystemErrorsScreen extends StatefulWidget {
  const SystemErrorsScreen({super.key});

  @override
  State<SystemErrorsScreen> createState() => _SystemErrorsScreenState();
}

class _SystemErrorsScreenState extends State<SystemErrorsScreen> {
  late Future<QuerySnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = AdminFirestoreService.systemFunctionErrorsQuery().get();
  }

  void _refresh() {
    setState(() {
      _future = AdminFirestoreService.systemFunctionErrorsQuery().get();
    });
  }

  String _fmtDate(dynamic v) {
    if (v is Timestamp) return DateFormat('yyyy.MM.dd HH:mm:ss').format(v.toDate());
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('시스템 오류', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            const Text('스케줄 함수(만료 처리, 자동 삭제 등) 실패 기록 — 최근 100건',
                style: TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary)),
            const Spacer(),
            IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '새로고침',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminTheme.cardBorder),
            ),
            child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AdminTheme.accent));
                }
                if (snap.hasError) {
                  return Center(child: Text('불러오지 못했습니다: ${snap.error}'));
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                      child: Text('최근 기록된 스케줄 함수 오류가 없습니다.', style: TextStyle(color: AdminTheme.textSecondary)));
                }
                return SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('발생 시각')),
                        DataColumn(label: Text('함수명')),
                        DataColumn(label: Text('메시지')),
                        DataColumn(label: Text('컨텍스트')),
                      ],
                      rows: [
                        for (final doc in docs)
                          DataRow(cells: [
                            DataCell(Text(_fmtDate(doc.data()['occurredAt']))),
                            DataCell(Text(doc.data()['functionName'] as String? ?? '-')),
                            DataCell(SizedBox(
                              width: 480,
                              child: Text(
                                doc.data()['message'] as String? ?? '-',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            )),
                            DataCell(Text(
                              doc.data()['context'] != null ? doc.data()['context'].toString() : '-',
                            )),
                          ]),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
