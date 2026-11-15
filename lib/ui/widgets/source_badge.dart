import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';

class SourceBadge extends StatelessWidget {
  const SourceBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: MemeTheme.surfaceRaised.withValues(alpha: .94),
      border: Border.all(color: MemeTheme.border),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(
        label,
        style: const TextStyle(
          color: MemeTheme.text,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
