import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:party_app/models/feedback_request.dart';
import 'package:party_app/services/feedback_service.dart';
import 'package:party_app/utils/local_media.dart';

/// 고객센터 문의 작성 화면.
/// 파티/사용자 신고, 환불 요청, 결제 분쟁 등과는 무관한 전용 화면 —
/// feedbackRequests 컬렉션에만 저장된다.
class FeedbackComposeScreen extends StatefulWidget {
  const FeedbackComposeScreen({super.key});

  @override
  State<FeedbackComposeScreen> createState() => _FeedbackComposeScreenState();
}

class _FeedbackComposeScreenState extends State<FeedbackComposeScreen> {
  /// 첨부 상한 — 정본은 [FeedbackService.maxImages] 하나뿐이다.
  static const int _maxImages = FeedbackService.maxImages;

  String _type = FeedbackType.inquiry;
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final List<XFile> _images = [];
  final _picker = ImagePicker();

  bool _isSubmitting = false;
  bool _showTitleError = false;
  bool _showContentError = false;
  bool _showEmailError = false;
  bool _showPhoneError = false;

  /// 스크린샷으로 남길 수 없는 오류(알림 미수신 등)라고 표시했는가.
  bool _screenshotUnavailable = false;

  /// 위를 체크했을 때 고른 사유. '기타'면 [_reasonOtherCtrl]을 함께 쓴다.
  String? _reasonPreset;
  final _reasonOtherCtrl = TextEditingController();

  /// 버그 신고에만 스크린샷을 요구한다 — 개선 제안·이용 문의·기타는 화면
  /// 오류와 무관해서, 무조건 요구하면 사진이 없다는 이유로 의견 자체를 못 보낸다.
  bool get _needsScreenshot => _type == FeedbackType.bug;

  /// 예외를 켰을 때 실제로 저장될 사유 문구. 조건을 못 채우면 null.
  String? get _resolvedReason {
    if (_reasonPreset == null) return null;
    if (_reasonPreset != FeedbackScreenshotBlocker.other) return _reasonPreset;
    final typed = _reasonOtherCtrl.text.trim();
    return typed.isEmpty ? null : typed;
  }

  /// 사진이 필요한데 없는 상태(예외를 켜지 않은 경우).
  bool get _screenshotMissing =>
      _needsScreenshot && !_screenshotUnavailable && _images.isEmpty;

  /// 예외를 켰는데 사유가 비어 있는 상태.
  bool get _reasonMissing =>
      _needsScreenshot && _screenshotUnavailable && _resolvedReason == null;

  /// 답변받을 이메일이 아직 형식을 못 갖췄는가. 판정은 모델이 한다
  /// ([FeedbackContact]) — 화면과 서비스가 같은 규격을 쓰기 위해서다.
  bool get _emailInvalid => !FeedbackContact.isValidEmail(_emailCtrl.text);

  /// 전화번호는 선택 입력이라 **비어 있으면 문제가 아니다.** 적었는데 형식이
  /// 어긋난 경우만 막는다.
  bool get _phoneInvalid =>
      !FeedbackContact.isValidPhoneOrEmpty(_phoneCtrl.text);

  /// 제출을 막아야 하는가.
  bool get _blocked =>
      _screenshotMissing || _reasonMissing || _emailInvalid || _phoneInvalid;

