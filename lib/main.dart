import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'bridge/avatar_room.dart';
import 'domain/companion_controller.dart';
import 'posture/posture_source.dart';
import 'speech/voice_kit.dart';
import 'theme.dart';
import 'ui/home_page.dart';
import 'ui/robert_cues.dart';

void main() {
  if (postureHelperBuilt) LicenseRegistry.addLicense(postureModelLicence);
  runApp(const CompanionApp());
}

/// The posture model is adapted from two datasets whose licences ask for
/// attribution, and one of them for non-commercial use only. The app's licence
/// list carries both.
Stream<LicenseEntry> postureModelLicence() => Stream.value(
      const LicenseEntryWithLineBreaks(['Prayer posture model'], '''
The prayer-movement helper's model (assets/models/prayer_posture.tflite) was
trained on, and is adapted from, these datasets. It is licensed CC BY-NC 4.0
(https://creativecommons.org/licenses/by-nc/4.0/): non-commercial use only.

Salat Postures, Robotics and Internet-of-Things Lab (Koubaa, Ammar, Benjdira,
Al-Hadid, Kawaf, Al-Yahri, Babiker, Assaf and Ras, "Activity Monitoring of
Islamic Prayer (Salat) Postures using Deep Learning", CDMA 2020).
https://www.kaggle.com/datasets/riotulab/salat-postures — CC BY-NC 4.0.

Islamic Multi-Category Salat Posture Dataset (IMCSPD), version 2, Baizid MD
Ashadzzaman, Baizid Kamruzzaman and Shadman Yaser, Mendeley Data, 2026.
https://doi.org/10.17632/xwrgj6c7wr.2 — CC BY 4.0
(https://creativecommons.org/licenses/by/4.0/).

Changes: images were cropped and resized, class names were merged into four
postures, and a MobileNetV3-Small network (ImageNet weights, Apache 2.0) was
trained on them.'''),
    );

class CompanionApp extends StatelessWidget {
  const CompanionApp(
      {super.key, this.controller, this.room, this.startTimer, this.voice});

  final CompanionController? controller;
  final AvatarRoom? room;

  /// The speech preview's parts; tests pass fakes. See [VoiceKit].
  final VoiceKit? voice;

  /// Times how long Robert talks; tests replace it. See [CompanionHome].
  final StartTimer? startTimer;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Robert · Learning companion',
        debugShowCheckedModeBanner: false,
        theme: companionTheme(),
        home: CompanionHome(
            controller: controller,
            room: room,
            startTimer: startTimer,
            voice: voice),
      );
}
