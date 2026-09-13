import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';
import 'members_screen.dart' show OpenMember;

class VerifiedUsersScreen extends StatelessWidget {
  final OpenMember onOpenMember;
  const VerifiedUsersScreen({super.key, required this.onOpenMember});

  String _formatBirth(Map<String, dynamic> d) {
    final y = d['birthYear'];
    final m = d['birthMonth'];
    final day = d['birthDay'];
    if (y == null) return '-';
    if (m == null || day == null) return '$y';
    return '$y.${m.toString().padLeft(2, '0')}.${day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('본인확인 사용자 목록', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        // 이 목록은 identityVerified == true 하나만 본다 — 회원 관리와 달리
        // 테스트 계정을 걸러내지 않아 두 화면의 사람 수가 다르게 보인다.
        // 숨기는 대신 어느 줄이 테스트 계정인지 맨 오른쪽에 표시한다.
        const Text(
          '본인확인을 마친 계정 전체입니다 — 회원 관리와 달리 테스트 계정도 함께 나옵니다.',
          style: TextStyle(fontSize: 12, color: AdminTheme.textSecondary),
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
              future: AdminFirestoreService.verifiedUsersQuery().get(),
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
                      child: Text('본인확인을 완료한 사용자가 없습니다.', style: TextStyle(color: AdminTheme.textSecondary)));
                }
                return SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('이름')),
                        DataColumn(label: Text('생년월일')),
                        DataColumn(label: Text('성별')),
                        DataColumn(label: Text('닉네임')),
                        DataColumn(label: Text('UID')),
                        DataColumn(label: Text('인증완료일')),
                        DataColumn(label: Text('인증상태')),
                        DataColumn(label: Text('테스트')),
                      ],
                      rows: [
                        for (final doc in docs)
                          DataRow(
                            onSelectChanged: (_) => onOpenMember(doc.id),
                            cells: [
                              DataCell(Text(doc.data()['name'] as String? ?? '-')),
                              DataCell(Text(_formatBirth(doc.data()))),
                              DataCell(Text(doc.data()['gender'] == 'male'
                                  ? '남성'
                                  : doc.data()['gender'] == 'female'
                                      ? '여성'
                                      : '-')),
                              DataCell(Text(doc.data()['nickname'] as String? ?? '-')),
                              DataCell(Text(doc.id)),
                              DataCell(Text(_fmtDate(doc.data()['identityVerifiedAt']))),
                              DataCell(_ProviderBadge(provider: doc.data()['verificationProvider'] as String?)),
                              DataCell(Text(
                                doc.data()['isTestAccount'] == true ? 'O' : '-',
                              )),
                            ],
                          ),
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

  String _fmtDate(dynamic ts) {
    if (ts is! Timestamp) return '-';
    return DateFormat('yyyy.MM.dd HH:mm').format(ts.toDate());
  }
}

class _ProviderBadge extends StatelessWidget {
  final String? provider;
  const _ProviderBadge({required this.provider});

  @override
  Widget build(BuildContext context) {
    final label = switch (provider) {
      'nice_intc_v2' => '인증완료 (NICE)',
      'nice_intc' => '인증완료 (NICE 구버전)',
      _ => '인증완료',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: const Color(0xFFE6F7ED), borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF17924E))),
    );
  }
}
