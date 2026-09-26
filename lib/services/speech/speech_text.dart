/// Speech-safe rendering of assistant replies.
///
/// Ask My Bee replies are Markdown-formatted (bold, italic, headings, lists,
/// inline code, links). The chat bubble renders that Markdown ([MarkdownText]),
/// but the TTS layer must never read the markers aloud. [sanitizeForSpeech]
/// strips Markdown syntax while keeping the actual words and numbers intact, so
/// a reply reads naturally ("Hive 3 weight is 12.6 kg") instead of literally
/// ("star star Hive 3 star star weight is ...").
library;

/// Removes Markdown syntax from [text] so TTS speaks the content, not markup.
///
/// Only presentation syntax is touched: emphasis, inline code, links,
/// headings, list markers, blockquotes and tables. Real content — words,
/// punctuation, numbers and decimals — is preserved verbatim. The result stays
/// readable and is never empty for a non-empty input.
String sanitizeForSpeech(String text) {
  if (text.isEmpty) return text;
  var s = text;

  // Links: keep only the visible label.
  s = s.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );

  // Emphasis pairs (*x* / **x** / _x_) only when the markers sit at word
  // boundaries, so snake_case identifiers and arithmetic ("2 * 3") are left
  // alone. Dense stars at a boundary (e.g. "***") are also consumed.
  for (final re in [
    RegExp(r'(?<![A-Za-z0-9])\*\*\*([^*\n]+)\*\*\*(?![A-Za-z0-9])'),
    RegExp(r'(?<![A-Za-z0-9])\*\*([^*\n]+)\*\*(?![A-Za-z0-9])'),
    RegExp(r'(?<![A-Za-z0-9])_([^_\n]+)_(?![A-Za-z0-9])'),
    RegExp(r'(?<![A-Za-z0-9])\*([^*\n]+)\*(?![A-Za-z0-9])'),
  ]) {
    s = s.replaceAllMapped(re, (m) => m.group(1) ?? '');
  }

  // Inline code and strikethrough markers.
  s = s.replaceAll('`', '').replaceAll('~~', '');

  final lines = <String>[];
  for (final raw in s.split('\n')) {
    var line = raw.replaceFirst(RegExp(r'^#{1,6}\s+'), ''); // headings
    line = line.replaceFirst(RegExp(r'^>\s?'), ''); // blockquote
    line = line.replaceFirst(RegExp(r'^\s*[-*+]\s+'), ''); // bullet list
    line = line.replaceFirstMapped(
      RegExp(r'^\s*(\d+)[.)]\s+'),
      (m) => '${m.group(1)}, ',
    ); // numbered list -> "1, first item"
    if (RegExp(r'^[\s|:\-]+$').hasMatch(line) && line.contains('|')) continue; // table separator row
    if (line.contains('|')) {
      // Table data row: pipes become commas so cells read naturally.
      line = line
          .split('|')
          .map((cell) => cell.trim())
          .where((cell) => cell.isNotEmpty)
          .join(', ');
    }
    lines.add(line);
  }

  return _collapseBlankLines(lines.join('\n'));
}

String _collapseBlankLines(String s) =>
    s.replaceAll(RegExp(r'\n{3,}'), '\n\n');