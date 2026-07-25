import 'package:flutter/material.dart';
import 'package:party_app/models/address_result.dart';
import 'package:party_app/screens/address_search_screen.dart';
import 'package:party_app/widgets/web_frame.dart';

class PartyLocationSelection {
  final AddressResult place;
  final String detailAddress;

  const PartyLocationSelection({required this.place, required this.detailAddress});
}

/// 등록 화면의 "장소 선택" 행 — 기존 `AddressSearchScreen`(수정하지 않음)으로
/// 주소를 검색한 뒤, 상세주소를 붙여 [PartyLocationSelection]으로 반환한다.
class PartyLocationPickerScreen extends StatefulWidget {
  final AddressResult? initialPlace;
  final String initialDetailAddress;

  const PartyLocationPickerScreen({
    super.key,
    this.initialPlace,
    this.initialDetailAddress = '',
  });

  @override
  State<PartyLocationPickerScreen> createState() => _PartyLocationPickerScreenState();
}

class _PartyLocationPickerScreenState extends State<PartyLocationPickerScreen> {
  AddressResult? _place;
  late final _detailController =
      TextEditingController(text: widget.initialDetailAddress);
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    _place = widget.initialPlace;
  }

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _openAddressSearch() async {
    final result = await Navigator.push<AddressResult>(
      context,
      webFramedRoute((_) => const AddressSearchScreen()),
    );
    if (result != null) {
      setState(() {
        _place = result;
        _showError = false;
      });
    }
  }

  void _confirm() {
    if (_place == null) {
      setState(() => _showError = true);
      return;
    }
    Navigator.pop(
      context,
      PartyLocationSelection(
        place: _place!,
        detailAddress: _detailController.text.trim(),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF7F7FA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final isSelected = _place != null;
    final hasError = _showError && !isSelected;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('장소 선택', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('파티 장소',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _openAddressSearch,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasError
                        ? Colors.red.shade400
                        : isSelected
                            ? Colors.green.shade400
                            : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search,
                        size: 18,
                        color: hasError
                            ? Colors.red.shade400
                            : isSelected
                                ? Colors.green
                                : Colors.black45),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isSelected ? _place!.displayName : '주소를 검색해주세요',
                            style: TextStyle(
                              fontSize: 15,
                              color: isSelected ? Colors.black87 : Colors.black38,
                              fontWeight:
                                  isSelected ? FontWeight.w500 : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isSelected && _place!.placeName.isNotEmpty)
                            Text(_place!.displayAddress,
                                style: const TextStyle(fontSize: 12, color: Colors.black45),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Icon(isSelected ? Icons.check_circle : Icons.chevron_right,
                        size: 18, color: isSelected ? Colors.green : Colors.black38),
                  ],
                ),
              ),
            ),
            if (hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text('파티 장소를 선택해주세요.',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
              ),
            const SizedBox(height: 20),
            const Text('상세주소',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _detailController,
              decoration:
                  _inputDecoration('예: ABC빌딩 5층 파티룸 A, 스타벅스 옆 건물 3층'),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6FA0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('선택 완료',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
