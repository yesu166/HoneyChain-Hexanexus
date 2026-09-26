import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honeychain/services/speech/speech_text.dart';
import 'package:honeychain/widgets/markdown_text.dart';

/// Flattens a [RichText]'s span tree into (text, style) pairs for assertions.
List<({String text, TextStyle? style})> _spans(InlineSpan root) {
  final out = <({String text, TextStyle? style})>[];
  void walk(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text != null) {
        out.add((text: span.text!, style: span.style));
      }
      if (span.children != null) {
        for (final child in span.children!) {
          walk(child);
        }
      }
    }
  }

  walk(root);
  return out;
}

RichText _richText(WidgetTester tester) =>
    tester.widget<RichText>(find.byType(RichText));

void main() {
  group('sanitizeForSpeech', () {
    test('empties pass through', () {
      expect(sanitizeForSpeech(''), '');
    });

    test('removes bold and italic markers, keeps the words', () {
      expect(sanitizeForSpeech('**Hive 1** is active'), 'Hive 1 is active');
      expect(sanitizeForSpeech('*low* activity'), 'low activity');
      expect(sanitizeForSpeech('_low_ activity'), 'low activity');
      expect(sanitizeForSpeech('***important***'), 'important');
    });

    test('does not mangle snake_case or arithmetic', () {
      expect(sanitizeForSpeech('total_brood is 4'), 'total_brood is 4');
      expect(sanitizeForSpeech('varroa_2 = 6'), 'varroa_2 = 6');
      expect(sanitizeForSpeech('2 * 3 = 6'), '2 * 3 = 6');
    });

    test('strips headings, blockquotes and list markers', () {
      expect(sanitizeForSpeech('## Next steps'), 'Next steps');
      expect(sanitizeForSpeech('- check brood\n- check queen'),
          'check brood\ncheck queen');
      expect(sanitizeForSpeech('* one\n* two'), 'one\ntwo');
      expect(sanitizeForSpeech('1. open hive\n2. look'), '1, open hive\n2, look');
      expect(sanitizeForSpeech('> remember to feed'), 'remember to feed');
    });

    test('keeps numbers, decimals and ordinary punctuation intact', () {
      expect(sanitizeForSpeech('Weight is 12.6 kg today.'),
          'Weight is 12.6 kg today.');
      expect(sanitizeForSpeech('Yes, that is correct!'), 'Yes, that is correct!');
    });

    test('renders inline code without backticks', () {
      expect(sanitizeForSpeech('run `flutter test` now'), 'run flutter test now');
    });

    test('reduces links to their visible label', () {
      expect(sanitizeForSpeech('see [Hive 3](https://example.com/h3)'),
          'see Hive 3');
    });

    test('flattens table rows and drops separator rows', () {
      expect(sanitizeForSpeech('hive | status\n--- | ---\nA | active'),
          'hive, status\nA, active');
    });

    test('collapses runs of blank lines', () {
      expect(sanitizeForSpeech('a\n\n\n\nb'), 'a\n\nb');
    });

    test('never returns empty for non-empty input', () {
      expect(sanitizeForSpeech('** **').isNotEmpty, isTrue);
    });
  });

  group('MarkdownText', () {
    testWidgets('renders plain text verbatim', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MarkdownText('Weight 12.6 kg')),
      ));
      expect(_richText(tester).text.toPlainText(), 'Weight 12.6 kg');
    });

    testWidgets('renders bold as a bold span', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MarkdownText('**Hive 3** is ready')),
      ));
      final spans = _spans(_richText(tester).text);
      expect(spans.any((s) => s.text == 'Hive 3' && (s.style?.fontWeight ?? FontWeight.normal) == FontWeight.w700),
          isTrue);
      expect(_richText(tester).text.toPlainText(),
          'Hive 3 is ready'); // no stray **
    });

    testWidgets('renders italic as an italic span', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MarkdownText('Activity is *low*')),
      ));
      final spans = _spans(_richText(tester).text);
      expect(spans.any((s) => s.text == 'low' && s.style?.fontStyle == FontStyle.italic),
          isTrue);
    });

    testWidgets('does not italicize snake_case or arithmetic', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MarkdownText('total_brood 2 * 3')),
      ));
      expect(_richText(tester).text.toPlainText(), 'total_brood 2 * 3');
    });

    testWidgets('renders headings larger and bold', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MarkdownText('## Next steps')),
      ));
      final spans = _spans(_richText(tester).text);
      expect(spans.single.text, 'Next steps');
      expect(spans.single.style?.fontWeight, FontWeight.w800);
      expect(spans.single.style?.fontSize, greaterThan(14));
    });

    testWidgets('renders bullet and numbered lists with prefixes',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MarkdownText('- a\n- b\n1. c')),
      ));
      expect(_richText(tester).text.toPlainText(), '•  a\n•  b\n1.  c');
    });

    testWidgets('renders inline code in monospace', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MarkdownText('run `flutter test`')),
      ));
      final spans = _spans(_richText(tester).text);
      expect(spans.any((s) => s.text == 'flutter test' && s.style?.fontFamily == 'monospace'),
          isTrue);
    });

    testWidgets('renders links as their label', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MarkdownText('[Hive 3](https://example.com)')),
      ));
      expect(_richText(tester).text.toPlainText(), 'Hive 3');
    });

    testWidgets('keeps raw HTML as literal text (no HTML rendering)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MarkdownText('<script>alert(1)</script>')),
      ));
      // Safe: it is just text; nothing executes, nothing is stripped.
      expect(_richText(tester).text.toPlainText(),
          '<script>alert(1)</script>');
    });

    testWidgets('an unterminated marker renders gracefully as plain text',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MarkdownText('**Hive 3')),
      ));
      expect(_richText(tester).text.toPlainText(), '**Hive 3');
    });
  });
}