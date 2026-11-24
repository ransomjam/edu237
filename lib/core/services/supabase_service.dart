import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

/// Initialises and exposes the Supabase client.
///
/// Call [SupabaseService.initialize] once in [main] before [runApp].
/// Access the client via [SupabaseService.client].
abstract final class SupabaseService {
  static Future<void> initialize() async {
    if (!AppConfig.isConfigured) {
      // Credentials not provided — skip initialisation.
      // The app will show a configuration error state.
      return;
    }
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
