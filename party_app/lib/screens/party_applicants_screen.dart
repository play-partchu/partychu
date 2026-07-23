import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/widgets/partychu_ui.dart';

class PartyApplicantsScreen extends StatefulWidget {
  final String partyId;
  final String partyTitle;
  // 다차수 파티일 때 라운드 번호 → 라벨/시간을 보여주기 위한 원본 rounds 배열.
  // 단일 차수 파티면 null.
  final List<Map<String, dynamic>>? rounds;

  const PartyApplicantsScreen({
    super.key,
    required this.partyId,
    required this.partyTitle,
    this.rounds,
  });

  @override
  State<PartyApplicantsScreen> createState() => _PartyApplicantsScreenState();
}

class _PartyApplicantsScreenState extends State<PartyApplicantsScreen> {
  late Future<List<_ApplicantInfo>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadApplicants();
  }

  Future<List<_ApplicantInfo>> _loadApplicants() async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('getApplicants');
    final result = await callable.call<Map<Object?, Object?>>({'partyId': widget.partyId});

    final list = (result.data['applicants'] as List<Object?>?) ?? [];
    return list.map((item) {
      final m = item as Map<Object?, Object?>;
      return _ApplicantInfo(
        uid: m['uid'] as String? ?? '',
        name: m['name'] as String? ?? '(이름 없음)',
        gender: m['gender'] as String? ?? '',
        status: m['status'] as String? ?? 'applied',
        cancelledBy: m['cancelledBy'] as String?,
        refundAmount: (m['refundAmount'] as num?)?.toInt(),
        refundStatus: m['refundStatus'] as String?,
        selectedRounds: (m['selectedRounds'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList(),
      );
    }).toList();
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
            const Text('신청자 목록',
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
                )),
            Text(
              widget.partyTitle,
              style: const TextStyle(fontSize: 11, color: Colors.black45),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: FutureBuilder<List<_ApplicantInfo>>(
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

          final applicants = snapshot.data ?? [];

          if (applicants.isEmpty) {
            return const PawEmptyState(
              title: '아직 신청자가 없어요',
              subtitle: '첫 번째 신청자를 기다리고 있어요 💕',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: applicants.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _ApplicantTile(
              info: applicants[index],
              number: index + 1,
              rounds: widget.rounds,
            ),
          );
        },
      ),
    );
  }
}

class _ApplicantInfo {
  final String uid;
  final String name;
  final String gender;
  final String status;
  final String? cancelledBy;
  final int? refundAmount;
  final String? refundStatus;
  final List<int>? selectedRounds;
  const _ApplicantInfo({
    required this.uid,
    required this.name,
    required this.gender,
    this.status = 'applied',
    this.cancelledBy,
    this.refundAmount,
    this.refundStatus,
    this.selectedRounds,
  });
}

class _ApplicantTile extends StatelessWidget {
  final _ApplicantInfo info;
  final int number;
  final List<Map<String, dynamic>>? rounds;
  const _ApplicantTile({required this.info, required this.number, this.rounds});

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
    final genderLabel = info.gender == 'male'
        ? '남'
        : info.gender == 'female'
            ? '여'
            : '미확인';
    final genderColor = info.gender == 'male'
        ? Colors.blue.shade500
        : info.gender == 'female'
            ? Colors.pink.shade400
            : Colors.grey;

    return Opacity(
      opacity: isCancelled ? 0.6 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEEEEEE)),
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
                  child: Text(
                    info.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      decoration: isCancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (isCancelled)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '취소됨',
                      style: TextStyle(
                          color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: genderColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      genderLabel,
                      style: TextStyle(
                        color: genderColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
            if (!isCancelled &&
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
                              color: const Color(0xFFFF6FA0).withValues(alpha: 0.3),
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
    );
  }
}
