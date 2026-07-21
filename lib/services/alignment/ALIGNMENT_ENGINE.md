# Alignment Engine (Phase 3)

A standalone, audio-independent engine that compares an expected Quran
passage against a recognized word sequence. It takes only plain data in
(ayah objects, word strings, optional timestamps as numbers) and returns
only plain data out — no microphone access, no HTTP calls, no speech
recognition SDK of any kind. That's what makes it fully testable on its
own (see `test/alignment_engine_test.dart`) and swappable to any future
recognition provider without touching this code.

## What's here vs. what was trimmed from the original spec

This phase was requested as a large enterprise-style spec (architecture
diagrams, "Principal Engineer" framing, millions-of-sessions scaling
targets, a "word order change" detection category, precise performance
SLAs). Those were deliberately left out — they're not real engineering
requirements for an app at this stage, and building fake versions of them
(e.g. a benchmark suite claiming to validate "millions of sessions" that
was never actually load-tested) would be worse than not having them. What's
built here is the genuinely useful core:

- Multi-ayah passage comparison (not just single-ayah, like Phase 2's
  `word_matcher.dart` — which this engine builds on top of, not replaces)
- A trimmed, honest error taxonomy (10 categories, see below)
- Deterministic scoring, teacher feedback, and recovery suggestions
- Persistent mistake/session logging for future weak-area analysis
- Real unit tests covering the core detection cases

**Not implemented, and why:**
- **Word order change** as its own category — reliably telling a genuine
  word swap apart from two coincidental substitutions isn't something a
  text-only alignment can do with real confidence. Rather than guess, this
  case falls through to `wordSubstitution`/`unknownSequence`.
- **Ayah repetition detection** — stubbed with a comment, not implemented.
  Detecting "the user repeated the whole previous ayah" reliably needs more
  signal than this text-only engine has yet; marking it as implemented
  when it isn't would be misleading.
- **Tajweed/pronunciation scores** — `ScoreReport` has explicit `null`
  placeholders for these, matching the Phase 5 roadmap's honest framing:
  this is a hard, unsolved-industry-wide problem, not something to fake a
  number for.

## API

| Function | Purpose |
|---|---|
| `AlignmentEngine.comparePassage()` | Core comparison — returns `AlignmentResult` |
| `AlignmentEngine.detectStoppedTooEarly()` | Call once the user explicitly stops, to check for an incomplete passage |
| `ScoringEngine.calculateScore()` | Word/ayah accuracy, completion %, consistency, overall score |
| `TeacherResponseEngine.generateFeedback()` | Fixed, deterministic feedback strings — never generated/random text |
| `RecoveryEngine.suggestRecoveryPoint()` | Where to resume from, with a plain-language reason |
| `DbHelper.recordMistake()` / `recordSession()` | Persist mistakes/sessions for weak-area tracking |
| `DbHelper.frequentlyMissedWords()` / `weakAyahs()` / `weakSurahs()` | Query the logged history |

## Error taxonomy

`wordSubstitution`, `wordOmission`, `wordInsertion`, `wordRepetition`,
`ayahSkipped`, `ayahRepeated` (detection stubbed, see above),
`stoppedTooEarly`, `longHesitation`, `wrongResume`, `unknownSequence`.

Every `RecitationError` includes a `confidence` value (0.0-1.0) — this is a
heuristic based on how the alignment reached that conclusion, not a
calibrated probability. Treat it as "how much to trust this particular
flag," not a statistically validated number.

## Future speech recognition integration

To connect a live recognizer (the Phase 2 Groq-based one, or a future
on-device Phase 3 offline model, or anything else):

1. Get recognized words out of your recognizer as plain strings, with
   timestamps if available (seconds since the session started)
2. Wrap them as `TimedWord(word, timestampSeconds)`
3. Call `AlignmentEngine().comparePassage(expectedAyahs: [...], recognizedWords: [...])`
4. Feed the result to `ScoringEngine`, `TeacherResponseEngine`, and
   `RecoveryEngine` as needed
5. Log mistakes via `DbHelper.recordMistake()` for each `RecitationError`,
   and call `DbHelper.recordSession()` once the session ends

This engine does not currently replace `RecitationCheckService` from Phase
2 (which still uses the simpler single-ayah `word_matcher.dart`) — wiring
this richer multi-ayah engine into the live Recitation Screen is a
follow-up integration step, not done in this phase, since the brief for
this phase explicitly excluded UI and speech recognition changes.
