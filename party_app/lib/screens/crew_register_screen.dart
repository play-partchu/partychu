import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:party_app/models/address_result.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/screens/address_search_screen.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/utils/register_return_signal.dart';
import 'package:party_app/utils/user_session.dart';

class CrewRegisterScreen extends StatefulWidget {
  const CrewRegisterScreen({super.key});

  @override
  State<CrewRegisterScreen> createState() => _CrewRegisterScreenState();
}

class _CrewRegisterScreenState extends State<CrewRegisterScreen> {
  // ── 글 유형 / 모집 기간 ────────────────────────────────────────────
  String _crewType    = '구인';
  String _recruitType = '항시';

  // ── 날짜 ─────────────────────────────────────────────────────────
  DateTime? _startDate;
  DateTime? _endDate;

  // ── 시간 ─────────────────────────────────────────────────────────
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  // ── 텍스트 입력 ──────────────────────────────────────────────────
  final _titleCtrl   = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _roleCtrl    = TextEditingController(); // '기타' 선택 시 직접 입력
  final _payCtrl     = TextEditingController();
  final _autoMsgCtrl = TextEditingController(); // 구인 전용 자동 안내 문구
  final _recruitCountCtrl = TextEditingController();

  // ── 모집 역할 (다중 선택, 상세검색에서 필터링 가능) ─────────────────
  final Set<String> _selectedRoles = {};

  // ── 모집 조건 (상세검색 필터용) ─────────────────────────────────────
  bool _beginnerFriendly      = false;
  bool _experiencedPreferred  = false;

  // ── 구직 전용: 프로필 사진 ─────────────────────────────────────────
  XFile? _profileImage;

  // ── 지역 선택 (최대 3개) ───────────────────────────────────────────
  final Set<String> _selectedRegions = {};

  static const _regionList = [
    '서울', '부산', '인천', '대구', '대전', '광주', '울산', '세종',
    '경기', '강원', '충남', '충북', '전남', '전북', '경남', '경북',
    '제주', '온라인',
  ];

  // ── 구인 전용: 실제 주소 ──────────────────────────────────────────
  AddressResult? _selectedAddress;
  final _detailAddressCtrl = TextEditingController();

  // ── 급여/페이 ────────────────────────────────────────────────────
  String _payType = '협의';
  static const _payTypes = ['협의', '시급', '건당', '무료', '기타'];
  // 상세검색 "보수" 필터('유료'/'협의'/'무료')와 매핑: 협의·무료를 제외한 나머지는 모두 유료로 취급.

