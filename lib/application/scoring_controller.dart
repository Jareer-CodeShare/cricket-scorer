/// Holds a match while it is being scored or viewed. It owns no cricket rules:
/// every ball goes through `InningsState.apply` in the domain layer, and every
/// accepted ball is saved straight away so nothing is lost if the app closes.
library;

import 'package:flutter/foundation.dart';

import '../domain/errors.dart';
import '../domain/innings.dart';
import '../domain/match_result.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../domain/rules.dart';

/// One innings together with its current (replayed) state.
class InningsView {
  InningsView(this.info, this.config, this.state);

  final InningsInfo info;
  final InningsConfig config;
  InningsState state;
}

class ScoringController extends ChangeNotifier {
  ScoringController(this._matches, this._teams, this._players);

  final MatchRepository _matches;
  final TeamRepository _teams;
  final PlayerRepository _players;

  MatchInfo? match;
  List<InningsView> innings = [];
  bool loading = false;

  final Map<int, String> _playerNames = {};
  final Map<int, String> _teamNames = {};

  // Players the scorer has picked for places that are still empty.
  int? _pickStriker;
  int? _pickNonStriker;
  int? _pickBowler;
  bool _busy = false;

  // ---- loading -------------------------------------------------------------

  /// Loads a match and rebuilds every innings by replaying its stored
  /// deliveries. Used both to resume a match and to reopen a finished one.
  Future<void> load(int matchId) async {
    loading = true;
    notifyListeners();
    try {
      final m = await _matches.byId(matchId);
      if (m == null) throw SetupException('Match not found.');
      match = m;

      for (final id in [m.teamAId, m.teamBId]) {
        final team = await _teams.byId(id);
        _teamNames[id] = team?.name ?? '?';
      }
      final squads = await _matches.squads(matchId);
      final allIds = squads.values.expand((ids) => ids);
      _playerNames
        ..clear()
        ..addEntries((await _players.byIds(allIds)).map((p) => MapEntry(p.id, p.name)));

      var infos = await _matches.innings(matchId);
      if (infos.isEmpty) {
        infos = [
          await _matches.addInnings(InningsInfo(
            matchId: matchId,
            number: 1,
            battingTeamId: m.battingFirstTeamId,
            bowlingTeamId: m.bowlingFirstTeamId,
          )),
        ];
      }

      final views = <InningsView>[];
      for (final info in infos) {
        final config = InningsConfig(
          battingIds: squads[info.battingTeamId] ?? const [],
          bowlingIds: squads[info.bowlingTeamId] ?? const [],
          maxOvers: m.overs,
          target: info.target,
        );
        final stored = await _matches.deliveries(info.id);
        views.add(InningsView(
          info,
          config,
          replayInnings(config, stored.map((d) => d.input)),
        ));
      }
      innings = views;
      _clearPicks();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ---- what the screens read ------------------------------------------------

  InningsView? get current => innings.isEmpty ? null : innings.last;
  InningsState? get state => current?.state;

  String playerName(int id) => _playerNames[id] ?? '?';
  String teamName(int id) => _teamNames[id] ?? '?';

  bool get matchOver => match?.status == MatchStatus.completed;

  bool get canStartSecondInnings =>
      !matchOver && innings.length == 1 && innings.first.state.isComplete;

  /// Striker / non-striker / bowler for the next ball: what the engine expects,
  /// or else what the scorer has picked.
  int? get strikerId => state?.striker ?? _pickStriker;
  int? get nonStrikerId => state?.nonStriker ?? _pickNonStriker;
  int? get bowlerId => state?.bowler ?? _pickBowler;

  /// The scorer still has to choose a player for at least one place.
  bool get needsSelection {
    final s = state;
    if (s == null || s.isComplete || matchOver) return false;
    return s.striker == null || s.nonStriker == null || s.bowler == null;
  }

  bool get readyToScore {
    final s = state;
    return !matchOver &&
        s != null &&
        !s.isComplete &&
        strikerId != null &&
        nonStrikerId != null &&
        bowlerId != null;
  }

  /// Batters who may fill the striker / non-striker place: not yet at the
  /// crease or out, and not the batter already picked for the other place.
  List<int> batterCandidates({required bool forStriker}) {
    final v = current;
    if (v == null) return const [];
    final other = forStriker ? nonStrikerId : strikerId;
    return v.config.battingIds
        .where((id) => id != other && !v.state.batters.containsKey(id))
        .toList();
  }

  /// Bowlers who may bowl the next over (not the one who just bowled).
  List<int> bowlerCandidates() {
    final v = current;
    if (v == null) return const [];
    final s = v.state;
    final banned = (s.deliveries.isNotEmpty && s.bowler == null)
        ? s.lastBowlerId
        : null;
    return v.config.bowlingIds.where((id) => id != banned).toList();
  }

  /// Players of the fielding side, for the optional fielder on a wicket.
  List<int> get fielderCandidates => current?.config.bowlingIds ?? const [];

  // ---- choosing players ----------------------------------------------------

  void pickStriker(int id) {
    if (state?.striker != null) return;
    _pickStriker = id;
    if (_pickNonStriker == id) _pickNonStriker = null;
    notifyListeners();
  }

  void pickNonStriker(int id) {
    if (state?.nonStriker != null) return;
    _pickNonStriker = id;
    if (_pickStriker == id) _pickStriker = null;
    notifyListeners();
  }

  void pickBowler(int id) {
    if (state?.bowler != null) return;
    _pickBowler = id;
    notifyListeners();
  }

  void _clearPicks() {
    _pickStriker = null;
    _pickNonStriker = null;
    _pickBowler = null;
  }

  // ---- scoring ---------------------------------------------------------------

  /// Records one ball. Returns a message for the scorer if the ball was
  /// rejected, or null on success.
  Future<String?> recordBall({
    int runsOffBat = 0,
    ExtraType extra = ExtraType.none,
    int extraRuns = 0,
    WicketType? wicket,
    int? dismissedId,
    int? fielderId,
  }) async {
    final v = current;
    if (v == null || match == null) return 'No match loaded.';
    if (_busy) return null; // ignore a double tap while saving
    if (!readyToScore) {
      return 'Choose the striker, non-striker and bowler first.';
    }
    final input = DeliveryInput(
      strikerId: strikerId!,
      nonStrikerId: nonStrikerId!,
      bowlerId: bowlerId!,
      runsOffBat: runsOffBat,
      extra: extra,
      extraRuns: extraRuns,
      wicket: wicket,
      dismissedId: dismissedId,
      fielderId: fielderId,
    );
    final InningsState next;
    try {
      next = v.state.apply(input); // all cricket rules live here
    } on ScoringException catch (e) {
      return e.message;
    }

    _busy = true;
    try {
      await _matches.addDelivery(v.info.id, next.deliveries.last);
      v.state = next;
      _clearPicks();
      if (next.isComplete && v.info.number == 2) await _finishMatch();
    } finally {
      _busy = false;
      notifyListeners();
    }
    return null;
  }

  /// Removes the last ball of the current innings and rebuilds the innings
  /// from the remaining deliveries.
  Future<String?> undo() async {
    final v = current;
    final m = match;
    if (v == null || m == null) return 'No match loaded.';
    if (_busy) return null;
    if (v.state.deliveries.isEmpty) return 'Nothing to undo.';

    _busy = true;
    try {
      await _matches.deleteLastDelivery(v.info.id);
      final remaining = v.state.deliveries
          .sublist(0, v.state.deliveries.length - 1)
          .map((d) => d.input);
      v.state = replayInnings(v.config, remaining);
      _clearPicks();
      if (m.status == MatchStatus.completed) {
        match = m.copyWith(status: MatchStatus.inProgress, clearResult: true);
        await _matches.update(match!);
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
    return null;
  }

  /// Starts the second innings once the first is complete.
  Future<String?> startSecondInnings() async {
    final m = match;
    if (m == null || !canStartSecondInnings) {
      return 'The first innings is not finished yet.';
    }
    if (_busy) return null;
    _busy = true;
    try {
      final first = innings.first;
      final info = await _matches.addInnings(InningsInfo(
        matchId: m.id,
        number: 2,
        battingTeamId: first.info.bowlingTeamId,
        bowlingTeamId: first.info.battingTeamId,
        target: first.state.runs + 1,
      ));
      final config = InningsConfig(
        battingIds: first.config.bowlingIds,
        bowlingIds: first.config.battingIds,
        maxOvers: m.overs,
        target: info.target,
      );
      innings = [...innings, InningsView(info, config, InningsState.start(config))];
      _clearPicks();
    } finally {
      _busy = false;
      notifyListeners();
    }
    return null;
  }

  Future<void> _finishMatch() async {
    final m = match!;
    final first = innings[0];
    final second = innings[1];
    final result = computeMatchResult(
      firstTeamId: first.info.battingTeamId,
      firstTeamName: teamName(first.info.battingTeamId),
      secondTeamId: second.info.battingTeamId,
      secondTeamName: teamName(second.info.battingTeamId),
      first: first.state,
      second: second.state,
    );
    if (result == null) return;
    match = m.copyWith(
      status: MatchStatus.completed,
      resultText: result.text,
      summaryText: _summary(),
    );
    await _matches.update(match!);
  }

  String _summary() => innings
      .map((v) =>
          '${teamName(v.info.battingTeamId)} ${v.state.runs}/${v.state.wickets} (${v.state.oversText})')
      .join(' · ');

  /// One-line description of where the match stands, for headers.
  String get statusLine {
    final m = match;
    final v = current;
    if (m == null || v == null) return '';
    if (m.status == MatchStatus.completed) return m.resultText ?? 'Match complete';
    final s = v.state;
    if (v.info.number == 2) {
      final need = s.runsRequired ?? 0;
      return 'Need $need from ${s.ballsRemaining} ${s.ballsRemaining == 1 ? 'ball' : 'balls'}';
    }
    return '${s.config.maxOvers} overs match · ${formatOvers(s.legalBalls)} bowled';
  }
}
