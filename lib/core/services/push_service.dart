import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../platform/platform_info.dart';

/// Registers this device to receive Camiva push notifications.
///
/// The whole job is: ask permission, get the FCM token, and store it against
/// the signed-in user so `send-reminder` knows where to push. Everything else
/// about a reminder — what it says, whether it was delivered — is decided
/// server-side.
///
/// Nothing here ever claims a notification was delivered. A stored token means
/// a device is reachable, not that anything reached it.
///
/// Every failure is swallowed deliberately. Push is an enhancement: a phone
/// that refuses permission, an emulator without Google Play services, or a
/// project with no Firebase config must not stop someone using the app.
abstract final class PushService {
  static bool _initialised = false;

  /// Sets up Firebase once, at startup. Safe to call when Firebase is not
  /// configured — it simply does nothing.
  static Future<void> initialise() async {
    if (_initialised) return;
    // Web push is not configured yet: Firebase on the web needs explicit
    // FirebaseOptions (there is no google-services.json), a
    // `web/firebase-messaging-sw.js` service worker and a VAPID key for
    // getToken(). Without them initializeApp() throws, so skip it outright
    // rather than relying on the catch below. `register_push_token` already
    // accepts 'web' (see PlatformInfo.pushPlatform) for when this is enabled.
    if (PlatformInfo.isWeb) {
      if (kDebugMode) debugPrint('[camiva] push not configured for web');
      return;
    }
    try {
      await Firebase.initializeApp();
      _initialised = true;
    } catch (error) {
      // No google-services.json, or a project without Firebase. The app runs
      // exactly as before; only push is unavailable.
      if (kDebugMode) debugPrint('[camiva] push unavailable: $error');
    }
  }

  /// Asks for notification permission and stores this device's token against
  /// [client]'s signed-in user. Call after sign-in.
  ///
  /// Returns true when a token was stored — used only for diagnostics, never
  /// to tell a user their notifications are working.
  static Future<bool> registerDevice(SupabaseClient client) async {
    if (!_initialised) return false;
    final user = client.auth.currentUser;
    if (user == null) return false;

    try {
      final messaging = FirebaseMessaging.instance;

      // Android 13+ and iOS both require an explicit grant. A refusal is a
      // normal outcome, not an error.
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        if (kDebugMode) debugPrint('[camiva] push permission denied');
        return false;
      }

      final token = await messaging.getToken();
      if (token == null) return false;

      await _store(client, token);

      // A token can be reissued at any time; the old one silently stops
      // working, so the new one has to be stored when it arrives.
      messaging.onTokenRefresh.listen((refreshed) {
        final current = client.auth.currentUser;
        if (current != null) _store(client, refreshed);
      });

      return true;
    } catch (error) {
      if (kDebugMode) debugPrint('[camiva] push registration failed: $error');
      return false;
    }
  }

  /// Removes this device's token. Called on sign-out so the next person to use
  /// the phone does not receive the previous user's reminders.
  static Future<void> unregisterDevice(SupabaseClient client) async {
    if (!_initialised) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await client.rpc('forget_push_token', params: {'p_token': token});
    } catch (error) {
      if (kDebugMode) debugPrint('[camiva] push cleanup failed: $error');
    }
  }

  static Future<void> _store(SupabaseClient client, String token) async {
    try {
      // Registered through a function rather than a direct upsert. A phone used
      // by two accounts hits a row owned by the previous user, which RLS
      // correctly refuses to update; the function reassigns the device to
      // whoever is signed in now.
      await client.rpc('register_push_token', params: {
        'p_token': token,
        'p_platform': PlatformInfo.pushPlatform,
      });
    } catch (error) {
      if (kDebugMode) debugPrint('[camiva] could not store push token: $error');
    }
  }
}
