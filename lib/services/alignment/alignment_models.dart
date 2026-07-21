import '../../models/quran_models.dart';

/// Categories of recitation mistake the engine can detect. This is a
/// deliberately trimmed set versus a larger enterprise-style taxonomy -
/// "word order change" as a distinct category was dropped because reliably
/// distinguishing a genuine word-swap from two independent substitutions is
/// not something this engine can do with real confidence, and a fabricated
/// category that just guesses would be worse than not having it.
enum ErrorType {
  wordSubstitution,
  wordOmission,
  wordInsertion,
  wordRepetition,
  ayahSkipped,
  ayahRepeated,
  stoppedTooEarly,
  longHesitation,
  wrongResume,
  unknownSequence,
}

enum ErrorSeverity { minor, moderate, major }

class RecitationError {
  final String errorId;
  final ErrorType type;
  final String? expectedWord;
  final String? actualWord;
  final int? wordIndexInAyah;
  final int surahNumber;
  final int ayahNumber;
  final ErrorSeverity severity;
  final double confidence; // 0.0-1.0, heuristic - see AlignmentEngine docs
  final int recoveryWordIndex; // flat index into the passage to resume from

  RecitationError({
    required this.errorId,
    required this.type,
    this.expectedWord,
    this.actualWord,
    this.wordIndexInAyah,
    required this.surahNumber,
    required this.ayahNumber,
    required this.severity,
    required this.confidence,
    required this.recoveryWordIndex,
  });

  Map<String, dynamic> toJson() => {
        'errorId': errorId,
        'type': type.name,
        'expectedWord': expectedWord,
        'actualWord': actualWord,
        'wordIndexInAyah': wordIndexInAyah,
        'surahNumber': surahNumber,
        'ayahNumber': ayahNumber,
        'severity': severity.name,
        'confidence': confidence,
        'recoveryWordIndex': recoveryWordIndex,
      };
}

/// Maps each flat word index in the passage back to its Surah/Ayah/word
/// position, so the engine can operate on one flattened word list internally
/// while still reporting errors in terms a caller (or a person) understands.
class PassageWordRef {
  final int surahNumber;
  final int ayahNumber;
  final int ayahIndex; // index into the passage's ayah list
  final int wordIndexInAyah;
  final String expectedWord; // normalized

  PassageWordRef({
    required this.surahNumber,
    required this.ayahNumber,
    required this.ayahIndex,
    required this.wordIndexInAyah,
    required this.expectedWord,
  });
}

enum FlatWordStatus { pending, correct, wrong, missing }

class AlignmentResult {
  final List<FlatWordStatus> wordStatus; // one per expected word in the passage
  final List<String?> recognizedForWord;
  final List<RecitationError> errors;
  final int currentPosition; // flat index of next pending word
  final int correctCount;
  final int totalWords;
  final bool passageComplete;

  AlignmentResult({
    required this.wordStatus,
    required this.recognizedForWord,
    required this.errors,
    required this.currentPosition,
    required this.correctCount,
    required this.totalWords,
    required this.passageComplete,
  });

  double get wordAccuracy => totalWords == 0 ? 0 : correctCount / totalWords;
}

class RecoveryPoint {
  final int flatWordIndex;
  final int surahNumber;
  final int ayahNumber;
  final int wordIndexInAyah;
  final String instruction; // human-readable, deterministic - see RecoveryEngine

  RecoveryPoint({
    required this.flatWordIndex,
    required this.surahNumber,
    required this.ayahNumber,
    required this.wordIndexInAyah,
    required this.instruction,
  });
}

class ScoreReport {
  final double wordAccuracy;
  final double ayahAccuracy;
  final double completionPercent;
  final int mistakeCount;
  final double consistencyScore;
  final double overallScore;
  // Explicit placeholders - never populated with fabricated numbers. These
  // exist so the data model doesn't need to change when Tajweed/Makharij
  // detection (Phase 5, experimental) is ready to plug in real values.
  final double? tajweedScorePlaceholder = null;
  final double? pronunciationScorePlaceholder = null;

  ScoreReport({
    required this.wordAccuracy,
    required this.ayahAccuracy,
    required this.completionPercent,
    required this.mistakeCount,
    required this.consistencyScore,
    required this.overallScore,
  });
}

/// A single recognized word with an optional timestamp (seconds since the
/// recitation session started). Timestamps are supplied by the caller (e.g.
/// the recognition service, if the transcription API returns word-level
/// timing) - this engine never touches audio itself, so it only ever
/// receives numbers, never audio data.
class TimedWord {
  final String word;
  final double? timestampSeconds;

  TimedWord(this.word, [this.timestampSeconds]);
}

/// Flattens a passage of ayahs into one continuous, indexable word list with
/// back-references to Surah/Ayah/word position.
class FlattenedPassage {
  final List<PassageWordRef> words;
  final List<AyahInfo> ayahs;

  FlattenedPassage(this.words, this.ayahs);

  factory FlattenedPassage.fromAyahs(List<AyahInfo> ayahs, List<String> Function(String) tokenizer) {
    final refs = <PassageWordRef>[];
    for (var ayahIndex = 0; ayahIndex < ayahs.length; ayahIndex++) {
      final ayah = ayahs[ayahIndex];
      final words = tokenizer(ayah.text);
      for (var w = 0; w < words.length; w++) {
        refs.add(PassageWordRef(
          surahNumber: ayah.surah,
          ayahNumber: ayah.ayah,
          ayahIndex: ayahIndex,
          wordIndexInAyah: w,
          expectedWord: words[w],
        ));
      }
    }
    return FlattenedPassage(refs, ayahs);
  }

  /// The flat index range [start, end) occupied by a given ayah index.
  (int, int) rangeForAyahIndex(int ayahIndex) {
    var start = -1, end = -1;
    for (var i = 0; i < words.length; i++) {
      if (words[i].ayahIndex == ayahIndex) {
        start = start == -1 ? i : start;
        end = i + 1;
      }
    }
    return (start, end);
  }
}
