// 파티 상세 하단의 '💬 참여 후기' 영역과, 게스트가 후기를 쓰는 시트.
//
// 카드를 크게 만들지 않는다 — 한 줄 후기 하나에 닉네임·작성일 한 줄이 전부다.
// 후기가 없으면 상세 화면의 공간을 거의 쓰지 않게 한 줄 안내로 접는다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;

import 'package:cloud_functions/cloud_functions.dart';

import 'package:party_app/models/party_review.dart';
import 'package:party_app/models/report_reason.dart';
import 'package:party_app/services/party_review_service.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/user_safety_actions.dart';

const Color _kLine = Color(0xFFECEEF3);

/// 파티 상세 하단 — 후기 목록.
///
/// 후기가 0개면 제목 줄과 한 줄 안내만 남는다(빈 카드나 큰 일러스트를 두지
/// 않는다 — 대부분의 파티가 한동안 0개다).
class PartyReviewSection extends StatelessWidget {
  const PartyReviewSection({super.key, required this.partyId});

  final String partyId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PartyReview>>(
      stream: PartyReviewService.watchForParty(partyId),
      builder: (context, snapshot) {
        // 아직 못 읽었으면 자리를 만들지 않는다 — 상세를 스크롤하는 중에
        // 빈 칸이 생겼다가 채워지면 화면이 튄다.
        if (!snapshot.hasData) return const SizedBox.shrink();
        final reviews = snapshot.data!;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '💬 참여 후기',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${reviews.length}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFFF6FA0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '실제 참여한 게스트가 남긴 후기예요.',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
              const SizedBox(height: 10),
              if (reviews.isEmpty)
                const Text(
                  '아직 후기가 없어요.',
                  style: TextStyle(fontSize: 13, color: Colors.black38),
                )
              else
                for (final r in reviews) _ReviewRow(review: r),
            ],
          ),
        );
      },
    );
  }
}

