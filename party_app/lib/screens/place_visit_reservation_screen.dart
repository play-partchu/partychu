import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/models/payment_order_summary.dart';
import 'package:party_app/models/payment_status.dart';
import 'package:party_app/models/place_visit_reservation.dart';
import 'package:party_app/models/place_weekly_hours.dart';
import 'package:party_app/screens/payment_method_screen.dart';
import 'package:party_app/services/place_visit_reservation_service.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 플레이스 **무료 방문 예약** 신청 화면 — 날짜 → 시간 → 인원 → 요청사항.
///
/// 결제가 없다. 유료 좌석권(상품 구매)과 헷갈리지 않도록 화면 곳곳에서
/// "방문 예약"이라는 말만 쓰고, 마지막 버튼도 '결제'가 아니라 '예약 신청하기'다.
///
/// 자리 계산은 [VisitSlotCalculator] 하나로 하고, 실제 접수는 서버가 같은 규칙을
/// 다시 검증한다(정원이 그 사이에 찼으면 서버가 막고 그 문구를 그대로 띄운다).
class PlaceVisitReservationScreen extends StatefulWidget {
  final String placeId;

  /// 플레이스 문서 — 영업시간·예약 설정·이름을 여기서 읽는다.
  final Map<String, dynamic> placeData;

  const PlaceVisitReservationScreen({
    super.key,
    required this.placeId,
    required this.placeData,
  });

  @override
  State<PlaceVisitReservationScreen> createState() =>
      _PlaceVisitReservationScreenState();
}

