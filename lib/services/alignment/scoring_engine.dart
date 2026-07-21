import 'alignment_models.dart';

/// Calculates scores from an alignment result. Every number here is derived
/// directly from the alignment data - nothing is invented or estimated from
/// factors the engine doesn't actually have (which is why Tajweed and
/// pronunciation scores stay as explicit null placeholders in ScoreReport
/// rather than being filled with a guessed value).
class ScoringEngine {
  ScoreReport calculateScore({
    required AlignmentResult result,
    required int totalAyahsInPassage,
    required int fullyCorrectAyahs,
  }) {
    final wordAccuracy = result.wordAccuracy;
    final ayahAccuracy = totalAyahsInPassage == 0 ? 0.0 : fullyCorrectAyahs / totalAyahsInPassage;
    final completionPercent = result.totalWords == 0 ? 0.0 : result.currentPosition / result.totalWords;
    final mistakeCount = result.errors.length;

    // Consistency: penalizes scattered mistakes across many ayahs more than
    // the same mistake count concentrated in one place, on the reasoning
    // that scattered errors suggest less stable memorization overall.
    final distinctAyahsWithErrors = result.errors.map((e) => e.ayahNumber).toSet().length;
    final consistencyScore = totalAyahsInPassage == 0
        ? 1.0
        : (1.0 - (distinctAyahsWithErrors / totalAyahsInPassage)).clamp(0.0, 1.0);

    // Overall score: weighted toward word accuracy (the most reliable
    // signal this engine has), with completion and consistency as smaller
    // factors. This weighting is a design choice, not a derived constant -
    // revisit it once real usage data suggests a better balance.
    final overallScore =
        (wordAccuracy * 0.6) + (completionPercent * 0.25) + (consistencyScore * 0.15);

    return ScoreReport(
      wordAccuracy: wordAccuracy,
      ayahAccuracy: ayahAccuracy,
      completionPercent: completionPercent,
      mistakeCount: mistakeCount,
      consistencyScore: consistencyScore,
      overallScore: overallScore,
    );
  }
}
