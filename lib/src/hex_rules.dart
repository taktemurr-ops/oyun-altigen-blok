import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';

import 'hex_engine.dart';

const altigenBlokId = 'oyun-altigen-blok';

class HexRules extends GameRules<HexLevel> {
  /// Üretim + çözücü türü: 100.000 numaralı bölüm (1000 dünya).
  @override
  int get levelCount => 100000;

  @override
  String get gameId => altigenBlokId;

  @override
  List<String> get optionalMechanics => const ['obstacle', 'big_board', 'timer'];

  @override
  List<GameModeId> get modes => const [
        GameModeId.campaign,
        GameModeId.endless,
        GameModeId.timeAttack,
        GameModeId.zen,
        GameModeId.daily,
        GameModeId.weekly,
        GameModeId.challenge,
      ];

  @override
  List<GameStat> get gameStats => const [
        GameStat('lines_cleared', 'Silinen sıra', 'Lines cleared', scale: 10),
        GameStat('combos', 'Kombo', 'Combos', scale: 5),
        GameStat('cells_placed', 'Yerleştirilen kare', 'Cells placed', scale: 100),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('lines', 'lines_cleared', [10, 25, 50]),
        MissionTemplate('combos', 'combos', [3, 8, 15]),
        MissionTemplate('cells', 'cells_placed', [80, 200, 400]),
      ];

  @override
  HexLevel generate(LevelSpec spec) => generateHexLevel(spec);

  @override
  Validation validate(HexLevel level, LevelSpec spec) {
    if (level.start.length != level.span * level.span) return const Validation.fail('bad board');
    final g = HexGame(level);
    for (final line in g.lines) {
      if (line.every((i) => level.start[i] != HexCell.empty)) return const Validation.fail('pre-filled line');
    }
    if (!g.hasMove) return const Validation.fail('dead start');
    if (level.target == 0) return const Validation.ok();
    final moves = simulateHexLevel(level);
    if (moves < 0) return const Validation.fail('AI could not solve');
    return Validation.ok(moves);
  }

  HexLevel finalize(GeneratedLevel<HexLevel> g) {
    final l = g.puzzle;
    if (l.target == 0) return l;
    final ai = g.validation.metric;
    final slack = 2.4 - l.difficulty * 0.1;
    final limit = l.difficulty >= 4 ? (ai * slack).ceil() + 4 : 0;
    return l.withAi(ai, limit);
  }

  static int stars(HexGame g) {
    if (!g.won) return 0;
    final ai = g.level!.aiMoves;
    if (ai <= 0) return 3;
    if (g.moves <= ai + 2) return 3;
    if (g.moves <= (ai * 1.5).ceil() + 2) return 2;
    return 1;
  }
}
