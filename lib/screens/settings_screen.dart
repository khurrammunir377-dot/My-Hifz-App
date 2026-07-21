import 'package:flutter/material.dart';
import '../services/db_helper.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ArabicFontSize _fontSize = ArabicFontSize.medium;
  bool _darkMode = false;
  bool _referenceAudio = false;
  bool _interruptionCue = true;
  bool _loaded = false;

  final TextEditingController _endpointController = TextEditingController();
  Map<String, dynamic> _stats = {'versesAttempted': 0, 'averageAccuracy': 0.0, 'versesLearned': 0};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final size = await SettingsService.instance.getFontSize();
    final dark = await SettingsService.instance.getDarkMode();
    final refAudio = await SettingsService.instance.getReferenceAudioEnabled();
    final endpoint = await SettingsService.instance.getRecognitionEndpoint();
    final cue = await SettingsService.instance.getInterruptionCueEnabled();
    final stats = await DbHelper.instance.overallStats();
    if (!mounted) return;
    setState(() {
      _fontSize = size;
      _darkMode = dark;
      _referenceAudio = refAudio;
      _interruptionCue = cue;
      _endpointController.text = endpoint;
      _stats = stats;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _endpointController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('Your Progress'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statColumn('Verses\nAttempted', '${_stats['versesAttempted']}'),
                _statColumn('Avg. Accuracy',
                    '${((_stats['averageAccuracy'] as double) * 100).toStringAsFixed(0)}%'),
                _statColumn('Verses\nLearned', '${_stats['versesLearned']}'),
              ],
            ),
          ),
          const Divider(),
          const ListTile(
            title: Text('Arabic Text Size'),
            subtitle: Text('Applies to the Recitation Screen'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ArabicFontSize>(
              segments: const [
                ButtonSegment(value: ArabicFontSize.small, label: Text('Small')),
                ButtonSegment(value: ArabicFontSize.medium, label: Text('Medium')),
                ButtonSegment(value: ArabicFontSize.large, label: Text('Large')),
              ],
              selected: {_fontSize},
              onSelectionChanged: (selection) async {
                final size = selection.first;
                setState(() => _fontSize = size);
                await SettingsService.instance.setFontSize(size);
              },
            ),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: _darkMode,
            onChanged: (value) async {
              setState(() => _darkMode = value);
              await SettingsService.instance.setDarkMode(value);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Restart the app to apply theme changes')),
                );
              }
            },
          ),
          SwitchListTile(
            title: const Text('Reciter Reference Audio'),
            subtitle: const Text('Coming in a future update'),
            value: _referenceAudio,
            onChanged: (value) async {
              setState(() => _referenceAudio = value);
              await SettingsService.instance.setReferenceAudioEnabled(value);
            },
          ),
          SwitchListTile(
            title: const Text('Real-Time Mistake Cue'),
            subtitle: const Text('Sound + vibration the instant a mistake is detected'),
            value: _interruptionCue,
            onChanged: (value) async {
              setState(() => _interruptionCue = value);
              await SettingsService.instance.setInterruptionCueEnabled(value);
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recognition Endpoint', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text(
                  'The address of the recitation-checking service. Ask your '
                  'developer for this if you don\'t have it.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _endpointController,
                  decoration: const InputDecoration(
                    hintText: 'https://your-project.supabase.co/functions/v1/check-recitation',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () async {
                      await SettingsService.instance
                          .setRecognitionEndpoint(_endpointController.text.trim());
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Saved')),
                        );
                      }
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('Support This App'),
            subtitle: const Text('Hifz Companion is free for everyone. Support is optional.'),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Support This App'),
                  content: const Text(
                    'This app is, and will always remain, completely free for '
                    'every student. Voluntary support options will be available '
                    'here in a future update, for those who wish to contribute '
                    'as an ongoing charitable act (Sadaqah Jariyah). No feature '
                    'is ever limited based on support.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _statColumn(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
