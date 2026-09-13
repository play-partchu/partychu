import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import 'package:party_app/utils/local_media.dart';

/// 썸네일 이미지를 표시하는 위젯.
/// imageFile(로컬) 또는 imageUrl(네트워크) 중 하나를 지정합니다.
class PartyThumbnailWidget extends StatelessWidget {
  final String? imageUrl;
  final XFile? imageFile;
  final BorderRadius borderRadius;
  final Widget? placeholder;

  const PartyThumbnailWidget({
    super.key,
    this.imageUrl,
    this.imageFile,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        Widget img;
        if (imageFile != null) {
          img = LocalMedia.image(
            imageFile!,
            fit: BoxFit.cover,
            width: w,
            height: h,
          );
        } else if (imageUrl?.isNotEmpty == true) {
          img = Image.network(
            imageUrl!,
            fit: BoxFit.cover,
            width: w,
            height: h,
            errorBuilder: (_, _, _) => _placeholder(w, h),
          );
        } else {
          return ClipRRect(
            borderRadius: borderRadius,
            child: SizedBox(width: w, height: h, child: _placeholder(w, h)),
          );
        }

        return ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox(width: w, height: h, child: img),
        );
      },
    );
  }

  Widget _placeholder(double w, double h) =>
      placeholder ??
      Container(
        width: w,
        height: h,
        color: const Color(0xFFFFEAF1),
        child: const Center(
          child: Icon(Icons.image_outlined, size: 28, color: Color(0xFFFFB8CF)),
        ),
      );
}
