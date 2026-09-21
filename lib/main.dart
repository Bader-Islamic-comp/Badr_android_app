import 'package:flutter/material.dart';

import 'bridge/avatar_room.dart';
import 'domain/companion_controller.dart';
import 'theme.dart';
import 'ui/home_page.dart';

void main() => runApp(const CompanionApp());

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key, this.controller, this.room});

  final CompanionController? controller;
  final AvatarRoom? room;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Robert · Learning companion',
        debugShowCheckedModeBanner: false,
        theme: companionTheme(),
        home: CompanionHome(controller: controller, room: room),
      );
}
