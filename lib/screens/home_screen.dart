import 'package:flutter/material.dart';
import '../models/quran_models.dart';
import '../services/quran_repository.dart';
import '../services/settings_service.dart';
import 'surah_list_screen.dart';
import 'recitation_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  (int, int)? _lastSession;

  @override
  void initState() {
    super.initState();
    _loadLastSession();
  }

  Future<void> _loadLastSession() async {
    final last = await SettingsService.instance.getLastSession();
    if (mounted) setState(() => _lastSession = last);
  }

  @override
  Widget build(BuildContext context) {
    final juzList = QuranRepository.instance.allJuz;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hifz Companion'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_lastSession != null) _continueCard(context, _lastSession!),
          Expanded(
            child: ListView.builder(
              itemCount: juzList.length,
              itemBuilder: (context, index) {
                final JuzInfo juz = juzList[index];
                return ListTile(
                  leading: CircleAvatar(child: Text('${juz.number}')),
                  title: Text('Juz ${juz.number}'),
                  subtitle: Text('Starts at ${juz.startSurahName}'),
                  trailing: const SizedBox(
                    width: 60,
                    child: LinearProgressIndicator(value: 0.0),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SurahListScreen(juzNumber: juz.number),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _continueCard(BuildContext context, (int, int) lastSession) {
    final (surah, ayah) = lastSession;
    final surahInfo = QuranRepository.instance.surahByNumber(surah);
    return Card(
      margin: const EdgeInsets.all(12),
      child: ListTile(
        leading: const Icon(Icons.play_circle_fill, size: 36),
        title: const Text('Continue Last Session'),
        subtitle: Text('${surahInfo.nameTransliteration} — Ayah $ayah'),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RecitationScreen(
                surahNumber: surah,
                initialAyah: ayah,
              ),
            ),
          );
        },
      ),
    );
  }
}
