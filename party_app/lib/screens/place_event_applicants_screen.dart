// ─────────────────────────────────────────────────────────────────────────────
// 호스트용 **매장 이벤트 신청자 목록**.
//
// 파티 신청자 화면(party_applicants_screen.dart)과는 **다른 데이터**를 본다.
//   · 파티      parties/{id}/applications      — 정원·승인·참가비·결제·환불
//   · 매장 이벤트 placeEventApplications        — 신청했다 / 물렀다, 그뿐
//
// 그래서 승인·거절·입금확인 같은 결정 UI가 없다. 여기 있는 것은 "누가 언제
// 신청했는가" 하나다. 두 데이터를 한 화면에서 섞지 않는다 — 섞는 순간 정원
// 없는 이벤트에 정원 문구가 붙고, 매출 집계가 이벤트 신청까지 세게 된다.
//
// 신청자 **이름**은 서버에서 온다([PlaceEventApplicationService.fetchApplicants]).
// 닉네임·실명은 users 문서에 있고 규칙상 본인·관리자만 읽을 수 있어서, 앱이
// 직접 조회할 방법이 없다. 표시 형태는 파티 신청자 화면과 같은 것을 쓴다
// ([ApplicantIdentity.displayLabel]) — **uid는 어떤 경우에도 이 자리에 오지
// 않는다.**
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/services/place_event_application_service.dart';
import 'package:party_app/utils/applicant_identity.dart';
import 'package:party_app/widgets/partychu_ui.dart';

class PlaceEventApplicantsScreen extends StatefulWidget {
  const PlaceEventApplicantsScreen({
    super.key,
    required this.promotion,
    required this.accent,
  });

  final PlacePromotion promotion;
  final Color accent;

  @override
  State<PlaceEventApplicantsScreen> createState() =>
      _PlaceEventApplicantsScreenState();
}

class _PlaceEventApplicantsScreenState
    extends State<PlaceEventApplicantsScreen> {
  late Future<List<PlaceEventApplicant>> _future;

  @override
  void initState() {
    super.initState();
    _future = PlaceEventApplicationService.fetchApplicants(
      widget.promotion.id,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _future = PlaceEventApplicationService.fetchApplicants(
        widget.promotion.id,
      );
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          '신청자',
          style: TextStyle(
            fontFamily: PartyChuTitleFont.family,
            fontWeight: PartyChuTitleFont.medium,
            fontSize: 18,
            color: Colors.black87,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: FutureBuilder<List<PlaceEventApplicant>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _message(
              '신청자를 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
              action: TextButton(
                onPressed: _reload,
                child: const Text('다시 시도'),
              ),
            );
          }
          final all = snap.data ?? const <PlaceEventApplicant>[];
          // **취소한 사람은 신청자 수에 넣지 않는다.** 목록 아래에 따로 접어
          // 두는 이유는, 지워 버리면 "신청했다가 취소했다"는 사실까지 사라져
          // 호스트가 자리를 비워 둔 이유를 알 수 없기 때문이다.
          final applied = all.where((a) => a.isApplied).toList();
          final cancelled = all.where((a) => !a.isApplied).toList();

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                _header(applied.length),
                const SizedBox(height: 14),
                if (applied.isEmpty)
                  _message('아직 신청자가 없어요.')
                else
                  for (var i = 0; i < applied.length; i++) ...[
                    _tile(applied[i], i + 1),
                    const SizedBox(height: 9),
                  ],
                if (cancelled.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    '취소한 신청 ${cancelled.length}건',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 9),
                  for (final a in cancelled) ...[
                    _tile(a, null),
                    const SizedBox(height: 9),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(int count) => Container(
    padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0xFFE8EBF2)),
    ),
    child: Row(
      children: [
        Text(widget.promotion.type.emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            widget.promotion.title.isEmpty
                ? '(제목 없음)'
                : widget.promotion.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$count명',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: widget.accent,
          ),
        ),
      ],
    ),
  );

  Widget _tile(PlaceEventApplicant a, int? number) {
    final withdrawn = a.identity.state != ApplicantIdentityState.ok;
    final at = a.appliedAt;
    final when = at == null
        ? ''
        : '${at.year}.${at.month}.${at.day} '
              '${at.hour.toString().padLeft(2, '0')}:'
              '${at.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              number == null ? '·' : '$number',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black38,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.displayLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: withdrawn ? Colors.black38 : Colors.black87,
                  ),
                ),
                if (when.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '$when 신청',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!a.isApplied)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F1F4),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Text(
                '취소',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.black45,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _message(String text, {Widget? action}) => Container(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE8EBF2)),
    ),
    child: Column(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.5,
            color: Colors.black45,
            height: 1.55,
          ),
        ),
        if (action != null) ...[const SizedBox(height: 6), action],
      ],
    ),
  );
}
