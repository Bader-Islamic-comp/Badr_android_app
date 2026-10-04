import 'text_direction.dart';

/// A source's reference as a child reads it.
///
/// The service sends a reference as the work, a middle dot and a span of
/// machine references: `حزمة بدر العربية للمسابقة · quran:7:19-23`,
/// `Tanzil Quran Text (Uthmani) · quran:12:87–quran:12:93`,
/// `… · bukhari:6324`. The span is rewritten for reading — `7:19–23`,
/// `سورة يوسف 12:87–93` when the source's title already names the surah,
/// `البخاري 6324` in an Arabic reply and `Bukhari 6324` in an English one —
/// and the work is kept as sent. [ReplySource.reference] keeps the raw text.
class SourceReference {
  const SourceReference._(this.work, this.span);

  /// [reference] made readable, or null when its span is not one this app
  /// knows: such a reference is shown exactly as the service sent it.
  ///
  /// [title] is the source's title, read only for a surah name that matches
  /// the reference's surah number. [arabic] names hadith collections in
  /// Arabic, for an Arabic reply.
  static SourceReference? parse(String reference,
      {String title = '', bool arabic = false}) {
    final cut = reference.lastIndexOf(_dot);
    final work = cut < 0 ? null : reference.substring(0, cut).trim();
    final span = _readable(
        reference.substring(cut < 0 ? 0 : cut + _dot.length).trim(),
        title: title,
        arabic: arabic);
    if (span == null) return null;
    return SourceReference._(work == null || work.isEmpty ? null : work, span);
  }

  /// The work as the service named it, if it did.
  final String? work;

  /// The readable span: `7:19–23`, `سورة يوسف 12:87–93`, `البخاري 6324`.
  final String span;

  /// The line as it reads, without direction marks: for screen readers and
  /// tests.
  String get plain => work == null ? span : '$work$_dot$span';

  /// The line as drawn. The work and the span each sit in their own isolate
  /// that takes its direction from its first letter, and every number range
  /// in a left-to-right one, so whichever way the line runs nothing in it
  /// changes places: an English work stays whole beside an Arabic span, and
  /// `12:87–93` never reads `93–12:87`.
  String get display => work == null
      ? _isolate(span)
      : '${_isolate(work!)}$_dot${_isolate(span)}';

  static const _dot = ' · ';
  static const _dash = '–';
  static final _firstStrongIsolate = String.fromCharCode(0x2068);
  static final _popIsolate = String.fromCharCode(0x2069);

  static String _isolate(String text) =>
      '$_firstStrongIsolate${isolateNumberRanges(text)}$_popIsolate';

  /// `quran:S:A`, `quran:S:A-B`, `bukhari:N`, `muslim_abdulbaqi:N`, ….
  static final _reference =
      RegExp(r'^([a-z][a-z_]*):(\d{1,6})(?::(\d{1,3}))?(?:-(\d{1,6}))?$');

  /// Hadith collections and the fiqh encyclopedia, as (Arabic, English).
  /// Both of Muslim's numberings read as Muslim.
  static const _collections = {
    'bukhari': ('البخاري', 'Bukhari'),
    'muslim': ('مسلم', 'Muslim'),
    'muslim_abdulbaqi': ('مسلم', 'Muslim'),
    'abu_dawud': ('أبو داود', 'Abu Dawud'),
    'tirmidhi': ('الترمذي', 'Tirmidhi'),
    'nasai': ('النسائي', 'Nasai'),
    'ibn_majah': ('ابن ماجه', 'Ibn Majah'),
    'dorar_fiqh': ('الموسوعة الفقهية', 'Fiqh encyclopedia'),
  };

  /// A span of one reference or two joined by an en dash, or null.
  static String? _readable(String span,
      {required String title, required bool arabic}) {
    final parts = span.split(_dash);
    if (parts.length > 2) return null;
    final refs = [for (final part in parts) _reference.firstMatch(part.trim())];
    if (refs.any((ref) => ref == null || !_known(ref))) return null;
    final first = refs.first!;
    final last = refs.last!;
    if (first[1] != last[1]) {
      // Two different kinds of source: each reads on its own.
      return [for (final ref in refs) _one(ref!, title: title, arabic: arabic)]
          .join(' $_dash ');
    }
    if (first[1] == 'quran') {
      final surah = first[2]!;
      final end = last[4] ?? last[3]!;
      final range = last[2] != surah
          ? '$surah:${first[3]}$_dash${last[2]}:$end'
          : end == first[3]
              ? '$surah:$end'
              : '$surah:${first[3]}$_dash$end';
      final name = last[2] == surah ? _surahName(title, surah) : null;
      return name == null ? range : '$name $range';
    }
    final from = first[2]!;
    final to = last[4] ?? last[2]!;
    final names = _collections[first[1]]!;
    final number = to == from ? from : '$from$_dash$to';
    return '${arabic ? names.$1 : names.$2} $number';
  }

  static bool _known(RegExpMatch ref) => ref[1] == 'quran'
      ? ref[3] != null
      : ref[3] == null && _collections.containsKey(ref[1]);

  static String _one(RegExpMatch ref,
          {required String title, required bool arabic}) =>
      _readable(ref[0]!, title: title, arabic: arabic)!;

  /// The surah's name as [title] gives it next to this surah's number, as in
  /// `سورة يوسف 12:85–98`, or null.
  static String? _surahName(String title, String surah) => RegExp(
          '((?:سورة|Surah|Sura)\\s+[^0-9\u0660-\u0669:·()«»—]+?)\\s*\\(?$surah:')
      .firstMatch(title)
      ?.group(1)
      ?.trim();
}
