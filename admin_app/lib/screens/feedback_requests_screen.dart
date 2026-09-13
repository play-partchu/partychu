import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';
import 'members_screen.dart' show OpenMember;

// 앱 '의견 보내기'로 들어온 글을 보는 화면 — Firestore `feedbackRequests`.
//
// 한 컬렉션에 개선 제안·버그 신고·이용 문의·기타가 **유형(type)으로만** 갈려
// 들어온다. 그래서 메뉴 이름도 '버그 신고'가 아니라 '의견·버그 신고'이고,
// 버그만 보려면 유형 필터를 쓴다.
//
// '시스템 오류' 메뉴와는 무관하다 — 그쪽은 스케줄 함수 실패 로그
// (systemFunctionErrors)라 사람이 쓴 글이 애초에 들어가지 않는다.

/// 앱 모델(party_app의 FeedbackType/FeedbackStatus)과 **같은 키**를 쓴다.
///
/// 관리자에서 새 키를 만들면 앱의 '내 의견' 화면이 라벨을 못 찾아 영문 키를
/// 그대로 보여준다 — 그래서 요청받은 접수/확인중/처리완료도 새로 만들지 않고
/// 이미 있는 키에 그대로 대응시킨다(접수=received, 확인 중=reviewing,
/// 처리 완료=answered).
const _typeLabels = {
  'bug': '버그 신고',
  'inquiry': '이용 문의',
  'payment': '결제/환불 문의',
  'host': '사업자/호스트 문의',
  // 고객센터 문의 선택지에는 없지만 옛 문서가 쓰던 값이다 — 지우면 그 글들이
  // 필터에서 사라지고 유형 배지도 영문 키로 보인다.
  'improvement': '개선 제안',
  'other': '기타 문의',
};

const _statusLabels = {
  'received': '접수',
  'reviewing': '확인 중',
  'planned': '처리 예정',
  'answered': '처리 완료',
  'hold': '보류',
};

const _statusColors = {
  'received': Color(0xFFE2568A),
  'reviewing': Color(0xFF9B5CFF),
  'planned': Color(0xFF2F80ED),
  'answered': Color(0xFF17924E),
  'hold': Color(0xFF8C7A87),
};

class FeedbackRequestsScreen extends StatefulWidget {
  final OpenMember onOpenMember;

  const FeedbackRequestsScreen({super.key, required this.onOpenMember});

  @override
  State<FeedbackRequestsScreen> createState() => _FeedbackRequestsScreenState();
}

class _FeedbackRequestsScreenState extends State<FeedbackRequestsScreen> {
  String? _typeFilter;
  String? _statusFilter;

