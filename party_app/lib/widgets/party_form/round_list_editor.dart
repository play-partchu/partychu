import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

const _kAccent = Color(0xFFFF6FA0);

/// 2차 이상 라운드 한 건의 초안. 1차는 기존 날짜/정원/참가비 섹션이 그대로
/// 담당하므로 이 클래스는 2차부터만 다룬다.
/// Firestore `parties.rounds` 배열 원소와 1:1 대응하며 [toMap]/[fromMap]으로
/// 직렬화·복원한다 — 재등록 시 이전 라운드 구성을 그대로 불러오는 데도 쓰인다.
class PartyRoundDraft {
  String id;
  final TextEditingController labelCtrl;
  TimeOfDay? time;
  // roundCapacityMode == 'perRound'일 때만 쓰이는 필드
  final TextEditingController capacityCtrl; // genderCapacityMode == 'unlimited'
  final TextEditingController maleCapacityCtrl; // genderCapacityMode == 'separate'
  final TextEditingController femaleCapacityCtrl;
  final TextEditingController maleFeeCtrl;
  final TextEditingController femaleFeeCtrl;

  PartyRoundDraft({
    String? id,
    String label = '',
    this.time,
    String? capacity,
    String? maleCapacity,
    String? femaleCapacity,
    String? maleFee,
    String? femaleFee,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       labelCtrl = TextEditingController(text: label),
       capacityCtrl = TextEditingController(text: capacity ?? ''),
       maleCapacityCtrl = TextEditingController(text: maleCapacity ?? ''),
       femaleCapacityCtrl = TextEditingController(text: femaleCapacity ?? ''),
       maleFeeCtrl = TextEditingController(text: maleFee ?? ''),
       femaleFeeCtrl = TextEditingController(text: femaleFee ?? '');

  factory PartyRoundDraft.fromMap(Map<String, dynamic> m) {
    DateTime? dt;
    final ts = m['time'];
    if (ts is Timestamp) dt = ts.toDate();
    return PartyRoundDraft(
      id: m['id'] as String?,
      label: m['label'] as String? ?? '',
      time: dt != null ? TimeOfDay(hour: dt.hour, minute: dt.minute) : null,
      capacity: (m['maxCapacity'] as num?)?.toString(),
      maleCapacity: (m['maleCapacity'] as num?)?.toString(),
      femaleCapacity: (m['femaleCapacity'] as num?)?.toString(),
      maleFee: (m['maleFee'] as num?)?.toString(),
      femaleFee: (m['femaleFee'] as num?)?.toString(),
    );
  }

  Map<String, dynamic> toMap({
    required int roundNumber,
    required DateTime partyDate,
    required String roundCapacityMode,
    required String genderCapacityMode,
  }) {
    final t = time ?? const TimeOfDay(hour: 19, minute: 0);
    final dt = DateTime(
      partyDate.year,
      partyDate.month,
      partyDate.day,
      t.hour,
      t.minute,
    );
    final label = labelCtrl.text.trim();
    return {
      'roundNumber': roundNumber,
      'label': label.isEmpty ? '$roundNumber차' : label,
      'time': Timestamp.fromDate(dt),
      if (roundCapacityMode == 'perRound')
        ..._perRoundFields(genderCapacityMode),
    };
  }

  Map<String, dynamic> _perRoundFields(String genderCapacityMode) {
    if (genderCapacityMode == 'unlimited') {
      final max = int.tryParse(capacityCtrl.text.trim()) ?? 0;
      return {
        'maxCapacity': max,
        'maleCapacity': 0,
        'femaleCapacity': 0,
        'currentParticipants': 0,
        'currentMaleCount': 0,
        'currentFemaleCount': 0,
        'maleFee': int.tryParse(maleFeeCtrl.text.trim()) ?? 0,
        'femaleFee': int.tryParse(femaleFeeCtrl.text.trim()) ?? 0,
      };
    }
    final male = int.tryParse(maleCapacityCtrl.text.trim()) ?? 0;
    final female = int.tryParse(femaleCapacityCtrl.text.trim()) ?? 0;
    return {
      'maxCapacity': male + female,
      'maleCapacity': male,
      'femaleCapacity': female,
      'currentParticipants': 0,
      'currentMaleCount': 0,
      'currentFemaleCount': 0,
      'maleFee': int.tryParse(maleFeeCtrl.text.trim()) ?? 0,
      'femaleFee': int.tryParse(femaleFeeCtrl.text.trim()) ?? 0,
    };
  }

  void dispose() {
    labelCtrl.dispose();
    capacityCtrl.dispose();
    maleCapacityCtrl.dispose();
    femaleCapacityCtrl.dispose();
    maleFeeCtrl.dispose();
    femaleFeeCtrl.dispose();
  }
}

/// 2차 이상 라운드 목록 편집 위젯 — 추가/삭제 + (perRound 모드일 때) 라운드별
/// 정원·참가비 입력을 제공한다. 순서 변경은 없다 — 라운드는 항상 시간순이라
/// index+2로 번호를 매긴다. [rounds]는 부모가 들고 있는 실제 리스트를 그대로
/// 참조로 받아 제자리에서 변경한다.
class RoundListEditor extends StatefulWidget {
  final List<PartyRoundDraft> rounds;
  final String roundCapacityMode; // 'unified' | 'perRound'
  final String genderCapacityMode; // 'unlimited' | 'separate'
  final VoidCallback onChanged;

  const RoundListEditor({
    super.key,
    required this.rounds,
    required this.roundCapacityMode,
    required this.genderCapacityMode,
    required this.onChanged,
  });

  @override
  State<RoundListEditor> createState() => RoundListEditorState();
}

class RoundListEditorState extends State<RoundListEditor> {
  void _notify() {
    widget.onChanged();
    setState(() {});
  }

  void addRound() {
    widget.rounds.add(PartyRoundDraft());
    _notify();
  }

  void _removeRound(int i) {
    widget.rounds.removeAt(i).dispose();
    _notify();
  }

  Future<void> _pickTime(PartyRoundDraft r) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: r.time ?? const TimeOfDay(hour: 21, minute: 0),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: Theme(
          data: Theme.of(
            ctx,
          ).copyWith(colorScheme: const ColorScheme.light(primary: _kAccent)),
          child: child!,
        ),
      ),
    );
    if (picked == null) return;
    setState(() => r.time = picked);
    widget.onChanged();
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    if (h == 0) return '오전 12:$m';
    if (h < 12) return '오전 $h:$m';
    if (h == 12) return '오후 12:$m';
    return '오후 ${h - 12}:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.rounds.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '1차는 위 "날짜 및 시간 선택"에서 정한 시간이에요. 2차부터 여기서 추가하세요.',
              style: TextStyle(fontSize: 12, color: Colors.black38),
            ),
          ),
        ...List.generate(widget.rounds.length, (i) => _roundCard(i)),
        GestureDetector(
          onTap: addRound,
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3F7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, size: 16, color: _kAccent),
                const SizedBox(width: 4),
                Text(
                  '${widget.rounds.length + 2}차 라운드 추가하기',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _kAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _roundCard(int i) {
    final r = widget.rounds[i];
    final roundNumber = i + 2;
    final perRound = widget.roundCapacityMode == 'perRound';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$roundNumber차',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _kAccent,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Colors.redAccent,
                ),
                onPressed: () => _removeRound(i),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: r.labelCtrl,
            onChanged: (_) => widget.onChanged(),
            decoration: _deco('라운드 이름 (선택, 예: 술집)'),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _pickTime(r),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              decoration: BoxDecoration(
                color: r.time != null
                    ? const Color(0xFFFFF3F7)
                    : const Color(0xFFF7F7FA),
                borderRadius: BorderRadius.circular(10),
                border: r.time != null
                    ? Border.all(color: _kAccent.withValues(alpha: 0.4))
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: r.time != null ? _kAccent : Colors.black38,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    r.time != null ? _fmtTime(r.time!) : '시간 선택',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: r.time != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: r.time != null ? _kAccent : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (perRound) ...[
            const SizedBox(height: 10),
            const Text(
              '이 라운드 정원/참가비',
              style: TextStyle(
                fontSize: 12,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            if (widget.genderCapacityMode == 'unlimited')
              TextField(
                controller: r.capacityCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => widget.onChanged(),
                decoration: _deco('최대 인원'),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: r.maleCapacityCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => widget.onChanged(),
                      decoration: _deco('남자 인원'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: r.femaleCapacityCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => widget.onChanged(),
                      decoration: _deco('여자 인원'),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: r.maleFeeCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => widget.onChanged(),
                    decoration: _deco('남자 참가비 (원)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: r.femaleFeeCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => widget.onChanged(),
                    decoration: _deco('여자 참가비 (원)'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE8EBF2)),
    ),
  );
}
