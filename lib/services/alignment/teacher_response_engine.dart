import 'alignment_models.dart';

/// Generates structured teacher feedback from a fixed set of deterministic
/// responses. This deliberately does NOT call any language model or
/// generate free text - the spec for this engine requires responses to be
/// structured and deterministic, and a fixed lookup table is the only way
/// to actually guarantee that.
class TeacherResponseEngine {
  String generateFeedback({
    required AlignmentResult result,
    RecitationError? mostRecentError,
  }) {
    if (result.passageComplete && result.errors.isEmpty) {
      return 'Excellent. Continue to the next verse.';
    }
    if (result.passageComplete && result.errors.isNotEmpty) {
      return 'Completed with ${result.errors.length} mistake(s) to review.';
    }
    if (mostRecentError == null) {
      return 'Continue.';
    }

    switch (mostRecentError.type) {
      case ErrorType.wordOmission:
        return 'You skipped a word. Repeat from "${mostRecentError.expectedWord ?? ''}".';
      case ErrorType.wordSubstitution:
        return 'That word wasn\'t quite right. The correct word is "${mostRecentError.expectedWord ?? ''}".';
      case ErrorType.wordInsertion:
        return 'It sounds like an extra word was added. Continue carefully from here.';
      case ErrorType.wordRepetition:
        return 'You repeated a word. Continue to the next one.';
      case ErrorType.ayahSkipped:
        return 'It looks like you skipped an ayah. Please return to Ayah ${mostRecentError.ayahNumber}.';
      case ErrorType.ayahRepeated:
        return 'You\'ve repeated this ayah. Continue to the next one when ready.';
      case ErrorType.stoppedTooEarly:
        return 'You stopped before finishing this ayah. Continue from "${mostRecentError.expectedWord ?? ''}".';
      case ErrorType.longHesitation:
        return 'Take your time. Continue from "${mostRecentError.expectedWord ?? ''}".';
      case ErrorType.wrongResume:
        return 'You resumed from a different part of the verse. Return to "${mostRecentError.expectedWord ?? ''}".';
      case ErrorType.unknownSequence:
        return 'That didn\'t match the expected verse. Please repeat this section.';
    }
  }
}
