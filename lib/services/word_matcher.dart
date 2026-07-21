/// Status of a single expected word after aligning against what was recognized.
enum WordStatus { pending, correct, wrong, missing }

class WordMatchResult {
  final List<WordStatus> expectedWordStatus; // one entry per expected word
  final List<String?> recognizedWordForExpected; // what was heard at that
  // position, if anything (for showing "you said X, expected Y")
  final int extraWordCount; // spoken words that didn't align to any expected word
  final int correctCount;
  final int currentPosition; // index of the next expected word still pending

  WordMatchResult({
    required this.expectedWordStatus,
    required this.recognizedWordForExpected,
    required this.extraWordCount,
    required this.correctCount,
    required this.currentPosition,
  });

  double get accuracy {
    final total = expectedWordStatus.length;
    if (total == 0) return 0;
    return correctCount / total;
  }
}

/// Normalizes Arabic text for comparison: strips diacritics (tashkeel),
/// normalizes alef variants, and removes punctuation, so minor recognizer
/// differences in diacritics don't register as word-level mistakes (that is
/// a Tajweed-level concern, handled separately, not a memorization mistake).
///
/// IMPORTANT: the bundled Quran text uses full Uthmani script, which
/// includes Quranic-only annotation marks and letter forms (e.g. alef wasla
/// "ٱ") that a standard speech-to-text model will never produce - it
/// transcribes using plain modern Arabic forms instead. Every one of these
/// must be normalized away on both sides of the comparison, or otherwise-
/// correct recitation gets flagged as wrong purely due to script
/// differences, not an actual mistake. This was a real bug found via live
/// testing (see conversation history) - previously only standard
/// diacritics were handled, missing alef wasla and Quranic-specific small
/// marks, which caused near-universal false "wrong word" results.
String normalizeArabic(String input) {
  var text = input;
  // Strip standard Arabic diacritics (harakat/tashkeel).
  text = text.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
  // Strip Quranic-only small high/low annotation marks (sukun, small high
  // seen, small high madda, small high yeh/noon, etc.) used throughout
  // Uthmani script but never produced by standard Arabic ASR output.
  text = text.replaceAll(RegExp(r'[\u0610-\u061A\u06D6-\u06DC\u06DF-\u06E4\u06E7-\u06E8\u06EA-\u06ED]'), '');
  // Strip extended Arabic diacritic blocks (Quranic annotation, rare but
  // present in some Uthmani text sources).
  text = text.replaceAll(RegExp(r'[\u08D4-\u08E1\u08E3-\u08FF]'), '');
  // Normalize all alef variants - INCLUDING alef wasla "ٱ" (U+0671), which
  // is extremely common in Quranic text (e.g. ٱلرَّحْمَٰنِ, ٱللَّهِ) but is
  // never how a speech-to-text model transcribes plain alef - to bare alef.
  text = text.replaceAll(RegExp(r'[\u0622\u0623\u0625\u0671\u0672\u0673]'), '\u0627');
  // Normalize alef maksura to yeh
  text = text.replaceAll('\u0649', '\u064A');
  // Remove tatweel (kashida)
  text = text.replaceAll('\u0640', '');
  // Strip punctuation/whitespace edges
  text = text.trim();
  return text;
}

List<String> tokenize(String text) {
  return text
      .split(RegExp(r'\s+'))
      .map(normalizeArabic)
      .where((w) => w.isNotEmpty)
      .toList();
}

/// Aligns the recognized words against the expected ayah words using a
/// Levenshtein-style edit-distance alignment (Needleman-Wunsch), so each
/// discrepancy is classified as correct / wrong / missing, with position.
/// Spoken words that don't correspond to any expected word are counted as
/// "extra" separately.
WordMatchResult alignWords({
  required List<String> expectedWords,
  required List<String> recognizedWords,
}) {
  final m = expectedWords.length;
  final n = recognizedWords.length;

  // dp[i][j] = min edit operations to align expected[0..i) with recognized[0..j)
  final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  for (var i = 0; i <= m; i++) dp[i][0] = i;
  for (var j = 0; j <= n; j++) dp[0][j] = j;

  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      if (expectedWords[i - 1] == recognizedWords[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1];
      } else {
        final substitution = dp[i - 1][j - 1] + 1;
        final deletion = dp[i - 1][j] + 1; // expected word missing
        final insertion = dp[i][j - 1] + 1; // extra spoken word
        dp[i][j] = [substitution, deletion, insertion].reduce((a, b) => a < b ? a : b);
      }
    }
  }

  // Backtrack to build the alignment
  final expectedStatus = List<WordStatus>.filled(m, WordStatus.missing);
  final recognizedForExpected = List<String?>.filled(m, null);
  var extraCount = 0;
  var correctCount = 0;

  var i = m, j = n;
  final ops = <String>[]; // for backtracking order (reversed)
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && expectedWords[i - 1] == recognizedWords[j - 1] && dp[i][j] == dp[i - 1][j - 1]) {
      expectedStatus[i - 1] = WordStatus.correct;
      recognizedForExpected[i - 1] = recognizedWords[j - 1];
      correctCount++;
      i--;
      j--;
    } else if (i > 0 && j > 0 && dp[i][j] == dp[i - 1][j - 1] + 1) {
      expectedStatus[i - 1] = WordStatus.wrong;
      recognizedForExpected[i - 1] = recognizedWords[j - 1];
      i--;
      j--;
    } else if (i > 0 && dp[i][j] == dp[i - 1][j] + 1) {
      expectedStatus[i - 1] = WordStatus.missing;
      i--;
    } else {
      // insertion - extra spoken word not matching any expected word
      extraCount++;
      j--;
    }
    ops.add(''); // placeholder, order not otherwise needed
  }

  // Find how far into the ayah the recitation has progressed: the last
  // expected word that has a non-pending status, +1. Words after that are
  // still "pending" (not yet reached), not "missing" - only backtrack marks
  // trailing words as missing if the recognizer has clearly moved past them
  // (i.e. recognizedWords is non-empty and alignment placed later words
  // after them). We approximate "pending" as: any run of missing words at
  // the very end of the ayah, beyond the recognized content, is pending
  // rather than a mistake, since the user simply hasn't recited them yet.
  var lastNonMissingFromEnd = m; // exclusive index
  for (var k = m - 1; k >= 0; k--) {
    if (expectedStatus[k] != WordStatus.missing) {
      lastNonMissingFromEnd = k + 1;
      break;
    }
    lastNonMissingFromEnd = k;
  }
  for (var k = lastNonMissingFromEnd; k < m; k++) {
    expectedStatus[k] = WordStatus.pending;
  }

  return WordMatchResult(
    expectedWordStatus: expectedStatus,
    recognizedWordForExpected: recognizedForExpected,
    extraWordCount: extraCount,
    correctCount: correctCount,
    currentPosition: lastNonMissingFromEnd,
  );
}
