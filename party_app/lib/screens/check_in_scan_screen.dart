import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:party_app/models/check_in_result.dart';
import 'package:party_app/services/check_in_service.dart';

const Color _kAccent = Color(0xFFFF6FA0);
const Color _kBorder = Color(0xFFE8EBF2);

/// 호스트용 **QR 체크인** — 스캐너는 이것 하나뿐이다.
///
/// 손님이 내미는 QR이 파티 참가권인지 예약인지 이용권인지 미리 알 필요가 없다.
/// 종류 판별·권한 검증·정보 조합은 전부 서버가 하고([CheckInService]) 이 화면은
/// 그 결과 하나를 그린다.
///
/// ── 스캔은 소진이 아니다 ────────────────────────────────────────────────────
///   1. 코드를 읽으면 **조회만** 한다(resolveCheckInToken) — 누가 무엇을
///      이용하러 왔는지 보여주고,
///   2. 호스트가 '체크인 처리'를 눌러야 상태가 바뀐다(consumeCheckIn).
///
/// 다른 날짜 QR을 잘못 찍었을 수 있으므로 이 분리는 타협하지 않는다.
///
/// ── 현장결제도 이 화면에서 끝난다 ───────────────────────────────────────────
/// 아직 결제 전이면 '현장결제 예정'을 크게 보여주고 체크인 버튼을 잠근다.
/// 돈을 받은 뒤 '결제 확인'을 누르면 그 자리에서 결제가 확인되고 체크인이
/// 열린다 — 손님을 줄 앞에 세워 두고 다른 화면으로 갈 일이 없다.
class CheckInScanScreen extends StatefulWidget {
  const CheckInScanScreen({super.key});

  @override
  State<CheckInScanScreen> createState() => _CheckInScanScreenState();
}

class _CheckInScanScreenState extends State<CheckInScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  /// 조회 중이거나 결과 카드가 떠 있는 동안은 다시 읽지 않는다.
  bool _busy = false;
  String? _lastCode;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null || code == _lastCode) return;

    setState(() {
      _busy = true;
      _lastCode = code;
    });
    await _controller.stop();

    try {
      final result = await CheckInService.resolve(code);
      if (!mounted) return;
      await _showResult(result, code);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      await _showError(e.message ?? 'QR을 확인할 수 없어요.');
    } catch (_) {
      if (!mounted) return;
      await _showError('QR 확인 중 오류가 발생했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _lastCode = null;
        });
        await _controller.start();
      }
    }
  }

  Future<void> _showResult(CheckInResult result, String token) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ResultSheet(result: result, token: token),
    );
  }

  Future<void> _showError(String message) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _Sheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '확인할 수 없어요',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(fontSize: 13.5, height: 1.5)),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기'),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('QR 체크인'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // 어디에 대야 하는지 — 카메라 화면만 있으면 손님도 호스트도 헤맨다.
          Center(
            child: Container(
              width: 236,
              height: 236,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Text(
              '파티 참가권 · 예약 · 이용권 QR을 모두 이 화면에서 확인해요.\n'
              '스캔해도 바로 사용되지 않아요 — 확인한 뒤 버튼을 눌러주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
                height: 1.6,
              ),
            ),
          ),
          if (_busy)
            const ColoredBox(
              color: Colors.black45,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    ),
  );
}

/// 스캔 결과 한 장 — **유형이 무엇이든 같은 모양**이다.
///
/// 상단은 언제나 "누가 왔나"(성함 · 만 나이)이고, 그 아래에 이용 정보가 온다.
/// 호스트가 한눈에 확인해야 하는 것이 그 순서라서다.
class _ResultSheet extends StatefulWidget {
  const _ResultSheet({required this.result, required this.token});

  final CheckInResult result;
  final String token;

