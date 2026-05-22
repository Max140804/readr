import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class HolePainter extends CustomPainter {
  final double holeRadius;

  HolePainter(this.holeRadius);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Color(0xFFFECD85);

    final path = Path()
      ..addOval(Rect.fromCircle(
          center: size.center(Offset.zero),
          radius: size.width / 2))
      ..addOval(Rect.fromCircle(
          center: size.center(Offset.zero),
          radius: holeRadius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}