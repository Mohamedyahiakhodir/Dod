import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes exports to the app cache and offers the share sheet / a "save as" dialog.
class ExportService {
  static String safeName(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();

  static Future<void> share(Uint8List bytes, String filename, String mime) async {
    final XFile x;
    if (kIsWeb) {
      x = XFile.fromData(bytes, name: filename, mimeType: mime);
    } else {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$filename');
      await f.writeAsBytes(bytes, flush: true);
      x = XFile(f.path, mimeType: mime);
    }
    await SharePlus.instance.share(ShareParams(files: [x], subject: filename));
  }

  /// Opens the system "save as" dialog. Returns true when the file was saved.
  static Future<bool> saveAs(Uint8List bytes, String filename, String mime) async {
    final r = await FilePicker.saveFile(dialogTitle: filename, fileName: filename, bytes: bytes, mimeType: mime);
    return r != null;
  }
}
