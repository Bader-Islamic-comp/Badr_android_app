import 'package:flutter/material.dart';

import 'bridge/avatar_room.dart';
import 'domain/companion_controller.dart';
import 'theme.dart';
import 'ui/home_page.dart';
import 'ui/robert_cues.dart';

void main() => runApp(const CompanionApp());

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key, this.controller, this.room, this.startTimer});

  final CompanionController? controller;
  final AvatarRoom? room;

  /// Times how long Robert talks; tests replace it. See [CompanionHome].
  final StartTimer? startTimer;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Robert · Learning companion',
        debugShowCheckedModeBanner: false,
        theme: companionTheme(),
        home: CompanionHome(
            controller: controller, room: room, startTimer: startTimer),
      );
}
