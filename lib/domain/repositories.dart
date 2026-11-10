/// Storage contracts. The domain and application layers depend only on these
/// interfaces; `lib/data` supplies the SQLite versions (the app) and the
/// in-memory versions (tests).
library;

import 'models.dart';

abstract class TeamRepository {
  /// All saved teams, sorted by name.
  Future<List<Team>> allTeams();
  Future<Team?> byId(int id);
  Future<Team> create(String name);
}

abstract class PlayerRepository {
  /// Players of a team, in the order they were added.
  Future<List<Player>> forTeam(int teamId);
  Future<List<Player>> byIds(Iterable<int> ids);
  Future<Player> add(int teamId, String name);

  /// True if the player is part of any saved match squad.
  Future<bool> isUsedInMatch(int playerId);
  Future<void> remove(int playerId);
}

abstract class MatchRepository {
  /// Saves the match and a snapshot of both squads, returns it with its id.
  Future<MatchInfo> create(
    MatchInfo match, {
    required List<int> squadA,
    required List<int> squadB,
  });
  Future<void> update(MatchInfo match);

  /// All matches, newest first.
  Future<List<MatchInfo>> all();
  Future<MatchInfo?> byId(int id);

  /// Squad snapshot: team id -> player ids, as they were when the match began.
  Future<Map<int, List<int>>> squads(int matchId);

  Future<InningsInfo> addInnings(InningsInfo innings);
  Future<List<InningsInfo>> innings(int matchId);

  Future<void> addDelivery(int inningsId, Delivery delivery);
  Future<void> deleteLastDelivery(int inningsId);

  /// Deliveries of an innings in the order they were bowled.
  Future<List<Delivery>> deliveries(int inningsId);
}
