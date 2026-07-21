import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_companion/models/quran_models.dart';
import 'package:hifz_companion/services/alignment/alignment_engine.dart';
import 'package:hifz_companion/services/alignment/alignment_models.dart';
import 'package:hifz_companion/services/alignment/recovery_engine.dart';
import 'package:hifz_companion/services/alignment/scoring_engine.dart';
import 'package:hifz_companion/services/alignment/teacher_response_engine.dart';
import 'package:hifz_companion/services/word_matcher.dart' show tokenize;

AyahInfo _ayah(int surah, int ayah, String text) {
  return AyahInfo(surah: surah, ayah: ayah, juz: 1, text: text, transliteration: '');
}

List<TimedWord> _words(String sentence) {
  return sentence.split(' ').map((w) => TimedWord(w)).toList();
}

void main() {
  final engine = AlignmentEngine();

  group('Perfect recitation', () {
    test('all words correct, passage complete, no errors', () {
      final passage = [_ayah(1, 1, 'بسم الله الرحمن الرحيم')];
      final result = engine.comparePassage(
        expectedAyahs: passage,
        recognizedWords: _words('بسم الله الرحمن الرحيم'),
      );

      expect(result.errors, isEmpty);
      expect(result.passageComplete, isTrue);
      expect(result.correctCount, equals(4));
      expect(result.wordAccuracy, equals(1.0));
    });
  });

  group('Single substitution', () {
    test('one wrong word is flagged as wordSubstitution', () {
      final passage = [_ayah(1, 1, 'بسم الله الرحمن الرحيم')];
      final result = engine.comparePassage(
        expectedAyahs: passage,
        recognizedWords: _words('بسم الله الكريم الرحيم'),
      );

      final subErrors = result.errors.where((e) => e.type == ErrorType.wordSubstitution);
      expect(subErrors.length, equals(1));
      expect(subErrors.first.expectedWord, equals('الرحمن'));
    });
  });

  group('Missing word', () {
    test('a dropped word is flagged as wordOmission', () {
      final passage = [_ayah(1, 1, 'بسم الله الرحمن الرحيم')];
      final result = engine.comparePassage(
        expectedAyahs: passage,
        recognizedWords: _words('بسم الرحمن الرحيم'), // "الله" dropped
      );

      final omissions = result.errors.where((e) => e.type == ErrorType.wordOmission);
      expect(omissions.length, equals(1));
      expect(omissions.first.expectedWord, equals('الله'));
    });
  });

  group('Extra word', () {
    test('an inserted word not in the expected text is flagged', () {
      final passage = [_ayah(1, 1, 'بسم الله الرحمن الرحيم')];
      final result = engine.comparePassage(
        expectedAyahs: passage,
        recognizedWords: _words('بسم الله جدا الرحمن الرحيم'), // "جدا" inserted
      );

      expect(result.errors.any((e) => e.type == ErrorType.wordInsertion), isTrue);
      // The genuine words should still align correctly around the insertion.
      expect(result.correctCount, equals(4));
    });
  });

  group('Skipped ayah', () {
    test('an entire ayah with no matching words is flagged as ayahSkipped', () {
      final passage = [
        _ayah(1, 1, 'بسم الله الرحمن الرحيم'),
        _ayah(1, 2, 'الحمد لله رب العالمين'),
      ];
      // Only the second ayah was recited; the first was skipped entirely.
      final result = engine.comparePassage(
        expectedAyahs: passage,
        recognizedWords: _words('الحمد لله رب العالمين'),
      );

      expect(result.errors.any((e) => e.type == ErrorType.ayahSkipped), isTrue);
    });
  });

  group('Scoring engine', () {
    test('perfect recitation scores 100% word accuracy', () {
      final passage = [_ayah(1, 1, 'بسم الله الرحمن الرحيم')];
      final result = engine.comparePassage(
        expectedAyahs: passage,
        recognizedWords: _words('بسم الله الرحمن الرحيم'),
      );
      final score = ScoringEngine().calculateScore(
        result: result,
        totalAyahsInPassage: 1,
        fullyCorrectAyahs: 1,
      );
      expect(score.wordAccuracy, equals(1.0));
      expect(score.tajweedScorePlaceholder, isNull);
      expect(score.pronunciationScorePlaceholder, isNull);
    });
  });

  group('Teacher response engine', () {
    test('perfect completion gives an encouraging deterministic message', () {
      final passage = [_ayah(1, 1, 'بسم الله الرحمن الرحيم')];
      final result = engine.comparePassage(
        expectedAyahs: passage,
        recognizedWords: _words('بسم الله الرحمن الرحيم'),
      );
      final feedback = TeacherResponseEngine().generateFeedback(result: result);
      expect(feedback, equals('Excellent. Continue to the next verse.'));
    });

    test('substitution gives a specific correction message', () {
      final passage = [_ayah(1, 1, 'بسم الله الرحمن الرحيم')];
      final result = engine.comparePassage(
        expectedAyahs: passage,
        recognizedWords: _words('بسم الله الكريم الرحيم'),
      );
      final error = result.errors.firstWhere((e) => e.type == ErrorType.wordSubstitution);
      final feedback = TeacherResponseEngine().generateFeedback(
        result: result,
        mostRecentError: error,
      );
      expect(feedback, contains('الرحمن'));
    });
  });

  group('Recovery engine', () {
    test('suggests repeating from the mistake for a substitution', () {
      final passage = [_ayah(1, 1, 'بسم الله الرحمن الرحيم')];
      final result = engine.comparePassage(
        expectedAyahs: passage,
        recognizedWords: _words('بسم الله الكريم الرحيم'),
      );
      final error = result.errors.firstWhere((e) => e.type == ErrorType.wordSubstitution);
      final flattened = FlattenedPassage.fromAyahs(passage, tokenize);
      final recovery = RecoveryEngine().suggestRecoveryPoint(error: error, passage: flattened);
      expect(recovery.instruction, equals('Repeat from this word.'));
      expect(recovery.ayahNumber, equals(1));
    });
  });
}
