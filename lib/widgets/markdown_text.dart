import 'package:flutter/material.dart';

/// Renders an Ask My Bee assistant reply as lightweight Markdown.
///
/// This is deliberately NOT a full Markdown engine:
/// - No WebView and no HTML rendering. The output is a plain `Text.rich`
///   built from `TextSpan`s, so a reply containing `<script>`, `<img>` or any
///   other tag shows it as literal, harmless text — nothing ever executes.
/// - Supported: `#` headings, `-`/`*` bullet lists, `1.` numbered lists,
///   `>>` blockquotes, simple tables, `**bold**`, `*italic*`, `_italic_`,
///   `` `inline code` `` and `[label](url)` links (rendered as the label).
/// - Streaming-safe: replies arrive whole from the backend, but the parser is
///   a pure, non-throwing scan, so partial text still renders gracefully and
///   an unterminated marker (`**Hive 3`) degrades to plain text.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? const TextStyle();
    return Text.rich(
      TextSpan(children: _blockSpans(text, base)),
      style: base,
    );
  }

  /// Splits [text] into block lines (headings, lists, tables) and joins the
  /// inline-rendered spans of each line with newlines.
  static List<InlineSpan> _blockSpans(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final raw = lines[index];
      if (raw.trim().isEmpty) {
        continue; // blank lines do not add visual height inside a bubble
      }
      var content = raw;
      var style = base;
      if (RegExp(r'^#{1,6}\s+').hasMatch(content)) {
        final level = content.indexOf(RegExp(r'\s')).clamp(1, 6);
        style = base.copyWith(
          fontSize: switch (level) {
            1 || 2 => (base.fontSize ?? 14) + 3,
            3 => (base.fontSize ?? 14) + 2,
            _ => (base.fontSize ?? 14) + 1,
          },
          fontWeight: FontWeight.w800,
          height: 1.3,
        );
        content = content.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
      } else if (RegExp(r'^>\s?').hasMatch(content)) {
        content = content.replaceFirst(RegExp(r'^>\s?'), '');
        style = base.copyWith(
          fontStyle: FontStyle.italic,
          color: base.color,
        );
      }

      if (RegExp(r'^[\s|:\-]+$').hasMatch(content)) {
        continue; // table separator row ("|---|---|")
      }

      if (RegExp(r'^[-*+]\s+').hasMatch(content)) {
        content = content.replaceFirst(RegExp(r'^[-*+]\s+'), '');
        spans.add(TextSpan(text: '•  ', style: style));
      } else if (RegExp(r'^\d+[.)]\s+').hasMatch(content)) {
        final number = content.split(RegExp(r'[.)]')).first;
        content = content.replaceFirst(RegExp(r'^\d+[.)]\s+'), '');
        spans.add(TextSpan(text: '$number.  ', style: style));
      } else if (content.contains('|')) {
        content = content
            .split('|')
            .map((cell) => cell.trim())
            .where((cell) => cell.isNotEmpty)
            .join('  ·  ');
      }

      spans.addAll(_inlineSpans(content, style));
      if (index < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }
    return spans;
  }

  /// Renders inline Markdown (bold, italic, code, links) into [TextSpan]s.
  ///
  /// A tiny scan rather than a state machine: markers are resolved only when
  /// they match at word boundaries and are closed on the same line, so
  /// snake_case (`total_brood`) and single markers are left as literal text.
  static List<InlineSpan> _inlineSpans(String line, TextStyle base) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();
    var i = 0;

    void flush() {
      if (buffer.isEmpty) return;
      spans.add(TextSpan(text: buffer.toString(), style: base));
      buffer.clear();
    }

    while (i < line.length) {
      final rest = line.substring(i);

      // [label](url) -> label
      final link = RegExp(r'^\[([^\]]*)\]\([^)]*\)').firstMatch(rest);
      if (link != null) {
        flush();
        spans.add(TextSpan(text: link.group(1) ?? '', style: base));
        i += link.group(0)!.length;
        continue;
      }

      // `code`
      if (rest.startsWith('`')) {
        final closing = rest.indexOf('`', 1);
        if (closing > 0) {
          flush();
          spans.add(
            TextSpan(
              text: rest.substring(1, closing),
              style: base.copyWith(
                fontFamily: 'monospace',
                fontSize: (base.fontSize ?? 14) - 1,
                backgroundColor: Colors.black.withValues(alpha: 0.06),
              ),
            ),
          );
          i += closing + 1;
          continue;
        }
        buffer.write('`');
        i += 1;
        continue;
      }

      // "***" is not worth a nested-emphasis state machine; keep it literal.
      if (rest.startsWith('***')) {
        buffer.write('*');
        i += 1;
        continue;
      }

      // Strong (** or __) and emphasis (* or _). A marker is an opener only at
      // a left word boundary AND when followed by content (so "2 * 3" stays
      // literal), and emphasis only closes at a right word boundary (so
      // "total_brood" and "*a*b" are never mangled).
      const markers = ['**', '__', '*', '_'];
      String? matched;
      for (final marker in markers) {
        if (rest.startsWith(marker) && _canOpen(line, i, marker.length)) {
          matched = marker;
          break;
        }
      }
      if (matched != null) {
        final body = _closingBody(rest, matched);
        if (body != null) {
          flush();
          final strong = matched == '**' || matched == '__';
          spans.add(
            TextSpan(
              text: _inlineText(body),
              style: strong
                  ? base.copyWith(fontWeight: FontWeight.w700)
                  : base.copyWith(fontStyle: FontStyle.italic),
            ),
          );
          i += matched.length + body.length + matched.length;
          continue;
        }
      }

      // Any other character: keep literally (including <b>, &amp;, etc.).
      buffer.write(rest[0]);
      i += 1;
    }

    flush();
    return spans;
  }

  /// True when a marker at [index] may open emphasis: it is not glued to a
  /// word on the left, and it is followed by actual content (not a space).
  static bool _canOpen(String line, int index, int markerLength) {
    if (index > 0 && _isWord(line.codeUnitAt(index - 1))) return false;
    final next = index + markerLength;
    if (next >= line.length) return false;
    final ch = line.codeUnitAt(next);
    if (ch == 0x20 || ch == 0x09 || ch == 0x0a || ch == 0x0d) return false;
    return true;
  }

  /// Looks for the matching closing [marker] after the opener. Returns the
  /// body, or null when the markers do not form a valid emphasis pair.
  static String? _closingBody(String rest, String marker) {
    final contentStart = marker.length;
    final closing = rest.indexOf(marker, contentStart);
    if (closing <= contentStart) return null;
    final content = rest.substring(contentStart, closing);
    if (content.isEmpty) return null;
    if (content.startsWith(' ') || content.endsWith(' ')) return null;
    final after = closing + marker.length;
    if (after < rest.length && _isWord(rest.codeUnitAt(after))) return null;
    return content;
  }

  /// Nested emphasis inside emphasis is rare; flatten any leftover single
  /// markers so "**Hive *3***" style output never shows literal stars.
  static String _inlineText(String body) =>
      body.replaceAll(RegExp(r'[*_]{1,3}'), '');

  static bool _isWord(int codeUnit) =>
      (codeUnit >= 0x30 && codeUnit <= 0x39) || // 0-9
      (codeUnit >= 0x41 && codeUnit <= 0x5a) || // A-Z
      (codeUnit >= 0x61 && codeUnit <= 0x7a); // a-z
}