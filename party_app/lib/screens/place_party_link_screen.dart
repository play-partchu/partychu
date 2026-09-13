import 'package:flutter/material.dart';

import 'package:party_app/models/party_open_state.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/services/party_create_eligibility.dart';
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/web_frame.dart';

// ══════════════════════════════════════════════════════════════════════════
// 파티 연결 관리 — 이미 등록해둔 일반 파티를 **플레이스(events) 또는
// 공간대여(places)** 에 붙이고 떼는 호스트 전용 화면.
//
// 두 대상은 화면이 하는 일이 완전히 같아서 파일을 나누지 않았다 — 무엇이
// 다른지는 [PartyLinkTarget] 하나에 모여 있고(컬렉션·연결 필드·부르는 이름),
// 이 화면은 그 값을 받아 그대로 넘긴다.
//
// 연결/해제 로직과 필드 설계는 전부 PlacePartyLink(서비스)에 있고, 이 파일은
// 목록 표시와 확인 다이얼로그만 담당한다.
// ══════════════════════════════════════════════════════════════════════════

const Color _kAccent = Color(0xFFFF6FA0);
const Color _kAccentBg = Color(0xFFFFF0F5);

/// 플레이스·공간대여 하나에 연결된 파티를 관리한다 —
/// 목록 확인 / 추가 연결 / 연결 해제.
class PlacePartyLinkScreen extends StatefulWidget {
  /// 대상 문서 id(events/{id} 또는 places/{id}).
  final String targetId;

  /// 대상 문서 데이터 — 후보 추천(주소·좌표 비교)과 연결 시 복사할 장소
  /// 정보의 출처다.
  final Map<String, dynamic> place;

  /// 무엇에 붙이는지. 기본은 플레이스라 기존 호출부는 그대로 동작한다.
  final PartyLinkTarget target;

  const PlacePartyLinkScreen({
    super.key,
    required this.targetId,
    required this.place,
    this.target = PartyLinkTarget.place,
  });

  @override
  State<PlacePartyLinkScreen> createState() => _PlacePartyLinkScreenState();
}

