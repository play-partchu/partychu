import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/party_form/date_time_sheet.dart';
import 'package:party_app/widgets/party_form/section_summary_row.dart';

class PartyReRegisterScreen extends StatefulWidget {
  final Map<String, dynamic> sourceData;
  final String sourcePartyId;

  const PartyReRegisterScreen({
    super.key,
    required this.sourceData,
    required this.sourcePartyId,
  });

  @override
  State<PartyReRegisterScreen> createState() => _PartyReRegisterScreenState();
}

class _PartyReRegisterScreenState extends State<PartyReRegisterScreen> {
  DateTime? _partyDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  DateTime? _recruitDeadlineDate;
  TimeOfDay? _recruitDeadlineTime;
  bool _isSubmitting = false;
  bool _showDateError = false;

  String get _title => widget.sourceData['title'] as String? ?? '';
  String get _category => widget.sourceData['category'] as String? ?? '';

  Future<void> _openDateTimeSheet() async {
    final result = await showPartyDateTimeSheet(
      context,
      initial: PartyDateTimeDraft(
        partyDate: _partyDate,
        startTime: _startTime,
        endTime: _endTime,
        recruitDeadlineTime: _recruitDeadlineTime,
        recruitDeadlineDate: _recruitDeadlineDate,
      ),
      // 재등록의 모집마감 날짜는 파티 날짜와 독립적으로 고른다(기존 동작
      // 그대로) — 등록/수정 화면처럼 파티 날짜를 공유하지 않는다.
      deadlineHasOwnDate: true,
    );
    if (result == null) return;
    setState(() {
      _partyDate = result.partyDate;
      _startTime = result.startTime;
      _endTime = result.endTime;
      _recruitDeadlineDate = result.recruitDeadlineDate;
      _recruitDeadlineTime = result.recruitDeadlineTime;
      _showDateError = false;
    });
  }

  String? _dateTimeSummary() {
    if (_partyDate == null || _startTime == null) return null;
    var s = '${formatPartyDate(_partyDate)} ${formatPartyTime(_startTime)}';
    if (_endTime != null) s += ' ~ ${formatPartyTime(_endTime)}';
    return s;
  }

  String? _dateTimeErrorText() {
    if (_partyDate == null && _startTime == null) return '파티 날짜와 시작 시간을 선택해줘';
    if (_partyDate == null) return '파티 날짜를 선택해줘';
    if (_startTime == null) return '시작 시간을 선택해줘';
    return null;
  }

  Future<void> _submit() async {
    final dateError = _partyDate == null;
    final timeError = _startTime == null;
    setState(() => _showDateError = dateError || timeError);

    if (dateError) {
      _snack('파티 날짜를 선택해줘');
      return;
    }
    if (timeError) {
      _snack('시작 시간을 선택해줘');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final partyDateTime = DateTime(
        _partyDate!.year, _partyDate!.month, _partyDate!.day,
        _startTime!.hour, _startTime!.minute,
      );
      final deadlineDateTime = (_recruitDeadlineDate != null && _recruitDeadlineTime != null)
          ? DateTime(
              _recruitDeadlineDate!.year, _recruitDeadlineDate!.month, _recruitDeadlineDate!.day,
              _recruitDeadlineTime!.hour, _recruitDeadlineTime!.minute,
            )
          : null;

      // 소스 데이터에서 복사, 날짜/시간/카운터 필드만 교체
      final newData = Map<String, dynamic>.from(widget.sourceData)
        ..remove('createdAt')
        ..remove('lastUsedAt')
        ..remove('recruitDeadlineAt');

      final maxCapacity = (newData['maxCapacity'] as int?) ??
          (newData['maxParticipants'] as int?) ?? 0;

      newData['date'] = '${formatPartyDate(_partyDate)} ${formatPartyTime(_startTime)}';
      newData['partyDateTime'] = Timestamp.fromDate(partyDateTime);
      newData['currentParticipants'] = 0;
      newData['currentMaleCount'] = 0;
      newData['currentFemaleCount'] = 0;
      newData['people'] = '0/$maxCapacity명';
      newData['applicants'] = [];
      newData['approvedApplicants'] = [];
      newData['recruitStatus'] = '모집중';
      newData['isRecurring'] = true;
      newData['hostId'] = UserSession.userId.isNotEmpty
          ? UserSession.userId
          : (newData['hostId'] ?? '');
      newData['createdAt'] = FieldValue.serverTimestamp();
      newData['lastUsedAt'] = FieldValue.serverTimestamp();
      if (deadlineDateTime != null) {
        newData['recruitDeadlineAt'] = Timestamp.fromDate(deadlineDateTime);
      }

      final batch = FirebaseFirestore.instance.batch();

      // 새 파티 문서 생성
      final newRef = FirebaseFirestore.instance.collection('parties').doc();
      batch.set(newRef, newData);

      // 소스 파티의 lastUsedAt 갱신
      final sourceRef = FirebaseFirestore.instance
          .collection('parties')
          .doc(widget.sourcePartyId);
      batch.update(sourceRef, {'lastUsedAt': FieldValue.serverTimestamp()});

      await batch.commit();

      if (!mounted) return;
      _snack('재등록이 완료되었습니다!');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) _snack('재등록에 실패했어요: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(title: const Text('파티 재등록', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 재등록 파티 미리보기 ──────────────────────────────────────
          _card(
            title: '재등록할 파티',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_category.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F3F8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_category,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 8),
                Text(_title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Color(0xFF4A63C8)),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '기존 사진·동영상·내용이 그대로 사용됩니다.\n날짜와 시간만 새로 선택해주세요.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF4A63C8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SectionSummaryRow(
            title: '날짜 및 시간 선택',
            summary: _dateTimeSummary(),
            hasError: _showDateError,
            errorText: _dateTimeErrorText(),
            onTap: _openDateTimeSheet,
          ),

          const SizedBox(height: 8),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('재등록 하기',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
