import 'package:material_ui/material_ui.dart';

import '../core/app_services.dart';
import '../platform/media_actions.dart';
import 'app_theme.dart';
import 'screens/search_screen.dart';

class MemeSearcherApp extends StatelessWidget {
  const MemeSearcherApp({
    required this.services,
    required this.actions,
    super.key,
  });

  final AppServices services;
  final MediaActions actions;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Meme Snatcher',
    debugShowCheckedModeBanner: false,
    theme: MemeTheme.build(),
    home: SearchScreen(services: services, actions: actions),
  );
}