  @override
  State<_ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<_ResultSheet> {
  late CheckInResult _r = widget.result;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message ?? '처리하지 못했어요.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '처리 중 오류가 발생했어요. 다시 시도해주세요.';
        });
      }
    }
  }

  /// 결제를 확인하면 그 자리에서 다시 조회한다 — 화면을 닫지 않고 체크인
  /// 버튼이 열리는 것까지 이어져야 한다.
  Future<void> _confirmPayment() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await CheckInService.confirmPayment(widget.token);
      final next = await CheckInService.resolve(widget.token);
      if (!mounted) return;
      setState(() {
        _r = next;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('결제를 확인했어요. 이제 체크인할 수 있어요.')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message ?? '결제를 확인하지 못했어요.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '결제 확인 중 오류가 발생했어요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return _Sheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusBanner(r),
          const SizedBox(height: 14),
          _guestBlock(r),
          if (!r.isEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: _kBorder),
            const SizedBox(height: 12),
            _usageBlock(r),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12.5, color: Colors.redAccent),
            ),
          ],
          const SizedBox(height: 16),
          _actions(context, r),
        ],
      ),
    );
  }

  /// 맨 위 한 줄 — 지금 무엇을 할 수 있는지가 제일 먼저 읽혀야 한다.
  Widget _statusBanner(CheckInResult r) {
    final (label, color) = switch (r.status) {
      CheckInStatus.ready => ('체크인 가능', const Color(0xFF2F9E68)),
      CheckInStatus.done => ('이미 처리된 QR', const Color(0xFF8A8A96)),
      CheckInStatus.blocked => ('지금은 사용할 수 없어요', Colors.redAccent),
    };
    // 현장결제 대기는 '막힘'보다 **무엇을 해야 하는지**가 중요하다.
    final onSitePending = r.canConfirmPayment && r.paymentMethod == 'on_site';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              r.domain.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _kAccent,
              ),
            ),
            const Spacer(),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        if (onSitePending) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '현장결제 예정',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFB25E00),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  r.paymentAmount != null
                      ? '${_comma(r.paymentAmount!)}원을 받은 뒤 결제 확인을 눌러주세요.'
                      : '결제를 받은 뒤 결제 확인을 눌러주세요.',
                  style: const TextStyle(fontSize: 12.5, height: 1.5),
                ),
              ],
            ),
          ),
        ] else if (r.blockReason != null) ...[
          const SizedBox(height: 6),
          Text(
            r.blockReason!,
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
        ],
        if (r.status == CheckInStatus.done && r.checkedInAt != null) ...[
          const SizedBox(height: 4),
          Text(
            '사용 처리: ${_fmtDateTime(r.checkedInAt!)}',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
        ],
      ],
    );
  }

  /// 고객 — 성함과 만 나이. 그 이상은 이 화면에 싣지 않는다.
  ///
  /// 전화번호·생년월일 전체·CI는 서버가 애초에 내려보내지 않는다
  /// (functions/applicantIdentity.js). 나이는 저장값이 아니라 지금 계산한
  /// 값이다 — 해가 바뀌면 옛 나이가 남기 때문이다.
  Widget _guestBlock(CheckInResult r) {
    final g = r.guest;
    if (g == null) {
      return const Text(
        '고객 정보를 확인할 수 없어요.',
        style: TextStyle(fontSize: 13.5, color: Colors.black54),
      );
    }
    final age = g.ageAt();
    final name = g.verifiedName ?? g.personLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (age != null) ...[
              const SizedBox(width: 8),
              Text(
                '만 $age세',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5B5B66),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            if (g.genderLabel.isNotEmpty)
              Text(
                g.genderLabel,
                style: const TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
            if (g.genderLabel.isNotEmpty && g.nickname.isNotEmpty)
              const Text(
                ' · ',
                style: TextStyle(fontSize: 12.5, color: Colors.black26),
              ),
            if (g.nickname.isNotEmpty)
              Text(
                g.nickname,
                style: const TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
            const Spacer(),
            // 신분증 대조의 근거 — 추측이 아니라 서버가 내려준 사실이다.
            Text(
              g.verified ? '본인확인 완료' : '본인확인 전',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: g.verified ? const Color(0xFF2F9E68) : Colors.black38,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 이용 정보 — 유형별로 **호스트가 현장에서 확인해야 하는 줄**만 그린다.
  ///
  /// 줄 이름이 유형마다 다른 이유: 같은 `title`이 파티에서는 파티명이고
  /// 예약에서는 플레이스명이며 이용권에서는 매장명이다. '장소·구성' 같은
  /// 두루뭉술한 이름 하나로 덮으면 호스트가 무엇을 보고 있는지 알 수 없다.
  Widget _usageBlock(CheckInResult r) {
    final rows = switch (r.domain) {
      // 파티 — 성함·만 나이는 위 블록, 여기는 파티명·일시·참가/체크인 상태.
      CheckInDomain.party => <(String, String)>[
        if (r.title.isNotEmpty) ('파티', r.title),
        if (r.at != null) ('파티 일시', _fmtRange(r.at!, r.endAt)),
        if (r.purchasedItem.isNotEmpty) ('참가 구성', r.purchasedItem),
        ?_applicationStatusRow(r),
        _checkInRow(r),
        if (r.paymentMethod != null) ('결제수단', _methodLabel(r.paymentMethod!)),
        if (r.paymentStatus != null)
          ('결제상태', _paymentLabel(r.paymentStatus!, r.paymentAmount)),
      ],
      // 예약 — 어느 객실에 몇 명이 언제 오는가.
      CheckInDomain.reservation => <(String, String)>[
        if (r.title.isNotEmpty) ('플레이스', r.title),
        if (r.at != null) ('예약 일시', _fmtRange(r.at!, r.endAt)),
        if (r.people != null) ('인원', '${r.people}명'),
        if (r.subtitle.isNotEmpty) ('객실·상품', r.subtitle),
        _checkInRow(r),
        if (r.paymentMethod != null) ('결제수단', _methodLabel(r.paymentMethod!)),
        if (r.paymentStatus != null)
          ('결제상태', _paymentLabel(r.paymentStatus!, r.paymentAmount)),
      ],
      // 이용권 — 무엇을 몇 개, 언제 쓰기로 산 것인가.
      // 서버가 title에 매장명을, subtitle에 상품명을 담는다.
      CheckInDomain.voucher => <(String, String)>[
        if (r.subtitle.isNotEmpty) ('상품·이용권', r.subtitle),
        if (r.title.isNotEmpty) ('매장', r.title),
        if (r.quantity != null) ('수량', '${r.quantity}개'),
        if (r.at != null) ('이용일', _fmtRange(r.at!, r.endAt)),
        _checkInRow(r),
        if (r.paymentMethod != null) ('결제수단', _methodLabel(r.paymentMethod!)),
        if (r.paymentStatus != null)
          ('결제상태', _paymentLabel(r.paymentStatus!, r.paymentAmount)),
      ],
      // 서버가 모르는 유형을 돌려준 경우(앱이 서버보다 오래됨) — 있는 값만.
      CheckInDomain.unknown => <(String, String)>[
        if (r.title.isNotEmpty) ('내용', r.title),
        if (r.at != null) ('일시', _fmtRange(r.at!, r.endAt)),
        _checkInRow(r),
      ],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 68,
                  child: Text(
                    row.$1,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.black45,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 참가 상태 — 파티는 **status를 바꾸지 않고** 체크인만 찍으므로, 승인
  /// 상태와 체크인 상태를 각각 보여줘야 호스트가 상황을 정확히 안다
  /// ("승인은 됐는데 아직 안 왔다"와 "이미 들어왔다"는 다른 상황이다).
  (String, String)? _applicationStatusRow(CheckInResult r) {
    final status = r.detail['applicationStatus'] as String?;
    if (status == null || status.isEmpty) return null;
    return ('참가 상태', _applicationLabel(status));
  }

  /// 체크인 상태 — 세 유형이 **같은 줄**을 쓴다. 이미 처리된 건은 언제
  /// 처리됐는지까지 적는다(같은 QR을 두 번 들이댔을 때 필요한 정보다).
  (String, String) _checkInRow(CheckInResult r) => (
    '체크인',
    r.checkedInAt != null
        ? '완료 · ${_fmtDateTime(r.checkedInAt!)}'
        : r.status == CheckInStatus.done
        ? '완료'
        : '전',
  );

  Widget _actions(BuildContext context, CheckInResult r) {
    if (_busy) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black54,
              side: const BorderSide(color: Color(0xFFDDE1EC)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('닫기'),
          ),
        ),
        if (r.canConfirmPayment) ...[
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _confirmPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB25E00),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('결제 확인'),
            ),
          ),
        ] else if (r.status == CheckInStatus.done &&
            r.domain != CheckInDomain.voucher) ...[
          // 잘못 찍은 체크인 되돌리기 — 줄이 길 때 옆 사람 QR을 먼저 찍는
          // 실수가 실제로 난다. 서버가 **그날 안에서만** 받아주고, 이용권은
          // 재고·매출과 얽혀 아예 열지 않는다(checkInTokens.js revokeCheckIn).
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: OutlinedButton(
              onPressed: () => _run(
                () => CheckInService.revoke(widget.token),
                '체크인을 되돌렸어요.',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Color(0xFFF3C4C4)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('체크인 취소'),
            ),
          ),
        ] else if (r.ok) ...[
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () => _run(
                () => CheckInService.consume(widget.token),
                '체크인 처리했어요.',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('체크인 처리'),
            ),
          ),
        ],
      ],
    );
  }
}