  /// 열어 둔 글. null이면 목록.
  String? _openedId;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];

  /// 작성자 표시용 users 문서 — 신고 문서에는 UID만 있어서 따로 붙인다.
  Map<String, Map<String, dynamic>> _authors = {};

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap =
          await AdminFirestoreService.feedbackRequestsQuery().limit(200).get();
      final authors = await AdminFirestoreService.fetchUsersForUids(
        snap.docs
            .map((d) => d.data()['userId'] as String? ?? '')
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList(),
      );
      if (!mounted) return;
      setState(() {
        _docs = snap.docs;
        _authors = authors;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 화면에 그릴 목록 — 유형·상태 필터는 **여기서** 건다.
  ///
  /// 서버에 걸지 않는 이유는 [AdminFirestoreService.feedbackRequestsQuery]에
  /// 적어 뒀다(그 조합에 필요한 복합 색인이 아직 없다). 그래서 필터를 바꿔도
  /// 서버를 다시 부르지 않는다 — 이미 받아 둔 목록에서 걸러 낼 뿐이다.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _filtered => _docs
      .where((d) => _typeFilter == null || d.data()['type'] == _typeFilter)
      .where((d) => _statusFilter == null || d.data()['status'] == _statusFilter)
      .toList();

  /// 작성자 닉네임 — 없으면 '(알 수 없음)'. **UID를 닉네임 자리에 넣지 않는다**
  /// (회원 목록과 같은 원칙 — UID는 UID 칸에서만 보여준다).
  String _nicknameOf(String uid) {
    final nickname = _authors[uid]?['nickname'] as String?;
    if (nickname != null && nickname.isNotEmpty) return nickname;
    return _authors.containsKey(uid) ? '(닉네임 없음)' : '(알 수 없음)';
  }

  @override
  Widget build(BuildContext context) {
    final opened = _openedId;
    if (opened != null) {
      final matches = _docs.where((d) => d.id == opened);
      if (matches.isNotEmpty) {
        final doc = matches.first;
        return _FeedbackDetail(
          doc: doc,
          authorNickname: _nicknameOf(doc.data()['userId'] as String? ?? ''),
          onBack: () => setState(() => _openedId = null),
          onOpenMember: widget.onOpenMember,
          onSaved: () async {
            await _load();
            if (mounted) setState(() => _openedId = null);
          },
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('의견·버그 신고',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            if (!_loading)
              Text('${_filtered.length}건',
                  style: const TextStyle(
                      fontSize: 13, color: AdminTheme.textSecondary)),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '앱 "의견 보내기"로 접수된 글입니다 — 개선 제안·버그 신고·이용 문의가 유형으로 구분됩니다.',
          style: TextStyle(fontSize: 12, color: AdminTheme.textSecondary),
        ),
        const SizedBox(height: 16),
        _toolbar(),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminTheme.cardBorder),
            ),
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AdminTheme.accent))
                : _error != null
                    ? Center(child: Text('불러오지 못했습니다: $_error'))
                    : _filtered.isEmpty
                        ? const Center(
                            child: Text('접수된 의견이 없습니다.',
                                style:
                                    TextStyle(color: AdminTheme.textSecondary)))
                        : _table(),
          ),
        ),
      ],
    );
  }

  Widget _toolbar() => Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String?>(
            value: _typeFilter,
            hint: const Text('유형'),
            items: [
              const DropdownMenuItem(value: null, child: Text('유형 전체')),
              for (final e in _typeLabels.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) {
              setState(() => _typeFilter = v);
            },
          ),
          DropdownButton<String?>(
            value: _statusFilter,
            hint: const Text('처리상태'),
            items: [
              const DropdownMenuItem(value: null, child: Text('상태 전체')),
              for (final e in _statusLabels.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) {
              setState(() => _statusFilter = v);
            },
          ),
          if (_typeFilter != null || _statusFilter != null)
            TextButton(
              onPressed: () {
                setState(() {
                  _typeFilter = null;
                  _statusFilter = null;
                });
              },
              child: const Text('필터 초기화'),
            ),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('새로고침'),
          ),
        ],
      );

  Widget _table() => _FeedbackScrollableTable(
        child: DataTable(
          dataRowMinHeight: 46,
          dataRowMaxHeight: 62,
          columns: const [
            DataColumn(label: Text('접수일')),
            DataColumn(label: Text('유형')),
            DataColumn(label: Text('작성자')),
            DataColumn(label: Text('UID')),
            // 답변을 보낼 통로 — 작성자가 문의에 직접 적은 값이다(계정
            // 이메일이 아니다). 고객센터 문의 이전 글에는 없어서 '-'가 뜬다.
            DataColumn(label: Text('이메일')),
            DataColumn(label: Text('연락처')),
            DataColumn(label: Text('제목')),
            DataColumn(label: Text('내용')),
            DataColumn(label: Text('첨부')),
            DataColumn(label: Text('처리상태')),
          ],
          rows: [for (final doc in _filtered) _row(doc)],
        ),
      );

  DataRow _row(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final uid = d['userId'] as String? ?? '';
    final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
    final images = (d['imageUrls'] as List?) ?? const [];
    final title = d['title'] as String? ?? '';
    final content = (d['content'] as String? ?? '').replaceAll('\n', ' ');
    final contactEmail = d['contactEmail'] as String? ?? '';
    final contactPhone = d['contactPhone'] as String? ?? '';

    return DataRow(
      onSelectChanged: (_) => setState(() => _openedId = doc.id),
      cells: [
        DataCell(Text(createdAt == null
            ? '-'
            : DateFormat('yyyy.MM.dd HH:mm').format(createdAt))),
        DataCell(_TypeBadge(type: d['type'] as String?)),
        DataCell(Text(_nicknameOf(uid))),
        DataCell(SelectableText(
          uid.isEmpty ? '-' : uid,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        )),
        DataCell(SizedBox(
          width: 190,
          child: SelectableText(
            contactEmail.isEmpty ? '-' : contactEmail,
            style: const TextStyle(fontSize: 12.5),
            maxLines: 1,
          ),
        )),
        DataCell(SelectableText(
          contactPhone.isEmpty ? '-' : contactPhone,
          style: const TextStyle(fontSize: 12.5),
        )),
        DataCell(SizedBox(
          width: 220,
          child: Text(
            title.isEmpty ? '(제목 없음)' : title,
            overflow: TextOverflow.ellipsis,
          ),
        )),
        DataCell(SizedBox(
          width: 300,
          child: Text(
            content.isEmpty ? '-' : content,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AdminTheme.textSecondary),
          ),
        )),
        DataCell(images.isNotEmpty
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.attach_file,
                      size: 14, color: AdminTheme.textSecondary),
                  Text('${images.length}'),
                ],
              )
            // 사진 없는 버그 신고가 정당한 예외인지 목록에서 바로 보이게 한다.
            : d['screenshotUnavailable'] == true
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6E5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFF0D9A8)),
                    ),
                    child: const Text('캡처불가',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF8A6520))),
                  )
                : const Text('-')),
        DataCell(_StatusBadge(status: d['status'] as String?)),
      ],
    );
  }
}

