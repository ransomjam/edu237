import 'dart:io';
import 'dart:typed_data';

import 'file_service.dart';

/// Selected by the conditional import in `file_service.dart` on every
/// non-web target. This is the only place `dart:io` file APIs may be used.
FileService createFileService() => IoFileService(Directory.systemTemp);

/// Writes files under [directory] (the system temp dir by default, which
/// needs no extra plugin such as `path_provider`).
class IoFileService implements FileService {
  IoFileService(this.directory);

  final Directory directory;

  @override
  Future<SavedFile> saveBytes({
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    final file = File(
      '${directory.path}${Platform.pathSeparator}${sanitizeFileName(fileName)}',
    );
    await file.writeAsBytes(bytes, flush: true);
    return SavedFile(location: file.path, isDownload: false);
  }
}