  @override
  void initState() {
    super.initState();
    // 답변받을 주소는 대개 로그인에 쓴 이메일이다 — 미리 채워 두되 **저장되는
    // 값은 어디까지나 사용자가 확인·수정한 뒤 제출한 것**이다(계정 이메일을
    // 문의 문서에 자동 복제하지 않는다).
    final signedInEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    if (signedInEmail.isNotEmpty) _emailCtrl.text = signedInEmail;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _reasonOtherCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remain = _maxImages - _images.length;
    if (remain <= 0) return;
    final picked = await _picker.pickMultiImage(
      limit: remain,
      imageQuality: 85,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (_images.length < _maxImages) _images.add(f);
      }
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return; // 연속 클릭 방지

    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final titleEmpty = title.isEmpty;
    final contentEmpty = content.isEmpty;
    final emailBad = _emailInvalid;
    final phoneBad = _phoneInvalid;
    setState(() {
      _showTitleError = titleEmpty;
      _showContentError = contentEmpty;
      _showEmailError = emailBad;
      _showPhoneError = phoneBad;
    });
    if (titleEmpty || contentEmpty) return;

    // 제출 버튼이 이미 잠겨 있어 정상 흐름에서는 여기 걸리지 않지만, 유형을
    // 버그로 바꾼 직후처럼 상태가 어긋난 순간을 대비한 안전망이다.
    if (_blocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            emailBad
                ? '답변받을 이메일 주소를 정확히 입력해주세요.'
                : phoneBad
                ? '연락처 형식을 확인해주세요. 예: 010-1234-5678'
                : _screenshotMissing
                ? '오류가 발생한 화면의 스크린샷을 1장 이상 첨부해주세요.'
                : '스크린샷을 첨부할 수 없는 이유를 선택해주세요.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await FeedbackService.submit(
        type: _type,
        title: title,
        content: content,
        images: _images,
        contactEmail: email,
        contactPhone: phone,
        screenshotUnavailable: _needsScreenshot && _screenshotUnavailable,
        screenshotUnavailableReason: _needsScreenshot && _screenshotUnavailable
            ? _resolvedReason
            : null,
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFFFF6FA0)),
              SizedBox(width: 8),
              Text(
                '문의 등록 완료',
                style: TextStyle(
                  fontFamily: 'SeoulHangang',
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                    Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                    Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                    Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                  ],
                ),
              ),
            ],
          ),
          content: const Text(
            '문의가 등록되었어요. 확인 후 입력하신 연락처로 답변드릴게요.',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6FA0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pop(context); // 작성 화면 닫기
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('제출에 실패했습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  InputDecoration _deco(String hint, {bool error = false}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: error ? Colors.redAccent : const Color(0xFFE8EBF2),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: error ? Colors.redAccent : const Color(0xFFE8EBF2),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: error ? Colors.redAccent : const Color(0xFFFF6FA0),
      ),
    ),
  );

  /// "스크린샷을 첨부할 수 없는 오류예요" 체크 한 줄.
  Widget _screenshotUnavailableToggle() => InkWell(
    onTap: () => setState(() {
      _screenshotUnavailable = !_screenshotUnavailable;
      // 껐다 켤 때 이전 사유가 남아 있으면 고르지도 않은 값이 저장된다.
      if (!_screenshotUnavailable) {
        _reasonPreset = null;
        _reasonOtherCtrl.clear();
      }
    }),
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: _screenshotUnavailable,
              activeColor: const Color(0xFFFF6FA0),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => setState(() {
                _screenshotUnavailable = v ?? false;
                if (!_screenshotUnavailable) {
                  _reasonPreset = null;
                  _reasonOtherCtrl.clear();
                }
              }),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '스크린샷을 첨부할 수 없는 오류예요',
              style: TextStyle(fontSize: 13.5, color: Colors.black87),
            ),
          ),
        ],
      ),
    ),
  );

  /// 예외를 켰을 때만 보이는 사유 선택 — 사유는 필수다.
  Widget _reasonPicker() => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '첨부할 수 없는 이유 (필수)',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: FeedbackScreenshotBlocker.presets.map((r) {
            final sel = _reasonPreset == r;
            return GestureDetector(
              onTap: () => setState(() => _reasonPreset = r),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFFFF6FA0) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: sel
                        ? const Color(0xFFFF6FA0)
                        : const Color(0xFFE8EBF2),
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  r,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : Colors.black54,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (_reasonPreset == FeedbackScreenshotBlocker.other) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _reasonOtherCtrl,
            maxLength: 60,
            onChanged: (_) => setState(() {}),
            decoration: _deco('어떤 상황인지 간단히 적어주세요').copyWith(counterText: ''),
          ),
        ],
        if (_reasonMissing)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 15, color: Colors.redAccent),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '스크린샷을 첨부할 수 없는 이유를 선택해주세요.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.redAccent,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _label(String text, {bool required = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(
              color: Color(0xFFFF6FA0),
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    ),
  );

  /// 💳 결제·환불 문의 안내 — 유형을 고르기 **전에** 보여준다.
  ///
  /// 파티츄 고객센터는 결제·환불을 직접 처리하지 않는다(처리 주체는 그 거래의
  /// 호스트다). 그래서 선택지에서 뺀 것으로 끝내지 않고, 갈 곳을 함께 알려
  /// 준다 — 유형만 사라지면 사용자는 '기타 문의'로 같은 글을 쓰게 된다.
  Widget _paymentNotice() => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0F5),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFFFD3E2)),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '💳 결제·환불 문의 안내',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFFD1497B),
          ),
        ),
        SizedBox(height: 6),
        Text(
          '결제 및 환불은 각 호스트가 직접 처리해요. '
          '해당 파티·플레이스·장소대여 상세의 문의하기를 통해 호스트에게 '
          '문의해주세요.',
          style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.6),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text(
          '고객센터 문의',
          style: TextStyle(
            fontFamily: 'SeoulHangang',
            fontSize: 17,
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Text(
              '이용 중 궁금한 점이나 불편한 점을 남겨주세요. '
              '확인 후 입력하신 이메일 또는 연락처로 답변드릴게요.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.black54,
                height: 1.6,
              ),
            ),
          ),
          _paymentNotice(),
          _label('문의 유형'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            // 읽기용 전체 목록([FeedbackType.all])이 아니라 **지금 접수하는
            // 유형**만 그린다 — 결제/환불은 호스트가 처리하므로 여기서 받지
            // 않는다(위 안내 박스). 옛 문서의 라벨은 all이 그대로 들고 있다.
            children: FeedbackType.composable.map((t) {
              final sel = _type == t;
              return GestureDetector(
                onTap: () => setState(() => _type = t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFFFF6FA0) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel
                          ? const Color(0xFFFF6FA0)
                          : const Color(0xFFE8EBF2),
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    FeedbackType.label(t),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : Colors.black54,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 22),

          // ── 답변받을 연락처 ─────────────────────────────────────────
          // 이메일은 필수, 전화번호는 선택이다. 답변이 나갈 통로라 제목·내용
          // 위에 둔다 — 다 쓰고 나서야 "연락처가 필요하다"를 알게 되면 이미
          // 긴 글을 쓴 뒤다.
          _label('연락받을 이메일 주소', required: true),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onChanged: (_) => setState(() {
              if (_showEmailError && !_emailInvalid) _showEmailError = false;
            }),
            decoration: _deco(
              '예: hello@example.com',
              error: _showEmailError,
            ),
          ),
          if (_showEmailError)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '답변받을 이메일 주소를 정확히 입력해주세요.',
                style: TextStyle(fontSize: 12.5, color: Colors.redAccent),
              ),
            ),
          const SizedBox(height: 16),

          _label('연락 가능한 연락처 (선택)'),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            // 형식 검증은 [FeedbackContact]가 하고, 여기서는 애초에 숫자와
            // 하이픈 말고는 들어오지 못하게 한다(오타가 줄어든다).
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
              LengthLimitingTextInputFormatter(13),
            ],
            onChanged: (_) => setState(() {
              if (_showPhoneError && !_phoneInvalid) _showPhoneError = false;
            }),
            decoration: _deco('예: 010-1234-5678', error: _showPhoneError),
          ),
          if (_showPhoneError)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '연락처 형식을 확인해주세요. 예: 010-1234-5678',
                style: TextStyle(fontSize: 12.5, color: Colors.redAccent),
              ),
            ),
          const SizedBox(height: 22),

          _label('문의 제목', required: true),
          TextField(
            controller: _titleCtrl,
            maxLength: 60,
            onChanged: (_) {
              if (_showTitleError) setState(() => _showTitleError = false);
            },
            decoration: _deco(
              '제목을 입력해주세요',
              error: _showTitleError,
            ).copyWith(counterText: ''),
          ),
          const SizedBox(height: 16),

          _label('문의 내용', required: true),
          TextField(
            controller: _contentCtrl,
            maxLines: 8,
            onChanged: (_) {
              if (_showContentError) setState(() => _showContentError = false);
            },
            decoration: _deco(
              '문의하실 내용을 자세히 적어주세요.',
              error: _showContentError,
            ),
          ),
          const SizedBox(height: 22),

          // 버그 신고는 스크린샷이 있어야 원인을 짚을 수 있어 필수, 그 외
          // 유형은 화면 오류와 무관하므로 선택이다.
          if (_needsScreenshot) ...[
            // 예외를 켠 뒤에도 "(필수)"라고 적혀 있으면 라벨이 거짓말이 된다.
            _label(
              _screenshotUnavailable
                  ? '📷 오류 화면 스크린샷 (선택)'
                  : '📷 오류 화면 스크린샷 (필수)',
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _screenshotUnavailable
                    ? '캡처가 가능한 화면이 하나라도 있다면 함께 올려주시면 확인이 훨씬 빨라집니다.'
                    : '문제가 발생한 화면을 캡처해서 첨부해주세요. 빠른 확인과 해결에 도움이 됩니다.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
            ),
            // 알림 미수신처럼 화면으로 남길 수 없는 오류를 위한 예외 경로.
            // 눈에 띄되 기본 경로보다 약하게 보이도록 체크박스 한 줄로만 둔다 —
            // 이게 버튼처럼 커지면 그냥 "사진 안 올리기"로 쓰이게 된다.
            _screenshotUnavailableToggle(),
            if (_screenshotUnavailable) _reasonPicker(),
            const SizedBox(height: 12),
          ] else
            _label('이미지 첨부 (선택 · 최대 $_maxImages장)'),
          // ⚠️ Row가 아니라 Wrap이어야 한다 — 상한이 5장이라 썸네일 5개(76px)와
          // 추가 버튼을 한 줄에 놓으면 약 500px로, 일반적인 폰 폭(360~390dp)에서
          // 가로 오버플로우가 난다. 줄바꿈이 되는 Wrap으로 둔다.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._images.asMap().entries.map(
                (e) => Padding(
                  // 삭제(✕)가 썸네일 밖으로 6px 튀어나오므로 그만큼 자리를 준다.
                  padding: const EdgeInsets.only(top: 6, right: 6),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LocalMedia.image(
                          e.value,
                          width: 76,
                          height: 76,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: GestureDetector(
                          onTap: () => setState(() => _images.removeAt(e.key)),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_images.length < _maxImages)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 6),
                  child: GestureDetector(
                    onTap: _pickImages,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _screenshotMissing
                              ? Colors.redAccent
                              : const Color(0xFFE8EBF2),
                        ),
                      ),
                      child: Icon(
                        Icons.add_a_photo_outlined,
                        color: _screenshotMissing
                            ? Colors.redAccent
                            : Colors.black38,
                        size: 24,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // 제출 버튼이 잠긴 이유를 그 자리에서 알려준다 — 버튼만 비활성으로
          // 두면 왜 눌리지 않는지 알 수 없다.
          if (_screenshotMissing)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 15, color: Colors.redAccent),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '오류가 발생한 화면의 스크린샷을 1장 이상 첨부해주세요.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.redAccent,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (_images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${_images.length}/$_maxImages장 첨부됨 · 사진을 지우려면 오른쪽 위 ✕를 누르세요',
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              // 스크린샷이 없거나(예외 미체크), 예외를 켰는데 사유가 비면 잠근다.
              onPressed: (_isSubmitting || _blocked) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6FA0),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '문의 등록하기',
                      style: TextStyle(
                        fontSize: 16,
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
