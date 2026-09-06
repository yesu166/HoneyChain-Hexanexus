import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TimelineStep {
  final String title;
  final String subtitle;
  final bool done;
  final IconData icon;
  const TimelineStep({required this.title, required this.subtitle, required this.done, this.icon = Icons.check_circle});
}

/// Vertical traceability / journey timeline.
class JourneyTimeline extends StatelessWidget {
  const JourneyTimeline({super.key, required this.steps});

  final List<TimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          _StepItem(step: steps[i]),
          if (i < steps.length - 1) _Line(done: steps[i].done),
        ],
      ],
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({required this.step});
  final TimelineStep step;

  @override
  Widget build(BuildContext context) {
    final color = step.done ? AppTheme.green : AppTheme.grey.withValues(alpha: 0.5);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: (step.done ? AppTheme.green : AppTheme.grey).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(step.done ? step.icon : Icons.circle_outlined, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.title, style: TextStyle(fontWeight: FontWeight.w700, color: step.done ? null : Colors.black45)),
              Text(step.subtitle, style: const TextStyle(color: Colors.black54, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.done});
  final bool done;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 16),
      width: 2,
      height: 26,
      color: done ? AppTheme.green.withValues(alpha: 0.4) : AppTheme.grey.withValues(alpha: 0.25),
    );
  }
}
