/// Small formatting helpers shared by the beekeeper UI.
library;

String formatDate(DateTime t, {bool withTime = false}) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final date = '${t.day} ${months[t.month - 1]} ${t.year}';
  if (!withTime) return date;
  String two(int v) => v.toString().padLeft(2, '0');
  return '$date, ${two(t.hour)}:${two(t.minute)}';
}

/// Mass formatter for reading timestamps.
String formatKg(double kg) {
  if (kg == kg.roundToDouble()) return kg.toStringAsFixed(0);
  return kg.toStringAsFixed(1);
}