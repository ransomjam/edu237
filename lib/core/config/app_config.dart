/// Supabase configuration read from compile-time --dart-define values.
///
/// To run the app locally:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://your-project.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=your-anon-key
///
/// To run tests without a real backend, these values are intentionally
/// left as empty strings — the AuthService mock replaces the real client.
///
/// Never hard-code real credentials here.
abstract final class AppConfig {
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// True when Supabase credentials have been provided at compile time.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
