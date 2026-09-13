import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:party_app/models/party_application_form.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/widgets/applicant_photo_protection.dart';

/// 승인제 파티의 **사전질문 답변 + 사진 제출** 화면.
///
/// 신청 흐름에서 차수 선택과 결제수단 선택 **사이**에 들어간다 — 결제를 하고
/// 나서야 질문이 나오면, 답을 못 채운 사람이 이미 돈을 낸 상태가 된다.
///
/// 즉시확정 파티는 이 화면 자체가 열리지 않는다(호출부에서 분기).
///
/// **질문과 사진은 독립이다.** 사진 칸은 호스트가 켠 파티에서만
/// ([PartyApplicationForm.requiresPhotos]) 뜨고, 그때는 최소 1장이 필수다.
/// 끄면 칸 자체가 없고 0장으로도 신청이 끝난다.
///
/// 돌려주는 값은 `applyToParty`에 그대로 실어 보낼 `{answers, photos}`다.
/// 사진은 여기서 **미리 업로드**하고 참조만 넘긴다 — 신청 호출을 파일 업로드
/// 시간만큼 붙들면 사용자는 멈춘 줄 안다.
class PartyApplicationAnswerScreen extends StatefulWidget {
  final String partyId;
  final String hostId;
  final String applicationId;
  final PartyApplicationForm form;

  const PartyApplicationAnswerScreen({
    super.key,
    required this.partyId,
    required this.hostId,
    required this.applicationId,
    required this.form,
  });

  @override
  State<PartyApplicationAnswerScreen> createState() =>
      _PartyApplicationAnswerScreenState();
}

