import 'package:edu237/core/platform/platform_info.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlatformInfo.pushPlatformFor', () {
    test('web builds report web, whatever OS the browser runs on', () {
      for (final platform in TargetPlatform.values) {
        expect(
          PlatformInfo.pushPlatformFor(isWeb: true, platform: platform),
          'web',
        );
      }
    });

    test('native mapping is unchanged from the shipped mobile app', () {
      expect(
        PlatformInfo.pushPlatformFor(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        'ios',
      );
      expect(
        PlatformInfo.pushPlatformFor(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        'android',
      );
    });
  });

  test('isNativeMobile follows defaultTargetPlatform off the web', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(PlatformInfo.isNativeMobile, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(PlatformInfo.isNativeMobile, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
}
