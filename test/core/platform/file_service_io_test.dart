import 'dart:io';
import 'dart:typed_data';

import 'package:edu237/core/platform/file_service.dart';
import 'package:edu237/core/platform/file_service_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('camiva_fs_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the VM build resolves the dart:io implementation', () {
    expect(FileService.instance, isA<IoFileService>());
  });

  test('saveBytes writes the bytes and returns the path', () async {
    final saved = await IoFileService(dir).saveBytes(
      bytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'receipt.pdf',
    );

    expect(saved.isDownload, isFalse);
    expect(File(saved.location).readAsBytesSync(), [1, 2, 3]);
  });

  test('a hostile file name cannot escape the target directory', () async {
    final saved = await IoFileService(dir).saveBytes(
      bytes: Uint8List(0),
      fileName: '../../etc/passwd',
    );

    expect(File(saved.location).parent.path, dir.path);
  });

  test('sanitizeFileName', () {
    expect(sanitizeFileName('a/b\\c:d.txt'), 'a_b_c_d.txt');
    expect(sanitizeFileName('..hidden'), 'hidden');
    expect(sanitizeFileName('   '), 'download');
  });
}
