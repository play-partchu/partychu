// ─────────────────────────────────────────────────────────────────────────────
// 게스트 QR 화면 — **파티·예약·이용권이 같은 한 장**을 쓴다.
//
// 예전에는 이용권에만 QR 다이얼로그가 있었고(voucher_qr_dialog.dart), 파티와
// 예약에는 QR 자체가 없었다. 이제 셋 다 서버가 토큰을 발급하므로 화면도 하나로
// 모은다 — 유형별로 세 벌을 만들면 "한 번 쓰면 끝"이나 "취소되면 못 쓴다" 같은
// 안내가 한쪽에만 붙는 일이 반드시 생긴다.
//
// 유형별로 다른 것은 [CheckInPass]에 담긴 값뿐이고, 이 파일에는 분기가 없다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:party_app/models/check_in_pass.dart';

const Color _kAccent = Color(0xFFFF6FA0);
const Color _kBorder = Color(0xFFE8EBF2);

/// 게스트 QR 한 장을 모달로 띄운다 — 목록 카드에서 부르는 유일한 입구.
Future<void> showCheckInQrSheet(BuildContext context, CheckInPass pass) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckInQrCard(pass: pass),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: Colors.black54),
                  child: const Text('닫기'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 목록 카드에 붙는 'QR 보기' 버튼 — 파티·예약·이용권이 같은 버튼을 쓴다.
///
/// 버튼을 띄울지 말지는 부르는 쪽이 [CheckInPass.hasQr]로 정한다. 여기서
/// 조건을 판단하지 않는 이유는, 카드마다 "QR이 없으면 무엇을 대신 보여줄지"가
/// 다르기 때문이다(결제 안내, 승인 대기 문구 …).
class CheckInQrButton extends StatelessWidget {
  const CheckInQrButton({super.key, required this.pass, this.label = 'QR 보기'});

  final CheckInPass pass;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: () => showCheckInQrSheet(context, pass),
      icon: const Icon(Icons.qr_code_2, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );
}

/// 게스트 QR 카드 본체.
///
/// 순서는 손님이 매장에서 읽는 순서다 — 무엇의 QR인지(제목·일시) → 누구
/// 것인지(성함) → QR → 지금 쓸 수 있는지(상태).
///
/// **유효성은 판단하지 않는다.** 여기 뜬 QR이 실제로 통과하는지는 호스트가
/// 스캔하는 순간 서버가 원본 문서를 다시 읽어 정한다. 화면이 스스로 "쓸 수
/// 있다"고 말하면 서버 판정과 어긋나는 순간 손님이 현장에서 거절당한다.
class CheckInQrCard extends StatelessWidget {
  const CheckInQrCard({super.key, required this.pass});

  final CheckInPass pass;

  @override
  Widget build(BuildContext context) {
    final p = pass;
    // 이미 쓴 QR은 흐리게 — 화면을 다시 열어도 통과하지 않는다는 사실이
    // 문구보다 먼저 읽혀야 한다.
    final dimmed = p.state == CheckInPassState.used;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          p.domain.label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: _kAccent,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          p.title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
        ),
        if (p.subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            p.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: Colors.black45),
          ),
        ],
        if (p.at != null) ...[
          const SizedBox(height: 6),
          Text(
            formatPassRange(p.at!, p.endAt),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF3D3D46),
            ),
          ),
        ],
        if (p.personName.isNotEmpty) ...[
          const SizedBox(height: 4),
          // 호스트는 이 이름과 신분증을 대조한다 — 대리입장·양도가 막히는
          // 근거라서 QR과 같은 화면에 있어야 한다.
          Text(
            '${p.personName} 님',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF3D3D46),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Opacity(
          opacity: dimmed ? 0.25 : 1,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kBorder),
            ),
            child: QrImageView(
              data: p.token,
              version: QrVersions.auto,
              size: 208,
              gapless: false,
              // 밝은 배경에 진한 코드 — 매장 조명이 어두워도 인식률이 높다.
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
        ),
        if (p.itemLabel.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            p.itemLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _kAccent,
            ),
          ),
        ],
        const SizedBox(height: 10),
        _statusChip(p),
        if (p.notice != null && p.notice!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            p.notice!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black45,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 10),
        const Text(
          '입장할 때 이 QR을 보여주세요.\n스캔만으로 처리되지 않고, 확인 뒤 체크인돼요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.black38, height: 1.5),
        ),
      ],
    );
  }

  Widget _statusChip(CheckInPass p) {
    final (bg, fg) = switch (p.state) {
      CheckInPassState.ready => (
        const Color(0xFFE6F6EF),
        const Color(0xFF1F8A63),
      ),
      CheckInPassState.used => (const Color(0xFFF2F2F5), Colors.black45),
      CheckInPassState.pending => (
        const Color(0xFFFFF3E0),
        const Color(0xFFB97400),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        p.statusLabel,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

/// '8월 30일 20:00' / '8월 30일 15:00 ~ 8월 31일 11:00'.
///
/// 같은 날이면 끝 시각만 붙인다 — 숙박이 하루짜리로 보이면 체크아웃 날짜를
/// 잘못 알게 되므로 여러 날은 날짜까지 적는다(호스트 스캔 결과와 같은 규칙).
String formatPassRange(DateTime start, DateTime? end) {
  String two(int v) => v.toString().padLeft(2, '0');
  String one(DateTime d) => '${d.month}월 ${d.day}일 ${two(d.hour)}:${two(d.minute)}';
  if (end == null) return one(start);
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  return sameDay
      ? '${one(start)} ~ ${two(end.hour)}:${two(end.minute)}'
      : '${one(start)} ~ ${one(end)}';
}
