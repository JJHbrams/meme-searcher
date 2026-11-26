import 'package:material_ui/material_ui.dart';

class ConchNavIcon extends StatelessWidget {
  const ConchNavIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 24;
    final color = theme.color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ConchOutline(
          color.withValues(alpha: color.a * (theme.opacity ?? 1)),
        ),
      ),
    );
  }
}

class _ConchOutline extends CustomPainter {
  const _ConchOutline(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Keep the swept-back shell, diagonal opening and grip of the app icon.
    canvas.drawPath(
      Path()
        ..moveTo(4, 4)
        ..cubicTo(6.8, 0.8, 13.5, 1.2, 18.5, 3.7)
        ..cubicTo(19.6, 4.3, 20.2, 5.7, 20, 6.9)
        ..cubicTo(22.8, 8, 23, 11, 21.1, 12.5)
        ..cubicTo(20.3, 15, 22.1, 17.5, 21.6, 20.5)
        ..cubicTo(21.3, 22.2, 19, 22.2, 16.1, 21.6)
        ..cubicTo(11.4, 20.8, 8.9, 19.3, 7, 17)
        ..cubicTo(5.5, 17, 4.3, 15, 4.7, 13.5)
        ..cubicTo(2.7, 12.6, 2.4, 10.6, 3.4, 9)
        ..cubicTo(2.1, 7.7, 2.6, 5.6, 4, 4)
        ..close(),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(11, 6.5)
        ..cubicTo(13.8, 8, 17.3, 11.5, 18, 15.3)
        ..quadraticBezierTo(18.4, 17, 17.7, 18.6)
        ..cubicTo(14, 17.1, 10.5, 13.6, 9.8, 10.4)
        ..quadraticBezierTo(9.4, 8.1, 11, 6.5)
        ..close()
        ..moveTo(8.9, 14.9)
        ..quadraticBezierTo(8.7, 16.9, 10.7, 19.5)
        ..moveTo(11, 16.1)
        ..quadraticBezierTo(11.4, 19, 13.4, 20.8),
      stroke,
    );
    canvas.drawCircle(const Offset(19.9, 9.7), 0.9, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ConchOutline oldDelegate) => oldDelegate.color != color;
}
