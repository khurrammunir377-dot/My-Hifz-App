import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'wav_utils.dart';
import 'word_matcher.dart';

const int kSampleRate = 16000;
const int kNumChannels = 1;
// ~2.5 seconds per chunk: short enough to feel responsive, long enough for
// the speech model to have meaningful context. Tune this if latency numbers
// from real testing suggest a different sweet spot.
const int _chunkDurationMs = 2500;
const int _bytesPerChunk = (kSampleRate * kNumChannels * 2 * _chunkDurationMs) ~/ 1000;

enum ChunkStatus { sending, ok, networkError }

class LiveCheckUpdate {
  final WordMatchResult matchResult;
  final ChunkStatus lastChunkStatus;
  final int lastLatencyMs;
  final bool newMistakeDetectedThisUpdate;

  LiveCheckUpdate({
    required this.matchResult,
    required this.lastChunkStatus,
    required this.lastLatencyMs,
    required this.newMistakeDetectedThisUpdate,
  });
}

/// Handles continuous listening during recitation: streams raw audio from the
/// microphone, slices it into rolling chunks, sends each chunk to the
/// recognition backend as it's captured, and incrementally updates the
/// word-level match result as transcripts come back - while also saving the
/// full session audio locally so playback keeps working exactly as in Phase 1.
class RecitationCheckService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;

  final List<int> _pendingChunkBuffer = [];
  final List<int> _fullSessionBuffer = [];
  final List<String> _recognizedWords = [];

  String _endpointUrl = '';
  List<String> _expectedWords = [];

  final StreamController<LiveCheckUpdate> _updatesController =
      StreamController<LiveCheckUpdate>.broadcast();
  Stream<LiveCheckUpdate> get updates => _updatesController.stream;

  bool _isActive = false;
  bool get isActive => _isActive;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start({
    required String endpointUrl,
    required List<String> expectedWords,
  }) async {
    _endpointUrl = endpointUrl;
    _expectedWords = expectedWords;
    _pendingChunkBuffer.clear();
    _fullSessionBuffer.clear();
    _recognizedWords.clear();
    _isActive = true;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: kSampleRate,
        numChannels: kNumChannels,
      ),
    );

    _subscription = stream.listen((chunk) {
      _pendingChunkBuffer.addAll(chunk);
      _fullSessionBuffer.addAll(chunk);
      if (_pendingChunkBuffer.length >= _bytesPerChunk) {
        final toSend = List<int>.from(_pendingChunkBuffer);
        _pendingChunkBuffer.clear();
        _sendChunk(toSend);
      }
    });
  }

  Future<void> _sendChunk(List<int> pcmBytes) async {
    if (_endpointUrl.isEmpty) return;
    final wav = pcm16ToWav(
      pcmBytes: pcmBytes,
      sampleRate: kSampleRate,
      numChannels: kNumChannels,
    );

    final stopwatch = Stopwatch()..start();
    try {
      final response = await http
          .post(
            Uri.parse(_endpointUrl),
            headers: {'Content-Type': 'audio/wav'},
            body: wav,
          )
          .timeout(const Duration(seconds: 10));
      stopwatch.stop();

      if (response.statusCode != 200) {
        _emitUpdate(ChunkStatus.networkError, stopwatch.elapsedMilliseconds);
        return;
      }

      final body = response.body;
      String transcript = '';
      try {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        transcript = (decoded['transcript'] as String?) ?? '';
      } catch (_) {
        // Malformed response - treat as an empty transcript for this chunk
        // rather than crashing the session.
      }
      final newWords = tokenize(transcript);

      final previousCorrect = _currentMatchResult()?.correctCount ?? 0;
      _recognizedWords.addAll(newWords);
      final updatedResult = _currentMatchResult()!;
      final newMistake = updatedResult.correctCount <= previousCorrect &&
          updatedResult.expectedWordStatus.contains(WordStatus.wrong);

      _emitUpdate(ChunkStatus.ok, stopwatch.elapsedMilliseconds, newMistake: newMistake);
    } catch (_) {
      stopwatch.stop();
      _emitUpdate(ChunkStatus.networkError, stopwatch.elapsedMilliseconds);
    }
  }

  WordMatchResult? _currentMatchResult() {
    if (_expectedWords.isEmpty) return null;
    return alignWords(expectedWords: _expectedWords, recognizedWords: _recognizedWords);
  }

  void _emitUpdate(ChunkStatus status, int latencyMs, {bool newMistake = false}) {
    final result = _currentMatchResult();
    if (result == null || _updatesController.isClosed) return;
    _updatesController.add(LiveCheckUpdate(
      matchResult: result,
      lastChunkStatus: status,
      lastLatencyMs: latencyMs,
      newMistakeDetectedThisUpdate: newMistake,
    ));
  }

  /// Stops listening, flushes any leftover buffered audio as a final chunk,
  /// saves the full session as a local WAV file, and returns its path plus
  /// the final match result.
  Future<(String filePath, WordMatchResult finalResult)> stop() async {
    await _subscription?.cancel();
    await _recorder.stop();
    _isActive = false;

    if (_pendingChunkBuffer.isNotEmpty) {
      await _sendChunk(List<int>.from(_pendingChunkBuffer));
      _pendingChunkBuffer.clear();
    }

    final dir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${dir.path}/recordings');
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${recordingsDir.path}/session_$timestamp.wav';
    final wav = pcm16ToWav(
      pcmBytes: _fullSessionBuffer,
      sampleRate: kSampleRate,
      numChannels: kNumChannels,
    );
    await File(path).writeAsBytes(wav);

    final finalResult = _currentMatchResult() ??
        alignWords(expectedWords: _expectedWords, recognizedWords: const []);

    return (path, finalResult);
  }

  Future<void> stopSafelyIfActive() async {
    if (_isActive) {
      await stop();
    }
  }

  void dispose() {
    _subscription?.cancel();
    _recorder.dispose();
    _updatesController.close();
  }
}
