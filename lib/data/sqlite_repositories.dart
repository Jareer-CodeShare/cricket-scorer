/// SQLite implementations of the repository interfaces from `lib/domain`.
/// Plain SQL, no cricket rules: this layer only stores and loads.
library;

import 'package:sqflite/sqflite.dart';

import '../domain/errors.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';

class SqliteTeamRepository implements TeamRepository {
  SqliteTeamRepository(this._db);
  final Database _db;

  static Team _team(Map<String, Object?> row) =>
      Team(id: row['id'] as int, name: row['name'] as String);

  @override
  Future<List<Team>> allTeams() async {
    final rows = await _db.query('teams', orderBy: 'name COLLATE NOCASE');
    return rows.map(_team).toList();
  }

  @override
  Future<Team?> byId(int id) async {
    final rows = await _db.query('teams', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _team(rows.first);
  }

  @override
  Future<Team> create(String name) async {
    final id = await _db.insert('teams', {'name': name});
    return Team(id: id, name: name);
  }
}

class SqlitePlayerRepository implements PlayerRepository {
  SqlitePlayerRepository(this._db);
  final Database _db;

  static Player _player(Map<String, Object?> row) => Player(
        id: row['id'] as int,
        teamId: row['team_id'] as int,
        name: row['name'] as String,
      );

  @override
  Future<List<Player>> forTeam(int teamId) async {
    final rows = await _db.query(
      'players',
      where: 'team_id = ?',
      whereArgs: [teamId],
      orderBy: 'id',
    );
    return rows.map(_player).toList();
  }

  @override
  Future<List<Player>> byIds(Iterable<int> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return [];
    final marks = List.filled(list.length, '?').join(',');
    final rows =
        await _db.rawQuery('SELECT * FROM players WHERE id IN ($marks)', list);
    return rows.map(_player).toList();
  }

  @override
  Future<Player> add(int teamId, String name) async {
    final id = await _db.insert('players', {'team_id': teamId, 'name': name});
    return Player(id: id, teamId: teamId, name: name);
  }

  @override
  Future<bool> isUsedInMatch(int playerId) async {
    final count = Sqflite.firstIntValue(await _db.rawQuery(
      'SELECT COUNT(*) FROM match_squads WHERE player_id = ?',
      [playerId],
    ));
    return (count ?? 0) > 0;
  }

  @override
  Future<void> remove(int playerId) async {
    if (await isUsedInMatch(playerId)) {
      throw SetupException('That player is part of a saved match.');
    }
    await _db.delete('players', where: 'id = ?', whereArgs: [playerId]);
  }
}

class SqliteMatchRepository implements MatchRepository {
  SqliteMatchRepository(this._db);
  final Database _db;

  static MatchInfo _match(Map<String, Object?> row) => MatchInfo(
        id: row['id'] as int,
        name: row['name'] as String,
        date: DateTime.parse(row['match_date'] as String),
        overs: row['overs'] as int,
        teamAId: row['team_a_id'] as int,
        teamBId: row['team_b_id'] as int,
        battingFirstTeamId: row['batting_first_team_id'] as int,
        status: MatchStatus.values.byName(row['status'] as String),
        resultText: row['result_text'] as String?,
        summaryText: row['summary_text'] as String?,
      );

  static Map<String, Object?> _matchRow(MatchInfo m) => {
        'name': m.name,
        'match_date': m.date.toIso8601String(),
        'overs': m.overs,
        'team_a_id': m.teamAId,
        'team_b_id': m.teamBId,
        'batting_first_team_id': m.battingFirstTeamId,
        'status': m.status.name,
        'result_text': m.resultText,
        'summary_text': m.summaryText,
      };

  static InningsInfo _innings(Map<String, Object?> row) => InningsInfo(
        id: row['id'] as int,
        matchId: row['match_id'] as int,
        number: row['number'] as int,
        battingTeamId: row['batting_team_id'] as int,
        bowlingTeamId: row['bowling_team_id'] as int,
        target: row['target'] as int?,
      );

