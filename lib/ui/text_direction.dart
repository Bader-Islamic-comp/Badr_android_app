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

/// [text] in its own direction. Right-to-left text takes the full width so
/// that a short line starts at the right edge, where an Arabic reader looks
/// first; left-to-right text is laid out exactly as a plain [Text].
Widget directionalText(String text, {TextStyle? style}) {
  final direction = directionOf(text);
  final widget = Text(text, style: style, textDirection: direction);
  return direction == TextDirection.rtl
      ? SizedBox(width: double.infinity, child: widget)
      : widget;
}
