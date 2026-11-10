# Cricket Scorer: instructions for Claude Code

Flutter app for university project EF101-P02. Read README.md first: it holds
the scoring and dismissal tables that the code must follow exactly.

## Layering rules (do not break)

- `lib/domain` is pure Dart. It must not import Flutter, sqflite or anything in
  `lib/data`, `lib/application` or `lib/ui`.
- ALL cricket rules live in `lib/domain/innings.dart` (`InningsState.apply`).
  Controllers and screens must never compute runs, overs, strike or wickets.
- Screens only talk to controllers in `lib/application`. Controllers only talk
  to the repository interfaces in `lib/domain/repositories.dart`.
- SQL lives only in `lib/data`. Plain `sqflite`, no ORM.
- An innings is rebuilt by replaying its deliveries (`replayInnings`); never
  store a second copy of a total.

## Commands

```
flutter analyze
flutter test
```

## Definition of done

1. `flutter analyze` reports no issues.
2. `flutter test` passes.
3. A rule change updates README.md tables and a unit test in the same commit.
4. Write the test first for engine changes.

## Style

Dart 3, null safety, `const` where possible, short doc comments on public
classes. Prefer small pure functions in the domain layer.
