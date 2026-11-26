import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app/app_model.dart';
import 'app/debug_args.dart';
import 'app/feature_registry.dart';
import 'app/storage.dart';
import 'app/truver_app.dart';

export 'app/test_app.dart' show TruverTestApp;
export 'app/truver_app.dart' show TruverApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Phone layouts are portrait (landscape boards come with the tablet / desktop layouts).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0x00000000),
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  ));
  final store = await PrefsStore.open();
  final args = await DebugArgs.load();
  registerFeatures();
  final model = AppModel(store: store, args: args);
  await model.audio.refreshMicPermission();
  runApp(TruverApp(model: model));
}
