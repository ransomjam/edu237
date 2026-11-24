import 'package:flutter/material.dart';
import 'core/platform/url_strategy.dart';
import 'core/services/push_service.dart';
import 'core/services/supabase_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureUrlStrategy();
  await SupabaseService.initialize();
  // Push is optional: this does nothing when Firebase is not configured.
  await PushService.initialise();
  runApp(const CamivaApp());
}