/// 신고 전문 + 첨부 + 처리상태 변경.
class _FeedbackDetail extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String authorNickname;
  final VoidCallback onBack;
  final OpenMember onOpenMember;
  final Future<void> Function() onSaved;

  const _FeedbackDetail({
    required this.doc,
    required this.authorNickname,
    required this.onBack,
    required this.onOpenMember,
    required this.onSaved,
  });

  @override
  State<_FeedbackDetail> createState() => _FeedbackDetailState();
}

class _FeedbackDetailState extends State<_FeedbackDetail> {
  late String _status =
      widget.doc.data()['status'] as String? ?? 'received';
  late final _memoCtrl = TextEditingController(
      text: widget.doc.data()['adminMemo'] as String? ?? '');
  late final _replyCtrl = TextEditingController(
      text: widget.doc.data()['userReply'] as String? ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _memoCtrl.dispose();
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await AdminFirestoreService.updateFeedbackRequest(
        widget.doc.id,
        status: _status,
        adminMemo: _memoCtrl.text.trim(),
        userReply: _replyCtrl.text.trim(),
      );
      await widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('저장하지 못했습니다: $e')));
    }
  }

  static bool _hasDeviceMeta(Map<String, dynamic> d) =>
      (d['appVersion'] ??
          d['platform'] ??
          d['osVersion'] ??
          d['deviceInfo'] ??
          d['relatedScreen']) !=
      null;

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data();
    final uid = d['userId'] as String? ?? '';
    final title = d['title'] as String? ?? '';
    final content = d['content'] as String? ?? '';
    final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
    final updatedAt = (d['updatedAt'] as Timestamp?)?.toDate();
    final images = (d['imageUrls'] as List?) ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('목록'),
            ),
            const SizedBox(width: 8),
            _TypeBadge(type: d['type'] as String?),
            const SizedBox(width: 8),
            _StatusBadge(status: d['status'] as String?),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AdminTheme.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? '(제목 없음)' : title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _meta('작성자', widget.authorNickname),
                      _meta(
                          '접수일',
                          createdAt == null
                              ? '-'
                              : DateFormat('yyyy.MM.dd HH:mm:ss')
                                  .format(createdAt)),
                      _meta(
                          '최종 변경',
                          updatedAt == null
                              ? '-'
                              : DateFormat('yyyy.MM.dd HH:mm:ss')
                                  .format(updatedAt)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text('UID  ',
                          style: TextStyle(
                              fontSize: 12, color: AdminTheme.textSecondary)),
                      SelectableText(uid.isEmpty ? '-' : uid,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12)),
                      if (uid.isNotEmpty)
                        TextButton(
                          onPressed: () => widget.onOpenMember(uid),
                          child: const Text('회원 상세 열기'),
                        ),
                    ],
                  ),
                  const Divider(height: 28),
                  // 답변받을 연락처 — 작성자가 이 문의에 직접 적은 값이다.
                  // 계정 이메일과 다를 수 있으므로 회원 상세의 값으로
                  // 대체하지 말 것(여기 적힌 곳으로 답변해야 한다).
                  const Text('답변받을 연락처',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _selectableMeta('이메일',
                          (d['contactEmail'] as String? ?? '').isEmpty
                              ? '-'
                              : d['contactEmail'] as String),
                      _selectableMeta('연락처',
                          (d['contactPhone'] as String? ?? '').isEmpty
                              ? '-'
                              : d['contactPhone'] as String),
                    ],
                  ),
                  if ((d['contactEmail'] as String? ?? '').isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        '고객센터 문의 도입 이전에 접수된 글이라 연락처가 없습니다 — '
                        'UID로 회원 상세를 열어 확인하세요.',
                        style: TextStyle(
                            fontSize: 12, color: AdminTheme.textSecondary),
                      ),
                    ),
                  const Divider(height: 28),
                  const Text('문의 내용',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SelectableText(
                    content.isEmpty ? '(내용 없음)' : content,
                    style: const TextStyle(height: 1.6),
                  ),
                  const SizedBox(height: 20),
                  // 첨부는 Cloudflare R2 공개 URL이라 그대로 띄우면 된다
                  // (Storage 규칙이 걸린 신청자 사진과는 다른 저장소다).
                  //
                  // 버그 신고는 앱이 스크린샷을 필수로 받지만, **그 규칙이
                  // 생기기 전에 접수된 글에는 첨부가 없다.** 그래서 없을 때도
                  // 그냥 "없음"으로 열려야 한다 — 여기서 막으면 옛 신고를
                  // 아예 못 본다.
                  Text(
                    d['type'] == 'bug'
                        ? '오류 화면 스크린샷 ${images.length}장'
                        : '첨부 ${images.length}장',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (images.isEmpty)
                    // 사진 없는 버그 신고는 세 가지가 섞여 있다 — 작성자가
                    // "캡처 불가"를 고른 정당한 예외 / 필수화 이전의 옛 신고 /
                    // 그 외. 관리자가 이걸 구분 못 하면 예외 경로가 남용돼도
                    // 알 수 없으므로 화면에서 갈라 보여준다.
                    if (d['screenshotUnavailable'] == true)
                      _ScreenshotUnavailableNotice(
                        reason: d['screenshotUnavailableReason'] as String?,
                      )
                    else
                      Text(
                        d['type'] == 'bug'
                            ? '첨부 없음 (스크린샷 필수화 이전에 접수된 신고입니다)'
                            : '첨부 없음',
                        style: const TextStyle(
                            fontSize: 12.5, color: AdminTheme.textSecondary),
                      )
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final (i, url) in images.indexed)
                          if (url is String && url.isNotEmpty)
                            _Attachment(
                              url: url,
                              index: i,
                              total: images.length,
                            ),
                      ],
                    ),
                  const Divider(height: 28),
                  // 기기 정보는 버그 신고일 때만 앱이 수집한다 — 없는 글에는
                  // 빈 칸만 늘어나므로 통째로 뺀다.
                  if (_hasDeviceMeta(d)) ...[
                    const Text('제출 환경',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: [
                        _meta('앱 버전', d['appVersion'] as String? ?? '-'),
                        _meta('플랫폼', d['platform'] as String? ?? '-'),
                        _meta('OS', d['osVersion'] as String? ?? '-'),
                        _meta('기기', d['deviceInfo'] as String? ?? '-'),
                        _meta('관련 화면', d['relatedScreen'] as String? ?? '-'),
                      ],
                    ),
                    const Divider(height: 28),
                  ],
                  _editor(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _meta(String label, String value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label  ',
              style: const TextStyle(
                  fontSize: 12, color: AdminTheme.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 12.5)),
        ],
      );

  /// 연락처처럼 **그대로 복사해서 써야 하는** 값 — 드래그 선택이 되어야 한다.
  Widget _selectableMeta(String label, String value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label  ',
              style: const TextStyle(
                  fontSize: 12, color: AdminTheme.textSecondary)),
          SelectableText(value, style: const TextStyle(fontSize: 12.5)),
        ],
      );

  /// 고칠 수 있는 것은 처리상태·작성자 답변·관리자 메모 셋뿐이다 —
  /// firestore.rules가 관리자에게도 그 셋(+updatedAt)만 허용한다. 원문·작성자·
  /// 첨부는 관리자도 바꿀 수 없다.
  Widget _editor() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('처리', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('처리상태  ', style: TextStyle(fontSize: 13)),
              DropdownButton<String>(
                value: _statusLabels.containsKey(_status) ? _status : 'received',
                items: [
                  for (final e in _statusLabels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _status = v ?? _status),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _replyCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '작성자에게 보여줄 답변 (앱 "내 의견"에 표시됩니다)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _memoCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '관리자 메모 (작성자에게는 보이지 않습니다)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: AdminTheme.accent),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('저장'),
          ),
        ],
      );
}