class _PlacePartyLinkScreenState extends State<PlacePartyLinkScreen> {
  List<({String id, Map<String, dynamic> data})> _linked = const [];
  bool _isLoading = true;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _isLoading = true);
    try {
      final linked = await PlacePartyLink.loadLinkedParties(
        widget.targetId,
        target: widget.target,
      );
      if (!mounted) return;
      setState(() {
        _linked = linked;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _msg('연결된 파티를 불러오지 못했어요.');
    }
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openPicker() async {
    final linkedCount = await Navigator.push<int>(
      context,
      webFramedRoute(
        (_) => PartyLinkPickerScreen(
          targetId: widget.targetId,
          place: widget.place,
          target: widget.target,
        ),
      ),
    );
    if (!mounted) return;
    if (linkedCount != null && linkedCount > 0) {
      _msg('파티 $linkedCount개를 연결했어요.');
      await _reload();
    }
  }

  /// 새 파티를 만들어 이 대상에 바로 붙인다.
  ///
  /// **등록 화면을 따로 만들지 않는다** — 정본인 [PartyRegisterScreen]을 그대로
  /// 열고 "어디에 붙일지"([PartyPrelinkTarget])만 넘긴다. 연결은 파티 문서가
  /// 만들어진 뒤 그쪽 저장 마무리에서 커밋되므로(등록 실패·뒤로가기면 아무것도
  /// 만들어지지 않는다), 이 화면은 결과 개수만 받아 목록을 다시 읽는다.
  Future<void> _createAndLink() async {
    // 여기도 결국 새 파티를 만드는 길이라 등록 화면과 같은 관문을 지난다 —
    // 플레이스를 갖고 있다는 사실이 자격을 대신하지 않는다.
    if (!await PartyCreateEligibility.ensure(context)) return;
    if (!mounted) return;
    final linkedCount = await Navigator.push<int>(
      context,
      webFramedRoute(
        (_) => PartyRegisterScreen.forLink(
          target: PartyPrelinkTarget(
            target: widget.target,
            targetId: widget.targetId,
            data: widget.place,
          ),
        ),
      ),
    );
    if (!mounted || linkedCount == null) return;
    // 0이면 등록은 됐지만 연결에 실패한 경우다 — 등록 화면이 이미 사유와 다음
    // 행동을 안내했으므로 여기서는 목록만 최신으로 맞춘다.
    if (linkedCount > 0) {
      _msg('새 파티를 만들어 이 ${widget.target.noun}에 연결했어요.');
    }
    await _reload();
  }

  Future<void> _unlink(String partyId, Map<String, dynamic> party) async {
    final choice = await showUnlinkDialog(context, party);
    if (choice == null || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await PlacePartyLink.unlinkParty(
        targetId: widget.targetId,
        partyId: partyId,
        restorePreviousLocation: choice == UnlinkLocationChoice.restorePrevious,
        target: widget.target,
      );
      if (!mounted) return;
      _msg('연결을 해제했어요. 파티는 그대로 남아 있어요.');
      await _reload();
    } catch (_) {
      _msg('연결 해제에 실패했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeName = widget.place['name'] as String? ?? widget.target.noun;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        title: const Text('파티 연결 관리'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            color: _kAccent,
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _kAccentBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFD6E4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        placeName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isLoading
                            ? '연결된 파티를 불러오는 중...'
                            : '연결된 파티 ${_linked.length}개',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 파티를 붙이는 두 가지 길 — 이미 만들어 둔 파티를 고르거나,
                // 여기서 새로 만들거나. 둘 다 결과가 "연결된 파티 1개"로
                // 같으므로 같은 크기·같은 자리에 나란히 세운다(채움/테두리
                // 차이는 대부분의 호스트가 먼저 찾는 쪽만 눈에 띄게 하려는 것).
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _isBusy ? null : _openPicker,
                    icon: const Icon(Icons.add_link, size: 20),
                    label: const Text('기존 파티 추가 연결'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _isBusy ? null : _createAndLink,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('새 파티 만들기'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kAccent,
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: _kAccent, width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '새로 등록한 파티는 이 ${widget.target.noun}에 자동으로 연결돼요.',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
                const SizedBox(height: 22),
                const Text(
                  '연결된 파티',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: CircularProgressIndicator(color: _kAccent),
                    ),
                  )
                else if (_linked.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        '아직 이 ${widget.target.noun}에 연결된 파티가 없어요.',
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                else
                  for (final item in _linked)
                    _LinkedPartyTile(
                      partyId: item.id,
                      party: item.data,
                      onUnlink: _isBusy
                          ? null
                          : () => _unlink(item.id, item.data),
                    ),
              ],
            ),
          ),
          if (_isBusy)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 연결된 파티 1건 타일
// ─────────────────────────────────────────────────────────────────────────────

/// 호스트 관리 화면 전용 '오픈예정' 칩.
///
/// 공용 [PartyCard.statusChip]은 오픈예정을 그리지 않는다(사용자에게 보이는
/// 카드 규칙). 그 규칙을 건드리지 않으려고 이 화면에만 두는 사본이며, 모양은
/// 예전 공용 칩이 쓰던 색을 그대로 이어받는다 — "아직 못 한다"가 아니라
/// "곧 열린다"는 뜻이라 마감 계열의 회색과 구분한다.
class _PreopenChip extends StatelessWidget {
  const _PreopenChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        PartyOpenState.preopenLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF4F46E5),
        ),
      ),
    );
  }
}

class _LinkedPartyTile extends StatelessWidget {
  final String partyId;
  final Map<String, dynamic> party;
  final VoidCallback? onUnlink;

  const _LinkedPartyTile({
    required this.partyId,
    required this.party,
    required this.onUnlink,
  });

