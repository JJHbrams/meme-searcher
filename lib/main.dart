import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'core/device_app_services.dart';
import 'core/meme_mcp_bridge.dart';
import 'core/windows_update_installer.dart';
import 'platform/media_actions.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final services = DeviceAppServices();
  runApp(MemeSearcherApp(services: services, actions: MediaActions()));
  if (Platform.isWindows) {
    unawaited(
      MemeMcpBridge.start(services).then<void>((_) {}, onError: (Object _) {}),
    );
  }
  unawaited(cleanCompletedWindowsUpdates());
}
