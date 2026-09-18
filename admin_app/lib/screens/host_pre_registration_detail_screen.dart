import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/business_info.dart';
import '../models/host_pre_registration.dart';
import '../services/host_pre_registration_service.dart';
import '../theme/admin_theme.dart';
import '../utils/masking.dart';
import '../utils/responsive.dart';
import 'host_pre_registrations_screen.dart' show PreRegStatusBadge;

final _fmt = DateFormat('yyyy.MM.dd HH:mm');
String _dt(DateTime? t) => t == null ? '-' : _fmt.format(t);
String _orDash(String v) => v.isEmpty ? '-' : v;

/// 호스트 사전등록 상세.
///
/// 이 화면이 하지 **않는** 것:
///   · 호스트 본인확인·사업자 인증 대행 — 호스트가 앱에서 NICE와 국세청 확인을
///     직접 거친다(verifyBusinessRegistration).
///   · 이메일만으로 인증 처리 — 계정 연결은 신청서와 회원을 잇는 표시일 뿐이다.
///   · 대표자 링크 보관 — 링크는 생성 직후 이 화면에서만 보이고 어디에도 저장되지
///     않는다(서버에는 토큰 해시만 있다).
class HostPreRegistrationDetailScreen extends StatefulWidget {
  final String id;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenMember;
  const HostPreRegistrationDetailScreen({
    super.key,
    required this.id,
    required this.onBack,
    required this.onOpenMember,
  });

  @override
  State<HostPreRegistrationDetailScreen> createState() => _HostPreRegistrationDetailScreenState();
}

class _HostPreRegistrationDetailScreenState extends State<HostPreRegistrationDetailScreen> {
  late Future<HostPreRegistrationDetail> _future;
  final _memoCtrl = TextEditingController();
  bool _memoInitialized = false;
  bool _busy = false;

  /// 방금 만든 대표자 링크 — 화면을 떠나면 사라진다(의도된 동작).
  RepresentativeLinkResult? _freshLink;