  @override
  Widget build(BuildContext context) {
    final title = party['title'] as String? ?? '파티';
    final date = PartyCard.formatDate(party);
    final status = PartyCard.effectiveStatus(party);
    final hasApplicants = PlacePartyLink.hasApplicants(party);
    // 플레이스+파티 콤보로 한 번에 등록된 파티는 장소 문서가 `linkedPartyId`/
    // `bundleId`로 이 파티를 대표로 가리키고 있어, 링크만 떼면 번들이 반쪽만
    // 남는다 — 목록에는 보여주되 해제는 막는다.
    final isBundled =
        party['isCombo'] == true ||
        (party['bundleId'] as String?)?.isNotEmpty == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 오픈예정은 공용 칩이 그리지 않는다 — 참가자에게 보이는
                    // 카드에서는 "아직 신청 못 한다"는 인상만 남기 때문이다
                    // (PartyCard.isPreopenStatus 참고). 반대로 **호스트 관리
                    // 화면에서는 꼭 보여야 한다** — 어느 파티가 아직 안 열렸는지
                    // 알아야 연결 여부를 판단할 수 있다. 그래서 공용 규칙은
                    // 그대로 두고 이 화면에만 칩을 따로 그린다.
                    if (PartyCard.isPreopenStatus(status))
                      const _PreopenChip()
                    else
                      PartyCard.statusChip(status),
                  ],
                ),
                if (date.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      date,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                if (hasApplicants)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      '신청자가 있는 파티예요',
                      style: TextStyle(fontSize: 11, color: Color(0xFFD97706)),
                    ),
                  ),
                if (isBundled)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      '이 플레이스와 함께 등록된 파티예요 (해제 불가)',
                      style: TextStyle(fontSize: 11, color: Colors.black38),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      webFramedRoute((_) => PartyDetailScreen(docId: partyId)),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: _kAccent,
                    ),
                    child: const Text(
                      '파티 상세 보기 →',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: isBundled ? null : onUnlink,
            style: TextButton.styleFrom(foregroundColor: Colors.black45),
            child: const Text('연결 해제', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// 연결 후보 선택 — 다중 선택 후 한 번에 연결
// ═════════════════════════════════════════════════════════════════════════

/// 연결되지 않은 내 파티 목록을 보여주고 여러 개를 한 번에 연결한다.
/// pop 값은 실제로 연결한 파티 개수(취소하면 null).
class PartyLinkPickerScreen extends StatefulWidget {
  final String targetId;
  final Map<String, dynamic> place;

  /// 무엇에 붙이는지. 후보 추리기(이미 어딘가에 붙은 파티 제외)는 대상과
  /// 무관하게 같고, 실제 쓰기만 대상별로 갈린다.
  final PartyLinkTarget target;

  const PartyLinkPickerScreen({
    super.key,
    required this.targetId,
    required this.place,
    this.target = PartyLinkTarget.place,
  });

  @override
  State<PartyLinkPickerScreen> createState() => _PartyLinkPickerScreenState();
}

class _PartyLinkPickerScreenState extends State<PartyLinkPickerScreen> {
  List<PartyLinkCandidate> _candidates = const [];
  final Set<String> _selected = <String>{};
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final list = await PlacePartyLink.loadCandidates(
        hostId: UserSession.userId,
        place: widget.place,
        target: widget.target,
      );
      if (!mounted) return;
      setState(() {
        _candidates = list;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _msg('파티 목록을 불러오지 못했어요.');
    }
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _submit() async {
    if (_selected.isEmpty) return;
    final withApplicants = _candidates
        .where((c) => _selected.contains(c.id))
        .where((c) => PlacePartyLink.hasApplicants(c.data))
        .toList();
    if (withApplicants.isNotEmpty) {
      final ok = await _confirmApplicants(withApplicants.length);
      if (ok != true || !mounted) return;
    }

    setState(() => _isSaving = true);
    try {
      await PlacePartyLink.linkParties(
        targetId: widget.targetId,
        place: widget.place,
        partyIds: _selected.toList(),
        hostId: UserSession.userId,
        target: widget.target,
      );
      if (!mounted) return;
      Navigator.pop(context, _selected.length);
    } on StateError catch (e) {
      if (mounted) setState(() => _isSaving = false);
      _msg(e.message);
    } catch (_) {
      if (mounted) setState(() => _isSaving = false);
      _msg('연결에 실패했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  Future<bool?> _confirmApplicants(int count) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('신청자가 있는 파티예요', style: TextStyle(fontSize: 17)),
      content: Text(
        '선택한 파티 중 $count개는 이미 신청자가 있어요.\n'
        '연결하면 파티의 장소 정보가 이 플레이스 주소로 바뀝니다. '
        '신청자에게 안내가 필요할 수 있어요.\n\n'
        '제목·소개·일정·참가비·모집 설정은 그대로 유지돼요.',
        style: const TextStyle(fontSize: 13, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: _kAccent),
          child: const Text('그래도 연결하기'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final recommended = _candidates.where((c) => c.isRecommended).toList();
    final others = _candidates.where((c) => !c.isRecommended).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        title: const Text('기존 파티 연결하기'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Stack(
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: _kAccent))
          else if (_candidates.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '연결할 수 있는 파티가 없어요.\n'
                  '이미 다른 플레이스에 연결됐거나 종료된 파티는 목록에 나오지 않아요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black45,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ),
            )
          else
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                const Text(
                  '이 플레이스에서 진행하는 파티를 골라주세요. 여러 개를 한 번에 연결할 수 있어요.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                if (recommended.isNotEmpty) ...[
                  const Text(
                    '📍 추천',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  for (final c in recommended) _tile(c),
                  const SizedBox(height: 18),
                ],
                if (others.isNotEmpty) ...[
                  Text(
                    recommended.isEmpty ? '내 파티' : '그 외 내 파티',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final c in others) _tile(c),
                ],
              ],
            ),
          if (_isSaving)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
      bottomNavigationBar: (_isLoading || _candidates.isEmpty)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (_selected.isEmpty || _isSaving)
                        ? null
                        : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE0E0E0),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Text(
                      _selected.isEmpty
                          ? '연결할 파티를 선택해주세요'
                          : '${_selected.length}개 파티 연결하기',
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _tile(PartyLinkCandidate c) {
    final checked = _selected.contains(c.id);
    final title = c.data['title'] as String? ?? '파티';
    final date = PartyCard.formatDate(c.data);
    final location = c.data['location'] as String? ?? '';
    final reason = c.recommendReason;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: checked ? _kAccent : const Color(0xFFEEEEEE),
          width: checked ? 1.4 : 1,
        ),
      ),
      child: CheckboxListTile(
        value: checked,
        onChanged: _isSaving
            ? null
            : (v) => setState(() {
                if (v == true) {
                  _selected.add(c.id);
                } else {
                  _selected.remove(c.id);
                }
              }),
        activeColor: _kAccent,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (date.isNotEmpty)
              Text(
                date,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            if (location.isNotEmpty)
              Text(
                location,
                style: const TextStyle(fontSize: 12, color: Colors.black38),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (reason != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  reason,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _kAccent,
                  ),
                ),
              ),
            if (PlacePartyLink.hasApplicants(c.data))
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                  '신청자 있음',
                  style: TextStyle(fontSize: 11, color: Color(0xFFD97706)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// 공용 다이얼로그 — 연결 해제 시 장소 정보 처리 선택
// ═════════════════════════════════════════════════════════════════════════

/// 연결 해제 후 파티의 장소 정보를 어떻게 할지.
enum UnlinkLocationChoice {
  /// 플레이스에서 가져온 주소·좌표를 그대로 남긴다.
  keepSnapshot,

  /// 연결 직전에 직접 입력했던 주소·좌표로 되돌린다.
  restorePrevious,
}

/// 연결 해제 확인 + 장소 정보 유지 여부 안내. 취소하면 null.
Future<UnlinkLocationChoice?> showUnlinkDialog(
  BuildContext context,
  Map<String, dynamic> party,
) {
  final hasPrevious =
      party[PlacePartyLink.previousSnapshotField] is Map &&
      (party[PlacePartyLink.previousSnapshotField] as Map).isNotEmpty;
  final hasApplicants = PlacePartyLink.hasApplicants(party);
  // 어느 종류에 붙어 있던 파티인지 — 문구를 '플레이스'로 굳히면 장소대여에
  // 연결된 파티의 해제 안내가 엉뚱한 것을 가리킨다.
  final noun =
      (PlacePartyLink.linkedTargetOf(party) ?? PartyLinkTarget.place).noun;

  return showDialog<UnlinkLocationChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('연결을 해제할까요?', style: TextStyle(fontSize: 17)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '연결을 해제해도 파티는 삭제되지 않아요.',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          if (hasApplicants)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '이 파티에는 신청자가 있어요. 장소 정보가 바뀌면 안내가 필요할 수 있어요.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Color(0xFFD97706),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            hasPrevious
                ? '지금 파티에 표시되는 주소·좌표는 이 $noun에서 가져온 값이에요. '
                      '연결 전에 직접 입력했던 장소로 되돌릴 수도 있어요.'
                : '지금 파티에 표시되는 주소·좌표는 이 $noun에서 가져온 값이에요. '
                      '해제해도 그 정보는 파티에 그대로 남아요.',
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Colors.black54,
            ),
          ),
        ],
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('취소'),
        ),
        if (hasPrevious)
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, UnlinkLocationChoice.restorePrevious),
            child: const Text('이전 장소로 되돌리기'),
          ),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, UnlinkLocationChoice.keepSnapshot),
          style: TextButton.styleFrom(foregroundColor: _kAccent),
          child: const Text('장소 정보 유지하고 해제'),
        ),
      ],
    ),
  );
}