/// 후기 한 줄 — 닉네임 · 작성일 / 본문.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.review});

  final PartyReview review;

  bool get _isMine => review.authorUid == UserSession.userId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  review.authorNickname,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (review.writtenDateLabel.isNotEmpty) ...[
                const Text(
                  ' · ',
                  style: TextStyle(fontSize: 12, color: Colors.black26),
                ),
                Text(
                  review.writtenDateLabel,
                  style: const TextStyle(fontSize: 12, color: Colors.black38),
                ),
              ],
              const Spacer(),
              // 신고는 기존 UGC 신고 구조를 그대로 쓴다(reports 컬렉션).
              // 내 후기에는 뜨지 않는다 — 본인 신고는 규칙이 막는다.
              if (!_isMine && UserSession.isLoggedIn)
                InkWell(
                  onTap: () => showReportSheet(
                    context,
                    targetType: ReportTargetType.partyReview,
                    targetId: review.id,
                    targetUserId: review.authorUid,
                    targetTitle: '참여 후기',
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(
                      Icons.flag_outlined,
                      size: 14,
                      color: Colors.black26,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            review.text,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

/// 후기 작성·수정 시트. 저장·삭제는 전부 서버 콜러블을 지난다.
///
/// [existing]이 있으면 수정, 없으면 새로 쓴다. 어느 쪽이든 기한이 지났으면
/// 서버가 거절하므로, 이 시트는 서버 메시지를 그대로 보여주기만 한다.
Future<bool> showPartyReviewSheet(
  BuildContext context, {
  required String partyId,
  String? occurrenceId,
  PartyReview? existing,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReviewComposeSheet(
      partyId: partyId,
      occurrenceId: occurrenceId,
      existing: existing,
    ),
  );
  return result ?? false;
}

class _ReviewComposeSheet extends StatefulWidget {
  const _ReviewComposeSheet({
    required this.partyId,
    required this.occurrenceId,
    required this.existing,
  });

  final String partyId;
  final String? occurrenceId;
  final PartyReview? existing;

  @override
  State<_ReviewComposeSheet> createState() => _ReviewComposeSheetState();
}

class _ReviewComposeSheetState extends State<_ReviewComposeSheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.existing?.text ?? '',
  );
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _canSubmit => PartyReviewLimits.isValid(_ctrl.text);

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text)));
  }

  /// 서버가 돌려준 사유를 그대로 보여준다 — 앱이 문구를 다시 지어내면
  /// 실제로 막힌 이유와 다른 말을 하게 된다.
  String _reasonOf(Object e) => e is FirebaseFunctionsException
      ? (e.message ?? '후기를 저장하지 못했어요.')
      : '후기를 저장하지 못했어요. 잠시 후 다시 시도해주세요.';

  Future<void> _submit() async {
    if (!_canSubmit || _busy) return;
    setState(() => _busy = true);
    try {
      await PartyReviewService.submit(
        partyId: widget.partyId,
        occurrenceId: widget.occurrenceId,
        text: _ctrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      _msg('후기를 등록했어요.');
    } catch (e) {
      setState(() => _busy = false);
      _msg(_reasonOf(e));
    }
  }

  Future<void> _delete() async {
    final review = widget.existing;
    if (review == null || _busy) return;
    setState(() => _busy = true);
    try {
      await PartyReviewService.remove(review.id);
      if (!mounted) return;
      Navigator.pop(context, true);
      _msg('후기를 삭제했어요.');
    } catch (e) {
      setState(() => _busy = false);
      _msg(_reasonOf(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final length = PartyReviewLimits.normalize(_ctrl.text).length;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null ? '💬 한 줄 후기 남기기' : '💬 후기 수정',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            '함께한 사람들에게 도움이 되는 한 줄이면 충분해요.',
            style: TextStyle(fontSize: 12.5, color: Colors.black45),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            // 한 줄 후기다 — 줄바꿈을 받지 않는다(서버도 공백으로 접는다).
            maxLines: 1,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            inputFormatters: [
              LengthLimitingTextInputFormatter(PartyReviewLimits.maxLength),
            ],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '예: 처음 갔는데도 편하게 어울릴 수 있었어요',
              hintStyle: const TextStyle(fontSize: 13.5, color: Colors.black26),
              filled: true,
              fillColor: const Color(0xFFF7F7FA),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kLine),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kLine),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '$length / ${PartyReviewLimits.maxLength}자'
            '${length < PartyReviewLimits.minLength ? ' · 최소 ${PartyReviewLimits.minLength}자' : ''}',
            style: TextStyle(
              fontSize: 11.5,
              color: _canSubmit ? Colors.black38 : const Color(0xFFD98324),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.existing != null) ...[
                TextButton(
                  onPressed: _busy ? null : _delete,
                  style: TextButton.styleFrom(foregroundColor: Colors.black45),
                  child: const Text('삭제'),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _canSubmit && !_busy ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6FA0),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(widget.existing == null ? '등록' : '수정'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 게스트 허브의 완료된 파티 카드 아래 한 줄 — 남은 기간과 작성/수정 버튼.
///
/// 참여를 마치지 않았거나(체크인 없음) 기한이 지났고 쓴 후기도 없으면 **아무것도
/// 그리지 않는다**. 진행중 파티 카드에 후기 자리가 생기지 않는 이유다.
///
/// ⚠ 여기 판정은 표시용이다. 실제 자격은 서버가 다시 본다 — 이 줄이 버튼을
///   띄워도 서버가 거절하면 그 사유가 그대로 사용자에게 보인다.
class PartyReviewRow extends StatelessWidget {
  const PartyReviewRow({
    super.key,
    required this.partyId,
    required this.appData,
  });

  final String partyId;

  /// `parties/{partyId}/applications/{id}` 문서 데이터.
  final Map<String, dynamic> appData;

  String? get _occurrenceId => appData['occurrenceId'] as String?;

  /// 신청 문서 id — 서버 `applicationDocId(uid, occurrenceId)`와 같은 규칙.
  String get _applicationId {
    final uid = UserSession.userId;
    final occ = _occurrenceId;
    return occ == null || occ.isEmpty ? uid : '${uid}_$occ';
  }

  /// 참여 완료의 정본 — 신청 상태가 아니라 체크인 시각이다
  /// (functions/checkInRules.js: `attended` 상태는 아무도 쓰지 않는다).
  bool get _checkedIn => _toDate(appData['checkedInAt']) != null;

  /// 이 게스트가 참여한 **회차**의 종료 시각. 정기 파티는 회차 종료를 쓰고,
  /// 일회성은 신청 시점에 베껴 둔 파티 시작 시각으로 물러선다(서버가 파티
  /// 문서의 최종 종료로 다시 계산하므로, 여기 값은 표시용 근사다).
  DateTime? get _occurrenceEnd =>
      _toDate(appData['occurrenceEndAt']) ?? _toDate(appData['partyDateTime']);

  static DateTime? _toDate(Object? v) {
    if (v is DateTime) return v.toLocal();
    try {
      final d = (v as dynamic)?.toDate();
      return d is DateTime ? d.toLocal() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedIn || UserSession.userId.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<PartyReview?>(
      stream: PartyReviewService.watchMine(
        partyId: partyId,
        applicationId: _applicationId,
      ),
      builder: (context, snapshot) {
        final mine = snapshot.data;
        // 이미 쓴 후기가 있으면 **서버가 박아 둔 기한**을 쓴다 — 앱이 다시
        // 계산하지 않으므로 서버 판정과 갈릴 수 없다.
        final window = mine != null
            ? ReviewWindow.fromEndsAt(mine.reviewWindowEndsAt)
            : ReviewWindow.fromOccurrenceEnd(_occurrenceEnd);

        // 기한이 지났고 쓴 것도 없으면 줄 자체를 만들지 않는다.
        if (mine == null && (window == null || !window.isOpen)) {
          return const SizedBox.shrink();
        }

        final canEdit = window != null && window.isOpen;

        return Column(
          children: [
            const Divider(height: 1, color: Color(0xFFE8EBF2)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mine == null ? '💬 한 줄 후기를 남겨보세요' : '💬 내 후기',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        if (mine != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            mine.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          canEdit
                              ? window.label(
                                  prefix: mine == null ? '후기 작성' : '수정 가능',
                                )
                              : '작성 기간이 끝났어요',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: canEdit
                                ? (window.isLastDay
                                      ? const Color(0xFFD98324)
                                      : Colors.black38)
                                : Colors.black26,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 기한이 지나면 버튼 자체를 없앤다(비활성 버튼을 남기면
                  // 눌러 보고 나서야 안 된다는 걸 알게 된다). 이미 쓴 후기는
                  // 그대로 위에 남는다.
                  if (canEdit)
                    TextButton(
                      onPressed: () => showPartyReviewSheet(
                        context,
                        partyId: partyId,
                        occurrenceId: _occurrenceId,
                        existing: mine,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFF6FA0),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: Text(mine == null ? '작성' : '수정'),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