  @override
  void initState() {
    super.initState();
    _future = HostPreRegistrationService.getDetail(widget.id);
  }

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = HostPreRegistrationService.getDetail(widget.id));
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _copy(String value, String what) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    _toast('$what 복사했습니다.');
  }

  Future<void> _run(Future<void> Function() job, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      if (done != null) _toast(done);
      _reload();
    } catch (e) {
      _toast(callableErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _update(String action, {String? memo, String? reason, String? uid, bool allowEmailMismatch = false, String? done}) {
    return _run(
      () => HostPreRegistrationService.update(
        widget.id,
        action,
        memo: memo,
        reason: reason,
        uid: uid,
        allowEmailMismatch: allowEmailMismatch,
      ),
      done: done,
    );
  }

  Future<String?> _askText(String title, String hint, {String confirm = '확인'}) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: context.dialogWidth(420),
          child: TextField(controller: ctrl, autofocus: true, maxLines: 3, decoration: InputDecoration(hintText: hint)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(confirm)),
        ],
      ),
    );
    ctrl.dispose();
    return (result == null || result.isEmpty) ? null : result;
  }

  Future<void> _createLink({required bool reissue}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await HostPreRegistrationService.createRepresentativeLink(widget.id, reissue: reissue);
      setState(() => _freshLink = r);
      _toast(reissue ? '대표자 인증 링크를 재발급했습니다. 이전 링크는 더 이상 쓸 수 없습니다.' : '대표자 인증 링크를 생성했습니다.');
      _reload();
    } catch (e) {
      _toast(callableErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerBar(),
        const SizedBox(height: 12),
        Expanded(
          child: FutureBuilder<HostPreRegistrationDetail>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                return const Center(child: CircularProgressIndicator(color: AdminTheme.accent));
              }
              if (snap.hasError || !snap.hasData) {
                return Center(child: Text('불러오지 못했습니다: ${snap.error == null ? '' : callableErrorMessage(snap.error!)}'));
              }
              final d = snap.data!;
              if (!_memoInitialized) {
                _memoCtrl.text = d.pre.memo;
                _memoInitialized = true;
              }
              return _body(d);
            },
          ),
        ),
      ],
    );
  }

  /// 뒤로가기 + 제목 + 동작 버튼. 좁은 화면에서는 버튼을 다음 줄로 내려
  /// 제목이 밀리거나 버튼이 잘리지 않게 한다.
  Widget _headerBar() {
    final busyDot = _busy
        ? const Padding(
            padding: EdgeInsets.only(right: 12),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        : const SizedBox.shrink();
    final formButton = OutlinedButton.icon(
      onPressed: () => HostPreRegistrationService.openInNewTab(HostPreRegistrationService.formUrl),
      icon: const Icon(Icons.open_in_new, size: 16),
      label: const Text('신청폼 열기'),
    );
    final refreshButton = IconButton(tooltip: '새로고침', onPressed: _reload, icon: const Icon(Icons.refresh));

    if (context.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
              const Expanded(
                child: Text('사전등록 상세',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ),
              busyDot,
              refreshButton,
            ],
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 8, children: [formButton]),
        ],
      );
    }
    return Row(
      children: [
        IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
        const Text('사전등록 상세', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const Spacer(),
        busyDot,
        formButton,
        const SizedBox(width: 8),
        refreshButton,
      ],
    );
  }

  Widget _body(HostPreRegistrationDetail d) {
    final p = d.pre;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusBar(p),
          if (p.needsRepresentativeCheck) _representativeWarning(),
          if (!p.imported) _importWarning(p),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _card('신청 정보', _applicationInfo(p)),
              _card('호스트', _hostInfo(p)),
              _card('대표자', _representativeInfo(p)),
              _card('사용기기', _deviceInfo(p)),
            ],
          ),
          const SizedBox(height: 16),
          _section('처리', _processing(p)),
          const SizedBox(height: 16),
          _section('호스트 계정 연결 · 인증 진행', _hostLink(d)),
          if (p.sameAsRepresentative == false || d.delegation != null) ...[
            const SizedBox(height: 16),
            _section('대표자 인증 링크', _representativeLink(d)),
          ],
          const SizedBox(height: 16),
          _section('관리자 메모', _memo(p)),
          const SizedBox(height: 16),
          _section('처리 이력', _timeline(d.history)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── 상단 ────────────────────────────────────────────────────────────────

  Widget _statusBar(HostPreRegistration p) {
    // 업체명이 길면 한 줄에 다 들어가지 않으므로 Wrap으로 흘려보낸다.
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PreRegStatusBadge(status: p.status),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
          child: Text(
            '${_orDash(p.storeName)} · FormHug #${p.serialNumber ?? '-'}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        if (p.processedAt != null)
          Text('처리 ${_dt(p.processedAt)}', style: const TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary)),
      ],
    );
  }

  Widget _representativeWarning() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
      ),
      child: const Row(
        children: [
          Text('⚠', style: TextStyle(fontSize: 26)),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('대표자 확인 필요',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
                SizedBox(height: 4),
                Text(
                  '호스트와 사업자 대표자가 다릅니다. 호스트가 앱에서 사업자 인증을 마쳐 "대표자 확인 필요" 상태가 되면 '
                  '아래에서 대표자 인증 링크를 만들어 대표자에게 전달하세요. 대표자가 NICE 본인확인으로 승인해야 권한이 열립니다.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF92400E)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _importWarning(HostPreRegistration p) {
    final reason = switch (p.importState) {
      'needsFieldMap' => 'FormHug 폼 필드 연결이 저장되지 않아 신청 내용을 아직 가져오지 않았습니다.',
      'fetchFailed' => 'FormHug에서 신청 내용을 가져오지 못했습니다.',
      _ => '신청 내용을 가져오는 중입니다.',
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFFF1F2), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(child: Text(reason, style: const TextStyle(fontSize: 13))),
          TextButton(
            onPressed: () => _run(
              () async => HostPreRegistrationService.formSetup({'action': 'reimport', 'id': widget.id}),
              done: '신청 내용을 다시 가져왔습니다.',
            ),
            child: const Text('다시 가져오기'),
          ),
        ],
      ),
    );
  }

  // ── 신청서 카드 ─────────────────────────────────────────────────────────

  Widget _applicationInfo(HostPreRegistration p) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv('신청 일시', _dt(p.submittedAt)),
          _kv('업체명', _orDash(p.storeName)),
          _kv('사업자등록번호', formatBusinessNumber(p.businessRegistrationNumber),
              copy: p.businessRegistrationNumber, copyLabel: '사업자등록번호를'),
          if (p.missingRequired.isNotEmpty)
            _kv('누락 항목', p.missingRequired.join(', ')),
        ],
      );

  Widget _hostInfo(HostPreRegistration p) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv('이름', _orDash(p.hostName)),
          _kv('가입 이메일', _orDash(p.hostEmail)),
          _kv('연락처', Masking.phone(p.hostPhone)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton.icon(
              onPressed: p.hostEmail.isEmpty ? null : () => _copy(p.hostEmail, '호스트 이메일을'),
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('호스트 이메일 복사'),
            ),
            OutlinedButton.icon(
              onPressed: p.hostPhone.isEmpty ? null : () => _copy(p.hostPhone, '호스트 연락처를'),
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('호스트 연락처 복사'),
            ),
          ]),
        ],
      );

  Widget _representativeInfo(HostPreRegistration p) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv('호스트와 동일', p.sameAsRepresentative == null ? '-' : (p.sameAsRepresentative! ? '예' : '아니오')),
          _kv('대표자 이름', p.sameAsRepresentative == true && p.representativeName.isEmpty ? '(호스트와 동일)' : _orDash(p.representativeName)),
          _kv('대표자 연락처', Masking.phone(p.representativePhone),
              copy: p.representativePhone, copyLabel: '대표자 연락처를'),
          _kv('대표자 이메일', _orDash(p.representativeEmail),
              copy: p.representativeEmail, copyLabel: '대표자 이메일을'),
        ],
      );

  Widget _deviceInfo(HostPreRegistration p) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv('사용기기', p.deviceLabel),
          if (p.usesAndroid) ...[
            const SizedBox(height: 4),
            _screenshotThumb(p),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton.icon(
                onPressed: p.googlePlayScreenshotUrl.isEmpty ? null : () => _openScreenshot(p),
                icon: const Icon(Icons.image_outlined, size: 14),
                label: const Text('Google Play 캡처 보기'),
              ),
              Tooltip(
                message: '신청서의 호스트 가입 이메일을 복사합니다. 캡처 속 Google 계정과 같은지 확인 후 테스터로 추가하세요.',
                child: OutlinedButton.icon(
                  onPressed: p.hostEmail.isEmpty ? null : () => _copy(p.hostEmail, 'Google 이메일(신청서 이메일)을'),
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Google 이메일 복사'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => HostPreRegistrationService.openInNewTab(HostPreRegistrationService.playConsoleUrl),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Google Play Console 열기'),
              ),
            ]),
          ],
        ],
      );

  bool _isSafeImageUrl(String url) => Uri.tryParse(url)?.scheme == 'https';

  Widget _screenshotThumb(HostPreRegistration p) {
    if (p.googlePlayScreenshotUrl.isEmpty || !_isSafeImageUrl(p.googlePlayScreenshotUrl)) {
      return const Text('첨부된 캡처가 없습니다.', style: TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary));
    }
    return InkWell(
      onTap: () => _openScreenshot(p),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 180,
          height: 120,
          color: const Color(0xFFF3F4F6),
          child: _networkImage(p.googlePlayScreenshotUrl, BoxFit.cover),
        ),
      ),
    );
  }

  /// FormHug 서명 링크는 CORS 헤더를 보장하지 않으므로 브라우저 <img>로 그린다.
  Widget _networkImage(String url, BoxFit fit) {
    return Image.network(
      url,
      fit: fit,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      errorBuilder: (_, _, _) => const Center(
        child: Text('이미지를 불러오지 못했습니다\n(링크 만료 시 새로고침)', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5)),
      ),
    );
  }

  void _openScreenshot(HostPreRegistration p) {
    if (!_isSafeImageUrl(p.googlePlayScreenshotUrl)) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          // 화면보다 큰 고정 크기를 쓰면 모바일에서 다이얼로그가 잘린다.
          width: context.dialogWidth(900, margin: 24),
          height: MediaQuery.sizeOf(context).height * 0.8 < 700
              ? MediaQuery.sizeOf(context).height * 0.8
              : 700,
          child: Column(
            children: [
              Row(children: [
                const SizedBox(width: 16),
                Expanded(child: Text(p.googlePlayScreenshotName.isEmpty ? 'Google Play 계정 캡처' : p.googlePlayScreenshotName)),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ]),
              Expanded(
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Center(child: _networkImage(p.googlePlayScreenshotUrl, BoxFit.contain)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 처리 ────────────────────────────────────────────────────────────────

  Widget _processing(HostPreRegistration p) {
    final s = p.status;
    final canPreregister = s == PreRegStatus.newApplication || s == PreRegStatus.reviewing;
    final canHostLink = s == PreRegStatus.reviewing || s == PreRegStatus.preregistered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          ElevatedButton.icon(
            onPressed: !_busy && canPreregister
                ? () => _update('markPreregistered', done: '사전등록 완료로 처리했습니다.')
                : null,
            icon: const Icon(Icons.check, size: 16),
            label: const Text('사전등록 완료'),
          ),
          if (p.sameAsRepresentative != false)
            OutlinedButton.icon(
              onPressed: !_busy && canHostLink
                  ? () => _update('markHostLinkSent', done: '호스트 인증 안내 발송으로 기록했습니다.')
                  : null,
              icon: const Icon(Icons.send_outlined, size: 16),
              // 라벨이 길어 좁은 카드 폭을 넘는다 — 넘칠 때만 두 줄로 접는다.
              label: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: context.fluid(460) - 110),
                child: const Text('호스트 본인확인/사업자 인증 안내 발송 처리'),
              ),
            ),
          if (s != PreRegStatus.rejected && s != PreRegStatus.verified)
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final reason = await _askText('반려', '반려 사유(이력에 남습니다)', confirm: '반려');
                      if (reason != null) await _update('reject', reason: reason, done: '반려했습니다.');
                    },
              icon: const Icon(Icons.block, size: 16),
              label: const Text('반려'),
            ),
          if (s == PreRegStatus.rejected)
            TextButton.icon(
              onPressed: _busy ? null : () => _update('reopen', done: '다시 확인중으로 되돌렸습니다.'),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('반려 취소'),
            ),
        ]),
        if (p.rejectReason.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('반려 사유: ${p.rejectReason}', style: const TextStyle(fontSize: 13)),
        ],
        const SizedBox(height: 8),
        const Text(
          '호스트와 대표자가 같으면, 호스트가 앱 마이페이지에서 NICE 본인확인과 사업자 인증을 직접 진행합니다. '
          '결과는 이 화면을 열 때 자동으로 반영됩니다.',
          style: TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary),
        ),
      ],
    );
  }

  // ── 호스트 계정 연결 ────────────────────────────────────────────────────

  Widget _hostLink(HostPreRegistrationDetail d) {
    final host = d.host;
    if (host == null) return _candidates(d);
    final authLabel = BizAuthorization.fromKey(host.authorization).label;
    final statusLabel = BizStatus.fromKey(host.businessStatus).label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv('연결 계정', '${_orDash(host.nickname)} · ${host.email.isEmpty ? '-' : host.email}'),
        Row(children: [
          const SizedBox(width: 110, child: Text('UID', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 12.5))),
          // UID는 28자 고정이라 좁은 화면에서 그대로 두면 넘친다.
          Expanded(
            child: SelectableText(host.uid, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 10),
        _step('1. 계정 연결', true, '연결됨'),
        _step('2. 본인확인(NICE)', host.identityVerified, host.identityVerified ? '완료' : '미완료 — 호스트가 앱에서 진행'),
        _step(
          '3. 사업자 인증',
          host.authorizedForThis || host.pendingOwnerApprovalForThis,
          host.businessStatus.isEmpty
              ? '미진행 — 호스트가 앱에서 진행'
              : '$statusLabel · $authLabel${host.businessNumberMatches ? '' : ' (신청서와 다른 사업자번호)'}',
        ),
        if (d.pre.sameAsRepresentative == false || host.pendingOwnerApprovalForThis)
          _step('4. 대표자 승인', host.authorizedForThis, host.authorizedForThis ? '승인 완료' : '대기'),
        if (host.verifiedRepresentativeName.isNotEmpty &&
            d.pre.representativeName.isNotEmpty &&
            host.verifiedRepresentativeName.replaceAll(' ', '') != d.pre.representativeName.replaceAll(' ', ''))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '⚠ 국세청에 등록된 대표자명과 신청서의 대표자 이름이 다릅니다. 대표자 링크는 국세청 대표자명과 NICE 실명이 같아야 승인됩니다.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFFB45309)),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          OutlinedButton(onPressed: () => widget.onOpenMember(host.uid), child: const Text('회원 상세 열기')),
          if (d.pre.status != PreRegStatus.verified)
            TextButton(
              onPressed: _busy ? null : () => _update('unlinkHost', done: '연결을 해제했습니다.'),
              child: const Text('연결 해제'),
            ),
        ]),
      ],
    );
  }

  Widget _step(String title, bool ok, String detail) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: ok ? const Color(0xFF059669) : AdminTheme.textSecondary),
        const SizedBox(width: 8),
        SizedBox(width: 130, child: Text(title, style: const TextStyle(fontSize: 13))),
        Expanded(child: Text(detail, style: const TextStyle(fontSize: 13, color: AdminTheme.textSecondary))),
      ]),
    );
  }

  Widget _candidates(HostPreRegistrationDetail d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '신청서 이메일로 가입한 회원을 찾았습니다. 연결은 신청서와 회원을 잇는 표시일 뿐, 본인확인·사업자 인증을 대신하지 않습니다.',
          style: TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary),
        ),
        const SizedBox(height: 8),
        if (d.candidates.isEmpty)
          const Text('같은 이메일로 가입한 회원이 없습니다. 호스트가 가입한 뒤 새로고침하세요.', style: TextStyle(fontSize: 13)),
        for (final c in d.candidates)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(border: Border.all(color: AdminTheme.cardBorder), borderRadius: BorderRadius.circular(8)),
            child: Builder(builder: (context) {
              final info = Text(
                '${_orDash(c.nickname)} · ${_orDash(c.email)} · ${c.matchedByLabel} 일치 · '
                '본인확인 ${c.identityVerified ? '완료' : '미완료'} · 가입 ${_dt(c.createdAt)}',
                style: const TextStyle(fontSize: 13),
              );
              final viewButton =
                  TextButton(onPressed: () => widget.onOpenMember(c.uid), child: const Text('회원 보기'));
              final linkButton = ElevatedButton(
                onPressed: _busy || c.accountStatus == 'withdrawn'
                    ? null
                    : () => _update('linkHost', uid: c.uid, done: '호스트 계정을 연결했습니다.'),
                child: const Text('연결'),
              );
              // 좁은 화면에서는 버튼 두 개가 설명글을 밀어내므로 아래로 내린다.
              if (context.isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    info,
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 4, children: [viewButton, linkButton]),
                  ],
                );
              }
              return Row(children: [Expanded(child: info), viewButton, linkButton]);
            }),
          ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _busy ? null : _manualLink,
          icon: const Icon(Icons.person_search, size: 16),
          label: const Text('다른 이메일로 가입한 계정을 UID로 연결'),
        ),
      ],
    );
  }

  Future<void> _manualLink() async {
    final uid = await _askText('UID로 계정 연결', '회원 관리에서 확인한 UID');
    if (uid == null) return;
    // 서버가 이메일 일치를 다시 확인한다. 다르면 사유를 받아 한 번 더 요청한다.
    try {
      await HostPreRegistrationService.update(widget.id, 'linkHost', uid: uid);
      _toast('호스트 계정을 연결했습니다.');
      _reload();
    } catch (e) {
      final msg = callableErrorMessage(e);
      if (!msg.contains('이메일')) {
        _toast(msg);
        return;
      }
      final reason = await _askText('이메일이 다릅니다', '신청자 본인 계정임을 확인한 방법(이력에 남습니다)', confirm: '연결');
      if (reason == null) return;
      await _update('linkHost', uid: uid, allowEmailMismatch: true, reason: reason, done: '호스트 계정을 연결했습니다.');
    }
  }

  // ── 대표자 인증 링크 ────────────────────────────────────────────────────

  Widget _representativeLink(HostPreRegistrationDetail d) {
    final link = d.delegation;
    final status = link?.linkStatus ?? 'none';
    final canCreate = status != 'requested' && status != 'approved' && d.pre.status != PreRegStatus.verified;
    final canReissue = status == 'requested';
    final pendingForThis = d.host?.pendingOwnerApprovalForThis == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const SizedBox(width: 110, child: Text('링크 상태', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 12.5))),
          _linkBadge(status),
        ]),
        const SizedBox(height: 8),
        if (link != null) ...[
          _kv('생성', _dt(link.requestedAt)),
          _kv('만료', _dt(link.expiresAt)),
          if (link.approvedAt != null) _kv('승인', _dt(link.approvedAt)),
          _kv('본인확인 시도', '${link.attemptCount}회'),
          if (link.needsManualReview)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '⚠ 이 사업자에 기존에 확인된 대표자 본인확인 정보와 달라 자동 승인이 멈췄습니다. 수동 확인이 필요합니다.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFFB91C1C)),
              ),
            ),
        ],
        if (!pendingForThis && status != 'approved')
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '호스트 계정이 연결되고, 호스트가 앱에서 이 사업자번호로 사업자 인증을 마쳐 "대표자 확인 필요" 상태여야 링크를 만들 수 있습니다.',
              style: TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary),
            ),
          ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ElevatedButton.icon(
            onPressed: !_busy && canCreate ? () => _createLink(reissue: false) : null,
            icon: const Icon(Icons.add_link, size: 16),
            label: const Text('대표자 인증링크 생성'),
          ),
          OutlinedButton.icon(
            onPressed: _freshLink == null ? null : () => _copy(_freshLink!.approvalUrl, '대표자 인증 링크를'),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('대표자 인증링크 복사'),
          ),
          OutlinedButton.icon(
            onPressed: !_busy && status == 'requested' && d.pre.status != PreRegStatus.representativeLinkSent
                ? () => _update('markRepresentativeLinkSent', done: '대표자 링크 발송으로 기록했습니다.')
                : null,
            icon: const Icon(Icons.send_outlined, size: 16),
            label: const Text('대표자 인증링크 발송 처리'),
          ),
          TextButton.icon(
            onPressed: !_busy && canReissue
                ? () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('링크 재발급'),
                        content: const Text('이전 링크는 즉시 쓸 수 없게 됩니다. 재발급도 호스트의 하루 요청 한도(3회)에 포함됩니다.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('재발급')),
                        ],
                      ),
                    );
                    if (ok == true) await _createLink(reissue: true);
                  }
                : null,
            icon: const Icon(Icons.autorenew, size: 16),
            label: const Text('링크 재발급'),
          ),
        ]),
        if (_freshLink != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(8), border: Border.all(color: AdminTheme.cardBorder)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(_freshLink!.approvalUrl, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                const SizedBox(height: 6),
                Text(
                  '만료 ${_dt(_freshLink!.expiresAt)} · 이 링크는 지금 이 화면에서만 보입니다(서버에는 해시만 저장). '
                  '잃어버리면 재발급해야 합니다.',
                  style: const TextStyle(fontSize: 12, color: AdminTheme.textSecondary),
                ),
              ],
            ),
          ),
        ] else if (status == 'requested')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '대기중인 링크가 있지만 링크 원문은 보관되지 않습니다. 복사가 필요하면 재발급하세요.',
              style: TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary),
            ),
          ),
      ],
    );
  }

  Widget _linkBadge(String status) {
    final (bg, fg) = switch (status) {
      'requested' => (const Color(0xFFE0E7FF), const Color(0xFF3730A3)),
      'approved' => (const Color(0xFFD1FAE5), const Color(0xFF047857)),
      'expired' || 'revoked' || 'rejected' => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
      _ => (const Color(0xFFF3F4F6), const Color(0xFF6B7280)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(linkStatusLabel(status), style: TextStyle(fontSize: 12.5, color: fg, fontWeight: FontWeight.w600)),
    );
  }

  // ── 메모·이력 ───────────────────────────────────────────────────────────

  Widget _memo(HostPreRegistration p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(controller: _memoCtrl, maxLines: 3, maxLength: 2000, decoration: const InputDecoration(hintText: '관리자 메모')),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: _busy ? null : () => _update('saveMemo', memo: _memoCtrl.text.trim(), done: '메모를 저장했습니다.'),
            child: const Text('메모 저장'),
          ),
        ),
      ],
    );
  }

  Widget _timeline(List<PreRegHistoryEntry> history) {
    if (history.isEmpty) return const Text('이력이 없습니다.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final h in history)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            // 좁은 화면에서 날짜·작성자 칸(186px)이 본문을 짓눌러 글자가 한
            // 자씩 끊기므로, 이때는 메타 정보를 윗줄로 올린다.
            child: context.isCompact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_dt(h.at)} · ${h.actorLabel}',
                        style: const TextStyle(fontSize: 12, color: AdminTheme.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(h.message, style: const TextStyle(fontSize: 13.5)),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 130, child: Text(_dt(h.at), style: const TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary))),
                      SizedBox(width: 56, child: Text(h.actorLabel, style: const TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary))),
                      Expanded(child: Text(h.message, style: const TextStyle(fontSize: 13.5))),
                    ],
                  ),
          ),
      ],
    );
  }

  // ── 공통 ────────────────────────────────────────────────────────────────

  Widget _card(String title, Widget child) {
    // 넓은 화면에서는 기존처럼 460 2단 배치, 좁으면 본문 폭에 맞춰 1단으로
    // 떨어진다(Wrap이 자동으로 줄을 바꾼다).
    return SizedBox(width: context.fluid(460), child: _section(title, child));
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

  Widget _kv(String k, String v, {String? copy, String? copyLabel}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: AdminTheme.textSecondary, fontSize: 12.5))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13.5))),
          if (copy != null && copy.isNotEmpty)
            IconButton(
              tooltip: '복사',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: () => _copy(copy, copyLabel ?? '값을'),
              icon: const Icon(Icons.copy),
            ),
        ],
      ),
    );
  }
}