/// 플레이스 등록 직후 띄우는 "기존 파티 연결" 유도 다이얼로그.
/// '기존 파티 연결하기'를 고르면 후보 선택 화면을 열고, 실제 연결한 개수를
/// 돌려준다('나중에 하기'면 0).
Future<int> promptLinkExistingParties({
  required BuildContext context,
  required String eventId,
  required Map<String, dynamic> place,
}) async {
  final wantsLink = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        '이 장소에서 진행하는 기존 파티가 있나요?',
        style: TextStyle(fontSize: 17),
      ),
      content: const Text(
        '이미 등록해둔 파티를 이 플레이스와 연결하면 '
        '파티 상세에서 플레이스 정보를 함께 보여줄 수 있어요.\n\n'
        '파티 제목·소개·일정·참가비·모집 설정은 그대로 유지돼요.',
        style: TextStyle(fontSize: 13, height: 1.5),
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('나중에 하기'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: _kAccent),
          child: const Text('기존 파티 연결하기'),
        ),
      ],
    ),
  );

  if (wantsLink != true || !context.mounted) return 0;
  final count = await Navigator.push<int>(
    context,
    webFramedRoute(
      (_) => PartyLinkPickerScreen(targetId: eventId, place: place),
    ),
  );
  return count ?? 0;
}

