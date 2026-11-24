import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the web build compiling.
///
/// `dart:io` does not exist in browsers, and `dart:html` / `dart:js` do not
/// exist under WASM or on mobile. Any of them imported from shared code breaks
/// a platform. They are only allowed in the platform halves of a conditional
/// import bridge (`*_io.dart` / `*_web.dart`).
void main() {
  test('platform-only libraries stay inside conditional-import bridges', () {
    final offenders = <String>[];
    final banned = {
      'dart:io': RegExp(r'_io\.dart$'),
      'dart:html': null, // deprecated and not WASM-safe: use package:web
      'dart:js': null, // ditto: use dart:js_interop
      'dart:js_util': null,
      'dart:ffi': RegExp(r'_io\.dart$'),
      'package:web/': RegExp(r'_web\.dart$'),
      'dart:js_interop': RegExp(r'_web\.dart$'),
    };

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      final source = entity.readAsStringSync();
      banned.forEach((library, allowedIn) {
        // `dart:` libraries must match exactly ('dart:js' is not
        // 'dart:js_interop'); `package:web/` matches any file in the package.
        final end = library.endsWith('/') ? '' : "'";
        final import = RegExp(
            "^\\s*(import|export)\\s+'${RegExp.escape(library)}$end",
            multiLine: true);
        if (import.hasMatch(source) &&
            (allowedIn == null || !allowedIn.hasMatch(path))) {
          offenders.add('$path imports $library');
        }
      });
    }

    expect(offenders, isEmpty,
        reason: 'Move platform code behind lib/core/platform/ bridges.');
  });
}
