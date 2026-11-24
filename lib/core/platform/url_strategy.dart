import 'url_strategy_io.dart'
    if (dart.library.js_interop) 'url_strategy_web.dart' as impl;

/// Configures the URL strategy for Flutter web so users can navigate to paths
/// like `/admin` without `#` (hash-routing).
void configureUrlStrategy() {
  impl.configureUrlStrategy();
}