String _comma(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

String _two(int v) => v.toString().padLeft(2, '0');

String _fmtDateTime(DateTime d) =>
    '${d.month}월 ${d.day}일 ${_two(d.hour)}:${_two(d.minute)}';

String _fmtRange(DateTime start, DateTime? end) {
  if (end == null) return _fmtDateTime(start);
  // 같은 날이면 시각만, 여러 날이면 날짜까지 — 숙박이 하루로 보이면 안 된다.
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  return sameDay
      ? '${_fmtDateTime(start)} ~ ${_two(end.hour)}:${_two(end.minute)}'
      : '${_fmtDateTime(start)} ~ ${_fmtDateTime(end)}';
}

/// 파티 신청 상태 — 서버가 저장하는 문자열 그대로 받아 사람 말로 옮긴다.
///
/// 'applied'는 즉시확정 파티의 "접수 = 자리 확정"이고 'approved'는 승인제
/// 파티의 승인이다. 현장에서는 둘 다 "들어와도 되는 사람"이라 같은 말을 쓴다 —
/// 구분이 필요한 곳은 통계이지 입구가 아니다.
/// 'attended'는 더 이상 쓰지 않는 옛 상태다(옛 문서에만 남아 있다).
String _applicationLabel(String key) => switch (key) {
  'applied' || 'approved' => '참가 확정',
  'pending' => '승인 대기',
  'rejected' => '거절됨',
  'cancelled' => '취소됨',
  'no_show' => '노쇼',
  'attended' => '참석(옛 기록)',
  _ => key,
};

String _methodLabel(String key) => switch (key) {
  'bank_transfer' => '무통장입금',
  'on_site' => '현장결제',
  _ => key,
};

String _paymentLabel(String status, int? amount) {
  final label = switch (status) {
    'paid' => '결제 완료',
    'awaiting_deposit' => '입금 대기',
    'deposit_pending' => '입금 확인중',
    'on_site_scheduled' => '현장결제 예정',
    'awaiting_approval' => '승인 대기',
    'cancelled' => '결제 취소',
    _ => status,
  };
  return amount == null ? label : '$label · ${_comma(amount)}원';
}