class _PlaceVisitReservationScreenState
    extends State<PlaceVisitReservationScreen> {
  late final PlaceVisitReservationConfig _config;
  late final PlaceWeeklyHours? _weeklyHours;

  DateTime _selectedDate = DateTime.now();
  TimeOfDay? _selectedTime;
  late int _people;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  /// 그 날짜의 슬롯별 예약 인원 — 화면을 열거나 날짜를 바꿀 때마다 다시 읽는다.
  Map<String, int> _reserved = const {};
  bool _loadingSlots = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _config = PlaceVisitReservationConfig.fromMap(
      widget.placeData['visitReservation'] is Map
          ? Map<String, dynamic>.from(
              widget.placeData['visitReservation'] as Map,
            )
          : null,
    );
    final weekly =
        widget.placeData['placeWeeklyHours'] ??
        widget.placeData['weeklyOperatingHours'];
    _weeklyHours = weekly is Map
        ? PlaceWeeklyHours.fromMap(Map<String, dynamic>.from(weekly))
        : null;
    _people = _config.minPeople;

    // 예약자 이름은 본인확인에서 받아 둔 실명을 미리 채운다. 연락처는 저장해
    // 두는 곳이 없어(본인확인이 휴대폰 번호를 남기지 않는다) 직접 입력받는다.
    _nameCtrl.text = UserSession.name;

    _selectedDate = _firstOpenDate();
    _loadSlots();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  /// 예약을 받는 가장 이른 날 — 오늘이 휴무거나 이미 마감이면 다음 날로 넘긴다.
  DateTime _firstOpenDate() {
    final now = DateTime.now();
    for (var i = 0; i <= _config.maxAdvanceDays; i++) {
      final day = DateTime(now.year, now.month, now.day + i);
      final slots = VisitSlotCalculator.slotsFor(
        config: _config,
        weeklyHours: _weeklyHours,
        placeData: widget.placeData,
        date: day,
        now: now,
      );
      if (slots.any((s) => s.selectable)) return day;
    }
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _loadSlots() async {
    setState(() => _loadingSlots = true);
    try {
      final reserved = await PlaceVisitReservationService.reservedPeopleOn(
        placeId: widget.placeId,
        date: _selectedDate,
      );
      if (!mounted) return;
      setState(() {
        _reserved = reserved;
        _loadingSlots = false;
      });
    } catch (_) {
      if (!mounted) return;
      // 잔여석을 못 읽어도 화면은 뜬다 — 최종 판정은 어차피 서버가 한다.
      setState(() {
        _reserved = const {};
        _loadingSlots = false;
      });
    }
  }

  List<VisitSlot> get _slots => VisitSlotCalculator.slotsFor(
    config: _config,
    weeklyHours: _weeklyHours,
    placeData: widget.placeData,
    date: _selectedDate,
    now: DateTime.now(),
    reservedBySlot: _reserved,
    people: _people,
  );

  bool get _canSubmit =>
      !_submitting &&
      _selectedTime != null &&
      _nameCtrl.text.trim().isNotEmpty &&
      _phoneCtrl.text.trim().length >= 9;

  @override
  Widget build(BuildContext context) {
    final placeName =
        widget.placeData['title'] as String? ??
        widget.placeData['name'] as String? ??
        '플레이스';

    return Scaffold(
      backgroundColor: const Color(0xFFFFF7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '방문 예약',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  _header(placeName),
                  const SizedBox(height: 14),
                  _card(step: '1', title: '방문 날짜', child: _dateRow()),
                  _card(step: '2', title: '방문 시간', child: _timeGrid()),
                  _card(step: '3', title: '인원', child: _peopleRow()),
                  _card(step: '4', title: '예약자 정보', child: _requesterForm()),
                  if (_config.notice.isNotEmpty) _noticeCard(),
                ],
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  // ── 상단 요약 ────────────────────────────────────────────────────────
  Widget _header(String placeName) {
    final auto = _config.approvalMode == VisitApprovalMode.auto;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PartyChuColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            placeName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: PartyChuColors.heading,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                auto ? Icons.bolt_rounded : Icons.how_to_reg_rounded,
                size: 15,
                color: PartyChuColors.primary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  auto ? '신청하면 바로 확정되는 매장이에요.' : '매장이 확인하고 승인하면 예약이 확정돼요.',
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            // 예약금이 있는 매장은 금액과 "언제 내는지"까지 미리 알려준다 —
            // 승인제는 승인이 난 뒤에야 입금 안내가 나간다.
            !_config.hasDeposit
                ? '결제 없는 무료 방문 예약이에요.'
                : '예약금 ${formatPrice(_config.depositPerPerson)} × 인원'
                      '${auto ? ' — 신청 후 바로 입금 안내를 드려요.' : ' — 승인되면 입금 안내를 드려요.'}',
            style: const TextStyle(fontSize: 11.5, color: Colors.black38),
          ),
        ],
      ),
    );
  }

  // ── 1. 날짜 ──────────────────────────────────────────────────────────
  Widget _dateRow() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 가까운 2주를 가로 스크롤로 보여주고, 그보다 뒤는 달력에서 고른다.
    final days = [
      for (var i = 0; i <= _config.maxAdvanceDays && i < 14; i++)
        today.add(Duration(days: i)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final day = days[i];
              final open = _config.acceptsDate(day, now: now);
              final selected = _isSameDay(day, _selectedDate);
              return GestureDetector(
                onTap: open ? () => _pickDate(day) : null,
                child: Container(
                  width: 58,
                  decoration: BoxDecoration(
                    color: selected
                        ? PartyChuColors.primary
                        : open
                        ? Colors.white
                        : const Color(0xFFF5F5F7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? PartyChuColors.primary
                          : PartyChuColors.border,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        i == 0
                            ? '오늘'
                            : PlaceWeeklyHours.weekdays[day.weekday - 1],
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.white70
                              : open
                              ? Colors.black45
                              : Colors.black26,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? Colors.white
                              : open
                              ? PartyChuColors.heading
                              : Colors.black26,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_config.maxAdvanceDays >= 14) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _openCalendar,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.calendar_month_rounded,
                  size: 15,
                  color: PartyChuColors.primary,
                ),
                SizedBox(width: 5),
                Text(
                  '다른 날짜 고르기',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: PartyChuColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _pickDate(DateTime day) {
    setState(() {
      _selectedDate = day;
      _selectedTime = null;
    });
    _loadSlots();
  }

  Future<void> _openCalendar() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: today,
      lastDate: today.add(Duration(days: _config.maxAdvanceDays)),
      selectableDayPredicate: (d) => _config.acceptsDate(d, now: now),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: PartyChuColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) _pickDate(picked);
  }

  // ── 2. 시간 ──────────────────────────────────────────────────────────
  Widget _timeGrid() {
    if (_loadingSlots) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: PartyChuColors.primary,
            ),
          ),
        ),
      );
    }
    final slots = _slots;
    if (slots.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '이 날짜에는 예약을 받지 않아요. 다른 날짜를 골라주세요.',
          style: TextStyle(fontSize: 12.5, color: Colors.black45),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: slots.map((slot) {
        final selected =
            _selectedTime != null &&
            _selectedTime!.hour == slot.time.hour &&
            _selectedTime!.minute == slot.time.minute;
        return GestureDetector(
          onTap: slot.selectable
              ? () => setState(() => _selectedTime = slot.time)
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? PartyChuColors.primary
                  : slot.selectable
                  ? Colors.white
                  : const Color(0xFFF5F5F7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? PartyChuColors.primary
                    : slot.selectable
                    ? PartyChuColors.border
                    : const Color(0xFFEAEAEE),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  slot.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white
                        : slot.selectable
                        ? PartyChuColors.heading
                        : Colors.black26,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  slot.blockedReason ?? '${slot.remaining}자리',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: selected
                        ? Colors.white70
                        : slot.selectable
                        ? Colors.black38
                        : Colors.black26,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── 3. 인원 ──────────────────────────────────────────────────────────
  Widget _peopleRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$_people명',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: PartyChuColors.heading,
              ),
            ),
            const Spacer(),
            _roundButton(
              Icons.remove_rounded,
              _people > _config.minPeople
                  ? () => setState(() => _people--)
                  : null,
            ),
            const SizedBox(width: 12),
            _roundButton(
              Icons.add_rounded,
              _people < _config.maxPeople
                  ? () => setState(() => _people++)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${_config.minPeople}~${_config.maxPeople}명까지 예약할 수 있어요.',
          style: const TextStyle(fontSize: 11.5, color: Colors.black45),
        ),
      ],
    );
  }

  Widget _roundButton(IconData icon, VoidCallback? onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: onTap == null ? const Color(0xFFF2F2F5) : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: onTap == null
              ? const Color(0xFFEAEAEE)
              : PartyChuColors.border,
        ),
      ),
      child: Icon(
        icon,
        size: 18,
        color: onTap == null ? Colors.black26 : PartyChuColors.primary,
      ),
    ),
  );

  // ── 4. 예약자 정보 ───────────────────────────────────────────────────
  Widget _requesterForm() {
    return Column(
      children: [
        _field(
          controller: _nameCtrl,
          hint: '예약자 이름',
          icon: Icons.person_rounded,
        ),
        const SizedBox(height: 10),
        _field(
          controller: _phoneCtrl,
          hint: '연락처 (예: 01012345678)',
          icon: Icons.phone_rounded,
          keyboardType: TextInputType.phone,
          formatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 10),
        _field(
          controller: _messageCtrl,
          hint: '요청사항 (선택) — 창가 자리 부탁드려요',
          icon: Icons.edit_note_rounded,
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 13.5),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12.5, color: Colors.black38),
        prefixIcon: Icon(icon, size: 18, color: PartyChuColors.primary),
        filled: true,
        fillColor: PartyChuColors.surfaceTint,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _noticeCard() => Container(
    margin: const EdgeInsets.only(top: 2),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E6),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFFFE2A8)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: Color(0xFFB98600),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _config.notice,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: Color(0xFF7A5B00),
            ),
          ),
        ),
      ],
    ),
  );

  // ── 하단 버튼 ────────────────────────────────────────────────────────
  Widget _bottomBar() {
    final auto = _config.approvalMode == VisitApprovalMode.auto;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F4))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_selectedTime != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${PlaceVisitReservationConfig.formatDateLabel(_selectedDate)} '
                '${PlaceVisitReservationConfig.formatTimeLabel(_selectedTime!)} · $_people명',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: PartyChuColors.primaryDeep,
                ),
              ),
            ),
          PartyChuPrimaryButton(
            label: _submitting
                ? '신청 중...'
                : auto
                ? '예약 확정하기'
                : '예약 신청하기',
            height: 54,
            showBadge: false,
            onTap: _canSubmit ? _submit : null,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_selectedTime == null) return;

    // 예약금이 걸린 매장만 결제수단을 고른다 — 0원이면(지금까지의 무료 예약)
    // 화면 자체가 뜨지 않고 예전과 똑같이 바로 신청된다.
    //
    // 금액은 화면에 보여주기 위한 값이고, 실제 금액과 결제 상태는 서버가 매장
    // 설정을 다시 읽어 정한다.
    PaymentInfo? payment;
    final deposit = _config.depositAmountFor(_people);
    if (deposit > 0) {
      payment = await Navigator.push<PaymentInfo>(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentMethodScreen(
            summary: PaymentOrderSummary.placeVisit(
              placeName:
                  widget.placeData['title'] as String? ??
                  widget.placeData['name'] as String? ??
                  '플레이스',
              visitText:
                  '${PlaceVisitReservationConfig.formatDateLabel(_selectedDate)} '
                  '${PlaceVisitReservationConfig.formatTimeLabel(_selectedTime!)}',
              peopleText: '$_people명',
              amount: deposit,
            ),
            defaultDepositorName: _nameCtrl.text.trim(),
            // 돈을 받는 사람 = 이 매장의 업주.
            hostId: widget.placeData['hostId'] as String? ?? '',
          ),
        ),
      );
      if (payment == null || !mounted) return;
    }

    setState(() => _submitting = true);
    try {
      final result = await PlaceVisitReservationService.create(
        placeId: widget.placeId,
        date: _selectedDate,
        time: _selectedTime!,
        peopleCount: _people,
        requesterName: _nameCtrl.text.trim(),
        requesterPhone: _phoneCtrl.text.trim(),
        requestMessage: _messageCtrl.text.trim(),
        payment: payment,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(result.autoApproved ? '예약이 확정됐어요' : '예약을 신청했어요'),
          content: Text(
            result.autoApproved
                ? '${PlaceVisitReservationConfig.formatDateLabel(_selectedDate)} '
                      '${PlaceVisitReservationConfig.formatTimeLabel(_selectedTime!)}에 뵐게요!'
                : '매장이 확인하면 알림으로 알려드려요. '
                      '진행 상황은 마이페이지 > 내 플레이스 예약에서 볼 수 있어요.',
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      // 서버가 이미 사람이 읽을 문구로 돌려준다(정원 초과·마감 등).
      _msg(e.message ?? '예약을 신청하지 못했어요. 잠시 후 다시 시도해주세요.');
      _loadSlots();
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _msg('예약을 신청하지 못했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );

  Widget _card({
    required String step,
    required String title,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PartyChuColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: PartyChuColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  step,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: PartyChuColors.heading,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
