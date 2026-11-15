import 'package:material_ui/material_ui.dart';

import 'core/device_app_services.dart';
import 'platform/media_actions.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MemeSearcherApp(services: DeviceAppServices(), actions: MediaActions()),
  );
}
