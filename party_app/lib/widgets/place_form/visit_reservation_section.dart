import 'package:flutter/material.dart';

import 'package:party_app/models/place_visit_reservation.dart';

/// 플레이스 등록·수정 화면의 **"방문 예약 받기"** 설정 카드.
///
/// 여기서 정하는 것은 결제가 없는 **무료 방문 예약**이다 — 손님이 "몇 시에 몇 명
/// 갈게요"를 신청하면 업주가 받아주는 흐름. 같은 화면 아래쪽 "상품·이용권
/// 판매"의 **유료 좌석권**(결제하고 QR을 받는 상품)과는 전혀 다른 기능이라,
/// 카드 제목과 안내 문구에서 그 차이를 분명히 말해 준다.
///
/// 다른 섹션들([PlaceProductSection] 등)과 같은 규약이다 — 이 위젯은 설정
/// 값만 들고 있고, 저장은 호출부가 플레이스 문서에 [PlaceVisitReservationConfig.
/// toMap]을 넣는 것으로 끝난다(별도 컬렉션 쓰기가 없다).
class VisitReservationSection extends StatefulWidget {
  final PlaceVisitReservationConfig config;
  final ValueChanged<PlaceVisitReservationConfig> onChanged;

  const VisitReservationSection({
    super.key,
    required this.config,
    required this.onChanged,
  });

  @override
  State<VisitReservationSection> createState() =>
      _VisitReservationSectionState();
}

class _VisitReservationSectionState extends State<VisitReservationSection> {
  static const _accent = Color(0xFF2E9E7B);

  PlaceVisitReservationConfig get config => widget.config;
  ValueChanged<PlaceVisitReservationConfig> get onChanged => widget.onChanged;

