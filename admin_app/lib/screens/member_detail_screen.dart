import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/business_info.dart';
import '../services/admin_firestore_service.dart';
import '../services/person_identity_service.dart';
import '../theme/admin_theme.dart';
import '../utils/masking.dart';
import '../utils/person_identity.dart';
import '../widgets/person_accounts_card.dart';

// Firebase Functions 리전 — functions/index.js/memberManagement.js와 일치해야 함.
const _functionsRegion = 'asia-northeast3';

const _accountStatusLabels = {
  'active': '정상',
  'dormant': '휴면',
  'restricted': '이용제한',
  'withdrawn': '탈퇴',
};

const _activityRoleLabels = {
  'host_activity': '호스트 활동',
  'guest_activity': '게스트 활동',
  'place_operator': '플레이스 운영',
  'shop_seller': '파티샵 판매',
  'crew_recruiting': '크루 구인',
  'crew_seeking': '크루 구직',
};

/// userActivityLogs.activityType → 화면 표시 라벨. crew_applied/report_*는
/// 앱에 기능 자체가 없어 절대 기록되지 않지만(memberManagement.js 참고),
/// 나중에 그 기능이 생겼을 때 바로 보이도록 라벨만 미리 마련해둔다.
const _activityTypeLabels = {
  'signup': '회원가입',
  'login': '로그인',
  'identity_verified': '본인인증 완료',
  'party_created': '파티 등록',
  'party_updated': '파티 수정',
  'party_deleted': '파티 삭제',
  'party_cancelled': '파티 모집 취소',
  'party_applied': '파티 참가 신청',
  'party_approved': '참가 신청 승인',
  'party_rejected': '참가 신청 거절',
  'party_application_cancelled': '참가 신청 취소',
  'party_attended': '파티 참가 완료',
  // 호스트가 잘못 찍은 체크인을 되돌린 기록 — 지운 흔적이 없으면 분쟁이
  // 났을 때 무슨 일이 있었는지 아무도 모른다.
  'party_check_in_revoked': '파티 체크인 취소',
  'party_no_show': '노쇼',
  'place_registered': '플레이스 등록',
  'place_reservation_confirmed': '플레이스 예약 확정',
  'place_reservation_cancelled': '플레이스 예약 취소',
  'package_booking_confirmed': '숙박+파티 패키지 예약 확정',
  'package_booking_cancelled': '숙박+파티 패키지 예약 취소',
  'product_registered': '상품 등록',
  'product_purchased': '상품 구매',
  'product_sold': '상품 판매',
  'crew_posted': '크루 공고 등록',
  'crew_applied': '크루 지원',
  'favorite_added': '찜',
  'favorite_removed': '찜 해제',
  'party_shared': '파티 공유',
  'report_filed': '신고 접수',
  'report_received': '신고 받음',
  'admin_status_changed': '관리자 계정상태 변경',
  'admin_memo_updated': '관리자 메모 수정',
  // 관리자가 이 회원이 참여한 채팅방의 대화를 열어본 기록(adminChatViewer.js).
  // 열람도 개인정보 접근이라 상태 변경과 같은 자리에 남긴다 — 대화 양쪽
  // 참여자의 타임라인에 각각 한 줄씩 찍힌다.
  'admin_chat_viewed': '관리자 채팅 열람',
  // 호스트 사전등록(functions/hostPreRegistration.js). 계정 연결·링크 생성은
  // 권한을 열지 않는다 — 권한은 사업자 인증·대표자 승인이 연다.
  'admin_host_preregistration_linked': '관리자 사전등록 계정 연결',
  'admin_business_delegation_link_created': '관리자 대표자 인증 링크 생성',
  'host_preregistration_verified': '호스트 사전등록 인증 완료',
};

class MemberDetailScreen extends StatefulWidget {
  final String uid;
  final VoidCallback onBack;

  /// '보유 계정'에서 같은 사람의 다른 계정을 눌렀을 때 — 그 계정의 상세로 간다.
  final ValueChanged<String>? onOpenMember;

  const MemberDetailScreen({
    super.key,
    required this.uid,
    required this.onBack,
    this.onOpenMember,
  });

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  late Future<_MemberDetailData> _future;

