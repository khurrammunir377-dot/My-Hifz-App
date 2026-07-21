import 'alignment_models.dart';

/// Suggests the best point for a student to resume from after a mistake.
/// The rules here are intentionally simple and explainable - a student
/// should always be able to understand *why* the app suggested a given
/// recovery point, rather than trusting an opaque decision.
class RecoveryEngine {
  RecoveryPoint suggestRecoveryPoint({
    required RecitationError error,
    required FlattenedPassage passage,
  }) {
    final index = error.recoveryWordIndex.clamp(0, passage.words.length - 1);
    final ref = passage.words[index];

    String instruction;
    switch (error.type) {
      case ErrorType.wordSubstitution:
      case ErrorType.wordOmission:
        instruction = 'Repeat from this word.';
        break;
      case ErrorType.ayahSkipped:
        instruction = 'Return to the start of this ayah.';
        break;
      case ErrorType.ayahRepeated:
        instruction = 'Continue to the next ayah.';
        break;
      case ErrorType.stoppedTooEarly:
        instruction = 'Continue from where you stopped.';
        break;
      case ErrorType.longHesitation:
        instruction = 'Continue from this word when ready.';
        break;
      case ErrorType.wrongResume:
      case ErrorType.unknownSequence:
        instruction = 'Return to this word and continue carefully.';
        break;
      case ErrorType.wordInsertion:
      case ErrorType.wordRepetition:
        instruction = 'Continue from here.';
        break;
    }

    return RecoveryPoint(
      flatWordIndex: index,
      surahNumber: ref.surahNumber,
      ayahNumber: ref.ayahNumber,
      wordIndexInAyah: ref.wordIndexInAyah,
      instruction: instruction,
    );
  }
}