  /// 호스트가 고정 예약금을 골랐는지. 금액을 아직 안 넣었어도 입력칸이 떠
  /// 있어야 하므로 값(depositPerPerson)과 별개로 들고 있는다.
  late bool _wantsDeposit = widget.config.hasDeposit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _accent.withValues(alpha: 0.25), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.event_available_rounded,
                size: 20,
                color: _accent,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '방문 예약 받기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Switch(
                value: config.enabled,
                activeThumbColor: _accent,
                onChanged: (v) => onChanged(config.copyWith(enabled: v)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '손님이 방문 날짜·시간·인원을 예약 신청하고, 내가 확인하는 무료 예약이에요.\n'
            '결제가 붙는 좌석권은 아래 "상품·이용권 판매"에서 따로 만들어요.',
            style: TextStyle(fontSize: 12, height: 1.45, color: Colors.black54),
          ),
          if (config.enabled) ...[
            const Divider(height: 28),
            _label('승인 방식'),
            const SizedBox(height: 6),
            for (final mode in VisitApprovalMode.values)
              _radioTile(
                label: mode.label,
                description: mode.description,
                selected: config.approvalMode == mode,
                onTap: () => onChanged(config.copyWith(approvalMode: mode)),
              ),
            const SizedBox(height: 16),

            _label('예약 받는 시간'),
            const SizedBox(height: 4),
            const Text(
              '비워두면 영업시간 전체에서 예약을 받아요. 휴무일·브레이크 타임은 자동으로 빠져요.',
              style: TextStyle(fontSize: 11.5, color: Colors.black45),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _timeButton(
                    context,
                    label: config.openFrom == null
                        ? '영업 시작부터'
                        : PlaceVisitReservationConfig.formatHhmm(
                            config.openFrom!,
                          ),
                    filled: config.openFrom != null,
                    onPick: (t) => onChanged(config.copyWith(openFrom: t)),
                    onClear: config.openFrom == null
                        ? null
                        : () => onChanged(config.copyWith(clearOpenFrom: true)),
                    initial: const TimeOfDay(hour: 18, minute: 0),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('~', style: TextStyle(color: Colors.black38)),
                ),
                Expanded(
                  child: _timeButton(
                    context,
                    label: config.openTo == null
                        ? '영업 종료까지'
                        : PlaceVisitReservationConfig.formatHhmm(
                            config.openTo!,
                          ),
                    filled: config.openTo != null,
                    onPick: (t) => onChanged(config.copyWith(openTo: t)),
                    onClear: config.openTo == null
                        ? null
                        : () => onChanged(config.copyWith(clearOpenTo: true)),
                    initial: const TimeOfDay(hour: 22, minute: 0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _stepper(
              label: '예약 시간 간격',
              value: config.slotMinutes,
              unit: '분',
              options: const [30, 60],
              onChanged: (v) => onChanged(config.copyWith(slotMinutes: v)),
            ),
            _stepper(
              label: '한 팀 이용 시간',
              value: config.stayMinutes,
              unit: '분',
              options: const [60, 90, 120, 180],
              onChanged: (v) => onChanged(config.copyWith(stayMinutes: v)),
              hint: '이 시간 동안 자리를 차지하는 것으로 계산해요.',
            ),
            const SizedBox(height: 8),

            _label('예약 인원'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _counter(
                    label: '최소',
                    value: config.minPeople,
                    min: 1,
                    max: config.maxPeople,
                    onChanged: (v) => onChanged(config.copyWith(minPeople: v)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _counter(
                    label: '최대',
                    value: config.maxPeople,
                    min: config.minPeople,
                    max: 50,
                    onChanged: (v) => onChanged(config.copyWith(maxPeople: v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _counter(
              label: '같은 시간대 총 좌석',
              value: config.capacityPerSlot,
              min: 1,
              max: 300,
              step: 5,
              onChanged: (v) => onChanged(config.copyWith(capacityPerSlot: v)),
              hint: '이 인원이 다 차면 그 시간대는 예약 마감으로 표시돼요.',
            ),
            const SizedBox(height: 16),

            _stepper(
              label: '예약 마감',
              value: config.leadTimeMinutes,
              unit: '분 전',
              options: const [0, 30, 60, 120, 240],
              onChanged: (v) => onChanged(config.copyWith(leadTimeMinutes: v)),
              hint: '방문 시각 기준으로 이 시간 전까지만 신청을 받아요.',
              labelBuilder: (v) => v == 0 ? '제한 없음' : '$v분 전',
            ),
            _stepper(
              label: '예약 가능 기간',
              value: config.maxAdvanceDays,
              unit: '일 뒤까지',
              options: const [7, 14, 30, 60],
              onChanged: (v) => onChanged(config.copyWith(maxAdvanceDays: v)),
            ),
            if (config.approvalMode == VisitApprovalMode.manual)
              _stepper(
                label: '승인 대기 시간',
                value: config.autoExpireHours,
                unit: '시간',
                options: const [3, 6, 12, 24],
                onChanged: (v) =>
                    onChanged(config.copyWith(autoExpireHours: v)),
                hint: '이 시간 안에 승인하지 않으면 신청이 자동으로 만료돼요.',
              ),
            const SizedBox(height: 12),

            // ── 예약금 ──────────────────────────────────────────────────
            // 0원이면 지금까지와 같은 무료 예약이다(결제 화면이 아예 뜨지
            // 않는다). 금액을 넣으면 신청할 때 결제수단을 고르게 되고,
            // 승인제 매장은 **승인 후에** 입금 안내가 나간다.
            // 이 예약은 좌석만 잡고 음식·주류는 현장에서 주문하는 형태라
            // **예약 시점에 총 이용금액을 알 수 없다.** 그래서 비율(%)
            // 예약금과 전액 선결제는 아예 선택지에 넣지 않는다 — 총액이
            // 확정되지 않았는데 비율을 계산하는 구조는 만들지 않는다.
            _label('결제 방식'),
            const SizedBox(height: 6),
            _radioTile(
              label: '예약금 없음',
              description: '자리만 잡고 이용금액은 전부 현장에서 결제해요.',
              selected: !_wantsDeposit,
              onTap: () {
                setState(() => _wantsDeposit = false);
                onChanged(config.copyWith(depositPerPerson: 0));
              },
            ),
            _radioTile(
              label: '고정 예약금',
              description: '1인당 정해진 금액을 미리 받고, 나머지는 현장에서 결제해요.',
              selected: _wantsDeposit,
              onTap: () => setState(() => _wantsDeposit = true),
            ),
            if (!_wantsDeposit) const SizedBox(height: 4),
            if (_wantsDeposit) ...[
              const SizedBox(height: 12),
              _label('1인당 예약금'),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: config.depositPerPerson == 0
                    ? ''
                    : '${config.depositPerPerson}',
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '비워두면 무료 예약이에요',
                  hintStyle: const TextStyle(
                    fontSize: 12,
                    color: Colors.black38,
                  ),
                  suffixText: '원',
                  filled: true,
                  fillColor: const Color(0xFFF7F7F9),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => onChanged(
                  config.copyWith(
                    depositPerPerson: int.tryParse(v.replaceAll(',', '')) ?? 0,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  config.hasDeposit
                      ? '예약금 × 인원을 미리 받고, 추가 이용금액은 현장에서 결제해요. '
                            '지금은 무통장입금·현장결제만 받을 수 있어요.'
                            '${config.approvalMode == VisitApprovalMode.manual ? ' 승인한 뒤에 입금 안내가 나가요.' : ''}'
                      : '금액을 넣어야 예약금을 받을 수 있어요.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: Colors.black45,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),

            _label('예약 안내 문구'),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: config.notice,
              maxLines: 3,
              maxLength: 200,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '예) 2인 이상만 예약을 받아요. 10분 이상 늦으면 자리가 취소될 수 있어요.',
                hintStyle: const TextStyle(fontSize: 12, color: Colors.black38),
                filled: true,
                fillColor: const Color(0xFFF7F7F9),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => onChanged(config.copyWith(notice: v)),
            ),
          ],
        ],
      ),
    );
  }

  // ── 부품 ────────────────────────────────────────────────────────────
  Widget _label(String text) => Text(
    text,
    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
  );

  Widget _radioTile({
    required String label,
    required String description,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? _accent : Colors.black26,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? _accent : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeButton(
    BuildContext context, {
    required String label,
    required bool filled,
    required ValueChanged<TimeOfDay> onPick,
    required VoidCallback? onClear,
    required TimeOfDay initial,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: initial,
          builder: (ctx, child) => Theme(
            data: Theme.of(
              ctx,
            ).copyWith(colorScheme: const ColorScheme.light(primary: _accent)),
            child: child!,
          ),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: filled
              ? _accent.withValues(alpha: 0.10)
              : const Color(0xFFF7F7F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: filled
                ? _accent.withValues(alpha: 0.45)
                : const Color(0xFFE8E8EE),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule_rounded, size: 15, color: Colors.black45),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: filled ? FontWeight.w700 : FontWeight.w500,
                  color: filled ? _accent : Colors.black54,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: Colors.black38,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 정해진 값들 중에서 고르는 줄 — 자유 입력보다 오설정이 적다.
  Widget _stepper({
    required String label,
    required int value,
    required String unit,
    required List<int> options,
    required ValueChanged<int> onChanged,
    String? hint,
    String Function(int)? labelBuilder,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          if (hint != null) ...[
            const SizedBox(height: 3),
            Text(
              hint,
              style: const TextStyle(fontSize: 11.5, color: Colors.black45),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((opt) {
              final selected = value == opt;
              return GestureDetector(
                onTap: () => onChanged(opt),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? _accent : const Color(0xFFF7F7F9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? _accent : const Color(0xFFE8E8EE),
                    ),
                  ),
                  child: Text(
                    labelBuilder?.call(opt) ?? '$opt$unit',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? Colors.white : Colors.black54,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _counter({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
    int step = 1,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ),
              _roundButton(
                Icons.remove_rounded,
                value > min
                    ? () => onChanged((value - step).clamp(min, max))
                    : null,
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _roundButton(
                Icons.add_rounded,
                value < max
                    ? () => onChanged((value + step).clamp(min, max))
                    : null,
              ),
            ],
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint,
            style: const TextStyle(fontSize: 11.5, color: Colors.black45),
          ),
        ],
      ],
    );
  }

  Widget _roundButton(IconData icon, VoidCallback? onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: onTap == null ? const Color(0xFFEFEFF3) : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE0E0E6)),
      ),
      child: Icon(
        icon,
        size: 16,
        color: onTap == null ? Colors.black26 : Colors.black87,
      ),
    ),
  );
}
