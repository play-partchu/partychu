import 'package:flutter/material.dart';

/// 등록/수정/재등록 화면 공통 시간선택기 — 오전/오후 토글 + 12시간 그리드 +
/// 정각/30분. 기존 등록 화면 `_showCustomTimePicker`를 그대로 추출한 것.
Future<TimeOfDay?> showCustomTimePicker(
  BuildContext context, {
  required TimeOfDay initial,
  required String title,
}) {
  int period = initial.hour < 12 ? 0 : 1;
  int hour = initial.hour % 12 == 0 ? 12 : initial.hour % 12;
  int minute = initial.minute >= 30 ? 30 : 0;

  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setS) {
        void confirm() {
          final h24 = period == 0
              ? (hour == 12 ? 0 : hour)
              : (hour == 12 ? 12 : hour + 12);
          Navigator.pop(ctx, TimeOfDay(hour: h24, minute: minute));
        }

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, 20 + MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(height: 16),
              Text(title,
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              // 오전 / 오후 토글
              Row(
                children: ['오전', '오후'].asMap().entries.map((e) {
                  final isSelected = period == e.key;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setS(() => period = e.key),
                      child: Container(
                        margin: EdgeInsets.only(
                            right: e.key == 0 ? 5 : 0,
                            left: e.key == 1 ? 5 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFFF6FA0)
                              : const Color(0xFFF5F5F7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          e.value,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              // 시간 그리드 (12, 1 ~ 11)
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.9,
                children: [12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map((h) {
                  final isSelected = hour == h;
                  return GestureDetector(
                    onTap: () => setS(() => hour = h),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFF6FA0)
                            : const Color(0xFFF5F5F7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$h시',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              // 분 선택 (정각 / 30분)
              Row(
                children: [0, 30].map((m) {
                  final isSelected = minute == m;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          right: m == 0 ? 4 : 0, left: m == 30 ? 4 : 0),
                      child: GestureDetector(
                        onTap: () => setS(() => minute = m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFFFF0F5)
                                : const Color(0xFFF5F5F7),
                            borderRadius: BorderRadius.circular(10),
                            border: isSelected
                                ? Border.all(
                                    color: const Color(0xFFFF6FA0), width: 1.5)
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            m == 0 ? '정각' : '30분',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? const Color(0xFFFF6FA0)
                                  : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6FA0),
                    foregroundColor: Colors.white,
                    shape:
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    '${period == 0 ? '오전' : '오후'} $hour시 ${minute == 0 ? '정각' : '30분'} 선택',
                    style:
                        const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