/// 호스트가 등록한 **내 공간** 중 하나를 고르는 시트.
///
/// 어떤 종류를 보여줄지는 [targets]가 정한다. 기본값이 플레이스뿐인 이유:
/// 파티 **수정** 화면의 "내 플레이스에서 선택"은 [PlacePartyLink.relinkParty]로
/// 이어지는데 그 경로는 events만 다룬다 — 목록에만 공간대여를 끼워 넣으면
/// 고른 뒤 연결이 조용히 어긋난다. 두 종류를 모두 다루는 등록 폼만
/// `PartyLinkTarget.values.toSet()`을 넘긴다.
///
/// 돌려주는 값은 연결 대상을 나타내는 공용 모델([PartyPrelinkTarget])이다 —
/// 어느 컬렉션의 문서인지가 값 안에 함께 담겨야 부른 쪽이 화면별 문자열
/// 비교 없이 올바른 연결 필드로 저장할 수 있다.
Future<PartyPrelinkTarget?> pickMyPlace(
  BuildContext context, {
  String? excludeEventId,
  Set<PartyLinkTarget> targets = const {PartyLinkTarget.place},
}) async {
  final hostId = UserSession.userId;
  if (hostId.isEmpty) return null;

  final spaces = (await PlacePartyLink.loadMySpaces(hostId: hostId))
      .where((s) => targets.contains(s.target))
      .where((s) => s.targetId != excludeEventId)
      .toList();
  if (!context.mounted) return null;

  if (spaces.isEmpty) {
    final noun = targets.length == 1 ? targets.first.noun : '공간';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('등록한 $noun이 없어요. 먼저 $noun을 등록해주세요.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return null;
  }

  return showModalBottomSheet<PartyPrelinkTarget>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '내 공간에서 선택',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: spaces.length,
              itemBuilder: (_, i) => MySpaceTile(
                space: spaces[i],
                onTap: () => Navigator.pop(ctx, spaces[i]),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// 내 공간 한 줄 — "📍 플레이스 · OO 혼술바" 형태로 종류를 이름 앞에 붙인다.
///
/// 시트(변경)와 등록 진입 선택 화면이 **같은 위젯**을 쓴다. 두 곳이 목록을
/// 따로 그리면 같은 공간이 화면마다 다르게 보인다.
class MySpaceTile extends StatelessWidget {
  final PartyPrelinkTarget space;
  final VoidCallback onTap;
  final bool selected;

  const MySpaceTile({
    super.key,
    required this.space,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final kind = space.target.listingKind;
    final location = space.displayLocation;
    return ListTile(
      leading: Text(kind.emoji, style: const TextStyle(fontSize: 20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: kind.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              kind.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: kind.color,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              space.displayName,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: location.isEmpty
          ? null
          : Text(
              location,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: selected
          ? const Icon(Icons.check_circle, color: _kAccent, size: 20)
          : null,
      onTap: onTap,
    );
  }
}
