/// Teams, players, match creation and the list of saved matches.
library;

import 'package:flutter/foundation.dart';

import '../domain/errors.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../domain/rules.dart';

class SetupController extends ChangeNotifier {
  SetupController(this._teams, this._players, this._matches);

  final TeamRepository _teams;
  final PlayerRepository _players;
  final MatchRepository _matches;

  List<Team> teams = const [];
  Map<int, List<Player>> playersByTeam = const {};

  /// All saved matches, newest first.
  List<MatchInfo> matches = const [];

  /// Reloads everything from storage. Call once at start-up; the other
  /// methods call it after they change something.
  Future<void> load() async {
    teams = await _teams.allTeams();
    final byTeam = <int, List<Player>>{};
    for (final t in teams) {
      byTeam[t.id] = await _players.forTeam(t.id);
    }
    playersByTeam = byTeam;
    matches = await _matches.all();
    notifyListeners();
  }

  int playerCount(int teamId) => playersByTeam[teamId]?.length ?? 0;

  List<Player> playersOf(int teamId) => playersByTeam[teamId] ?? const [];

  String teamName(int? id) {
    for (final t in teams) {
      if (t.id == id) return t.name;
    }
    return '?';
  }

  /// Why this team cannot start a match yet, or null if it can.
  String? teamProblem(int teamId) => teamSizeProblem(playerCount(teamId));

  Future<Team> createTeam(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) throw SetupException('Team name cannot be empty.');
    if (teams.any((t) => t.name.toLowerCase() == name.toLowerCase())) {
      throw SetupException('A team called "$name" already exists.');
    }
    final team = await _teams.create(name);
    await load();
    return team;
  }

  Future<void> addPlayer(int teamId, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) throw SetupException('Player name cannot be empty.');
    if (playerCount(teamId) >= maxPlayersPerTeam) {
      throw SetupException('A team can have at most $maxPlayersPerTeam players.');
    }
    final exists = playersOf(teamId)
        .any((p) => p.name.toLowerCase() == name.toLowerCase());
    if (exists) {
      throw SetupException('"$name" is already in this team.');
    }
    await _players.add(teamId, name);
    await load();
  }

  Future<void> removePlayer(Player player) async {
    if (await _players.isUsedInMatch(player.id)) {
      throw SetupException(
          '${player.name} played in a saved match and cannot be removed.');
    }
    await _players.remove(player.id);
    await load();
  }

  /// Everything wrong with a proposed match, as messages for the set-up screen.
  /// An empty list means the match can start.
  List<String> matchProblems({
    required String name,
    required int? overs,
    required int? teamAId,
    required int? teamBId,
  }) {
    final problems = <String>[];
    if (name.trim().isEmpty) problems.add('Enter a match name or venue.');
    if (overs == null || overs < 1 || overs > maxOversPerMatch) {
      problems.add('Overs must be a number from 1 to $maxOversPerMatch.');
    }
    if (teamAId == null || teamBId == null) {
      problems.add('Choose both teams.');
    } else if (teamAId == teamBId) {
      problems.add('Choose two different teams.');
    } else {
      for (final id in [teamAId, teamBId]) {
        final problem = teamProblem(id);
        if (problem != null) problems.add('${teamName(id)} $problem.');
      }
    }
    return problems;
  }

  /// Creates the match, snapshots both squads and creates the first innings.
  Future<MatchInfo> startMatch({
    required String name,
    required DateTime date,
    required int overs,
    required int teamAId,
    required int teamBId,
    required int battingFirstTeamId,
  }) async {
    final problems = matchProblems(
      name: name,
      overs: overs,
      teamAId: teamAId,
      teamBId: teamBId,
    );
    if (problems.isNotEmpty) throw SetupException(problems.first);
    if (battingFirstTeamId != teamAId && battingFirstTeamId != teamBId) {
      throw SetupException('Choose which team bats first.');
    }

    final squadA = (await _players.forTeam(teamAId)).map((p) => p.id).toList();
    final squadB = (await _players.forTeam(teamBId)).map((p) => p.id).toList();
    final match = await _matches.create(
      MatchInfo(
        name: name.trim(),
        date: date,
        overs: overs,
        teamAId: teamAId,
        teamBId: teamBId,
        battingFirstTeamId: battingFirstTeamId,
      ),
      squadA: squadA,
      squadB: squadB,
    );
    await _matches.addInnings(InningsInfo(
      matchId: match.id,
      number: 1,
      battingTeamId: battingFirstTeamId,
      bowlingTeamId: match.bowlingFirstTeamId,
    ));
    await load();
    return match;
  }
}
