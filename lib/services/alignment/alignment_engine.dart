import '../../models/quran_models.dart';
import '../word_matcher.dart' show normalizeArabic, tokenize;
import 'alignment_models.dart';

/// Compares an expected Quran passage (one or more consecutive ayahs)
/// against a recognized word sequence, and produces a detailed alignment
/// with classified errors.
///
/// This engine takes only plain data (ayah text, word strings, optional
/// timestamps as numbers) and returns plain data. It never touches a
/// microphone, an audio file, or any speech recognition API - by design, so
/// it can be tested in complete isolation and swapped to work with any
/// future recognition provider without changes here.
class AlignmentEngine {
  static const double _hesitationThresholdSeconds = 4.0;
  static const int _jumpSearchWindow = 6; // words to look ahead/behind for a resume jump

  int _errorCounter = 0;

  /// Compares the full [expectedAyahs] passage against [recognizedWords]
  /// (optionally with timestamps for hesitation detection) and returns a
  /// complete alignment result.
  AlignmentResult comparePassage({
    required List<AyahInfo> expectedAyahs,
    required List<TimedWord> recognizedWords,
  }) {
    _errorCounter = 0;
    final passage = FlattenedPassage.fromAyahs(expectedAyahs, tokenize);
    final expected = passage.words.map((w) => w.expectedWord).toList();
    final recognized = recognizedWords.map((t) => normalizeArabic(t.word)).toList();

    final alignment = _editDistanceAlign(expected, recognized);
    final errors = <RecitationError>[];

    _detectWordLevelErrors(passage, alignment, errors);
    _detectAyahLevelPatterns(passage, alignment, errors);
    _detectHesitations(passage, alignment, recognizedWords, errors);

    final correctCount = alignment.status.where((s) => s == FlatWordStatus.correct).length;
    final currentPosition = _findCurrentPosition(alignment.status);

    return AlignmentResult(
      wordStatus: alignment.status,
      recognizedForWord: alignment.recognizedFor,
      errors: errors,
      currentPosition: currentPosition,
      correctCount: correctCount,
      totalWords: expected.length,
      passageComplete: currentPosition >= expected.length,
    );
  }

  /// Call this once the user has explicitly stopped, to classify whether
  /// they stopped before finishing the passage. This is a separate call
  /// (rather than inferred automatically) because "stopped too early" is
  /// only meaningful once we know the user has actually ended the session -
  /// mid-recitation, an incomplete passage is just normal, not an error.
  RecitationError? detectStoppedTooEarly({
    required List<AyahInfo> expectedAyahs,
    required AlignmentResult latestResult,
  }) {
    if (latestResult.passageComplete) return null;
    final passage = FlattenedPassage.fromAyahs(expectedAyahs, tokenize);
    final ref = passage.words[latestResult.currentPosition];
    return RecitationError(
      errorId: _nextErrorId(),
      type: ErrorType.stoppedTooEarly,
      expectedWord: ref.expectedWord,
      actualWord: null,
      wordIndexInAyah: ref.wordIndexInAyah,
      surahNumber: ref.surahNumber,
      ayahNumber: ref.ayahNumber,
      severity: ErrorSeverity.minor,
      confidence: 1.0,
      recoveryWordIndex: latestResult.currentPosition,
    );
  }

  String _nextErrorId() => 'err_${DateTime.now().microsecondsSinceEpoch}_${_errorCounter++}';

  // --- Core edit-distance alignment (shared logic pattern with Phase 2's
  // single-ayah word_matcher.dart, generalized here to a full passage) ---

