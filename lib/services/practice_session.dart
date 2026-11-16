import '../models/domino_tile.dart';
import '../models/game_state.dart';
import '../models/player.dart';

/// Keeps a practice game alive when the player goes back to the menu.
/// The screen binds its lists here, so leaving and returning resumes the same
/// hand, board and score instead of dealing a new game.
class PracticeSession {
  PracticeSession._();

  static final PracticeSession instance = PracticeSession._();

  bool active = false;

  late List<DominoTile> hand;
  late List<Player> players;
  late List<PlacedTile> board;

  int team1Score = 0;
  int team2Score = 0;
  int current = 0;
  int consecutivePasses = 0;
  bool handOver = false;
  double topRun = 3;
  double bottomRun = 3;

  /// Points the session at the screen's live lists.
  void bind({
    required List<DominoTile> hand,
    required List<Player> players,
    required List<PlacedTile> board,
  }) {
    this.hand = hand;
    this.players = players;
    this.board = board;
    active = true;
  }

  void clear() => active = false;
}
