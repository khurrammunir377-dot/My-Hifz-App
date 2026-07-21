class SurahInfo {
  final int number;
  final String nameArabic;
  final String nameTransliteration;
  final String type; // meccan / medinan
  final int totalVerses;

  SurahInfo({
    required this.number,
    required this.nameArabic,
    required this.nameTransliteration,
    required this.type,
    required this.totalVerses,
  });

  factory SurahInfo.fromJson(Map<String, dynamic> json) {
    return SurahInfo(
      number: json['number'] as int,
      nameArabic: json['name_arabic'] as String,
      nameTransliteration: json['name_transliteration'] as String,
      type: json['type'] as String,
      totalVerses: json['total_verses'] as int,
    );
  }
}

class AyahInfo {
  final int surah;
  final int ayah;
  final int juz;
  final String text;
  final String transliteration;

  AyahInfo({
    required this.surah,
    required this.ayah,
    required this.juz,
    required this.text,
    required this.transliteration,
  });

  factory AyahInfo.fromJson(Map<String, dynamic> json) {
    return AyahInfo(
      surah: json['surah'] as int,
      ayah: json['ayah'] as int,
      juz: json['juz'] as int,
      text: json['text'] as String,
      transliteration: json['transliteration'] as String? ?? '',
    );
  }
}

class JuzInfo {
  final int number;
  final int startSurah;
  final int startAyah;
  final int endSurah;
  final int endAyah;
  final String startSurahName;

  JuzInfo({
    required this.number,
    required this.startSurah,
    required this.startAyah,
    required this.endSurah,
    required this.endAyah,
    required this.startSurahName,
  });

  factory JuzInfo.fromJson(Map<String, dynamic> json) {
    return JuzInfo(
      number: json['number'] as int,
      startSurah: json['start_surah'] as int,
      startAyah: json['start_ayah'] as int,
      endSurah: json['end_surah'] as int,
      endAyah: json['end_ayah'] as int,
      startSurahName: json['start_surah_name'] as String,
    );
  }
}
