import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:party_app/models/party_capacity_status.dart';
import 'package:party_app/models/payment_method.dart';
import 'package:party_app/models/payment_status.dart';
import 'package:party_app/screens/full_screen_image_viewer.dart';
import 'package:party_app/utils/applicant_identity.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/widgets/applicant_photo_protection.dart';
import 'package:party_app/widgets/application_result_dialogs.dart';
import 'package:party_app/widgets/occurrence_picker.dart';
import 'package:party_app/widgets/party_capacity_meter.dart';
import 'package:party_app/widgets/party_identity_notice.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/web_frame.dart';

class PartyApplicantsScreen extends StatefulWidget {
  final String partyId;
  final String partyTitle;
  // 다차수 파티일 때 라운드 번호 → 라벨/시간을 보여주기 위한 원본 rounds 배열.
  // 단일 차수 파티면 null.
  final List<Map<String, dynamic>>? rounds;

  /// 파티 문서 — 모집 현황과 취소 사유 안내를 목록 위에 띄우는 데 쓴다.
  final Map<String, dynamic>? partyData;

  const PartyApplicantsScreen({
    super.key,
    required this.partyId,
    required this.partyTitle,
    this.rounds,
    this.partyData,
  });

  @override
  State<PartyApplicantsScreen> createState() => _PartyApplicantsScreenState();
}

class _PartyApplicantsScreenState extends State<PartyApplicantsScreen> {
  /// **이 파티의 신청 전체.** 회차별로 나눠 보여주더라도 한 번에 다 받아 둔다 —
  /// 날짜 선택 화면이 "8/21(금) 신청자 3명"처럼 **모든 날짜의 건수**를 같이
  /// 보여줘야 하므로, 어차피 전체가 필요하다. 날짜를 옮길 때마다 서버를 다시
  /// 부르면 그 사이 건수가 어긋나 보이기까지 한다.
  late Future<List<_ApplicantInfo>> _future;

  /// 이 파티에 있는 회차들. 비어 있으면 단일 날짜 파티라 날짜 고르는 단계를
  /// 아예 거치지 않는다.
  List<String> _occurrenceIds = const [];

  /// 지금 보고 있는 회차. 단일 날짜 파티면 null.
  String? _selected;

  @override
  void initState() {
    super.initState();
    _future = _loadInitial();
  }

  /// 첫 로드에서 회차 목록을 만들고 기본 회차(오늘 이후 가장 가까운 회차)를
  /// 정한다. 목록 자체는 전체를 그대로 들고 있고, 화면에 그릴 때 거른다.
  Future<List<_ApplicantInfo>> _loadInitial() async {
    final all = await _fetchApplicants();
    final ids = buildOccurrenceIds(
      partyData: widget.partyData,
      fromApplications: all.map((a) => a.occurrenceId),
    );
    if (mounted) {
      setState(() {
        _occurrenceIds = ids;
        _selected = defaultOccurrenceId(ids);
      });
    }
    return all;
  }