/// "스크린샷을 남길 수 없는 오류"로 접수된 건임을 알리는 안내 박스.
/// 사진이 없는 이유가 작성자의 선택이었음을 관리자가 바로 알 수 있게 한다.
class _ScreenshotUnavailableNotice extends StatelessWidget {
  final String? reason;
  const _ScreenshotUnavailableNotice({required this.reason});

  @override
  Widget build(BuildContext context) {
    final text = (reason ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF0D9A8)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, size: 17, color: Color(0xFFB07D2B)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('작성자가 "스크린샷을 첨부할 수 없는 오류"로 접수했습니다.',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF8A6520))),
            const SizedBox(height: 4),
            SelectableText(
              text.isEmpty ? '사유 없음' : '사유: $text',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF8A6520)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// 첨부 한 장 — 눌러서 원본 크기로 본다.
///
/// 오류 스크린샷은 글자를 읽어야 원인을 알 수 있어서, 작은 다이얼로그로는
/// 쓸모가 없다. 화면 대부분을 쓰는 뷰어로 띄우고 확대·이동까지 열어 둔다.
class _Attachment extends StatelessWidget {
  final String url;
  final int index;
  final int total;
  const _Attachment({
    required this.url,
    required this.index,
    required this.total,
  });

  void _open(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '스크린샷 ${index + 1}/$total',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: '닫기',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 최대 5배까지 확대 — 스크린샷 안의 작은 글자를 읽기 위한 것이다.
              Flexible(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: size.width * 0.9,
                      maxHeight: size.height * 0.8,
                    ),
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : const SizedBox(
                              width: 80,
                              height: 80,
                              child: Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white),
                              ),
                            ),
                      errorBuilder: (_, _, _) => const Padding(
                        padding: EdgeInsets.all(40),
                        child: Text('이미지를 불러오지 못했습니다.',
                            style: TextStyle(color: Colors.white70)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => _open(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            url,
            width: 140,
            height: 140,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 140,
              height: 140,
              color: const Color(0xFFF2F3F7),
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined,
                  color: Colors.black26),
            ),
          ),
        ),
      );
}

