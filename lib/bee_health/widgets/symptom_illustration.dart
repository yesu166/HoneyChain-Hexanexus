import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A small, deterministic, dependency-free illustration of a bee-health
/// symptom, drawn locally per feature. Distinct for each feature so the
/// beekeeper can identify the exact symptom being asked about.
///
/// This replaces any remote/binary image asset — nothing is fetched from the
/// network and the drawing is stable across platforms.
class SymptomIllustration extends StatelessWidget {
  const SymptomIllustration({super.key, required this.featureId});

  final String featureId;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 168,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.tint(featureColor),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: Center(
        child: SizedBox(
          width: 168,
          height: 168,
          child: CustomPaint(
            painter: _SymptomPainter(featureId: featureId, color: featureColor),
          ),
        ),
      ),
    );
  }

  Color get featureColor {
    return switch (featureId) {
      'brood_spotted_comb' => AppTheme.orangeDark,
      'brood_larvae_yellow_curled' => AppTheme.honeyDark,
      'brood_sour_odor' => AppTheme.honey,
      'adult_crawling_unable_to_fly' => AppTheme.greenDark,
      'adult_k_wing' => AppTheme.teal,
      'adult_scattered_clusters' => AppTheme.green,
      'adult_yellow_fecal_spots' => AppTheme.honeyDark,
      'adult_swollen_black_abdomen' => AppTheme.ink,
      _ => AppTheme.orangeDark,
    };
  }
}

/// Draws one icon per symptom using basic canvas primitives (circles, lines,
/// rects). The shapes are intentionally simple and readable at small sizes.
class _SymptomPainter extends CustomPainter {
  const _SymptomPainter({required this.featureId, required this.color});

  final String featureId;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    final soft = Paint()..color = color.withValues(alpha: 0.22);

