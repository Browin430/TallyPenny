import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/utils/id_gen.dart';

/// 将用户选择的发票复制到 App 私有文档目录，避免相册/临时文件失效。
class InvoiceFileStorage {
  const InvoiceFileStorage();

  Future<String> persist({
    required String sourcePath,
    required String originalName,
  }) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'invoices'));
    await directory.create(recursive: true);
    final sourceExtension = p.extension(sourcePath).toLowerCase();
    final originalExtension = p.extension(originalName).toLowerCase();
    final extension = sourceExtension.isNotEmpty
        ? sourceExtension
        : (originalExtension.isNotEmpty ? originalExtension : '.jpg');
    final target = p.join(directory.path, '${IdGen.newId()}$extension');
    await File(sourcePath).copy(target);
    return target;
  }

  Future<void> deleteIfPresent(String storedPath) async {
    final file = File(storedPath);
    if (await file.exists()) await file.delete();
  }
}
