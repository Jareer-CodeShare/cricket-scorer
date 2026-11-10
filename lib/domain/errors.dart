/// Thrown when a scoring action breaks a rule of cricket or does not fit the
/// current state of the innings. The message is written for the scorer and is
/// shown directly in the UI.
class ScoringException implements Exception {
  ScoringException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when team, player or match set-up is not acceptable (empty name,
/// duplicate team, team too small to play, ...). The message is shown in the UI.
class SetupException implements Exception {
  SetupException(this.message);

  final String message;

  @override
  String toString() => message;
}
