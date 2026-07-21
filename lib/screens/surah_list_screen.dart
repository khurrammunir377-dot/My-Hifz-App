import 'package:flutter/material.dart';
import '../services/quran_repository.dart';
import 'recitation_screen.dart';

class SurahListScreen extends StatelessWidget {
  final int juzNumber;

  const SurahListScreen({super.key, required this.juzNumber});

  @override
  Widget build(BuildContext context) {
    final surahs = QuranRepository.instance.surahsInJuz(juzNumber);

    return Scaffold(
      appBar: AppBar(title: Text('Juz $juzNumber')),
      body: ListView.separated(
        itemCount: surahs.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final surah = surahs[index];
          return ListTile(
            leading: CircleAvatar(child: Text('${surah.number}')),
            title: Text(
              surah.nameArabic,
              style: const TextStyle(fontSize: 20),
              textDirection: TextDirection.rtl,
            ),
            subtitle: Text(
              '${surah.nameTransliteration} · ${surah.totalVerses} verses · '
              '${surah.type[0].toUpperCase()}${surah.type.substring(1)}',
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RecitationScreen(
                    surahNumber: surah.number,
                    initialAyah: 1,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