class _PartyApplicationAnswerScreenState
    extends State<PartyApplicationAnswerScreen> {
  static const _accent = Color(0xFF7C5CBF);

  final Map<String, TextEditingController> _controllers = {};
  final List<_PendingPhoto> _photos = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    for (final q in widget.form.questions) {
      _controllers[q.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 사진 칸을 그리고 검사할지 — 호스트가 켠 파티에서만 true다.
  bool get _photosRequested => widget.form.requiresPhotos;

  /// 필수 질문이 모두 채워졌는지 — 아니면 다음 단계로 못 간다.
  bool get _requiredFilled => widget.form.questions
      .where((q) => q.required)
      .every((q) => (_controllers[q.id]?.text.trim() ?? '').isNotEmpty);

  /// 사진 요청이 켜져 있으면 최소 1장. 꺼져 있으면 0장이어도 통과한다.
  bool get _photosSatisfied => !_photosRequested || _photos.isNotEmpty;

  /// 다음 단계로 갈 수 있는지 — 질문과 사진 조건을 함께 본다.
  bool get _canSubmit => _requiredFilled && _photosSatisfied;

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pickPhotos() async {
    final remain = PartyApplicationLimits.maxPhotos - _photos.length;
    if (remain <= 0) {
      _msg('사진은 최대 ${PartyApplicationLimits.maxPhotos}장까지 올릴 수 있어요.');
      return;
    }
    final picked = await ImagePicker().pickMultiImage(
      limit: remain,
      // 심사용 사진이라 원본 해상도가 필요 없다 — 업로드도 빠르고 호스트
      // 화면에서 디코딩 부담도 줄어든다.
      imageQuality: 85,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked.take(remain)) {
        _photos.add(_PendingPhoto(file: f));
      }
    });
  }

  /// 사진을 Storage에 올리고 참조 목록을 돌려준다.
  ///
  /// 경로는 `partyApplications/{partyId}/{applicationId}/{photoId}`이고,
  /// storage.rules가 이 경로의 맨 앞 조각(uid)으로 소유자를 판정한다.
  /// 메타데이터의 hostId는 **호스트가 읽을 수 있게** 하는 유일한 근거다 —
  /// Storage 규칙은 Firestore를 조회할 수 없기 때문이다(storage.rules 주석 참고).
  Future<List<Map<String, dynamic>>?> _uploadPhotos() async {
    if (_photos.isEmpty) return const [];
    final storage = FirebaseStorage.instance;
    final refs = <Map<String, dynamic>>[];
    for (var i = 0; i < _photos.length; i++) {
      final p = _photos[i];
      final id =
          'p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_$i';
      try {
        // putFile이 아니라 putData다 — 웹에는 dart:io File이 없다. 경로·메타
        // 데이터·규칙은 예전과 완전히 같고, 보내는 바이트도 같은 파일이다.
        await storage
            .ref(
              'partyApplications/${widget.partyId}/${widget.applicationId}/$id',
            )
            .putData(
              await p.file.readAsBytes(),
              SettableMetadata(
                contentType: 'image/jpeg',
                customMetadata: {'hostId': widget.hostId},
              ),
            );
        refs.add({'id': id});
      } catch (e) {
        debugPrint('[ApplicationAnswer] 사진 업로드 실패: $e');
        return null;
      }
    }
    return refs;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_requiredFilled) {
      _msg('필수 질문에 모두 답변해주세요.');
      return;
    }
    if (!_photosSatisfied) {
      _msg('프로필 사진을 1장 이상 올려주세요.');
      return;
    }
    setState(() => _submitting = true);
    final photos = await _uploadPhotos();
    if (!mounted) return;
    if (photos == null) {
      setState(() => _submitting = false);
      _msg('사진을 올리지 못했어요. 잠시 후 다시 시도해주세요.');
      return;
    }

    final answers = <String, String>{};
    for (final q in widget.form.questions) {
      final v = _controllers[q.id]?.text.trim() ?? '';
      if (v.isNotEmpty) answers[q.id] = v;
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      PartyApplicationSubmission(answers: answers, photos: photos),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      appBar: AppBar(
        title: const Text(
          '사전질문',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          _intro(),
          const SizedBox(height: 18),
          for (var i = 0; i < widget.form.questions.length; i++)
            _questionField(i, widget.form.questions[i]),
          const SizedBox(height: 6),
          // 호스트가 요청한 파티에서만 사진 칸이 뜬다.
          if (_photosRequested) _photoSection(),
          const SizedBox(height: 18),
          _privacyNotice(),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget _intro() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _accent.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.how_to_reg_outlined, size: 19, color: _accent),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            '호스트 승인이 필요한 파티예요.\n'
            '아래 내용을 확인한 뒤 승인되면 참가가 확정돼요.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: Color(0xFF4A3A70),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _questionField(int index, PartyApplicationQuestion q) {
    final controller = _controllers[q.id]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${index + 1}.',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _accent,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  q.text,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
              if (q.required)
                Container(
                  margin: const EdgeInsets.only(left: 6, top: 1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEDF3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
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
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLength: PartyApplicationLimits.maxAnswerLength,
            maxLines: 4,
            minLines: 2,
            textInputAction: TextInputAction.newline,
            onChanged: (_) => setState(() {}), // 하단 버튼 활성 상태 갱신
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: '답변을 입력해주세요',
              hintStyle: const TextStyle(fontSize: 13.5, color: Colors.black38),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE3E5EC)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE3E5EC)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Text(
            '프로필 사진 제출',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEDF3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '필수',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFFE0407A),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '${_photos.length}/${PartyApplicationLimits.maxPhotos}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _accent,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      // 사진을 **고르기 전에** 읽도록 추가 칸 바로 위에 둔다 — 무엇이 어디까지
      // 보호되는지 알고 나서 낼지 말지를 정할 수 있어야 한다.
      const ApplicantPhotoGuestNotice(),
      const SizedBox(height: 12),
      SizedBox(
        height: 92,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (var i = 0; i < _photos.length; i++) _photoThumb(i),
            if (_photos.length < PartyApplicationLimits.maxPhotos)
              _addPhotoTile(),
          ],
        ),
      ),
    ],
  );

  Widget _photoThumb(int index) => Padding(
    padding: const EdgeInsets.only(right: 9),
    child: Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LocalMedia.image(
            _photos[index].file,
            width: 92,
            height: 92,
            fit: BoxFit.cover,
            // 썸네일이라 원본 해상도로 디코딩할 이유가 없다.
            cacheWidth: 276,
          ),
        ),
        Positioned(
          right: 3,
          top: 3,
          child: GestureDetector(
            onTap: () => setState(() => _photos.removeAt(index)),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Color(0xCC000000),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _addPhotoTile() => GestureDetector(
    onTap: _pickPhotos,
    child: Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8DBE4)),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_outlined, size: 21, color: Colors.black45),
          SizedBox(height: 5),
          Text('사진 추가', style: TextStyle(fontSize: 11, color: Colors.black45)),
        ],
      ),
    ),
  );

  /// 개인정보 주의 문구 — 이 화면에서는 항상 보인다.
  Widget _privacyNotice() => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4F4),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFD5D5)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.privacy_tip_outlined, size: 18, color: Color(0xFFD94A4A)),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            kApplicationAnswerPrivacyNotice,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: Color(0xFF8B2F2F),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _bottomBar() => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _submitting || !_canSubmit ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  '다음',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
        ),
      ),
    ),
  );
}

/// 답변 화면이 돌려주는 값 — `applyToParty` 호출에 그대로 실린다.
class PartyApplicationSubmission {
  final Map<String, String> answers;
  final List<Map<String, dynamic>> photos;

  const PartyApplicationSubmission({
    required this.answers,
    required this.photos,
  });
}

class _PendingPhoto {
  final XFile file;
  const _PendingPhoto({required this.file});
}

/// 신청 문서 ID 규칙 — 서버 `applicationDocId(uid, occurrenceId)`와 같아야 한다.
///
/// 사진 경로에 이 값이 들어가고 storage.rules가 맨 앞 조각으로 소유자를
/// 판정하므로, 규칙이 갈라지면 업로드가 통째로 막힌다.
String partyApplicationDocId(String? occurrenceId) {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  return (occurrenceId == null || occurrenceId.isEmpty)
      ? uid
      : '${uid}_$occurrenceId';
}
