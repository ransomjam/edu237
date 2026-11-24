import 'package:flutter/foundation.dart';

/// Platform questions answered without `dart:io`.
///
/// `Platform.isAndroid` and friends live in `dart:io`, which does not exist on
/// the web: importing it breaks the web build. Everything here is derived from
/// [kIsWeb] and [defaultTargetPlatform], which compile on every target.
///
/// Note that [defaultTargetPlatform] reports the *host OS* on the web too (a
/// browser on an Android phone reports [TargetPlatform.android]), so always
/// check [kIsWeb] first when the question is "can I use a native plugin?".
abstract final class PlatformInfo {
  /// True when running in a browser (JS or WASM build).
  static bool get isWeb => kIsWeb;

  /// True for the native mobile apps, false for the web build on a phone.
  static bool get isNativeMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// The `p_platform` value `register_push_token` expects for this build.
  static String get pushPlatform =>
      pushPlatformFor(isWeb: kIsWeb, platform: defaultTargetPlatform);

  /// Pure form of [pushPlatform], so tests can cover the web branch ([kIsWeb]
  /// is a compile-time constant and cannot be overridden in a VM test).
  ///
  /// Native builds keep the exact mapping the app shipped with; the backend
  /// accepts only `android`, `ios` and `web`.
  @visibleForTesting
  static String pushPlatformFor({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (isWeb) return 'web';
    return platform == TargetPlatform.iOS ? 'ios' : 'android';
  }
}
