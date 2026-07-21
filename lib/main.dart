import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/quran_repository.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HifzCompanionApp());
}

class HifzCompanionApp extends StatefulWidget {
  const HifzCompanionApp({super.key});

  @override
  State<HifzCompanionApp> createState() => _HifzCompanionAppState();
}

class _HifzCompanionAppState extends State<HifzCompanionApp> {
  bool _ready = false;
  bool _darkMode = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await QuranRepository.instance.load();
    final darkMode = await SettingsService.instance.getDarkMode();
    setState(() {
      _darkMode = darkMode;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading Hifz Companion...'),
              ],
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hifz Companion',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const HomeScreen(),
    );
  }
}
