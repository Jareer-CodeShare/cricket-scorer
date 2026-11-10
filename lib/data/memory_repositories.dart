/// In-memory implementations of the repository interfaces. They hold data in
/// plain Dart collections, so the application layer can be tested without a
/// database. The app itself uses the SQLite versions in `sqlite_repositories.dart`.
library;

import '../domain/errors.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';

/// Shared storage behind the three in-memory repositories.
class MemoryStore {
  int _nextId = 1;
  int nextId() => _nextId++;

  final List<Team> teams = [];
  final List<Player> players = [];
  final Map<int, MatchInfo> matches = {};
  final Map<int, Map<int, List<int>>> squads = {};
  final Map<int, InningsInfo> innings = {};
  final Map<int, List<Delivery>> deliveries = {};
}

class MemoryTeamRepository implements TeamRepository {
  MemoryTeamRepository(this._s);
  final MemoryStore _s;

  @override
  Future<List<Team>> allTeams() async {
    final list = List.of(_s.teams);
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  Future<Team?> byId(int id) async {
    for (final t in _s.teams) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Future<Team> create(String name) async {
    final team = Team(id: _s.nextId(), name: name);
    _s.teams.add(team);
    return team;
  }
}

class MemoryPlayerRepository implements PlayerRepository {
  MemoryPlayerRepository(this._s);
  final MemoryStore _s;

  @override
  Future<List<Player>> forTeam(int teamId) async =>
      _s.players.where((p) => p.teamId == teamId).toList();

  @override
  Future<List<Player>> byIds(Iterable<int> ids) async {
    final wanted = ids.toSet();
    return _s.players.where((p) => wanted.contains(p.id)).toList();
  }

  @override
  Future<Player> add(int teamId, String name) async {
    final player = Player(id: _s.nextId(), teamId: teamId, name: name);
    _s.players.add(player);
    return player;
  }

  @override
  Future<bool> isUsedInMatch(int playerId) async => _s.squads.values
      .any((bySide) => bySide.values.any((ids) => ids.contains(playerId)));

  @override
  Future<void> remove(int playerId) async {
    if (await isUsedInMatch(playerId)) {
      throw SetupException('That player is part of a saved match.');
    }
    _s.players.removeWhere((p) => p.id == playerId);
  }
}

class MemoryMatchRepository implements MatchRepository {
  MemoryMatchRepository(this._s);
  final MemoryStore _s;

  @override
  Future<MatchInfo> create(
    MatchInfo match, {
    required List<int> squadA,
    required List<int> squadB,
  }) async {
    final saved = match.copyWith(id: _s.nextId());
    _s.matches[saved.id] = saved;
    _s.squads[saved.id] = {
      saved.teamAId: List.of(squadA),
      saved.teamBId: List.of(squadB),
    };
    return saved;
  }

  @override
  Future<void> update(MatchInfo match) async {
    _s.matches[match.id] = match;
  }

  @override
  Future<List<MatchInfo>> all() async {
    final list = _s.matches.values.toList();
    list.sort((a, b) => b.id.compareTo(a.id)); // newest first
    return list;
  }

  @override
  Future<MatchInfo?> byId(int id) async => _s.matches[id];

  @override
  Future<Map<int, List<int>>> squads(int matchId) async => {
        for (final e in (_s.squads[matchId] ?? {}).entries)
          e.key: List.of(e.value),
      };

  @override
  Future<InningsInfo> addInnings(InningsInfo innings) async {
    final saved = innings.copyWith(id: _s.nextId());
    _s.innings[saved.id] = saved;
    _s.deliveries[saved.id] = [];
    return saved;
  }

  @override
  Future<List<InningsInfo>> innings(int matchId) async {
    final list = _s.innings.values.where((i) => i.matchId == matchId).toList();
    list.sort((a, b) => a.number.compareTo(b.number));
    return list;
  }

  @override
  Future<void> addDelivery(int inningsId, Delivery delivery) async {
    _s.deliveries[inningsId]!.add(delivery);
  }

  @override
  Future<void> deleteLastDelivery(int inningsId) async {
    final list = _s.deliveries[inningsId]!;
    if (list.isNotEmpty) list.removeLast();
  }

  @override
  Future<List<Delivery>> deliveries(int inningsId) async =>
      List.of(_s.deliveries[inningsId] ?? const []);
}
