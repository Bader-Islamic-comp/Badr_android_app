import 'package:flutter/widgets.dart';

/// A letter that sets a paragraph's direction: Latin, or a right-to-left
/// script (Hebrew, Arabic and the scripts between them, and the Arabic
/// presentation forms). Digits and punctuation are neutral and skipped.
final _strong =
    RegExp(r'[A-Za-z\u00C0-\u024F\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');
final _rightToLeft = RegExp(r'[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');

/// The direction [text] reads in, from its first strong letter, as the
/// Unicode bidirectional algorithm picks a paragraph's direction: an Arabic
/// reply or source title reads right to left even though the app's own
/// layout stays left to right. Text with no letters reads left to right.
TextDirection directionOf(String text) {
  final first = _strong.firstMatch(text);
  return first != null && _rightToLeft.hasMatch(first.group(0)!)
      ? TextDirection.rtl
      : TextDirection.ltr;
}

/// A number range or reference ("12:36\u201342", "2:255", "1/3"): digits joined by
/// a colon, dash, slash or point. A Latin tag written onto the numbers
/// ("quran:7:19-23", "quran:12:87\u2013quran:12:93") belongs to the run: with
/// only the numbers isolated, right-to-left text puts them before their tag
/// and "quran:7:19-23" reads "7:19-23:quran".
const _digits = r'[0-9\u0660-\u0669]+';
const _tag = r'(?:[A-Za-z][A-Za-z_]*:)?';
const _joiner = r'[:/.\u2013\u2014-]';
final _numberRun = RegExp('$_tag$_digits(?:$_joiner$_tag$_digits)+');

/// [text] with every number range wrapped in a left-to-right isolate (U+2066
/// ... U+2069). Inside right-to-left text the bidi algorithm orders the
/// numbers around a dash from right to left, so "12:36\u201342" would read
/// "42\u201312:36"; isolated, it reads as written. Only for right-to-left text.
String isolateNumberRanges(String text) =>
    text.replaceAllMapped(_numberRun, (match) => '\u2066${match[0]}\u2069');

/// [text] in its own direction. Right-to-left text takes the full width so
/// that a short line starts at the right edge, where an Arabic reader looks
/// first, and its number ranges are isolated ([isolateNumberRanges]);
/// left-to-right text is laid out exactly as a plain [Text].
Widget directionalText(String text, {TextStyle? style}) {
  final direction = directionOf(text);
  final shown =
      direction == TextDirection.rtl ? isolateNumberRanges(text) : text;
  final widget = Text(shown, style: style, textDirection: direction);
  return direction == TextDirection.rtl
      ? SizedBox(width: double.infinity, child: widget)
      : widget;
}
