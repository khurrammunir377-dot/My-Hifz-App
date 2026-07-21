import 'dart:async';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../models/quran_models.dart';
import '../services/db_helper.dart';
import '../services/quran_repository.dart';
import '../services/recitation_check_service.dart';
import '../services/settings_service.dart';
import '../services/word_matcher.dart';
import '../theme/app_theme.dart';

class RecitationScreen extends StatefulWidget {
  final int surahNumber;
  final int initialAyah;

  const RecitationScreen({
    super.key,
    required this.surahNumber,
    required this.initialAyah,
  });

  @override
  State<RecitationScreen> createState() => _RecitationScreenState();
}

class _RecitationScreenState extends State<RecitationScreen>
    with WidgetsBindingObserver {
  late List<AyahInfo> _ayahs;
  late int _currentIndex;

  final RecitationCheckService _checkService = RecitationCheckService();
  final ap.AudioPlayer _player = ap.AudioPlayer();
  StreamSubscription<LiveCheckUpdate>? _updatesSub;

  bool _isChecking = false;
  bool _cueEnabled = true;
  String _fontSizeName = 'medium';
  String _endpointUrl = '';

  WordMatchResult? _liveResult;
  ChunkStatus? _lastChunkStatus;
  String? _lastRecordingPath;
  bool _showingFinalSummary = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ayahs = QuranRepository.instance.ayahsForSurah(widget.surahNumber);
    _currentIndex = _ayahs.indexWhere((a) => a.ayah == widget.initialAyah);
    if (_currentIndex < 0) _currentIndex = 0;
    _loadSettings();
    _saveSession();

    _updatesSub = _checkService.updates.listen((update) {
      if (!mounted) return;
      setState(() {
        _liveResult = update.matchResult;
        _lastChunkStatus = update.lastChunkStatus;
      });
      if (update.newMistakeDetectedThisUpdate && _cueEnabled) {
        _triggerMistakeCue();
      }
    });
  }

  Future<void> _loadSettings() async {
    final size = await SettingsService.instance.getFontSize();
    final endpoint = await SettingsService.instance.getRecognitionEndpoint();
    final cue = await SettingsService.instance.getInterruptionCueEnabled();
    if (!mounted) return;
    setState(() {
      _fontSizeName = size.name;
      _endpointUrl = endpoint;
      _cueEnabled = cue;
    });
  }

  Future<void> _saveSession() async {
    final ayah = _ayahs[_currentIndex];
    await SettingsService.instance.setLastSession(ayah.surah, ayah.ayah);
  }

  Future<void> _triggerMistakeCue() async {
    HapticFeedback.mediumImpact();
    try {
      await _player.play(ap.AssetSource('audio/mistake_tone.wav'));
    } catch (_) {
      // Non-critical - a missed cue tone shouldn't interrupt the session.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _checkService.stopSafelyIfActive();
    }
  }

  AyahInfo get _currentAyah => _ayahs[_currentIndex];

  Future<void> _toggleChecking() async {
    if (_isChecking) {
      await _stopChecking();
    } else {
      await _startChecking();
    }
  }

  Future<void> _startChecking() async {
    if (_endpointUrl.isEmpty) {
      _showEndpointNotConfiguredDialog();
      return;
    }

    final hasPermission = await _checkService.hasPermission();
    if (!hasPermission) {
      final granted = await _requestMicPermission();
      if (!granted) return;
    }

    setState(() {
      _isChecking = true;
      _liveResult = null;
      _lastChunkStatus = null;
      _showingFinalSummary = false;
      _lastRecordingPath = null;
    });

    final expectedWords = tokenize(_currentAyah.text);
    await _checkService.start(
      endpointUrl: _endpointUrl,
      expectedWords: expectedWords,
    );
  }

  Future<void> _stopChecking() async {
    final (path, finalResult) = await _checkService.stop();
    setState(() {
      _isChecking = false;
      _liveResult = finalResult;
      _lastRecordingPath = path;
      _showingFinalSummary = true;
    });

    await DbHelper.instance.recordAttempt(
      surah: _currentAyah.surah,
      ayah: _currentAyah.ayah,
      accuracy: finalResult.accuracy,
    );
  }

  Future<bool> _requestMicPermission() async {
    final status = await ph.Permission.microphone.status;
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      _showPermanentlyDeniedDialog();
      return false;
    }

    final result = await ph.Permission.microphone.request();
    if (result.isGranted) return true;
    if (result.isPermanentlyDenied) {
      _showPermanentlyDeniedDialog();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is required to check your recitation.')),
      );
    }
    return false;
  }

  void _showPermanentlyDeniedDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Microphone Access Needed'),
        content: const Text(
          'Hifz Companion needs microphone access to check your recitation. '
          'Please enable it in your phone\'s app settings.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ph.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showEndpointNotConfiguredDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Recitation Checking Not Set Up Yet'),
        content: const Text(
          'To check your recitation, this app needs the address of the '
          'recognition service, set once in Settings → Recognition Endpoint. '
          'Ask your developer for this address if you don\'t have it yet.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _playLastRecording() async {
    if (_lastRecordingPath == null) return;
    await _player.play(ap.DeviceFileSource(_lastRecordingPath!));
  }

  void _goToAyah(int delta) {
    final newIndex = _currentIndex + delta;
    if (newIndex < 0 || newIndex >= _ayahs.length) return;
    setState(() {
      _currentIndex = newIndex;
      _liveResult = null;
      _lastRecordingPath = null;
      _showingFinalSummary = false;
    });
    _saveSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updatesSub?.cancel();
    _checkService.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surahInfo = QuranRepository.instance.surahByNumber(widget.surahNumber);
    final fontSize = arabicFontSizeValue(_fontSizeName);

    return Scaffold(
      appBar: AppBar(title: Text(surahInfo.nameTransliteration)),
      body: SafeArea(
        child: Column(
          children: [
            if (_lastChunkStatus == ChunkStatus.networkError)
              Container(
                width: double.infinity,
                color: Colors.orange.shade100,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: const Text(
                  'Connection issue — retrying next chunk...',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _buildAyahText(fontSize),
                    const SizedBox(height: 8),
                    Text(
                      '${surahInfo.nameTransliteration} · Ayah ${_currentAyah.ayah} of ${surahInfo.totalVerses}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Checks word accuracy. Tajweed rule-checking coming soon.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    if (_liveResult != null) _buildMismatchDetails(),
                  ],
                ),
              ),
            ),
            _buildVerseNav(),
            _buildCheckingControls(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildAyahText(double fontSize) {
    final expectedWords = tokenize(_currentAyah.text);
    final displayWords = _currentAyah.text.trim().split(RegExp(r'\s+'));

    if (_liveResult == null || displayWords.length != expectedWords.length) {
      return Text(
        _currentAyah.text,
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        style: TextStyle(fontSize: fontSize, height: 1.8),
      );
    }

    final spans = <TextSpan>[];
    for (var i = 0; i < displayWords.length; i++) {
      final status = _liveResult!.expectedWordStatus[i];
      Color color;
      switch (status) {
        case WordStatus.correct:
          color = Colors.green.shade700;
          break;
        case WordStatus.wrong:
          color = Colors.red.shade700;
          break;
        case WordStatus.missing:
          color = Colors.orange.shade800;
          break;
        case WordStatus.pending:
          color = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
          break;
      }
      final isCurrent = i == _liveResult!.currentPosition && _isChecking;
      spans.add(TextSpan(
        text: '${displayWords[i]} ',
        style: TextStyle(
          fontSize: fontSize,
          height: 1.8,
          color: color,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          decoration: isCurrent ? TextDecoration.underline : null,
        ),
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
    );
  }

  Widget _buildMismatchDetails() {
    if (_liveResult == null) return const SizedBox.shrink();
    final expectedWords = _currentAyah.text.trim().split(RegExp(r'\s+'));
    final mismatches = <Widget>[];
    for (var i = 0; i < _liveResult!.expectedWordStatus.length && i < expectedWords.length; i++) {
      if (_liveResult!.expectedWordStatus[i] == WordStatus.wrong) {
        final heard = _liveResult!.recognizedWordForExpected[i] ?? '?';
        mismatches.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            'Expected "${expectedWords[i]}" — heard "$heard"',
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
        ));
      }
    }
    if (mismatches.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(children: mismatches),
    );
  }

  Widget _buildVerseNav() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: (_currentIndex > 0 && !_isChecking) ? () => _goToAyah(-1) : null,
          ),
          Text('Verse ${_currentIndex + 1} / ${_ayahs.length}'),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios),
            onPressed: (_currentIndex < _ayahs.length - 1 && !_isChecking) ? () => _goToAyah(1) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildCheckingControls() {
    String statusText;
    if (_isChecking) {
      final correct = _liveResult?.correctCount ?? 0;
      final total = _liveResult?.expectedWordStatus.length ?? tokenize(_currentAyah.text).length;
      statusText = 'Listening... $correct/$total correct so far';
    } else if (_showingFinalSummary && _liveResult != null) {
      final correct = _liveResult!.correctCount;
      final total = _liveResult!.expectedWordStatus.length;
      final pct = (_liveResult!.accuracy * 100).toStringAsFixed(0);
      statusText = '$correct/$total words correct ($pct%)';
    } else {
      statusText = 'Tap to check your recitation';
    }

    return Column(
      children: [
        Text(statusText, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _toggleChecking,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: _isChecking ? Colors.red : Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isChecking ? Icons.stop : Icons.mic,
              color: Colors.white,
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_showingFinalSummary && !_isChecking)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _playLastRecording,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play Back'),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _showingFinalSummary = false;
                  _liveResult = null;
                }),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
              FilledButton.icon(
                onPressed: _currentIndex < _ayahs.length - 1 ? () => _goToAyah(1) : null,
                icon: const Icon(Icons.check),
                label: const Text('Next Verse'),
              ),
            ],
          ),
      ],
    );
  }
}
