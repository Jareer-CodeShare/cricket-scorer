/// The SQLite schema. Five of the seven entities in the brief are tables
/// (Team, Player, Match, Innings, Delivery); BatterInnings and BowlerSpell are
/// derived by the rules engine from the deliveries, so there is no second copy
/// of any run total that could disagree with the delivery log.
library;

const int schemaVersion = 1;

const List<String> schemaStatements = [
  '''
CREATE TABLE teams (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE COLLATE NOCASE
)''',
  '''
CREATE TABLE players (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  team_id INTEGER NOT NULL REFERENCES teams(id),
  name TEXT NOT NULL,
  UNIQUE (team_id, name COLLATE NOCASE)
)''',
  '''
CREATE TABLE matches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  match_date TEXT NOT NULL,
  overs INTEGER NOT NULL,
  team_a_id INTEGER NOT NULL REFERENCES teams(id),
  team_b_id INTEGER NOT NULL REFERENCES teams(id),
  batting_first_team_id INTEGER NOT NULL REFERENCES teams(id),
  status TEXT NOT NULL,
  result_text TEXT,
  summary_text TEXT
)''',
  // The squads as they were when the match began, so an old scorecard never
  // changes if a team's player list changes later.
  '''
CREATE TABLE match_squads (
  match_id INTEGER NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  team_id INTEGER NOT NULL REFERENCES teams(id),
  player_id INTEGER NOT NULL REFERENCES players(id),
  PRIMARY KEY (match_id, player_id)
)''',
  '''
CREATE TABLE innings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  match_id INTEGER NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  number INTEGER NOT NULL,
  batting_team_id INTEGER NOT NULL REFERENCES teams(id),
  bowling_team_id INTEGER NOT NULL REFERENCES teams(id),
  target INTEGER,
  UNIQUE (match_id, number)
)''',
  // The event log. seq is a strictly increasing number per innings so replay
  // order is never ambiguous.
  '''
CREATE TABLE deliveries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  innings_id INTEGER NOT NULL REFERENCES innings(id) ON DELETE CASCADE,
  seq INTEGER NOT NULL,
  striker_id INTEGER NOT NULL REFERENCES players(id),
  non_striker_id INTEGER NOT NULL REFERENCES players(id),
  bowler_id INTEGER NOT NULL REFERENCES players(id),
  runs_off_bat INTEGER NOT NULL,
  extra_type TEXT NOT NULL,
  extra_runs INTEGER NOT NULL,
  is_legal INTEGER NOT NULL,
  wicket_type TEXT,
  dismissed_id INTEGER REFERENCES players(id),
  fielder_id INTEGER REFERENCES players(id),
  UNIQUE (innings_id, seq)
)''',
  'CREATE INDEX idx_deliveries_innings ON deliveries (innings_id, seq)',
  'CREATE INDEX idx_players_team ON players (team_id)',
];
