import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:party_app/models/address_result.dart';
import 'package:party_app/models/business_verification.dart';
import 'package:party_app/screens/address_search_screen.dart';
import 'package:party_app/services/business_verification_service.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/payout_account_prompt.dart';
import 'package:party_app/widgets/owner_approval_panel.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 사업자 인증 — 국세청 사업자등록정보 진위확인/상태조회로 실제 사업자인지
/// 확인한다. **계정 단위**라 한 번 통과하면 콘텐츠를 올릴 때마다 다시 입력하지
/// 않는다.
///
/// 입력값은 두 축으로 나뉜다. 섞으면 "주소가 달라서 인증이 떨어졌다"는 오해가
/// 생기므로 화면도 카드를 나눠 보여준다.
///   · **국세청 통과 조건** — 사업자등록번호 + 대표자명 + 개업일자 일치와
///     계속사업자 여부. 이 셋만 진위확인 요청의 판정 대상이다.
///   · **앱에 저장할 사업자 정보** — 상호명 + 사업장 주소. 국세청 통과 여부를
///     가르지 않지만(본점 주소와 실제 개최 주소는 다른 것이 정상이다)
///     **입력은 필수**다. 둘 중 하나라도 비면 확인 요청을 보내지 않는다.
///
/// 입력값은 서버(Cloud Functions)로만 보낸다. 앱이 국세청 API를 직접 부르거나
/// 서비스키를 들고 있지 않는다.
class BusinessVerificationScreen extends StatefulWidget {
  const BusinessVerificationScreen({super.key});

  @override
  State<BusinessVerificationScreen> createState() =>
      _BusinessVerificationScreenState();
}

