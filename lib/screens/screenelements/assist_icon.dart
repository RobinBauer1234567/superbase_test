import 'package:flutter/material.dart';

/// Monochromes Assist-Symbol: Fußballschuh mit Bewegungslinien.
///
/// Absichtlich als CustomPainter umgesetzt, damit das Icon auf allen
/// Plattformen identisch aussieht und nicht von Emoji-Fonts abhängt.
class AssistIcon extends StatelessWidget {
  final double size;
  final Color color;

  const AssistIcon({
    super.key,
    this.size = 18,
    this.color = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Vorlage',
      image: true,
      child: SizedBox(
        width: size * 1.4,
        height: size,
        child: CustomPaint(
          painter: _AssistBootPainter(color),
        ),
      ),
    );
  }
}

class _AssistBootPainter extends CustomPainter {
  final Color color;

  const _AssistBootPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 28.0;
    final sy = size.height / 20.0;

    Offset p(double x, double y) => Offset(x * sx, y * sy);

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * sy
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Bewegungslinien – angelehnt an Entwurf 12.
    canvas.drawLine(p(0.8, 8.0), p(6.0, 8.0), stroke);
    canvas.drawLine(p(1.8, 12.0), p(7.0, 12.0), stroke);
    canvas.drawLine(p(3.2, 16.0), p(8.0, 16.0), stroke);

    // Schuh-Silhouette.
    final boot = Path()
      ..moveTo(p(7.0, 12.7).dx, p(7.0, 12.7).dy)
      ..lineTo(p(9.0, 11.4).dx, p(9.0, 11.4).dy)
      ..lineTo(p(10.0, 7.3).dx, p(10.0, 7.3).dy)
      ..quadraticBezierTo(
        p(10.5, 4.6).dx,
        p(10.5, 4.6).dy,
        p(12.8, 4.0).dx,
        p(12.8, 4.0).dy,
      )
      ..quadraticBezierTo(
        p(14.0, 4.0).dx,
        p(14.0, 4.0).dy,
        p(15.0, 6.3).dx,
        p(15.0, 6.3).dy,
      )
      ..lineTo(p(18.0, 8.3).dx, p(18.0, 8.3).dy)
      ..quadraticBezierTo(
        p(21.0, 10.0).dx,
        p(21.0, 10.0).dy,
        p(25.0, 11.2).dx,
        p(25.0, 11.2).dy,
      )
      ..quadraticBezierTo(
        p(27.2, 11.9).dx,
        p(27.2, 11.9).dy,
        p(27.0, 14.1).dx,
        p(27.0, 14.1).dy,
      )
      ..quadraticBezierTo(
        p(26.7, 16.0).dx,
        p(26.7, 16.0).dy,
        p(23.8, 16.0).dx,
        p(23.8, 16.0).dy,
      )
      ..lineTo(p(10.2, 16.0).dx, p(10.2, 16.0).dy)
      ..quadraticBezierTo(
        p(7.8, 15.8).dx,
        p(7.8, 15.8).dy,
        p(7.0, 14.2).dx,
        p(7.0, 14.2).dy,
      )
      ..close();

    canvas.drawPath(boot, fill);

    // Kleine Stollen.
    final studWidth = 1.9 * sx;
    final studHeight = 2.0 * sy;
    for (final x in <double>[10.2, 15.0, 21.1, 24.3]) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x * sx, 15.2 * sy, studWidth, studHeight),
        Radius.circular(0.7 * sy),
      );
      canvas.drawRRect(rect, fill);
    }

    // Weiße Schnürsenkel als Negativdetail.
    final lace = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25 * sy
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(p(13.4, 7.0), p(15.6, 8.0), lace);
    canvas.drawLine(p(14.4, 8.5), p(16.6, 9.5), lace);
    canvas.drawLine(p(15.6, 10.0), p(17.7, 10.9), lace);
  }

  @override
  bool shouldRepaint(covariant _AssistBootPainter oldDelegate) =>
      oldDelegate.color != color;
}
