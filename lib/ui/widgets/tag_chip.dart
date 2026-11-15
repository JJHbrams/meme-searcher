import 'package:material_ui/material_ui.dart';

class TagChip extends StatelessWidget {
  const TagChip({required this.label, required this.onDelete, super.key});

  final String label;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => InputChip(
    label: Text('#$label'),
    onDeleted: onDelete,
    backgroundColor: const Color(0xff33402a),
    labelStyle: const TextStyle(color: Color(0xffdcffc0)),
    deleteIconColor: const Color(0xffdcffc0),
    side: const BorderSide(color: Color(0xff526443)),
    visualDensity: VisualDensity.compact,
  );
}