class _BusinessVerificationScreenState
    extends State<BusinessVerificationScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _bizNoCtrl = TextEditingController();
  final _repNameCtrl = TextEditingController();
  final _openDateCtrl = TextEditingController();
  final _bizNameCtrl = TextEditingController();

  /// 사업장 **기본주소** — 주소검색 결과로만 채운다(직접 타이핑 불가).
  ///
  /// AddressResult가 아니라 문자열로 들고 있는 이유: 재시도할 때 저장된 값을
  /// 되살려야 하는데, 저장돼 있는 것은 주소 문자열뿐이라 좌표까지 갖춘
  /// AddressResult로 되돌릴 수 없다.
  ///
  /// ⚠️ 다른 칸과 **같은 방식**(TextEditingController + TextFormField)으로
  ///    든다. 예전에는 화면 표시용 String과 Form 밖의 오류 플래그를 따로
  ///    들었는데, 그러면 이 칸만 `_formKey.currentState.validate()`가 보지
  ///    못한다 — 표시값과 검증값이 두 벌이 되어 "화면에는 주소가 멀쩡히
  ///    보이는데 제출은 조용히 멈추는" 상태가 만들어진다. 표시·검증·전송이
  ///    모두 이 컨트롤러 하나를 읽는다.
  final _bizBaseAddressCtrl = TextEditingController();
  final _bizDetailAddressCtrl = TextEditingController();

  /// 기본주소 칸만 따로 다시 검사하기 위한 손잡이 — 주소를 고른 직후 폼
  /// 전체를 돌리면 아직 손대지도 않은 칸까지 빨갛게 만든다.
  final _bizBaseAddressFieldKey = GlobalKey<FormFieldState<String>>();

  /// 막혔을 때 **첫 번째로 잘못된 칸**으로 데려가기 위한 포커스들.
  final _bizNoFocus = FocusNode();
  final _repNameFocus = FocusNode();
  final _openDateFocus = FocusNode();
  final _bizNameFocus = FocusNode();
  final _bizBaseAddressFocus = FocusNode();
  final _bizDetailAddressFocus = FocusNode();

  bool _submitting = false;
  bool _loaded = false;
  BusinessVerification _current = BusinessVerification.none;

  /// **사업자 정보 변경 모드.**
  ///
  /// 인증을 마친 계정은 평소에 입력 폼을 보여주지 않는다(이미 끝난 일을
  /// 다시 묻는 화면이 된다). 대신 '사업자 정보 변경'을 누르면 이 값이 켜지고,
  /// 같은 폼이 **저장된 값으로 채워진 채** 열린다.
  ///
  /// 폼을 따로 만들지 않는 이유: 최초 인증과 변경은 입력 항목도 검증 규칙도
  /// 완전히 같다. 두 벌로 나누면 한쪽만 고쳐 규칙이 어긋난다.
  bool _changing = false;

  /// 지금 폼을 보여줄 상황인가 — 미인증(재시도 포함)이거나 변경 모드일 때.
  bool get _showsForm => _current.canRetry || _changing;

  /// 변경 모드에서 사업자등록번호를 **실제로 바꿨는가**.
  ///
  /// 바꿨다면 "새 사업자정보로 다시 인증해야 한다"를 입력 중에 미리 알려준다 —
  /// 인증 버튼을 누른 뒤에야 알게 되면 늦다.
  bool get _businessNumberEdited {
    if (!_changing) return false;
    final typed = _bizNoCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final saved = _current.businessNumber.replaceAll(RegExp(r'[^0-9]'), '');
    return typed.isNotEmpty && saved.isNotEmpty && typed != saved;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  /// 대표자 승인은 **다른 사람의 다른 기기**에서 끝난다 — 이 화면은 그 사실을
  /// 알 방법이 없어서, 승인을 받고 앱으로 돌아와도 계속 '대표자 확인이
  /// 필요합니다'가 떠 있었다(사용자는 승인이 안 된 줄 안다). 앱이 다시
  /// 앞으로 올 때마다 서버 값을 다시 읽어, 돌아오면 바로 완료로 바뀌게 한다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bizNoCtrl.dispose();
    _repNameCtrl.dispose();
    _openDateCtrl.dispose();
    _bizNameCtrl.dispose();
    _bizBaseAddressCtrl.dispose();
    _bizDetailAddressCtrl.dispose();
    _bizNoFocus.dispose();
    _repNameFocus.dispose();
    _openDateFocus.dispose();
    _bizNameFocus.dispose();
    _bizBaseAddressFocus.dispose();
    _bizDetailAddressFocus.dispose();
    super.dispose();
  }

  // ── 입력 검증 ──────────────────────────────────────────────────────────
  // 규칙은 여기 적힌 함수 하나뿐이다. TextFormField의 validator와, 막혔을 때
  // "어느 칸이 막았는지" 고르는 [_firstInvalidField]가 **같은 함수**를 쓴다 —
  // 두 벌로 두면 한쪽만 고쳐서 "폼은 통과인데 제출은 막히는" 상태가 된다.

  String? _validateBizNo(String? v) {
    final d = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length != 10) return '사업자등록번호 10자리를 입력해주세요';
    return null;
  }

  String? _validateRepName(String? v) =>
      (v ?? '').trim().isEmpty ? '대표자명을 입력해주세요' : null;

  String? _validateOpenDate(String? v) {
    final d = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length != 8) return '개업일자를 YYYYMMDD 형식으로 입력해주세요';
    final m = int.tryParse(d.substring(4, 6)) ?? 0;
    final day = int.tryParse(d.substring(6, 8)) ?? 0;
    if (m < 1 || m > 12 || day < 1 || day > 31) return '개업일자를 다시 확인해주세요';
    return null;
  }

  String? _validateBizName(String? v) =>
      (v ?? '').trim().isEmpty ? '상호명을 입력해주세요' : null;

  String? _validateBaseAddress(String? v) =>
      (v ?? '').trim().isEmpty ? '주소를 검색해주세요' : null;

  String? _validateDetailAddress(String? v) =>
      (v ?? '').trim().isEmpty ? '상세주소를 입력해주세요' : null;

  /// 입력 칸을 **화면에 놓인 순서 그대로** 든다 — 막혔을 때 데려갈 곳을 이
  /// 순서로 고른다. 순서가 화면과 다르면 엉뚱한 칸으로 포커스가 튄다.
  List<({FocusNode focus, String? Function() check})> get _requiredFields => [
    (focus: _bizNoFocus, check: () => _validateBizNo(_bizNoCtrl.text)),
    (focus: _repNameFocus, check: () => _validateRepName(_repNameCtrl.text)),
    (focus: _openDateFocus, check: () => _validateOpenDate(_openDateCtrl.text)),
    (focus: _bizNameFocus, check: () => _validateBizName(_bizNameCtrl.text)),
    (
      focus: _bizBaseAddressFocus,
      check: () => _validateBaseAddress(_bizBaseAddressCtrl.text),
    ),
    (
      focus: _bizDetailAddressFocus,
      check: () => _validateDetailAddress(_bizDetailAddressCtrl.text),
    ),
  ];

  /// 제출을 막은 **첫 번째** 칸. 없으면 null(= 보낼 수 있다).
  ///
  /// `FormState.validate()`의 결과를 그대로 믿지 않는 이유: Form은 그 순간
  /// 화면에 붙어 있는 칸만 검사한다. 값은 컨트롤러가 정본이므로 여기서 직접
  /// 읽는다 — 그래야 "무엇이 막았는지"까지 알 수 있다.
  ({FocusNode focus, String? Function() check})? _firstInvalidField() {
    for (final f in _requiredFields) {
      if (f.check() != null) return f;
    }
    return null;
  }

  /// 막은 칸을 화면 안으로 끌어와 포커스를 준다 — 스크롤 밖에서 조용히
  /// 빨개져 있으면 사용자에게는 "아무 일도 안 일어난 것"과 같다.
  Future<void> _revealAndFocus(FocusNode node) async {
    final ctx = node.context;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.2,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
    if (mounted) node.requestFocus();
  }

  /// 저장된 값으로 폼을 채운 뒤 변경 모드로 들어간다.
  ///
  /// 사용자가 바꾸고 싶은 것은 보통 한두 항목이라, 다섯 칸을 처음부터 다시
  /// 치게 하면 그 자체가 오입력 원인이 된다.
  void _startChange() {
    setState(() {
      _changing = true;
      _bizNoCtrl.text = _current.businessNumber;
      _repNameCtrl.text = _current.representativeName;
      _openDateCtrl.text = _current.openingDate;
      _bizNameCtrl.text = _current.businessName;
      _bizBaseAddressCtrl.text = _baseAddressOf(_current);
      _bizDetailAddressCtrl.text = _current.businessDetailAddress;
    });
  }

  /// 저장된 문서에서 읽어낸 **기본주소**.
  ///
  /// 주소를 기본/상세로 나눠 저장하기 전의 문서에는 businessAddress 한 덩어리만
  /// 있다 — 그 경우 통째로 기본주소 자리에 되살린다(사용자가 다시 검색하면
  /// 교체된다). 되살리는 자리가 두 곳(재진입·변경 모드)이라 함수로 묶는다.
  String _baseAddressOf(BusinessVerification v) =>
      v.businessBaseAddress.isNotEmpty
      ? v.businessBaseAddress
      : v.businessAddress;

  /// 변경을 그만두고 원래 화면(인증 완료 상태 카드)으로 돌아간다.
  /// 서버에는 아무것도 보내지 않았으므로 되돌릴 것도 없다.
  void _cancelChange() {
    setState(() => _changing = false);
  }

  Future<void> _load() async {
    final v = await BusinessVerificationService.fetch();
    if (!mounted) return;
    setState(() {
      _current = v;
      _loaded = true;
      // 재시도할 때 처음부터 다시 치지 않도록 지난 입력을 되살린다.
      if (_bizNoCtrl.text.isEmpty) _bizNoCtrl.text = v.businessNumber;
      if (_repNameCtrl.text.isEmpty) _repNameCtrl.text = v.representativeName;
      if (_openDateCtrl.text.isEmpty) _openDateCtrl.text = v.openingDate;
      if (_bizNameCtrl.text.isEmpty) _bizNameCtrl.text = v.businessName;
      if (_bizBaseAddressCtrl.text.isEmpty) {
        _bizBaseAddressCtrl.text = _baseAddressOf(v);
      }
      if (_bizDetailAddressCtrl.text.isEmpty) {
        _bizDetailAddressCtrl.text = v.businessDetailAddress;
      }
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    // 먼저 폼 전체를 한 번에 검사한다 — 걸린 칸을 **모두** 빨갛게 만들어야
    // 하나 고치고 다시 눌렀을 때 나머지가 새로 나타나지 않는다.
    _formKey.currentState?.validate();

    // 그리고 컨트롤러 값으로 직접 한 번 더 본다. validate()의 결과만 믿으면
    // 안 되는 이유가 둘이다.
    //   · currentState가 null이면 `?? false`로 **말없이** 막혔다(무엇이
    //     막았는지 사용자도 로그도 알 수 없다).
    //   · Form은 그 순간 붙어 있는 칸만 검사한다.
    // 여기서 고른 칸이 곧 "왜 안 보내지는지"의 답이다.
    final blocked = _firstInvalidField();
    if (blocked != null) {
      await _revealAndFocus(blocked.focus);
      if (!mounted) return;
      _snack('필수 정보를 확인해주세요.');
      return;
    }

    final base = _bizBaseAddressCtrl.text.trim();

    // 저장·전송용 전체 주소 — 옛 데이터와 같은 자리(businessAddress)에 들어가는
    // 값이라 형태도 그대로 "한 줄짜리 주소 문자열"로 맞춘다.
    final detail = _bizDetailAddressCtrl.text.trim();
    final fullAddress = [base, detail].where((s) => s.isNotEmpty).join(' ');

    final wasChanging = _changing;
    setState(() => _submitting = true);
    try {
      final result = await BusinessVerificationService.verify(
        businessNumber: _bizNoCtrl.text,
        representativeName: _repNameCtrl.text.trim(),
        openingDate: _openDateCtrl.text,
        businessName: _bizNameCtrl.text.trim(),
        businessAddress: fullAddress,
        businessBaseAddress: base,
        businessDetailAddress: detail,
      );
      if (!mounted) return;
      // 성공했을 때만 변경 모드를 닫는다 — 실패했는데 폼이 닫히면 방금 친
      // 값이 사라져 처음부터 다시 입력해야 한다.
      if (result.isVerified) _changing = false;
      await _load();
      if (!mounted) return;
      _snack(
        result.isVerified
            ? (wasChanging ? '새 사업자정보로 인증이 완료됐어요.' : '사업자 인증이 완료됐어요.')
            // 기존 권한이 살아 있는 경우에는 그 사실을 **먼저** 말한다 —
            // 실패 문구만 보면 인증이 풀린 줄 알고 놀란다.
            : result.keptExistingVerification
            ? '${result.guidance} 기존 인증정보는 그대로 유지됐어요.'
            // 사업자는 확인됐는데 권한만 없는 경우도 여기로 온다 —
            // 문구는 result.guidance가 '대표자 확인'으로 갈라 준다.
            : result.guidance,
      );
      // 사업자 인증이 끝났다고 결제 준비가 끝난 것은 아니다 — 무통장입금을
      // 받으려면 수취계좌 인증이 따로 필요하다. 그 자리로 바로 이어 준다.
      //
      // 사업자 인증 상태와는 **완전히 별개**다. 여기서 '나중에 할게요'를
      // 눌러도 위에서 이미 끝난 인증은 그대로고, 현장결제도 그대로 쓸 수
      // 있다. 이미 수취계좌를 인증한 호스트에게는 안내가 뜨지 않는다.
      if (result.isVerified && mounted) {
        await promptBankTransferSetupAfterBusinessVerification(context);
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      // 서버가 한국어 안내 문구로 던지므로 그대로 보여준다.
      _snack(e.message ?? '인증에 실패했어요. 잠시 후 다시 시도해주세요.');
    } catch (_) {
      if (!mounted) return;
      _snack('인증에 실패했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 기존 주소검색 화면을 열어 기본주소를 받아온다.
  ///
  /// 도로명이 있으면 도로명, 없으면 지번을 쓴다([AddressResult.displayAddress]와
  /// 같은 기준) — 검색 결과에 없는 값을 사용자가 손으로 고칠 수는 없다.
  Future<void> _pickBusinessAddress() async {
    final picked = await Navigator.push<AddressResult>(
      context,
      webFramedRoute((_) => const AddressSearchScreen()),
    );
    if (picked == null || !mounted) return;
    setState(() => _bizBaseAddressCtrl.text = picked.displayAddress);
    // 이 칸만 다시 검사해 오류 문구를 지운다 — 폼 전체를 돌리면 아직 손대지도
    // 않은 칸까지 빨갛게 만든다.
    _bizBaseAddressFieldKey.currentState?.validate();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('사업자 인증'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              // ListView가 아니라 **한 번에 다 그리는** 스크롤이다. ListView는
              // 화면 밖 칸을 버리고, 버려진 TextFormField는 Form에서 빠져
              // `validate()`가 그 칸을 건너뛴다 — 스크롤 위치에 따라 검증
              // 결과가 달라지고, 막은 칸으로 데려갈 수도 없다.
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusCard(verification: _current),
                    // 대표자 승인 — 사업자는 확인됐는데 권한만 없는 상태에서만 뜬다.
                    // 이 칸은 링크를 만들어 전달하는 것까지만 하고, 실제 승인은
                    // 대표자가 NICE 본인확인을 마친 뒤 서버가 정한다.
                    if (_current.needsOwnerApproval) ...[
                      const SizedBox(height: 12),
                      OwnerApprovalPanel(
                        verification: _current,
                        onRefresh: _load,
                      ),
                    ],
                    // 권한 축이 생기기 전에 인증을 마친 계정 — 상태 카드만으로는
                    // "왜 완료인데 아래에 폼이 또 있지?"가 된다. 무엇을 하면
                    // 끝나는지 폼 바로 위에서 말해 준다.
                    if (_current.needsReverification) ...[
                      const SizedBox(height: 12),
                      _noticeCard(
                        icon: Icons.verified_user_outlined,
                        title: '한 번만 다시 확인하면 끝나요',
                        body:
                            '아래 정보가 사업자등록증과 같은지 확인하고 "다시 확인하기"를 '
                            '눌러주세요. 국세청 확인은 이미 통과한 정보라 그대로 두고 '
                            '누르셔도 됩니다.',
                        bg: const Color(0xFFFFFBEB),
                        fg: const Color(0xFFB45309),
                      ),
                    ],
                    // 인증을 마친 계정의 진입점 — 사업자등록번호는 법인 전환·
                    // 업종 변경·폐업 후 재개업으로 바뀔 수 있어서 "인증 완료"가
                    // 마지막 상태가 아니다.
                    if (_current.canChange && !_changing) ...[
                      const SizedBox(height: 12),
                      _ChangeEntry(
                        pendingChange: _current.pendingChange,
                        onPressed: _startChange,
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_changing) ...[
                      _noticeCard(
                        icon: Icons.autorenew_rounded,
                        title: '사업자 정보가 변경되었나요?',
                        body:
                            '새 사업자정보를 입력하고 다시 인증할 수 있어요. '
                            '새 인증이 완료되기 전까지 기존 인증정보는 유지됩니다.',
                        bg: const Color(0xFFEFF6FF),
                        fg: const Color(0xFF1D4ED8),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_showsForm) ...[
                      _card(
                        title: '사업자등록증 정보',
                        subtitle: '국세청 확인에 쓰이는 항목이에요. 사업자등록증에 적힌 그대로 입력해주세요.',
                        children: [
                          _label('사업자등록번호'),
                          TextFormField(
                            controller: _bizNoCtrl,
                            focusNode: _bizNoFocus,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            decoration: _dec('숫자 10자리 (예: 1234567890)'),
                            // 번호를 고치는 즉시 아래 안내가 뜨고 사라지도록
                            // 다시 그린다(입력 중에 알아야 의미가 있다).
                            onChanged: (_) => setState(() {}),
                            validator: _validateBizNo,
                          ),
                          if (_businessNumberEdited) ...[
                            const SizedBox(height: 10),
                            _inlineNotice(
                              '사업자등록번호가 변경되면 새 사업자정보로 다시 인증해야 합니다.',
                            ),
                          ],
                          const SizedBox(height: 16),
                          _label('대표자명'),
                          TextFormField(
                            controller: _repNameCtrl,
                            focusNode: _repNameFocus,
                            decoration: _dec('예: 홍길동'),
                            validator: _validateRepName,
                          ),
                          const SizedBox(height: 16),
                          _label('개업일자'),
                          TextFormField(
                            controller: _openDateCtrl,
                            focusNode: _openDateFocus,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(8),
                            ],
                            decoration: _dec('YYYYMMDD (예: 20200105)'),
                            validator: _validateOpenDate,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _card(
                        title: '사업자 정보',
                        subtitle:
                            '앱에 저장되는 사업자 정보예요. 국세청 통과 여부를 가르지는 않지만 '
                            '두 항목 모두 입력해야 확인을 진행할 수 있어요. 본점 주소와 실제 '
                            '파티·플레이스를 여는 주소는 달라도 괜찮아요 — 개최 주소는 등록 '
                            '화면에서 따로 입력해요.',
                        children: [
                          _label('상호명'),
                          TextFormField(
                            controller: _bizNameCtrl,
                            focusNode: _bizNameFocus,
                            decoration: _dec('예: 파티츄 라운지'),
                            validator: _validateBizName,
                          ),
                          const SizedBox(height: 16),
                          _label('사업장 주소'),
                          // 플레이스·파티 등록과 **같은 주소검색 화면**을 그대로
                          // 쓴다(AddressSearchScreen) — 검색 방식·결과 표기가
                          // 앱 전체에서 하나여야 한다.
                          //
                          // 눌러서 여는 칸이지만 **다른 칸과 같은 TextFormField**다.
                          // 직접 타이핑만 막고(readOnly), 값과 오류 표시는 Form이
                          // 다른 칸과 똑같이 다룬다 — 이 칸만 Form 밖에 두면
                          // validate()가 보지 못해 표시값과 검증값이 갈린다.
                          TextFormField(
                            key: _bizBaseAddressFieldKey,
                            controller: _bizBaseAddressCtrl,
                            focusNode: _bizBaseAddressFocus,
                            readOnly: true,
                            showCursor: false,
                            enableInteractiveSelection: false,
                            onTap: _pickBusinessAddress,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                            decoration: _dec('주소를 검색해주세요').copyWith(
                              prefixIcon: const Icon(
                                Icons.search,
                                size: 18,
                                color: Color(0xFFFF6FA0),
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 20,
                              ),
                              suffixText: _bizBaseAddressCtrl.text.isEmpty
                                  ? null
                                  : '변경',
                              suffixStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFFF6FA0),
                              ),
                            ),
                            validator: _validateBaseAddress,
                          ),
                          const SizedBox(height: 16),
                          _label('상세주소'),
                          TextFormField(
                            controller: _bizDetailAddressCtrl,
                            focusNode: _bizDetailAddressFocus,
                            decoration: _dec('예: 101동 1203호, 3층 파티츄'),
                            validator: _validateDetailAddress,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _changing
                                      ? '새 정보로 다시 인증하기'
                                      : _current.status ==
                                            BusinessVerificationStatus
                                                .unverified
                                      ? '국세청으로 확인하기'
                                      : '다시 확인하기',
                                ),
                        ),
                      ),
                      if (_changing) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 48,
                          child: TextButton(
                            onPressed: _submitting ? null : _cancelChange,
                            child: const Text('변경 취소'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Text(
                        '입력하신 정보는 국세청 확인에만 쓰이고, 파티·플레이스 같은 공개 게시물에는 '
                        '저장되지 않아요. 다른 이용자에게는 "사업자 인증 완료" 여부만 보여요.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: Colors.black45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  // ── 작은 조각들 ────────────────────────────────────────────────────────
  /// 항목 라벨. 이 화면의 입력은 **다섯 개 모두 필수**라 별표를 늘 붙인다 —
  /// 어떤 것이 선택인지 세어보게 만들 이유가 없다.
  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text.rich(
      TextSpan(
        text: t,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        children: const [
          TextSpan(
            text: ' *',
            style: TextStyle(
              color: Color(0xFFE5484D),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );

  /// 카드 한 장짜리 안내(변경 모드 상단 배너).
  Widget _noticeCard({
    required IconData icon,
    required String title,
    required String body,
    required Color bg,
    required Color fg,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: fg),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: fg,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(fontSize: 13, height: 1.5, color: fg),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  /// 입력칸 바로 아래 붙는 한 줄 경고 — 사업자등록번호를 고쳤을 때만 뜬다.
  Widget _inlineNotice(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFFDE68A)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: Color(0xFFB45309),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Color(0xFFB45309),
            ),
          ),
        ),
      ],
    ),
  );

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.black26, fontSize: 14),
    filled: true,
    fillColor: const Color(0xFFF9FAFB),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: PartyChuColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: PartyChuColors.border),
    ),
    // 막힌 칸은 테두리까지 빨개야 한다 — 아래 작은 글씨 한 줄만으로는
    // "왜 안 보내지는지"가 눈에 들어오지 않는다.
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
    ),
  );

  Widget _card({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: PartyChuColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Colors.black45,
            ),
          ),
        ],
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );
}

/// 인증을 마친 계정에만 보이는 **사업자 정보 변경** 진입점.
///
/// 실패한 채로 남아 있는 변경 시도가 있으면 그 사실도 함께 알린다 — 이때
/// 중요한 것은 "기존 인증은 그대로다"라서, 실패 문구보다 그쪽을 먼저 읽히게
/// 배치한다.
class _ChangeEntry extends StatelessWidget {
  const _ChangeEntry({required this.pendingChange, required this.onPressed});

  final BusinessChangeAttempt? pendingChange;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final pending = pendingChange;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PartyChuColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '사업자 정보가 바뀌었나요?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            '사업자등록번호·대표자명·개업일자·상호명·사업장 주소를 새로 입력해 '
            '다시 인증할 수 있어요. 새 인증이 완료되기 전까지 기존 인증정보는 유지됩니다.',
            style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black45),
          ),
          if (pending != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${pending.formattedBusinessNumber}(으)로 바꾸려던 인증이 '
                    '아직 완료되지 않았어요.',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                      color: Color(0xFFB45309),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pending.guidance,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('사업자 정보 변경'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: const BorderSide(color: PartyChuColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 현재 인증 상태 — 인증 완료 / 심사 필요 / 인증 실패 / 휴·폐업 확인 필요를
/// 색과 문구로 분명히 구분해 보여준다.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.verification});

  final BusinessVerification verification;

  ({Color bg, Color fg, IconData icon}) get _style {
    // 권한 축을 **먼저** 본다 — 권한이 없는 계정도 status는 'verified'라서
    // 그냥 두면 초록색 '인증 완료' 카드로 그려진다. 그 초록 카드가 이번
    // "완료라는데 등록은 막힌다"의 시작점이었다.
    //
    // 실패(빨강)도 아니다: 사업자 정보 자체는 국세청에서 확인됐고 남은 것은
    // 권한 확인 하나뿐이라 '기다리는 중'의 색을 쓴다. 대표자 승인이 필요한
    // 경우와 본인이 다시 확인하면 되는 경우를 색으로 가르지 않는 이유는,
    // 무엇을 해야 하는지는 headline·guidance가 이미 갈라 말하기 때문이다.
    if (verification.verifiedWithoutAuthorization) {
      return (
        bg: const Color(0xFFFFFBEB),
        fg: const Color(0xFFB45309),
        // 대표자 승인 대기는 사업자 확인이 **끝난** 상태라 체크 표시를 쓴다
        // (제목도 "사업자 정보는 확인됐어요"다). 경고 아이콘을 쓰면 색과
        // 겹쳐 실패로 읽힌다.
        icon: verification.needsOwnerApproval
            ? Icons.check_circle_outline
            : Icons.badge_outlined,
      );
    }
    switch (verification.status) {
      case BusinessVerificationStatus.verified:
        return (
          bg: const Color(0xFFECFDF5),
          fg: const Color(0xFF047857),
          icon: Icons.verified_outlined,
        );
      case BusinessVerificationStatus.pending:
        return (
          bg: const Color(0xFFFFFBEB),
          fg: const Color(0xFFB45309),
          icon: Icons.hourglass_empty,
        );
      case BusinessVerificationStatus.failed:
        return (
          bg: const Color(0xFFFEF2F2),
          fg: const Color(0xFFB91C1C),
          icon: Icons.error_outline,
        );
      case BusinessVerificationStatus.suspended:
        return (
          bg: const Color(0xFFFEF2F2),
          fg: const Color(0xFFB91C1C),
          icon: Icons.pause_circle_outline,
        );
      case BusinessVerificationStatus.unverified:
        return (
          bg: const Color(0xFFF3F4F6),
          fg: const Color(0xFF4B5563),
          icon: Icons.badge_outlined,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    final v = verification;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(s.icon, size: 20, color: s.fg),
              const SizedBox(width: 8),
              Text(
                v.headline,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: s.fg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            v.guidance,
            style: TextStyle(fontSize: 13, height: 1.5, color: s.fg),
          ),
          if (v.businessNumber.isNotEmpty) ...[
            const SizedBox(height: 12),
            _row('사업자등록번호', v.formattedBusinessNumber, s.fg),
            if (v.representativeName.isNotEmpty)
              _row('대표자명', v.representativeName, s.fg),
            if (v.openingDate.isNotEmpty)
              _row('개업일자', v.formattedOpeningDate, s.fg),
            // 상호명·사업장 주소도 함께 보여준다 — 이 둘만 고치는 변경이
            // 흔한데, 저장된 값이 화면에 없으면 바뀌었는지 확인할 길이 없다.
            if (v.businessName.isNotEmpty) _row('상호명', v.businessName, s.fg),
            if (v.businessAddress.isNotEmpty)
              _row('사업장 주소', v.businessAddress, s.fg),
            if (v.ntsStatusLabel.isNotEmpty)
              _row('국세청 상태', v.ntsStatusLabel, s.fg),
            if (v.taxType.isNotEmpty) _row('과세유형', v.taxType, s.fg),
          ],
        ],
      ),
    );
  }

  Widget _row(String k, String value, Color fg) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            k,
            style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.75)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ],
    ),
  );
}
