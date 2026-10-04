import 'package:companion_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The question field with a hardware keyboard, as on an emulator: Ctrl+V and
/// the keyboard's own Paste key both paste, and the Copy key copies.
void main() {
  testWidgets('the question field pastes from Ctrl+V and the Paste key',
      (tester) async {
    final copied = <String?>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.getData':
          return {'text': 'pasted question'};
        case 'Clipboard.hasStrings':
          return {'value': true};
        case 'Clipboard.setData':
          copied.add((call.arguments as Map)['text'] as String?);
          return null;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(const CompanionApp());
    await tester.pumpAndSettle();
    String typed() =>
        tester.widget<TextField>(find.byType(TextField)).controller!.text;

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(typed(), 'pasted question');

    await tester.enterText(find.byType(TextField), '');
    await tester.sendKeyEvent(LogicalKeyboardKey.paste);
    await tester.pumpAndSettle();
    expect(typed(), 'pasted question',
        reason: 'Android sends its Paste key as KEYCODE_PASTE');

    final field = tester.widget<TextField>(find.byType(TextField));
    field.controller!.selection =
        TextSelection(baseOffset: 0, extentOffset: typed().length);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.copy);
    await tester.pumpAndSettle();
    expect(copied, ['pasted question']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
