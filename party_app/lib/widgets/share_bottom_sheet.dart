import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_share/kakao_flutter_sdk_share.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:party_app/services/share_service.dart';
import 'package:party_app/utils/party_utils.dart';

/// 모임 상세의 공유 버튼을 누르면 뜨는 PartyChu 전용 공유 메뉴.
/// 링크복사/카카오톡/인스타그램/문자/이메일/더보기를 그리드로 보여준다.
Future<void> showPartyShareSheet(
  BuildContext context, {
  required String partyId,
  required Map<String, dynamic> partyData,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    // 옵션을 탭하면 시트를 먼저 닫고(Navigator.pop) 실제 공유 작업은 비동기로
    // 이어지는데, 그 시점엔 이 builder가 만든 context는 이미 unmount된
    // 상태다. SnackBar 등 사후 UI 피드백은 시트를 띄운 "바깥" 화면의
    // context(여기서 받은 context)를 계속 들고 써야 한다.
    builder: (_) => _ShareBottomSheet(outerContext: context, partyId: partyId, partyData: partyData),
  );
}

class _ShareBottomSheet extends StatelessWidget {
  final BuildContext outerContext;
  final String partyId;
  final Map<String, dynamic> partyData;

  const _ShareBottomSheet({
    required this.outerContext,
    required this.partyId,
    required this.partyData,
  });

  void _showFailureSnack() {
    if (!outerContext.mounted) return;
    ScaffoldMessenger.of(outerContext).showSnackBar(
      const SnackBar(content: Text('공유에 실패했어요. 다시 시도해주세요.')),
    );
  }

  Future<void> _copyLink(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      ShareService.logShareEvent(partyId);
      if (outerContext.mounted) {
        ScaffoldMessenger.of(outerContext)
            .showSnackBar(const SnackBar(content: Text('링크가 복사되었습니다.')));
      }
    } catch (e) {
      debugPrint('[ShareBottomSheet] copy link failed: $e');
      _showFailureSnack();
    }
  }

  Future<void> _shareKakao(String url) async {
    try {
      final title = partyData['title'] as String? ?? '파티';
      // 앱이 실제로 보여주는 대표 미디어와 항상 같은 이미지를 카카오 공유
      // 미리보기에도 써야 한다 — getPartyCoverMedia().thumbnailUrl은 대표가
      // 사진이든 동영상이든 항상 채워지는 정지 이미지라, 예전처럼
      // images[0]/imageUrls[0]만 보다가 대표를 동영상으로 고른 파티는 엉뚱한
      // (또는 없는) 사진이 뜨던 문제가 없다.
      final coverImage = getPartyCoverMedia(partyData, tag: 'KakaoShare')?.thumbnailUrl;

      final link = Link(webUrl: Uri.parse(url), mobileWebUrl: Uri.parse(url));
      final template = FeedTemplate(
        content: Content(
          title: title,
          description: ShareService.buildShortDescription(partyData),
          imageUrl: coverImage != null && coverImage.isNotEmpty ? Uri.parse(coverImage) : null,
          link: link,
        ),
        buttons: [Button(title: '상세보기', link: link)],
      );

      final available = await ShareClient.instance.isKakaoTalkSharingAvailable();
      if (available) {
        final uri = await ShareClient.instance.shareDefault(template: template);
        await ShareClient.instance.launchKakaoTalk(uri);
      } else {
        final uri = await WebSharerClient.instance.makeDefaultUrl(template: template);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      ShareService.logShareEvent(partyId);
    } catch (e) {
      debugPrint('[ShareBottomSheet] kakao share failed: $e');
      // 카카오톡 공유는 SDK 자체 오류(템플릿 크기 초과 등)일 수도 있어
      // share_plus 기본 공유로 폴백한다 — 사용자가 아예 공유를 못 하고
      // 끝나는 상황을 피한다.
      await _shareMore(url, silent: true);
    }
  }

  Future<void> _launchScheme(String scheme, String url) async {
    try {
      final uri = Uri.tryParse(scheme);
      final opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('scheme not handled: $scheme');
      ShareService.logShareEvent(partyId);
    } catch (e) {
      debugPrint('[ShareBottomSheet] scheme launch failed ($scheme): $e');
      // 인스타그램은 배경 이미지 공유 없이는 앱만 여는 수준이라, 실행 자체가
      // 안 되는 기기(미설치 등)에서는 바로 일반 공유로 대체한다.
      await _shareMore(url, silent: true);
    }
  }

  Future<void> _shareSms(String text) async {
    await _launchUrlOrFallback(Uri(scheme: 'sms', queryParameters: {'body': text}));
  }

  Future<void> _shareEmail(String title, String text) async {
    await _launchUrlOrFallback(
      Uri(scheme: 'mailto', queryParameters: {'subject': title, 'body': text}),
    );
  }

  Future<void> _launchUrlOrFallback(Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('could not launch $uri');
      ShareService.logShareEvent(partyId);
    } catch (e) {
      debugPrint('[ShareBottomSheet] launch failed ($uri): $e');
      _showFailureSnack();
    }
  }

  Future<void> _shareMore(String url, {bool silent = false}) async {
    try {
      await SharePlus.instance.share(ShareParams(text: ShareService.buildShareText(partyData, url)));
      ShareService.logShareEvent(partyId);
    } catch (e) {
      debugPrint('[ShareBottomSheet] share_plus failed: $e');
      if (!silent) _showFailureSnack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = ShareService.buildPartyShareUrl(partyId);
    final text = ShareService.buildShareText(partyData, url);
    final title = partyData['title'] as String? ?? '파티';

    final options = <_ShareOptionData>[
      _ShareOptionData('📋', '링크 복사', const Color(0xFF6B7280), () => _copyLink(url)),
      _ShareOptionData('💬', '카카오톡', const Color(0xFFFEE500), () => _shareKakao(url)),
      _ShareOptionData('📸', '인스타그램\n스토리', const Color(0xFFE1306C),
          () => _launchScheme('instagram-stories://share', url)),
      _ShareOptionData('📱', '인스타그램\nDM', const Color(0xFFC13584),
          () => _launchScheme('instagram://direct-inbox', url)),
      _ShareOptionData('💌', '문자', const Color(0xFF34C759), () => _shareSms(text)),
      _ShareOptionData('✉️', '이메일', const Color(0xFF4A90D9), () => _shareEmail(title, text)),
      _ShareOptionData('⋯', '더보기', const Color(0xFFB0B4BC), () => _shareMore(url)),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text('공유하기',
                style: TextStyle(fontFamily: 'SeoulHangang', fontSize: 17, fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              childAspectRatio: 0.82,
              children: [for (final option in options) _ShareOptionTile(option)],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareOptionData {
  final String emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;
  _ShareOptionData(this.emoji, this.label, this.color, this.onTap);
}

class _ShareOptionTile extends StatelessWidget {
  final _ShareOptionData data;
  const _ShareOptionTile(this.data);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.pop(context);
        data.onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: data.color, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(data.emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(height: 6),
          Text(
            data.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 11.5, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}