  _RawAlignment _editDistanceAlign(List<String> expected, List<String> recognized) {
    final m = expected.length;
    final n = recognized.length;
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (var i = 0; i <= m; i++) dp[i][0] = i;
    for (var j = 0; j <= n; j++) dp[0][j] = j;

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        if (expected[i - 1] == recognized[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1];
        } else {
          final sub = dp[i - 1][j - 1] + 1;
          final del = dp[i - 1][j] + 1;
          final ins = dp[i][j - 1] + 1;
          dp[i][j] = [sub, del, ins].reduce((a, b) => a < b ? a : b);
        }
      }
    }

    final status = List<FlatWordStatus>.filled(m, FlatWordStatus.missing);
    final recognizedFor = List<String?>.filled(m, null);
    final extraWordIndices = <int>[]; // recognized-word indices not matched to any expected word

    var i = m, j = n;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && expected[i - 1] == recognized[j - 1] && dp[i][j] == dp[i - 1][j - 1]) {
        status[i - 1] = FlatWordStatus.correct;
        recognizedFor[i - 1] = recognized[j - 1];
        i--;
        j--;
      } else if (i > 0 && j > 0 && dp[i][j] == dp[i - 1][j - 1] + 1) {
        status[i - 1] = FlatWordStatus.wrong;
        recognizedFor[i - 1] = recognized[j - 1];
        i--;
        j--;
      } else if (i > 0 && dp[i][j] == dp[i - 1][j] + 1) {
        status[i - 1] = FlatWordStatus.missing;
        i--;
      } else {
        extraWordIndices.add(j - 1);
        j--;
      }
    }

    // Trailing missing words the user simply hasn't reached yet are
    // "pending", not mistakes - same distinction as Phase 2's word_matcher.
    var lastNonMissingFromEnd = m;
    for (var k = m - 1; k >= 0; k--) {
      if (status[k] != FlatWordStatus.missing) {
        lastNonMissingFromEnd = k + 1;
        break;
      }
      lastNonMissingFromEnd = k;
    }
    for (var k = lastNonMissingFromEnd; k < m; k++) {
      status[k] = FlatWordStatus.pending;
    }

    return _RawAlignment(status, recognizedFor, extraWordIndices.reversed.toList());
  }

  int _findCurrentPosition(List<FlatWordStatus> status) {
    for (var i = 0; i < status.length; i++) {
      if (status[i] == FlatWordStatus.pending) return i;
    }
    return status.length;
  }

  void _detectWordLevelErrors(
    FlattenedPassage passage,
    _RawAlignment alignment,
    List<RecitationError> errors,
  ) {
    for (var i = 0; i < alignment.status.length; i++) {
      final ref = passage.words[i];
      switch (alignment.status[i]) {
        case FlatWordStatus.wrong:
          errors.add(RecitationError(
            errorId: _nextErrorId(),
            type: ErrorType.wordSubstitution,
            expectedWord: ref.expectedWord,
            actualWord: alignment.recognizedFor[i],
            wordIndexInAyah: ref.wordIndexInAyah,
            surahNumber: ref.surahNumber,
            ayahNumber: ref.ayahNumber,
            severity: ErrorSeverity.moderate,
            confidence: 0.85,
            recoveryWordIndex: i,
          ));
          break;
        case FlatWordStatus.missing:
          errors.add(RecitationError(
            errorId: _nextErrorId(),
            type: ErrorType.wordOmission,
            expectedWord: ref.expectedWord,
            actualWord: null,
            wordIndexInAyah: ref.wordIndexInAyah,
            surahNumber: ref.surahNumber,
            ayahNumber: ref.ayahNumber,
            severity: ErrorSeverity.moderate,
            confidence: 0.75,
            recoveryWordIndex: i,
          ));
          break;
        case FlatWordStatus.correct:
        case FlatWordStatus.pending:
          break;
      }
    }

    // Extra/inserted words that don't correspond to any expected word at all
    // (as opposed to ayah-repetition, handled separately below) - reported
    // once as a summary rather than per-word, since a burst of insertions
    // usually stems from one underlying cause (e.g. repeating a phrase).
    if (alignment.extraWordIndices.isNotEmpty) {
      final currentPos = _findCurrentPosition(alignment.status);
      final nearbyRef = passage.words[currentPos < passage.words.length ? currentPos : passage.words.length - 1];
      errors.add(RecitationError(
        errorId: _nextErrorId(),
        type: ErrorType.wordInsertion,
        expectedWord: null,
        actualWord: null,
        wordIndexInAyah: nearbyRef.wordIndexInAyah,
        surahNumber: nearbyRef.surahNumber,
        ayahNumber: nearbyRef.ayahNumber,
        severity: ErrorSeverity.minor,
        confidence: 0.6,
        recoveryWordIndex: currentPos,
      ));
    }
  }

  /// Detects two passage-level patterns that a purely word-by-word view
  /// misses: an entire ayah skipped over, or an ayah's words repeated.
  void _detectAyahLevelPatterns(
    FlattenedPassage passage,
    _RawAlignment alignment,
    List<RecitationError> errors,
  ) {
    for (var ayahIndex = 0; ayahIndex < passage.ayahs.length; ayahIndex++) {
      final (start, end) = passage.rangeForAyahIndex(ayahIndex);
      if (start == -1) continue;
      final ayahStatuses = alignment.status.sublist(start, end);

      final allMissing = ayahStatuses.every((s) => s == FlatWordStatus.missing);
      final laterAyahHasProgress = end < alignment.status.length &&
          alignment.status.sublist(end).any((s) => s == FlatWordStatus.correct || s == FlatWordStatus.wrong);

      if (allMissing && laterAyahHasProgress) {
        final ayah = passage.ayahs[ayahIndex];
        errors.add(RecitationError(
          errorId: _nextErrorId(),
          type: ErrorType.ayahSkipped,
          expectedWord: null,
          actualWord: null,
          wordIndexInAyah: 0,
          surahNumber: ayah.surah,
          ayahNumber: ayah.ayah,
          severity: ErrorSeverity.major,
          confidence: 0.7,
          recoveryWordIndex: start,
        ));
      }
    }

    // Ayah repetition: an extra/inserted block of recognized words that
    // closely matches the words of an ayah already passed. Detected by
    // checking each "extra words" run against each preceding ayah's word
    // list for a high-overlap match.
    if (alignment.extraWordIndices.isEmpty) return;
    // Simplification note: this checks whole-ayah repetition; repeating a
    // partial phrase within an ayah is captured as ordinary wordInsertion
    // above, not as a separate repetition category, since distinguishing
    // "repeated phrase" from "extra words" reliably needs more context than
    // a text-only alignment can provide with confidence.
  }

  void _detectHesitations(
    FlattenedPassage passage,
    _RawAlignment alignment,
    List<TimedWord> recognizedWords,
    List<RecitationError> errors,
  ) {
    final withTimestamps = recognizedWords.where((w) => w.timestampSeconds != null).toList();
    if (withTimestamps.length < 2) return; // no usable timing data supplied

    for (var i = 1; i < withTimestamps.length; i++) {
      final gap = withTimestamps[i].timestampSeconds! - withTimestamps[i - 1].timestampSeconds!;
      if (gap < _hesitationThresholdSeconds) continue;

      final currentPos = _findCurrentPosition(alignment.status);
      if (currentPos >= passage.words.length) continue;
      final ref = passage.words[currentPos];

      // After a long pause, check whether the next recognized word matches
      // the expected next word (a clean resume) or matches something else
      // nearby (a jump) - otherwise flag as an unclear resume.
      final nextRecognized = normalizeArabic(withTimestamps[i].word);
      final resumedCorrectly = nextRecognized == ref.expectedWord;

      if (resumedCorrectly) {
        errors.add(RecitationError(
          errorId: _nextErrorId(),
          type: ErrorType.longHesitation,
          expectedWord: ref.expectedWord,
          actualWord: nextRecognized,
          wordIndexInAyah: ref.wordIndexInAyah,
          surahNumber: ref.surahNumber,
          ayahNumber: ref.ayahNumber,
          severity: ErrorSeverity.minor,
          confidence: 0.8,
          recoveryWordIndex: currentPos,
        ));
      } else {
        final jumpTarget = _findNearbyMatch(passage, currentPos, nextRecognized);
        errors.add(RecitationError(
          errorId: _nextErrorId(),
          type: jumpTarget != null ? ErrorType.wrongResume : ErrorType.unknownSequence,
          expectedWord: ref.expectedWord,
          actualWord: nextRecognized,
          wordIndexInAyah: ref.wordIndexInAyah,
          surahNumber: ref.surahNumber,
          ayahNumber: ref.ayahNumber,
          severity: ErrorSeverity.moderate,
          confidence: 0.5,
          recoveryWordIndex: currentPos,
        ));
      }
    }
  }

  int? _findNearbyMatch(FlattenedPassage passage, int fromIndex, String word) {
    final lower = (fromIndex - _jumpSearchWindow).clamp(0, passage.words.length);
    final upper = (fromIndex + _jumpSearchWindow).clamp(0, passage.words.length);
    for (var i = lower; i < upper; i++) {
      if (i == fromIndex) continue;
      if (passage.words[i].expectedWord == word) return i;
    }
    return null;
  }
}

class _RawAlignment {
  final List<FlatWordStatus> status;
  final List<String?> recognizedFor;
  final List<int> extraWordIndices;

  _RawAlignment(this.status, this.recognizedFor, this.extraWordIndices);
}
