import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:party_app/models/address_result.dart';

class AddressSearchScreen extends StatefulWidget {
  const AddressSearchScreen({super.key});

  @override
  State<AddressSearchScreen> createState() => _AddressSearchScreenState();
}

class _AddressSearchScreenState extends State<AddressSearchScreen> {
  final _searchController = TextEditingController();
  List<AddressResult> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  Timer? _debounce;

  // 디버그 상태
  int _statusCode = 0;
  String _errorMessage = '';
  String _searchedKeyword = '';
  String _normalizedKeyword = '';
  int _resultCount = 0;
  bool _isAuthError = false;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _search(value.trim());
    });
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _statusCode = 0;
        _errorMessage = '';
        _searchedKeyword = '';
        _normalizedKeyword = '';
        _resultCount = 0;
        _isAuthError = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _errorMessage = '';
      _isAuthError = false;
    });

    debugPrint('[AddressSearch] 검색어: $query');

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('geocodeAddress');
      final result = await callable.call<Map<Object?, Object?>>({
        'query': query,
      });

      final body = result.data;
      final status = body['status'] as String? ?? '';
      final code = (body['statusCode'] as num?)?.toInt() ?? 0;
      final debug = body['debug'] as Map<Object?, Object?>? ?? {};

      final rawQuery = debug['rawQuery'] as String? ?? query;
      final normalizedQuery = debug['normalizedQuery'] as String? ?? query;

      final addressesList = (body['addresses'] as List<Object?>?) ?? [];

      debugPrint(
        '[AddressSearch] status=$status statusCode=$code '
        'rawQuery=$rawQuery normalizedQuery=$normalizedQuery '
        'resultCount=${addressesList.length}',
      );

      // 인증 오류
      if (status == 'AUTH_ERROR' || code == 401 || code == 403) {
        if (mounted) {
          setState(() {
            _results = [];
            _isLoading = false;
            _statusCode = code;
            _errorMessage = '지도 API 인증 오류입니다. 관리자 설정을 확인해주세요.';
            _searchedKeyword = rawQuery;
            _normalizedKeyword = normalizedQuery;
            _resultCount = 0;
            _isAuthError = true;
          });
        }
        return;
      }

      // 결과 파싱
      final List<AddressResult> results = [];
      for (final addr in addressesList) {
        final m = addr as Map<Object?, Object?>;
        final road = m['roadAddress'] as String? ?? '';
        final jibun = m['jibunAddress'] as String? ?? '';
        final lng = double.tryParse(m['x'] as String? ?? '') ?? 0.0;
        final lat = double.tryParse(m['y'] as String? ?? '') ?? 0.0;
        results.add(
          AddressResult(
            placeName: '',
            address: road.isNotEmpty ? road : jibun,
            roadAddress: road,
            jibunAddress: jibun,
            latitude: lat,
            longitude: lng,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
          _statusCode = code;
          _errorMessage = results.isEmpty
              ? '검색 결과가 없습니다. 도로명 또는 지번 주소로 다시 검색해주세요.'
              : '';
          _searchedKeyword = rawQuery;
          _normalizedKeyword = normalizedQuery;
          _resultCount = results.length;
          _isAuthError = false;
        });
      }
    } catch (e, st) {
      debugPrint('[AddressSearch] 예외: $e\n$st');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '요청 실패: $e';
          _searchedKeyword = query;
          _normalizedKeyword = '';
          _resultCount = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        foregroundColor: Colors.black,
        titleSpacing: 0,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: _onChanged,
          onSubmitted: (v) => _search(v.trim()),
          decoration: const InputDecoration(
            hintText: '도로명 또는 지번 주소 검색',
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 8),
          ),
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                _search('');
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasSearched) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 64, color: Colors.black26),
            SizedBox(height: 12),
            Text(
              '도로명 또는 지번 주소를 검색하세요',
              style: TextStyle(color: Colors.black45, fontSize: 15),
            ),
            SizedBox(height: 6),
            Text(
              '예) 테헤란로 152, 역삼동 737-5',
              style: TextStyle(color: Colors.black26, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // 인증 오류
    if (_isAuthError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.redAccent),
              const SizedBox(height: 12),
              const Text(
                '지도 API 인증 오류입니다.',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '관리자 설정을 확인해주세요.',
                style: TextStyle(color: Colors.black45, fontSize: 13),
              ),
              const SizedBox(height: 20),
              _debugCard(),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.location_off_outlined,
                size: 64,
                color: Colors.black26,
              ),
              const SizedBox(height: 12),
              const Text(
                '검색 결과가 없습니다',
                style: TextStyle(color: Colors.black45, fontSize: 15),
              ),
              const SizedBox(height: 4),
              const Text(
                '도로명 또는 지번 주소로 다시 검색해주세요.\n'
                '도로명만 입력했다면 건물번호를 붙여서(예: 강남대로65길 12)\n'
                '다시 검색해보세요.',
                style: TextStyle(color: Colors.black38, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _debugCard(),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, i) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, index) {
        final r = _results[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.location_on_outlined,
              size: 20,
              color: Colors.black54,
            ),
          ),
          title: Text(
            r.roadAddress.isNotEmpty ? r.roadAddress : r.jibunAddress,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: r.jibunAddress.isNotEmpty && r.jibunAddress != r.roadAddress
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          '지번',
                          style: TextStyle(fontSize: 10, color: Colors.black54),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          r.jibunAddress,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          onTap: () => Navigator.pop(context, r),
        );
      },
    );
  }

  Widget _debugCard() {
    if (_searchedKeyword.isEmpty && _statusCode == 0) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '디버그 정보',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 6),
          _debugRow('statusCode', '$_statusCode'),
          _debugRow(
            'errorMessage',
            _errorMessage.isNotEmpty ? _errorMessage : '-',
          ),
          _debugRow(
            'searchedKeyword',
            _searchedKeyword.isNotEmpty ? _searchedKeyword : '-',
          ),
          _debugRow(
            'normalizedKeyword',
            _normalizedKeyword.isNotEmpty ? _normalizedKeyword : '-',
          ),
          _debugRow('resultCount', '$_resultCount'),
        ],
      ),
    );
  }

  Widget _debugRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 11,
            color: Colors.black54,
            fontFamily: 'monospace',
          ),
          children: [
            TextSpan(
              text: '$key: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
