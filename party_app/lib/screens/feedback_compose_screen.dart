import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:party_app/models/feedback_request.dart';
import 'package:party_app/services/feedback_service.dart';

/// 의견 보내기 작성 화면.
/// 파티/사용자 신고, 환불 요청, 결제 분쟁 등과는 무관한 전용 화면 —
/// feedbackRequests 컬렉션에만 저장된다.
class FeedbackComposeScreen extends StatefulWidget {
  const FeedbackComposeScreen({super.key});

  @override
  State<FeedbackComposeScreen> createState() => _FeedbackComposeScreenState();
}

class _FeedbackComposeScreenState extends State<FeedbackComposeScreen> {
  String _type = FeedbackType.improvement;
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _relatedScreenCtrl = TextEditingController();
  final List<XFile> _images = [];
  final _picker = ImagePicker();

  bool _isSubmitting = false;
  bool _showTitleError = false;
  bool _showContentError = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _relatedScreenCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remain = 3 - _images.length;
    if (remain <= 0) return;
    final picked = await _picker.pickMultiImage(limit: remain, imageQuality: 85);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (_images.length < 3) _images.add(f);
      }
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return; // 연속 클릭 방지

    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    final titleEmpty = title.isEmpty;
    final contentEmpty = content.isEmpty;
    setState(() {
      _showTitleError = titleEmpty;
      _showContentError = contentEmpty;
    });
    if (titleEmpty || contentEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      await FeedbackService.submit(
        type: _type,
        title: title,
        content: content,
        images: _images.map((x) => File(x.path)).toList(),
        relatedScreen: _type == FeedbackType.bug
            ? _relatedScreenCtrl.text.trim().isEmpty
                ? null
                : _relatedScreenCtrl.text.trim()
            : null,
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.check_circle, color: Color(0xFFFF6FA0)),
            SizedBox(width: 8),
            Text('접수 완료', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
          ]),
          content: const Text(
            '의견이 접수되었습니다.\n보내주신 의견은 서비스 개선에 참고하겠습니다.',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6FA0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('제출에 실패했습니다: $e')),
        );
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
          borderSide: BorderSide(color: error ? Colors.redAccent : const Color(0xFFE8EBF2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: error ? Colors.redAccent : const Color(0xFFE8EBF2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: error ? Colors.redAccent : const Color(0xFFFF6FA0)),
        ),
      );

  Widget _label(String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          if (required)
            const Text(' *', style: TextStyle(color: Color(0xFFFF6FA0), fontWeight: FontWeight.bold)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text('의견 보내기',
            style: TextStyle(fontFamily: 'SeoulHangang', fontSize: 17, fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          _label('의견 유형'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: FeedbackType.all.map((t) {
              final sel = _type == t;
              return GestureDetector(
                onTap: () => setState(() => _type = t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFFFF6FA0) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Text(FeedbackType.label(t),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : Colors.black54,
                      )),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 22),

          _label('제목', required: true),
          TextField(
            controller: _titleCtrl,
            maxLength: 60,
            onChanged: (_) {
              if (_showTitleError) setState(() => _showTitleError = false);
            },
            decoration: _deco('제목을 입력해주세요', error: _showTitleError).copyWith(counterText: ''),
          ),
          const SizedBox(height: 16),

          _label('내용', required: true),
          TextField(
            controller: _contentCtrl,
            maxLines: 8,
            onChanged: (_) {
              if (_showContentError) setState(() => _showContentError = false);
            },
            decoration: _deco('의견을 자세히 적어주시면 큰 도움이 돼요', error: _showContentError),
          ),
          const SizedBox(height: 22),

          if (_type == FeedbackType.bug) ...[
            _label('오류가 발생한 화면 (선택)'),
            TextField(
              controller: _relatedScreenCtrl,
              decoration: _deco('예: 파티 상세 화면'),
            ),
            const SizedBox(height: 22),
          ],

          _label('이미지 첨부 (최대 3장)'),
          Row(children: [
            ..._images.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(clipBehavior: Clip.none, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(e.value.path), width: 76, height: 76, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: -6, right: -6,
                      child: GestureDetector(
                        onTap: () => setState(() => _images.removeAt(e.key)),
                        child: Container(
                          width: 20, height: 20,
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ]),
                )),
            if (_images.length < 3)
              GestureDetector(
                onTap: _pickImages,
                child: Container(
                  width: 76, height: 76,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE8EBF2)),
                  ),
                  child: const Icon(Icons.add_a_photo_outlined, color: Colors.black38, size: 24),
                ),
              ),
          ]),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6FA0),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('의견 보내기',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