  // 계정 상태/관리자 메모 편집 폼 — 데이터가 처음 로드될 때 한 번만 현재
  // 값으로 채우고, 그 뒤로는 사용자 입력을 그대로 유지한다(재조회 때마다
  // 덮어쓰지 않도록 _formInitialized로 한 번만 초기화).
  bool _formInitialized = false;
  String _accountStatus = 'active';
  final _memoCtrl = TextEditingController();
  bool _isTestAccount = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  void _initFormIfNeeded(Map<String, dynamic> user) {
    if (_formInitialized) return;
    _accountStatus = user['accountStatus'] as String? ?? 'active';
    _memoCtrl.text = user['adminMemo'] as String? ?? '';
    _isTestAccount = user['isTestAccount'] as bool? ?? false;
    _formInitialized = true;
  }

  Future<void> _saveAccountStatusAndMemo() async {
    setState(() => _saving = true);
    try {
      await FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable('adminUpdateMember')
          .call({
        'targetUid': widget.uid,
        'accountStatus': _accountStatus,
        'adminMemo': _memoCtrl.text.trim(),
        'isTestAccount': _isTestAccount,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장했습니다.')));
      setState(() {
        _future = _load();
        _formInitialized = false; // 다음 로드 결과로 폼을 다시 채운다
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<_MemberDetailData> _load() async {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
    final user = userDoc.data() ?? <String, dynamic>{};
    // 같은 사람의 다른 계정 — 실패해도 나머지 상세는 그대로 보여 준다.
    PersonGroup? person;
    Object? personError;
    try {
      person = await PersonIdentityService.accountsOfPerson(widget.uid, user);
    } catch (e) {
      personError = e;
    }
    final applications = await AdminFirestoreService.applicationsForUser(widget.uid);
    final favorites = await AdminFirestoreService.favoritesForUser(widget.uid);
    final userStats = await AdminFirestoreService.userStatsForUser(widget.uid);
    final activityLogs = await AdminFirestoreService.activityLogsForUser(widget.uid);
    // 계정 연결 조회는 실패해도 나머지 상세를 막지 않는다 — 이력이 없는 것과
    // 조회가 실패한 것을 화면에서 구분해 보여준다.
    Map<String, dynamic> linkHistory;
    try {
      linkHistory = await AdminFirestoreService.accountLinkHistory(widget.uid);
    } catch (e) {
      linkHistory = {'error': '$e'};
    }
    return _MemberDetailData(
      user: user,
      person: person,
      personError: personError,
      applications: applications,
      favorites: favorites,
      userStats: userStats,
      activityLogs: activityLogs,
      linkHistory: linkHistory,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
            const Text('회원 상세', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: FutureBuilder<_MemberDetailData>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AdminTheme.accent));
              }
              if (snap.hasError || !snap.hasData) {
                return const Center(child: Text('불러오지 못했습니다.'));
              }
              return _buildBody(snap.data!);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBody(_MemberDetailData data) {
    final d = data.user;
    _initFormIfNeeded(d);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section('기본 프로필', _profileGrid(d)),
          const SizedBox(height: 20),
          _section('보유 계정', _personAccountsSection(data)),
          const SizedBox(height: 20),
          _section('계정 연결 이력', _accountLinkSection(data.linkHistory)),
          const SizedBox(height: 20),
          _section('계정 상태 · 관리자 메모', _accountStatusForm()),
          const SizedBox(height: 20),
          _section('본인확인 정보', _verificationGrid(d)),
          const SizedBox(height: 20),
          _section('사업자 정보', _businessGrid(d)),
          const SizedBox(height: 20),
          _section('호스트로서의 활동', _hostActivitySummary(data.userStats)),
          const SizedBox(height: 20),
          _section('게스트로서의 활동', _usageStatsSummary(data.userStats)),
          const SizedBox(height: 20),
          _section('신청 · 참여 내역', _applicationsTable(data.applications)),
          const SizedBox(height: 20),
          _section('찜 목록', _favoritesTable(data.favorites)),
          const SizedBox(height: 20),
          _section('주 이용 지역 · 시간대', _usagePatternGrid(data.applications)),
          const SizedBox(height: 20),
          _section('통합 활동 타임라인', _timelineList(data.activityLogs)),
        ],
      ),
    );
  }

  /// 실제 회원 1명이 가진 로그인 계정 전부(동일 CI 기준).
  Widget _personAccountsSection(_MemberDetailData data) {
    final person = data.person;
    if (person == null) {
      return Text(
        '보유 계정을 불러오지 못했습니다: ${data.personError}',
        style: const TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary),
      );
    }
    final d = data.user;
    final name = (d['name'] as String?)?.trim();
    final nickname = (d['nickname'] as String?)?.trim();
    return PersonAccountsCard(
      person: person,
      currentUid: widget.uid,
      displayName: name != null && name.isNotEmpty
          ? name
          : (nickname != null && nickname.isNotEmpty ? nickname : '(이름 없음)'),
      onOpenAccount: widget.onOpenMember,
    );
  }

  Widget _section(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: AdminTheme.textSecondary, fontSize: 12.5))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13.5))),
        ],
      ),
    );
  }

  Widget _profileGrid(Map<String, dynamic> d) {
    final photoUrl = d['profileImageUrl'] as String? ?? '';
    final signupProvider = d['signupProvider'] as String?;
    final isTestAccount = d['isTestAccount'] as bool? ?? false;
    final signupProviderLabel = signupProvider != null
        ? memberProviderLabels[signupProvider] ?? signupProvider
        : (isTestAccount ? '이메일(테스트)' : '-');
    final roles = (d['activityRoles'] as List?)?.cast<String>() ?? const [];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: AdminTheme.accentLight,
          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
          child: photoUrl.isEmpty ? const Icon(Icons.person, size: 28, color: AdminTheme.accent) : null,
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('닉네임', d['nickname'] as String? ?? '-'),
              _kv('UID', widget.uid),
              _kv('이메일', d['email'] as String? ?? '-'),
              _kv('휴대전화', Masking.phone(d['phoneNumber'] as String?)),
              _kv('가입일', _fmtDate(d['createdAt'])),
              _kv('가입 경로', signupProviderLabel + (isTestAccount ? ' (테스트 계정)' : '')),
              _kv('최근 로그인일', _fmtDate(d['lastLoginAt'])),
              _kv('최근 활동일', _fmtDate(d['lastActiveAt'])),
              if (roles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(
                        width: 110,
                        child: Text('활동 배지', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 12.5)),
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final role in roles)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AdminTheme.accentLight,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _activityRoleLabels[role] ?? role,
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminTheme.accent),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 관리자만 바꿀 수 있는 계정 상태(정상/휴면/이용제한/탈퇴)와 내부 메모 —
  /// adminUpdateMember(Cloud Functions onCall)를 통해서만 저장된다. 회원
  /// 자진 탈퇴 플로우는 이번 범위가 아니라, 여기서는 관리자가 상태만 바꾼다.
  Widget _accountStatusForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 110,
              child: Text('계정 상태', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 12.5)),
            ),
            DropdownButton<String>(
              value: _accountStatus,
              items: [
                for (final entry in _accountStatusLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _accountStatus = v);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(
              width: 110,
              child: Text('테스트 계정', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 12.5)),
            ),
            Checkbox(
              value: _isTestAccount,
              onChanged: (v) => setState(() => _isTestAccount = v ?? false),
            ),
            // 좁은 화면에서 줄바꿈되도록 남은 폭만 쓴다.
            const Expanded(
              child: Text('회원 관리 기본 목록·대시보드 통계에서 제외', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('관리자 메모', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 12.5)),
        const SizedBox(height: 6),
        TextField(
          controller: _memoCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            isDense: true,
            hintText: '이 회원에 대한 내부 메모(다른 회원에게는 보이지 않습니다)',
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: _saving ? null : _saveAccountStatusAndMemo,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('저장'),
        ),
      ],
    );
  }

  /// userStats의 호스트 쪽 필드 — 등록/운영 수, 예약, 매출·환불. "받은 신청
  /// 승인/거절/취소 건수"와 "행사 완료 수"는 아직 별도 트리거가 없어 이번
  /// 범위에 포함하지 않았다(향후 과제).
  Widget _hostActivitySummary(Map<String, dynamic>? stats) {
    int n(String key) => (stats?[key] as num?)?.toInt() ?? 0;
    num money(String key) => (stats?[key] as num?) ?? 0;
    final placeReservations = n('totalPlaceReservationsAsHost') + n('totalPackageBookingsAsHost');
    final money2 = NumberFormat('#,###');
    return Wrap(
      spacing: 28,
      runSpacing: 12,
      children: [
        _kvInline('등록한 파티', '${n('totalPartiesCreated')}개'),
        _kvInline('등록한 플레이스', '${n('totalPlacesCreated')}개'),
        _kvInline('등록한 상품', '${n('totalProductsRegistered')}개'),
        _kvInline('등록한 크루 공고', '${n('totalCrewPostings')}건'),
        _kvInline('받은 예약(장소·패키지)', '$placeReservations건'),
        _kvInline('누적 결제 금액', '${money2.format(money('cumulativePaymentAmount'))}원'),
        _kvInline('누적 환불 금액', '${money2.format(money('cumulativeRefundAmount'))}원'),
      ],
    );
  }

  Widget _verificationGrid(Map<String, dynamic> d) {
    final verified = (d['identityVerified'] as bool?) ?? (d['isVerified'] as bool?) ?? false;
    if (!verified) {
      return const Text('본인확인 미완료', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 13));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv('이름', d['name'] as String? ?? '-'),
        _kv('생년월일', _formatBirth(d)),
        _kv('성별', d['gender'] == 'male' ? '남성' : d['gender'] == 'female' ? '여성' : '-'),
        _kv('인증완료일', _fmtDate(d['identityVerifiedAt'])),
        _kv('인증방식', d['verificationProvider'] as String? ?? '-'),
        _kv('CI', Masking.token(d['ci'] as String?)),
        _kv('DI', Masking.token(d['di'] as String?)),
        _kv('휴대폰', Masking.phone(d['phoneNumber'] as String?)),
      ],
    );
  }

  /// 사업자 정보 — 전부 users/{uid}.businessVerification 맵에 이미 저장돼 있는
  /// 값이다. 이 화면이 회원 문서를 이미 읽고 있으므로 추가 조회가 없고,
  /// 가입일·UID·이메일 같은 계정정보는 위 "기본 프로필"의 값을 그대로 쓴다
  /// (사업자 쪽에 중복 저장하지 않는다).
  ///
  /// 이 맵을 만드는 곳은 국세청 진위확인을 실제로 호출하는
  /// verifyBusinessRegistration 하나뿐이라, 그 함수가 배포되기 전이거나 회원이
  /// 인증을 시도한 적이 없으면 맵 자체가 없다 — 그 경우를 "일반회원"으로 본다.
  // ── 계정 연결 이력(탈퇴 → 재가입) ────────────────────────────────────────
  //
  // 같은 본인확인(CI)을 쓰던 계정들을 이어 보여준다. 탈퇴하면 users의 CI는
  // 지워지지만 identityLinks 문서에 이전 uid가 남아, 새 uid로 재가입해도
  // 관리자가 이전 계정을 되짚을 수 있다(functions/identityLink.js).
  //
  // 본인확인을 마치지 않은 회원은 CI가 없어 연결 자체가 없다 — 추적 불가가
  // 정상이며, 그 사실을 숨기지 않고 그대로 적는다.
  Widget _accountLinkSection(Map<String, dynamic> h) {
    if (h['error'] != null) {
      return Text('연결 이력을 불러오지 못했습니다 — ${h['error']}',
          style: const TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary));
    }
    if (h['linked'] != true) {
      return const Text(
        '본인확인 기록이 없어 계정 연결을 추적할 수 없습니다.',
        style: TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary),
      );
    }

    final previous = ((h['previous'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final isRejoined = h['isRejoined'] == true;

    String day(dynamic iso) {
      if (iso is! String) return '-';
      final t = DateTime.tryParse(iso);
      return t == null ? '-' : DateFormat('yyyy.MM.dd').format(t.toLocal());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isRejoined)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFCC80)),
            ),
            child: Text(
              '재가입 계정 — 같은 본인확인으로 이전에 ${previous.length}개 계정을 쓴 적이 있습니다.',
              style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFFB56A00)),
            ),
          )
        else
          const Text('이전에 사용한 계정이 없습니다.',
              style: TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary)),
        if (previous.isNotEmpty) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 24,
              headingRowHeight: 34,
              dataRowMinHeight: 34,
              dataRowMaxHeight: 42,
              columns: const [
                DataColumn(label: Text('이전 UID')),
                DataColumn(label: Text('가입일')),
                DataColumn(label: Text('탈퇴 신청일')),
                DataColumn(label: Text('최종 탈퇴일')),
                DataColumn(label: Text('유형')),
                DataColumn(label: Text('탈퇴 직전 상태')),
              ],
              rows: [
                for (final p in previous)
                  DataRow(cells: [
                    DataCell(SelectableText(
                      p['uid'] as String? ?? '-',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    )),
                    DataCell(Text(day(p['createdAt']))),
                    DataCell(Text(day(p['withdrawalRequestedAt']))),
                    DataCell(Text(day(p['withdrawnAt']))),
                    DataCell(Text(p['withdrawnMemberType'] == 'business'
                        ? '사업자'
                        : p['withdrawnMemberType'] == 'individual'
                            ? '일반'
                            : '-')),
                    // 제재 중에 나간 계정인지 — 재가입 심사에서 가장 먼저 볼 값이다.
                    DataCell(Text(
                      (p['withdrawnFromStatus'] as String?) == null ||
                              p['withdrawnFromStatus'] == 'active'
                          ? '-'
                          : '${p['withdrawnFromStatus']}',
                      style: TextStyle(
                        color: (p['withdrawnFromStatus'] as String?) == 'restricted'
                            ? const Color(0xFFC62828)
                            : null,
                        fontWeight: (p['withdrawnFromStatus'] as String?) == 'restricted'
                            ? FontWeight.bold
                            : null,
                      ),
                    )),
                  ]),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _businessGrid(Map<String, dynamic> d) {
    final biz = BusinessInfo.fromUserDoc(d);
    if (!biz.isBusiness) {
      return const Text(
        '일반회원 — 사업자 인증을 시도한 기록이 없습니다.',
        style: TextStyle(color: AdminTheme.textSecondary, fontSize: 13),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv('사업자 여부', '사업자'),
        _kv('인증 상태', biz.status.label
            + (biz.failReason != null ? ' (${biz.failReason})' : '')),
        // 진위(위 '인증 상태')와 권한은 별개다 — 국세청 확인이 끝나도
        // 본인 명의가 아니면 파티·플레이스 등록 권한은 열리지 않는다.
        if (biz.delegationId.isNotEmpty)
          _kv('위임 문서', biz.delegationId),
        _kv('사용 권한', biz.authorization.label
            + (biz.authorizationReasonLabel.isNotEmpty
                ? ' — ${biz.authorizationReasonLabel}'
                : '')),
        _kv('사업자등록번호', biz.formattedBusinessNumber),
        _kv('상호명', biz.businessName.isNotEmpty ? biz.businessName : '-'),
        _kv('대표자명', biz.representativeName.isNotEmpty ? biz.representativeName : '-'),
        _kv('사업장 주소', biz.businessAddress.isNotEmpty ? biz.businessAddress : '-'),
        _kv('개업일자', biz.formattedOpeningDate),
        // 국세청 납세자 상태 — '계속사업자'/'휴업자'/'폐업자'.
        _kv('휴·폐업 상태', biz.ntsStatusLabel.isNotEmpty ? biz.ntsStatusLabel : '-'),
        _kv('과세유형', biz.taxType.isNotEmpty ? biz.taxType : '-'),
        _kv('인증완료일', biz.verifiedAt == null
            ? '-'
            : DateFormat('yyyy.MM.dd HH:mm').format(biz.verifiedAt!)),
        // 사업자번호 교체 이력 — 있을 때만 보여준다(대부분의 회원에게는 없다).
        if (biz.previousBusinessNumber.isNotEmpty)
          _kv('이전 사업자등록번호',
              '${BusinessInfo.formatBusinessNumber(biz.previousBusinessNumber)}'
              ' (교체 ${biz.changeCount}회)'),
        // 바꾸려다 아직 통과하지 못한 시도. 위 인증 상태는 **기존 사업자**의
        // 것이고 그대로 유효하다 — 변경은 성공한 순간에만 반영된다.
        if (biz.hasPendingChange)
          _kv('변경 시도 중',
              '${BusinessInfo.formatBusinessNumber(biz.pendingChangeBusinessNumber)}'
              ' — ${biz.pendingChangeStatusLabel}'
              '${biz.pendingChangeFailReason != null ? ' (${biz.pendingChangeFailReason})' : ''}'),
        _kv('최근 확인일', biz.lastCheckedAt == null
            ? '-'
            : DateFormat('yyyy.MM.dd HH:mm').format(biz.lastCheckedAt!)),
      ],
    );
  }

  // userStats(원본 신청 기록과 분리된 요약 통계 컬렉션)에서 온 값 — 활동이
  // 없는 회원은 문서 자체가 없을 수 있어 전부 기본값 0/'-'으로 표시한다.
  Widget _usageStatsSummary(Map<String, dynamic>? stats) {
    if (stats == null) {
      return const Text('아직 집계된 이용 통계가 없습니다.', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 13));
    }
    int n(String key) => (stats[key] as num?)?.toInt() ?? 0;
    final favoriteRegion = stats['favoriteRegion'] as String? ?? '-';
    final mostUsedHour = stats['mostUsedHour'] != null ? '${stats['mostUsedHour']}시대' : '-';

    return Wrap(
      spacing: 28,
      runSpacing: 12,
      children: [
        _kvInline('신청', '${n('totalApplications')}회'),
        _kvInline('승인', '${n('totalConfirmed')}회'),
        _kvInline('실제 이용', '${n('totalAttended')}회'),
        _kvInline('취소', '${n('totalCancelled')}회'),
        _kvInline('노쇼', '${n('totalNoShows')}회'),
        _kvInline('찜', '${n('totalFavorites')}회'),
        _kvInline('앱 열기', '${n('totalAppOpens')}회'),
        _kvInline('파티 조회', '${n('totalPartyViews')}회'),
        _kvInline('주 이용 지역', favoriteRegion.replaceAll('_', ' ')),
        _kvInline('주 이용 시간대', mostUsedHour),
        _kvInline('마지막 참여일', _fmtDate(stats['lastParticipationAt'])),
        _kvInline('플레이스 예약(한 것)', '${n('totalPlaceReservationsAsGuest') + n('totalPackageBookingsAsGuest')}건'),
        _kvInline('상품 구매', '${n('totalProductPurchases')}건'),
        // 크루 지원 — 앱에 아직 기능이 없어 항상 0(memberManagement.js 참고).
        _kvInline('크루 지원', '0건 (준비 중)'),
      ],
    );
  }

  Widget _applicationsTable(List<Map<String, dynamic>> applications) {
    if (applications.isEmpty) {
      return const Text('신청 내역이 없습니다.', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 13));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('파티ID')),
          DataColumn(label: Text('상태')),
          DataColumn(label: Text('지역')),
          DataColumn(label: Text('신청일')),
          DataColumn(label: Text('상태 변경일')),
        ],
        rows: [
          for (final a in applications)
            DataRow(cells: [
              DataCell(Text(a['partyId'] as String? ?? '-')),
              DataCell(_StatusChip(status: a['status'] as String? ?? '-')),
              DataCell(Text(a['region'] as String? ?? '-')),
              DataCell(Text(_fmtDate(a['appliedAt']))),
              DataCell(Text(_fmtDate(a['statusUpdatedAt']))),
            ]),
        ],
      ),
    );
  }

  Widget _favoritesTable(List<QueryDocumentSnapshot<Map<String, dynamic>>> favorites) {
    if (favorites.isEmpty) {
      return const Text('찜한 항목이 없습니다.', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 13));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final doc in favorites)
          Chip(
            label: Text('${doc.data()['type']} · ${doc.data()['itemId']}'),
            backgroundColor: AdminTheme.accentLight,
          ),
      ],
    );
  }

  Widget _usagePatternGrid(List<Map<String, dynamic>> applications) {
    if (applications.isEmpty) {
      return const Text('데이터가 누적되면 표시됩니다.', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 13));
    }
    final regionCounts = <String, int>{};
    final hourCounts = <int, int>{};
    for (final a in applications) {
      final region = a['region'] as String?;
      if (region != null && region.isNotEmpty) {
        regionCounts[region] = (regionCounts[region] ?? 0) + 1;
      }
      final dt = a['partyDateTime'] as Timestamp?;
      if (dt != null) {
        final hour = dt.toDate().hour;
        hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
      }
    }
    final topRegion = regionCounts.entries.isEmpty
        ? '-'
        : (regionCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    final topHour = hourCounts.entries.isEmpty
        ? '-'
        : '${(hourCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key}시대';
    return Row(
      children: [
        _kvInline('주 이용 지역', topRegion),
        const SizedBox(width: 32),
        _kvInline('주 이용 시간대', topHour),
      ],
    );
  }

  Widget _kvInline(String k, String v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: const TextStyle(fontSize: 12, color: AdminTheme.textSecondary)),
        const SizedBox(height: 4),
        Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// 호스트·게스트 활동을 시간순으로 섞어 보여주는 통합 타임라인 —
  /// userActivityLogs를 최신순으로 그대로 나열한다.
  Widget _timelineList(List<QueryDocumentSnapshot<Map<String, dynamic>>> logs) {
    if (logs.isEmpty) {
      return const Text('아직 기록된 활동이 없습니다.', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 13));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final doc in logs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    _fmtDate(doc.data()['occurredAt']),
                    style: const TextStyle(fontSize: 12, color: AdminTheme.textSecondary),
                  ),
                ),
                Expanded(
                  child: Text(
                    _activityTypeLabels[doc.data()['activityType']] ??
                        doc.data()['activityType'] as String? ??
                        '-',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                if (doc.data()['actorType'] == 'admin')
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Text('관리자 처리', style: TextStyle(fontSize: 11, color: AdminTheme.textSecondary)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _fmtDate(dynamic ts) {
    if (ts is! Timestamp) return '-';
    return DateFormat('yyyy.MM.dd HH:mm').format(ts.toDate());
  }

  String _formatBirth(Map<String, dynamic> d) {
    final y = d['birthYear'];
    final m = d['birthMonth'];
    final day = d['birthDay'];
    if (y == null) return '-';
    if (m == null || day == null) return '$y';
    return '$y.${m.toString().padLeft(2, '0')}.${day.toString().padLeft(2, '0')}';
  }
}

class _MemberDetailData {
  final Map<String, dynamic> user;

  /// 이 계정의 주인이 가진 계정 전부 — 조회에 실패하면 null.
  final PersonGroup? person;
  final Object? personError;
  final List<Map<String, dynamic>> applications;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> favorites;
  final Map<String, dynamic>? userStats;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> activityLogs;

  /// adminGetAccountLinkHistory 결과 — 탈퇴 후 재가입으로 이어진 계정들.
  final Map<String, dynamic> linkHistory;

  _MemberDetailData({
    required this.user,
    required this.person,
    required this.personError,
    required this.applications,
    required this.favorites,
    required this.userStats,
    required this.activityLogs,
    required this.linkHistory,
  });
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  static const _labels = {
    'applied': '신청',
    'approved': '승인',
    // 'attended'는 옛 문서에만 남아 있는 상태다 — 새로 쓰는 경로는 없다.
    'attended': '실제참여(옛 기록)',
    'cancelled': '취소',
    'rejected': '거절',
    'no_show': '노쇼',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AdminTheme.accentLight, borderRadius: BorderRadius.circular(20)),
      child: Text(_labels[status] ?? status,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminTheme.accent)),
    );
  }
}
