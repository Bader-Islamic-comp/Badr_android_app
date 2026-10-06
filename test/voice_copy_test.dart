import 'dart:io';

import 'package:companion_mobile/data/demo_api.dart';
import 'package:companion_mobile/speech/robert_voice.dart';
import 'package:companion_mobile/speech/voice_capture.dart';
import 'package:companion_mobile/ui/adhkar_page.dart';
import 'package:companion_mobile/ui/dhikr_game_page.dart';
import 'package:companion_mobile/ui/duas_page.dart';
import 'package:companion_mobile/ui/talk_page.dart';
import 'package:companion_mobile/ui/voice_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The speech preview's own words. It is practice, never a verdict: no
/// child-facing line may judge a recitation, and none may call one correct,
/// valid or accepted. Feedback lines are the service's reviewed copy; these
/// are the app's.

/// The spec's banned words, and the words of a verdict.
const _bannedArabic = [
  'غلط',
  'خطأ',
  'فشلت',
  'ما قُبل',
  'باطل',
  'لا يصح',
  'ما بتنحسب',
  'مرفوض',
];
final _bannedEnglish = RegExp(
    r'\b(wrong|fail|failed|failure|invalid|rejected|incorrect|mistakes?|'
    r'correct(ly)?|valid|accepted|verdict)\b',
    caseSensitive: false);

/// Every file that holds speech preview copy, including the shell's lines.
const _files = [
  'lib/data/demo_api.dart',
  'lib/domain/speech_models.dart',
  'lib/speech/audio_playback.dart',
  'lib/speech/robert_voice.dart',
  'lib/speech/speech_player.dart',
  'lib/speech/voice_capture.dart',
  'lib/speech/voice_kit.dart',
  'lib/speech/voice_recorder.dart',
  'lib/ui/adhkar_page.dart',
  'lib/ui/dhikr_game_page.dart',
  'lib/ui/duas_page.dart',
  'lib/ui/home_page.dart',
  'lib/ui/learn_page.dart',
  'lib/ui/parent_sheet.dart',
  'lib/ui/quests_page.dart',
  'lib/ui/talk_page.dart',
  'lib/ui/voice_widgets.dart',
];

final _literal = RegExp(r"'(?:[^'\\\n]|\\.)*'" r'|"(?:[^"\\\n]|\\.)*"');

/// String literals of [source], leaving out comment lines.
List<String> _strings(String source) => [
      for (final line in source.split('\n'))
        if (!line.trimLeft().startsWith('//'))
          for (final match in _literal.allMatches(line))
            match[0]!.substring(1, match[0]!.length - 1),
    ];

String? _banned(String text) {
  for (final word in _bannedArabic) {
    if (text.contains(word)) return word;
  }
  return _bannedEnglish.firstMatch(text)?[0];
}

void main() {
  test('no speech preview copy judges a recitation', () {
    var checked = 0;
    for (final path in _files) {
      final strings = _strings(File(path).readAsStringSync());
      expect(strings, isNotEmpty, reason: '$path has copy to check');
      for (final text in strings) {
        checked++;
        expect(_banned(text), isNull, reason: '$path: "$text"');
      }
    }
    expect(checked, greaterThan(200));
  });

  test('the copy the pages show, by name', () {
    final copy = [
      ...DemoApi.knownErrors.values,
      VoiceCapture.permissionRefused,
      VoiceCapture.couldNotStart,
      VoiceCapture.holdLonger,
      RobertVoice.slowCopy,
      RobertVoice.couldNotPlay,
      TalkPage.preparingCopy,
      TalkPage.speakingCopy,
      TalkPage.unavailableCopy,
      MicrophoneOffNote.text,
      PracticeWords.clearLabel,
      PracticeWords.practiseLabel,
      PracticePanel.sendingCopy,
      PracticePanel.promptCopy,
      practiceRest,
      practiceOnly,
      DuasPage.voiceComing,
      DuasPage.fromQuran,
      DhikrGamePage.intro,
      DhikrGamePage.starsCollected,
      DhikrGamePage.lovelyPractice,
      DhikrGamePage.wellDone,
      DhikrGamePage.starEarned,
    ];
    for (final text in copy) {
      expect(_banned(text), isNull, reason: text);
    }
    // The daily cap is warm, never a loss.
    for (final text in [
      DhikrGamePage.starsCollected,
      DhikrGamePage.lovelyPractice,
    ]) {
      expect(
          text,
          isNot(matches(RegExp(r'\b(lost|lose|miss|only|no more)\b',
              caseSensitive: false))));
    }
  });

  test('the scan finds a banned word when there is one', () {
    expect(_banned('That was wrong.'), 'wrong');
    expect(_banned('Your recitation is accepted'), 'accepted');
    expect(_banned('هذا خطأ'), 'خطأ');
    expect(_strings("const a = 'one'; // 'wrong'\n// 'mistake'\n"),
        ['one', 'wrong'],
        reason:
            'a trailing comment is scanned too; whole comment lines are not');
  });
}
