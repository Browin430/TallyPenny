import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

import '../core/icons/app_icons.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

enum _ImageChoice { crop, original }

/// 选择图片后让用户决定裁剪或保留原图；取消时返回 null。
Future<String?> preparePickedImage(
  BuildContext context,
  String sourcePath, {
  String cropTitle = '裁剪图片',
}) async {
  final s = context.colors;
  final choice = await showModalBottomSheet<_ImageChoice>(
    context: context,
    backgroundColor: s.surface,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('处理图片', style: AppText.title(s.ink)),
            const SizedBox(height: 6),
            Text('可裁掉无关区域，只保留关键信息。', style: AppText.sub(s.inkSecondary)),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(FMIcons.edit, color: s.accent),
              title: const Text('裁剪后使用'),
              onTap: () => Navigator.of(sheetContext).pop(_ImageChoice.crop),
            ),
            ListTile(
              leading: Icon(FMIcons.photo, color: s.inkSecondary),
              title: const Text('使用原图'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ImageChoice.original),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null) return null;
  if (choice == _ImageChoice.original) return sourcePath;

  final cropped = await ImageCropper().cropImage(
    sourcePath: sourcePath,
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 92,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: cropTitle,
        toolbarColor: s.ink,
        toolbarWidgetColor: s.bg,
        activeControlsWidgetColor: s.accent,
        lockAspectRatio: false,
      ),
      IOSUiSettings(
        title: cropTitle,
        doneButtonTitle: '完成',
        cancelButtonTitle: '取消',
      ),
    ],
  );
  return cropped?.path;
}
