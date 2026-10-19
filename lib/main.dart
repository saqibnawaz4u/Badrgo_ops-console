import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:http/http.dart' as http;

import 'app/app.dart';
import 'core/presentation/brand_font.dart';
import 'app/config.dart';
import 'app/di.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean URLs (/trips/trp_123) so deep links can be shared and reloaded.
  usePathUrlStrategy();
  // Brand typeface from Fontshare; falls back to the default font if it
  // cannot be loaded within a few seconds.
  await BrandFont.load(http.Client());
  final deps = await AppDependencies.create(AppConfig.fromEnvironment());
  deps.auth.add(const AuthStarted());
  runApp(OpsConsoleApp(deps: deps));
}