  static Delivery _delivery(Map<String, Object?> row) => Delivery(
        seq: row['seq'] as int,
        input: DeliveryInput(
          strikerId: row['striker_id'] as int,
          nonStrikerId: row['non_striker_id'] as int,
          bowlerId: row['bowler_id'] as int,
          runsOffBat: row['runs_off_bat'] as int,
          extra: ExtraType.values.byName(row['extra_type'] as String),
          extraRuns: row['extra_runs'] as int,
          wicket: row['wicket_type'] == null
              ? null
              : WicketType.values.byName(row['wicket_type'] as String),
          dismissedId: row['dismissed_id'] as int?,
          fielderId: row['fielder_id'] as int?,
        ),
      );

  @override
  Future<MatchInfo> create(
    MatchInfo match, {
    required List<int> squadA,
    required List<int> squadB,
  }) async {
    final id = await _db.transaction<int>((txn) async {
      final matchId = await txn.insert('matches', _matchRow(match));
      final batch = txn.batch();
      for (final playerId in squadA) {
        batch.insert('match_squads', {
          'match_id': matchId,
          'team_id': match.teamAId,
          'player_id': playerId,
        });
      }
      for (final playerId in squadB) {
        batch.insert('match_squads', {
          'match_id': matchId,
          'team_id': match.teamBId,
          'player_id': playerId,
        });
      }
      await batch.commit(noResult: true);
      return matchId;
    });
    return match.copyWith(id: id);
  }

  @override
  Future<void> update(MatchInfo match) async {
    await _db.update(
      'matches',
      _matchRow(match),
      where: 'id = ?',
      whereArgs: [match.id],
    );
  }

  @override
  Future<List<MatchInfo>> all() async {
    final rows = await _db.query('matches', orderBy: 'match_date DESC, id DESC');
    return rows.map(_match).toList();
  }

  @override
  Future<MatchInfo?> byId(int id) async {
    final rows = await _db.query('matches', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _match(rows.first);
  }

  @override
  Future<Map<int, List<int>>> squads(int matchId) async {
    final rows = await _db.query(
      'match_squads',
      where: 'match_id = ?',
      whereArgs: [matchId],
      orderBy: 'player_id',
    );
    final result = <int, List<int>>{};
    for (final row in rows) {
      result
          .putIfAbsent(row['team_id'] as int, () => [])
          .add(row['player_id'] as int);
    }
    return result;
  }

  @override
  Future<InningsInfo> addInnings(InningsInfo innings) async {
    final id = await _db.insert('innings', {
      'match_id': innings.matchId,
      'number': innings.number,
      'batting_team_id': innings.battingTeamId,
      'bowling_team_id': innings.bowlingTeamId,
      'target': innings.target,
    });
    return innings.copyWith(id: id);
  }

  @override
  Future<List<InningsInfo>> innings(int matchId) async {
    final rows = await _db.query(
      'innings',
      where: 'match_id = ?',
      whereArgs: [matchId],
      orderBy: 'number',
    );
    return rows.map(_innings).toList();
  }

  @override
  Future<void> addDelivery(int inningsId, Delivery delivery) async {
    final i = delivery.input;
    await _db.insert('deliveries', {
      'innings_id': inningsId,
      'seq': delivery.seq,
      'striker_id': i.strikerId,
      'non_striker_id': i.nonStrikerId,
      'bowler_id': i.bowlerId,
      'runs_off_bat': i.runsOffBat,
      'extra_type': i.extra.name,
      'extra_runs': i.extraRuns,
      'is_legal': delivery.isLegal ? 1 : 0,
      'wicket_type': i.wicket?.name,
      'dismissed_id': i.wicket == null ? null : i.dismissedPlayerId,
      'fielder_id': i.fielderId,
    });
  }

  @override
  Future<void> deleteLastDelivery(int inningsId) async {
    await _db.rawDelete(
      'DELETE FROM deliveries WHERE id = ('
      'SELECT id FROM deliveries WHERE innings_id = ? ORDER BY seq DESC LIMIT 1)',
      [inningsId],
    );
  }

  @override
  Future<List<Delivery>> deliveries(int inningsId) async {
    final rows = await _db.query(
      'deliveries',
      where: 'innings_id = ?',
      whereArgs: [inningsId],
      orderBy: 'seq',
    );
    return rows.map(_delivery).toList();
  }
}
