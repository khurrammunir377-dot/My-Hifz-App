import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/quran_models.dart';

/// Loads the bundled Quran text dataset (Arabic Uthmani script + transliteration)
/// once at app start, and provides fast in-memory lookups by Juz / Surah / Ayah.
///
/// The dataset ships as a single JSON asset (assets/data/quran_data.json) so the
/// app works fully offline with no network dependency for reading Quran text.
class QuranRepository {
  QuranRepository._internal();
  static final QuranRepository instance = QuranRepository._internal();

  List<SurahInfo> _surahs = [];
  List<AyahInfo> _ayahs = [];
  List<JuzInfo> _juzList = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/data/quran_data.json');
    final Map<String, dynamic> data = json.decode(raw) as Map<String, dynamic>;

    _surahs = (data['surahs'] as List)
        .map((e) => SurahInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    _ayahs = (data['verses'] as List)
        .map((e) => AyahInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    _juzList = (data['juz'] as List)
        .map((e) => JuzInfo.fromJson(e as Map<String, dynamic>))
        .toList();

    _loaded = true;
  }

  List<JuzInfo> get allJuz => _juzList;

  SurahInfo surahByNumber(int number) =>
      _surahs.firstWhere((s) => s.number == number);

  /// Distinct surah numbers that fall (fully or partially) inside the given Juz,
  /// in ascending order.
  List<SurahInfo> surahsInJuz(int juzNumber) {
    final juz = _juzList.firstWhere((j) => j.number == juzNumber);
    final surahNumbers = <int>{};
    for (var s = juz.startSurah; s <= juz.endSurah; s++) {
      surahNumbers.add(s);
    }
    final list = surahNumbers.map(surahByNumber).toList();
    list.sort((a, b) => a.number.compareTo(b.number));
    return list;
  }

  /// All ayahs for a given surah, in ascending ayah order.
  List<AyahInfo> ayahsForSurah(int surahNumber) {
    final list = _ayahs.where((a) => a.surah == surahNumber).toList();
    list.sort((a, b) => a.ayah.compareTo(b.ayah));
    return list;
  }

  AyahInfo? ayah(int surah, int ayahNumber) {
    try {
      return _ayahs.firstWhere((a) => a.surah == surah && a.ayah == ayahNumber);
    } catch (_) {
      return null;
    }
  }
}