class _TypeBadge extends StatelessWidget {
  final String? type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final isBug = type == 'bug';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isBug ? const Color(0xFFFFE9EF) : const Color(0xFFF0EEFB),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _typeLabels[type] ?? (type ?? '-'),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: isBug ? const Color(0xFFE2568A) : const Color(0xFF6B5AC7),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String? status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[status] ?? AdminTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabels[status] ?? (status ?? '-'),
        style: TextStyle(
            fontSize: 11.5, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

/// 회원 관리 표와 같은 스크롤 처리 — 데스크톱 웹에서 가로 스크롤바를 항상
/// 띄우고, 열이 넘쳐도 오른쪽 끝까지 볼 수 있게 한다
/// (members_screen.dart의 _ScrollableTable과 같은 이유. 두 화면이 다른
/// 파일이라 private 위젯을 공유하지 못해 같은 모양을 한 벌 더 둔다).
class _FeedbackScrollableTable extends StatefulWidget {
  final Widget child;
  const _FeedbackScrollableTable({required this.child});

  @override
  State<_FeedbackScrollableTable> createState() =>
      _FeedbackScrollableTableState();
}

class _FeedbackScrollableTableState extends State<_FeedbackScrollableTable> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
        controller: _vertical,
        thumbVisibility: true,
        child: Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          notificationPredicate: (n) => n.depth == 1,
          child: SingleChildScrollView(
            controller: _vertical,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: widget.child,
            ),
          ),
        ),
      );
}
