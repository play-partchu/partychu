import 'package:flutter/material.dart';

/// 호스트가 자유롭게 구성하는 "패키지"(고정 시간대 요금제) 한 건의 초안.
/// Firestore `placeRooms.packages` 배열 원소와 1:1로 대응하며,
/// [toMap]/[fromMap]으로 그대로 직렬화·복원한다 — 저장뿐 아니라
/// "이전 룸 내용 불러오기" 기능에서도 동일한 변환을 재사용한다.
class PlacePackageDraft {
  String id;
  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController descCtrl;
  final TextEditingController minPeopleCtrl;
  final TextEditingController maxPeopleCtrl;
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  Set<String> days;
  bool isActive;

  PlacePackageDraft({
    String? id,
    String name = '',
    this.startTime,
    this.endTime,
    int? price,
    String description = '',
    Set<String>? days,
    int? minPeople,
    int? maxPeople,
    this.isActive = true,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       nameCtrl = TextEditingController(text: name),
       priceCtrl = TextEditingController(text: price?.toString() ?? ''),
       descCtrl = TextEditingController(text: description),
       minPeopleCtrl = TextEditingController(
         text: minPeople?.toString() ?? '',
       ),
       maxPeopleCtrl = TextEditingController(
         text: maxPeople?.toString() ?? '',
       ),
       days = days ?? {};

  static TimeOfDay? _parseTime(String? s) {
    if (s == null || !s.contains(':')) return null;
    final p = s.split(':');
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    if (h >= 24) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  factory PlacePackageDraft.fromMap(Map<String, dynamic> m) {
    return PlacePackageDraft(
      id: m['id'] as String?,
      name: m['name'] as String? ?? '',
      startTime: _parseTime(m['startTime'] as String?),
      endTime: _parseTime(m['endTime'] as String?),
      price: (m['price'] as num?)?.toInt(),
      description: m['description'] as String? ?? '',
      days: ((m['days'] as List?)?.cast<String>() ?? []).toSet(),
      minPeople: (m['minPeople'] as num?)?.toInt(),
      maxPeople: (m['maxPeople'] as num?)?.toInt(),
      isActive: m['isActive'] as bool? ?? true,
    );
  }

  static String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap(int sortOrder) => {
    'id': id,
    'name': nameCtrl.text.trim(),
    'startTime': startTime != null ? _fmtTime(startTime!) : '',
    'endTime': endTime != null ? _fmtTime(endTime!) : '',
    'price': int.tryParse(priceCtrl.text.trim()) ?? 0,
    'description': descCtrl.text.trim(),
    'days': days.toList(),
    if (minPeopleCtrl.text.trim().isNotEmpty)
      'minPeople': int.tryParse(minPeopleCtrl.text.trim()),
    if (maxPeopleCtrl.text.trim().isNotEmpty)
      'maxPeople': int.tryParse(maxPeopleCtrl.text.trim()),
    'isActive': isActive,
    'sortOrder': sortOrder,
  };

  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
    descCtrl.dispose();
    minPeopleCtrl.dispose();
    maxPeopleCtrl.dispose();
  }
}

/// 패키지 목록 편집 위젯 — 추가/삭제/순서변경(위·아래 버튼)을 제공한다.
/// [packages]는 부모([RoomCardState])가 들고 있는 실제 리스트를 그대로
/// 참조로 받아 제자리에서 변경한다 — 저장 시점엔 부모가 이 리스트를 그대로
/// 읽으면 되므로 별도 동기화가 필요 없다.
class PackageListEditor extends StatefulWidget {
  final List<PlacePackageDraft> packages;
  final VoidCallback onChanged;

  const PackageListEditor({
    super.key,
    required this.packages,
    required this.onChanged,
  });

  @override
  State<PackageListEditor> createState() => PackageListEditorState();
}

class PackageListEditorState extends State<PackageListEditor> {
  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  void _notify() {
    widget.onChanged();
    setState(() {});
  }

  void addPackage() {
    widget.packages.add(PlacePackageDraft());
    _notify();
  }

  void _removePackage(int i) {
    widget.packages.removeAt(i).dispose();
    _notify();
  }

  void _moveUp(int i) {
    if (i == 0) return;
    final item = widget.packages.removeAt(i);
    widget.packages.insert(i - 1, item);
    _notify();
  }

  void _moveDown(int i) {
    if (i == widget.packages.length - 1) return;
    final item = widget.packages.removeAt(i);
    widget.packages.insert(i + 1, item);
    _notify();
  }

  Future<void> _pickTime(PlacePackageDraft p, bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          (isStart ? p.startTime : p.endTime) ??
          const TimeOfDay(hour: 11, minute: 0),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF7C5CBF)),
          ),
          child: child!,
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        p.startTime = picked;
      } else {
        p.endTime = picked;
      }
    });
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
        if (widget.packages.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '낮타임 / 밤타임 / 올나잇처럼 원하는 패키지를 자유롭게 추가하세요.',
              style: TextStyle(fontSize: 12, color: Colors.black38),
            ),
          ),
        ...List.generate(widget.packages.length, (i) => _packageCard(i)),
        GestureDetector(
          onTap: addPackage,
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDDE1EC)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 16, color: Color(0xFF7C5CBF)),
                SizedBox(width: 4),
                Text(
                  '패키지 추가',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7C5CBF),
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

  Widget _packageCard(int i) {
    final p = widget.packages[i];
    final isAllDays = _weekdays.every(p.days.contains);
    final overnight =
        p.startTime != null &&
        p.endTime != null &&
        (p.endTime!.hour * 60 + p.endTime!.minute) <=
            (p.startTime!.hour * 60 + p.startTime!.minute);
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
                  '패키지 ${i + 1}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF7C5CBF),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                onPressed: i == 0 ? null : () => _moveUp(i),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: const Color(0xFF7C5CBF),
                disabledColor: Colors.black12,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                onPressed: i == widget.packages.length - 1
                    ? null
                    : () => _moveDown(i),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: const Color(0xFF7C5CBF),
                disabledColor: Colors.black12,
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Colors.redAccent,
                ),
                onPressed: () => _removePackage(i),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: p.nameCtrl,
            onChanged: (_) => widget.onChanged(),
            decoration: _deco('패키지명 (예: 낮타임, 올나잇)'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _timeButton(
                  '시작',
                  p.startTime,
                  () => _pickTime(p, true),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('~'),
              ),
              Expanded(
                child: _timeButton(
                  '종료',
                  p.endTime,
                  () => _pickTime(p, false),
                ),
              ),
            ],
          ),
          if (overnight)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '종료가 시작보다 이르므로 익일까지로 처리돼요 (예: 22:00~08:00)',
                style: TextStyle(fontSize: 11, color: Color(0xFF7C5CBF)),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: p.priceCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => widget.onChanged(),
            decoration: _deco('가격 (원)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: p.descCtrl,
            maxLines: 2,
            onChanged: (_) => widget.onChanged(),
            decoration: _deco('설명 또는 안내문 (선택)'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: p.minPeopleCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => widget.onChanged(),
                  decoration: _deco('최소 인원 (선택)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: p.maxPeopleCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => widget.onChanged(),
                  decoration: _deco('최대 인원 (선택)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '적용 요일',
            style: TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              GestureDetector(
                onTap: () => setState(() {
                  if (isAllDays) {
                    p.days.clear();
                  } else {
                    p.days
                      ..clear()
                      ..addAll(_weekdays);
                  }
                  widget.onChanged();
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isAllDays
                        ? const Color(0xFF7C5CBF)
                        : const Color(0xFFF7F7FA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isAllDays
                          ? const Color(0xFF7C5CBF)
                          : const Color(0xFFDDE1EC),
                    ),
                  ),
                  child: Text(
                    '매일',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isAllDays ? Colors.white : Colors.black54,
                    ),
                  ),
                ),
              ),
              ..._weekdays.map((d) {
                final sel = p.days.contains(d);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (sel) {
                      p.days.remove(d);
                    } else {
                      p.days.add(d);
                    }
                    widget.onChanged();
                  }),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: sel
                          ? const Color(0xFF7C5CBF)
                          : const Color(0xFFF7F7FA),
                      border: Border.all(
                        color: sel
                            ? const Color(0xFF7C5CBF)
                            : const Color(0xFFDDE1EC),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: sel ? Colors.white : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(
                value: p.isActive,
                onChanged: (v) => setState(() {
                  p.isActive = v;
                  widget.onChanged();
                }),
                activeThumbColor: const Color(0xFFFF6FA0),
              ),
              Text(
                p.isActive ? '사용 중' : '사용 안 함',
                style: TextStyle(
                  fontSize: 12,
                  color: p.isActive
                      ? const Color(0xFFFF6FA0)
                      : Colors.black45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeButton(String label, TimeOfDay? t, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: t != null ? const Color(0xFFF3EFFA) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(10),
          border: t != null
              ? Border.all(color: const Color(0xFF7C5CBF).withValues(alpha: 0.4))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.black38),
            ),
            Text(
              t != null ? _fmtTime(t) : '선택',
              style: TextStyle(
                fontSize: 13,
                fontWeight: t != null ? FontWeight.w600 : FontWeight.normal,
                color: t != null ? const Color(0xFF7C5CBF) : Colors.black38,
              ),
            ),
          ],
        ),
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