  /// 회차별 신청 건수 — 날짜 선택 화면에 그대로 쓴다(취소된 신청은 뺀다).
  Map<String, int> _countsOf(List<_ApplicantInfo> all) {
    final counts = <String, int>{};
    for (final a in all) {
      final id = a.occurrenceId;
      if (id == null || a.status == 'cancelled') continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  /// 지금 보고 있는 회차의 신청만 남긴다. 단일 날짜 파티([_selected]가 null)면
  /// 거르지 않는다 — 그 파티의 신청에는 회차 자체가 없다.
  List<_ApplicantInfo> _visible(List<_ApplicantInfo> all) {
    final selected = _selected;
    if (selected == null) return all;
    return all.where((a) => a.occurrenceId == selected).toList();
  }

  /// 날짜 목록을 열어 회차를 고른다. 그냥 닫으면 보던 날짜를 그대로 둔다.
  Future<void> _changeOccurrence(List<_ApplicantInfo> all) async {
    final picked = await showOccurrenceSheet(
      context: context,
      occurrenceIds: _occurrenceIds,
      selected: _selected,
      counts: _countsOf(all),
    );
    if (picked == null || !mounted) return;
    setState(() => _selected = picked);
  }

  /// 회차를 지정하지 않고 **이 파티의 신청 전체**를 받는다. 서버도 회차별
  /// 필터(`occurrenceId`)를 받지만 이 화면은 쓰지 않는다 — 달력이 모든 날짜의
  /// 신청자 수를 보여줘야 해서 어차피 전부 필요하고, 나눠 받으면 화면에 보이는
  /// 목록과 달력 숫자가 서로 다른 시점의 값이 된다.
  Future<List<_ApplicantInfo>> _fetchApplicants() async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-northeast3',
    ).httpsCallable('getApplicants');
    final result = await callable.call<Map<Object?, Object?>>({
      'partyId': widget.partyId,
    });

    final list = (result.data['applicants'] as List<Object?>?) ?? [];
    return list.map((item) {
      final m = item as Map<Object?, Object?>;
      return _ApplicantInfo(
        uid: m['uid'] as String? ?? '',
        applicationId:
            m['applicationId'] as String? ?? m['uid'] as String? ?? '',
        occurrenceId: m['occurrenceId'] as String?,
        identity: ApplicantIdentity.fromMap(
          m['identity'] as Map<Object?, Object?>?,
        ),
        gender: m['gender'] as String? ?? '',
        status: m['status'] as String? ?? 'applied',
        cancelledBy: m['cancelledBy'] as String?,
        refundAmount: (m['refundAmount'] as num?)?.toInt(),
        refundStatus: m['refundStatus'] as String?,
        selectedRounds: (m['selectedRounds'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList(),
        applicationType: m['applicationType'] as String? ?? 'round',
        packageName: m['packageName'] as String?,
        appliedFee: (m['appliedFee'] as num?)?.toInt(),
        payment: PaymentInfo.fromMap(
          (m['payment'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)),
        ),
        // 사전질문 답변·제출 사진 — 승인제 파티에만 있다. 이 콜러블은 호스트
        // 전용이라(서버가 hostId를 확인한다) 다른 참가자에게는 어떤 경로로도
        // 내려가지 않는다.
        answers: (m['answers'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
        ),
        questionsSnapshot: (m['questionsSnapshot'] as List?)
            ?.map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v)))
            .toList(),
        photoIds: (m['photos'] as List?)
            ?.map((e) => (e as Map)['id']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList(),
      );
    }).toList();
  }

  /// 승인·거절·입금확인이 **지금 서버로 가 있는** 신청들.
  ///
  /// 같은 건이 두 번 가면 서버가 막아 주긴 하지만(이미 같은 결정이면 거절),
  /// 그 전에 눌리지 않게 하는 편이 낫다 — 두 번째 탭이 오류로 돌아오면
  /// 방금 잘 끝난 처리가 실패한 것처럼 보인다.
  final Set<String> _inFlight = {};

  bool _isBusy(_ApplicantInfo info) => _inFlight.contains(info.applicationId);

  /// 호스트의 승인/거절 — 서버 콜러블만 상태를 바꾼다.
  ///
  /// 회차는 [applicationId]가 이미 담고 있다(`{uid}_{occurrenceId}`) — 그 값을
  /// **파싱하지 않고 그대로** 보내므로 해당 날짜 신청만 처리된다.
  ///
  /// 서버가 성공으로 답했을 때만 true를 돌려주고, 그때 목록을 다시 불러
  /// '승인 대기' 같은 표시가 곧바로 최신이 된다. 완료 팝업은 **시트가 닫힌
  /// 뒤에** 떠야 해서 여기서 띄우지 않고 호출부가 띄운다.
  Future<bool> _decide(_ApplicantInfo info, String decision) async {
    if (_isBusy(info)) return false;
    setState(() => _inFlight.add(info.applicationId));
    try {
      await FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('decidePartyApplication').call({
        'partyId': widget.partyId,
        'applicationId': info.applicationId,
        'decision': decision,
      });
      if (!mounted) return false;
      setState(() => _future = _fetchApplicants());
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return false;
      // 실패는 예전 그대로다 — 성공 팝업 자리에 오류창을 세우지 않는다.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? '처리하지 못했어요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _inFlight.remove(info.applicationId));
    }
  }

  /// 신청자 심사 상세 — 신원 한 줄, 사전질문 답변, 제출 사진, 승인/거절.
  ///
  /// 사진은 Firebase Storage에서 내려받는다. 규칙(storage.rules)이 호스트와
  /// 신청자 본인만 읽게 하므로 다른 참가자는 경로를 알아도 열 수 없다.
  Future<void> _openApplicantDetail(_ApplicantInfo info) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _ApplicantDetailSheet(
        info: info,
        partyId: widget.partyId,
        // 성공했을 때만 시트를 닫고 완료 팝업을 띄운다. 실패하면 시트는 그대로
        // 남아 바로 다시 시도할 수 있고, 오류 안내는 [_decide]가 이미 띄웠다.
        onDecide: (decision) async {
          final ok = await _decide(info, decision);
          if (!ok) return false;
          if (sheetContext.mounted) Navigator.pop(sheetContext);
          if (!mounted) return true;
          await showApplicationDecisionResult(
            context,
            personLabel: info.personLabel,
            decision: decision,
            paymentStatus: info.payment?.status,
          );
          return true;
        },
      ),
    );
  }

  /// 입금을 확인해야 하는 신청 — '입금확인중'을 먼저, 그다음 '입금대기'.
  /// 취소된 신청은 확인할 것이 없으므로 뺀다.
  List<_ApplicantInfo> _needsDepositCheck(List<_ApplicantInfo> all) {
    final list = all
        .where(
          (a) =>
              a.status != 'cancelled' &&
              a.payment?.method == PaymentMethod.bankTransfer &&
              (a.payment?.status == PaymentStatus.depositPending ||
                  a.payment?.status == PaymentStatus.awaitingDeposit),
        )
        .toList();
    list.sort((a, b) {
      int rank(_ApplicantInfo x) =>
          x.payment?.status == PaymentStatus.depositPending ? 0 : 1;
      return rank(a).compareTo(rank(b));
    });
    return list;
  }

  /// 호스트가 입금을 확인한다 — 서버가 결제완료(paid) + 신청 확정(approved)을
  /// 한 번에 처리한다. 성공하면 목록을 다시 불러 상태가 바로 반영된다.
  Future<void> _confirmDeposit(_ApplicantInfo info) async {
    if (_isBusy(info)) return;
    setState(() => _inFlight.add(info.applicationId));
    // 성공 팝업은 try **밖**에서 띄운다 — 안에 두면 팝업에서 난 오류까지
    // '입금 확인에 실패했어요'로 잡혀, 잘 끝난 처리가 실패로 안내된다.
    var ok = false;
    try {
      await FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('confirmPartyDeposit').call({
        'partyId': widget.partyId,
        // 회차별 신청을 정확히 한 건만 확정한다 — 같은 사람이 8/15·8/22를
        // 둘 다 신청했으면 uid만으로는 어느 건인지 알 수 없다.
        'applicationId': info.applicationId,
        // 회차 개념이 없던 서버로 롤백되는 경우를 대비한 폴백.
        'applicantUid': info.uid,
      });
      ok = true;
    } catch (e) {
      if (!mounted) return;
      final msg =
          e is FirebaseFunctionsException && (e.message ?? '').isNotEmpty
          ? e.message!
          : '입금 확인에 실패했어요.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _inFlight.remove(info.applicationId));
    }
    if (!ok || !mounted) return;

    // 목록을 **팝업보다 먼저** 갱신한다 — 확인을 누르고 돌아왔을 때 '입금
    // 확인' 카드에서 그 줄이 이미 사라져 있어야 끝난 것으로 읽힌다.
    // 보고 있던 회차([_selected])는 그대로라 화면은 같은 날짜에 머문다.
    setState(() => _future = _fetchApplicants());
    await showDepositConfirmedResult(context, personLabel: info.personLabel);
  }

  /// 목록 맨 위의 **입금 확인 카드** — 확인이 필요한 신청만 모아 한 화면에서
  /// 처리한다. 확인할 것이 없으면 그리지 않는다.
  Widget? _depositSection(List<_ApplicantInfo> all) {
    final targets = _needsDepositCheck(all);
    if (targets.isEmpty) return null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PartyChuColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_rounded,
                size: 16,
                color: PartyChuColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '입금 확인 ${targets.length}건',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '입금을 확인하면 결제완료로 바뀌고 신청이 확정돼요.',
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
          const SizedBox(height: 8),
          for (final t in targets) _depositRow(t),
        ],
      ),
    );
  }

  Widget _depositRow(_ApplicantInfo info) {
    final p = info.payment!;
    final claimed = p.status == PaymentStatus.depositPending;
    // 처리 중에는 눌리지 않는다 — 같은 건이 두 번 확정되지 않게.
    final busy = _isBusy(info);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // 입금자명이 신청자와 다를 수 있어 함께 보여준다 — 통장
                  // 내역과 대조하는 사람이 그대로 쓰는 값이다.
                  p.depositorName == null || p.depositorName!.isEmpty
                      ? info.displayLabel
                      : '${info.displayLabel} (입금자 ${p.depositorName})',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${p.status.label}'
                  '${info.appliedFee == null ? '' : ' · ${formatPrice(info.appliedFee!)}'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: claimed
                        ? PartyChuColors.primaryDeep
                        : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 30,
            child: ElevatedButton(
              onPressed: busy ? null : () => _confirmDeposit(info),
              style: ElevatedButton.styleFrom(
                backgroundColor: claimed
                    ? PartyChuColors.primary
                    : Colors.white,
                foregroundColor: claimed
                    ? Colors.white
                    : PartyChuColors.primaryDeep,
                elevation: 0,
                side: claimed
                    ? null
                    : const BorderSide(color: PartyChuColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      '입금 확인',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 목록 위 안내 — 입장 시 본인 확인 안내(항상) + 취소 사유·모집 현황.
  ///
  /// 본인확인 안내는 **파티 데이터가 없어도** 뜬다. 이 화면은 호스트가 입장을
  /// 확인하는 자리이기도 해서, 모집 현황을 그릴 수 없다는 이유로 안내까지
  /// 사라지면 안 된다.
  Widget _header() {
    final data = widget.partyData;
    final cancelLabel = data == null ? null : PartyCancelReason.labelOf(data);
    final status = data == null ? null : PartyCapacityStatus.fromMap(data);
    final showCapacity = status != null && status.hasMin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PartyHostIdentityCheckNotice(),
        if (cancelLabel != null || showCapacity) ...[
          const SizedBox(height: 12),
          _capacityHeader(data!, cancelLabel, status!),
        ],
      ],
    );
  }

  Widget _capacityHeader(
    Map<String, dynamic> data,
    String? cancelLabel,
    PartyCapacityStatus status,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cancelLabel == null
              ? const Color(0xFFE8EBF2)
              : const Color(0xFFE53935),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cancelLabel != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: Color(0xFFE53935),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cancelLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE53935),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 26),
              child: Text(
                '신청자 전원에게 취소 안내가 나갔고, 결제한 참가자는 전액 환불 처리됩니다.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          PartyCapacityMeter(
            status: status,
            autoCancelPolicy: PartyMinCapacityPolicy.fromKey(
              data['minCapacityPolicy'] as String?,
            ).isAutoCancel,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '신청자 목록',
              style: TextStyle(
                fontFamily: 'SeoulHangang',
                fontWeight: FontWeight.w500,
                fontSize: 16,
                shadows: [
                  Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                  Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                  Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                  Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                ],
              ),
            ),
            Text(
              widget.partyTitle,
              style: const TextStyle(fontSize: 11, color: Colors.black45),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: _list(),
    );
  }

  Widget _list() {
    return FutureBuilder<List<_ApplicantInfo>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              '불러오기 실패: ${snapshot.error}',
              style: const TextStyle(color: Colors.black45),
            ),
          );
        }

        final all = snapshot.data ?? [];
        // 지금 보고 있는 날짜의 신청만 아래 전부에 쓴다 — 목록·번호·입금 확인
        // 묶음이 한 회차만 보도록 여기서 한 번에 거른다.
        final applicants = _visible(all);
        final selected = _selected;
        // 회차가 있는 파티만 날짜 줄을 그린다. 선택된 날짜와 그 날짜의 신청자
        // 수를 못 박아 두고, 누르면 날짜 목록이 열린다.
        final occurrenceBar = (_occurrenceIds.isEmpty || selected == null)
            ? null
            : OccurrenceHeaderButton(
                occurrenceId: selected,
                count: applicants.where((a) => a.status != 'cancelled').length,
                onTap: () => _changeOccurrence(all),
              );
        final header = _header();

        if (applicants.isEmpty) {
          return Column(
            children: [
              ?occurrenceBar,
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: header,
              ),
              const Expanded(
                child: PawEmptyState(
                  title: '아직 신청자가 없어요',
                  subtitle: '첫 번째 신청자를 기다리고 있어요 💕',
                ),
              ),
            ],
          );
        }

        // 목록 위 고정 칸 — 취소 안내·모집 현황, 그리고 입금 확인이 필요한
        // 신청 묶음. 호스트가 다른 화면으로 가지 않고 여기서 다 처리한다.
        final leading = <Widget>[header, ?_depositSection(applicants)];

        return Column(
          children: [
            ?occurrenceBar,
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: applicants.length + leading.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  if (index < leading.length) return leading[index];
                  final i = index - leading.length;
                  return _ApplicantTile(
                    info: applicants[i],
                    number: i + 1,
                    rounds: widget.rounds,
                    // 심사할 것이 있거나 승인 대기 중이면 눌러서 상세를 연다.
                    // 즉시확정 파티에는 답변도 사진도 없으므로 예전처럼
                    // 누를 수 없는 줄 그대로다.
                    onTap:
                        applicants[i].hasSubmission ||
                            applicants[i].isPendingApproval
                        ? () => _openApplicantDetail(applicants[i])
                        : null,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ApplicantInfo {
  final String uid;

  /// 신청 문서 ID. 정기 파티는 같은 사람이 회차마다 신청할 수 있어 uid만으로는
  /// 어느 건인지 지목할 수 없다 — 승인·거절·입금확인은 이 값을 서버에 그대로
  /// 되돌려 보낸다(**파싱하지 않는다**).
  final String applicationId;

  /// 이 신청이 어느 회차의 것인지('2026-08-15'). 일회성 파티는 null.
  final String? occurrenceId;

  /// 호스트에게 보여줄 신원(닉네임·실명·본인확인 성별·생년월일).
  /// 실명도 여기에 담겨 온다 — 서버 응답의 최상위 `name`은 같은 값이라 쓰지 않는다.
  final ApplicantIdentity identity;

  final String gender;
  final String status;
  final String? cancelledBy;
  final int? refundAmount;
  final String? refundStatus;
  final List<int>? selectedRounds;

  /// 'round'(개별 차수) | 'package'(차수 패키지). 예전 신청 문서에는 없어
  /// 기본값이 'round'다.
  final String applicationType;

  /// 패키지로 신청한 경우의 패키지명('1+2차 통합권').
  final String? packageName;

  /// 신청 시점에 확정된 결제 금액.
  final int? appliedFee;

  /// 결제 정보 — 무료 파티나 결제가 붙기 전 신청에는 없다.
  final PaymentInfo? payment;

  /// 사전질문 답변 — `{질문id: 답변}`. 승인제가 아닌 파티는 null.
  final Map<String, String>? answers;

  /// 신청 당시의 질문 정의 스냅샷. 답변에는 문구가 없으므로, 화면이 "무엇에
  /// 대한 답인지"를 그리려면 이 목록이 필요하다. 호스트가 나중에 질문을 고쳐도
  /// 이 값은 신청 시점 그대로다.
  final List<Map<String, dynamic>>? questionsSnapshot;

  /// 제출 사진의 id 목록. 실제 파일은 Firebase Storage에 있고
  /// `partyApplications/{partyId}/{applicationId}/{id}` 경로다.
  final List<String>? photoIds;

  const _ApplicantInfo({
    required this.uid,
    required this.applicationId,
    this.occurrenceId,
    required this.identity,
    required this.gender,
    this.status = 'applied',
    this.cancelledBy,
    this.refundAmount,
    this.refundStatus,
    this.selectedRounds,
    this.applicationType = 'round',
    this.packageName,
    this.appliedFee,
    this.payment,
    this.answers,
    this.questionsSnapshot,
    this.photoIds,
  });

  bool get isPackage => applicationType == 'package';

  /// 승인제 신청인지 — 호스트가 결정을 내려야 하는 구간.
  bool get isPendingApproval => status == 'pending';

  /// 심사 화면에 보여줄 것이 있는지(답변 또는 사진).
  bool get hasSubmission =>
      (answers != null && answers!.isNotEmpty) ||
      (photoIds != null && photoIds!.isNotEmpty);

  /// 호스트 화면에 그리는 한 줄 — `여성 · 냥냥이(홍길동) · 91년생 (35세)`.
  /// 괄호 안은 **본인확인으로 확인된 실명**이고, 닉네임과 같으면 한 번만 쓴다.
  /// 나이는 여기서 매번 계산된다(저장된 값이 아니다).
  /// 탈퇴·삭제된 계정이면 '탈퇴한 회원'.
  ///
  /// **uid는 어떤 경우에도 이 자리에 오지 않는다.**
  String get displayLabel => identity.displayLabel();

  /// 완료 팝업처럼 **이름만 부르면 되는 자리**에 쓰는 값 —
  /// `냥냥이(홍길동)`. 성별·나이까지 붙는 [displayLabel]을 그대로
  /// 쓰면 "○○님의 신청을 승인했어요"가 한 줄로 읽히지 않는다.
  String get personLabel => identity.personLabel;

  /// 본인확인 상태를 줄에 표시할 수 있는 신청자인지 — 탈퇴·정보 없음이면
  /// 상태 자체를 말할 근거가 없다.
  bool get canShowVerification => identity.state == ApplicantIdentityState.ok;

  /// 본인확인을 마쳤는지. 서버가 내려준 값을 그대로 쓴다 — 예전처럼 "성별이
  /// 비어 있으면 미확인"으로 넘겨짚지 않는다([ApplicantIdentity.verified]).
  bool get isVerified => identity.verified;

  /// 입장 확인 때 신분증과 대조할 실명. 확인 전이면 null이라 줄이 빠진다.
  String? get verifiedName => identity.verifiedName;
}

class _ApplicantTile extends StatelessWidget {
  final _ApplicantInfo info;
  final int number;
  final List<Map<String, dynamic>>? rounds;

  /// 눌러서 심사 상세를 여는 동작. 볼 것이 없는 신청(즉시확정 파티)은 null이라
  /// 예전처럼 누를 수 없는 줄로 남는다.
  final VoidCallback? onTap;

  const _ApplicantTile({
    required this.info,
    required this.number,
    this.rounds,
    this.onTap,
  });

  static String _fmt(int v) => formatAmount(v);

  String _roundLabel(int roundNumber) {
    final match = rounds?.firstWhere(
      (r) => (r['roundNumber'] as num?)?.toInt() == roundNumber,
      orElse: () => const {},
    );
    final label = match?['label'] as String?;
    return (label != null && label.isNotEmpty) ? label : '$roundNumber차';
  }

  @override
  Widget build(BuildContext context) {
    final isCancelled = info.status == 'cancelled';

    return Opacity(
      opacity: isCancelled ? 0.6 : 1.0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: info.isPendingApproval
                  ? const Color(0xFFD9CDF2)
                  : const Color(0xFFEEEEEE),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE4ED),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$number',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE0568A),
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    // 회차 날짜는 여기 붙이지 않는다 — 위 회차 선택 줄이 지금
                    // 어느 날짜를 보고 있는지 이미 말해준다. 줄마다 같은 날짜를
                    // 되풀이하면 정작 봐야 할 사람 정보가 밀려 잘린다.
                    child: Text(
                      info.displayLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        decoration: isCancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  if (isCancelled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '취소됨',
                        style: TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    )
                  // 성별 뱃지는 없앴다 — 위 문구가 이미 '여성 · …'으로 말한다.
                  //
                  // 본인확인 상태는 **완료·미완료 양쪽 다** 말한다. 예전에는
                  // 미확인일 때만 배지를 붙였는데, 그러면 배지 없는 줄이
                  // "확인했다"인지 "아직 안 봤다"인지 알 수 없어 입장 확인의
                  // 근거로 쓸 수 없다.
                  else if (info.canShowVerification)
                    IdentityVerifiedBadge(verified: info.isVerified),
                ],
              ),
              // 입장 확인용 실명 — 신분증과 대조할 값 하나만 라벨을 달아 따로
              // 그린다. 위 한 줄의 `냥냥이(홍길동)` 괄호 안을 읽게 하면 현장에서
              // 닉네임과 헷갈린다. 취소된 신청은 입장할 일이 없으므로 뺀다.
              if (!isCancelled && info.verifiedName != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 46),
                  child: VerifiedNameLine(verifiedName: info.verifiedName),
                ),
              ],
              // 결제 상태 — 신청이 들어왔다고 돈이 들어온 것은 아니다. 누구를
              // 아직 못 받았는지 타일에서도 바로 보이게 한다.
              if (!isCancelled && info.payment != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 46),
                  child: Row(
                    children: [
                      Icon(
                        info.payment!.method.icon,
                        size: 12,
                        color: info.payment!.status.isUnpaid
                            ? PartyChuColors.primaryDeep
                            : Colors.black45,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${info.payment!.status.label} · '
                        '${info.payment!.method.label}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: info.payment!.status.isUnpaid
                              ? PartyChuColors.primaryDeep
                              : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // 패키지 신청은 차수 배지를 낱개로 늘어놓지 않고 "1+2차 통합권"
              // 하나로 보여준다 — 호스트가 "이 사람은 묶음으로 왔다"를 한눈에
              // 알아야 정산·안내가 어긋나지 않는다. 포함 차수와 결제 금액은
              // 배지 아래 한 줄로 함께 적는다.
              if (!isCancelled &&
                  info.isPackage &&
                  info.selectedRounds != null &&
                  info.selectedRounds!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 46),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0F5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFF6FA0)),
                        ),
                        child: Text(
                          '🎫 ${info.packageName ?? '차수 패키지'}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFF6FA0),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          info.selectedRounds!.map(_roundLabel).join(' + '),
                          if (info.appliedFee != null)
                            formatPrice(info.appliedFee!),
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (!isCancelled &&
                  info.selectedRounds != null &&
                  info.selectedRounds!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 46),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: info.selectedRounds!
                        .map(
                          (rn) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3F7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(
                                  0xFFFF6FA0,
                                ).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              _roundLabel(rn),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFF6FA0),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              if (isCancelled) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 46),
                  child: Text(
                    [
                      info.cancelledBy == 'host' ? '호스트가 파티 취소' : '참가자가 직접 취소',
                      if (info.refundAmount != null && info.refundAmount! > 0)
                        info.refundStatus == 'pending'
                            ? '환불 예정 ${_fmt(info.refundAmount!)}'
                            : '환불 ${_fmt(info.refundAmount!)}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 호스트 전용 신청자 심사 시트.
///
/// 보여주는 것은 세 가지다 — 신원 한 줄(성별·닉네임(실명)·N년생), 사전질문
/// 답변, 제출 사진. 그리고 승인/거절 버튼.
///
/// 사진은 **호스트만** 볼 수 있다. Firebase Storage 규칙이 경로의 소유자(uid)와
/// 파일 메타데이터의 hostId로 판정하므로, 다른 참가자는 이 시트에 닿을 수 없을
/// 뿐 아니라 경로를 알아내도 파일을 열 수 없다(storage.rules 참고).
///
/// 사진 영역은 파티의 사진 요청 옵션이 아니라 **이 신청에 저장된 사진**으로
/// 열린다 — 호스트가 옵션을 끈 뒤에도 이미 제출된 사진은 계속 심사할 수 있다.
class _ApplicantDetailSheet extends StatelessWidget {
  final _ApplicantInfo info;
  final String partyId;

  /// 승인/거절을 서버로 보내고 **성공했는지** 돌려준다. 실패면 시트가
  /// 그대로 남아 재시도할 수 있다.
  final Future<bool> Function(String decision) onDecide;

  const _ApplicantDetailSheet({
    required this.info,
    required this.partyId,
    required this.onDecide,
  });

  static const _accent = Color(0xFF7C5CBF);

  /// 질문 문구는 신청 당시 스냅샷에서 읽는다 — 호스트가 나중에 질문을 고쳐도
  /// 이 사람이 무엇에 답했는지가 바뀌면 안 된다.
  List<({String text, String answer, bool required})> get _qa {
    final snap = info.questionsSnapshot;
    final answers = info.answers ?? const {};
    if (snap == null || snap.isEmpty) return const [];
    return [
      for (final q in snap)
        (
          text: q['text']?.toString() ?? '',
          answer: answers[q['id']?.toString() ?? ''] ?? '',
          required: q['required'] == true,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final qa = _qa;
    // 사진 영역을 그릴지는 **이 신청에 저장된 사진**으로 정한다. 파티의 현재
    // 사진 요청 옵션은 보지 않는다.
    //
    // 옵션을 끄면 신규 신청자에게는 제출 칸이 사라지지만(신청 화면은 여전히
    // `requiresPhotos`로만 열린다), 이미 받아 둔 사진까지 호스트 화면에서
    // 사라지면 심사 중이던 사람의 제출물이 통째로 없어진 것처럼 보인다.
    // Storage 파일도 신청 문서의 photos도 지우지 않으므로, 여기서도 감추지
    // 않고 그대로 보여준다.
    //
    // 옵션이 켜져 있어도 아직 아무도 내지 않았으면 목록이 비어 있어 어차피
    // 그리지 않는다 — 그래서 "옵션 ON 이거나 기존 사진 있음"은 결국 이 한
    // 조건으로 모인다.
    final photos = info.photoIds ?? const <String>[];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 14),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE0E2EA),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              children: [
                Text(
                  info.displayLabel,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // 심사 상세도 입장 확인의 근거가 되는 자리다 — 목록 줄과 같은
                // 본인확인 상태·실명을 여기서도 그대로 보여준다.
                if (info.canShowVerification) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IdentityVerifiedBadge(verified: info.isVerified),
                  ),
                ],
                if (info.verifiedName != null) ...[
                  const SizedBox(height: 6),
                  VerifiedNameLine(verifiedName: info.verifiedName),
                ],
                if (info.isPendingApproval) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '승인 대기',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: _accent,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (qa.isNotEmpty) ...[
                  const Text(
                    '사전질문 답변',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < qa.length; i++) _qaCard(i, qa[i]),
                  const SizedBox(height: 8),
                ],
                if (photos.isNotEmpty) ...[
                  Text(
                    '제출 사진 ${photos.length}장',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '호스트만 볼 수 있어요. 외부에 공유하지 마세요.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  // 사진에 실제로 걸려 있는 보호 수준을 그대로 적는다 —
                  // Android는 OS가 막고, iOS는 막지 못해 감지·가리기까지다.
                  const ApplicantPhotoHostNotice(),
                  const SizedBox(height: 10),
                  _SubmittedPhotoStrip(
                    partyId: partyId,
                    applicationId: info.applicationId,
                    photoIds: photos,
                  ),
                  const SizedBox(height: 8),
                ],
                if (qa.isEmpty && photos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '제출한 사전질문 답변이나 사진이 없어요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ),
              ],
            ),
          ),
          if (info.isPendingApproval) _DecideBar(onDecide: onDecide),
        ],
      ),
    );
  }

  Widget _qaCard(
    int index,
    ({String text, String answer, bool required}) item,
  ) {
    final answered = item.answer.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${index + 1}.',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _accent,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.text,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
              if (item.required)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text(
                    '필수',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFE0407A),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            answered ? item.answer : '(답변 없음)',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: answered ? Colors.black87 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }
}

