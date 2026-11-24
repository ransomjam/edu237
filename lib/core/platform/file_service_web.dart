import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_service.dart';

/// Selected by the conditional import in `file_service.dart` for browser
/// builds (JS and WASM). Uses `package:web`, never the deprecated `dart:html`,
/// so it stays WASM-compatible.
FileService createFileService() => const WebFileService();

/// Hands bytes to the browser as a download via a temporary object URL.
class WebFileService implements FileService {
  const WebFileService();

  @override
  Future<SavedFile> saveBytes({
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    final name = sanitizeFileName(fileName);
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);

    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = name
      ..style.display = 'none';
    web.document.body!.append(anchor);
    anchor.click();
    anchor.remove();

    // Revoking synchronously can cancel the download in some browsers, so the
    // URL is released once the click has been processed.
    Timer(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));

    return SavedFile(location: name, isDownload: true);
  }
}
