import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Stand-in QR pattern derived deterministically from a seed string.
///
/// This is a visual placeholder until the backend issues real QR codes;
/// it is intentionally labelled as such wherever it is used.
class QrCodePlaceholder extends StatelessWidget {
  const QrCodePlaceholder({super.key, required this.seed, this.size = 168});

  final String seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: CustomPaint(
        size: Size.square(size - 20),
        painter: _QrPainter(seed),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.seed);

  static const int _n = 21;
  final String seed;

  @override
  void paint(Canvas canvas, Size size) {
    final module = size.width / _n;
    final ink = Paint()..color = AppTheme.ink;

    final rng = Random(seed.hashCode);
    for (var y = 0; y < _n; y++) {
      for (var x = 0; x < _n; x++) {
        if (_finderZone(x, y)) continue;
        if (rng.nextBool()) {
          canvas.drawRect(
            Rect.fromLTWH(x * module, y * module, module, module),
            ink,
          );
        }
      }
    }

    // Finder patterns in the three corners (7x7).
    for (final origin in const [
      (0, 0),
      (_n - 7, 0),
      (0, _n - 7),
    ]) {
      final (fx, fy) = origin;
      _drawFinder(canvas, fx, fy, module, ink);
    }
  }

  bool _finderZone(int x, int y) {
    return (x < 7 && y < 7) ||
        (x >= _n - 7 && y < 7) ||
        (x < 7 && y >= _n - 7);
  }

  void _drawFinder(
    Canvas canvas,
    int fx,
    int fy,
    double module,
    Paint ink,
  ) {
    canvas.drawRect(
      Rect.fromLTWH(fx * module, fy * module, 7 * module, 7 * module),
      ink,
    );
    canvas.drawRect(
      Rect.fromLTWH((fx + 1) * module, (fy + 1) * module, 5 * module, 5 * module),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromLTWH((fx + 2) * module, (fy + 2) * module, 3 * module, 3 * module),
      ink,
    );
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.seed != seed;
}