/// 승인/거절 버튼 — **누른 순간부터 서버 응답까지** 둘 다 잠근다.
///
/// 승인과 거절이 잇달아 눌리면 두 번째는 서버가 막지만, 호스트 화면에는 그
/// 거절 사유가 오류로 뜬다. 방금 잘 끝난 처리가 실패한 것처럼 보이므로,
/// 애초에 눌리지 않게 한다.
///
/// 성공 여부를 돌려받는 이유는 실패를 되살리기 위해서다 — 실패하면 버튼을
/// 다시 열어 그 자리에서 재시도할 수 있고, 성공하면 시트가 닫히므로 여기로
/// 돌아오지 않는다.
class _DecideBar extends StatefulWidget {
  final Future<bool> Function(String decision) onDecide;

  const _DecideBar({required this.onDecide});

  @override
  State<_DecideBar> createState() => _DecideBarState();
}

class _DecideBarState extends State<_DecideBar> {
  static const _accent = Color(0xFF7C5CBF);

  /// 지금 보낸 결정. null이면 진행 중인 것이 없다.
  String? _sending;

  Future<void> _send(String decision) async {
    if (_sending != null) return;
    setState(() => _sending = decision);
    final ok = await widget.onDecide(decision);
    // 성공하면 시트가 이미 닫혀 있다 — mounted로 걸러 낸다.
    if (!ok && mounted) setState(() => _sending = null);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _sending != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : () => _send('rejected'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD94A4A),
                  side: const BorderSide(color: Color(0xFFEFC6C6)),
                  minimumSize: const Size(0, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: _label('거절', busy: _sending == 'rejected'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: busy ? null : () => _send('approved'),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  minimumSize: const Size(0, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: _label('승인', busy: _sending == 'approved'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, {required bool busy}) => busy
      ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Text(
          text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        );
}

/// 제출 사진 가로 목록 — 썸네일을 누르면 전체화면으로 크게 본다.
///
/// ## 왜 따로 위젯인가
/// 다운로드 URL을 **한 번만** 받아 오기 위해서다. 예전에는 썸네일마다
/// `FutureBuilder`가 자기 URL을 받았는데, 그러면 (1) 시트가 다시 그려질 때마다
/// Storage에 다시 묻고 (2) 사진을 눌렀을 때 **다른 장의 URL을 모르고 있어**
/// 좌우로 넘길 수가 없다. 여기서 한 번에 받아 두면 탭한 즉시 전체 목록을
/// 넘기며 볼 수 있다.
///
/// ## 권한
/// URL은 예전과 똑같이 **호스트의 인증된 Storage SDK 호출**로 받는다
/// (`storage.rules`가 호스트와 신청자 본인만 읽게 한다). 전체보기를 붙였다고
/// 규칙이나 파일 공개 범위를 건드리지 않았다 — 화면만 커졌을 뿐, 이 사진에
/// 닿을 수 있는 사람은 그대로다.
class _SubmittedPhotoStrip extends StatefulWidget {
  final String partyId;
  final String applicationId;
  final List<String> photoIds;

  const _SubmittedPhotoStrip({
    required this.partyId,
    required this.applicationId,
    required this.photoIds,
  });

  @override
  State<_SubmittedPhotoStrip> createState() => _SubmittedPhotoStripState();
}

class _SubmittedPhotoStripState extends State<_SubmittedPhotoStrip> {
  static const double _size = 116;

  /// 사진 id → 다운로드 URL. 실패한 장은 담기지 않는다.
  late final Future<List<String?>> _urls = _resolveUrls();

  Future<List<String?>> _resolveUrls() => Future.wait([
    for (final id in widget.photoIds)
      FirebaseStorage.instance
          .ref(
            'partyApplications/${widget.partyId}/${widget.applicationId}/$id',
          )
          .getDownloadURL()
          // 한 장이 실패해도 나머지는 보여준다.
          .then<String?>((url) => url)
          .catchError((Object e) {
            // 사진 URL이 로그에 남지 않도록 종류만 적는다.
            debugPrint('[제출 사진] URL을 가져오지 못했어요 (${e.runtimeType})');
            return null;
          }),
  ]);

  /// 전체화면으로 연다 — 열 수 있는 사진만 넘겨서 번호('3 / 5')가 실제로 볼 수
  /// 있는 장수와 맞게 한다.
  void _openViewer(List<String?> urls, int tappedIndex) {
    final available = <String>[];
    var initial = 0;
    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      if (url == null) continue;
      if (i == tappedIndex) initial = available.length;
      available.add(url);
    }
    if (available.isEmpty) return;

    // push라 신청자 심사 시트는 그대로 아래 남아 있다 — 닫고 돌아오면 스크롤
    // 위치도, 승인/거절 상태도 그대로다(시트를 다시 만들지 않는다).
    Navigator.push(
      context,
      // 화면을 여는 방식은 이 프로젝트의 다른 곳과 같다(webFramedRoute) —
      // 웹의 넓은 화면에서 본문이 가운데로 모이는 처리를 같이 받는다.
      webFramedRoute<void>(
        (_) => FullScreenImageViewer.gallery(
          imageUrls: available,
          initialIndex: initial,
          // 저장·공유 버튼 없이 보기만 하는 화면이고, 떠 있는 동안
          // 캡처 보호를 하나 더 잡는다.
          protected: true,
        ),
      ),
    );
  }

  Widget _placeholder({required bool failed}) => Container(
    width: _size,
    height: _size,
    decoration: BoxDecoration(
      color: const Color(0xFFF2F3F7),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Center(
      child: failed
          ? const Icon(
              Icons.broken_image_outlined,
              size: 22,
              color: Colors.black26,
            )
          : const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // 썸네일이 화면에 있는 동안 캡처 보호를 잡는다. 전체화면 뷰어도 따로
    // 하나를 잡으므로, 뷰어만 닫아도 이 줄은 계속 보호된다.
    return ProtectedPhotoScope(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: _size,
        child: FutureBuilder<List<String?>>(
          future: _urls,
          builder: (context, snap) {
            final urls = snap.data;
            return ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.photoIds.length,
              separatorBuilder: (_, _) => const SizedBox(width: 9),
              itemBuilder: (_, i) {
                if (urls == null) {
                  return _placeholder(failed: snap.hasError);
                }
                final url = urls[i];
                if (url == null) return _placeholder(failed: true);

                return GestureDetector(
                  onTap: () => _openViewer(urls, i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      url,
                      width: _size,
                      height: _size,
                      fit: BoxFit.cover,
                      // 썸네일이라 원본 해상도로 디코딩할 이유가 없다(전체화면은
                      // 원본 그대로 다시 받는다).
                      cacheWidth: 348,
                      errorBuilder: (_, _, _) => _placeholder(failed: true),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
