import 'dart:async';

import 'package:companion_mobile/data/demo_api.dart';
import 'package:companion_mobile/domain/companion_controller.dart';
import 'package:companion_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class PendingController extends CompanionController {
  PendingController() : super(DemoApi(const DemoConfig())) {
    connected = true;
  }

  final pending = Completer<void>();
  bool started = false;
  bool conversationPresent = true;

  @override
  bool get hasConversation => conversationPresent;

  @override
  Future<bool> ask(String text) async {
    started = true;
    await pending.future;
    return false;
  }

  @override
  Future<void> clearConversation() async {
    started = true;
    await pending.future;
    conversationPresent = false;
  }
}

void main() {
  for (final deleting in [false, true]) {
    testWidgets(
        'unmount during ${deleting ? 'delete' : 'send'} preserves disposal safety',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = PendingController();
      await tester.pumpWidget(CompanionApp(controller: model));
      await tester.pumpAndSettle();
      if (!deleting) {
        await tester.enterText(find.byType(TextField), 'Synthetic question');
      }
      final action = deleting
          ? find.text('Clear development conversation')
          : find.byTooltip('Send test question');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();
      expect(model.started, isTrue);
      await tester.pumpWidget(const SizedBox());
      model.pending.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      model.dispose();
    });
  }
}