    switch (featureId) {
      case 'brood_spotted_comb':
        _drawComb(canvas, c, stroke, soft, dotted: true);
      case 'brood_larvae_yellow_curled':
        _drawLarvae(canvas, c, stroke, soft);
      case 'brood_sour_odor':
        _drawOdor(canvas, c, stroke, soft);
      case 'adult_crawling_unable_to_fly':
        _drawCrawling(canvas, c, stroke, fill);
      case 'adult_k_wing':
        _drawKWing(canvas, c, stroke, fill);
      case 'adult_scattered_clusters':
        _drawScattered(canvas, c, fill, soft);
      case 'adult_yellow_fecal_spots':
        _drawFecal(canvas, c, fill);
      case 'adult_swollen_black_abdomen':
        _drawSwollen(canvas, c, stroke, fill);
      default:
        _drawComb(canvas, c, stroke, soft, dotted: false);
    }
  }

  void _hex(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i - math.pi / 6;
      final p =
          center + Offset(r * math.cos(angle), r * math.sin(angle));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawComb(
    Canvas canvas,
    Offset c,
    Paint stroke,
    Paint soft, {
    required bool dotted,
  }) {
    const r = 34.0;
    final cells = <Offset>[
      Offset(0, 0),
      Offset(r * 1.4, 0),
      Offset(-r * 1.4, 0),
      Offset(-r * 0.8, r * 1.3),
      Offset(r * 0.8, r * 1.3),
      Offset(-r * 0.8, -r * 1.3),
      Offset(r * 0.8, -r * 1.3),
    ];
    for (final d in cells) {
      final center = c + Offset(d.dx, d.dy * 0.95);
      _hex(canvas, center, r, soft);
      _hex(canvas, center, r, stroke);
    }
    if (dotted) {
      final dot = Paint()..color = color;
      for (final d in cells) {
        canvas.drawCircle(c + Offset(d.dx, d.dy * 0.95), r * 0.3, dot);
      }
    }
  }

  void _drawLarvae(
    Canvas canvas,
    Offset c,
    Paint stroke,
    Paint soft,
  ) {
    _hex(canvas, c + Offset(0, 8), 34, soft);
    _hex(canvas, c + Offset(0, 8), 34, stroke);
    final curve = Path()
      ..moveTo(c.dx - 20, c.dy + 16)
      ..quadraticBezierTo(c.dx - 14, c.dy - 12, c.dx, c.dy - 4)
      ..quadraticBezierTo(c.dx + 12, c.dy, c.dx, c.dy + 14)
      ..quadraticBezierTo(c.dx - 10, c.dy + 20, c.dx + 2, c.dy + 26);
    canvas.drawPath(curve, stroke);
  }

  void _drawOdor(Canvas canvas, Offset c, Paint stroke, Paint soft) {
    final base = Rect.fromCenter(
      center: c + Offset(0, 24),
      width: 56,
      height: 40,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(base, const Radius.circular(14)),
      soft,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(base, const Radius.circular(14)),
      stroke,
    );
    for (var i = 0; i < 3; i++) {
      final x = c.dx - 16 + i * 16;
      final wave = Path()
        ..moveTo(x, c.dy + 2)
        ..quadraticBezierTo(x - 6, c.dy - 8, x, c.dy - 16)
        ..quadraticBezierTo(x + 6, c.dy - 24, x, c.dy - 32);
      canvas.drawPath(wave, stroke);
    }
  }

  void _drawCrawling(Canvas canvas, Offset c, Paint stroke, Paint fill) {
    final ground = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c + Offset(-30, 34), c + Offset(30, 34), ground);
    _beeBody(canvas, c + Offset(0, 6), stroke, fill, freakWing: false);
    for (final lx in <double>[-12, 0, 12]) {
      canvas.drawLine(
        c + Offset(lx, 16),
        c + Offset(lx, 30),
        stroke,
      );
    }
  }

  void _drawKWing(Canvas canvas, Offset c, Paint stroke, Paint fill) {
    _beeBody(canvas, c + Offset(0, 4), stroke, fill, freakWing: true);
  }

  void _drawScattered(Canvas canvas, Offset c, Paint fill, Paint soft) {
    final pts = <Offset>[
      c + Offset(-30, -20),
      c + Offset(28, -14),
      c + Offset(-4, 2),
      c + Offset(34, 20),
      c + Offset(-32, 24),
    ];
    for (final p in pts) {
      canvas.drawCircle(p, 16, soft);
      _miniBee(canvas, p - Offset(0, 4), fill);
    }
  }

  void _drawFecal(Canvas canvas, Offset c, Paint fill) {
    final panel = Paint()
      ..color = color.withValues(alpha: 0.15);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: 80, height: 80),
        const Radius.circular(12),
      ),
      panel,
    );
    final dot = Paint()..color = color;
    final spots = <Offset>[
      c + Offset(-20, -18),
      c + Offset(14, -22),
      c + Offset(-8, 4),
      c + Offset(22, 16),
      c + Offset(-24, 22),
    ];
    for (final p in spots) {
      canvas.drawCircle(p, 5, dot);
    }
  }

  void _drawSwollen(Canvas canvas, Offset c, Paint stroke, Paint fill) {
    final abdomen = Paint()
      ..color = AppTheme.ink;
    canvas.drawOval(
      Rect.fromCenter(center: c + Offset(14, 6), width: 34, height: 52),
      abdomen,
    );
    canvas.drawCircle(c + Offset(-10, 2), 15, fill);
    final leftWing = Offset(-10, -14);
    final rightWing = Offset(10, -16);
    canvas.drawLine(c + leftWing, c + Offset(-24, -30), stroke);
    canvas.drawLine(c + rightWing, c + Offset(-2, -34), stroke);
  }

  void _beeBody(
    Canvas canvas,
    Offset c,
    Paint stroke,
    Paint fill, {
    required bool freakWing,
  }) {
    canvas.drawOval(
      Rect.fromCenter(center: c + Offset(5, 0), width: 22, height: 30),
      fill,
    );
    canvas.drawCircle(c + Offset(-9, 0), 9, fill);
    final left = Offset(-8, -12);
    final right = Offset(8, -12);
    canvas.drawLine(
      c + left,
      c + (freakWing ? Offset(-22, -30) : Offset(-22, -26)),
      stroke,
    );
    canvas.drawLine(
      c + right,
      c + (freakWing ? Offset(26, -34) : Offset(26, -26)),
      stroke,
    );
  }

  void _miniBee(Canvas canvas, Offset c, Paint fill) {
    canvas.drawOval(
      Rect.fromCenter(center: c + const Offset(3.0, 0.0), width: 16, height: 22),
      fill,
    );
    canvas.drawCircle(c + const Offset(-5.0, 0.0), 6, fill);
  }

  @override
  bool shouldRepaint(covariant _SymptomPainter oldDelegate) =>
      oldDelegate.featureId != featureId || oldDelegate.color != color;
}