  bool _isSubmitting = false;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _roleCtrl.dispose();
    _payCtrl.dispose();
    _recruitCountCtrl.dispose();
    _autoMsgCtrl.dispose();
    _detailAddressCtrl.dispose();
    super.dispose();
  }

  // ── 프로필 사진 선택 (구직) ──────────────────────────────────────
  Future<void> _pickProfileImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) { return; }
    setState(() => _profileImage = picked);
  }

  // ── 날짜 선택 ─────────────────────────────────────────────────────
  Future<void> _pickDate(bool isStart) async {
    final now   = DateTime.now();
    final first = isStart ? now : (_startDate ?? now);
    final init  = isStart
        ? (_startDate ?? now)
        : (_endDate ?? first.add(const Duration(days: 1)));

    final picked = await showDatePicker(
      context: context,
      initialDate: init.isBefore(first) ? first : init,
      firstDate:   first,
      lastDate:    DateTime(now.year + 2),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFFFF6FA0)),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) { return; }
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) { _endDate = null; }
      } else {
        _endDate = picked;
      }
    });
  }

  // ── 시간 선택 ─────────────────────────────────────────────────────
  Future<void> _pickTime(bool isStart) async {
    final init = isStart
        ? (_startTime ?? const TimeOfDay(hour: 18, minute: 0))
        : (_endTime   ?? const TimeOfDay(hour: 22, minute: 0));

    final picked = await showTimePicker(
      context: context,
      initialTime: init,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFF6FA0),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        ),
      ),
    );
    if (picked == null || !mounted) { return; }
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  // ── 포맷 헬퍼 ────────────────────────────────────────────────────
  String _fmtDate(DateTime d) {
    final w = _weekdays[d.weekday - 1];
    return '${d.year}.${d.month.toString().padLeft(2,'0')}.${d.day.toString().padLeft(2,'0')} ($w)';
  }

  String _fmtTime(TimeOfDay t) {
    final h  = t.hour;
    final m  = t.minute.toString().padLeft(2, '0');
    if (h == 0)  { return '오전 12:$m'; }
    if (h < 12)  { return '오전 $h:$m'; }
    if (h == 12) { return '오후 12:$m'; }
    return '오후 ${h - 12}:$m';
  }

  String _timeStr(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

  // ── 제출 ─────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (UserSession.userId.isEmpty) { _msg('로그인이 필요합니다.'); return; }
    if (_titleCtrl.text.trim().isEmpty) { _msg('제목을 입력해주세요.'); return; }
    if (_contentCtrl.text.trim().isEmpty) { _msg('내용을 입력해주세요.'); return; }
    if (_recruitType == '날짜지정' && _startDate == null) {
      _msg('시작 날짜를 선택해주세요.'); return;
    }

    setState(() => _isSubmitting = true);
    try {
      // 구직: 프로필 사진 업로드 (선택)
      String? profileImageUrl;
      if (_crewType == '구직' && _profileImage != null) {
        profileImageUrl =
            await CloudflareService.uploadImage(File(_profileImage!.path));
      }

      // '기타' 선택 시 직접 입력한 역할명을 함께 포함
      final customRole = _roleCtrl.text.trim();
      final roles = {
        ..._selectedRoles.where((r) => r != '기타'),
        if (_selectedRoles.contains('기타') && customRole.isNotEmpty) customRole,
      }.toList();

      final doc = <String, dynamic>{
        'crewType':    _crewType,
        'recruitType': _recruitType,
        'title':       _titleCtrl.text.trim(),
        'content':     _contentCtrl.text.trim(),
        'roles':       roles,
        'role':        roles.join(' · '), // 구버전 호환용 표시 문자열
        'regions':     _selectedRegions.toList(),
        'payType':     _payType,
        'payAmount':   (_payType == '협의' || _payType == '무료') ? 0
            : int.tryParse(_payCtrl.text.trim().replaceAll(',', '')) ?? 0,
        'recruitCount': int.tryParse(_recruitCountCtrl.text.trim()) ?? 0,
        'beginnerFriendly':     _beginnerFriendly,
        'experiencedPreferred': _experiencedPreferred,
        'hostId':      UserSession.userId,
        'hostName':    UserSession.displayName,
        'isActive':    true,
        'createdAt':   FieldValue.serverTimestamp(),
        'updatedAt':   FieldValue.serverTimestamp(),
      };

      // 구인 전용 필드
      if (_crewType == '구인') {
        doc['autoMessage'] = _autoMsgCtrl.text.trim();
        if (_selectedAddress != null) {
          doc['address']       = _selectedAddress!.address;
          doc['roadAddress']   = _selectedAddress!.roadAddress;
          doc['jibunAddress']  = _selectedAddress!.jibunAddress;
          doc['latitude']      = _selectedAddress!.latitude;
          doc['longitude']     = _selectedAddress!.longitude;
          final detail = _detailAddressCtrl.text.trim();
          if (detail.isNotEmpty) { doc['detailAddress'] = detail; }
        }
      }

      // 구직 전용 필드
      if (_crewType == '구직' && profileImageUrl != null) {
        doc['profileImageUrl'] = profileImageUrl;
      }

      if (_recruitType == '날짜지정') {
        doc['startDate'] = Timestamp.fromDate(_startDate!);
        if (_endDate != null) { doc['endDate'] = Timestamp.fromDate(_endDate!); }
      }
      if (_startTime != null) { doc['startTime'] = _timeStr(_startTime!); }
      if (_endTime   != null) { doc['endTime']   = _timeStr(_endTime!); }

      await FirebaseFirestore.instance.collection('crews').add(doc);
      if (!mounted) { return; }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            const Icon(Icons.check_circle,
                color: Color(0xFFFF6FA0), size: 26),
            const SizedBox(width: 10),
            Text(
              _crewType == '구인' ? '구인 등록 완료' : '구직 등록 완료',
              style: const TextStyle(
                  fontFamily: 'SeoulHangang',
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                    Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                    Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                    Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                  ]),
            ),
          ]),
          content: Text(
            _crewType == '구인'
                ? '파티크루 구인 글이 등록되었습니다.'
                : '파티크루 구직 글이 등록되었습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // 다이얼로그 닫기
                // 등록 화면이 몇 단계 깊이 열려 있었든(모바일:
                // RegisterTypeScreen 경유, 데스크톱: MainScreen에서 바로)
                // 곧장 메인화면 파티크루 탭으로 복귀한다.
                pendingTopTabAfterRegister.value = 3;
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              child: const Text('확인',
                  style: TextStyle(
                      color: Color(0xFFFF6FA0),
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) { _msg('등록 중 오류가 발생했습니다. 다시 시도해주세요.'); }
    } finally {
      if (mounted) { setState(() => _isSubmitting = false); }
    }
  }

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  // ── 빌드 ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text('파티크루 등록',
            style: TextStyle(fontFamily: 'SeoulHangang', fontSize: 17, fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── 1. 글 유형 ───────────────────────────────────────────
          _label('글 유형'),
          _segment(
            options:  ['구인', '구직'],
            selected: _crewType,
            accent:   const Color(0xFFFF6FA0),
            onTap:    (v) => setState(() => _crewType = v),
          ),
          const SizedBox(height: 22),

          // ── 2. 구직 전용: 프로필 사진 ────────────────────────────
          if (_crewType == '구직') ...[
            _label('프로필 사진 (선택)'),
            _buildProfileImagePicker(),
            const SizedBox(height: 22),
          ],

          // ── 3. 모집 기간 ─────────────────────────────────────────
          _label('모집 기간'),
          _segment(
            options:       ['항시', '날짜지정'],
            displayValues: ['항시 모집', '날짜 지정'],
            selected:      _recruitType,
            accent:        const Color(0xFF7C5CBF),
            onTap:         (v) => setState(() => _recruitType = v),
          ),
          const SizedBox(height: 12),

          if (_recruitType == '날짜지정') ...[
            Row(children: [
              Expanded(
                  child: _dateTile(
                      '시작 날짜', _startDate, () => _pickDate(true))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('~',
                    style: TextStyle(
                        fontSize: 16, color: Colors.black45)),
              ),
              Expanded(
                  child: _dateTile('종료 날짜 (선택)', _endDate,
                      () => _pickDate(false))),
            ]),
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 6),

          // ── 4. 모집 시간 ─────────────────────────────────────────
          _label('모집 시간 (선택)'),
          Row(children: [
            Expanded(
                child: _timeTile(
                    '시작 시간', _startTime, () => _pickTime(true))),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('~',
                  style: TextStyle(fontSize: 16, color: Colors.black45)),
            ),
            Expanded(
                child: _timeTile(
                    '종료 시간', _endTime, () => _pickTime(false))),
          ]),
          const SizedBox(height: 22),

          // ── 5. 역할/직종 (다중 선택 — 상세검색 필터와 매칭) ────────
          _label(_crewType == '구인' ? '모집 역할' : '지원 가능 역할'),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: ListingConstants.crewRoles.map((r) {
              final sel = _selectedRoles.contains(r);
              return GestureDetector(
                onTap: () => setState(() {
                  if (sel) { _selectedRoles.remove(r); } else { _selectedRoles.add(r); }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFFFF6FA0) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Text(r,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : Colors.black54,
                      )),
                ),
              );
            }).toList(),
          ),
          if (_selectedRoles.contains('기타')) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _roleCtrl,
              textInputAction: TextInputAction.next,
              decoration: _deco('기타 역할을 직접 입력해주세요'),
            ),
          ],
          const SizedBox(height: 22),

          // ── 6. 제목 ──────────────────────────────────────────────
          _label('제목'),
          TextField(
            controller: _titleCtrl,
            textInputAction: TextInputAction.next,
            decoration: _deco(
              _crewType == '구인'
                  ? '예: 10월 할로윈 파티 DJ 구인합니다'
                  : '예: 파티 MC 경력 3년, 활동 가능합니다',
            ),
          ),
          const SizedBox(height: 22),

          // ── 7. 상세 내용 ─────────────────────────────────────────
          _label('상세 내용'),
          TextField(
            controller: _contentCtrl,
            maxLines: 6,
            textInputAction: TextInputAction.newline,
            decoration: _deco(
              _crewType == '구인'
                  ? '파티 일정, 장소, 조건, 페이 등을 자세히 입력해주세요.'
                  : '경력, 보유 장비, 가능한 역할, 희망 조건 등을 입력해주세요.',
            ),
          ),
          const SizedBox(height: 22),

          // ── 8. 구인 전용: 실제 주소 ──────────────────────────────
          if (_crewType == '구인') ...[
            _label('실제 주소 (선택)'),
            _buildAddressSection(),
            const SizedBox(height: 22),
          ],

          // ── 9. 활동 지역 (선택식, 최대 3개) ──────────────────────
          Row(children: [
            Expanded(
              child: _label('활동 지역 (최대 3개)'),
            ),
            Text(
              '${_selectedRegions.length}/3개 선택',
              style: TextStyle(
                  fontSize: 12,
                  color: _selectedRegions.length >= 3
                      ? const Color(0xFFFF6FA0)
                      : Colors.black38),
            ),
          ]),
          _buildRegionSelector(),
          const SizedBox(height: 22),

          // ── 9. 급여/페이 ─────────────────────────────────────────
          _label('급여 / 페이'),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _payTypes.map((t) {
              final sel = _payType == t;
              return GestureDetector(
                onTap: () => setState(() {
                  _payType = t;
                  if (t == '협의' || t == '무료') { _payCtrl.clear(); }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 9),
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
                  child: Text(t,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : Colors.black54,
                      )),
                ),
              );
            }).toList(),
          ),
          if (_payType != '협의' && _payType != '무료') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _payCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: _deco(
                  _payType == '시급' ? '시급 금액 (원)' : '금액 (원)'),
            ),
          ],
          const SizedBox(height: 22),

          // ── 9-1. 모집 인원 (선택) ────────────────────────────────
          _label('모집 인원 (선택)'),
          TextField(
            controller: _recruitCountCtrl,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: _deco('예: 2 (인원 미정이면 비워두세요)'),
          ),
          const SizedBox(height: 22),

          // ── 9-2. 모집 조건 (상세검색 필터용) ─────────────────────
          _label('모집 조건'),
          Row(children: [
            Expanded(
              child: _conditionToggle(
                label: '초보 가능',
                value: _beginnerFriendly,
                onChanged: (v) => setState(() => _beginnerFriendly = v),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _conditionToggle(
                label: '경력 우대',
                value: _experiencedPreferred,
                onChanged: (v) => setState(() => _experiencedPreferred = v),
              ),
            ),
          ]),
          const SizedBox(height: 22),

          // ── 10. 구인 전용: 지원자 자동 안내 문구 ─────────────────
          if (_crewType == '구인') ...[
            _label('지원자 자동 안내 문구'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFD6E4)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Row(children: [
                  Icon(Icons.notifications_outlined,
                      size: 14, color: Color(0xFFFF6FA0)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '근무 시작 2시간 전에 지원자에게 자동으로 발송돼요.',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFFFF6FA0)),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: _autoMsgCtrl,
                  maxLines: 4,
                  decoration: _deco(
                    '예: 안녕하세요! 오늘 근무 관련 안내드립니다.\n집합 장소는 ...',
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 22),
          ],

          // ── 제출 버튼 ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6FA0),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      _crewType == '구인' ? '구인 글 등록하기' : '구직 글 등록하기',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── 프로필 사진 picker (구직) ─────────────────────────────────────
  Widget _buildProfileImagePicker() {
    return GestureDetector(
      onTap: _pickProfileImage,
      child: _profileImage == null
          ? Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFE8EBF2),
                    style: BorderStyle.solid),
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                const Icon(Icons.add_a_photo_outlined,
                    size: 32, color: Color(0xFFFF6FA0)),
                const SizedBox(height: 8),
                const Text('프로필 사진 추가 (선택)',
                    style: TextStyle(
                        fontSize: 13, color: Colors.black45)),
                const SizedBox(height: 2),
                Text('1:1 비율 권장',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.black.withValues(alpha: 0.3))),
              ]),
            )
          : Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  File(_profileImage!.path),
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 8, right: 8,
                child: GestureDetector(
                  onTap: () => setState(() => _profileImage = null),
                  child: Container(
                    width: 28, height: 28,
                    decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle),
                    child: const Icon(Icons.close,
                        size: 16, color: Colors.white),
                  ),
                ),
              ),
              Positioned(
                bottom: 8, right: 8,
                child: GestureDetector(
                  onTap: _pickProfileImage,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('변경',
                        style: TextStyle(
                            fontSize: 12, color: Colors.white)),
                  ),
                ),
              ),
            ]),
    );
  }

  // ── 구인 전용: 주소 검색 섹션 ────────────────────────────────────
  Widget _buildAddressSection() {
    return Column(
      children: [
        GestureDetector(
          onTap: () async {
            final result = await Navigator.push<AddressResult>(
              context,
              MaterialPageRoute(
                  builder: (_) => const AddressSearchScreen()),
            );
            if (result != null) {
              setState(() => _selectedAddress = result);
            }
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: _selectedAddress != null
                  ? const Color(0xFFFFF0F5)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _selectedAddress != null
                    ? const Color(0xFFFF6FA0)
                    : const Color(0xFFE8EBF2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: _selectedAddress != null
                      ? const Color(0xFFFF6FA0)
                      : Colors.black38,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedAddress != null
                        ? _selectedAddress!.address
                        : '주소 검색',
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedAddress != null
                          ? Colors.black87
                          : Colors.black38,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_selectedAddress != null)
                  GestureDetector(
                    onTap: () =>
                        setState(() => _selectedAddress = null),
                    child: const Icon(Icons.close,
                        size: 16, color: Colors.black38),
                  )
                else
                  const Icon(Icons.search,
                      size: 18, color: Colors.black38),
              ],
            ),
          ),
        ),
        if (_selectedAddress != null) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _detailAddressCtrl,
            textInputAction: TextInputAction.next,
            decoration: _deco('상세 주소 (동/호수 등, 선택)'),
          ),
        ],
      ],
    );
  }

  // ── 지역 선택 칩 ─────────────────────────────────────────────────
  Widget _buildRegionSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Wrap(
        spacing: 8, runSpacing: 8,
        children: _regionList.map((region) {
          final sel = _selectedRegions.contains(region);
          final disabled = !sel && _selectedRegions.length >= 3;
          return GestureDetector(
            onTap: disabled
                ? null
                : () => setState(() {
                      if (sel) {
                        _selectedRegions.remove(region);
                      } else {
                        _selectedRegions.add(region);
                      }
                    }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              padding: const EdgeInsets.symmetric(
                  horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: sel
                    ? const Color(0xFFFF6FA0)
                    : disabled
                        ? const Color(0xFFF7F7FA)
                        : const Color(0xFFFFF0F5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel
                      ? const Color(0xFFFF6FA0)
                      : disabled
                          ? const Color(0xFFE8EBF2)
                          : const Color(0xFFFFD6E4),
                  width: sel ? 1.5 : 1,
                ),
              ),
              child: Text(
                region,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sel
                      ? Colors.white
                      : disabled
                          ? Colors.black26
                          : const Color(0xFFFF6FA0),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _conditionToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: value ? const Color(0xFFFFF0F5) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
              width: value ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Icon(
              value ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: value ? const Color(0xFFFF6FA0) : Colors.black26,
            ),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: value ? const Color(0xFFFF6FA0) : Colors.black54,
                )),
          ]),
        ),
      );

  // ── 공통 위젯 ────────────────────────────────────────────────────
  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.black87)),
      );

  Widget _segment({
    required List<String> options,
    required String selected,
    required Color accent,
    required void Function(String) onTap,
    List<String>? displayValues,
  }) =>
      Row(
        children: List.generate(options.length, (i) {
          final val     = options[i];
          final display = displayValues?[i] ?? val;
          final isSel   = selected == val;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(val),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: EdgeInsets.only(
                    right: i < options.length - 1 ? 8 : 0),
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: isSel ? accent : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSel ? accent : const Color(0xFFE8EBF2),
                    width: isSel ? 1.5 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(display,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSel ? Colors.white : Colors.black54,
                    )),
              ),
            ),
          );
        }),
      );

  Widget _dateTile(String label, DateTime? date, VoidCallback onTap) {
    final has = date != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: has ? const Color(0xFFFFF0F5) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: has
                  ? const Color(0xFFFF6FA0)
                  : const Color(0xFFE8EBF2)),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: Colors.black38)),
          const SizedBox(height: 3),
          Text(
            has ? _fmtDate(date) : '날짜 선택',
            style: TextStyle(
              fontSize: 12,
              fontWeight: has ? FontWeight.w600 : FontWeight.normal,
              color: has ? const Color(0xFFFF6FA0) : Colors.black38,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _timeTile(String label, TimeOfDay? time, VoidCallback onTap) {
    final has = time != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: has ? const Color(0xFFFFF0F5) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: has
                  ? const Color(0xFFFF6FA0)
                  : const Color(0xFFE8EBF2)),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: Colors.black38)),
          const SizedBox(height: 3),
          Row(children: [
            Icon(Icons.access_time,
                size: 13,
                color:
                    has ? const Color(0xFFFF6FA0) : Colors.black26),
            const SizedBox(width: 4),
            Text(
              has ? _fmtTime(time) : '시간 선택',
              style: TextStyle(
                fontSize: 12,
                fontWeight: has ? FontWeight.w600 : FontWeight.normal,
                color:
                    has ? const Color(0xFFFF6FA0) : Colors.black38,
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: Colors.black38, fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE8EBF2))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE8EBF2))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Color(0xFFFF6FA0))),
      );
}
