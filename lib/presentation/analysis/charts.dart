import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';
import '../../state/app_providers.dart';

/// 环形图（消费结构）。进入页面平滑展开，点击扇区选中。
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.totalCents,
    required this.selectedIndex,
    required this.onSelect,
    required this.centerTitle,
    required this.centerValue,
    required this.centerValueColor,
    this.size = 210,
  });

  final List<CategorySlice> slices;
  final int totalCents;
  final int? selectedIndex;
  final ValueChanged<int?> onSelect;
  final String centerTitle;
  final String centerValue;
  final Color centerValueColor;
  final double size;

  static const _strokeBase = 26.0;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => Opacity(
        opacity: Curves.easeOut.transform(t),
        child: Transform.scale(
          scale: 0.94 + 0.06 * t,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _handleTap(d.localPosition, t),
            child: CustomPaint(
              size: Size.square(size),
              painter: _DonutPainter(
                slices: slices,
                total: totalCents,
                progress: t,
                selectedIndex: selectedIndex,
                strokeBase: _strokeBase,
              ),
              child: SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(centerTitle, style: AppText.caption(s0(context))),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 34),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            centerValue,
                            style: AppText.amountM(centerValueColor)
                                .copyWith(fontSize: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 环形图中心副标题颜色由调用方主题决定，这里取上下文主题默认。
  static Color s0(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);

  void _handleTap(Offset pos, double progress) {
    if (slices.isEmpty || totalCents <= 0) return;
    final center = Offset(size / 2, size / 2);
    final vector = pos - center;
    final radius = vector.distance;
    final outer = size / 2;
    final inner = outer - _strokeBase - 6;
    if (radius < inner || radius > outer) {
      onSelect(null);
      return;
    }
    var angle = math.atan2(vector.dy, vector.dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;

    var start = 0.0;
    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i].cents / totalCents * 2 * math.pi * progress;
      final end = start + sweep;
      if (angle >= start && angle < end) {
        onSelect(selectedIndex == i ? null : i);
        return;
      }
      start = end;
    }
    onSelect(null);
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.total,
    required this.progress,
    required this.selectedIndex,
    required this.strokeBase,
  });

  final List<CategorySlice> slices;
  final int total;
  final double progress;
  final int? selectedIndex;
  final double strokeBase;

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty || total <= 0) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeBase
        ..color = const Color(0x14808080);
      canvas.drawArc(
        Offset.zero & size,
        0,
        2 * math.pi,
        false,
        paint,
      );
      return;
    }

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeBase / 2 - 2;
    const gap = 0.024; // 扇区间隙（弧度）
    var start = -math.pi / 2;

    for (var i = 0; i < slices.length; i++) {
      final fraction = slices[i].cents / total;
      final sweep = fraction * 2 * math.pi * progress;
      final selected = selectedIndex == i;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? strokeBase + 5 : strokeBase
        ..color = slices[i].category.color.withValues(
              alpha: selectedIndex == null || selected ? 1.0 : 0.35,
            )
        ..strokeCap = StrokeCap.round;

      final useSweep = math.max(sweep - gap * progress, 0.001);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        useSweep,
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.total != total ||
      !identical(oldDelegate.slices, slices);
}

/// 六个月收支趋势折线图。
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.trend,
    required this.incomeColor,
    required this.expenseColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<MonthTrendPoint> trend;
  final Color incomeColor;
  final Color expenseColor;
  final Color gridColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    if (trend.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: 150,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendPainter(
              trend: trend,
              incomeColor: incomeColor,
              expenseColor: expenseColor,
              gridColor: gridColor,
            ),
          ),
        ),
        const SizedBox(height: FMSpacing.s),
        Row(
          children: [
            for (final p in trend)
              Expanded(
                child: Text(
                  p.label,
                  textAlign: TextAlign.center,
                  style: AppText.caption(labelColor),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.trend,
    required this.incomeColor,
    required this.expenseColor,
    required this.gridColor,
  });

  final List<MonthTrendPoint> trend;
  final Color incomeColor;
  final Color expenseColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final maxVal = trend
        .expand((p) => [p.income, p.expense])
        .fold(1, (m, v) => v > m ? v : m)
        .toDouble();

    // 网格线。
    final gridPaint = Paint()
      ..strokeWidth = 0.5
      ..color = gridColor;
    for (final f in const [0.25, 0.5, 0.75]) {
      final y = size.height * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    Offset pointAt(int i, int cents) {
      final x = size.width * (trend.length == 1 ? 0.5 : i / (trend.length - 1));
      final y = size.height - (cents / maxVal) * (size.height - 10) - 5;
      return Offset(x, y);
    }

    void drawLine(int Function(MonthTrendPoint) pick, Color color) {
      final points = [
        for (var i = 0; i < trend.length; i++) pointAt(i, pick(trend[i])),
      ];
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        final prev = points[i - 1];
        final cur = points[i];
        final mid = Offset((prev.dx + cur.dx) / 2, (prev.dy + cur.dy) / 2);
        path.cubicTo(mid.dx, prev.dy, mid.dx, cur.dy, cur.dx, cur.dy);
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawPath(path, paint);

      // 端点。
      for (final p in points) {
        canvas.drawCircle(p, 3, Paint()..color = color);
      }
    }

    drawLine((p) => p.income, incomeColor);
    drawLine((p) => p.expense, expenseColor);
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      !identical(oldDelegate.trend, trend);
}
