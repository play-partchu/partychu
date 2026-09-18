import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/host_pre_registration.dart';
import '../services/host_pre_registration_service.dart';
import '../theme/admin_theme.dart';
import '../utils/responsive.dart';
import '../widgets/host_pre_registration_field_map_dialog.dart';

/// 호스트 사전등록 목록 — FormHug 신청서가 웹훅으로 쌓이는 곳.
///
/// 읽기는 hostPreRegistrations를 실시간으로 받는다(규칙: 관리자 읽기만).
/// 상태를 바꾸는 모든 처리는 상세 화면의 콜러블을 거친다.
class HostPreRegistrationsScreen extends StatefulWidget {
  final ValueChanged<String> onOpen;
  const HostPreRegistrationsScreen({super.key, required this.onOpen});

  @override
  State<HostPreRegistrationsScreen> createState() => _HostPreRegistrationsScreenState();
}

class _HostPreRegistrationsScreenState extends State<HostPreRegistrationsScreen> {
  static const _chipFilters = [
    PreRegFilter.all,
    PreRegFilter.newOnly,
    PreRegFilter.inProgress,
    PreRegFilter.representativeRequired,
    PreRegFilter.done,
  ];

  late final Stream<List<HostPreRegistration>> _stream = HostPreRegistrationService.watchLatest();
  late final Stream<bool> _fieldMapReady = HostPreRegistrationService.watchFieldMapReady();
  final _searchCtrl = TextEditingController();
  PreRegFilter _filter = PreRegFilter.all;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 12),
        _fieldMapBanner(),
        _filters(),
        const SizedBox(height: 12),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _header() {
    const title = Text('호스트 사전등록', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold));
    final actions = [
      OutlinedButton.icon(
        onPressed: () => showHostPreRegistrationFieldMapDialog(context),
        icon: const Icon(Icons.link, size: 16),
        label: const Text('폼 필드 연결'),
      ),
      ElevatedButton.icon(
        onPressed: () => HostPreRegistrationService.openInNewTab(HostPreRegistrationService.formUrl),
        icon: const Icon(Icons.open_in_new, size: 16),
        label: const Text('신청폼 열기'),
      ),
    ];
    // 좁은 화면에서는 제목과 버튼을 한 줄에 두면 버튼이 화면 밖으로 밀린다 —
    // 제목 아래로 내리고 버튼끼리 줄바꿈시킨다.
    if (context.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      );
    }
    return Row(
      children: [
        title,
        const Spacer(),
        actions[0],
        const SizedBox(width: 8),
        actions[1],
      ],
    );
  }

  Widget _fieldMapBanner() {
    return StreamBuilder<bool>(
      stream: _fieldMapReady,
      builder: (context, snap) {
        if (!snap.hasData || snap.data == true) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFFD591)),
          ),
          child: const Text(
            'FormHug 폼 필드 연결이 아직 저장되지 않았습니다. 신청은 번호만 접수되고, '
            '"폼 필드 연결"을 저장하면 내용을 가져옵니다.',
            style: TextStyle(fontSize: 13),
          ),
        );
      },
    );
  }

  Widget _filters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final f in _chipFilters)
          ChoiceChip(
            label: Text(f.label),
            selected: _filter == f,
            onSelected: (_) => setState(() => _filter = f),
          ),
        const SizedBox(width: 12),
        TextButton.icon(
          onPressed: () => setState(() => _filter = PreRegFilter.unprocessed),
          icon: const Icon(Icons.inbox_outlined, size: 16),
          label: Text('미처리만 보기${_filter == PreRegFilter.unprocessed ? ' ✓' : ''}'),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _filter = PreRegFilter.representativeRequired),
          icon: const Icon(Icons.warning_amber_rounded, size: 16),
          label: const Text('대표자 확인 필요만 보기'),
        ),
        SizedBox(
          // 넓은 화면에서는 기존 320, 좁으면 본문 폭까지만.
          width: context.fluid(320),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: '업체명·사업자번호·이름·이메일·전화번호',
            ),
          ),
        ),
      ],
    );
  }

  Widget _body() {
    return StreamBuilder<List<HostPreRegistration>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('불러오지 못했습니다: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AdminTheme.accent));
        }
        final all = snap.data!;
        final rows = all
            .where(_filter.matches)
            .where((p) => p.matchesQuery(_searchCtrl.text))
            .toList();
        final newCount = all.where((p) => p.isNew).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '표시 ${rows.length}건 / 전체 ${all.length}건 · 신규 $newCount건',
              style: const TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('해당하는 신청이 없습니다.'))
                  : _table(rows),
            ),
          ],
        );
      },
    );
  }

  Widget _table(List<HostPreRegistration> rows) {
    final fmt = DateFormat('yyyy.MM.dd HH:mm');
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminTheme.cardBorder),
      ),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('신청일시')),
              DataColumn(label: Text('업체명')),
              DataColumn(label: Text('사업자번호')),
              DataColumn(label: Text('호스트 이름')),
              DataColumn(label: Text('호스트 이메일')),
              DataColumn(label: Text('사용기기')),
              DataColumn(label: Text('대표자 동일')),
              DataColumn(label: Text('상태')),
            ],
            rows: [
              for (final p in rows)
                DataRow(
                  // 신규 신청은 행 전체를 강조한다.
                  color: p.isNew ? const WidgetStatePropertyAll(AdminTheme.accentLight) : null,
                  onSelectChanged: (_) => widget.onOpen(p.id),
                  cells: [
                    DataCell(Text(p.submittedAt == null ? '-' : fmt.format(p.submittedAt!))),
                    DataCell(Text(p.imported ? (p.storeName.isEmpty ? '-' : p.storeName) : '(내용 가져오기 전)')),
                    DataCell(Text(formatBusinessNumber(p.businessRegistrationNumber))),
                    DataCell(Text(p.hostName.isEmpty ? '-' : p.hostName)),
                    DataCell(Text(p.hostEmail.isEmpty ? '-' : p.hostEmail)),
                    DataCell(Text(p.deviceLabel)),
                    DataCell(Text(
                      p.sameAsRepresentativeLabel,
                      style: TextStyle(
                        color: p.sameAsRepresentative == false ? const Color(0xFFB45309) : null,
                        fontWeight: p.sameAsRepresentative == false ? FontWeight.bold : null,
                      ),
                    )),
                    DataCell(PreRegStatusBadge(status: p.status, isNew: p.isNew)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PreRegStatusBadge extends StatelessWidget {
  final PreRegStatus status;
  final bool isNew;
  const PreRegStatusBadge({super.key, required this.status, this.isNew = false});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      PreRegStatus.newApplication => (AdminTheme.accent, Colors.white),
      PreRegStatus.verified => (const Color(0xFFD1FAE5), const Color(0xFF047857)),
      PreRegStatus.rejected => (const Color(0xFFF3F4F6), const Color(0xFF6B7280)),
      PreRegStatus.representativeVerificationRequired ||
      PreRegStatus.representativeLinkSent =>
        (const Color(0xFFFEF3C7), const Color(0xFFB45309)),
      _ => (const Color(0xFFE0E7FF), const Color(0xFF3730A3)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        isNew ? 'NEW · ${status.label}' : status.label,
        style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
