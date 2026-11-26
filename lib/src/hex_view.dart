import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/core/strings.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/app/studio_ui.dart';

import 'hex_engine.dart';
import 'hex_rules.dart';

final Map<StudioLook, ThemeData> _studioThemes = {};

const double _sqrt3 = 1.7320508075688772;

Offset hexCenter(int q, int r, double s) => Offset(s * _sqrt3 * (q + r / 2), s * 1.5 * r);

(int, int) pixelToHex(Offset p, double s) {
  final qf = (_sqrt3 / 3 * p.dx - p.dy / 3) / s;
  final rf = (2 / 3 * p.dy) / s;
  final sf = -qf - rf;
  var q = qf.round(), r = rf.round();
  final sr = sf.round();
  final dq = (q - qf).abs(), dr = (r - rf).abs(), ds = (sr - sf).abs();
  if (dq > dr && dq > ds) {
    q = -r - sr;
  } else if (dr > ds) {
    r = -q - sr;
  }
  return (q, r);
}

Path hexPath(Offset c, double s) {
  final path = Path();
  for (var k = 0; k < 6; k++) {
    final a = math.pi / 180 * (60 * k - 30);
    final p = c + Offset(s * math.cos(a), s * math.sin(a));
    if (k == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

void paintHexCell(Canvas c, Offset center, double s, Color color,
    {double alpha = 1, String? mark, bool outline = false}) {
  final path = hexPath(center, s * 0.93);
  if (outline) {
    c.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.12);
    return;
  }
  c.drawPath(path.shift(Offset(0, s * 0.1)), Paint()..color = Colors.black.withValues(alpha: 0.25 * alpha));
  c.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, Colors.white, 0.22)!.withValues(alpha: alpha), Color.lerp(color, Colors.black, 0.18)!.withValues(alpha: alpha)],
        ).createShader(Rect.fromCircle(center: center, radius: s)));
  c.drawPath(hexPath(center.translate(0, -s * 0.18), s * 0.52),
      Paint()..color = Colors.white.withValues(alpha: 0.16 * alpha));
  if (mark != null) {
    final tp = TextPainter(
      text: TextSpan(text: mark, style: TextStyle(fontSize: s * 0.7, color: Colors.black.withValues(alpha: 0.45))),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }
}

/// Oyun ekranı: düğmeler, çipler, üst bilgi ve pencereler onaylı koyu
/// tasarımda (merkezin paleti, studio-core StudioLook); tahta çizimi kendi
/// renklerini korur.
class HexView extends StatelessWidget {
  final PlayContext ctx;
  const HexView({super.key, required this.ctx});

  @override
  Widget build(BuildContext context) {
    final look = StudioLook.of(context);
    return Theme(data: _studioThemes[look] ??= buildStudioTheme(look), child: HexViewBody(ctx: ctx));
  }
}

class HexViewBody extends StatefulWidget {
  final PlayContext ctx;
  const HexViewBody({super.key, required this.ctx});

  @override
  State<HexViewBody> createState() => _HexViewState();
}

class _HexViewState extends State<HexViewBody> {
  late HexLevel level;
  late HexGame game;
  final GlobalKey _boardKey = GlobalKey();
  int? _selected;
  int? _hoverTray;
  (int, int)? _hover;
  (int, int, int)? _hint;
  Set<int> _flash = {};
  int _seconds = 0, _hints = 0;
  Timer? _timer, _flashTimer;
  bool _ended = false;
  double _s = 20;

  PlayContext get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    level = HexRules().finalize(ctx.generated as GeneratedLevel<HexLevel>);
    final snap = ctx.resume['snap'];
    game = snap is String ? HexGame.restore(level, snap) : HexGame(level);
    _seconds = (ctx.resume['secs'] as num?)?.toInt() ?? 0;
    _hints = (ctx.resume['hints'] as num?)?.toInt() ?? 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_ended || !mounted) return;
      setState(() => _seconds++);
      if (level.timeLimit > 0 && _seconds >= level.timeLimit) _end();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }

  void _persist() => ctx.saveResume({'snap': game.serialize(), 'secs': _seconds, 'hints': _hints});

  void _place(int t, int q, int r) {
    final res = game.place(t, q, r);
    if (res == null) {
      ctx.sfx(Sfx.error);
      return;
    }
    ctx.sfx(res.lines > 1 ? Sfx.combo : (res.lines == 1 ? Sfx.clear : Sfx.place));
    setState(() {
      _selected = null;
      _hint = null;
      _flash = res.cleared.toSet();
    });
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _flash = {});
    });
    _persist();
    if (game.won || game.outOfMoves || !game.hasMove) _end();
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    final goal = level.target > 0;
    final won = goal ? game.won : game.score > 0;
    ctx.sfx(won ? Sfx.win : Sfx.lose);
    final stars = goal
        ? HexRules.stars(game)
        : (game.score >= 1500 ? 3 : game.score >= 500 ? 2 : game.score > 0 ? 1 : 0);
    ctx.finish(RoundResult(
      won: won,
      score: game.score,
      stars: won ? stars : 0,
      seconds: _seconds,
      moves: game.moves,
      hintsUsed: _hints,
      undosUsed: 0,
      gameStats: {'lines_cleared': game.linesCleared, 'combos': game.bestCombo, 'cells_placed': game.placed},
    ));
  }

  Future<void> _useHint() async {
    if (!await ctx.requestHint()) return;
    _hints++;
    setState(() {
      _hint = game.bestMove();
      if (_hint != null) _selected = _hint!.$1;
    });
    _persist();
  }

  // ---- Girdi ----
  Offset _origin(Size box) => Offset(box.width / 2, box.height / 2);

  (int, int)? _cellAtGlobal(Offset global) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(global) - _origin(box.size);
    return pixelToHex(local, _s);
  }

  (int, int)? _snap(HexPiece p, (int, int)? c) {
    if (c == null) return null;
    if (game.canPlace(p, c.$1, c.$2)) return c;
    for (final d in kHexDirs) {
      if (game.canPlace(p, c.$1 + d[0], c.$2 + d[1])) return (c.$1 + d[0], c.$2 + d[1]);
    }
    return c;
  }

  double get _lift => _s * 3.2;

  void _onBoardTap(TapUpDetails d) {
    final sel = _selected;
    final c = _cellAtGlobal(d.globalPosition);
    if (sel == null || c == null) return;
    final p = game.tray[sel];
    if (p == null) return;
    final a = game.anchorCovering(p, c.$1, c.$2);
    if (a == null) {
      ctx.sfx(Sfx.error);
      return;
    }
    _place(sel, a.$1, a.$2);
  }

  // ---- Çizim ----
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final span = level.span;
      final maxW = cons.maxWidth - 16;
      final maxH = cons.maxHeight * 0.6;
      _s = math.min(maxW / (_sqrt3 * span), maxH / (1.5 * (span - 1) + 2)).clamp(8.0, 40.0);
      final w = _sqrt3 * span * _s, h = (1.5 * (span - 1) + 2) * _s;
      return DragTarget<int>(
        onMove: (d) {
          final p = game.tray[d.data];
          if (p == null) return;
          final c = _snap(p, _cellAtGlobal(d.offset + Offset(0, -_lift)));
          setState(() {
            _hoverTray = d.data;
            _hover = c;
          });
        },
        onLeave: (_) => setState(() => _hoverTray = null),
        onAcceptWithDetails: (d) {
          final c = _hover;
          setState(() => _hoverTray = null);
          if (c != null) _place(d.data, c.$1, c.$2);
        },
        builder: (context, _, __) => Column(children: [
          _hud(),
          const SizedBox(height: 6),
          Center(
            child: GestureDetector(
              onTapUp: _onBoardTap,
              child: Semantics(
                label: 'board',
                child: SizedBox(
                  key: _boardKey,
                  width: w,
                  height: h,
                  child: CustomPaint(painter: _BoardPainter(this)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: _trayRow()),
          _buttons(),
        ]),
      );
    });
  }

  Widget _hud() {
    final goal = level.target;
    final v = game.progressValue;
    final label = goal == 0
        ? (Strings.tx(ctx.lang, 'Puan: {0}', 'Score: {0}', [game.score]))
        : level.goalType == HexGoalType.lines
            ? (Strings.tx(ctx.lang, 'Sıra: {0} / {1}', 'Lines: {0} / {1}', [v, goal]))
            : (Strings.tx(ctx.lang, 'Puan: {0} / {1}', 'Score: {0} / {1}', [v, goal]));
    final left = level.moveLimit > 0 ? level.moveLimit - game.moves : null;
    final secs = level.timeLimit > 0 ? (level.timeLimit - _seconds).clamp(0, 9999) : _seconds;
    String two(int x) => x.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            if (goal > 0) ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(value: (v / goal).clamp(0, 1).toDouble()),
            ],
          ]),
        ),
        if (left != null) ...[
          const SizedBox(width: 10),
          const Icon(Icons.touch_app_outlined, size: 18),
          Text(' $left'),
        ],
        const SizedBox(width: 10),
        const Icon(Icons.timer_outlined, size: 18),
        Text(' ${secs ~/ 60}:${two(secs % 60)}'),
      ]),
    );
  }

  Widget _trayRow() {
    final cell = (_s * 0.62).clamp(8.0, 22.0);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [for (var i = 0; i < 3; i++) _trayPiece(i, cell)],
    );
  }

  Widget _trayPiece(int i, double s) {
    final p = game.tray[i];
    if (p == null) return SizedBox(width: s * 6, height: s * 6);
    final selected = _selected == i;
    final piece = _PieceBox(piece: p, s: s, view: this, selected: selected, hinted: _hint?.$1 == i);
    return Semantics(
      button: true,
      label: 'piece ${p.size}',
      child: GestureDetector(
        onTap: () => setState(() => _selected = selected ? null : i),
        child: Draggable<int>(
          data: i,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: () => setState(() => _selected = i),
          feedback: Transform.translate(
            offset: Offset(0, -_lift),
            child: CustomPaint(painter: _PiecePainter(p, _s, this, 0.85)),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: piece),
          child: piece,
        ),
      ),
    );
  }

  Widget _buttons() => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton.filledTonal(onPressed: _ended ? null : _useHint, icon: const Icon(Icons.lightbulb), tooltip: ctx.t('hint')),
        ]),
      );

  Color colorOf(int v) => v == HexCell.stone ? const Color(0xFF6B7280) : ctx.pieceColors[(v - 1) % ctx.pieceColors.length];
  String? markOf(int v) => ctx.colorBlind && v > 0 && v != HexCell.stone ? ctx.symbol(v - 1) : null;
}

class _PieceBox extends StatelessWidget {
  final HexPiece piece;
  final double s;
  final _HexViewState view;
  final bool selected, hinted;
  const _PieceBox({required this.piece, required this.s, required this.view, required this.selected, required this.hinted});

  @override
  Widget build(BuildContext context) {
    var minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
    for (final c in piece.cells) {
      final o = hexCenter(c[0], c[1], s);
      minX = math.min(minX, o.dx);
      maxX = math.max(maxX, o.dx);
      minY = math.min(minY, o.dy);
      maxY = math.max(maxY, o.dy);
    }
    final w = maxX - minX + s * 2, h = maxY - minY + s * 2;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected || hinted ? Theme.of(context).colorScheme.primary : Colors.transparent,
          width: 3,
        ),
      ),
      child: SizedBox(
        width: w,
        height: h,
        child: CustomPaint(
          painter: _PiecePainter(piece, s, view, 1, shift: Offset(-minX + s, -minY + s)),
        ),
      ),
    );
  }
}

class _PiecePainter extends CustomPainter {
  final HexPiece p;
  final double s;
  final _HexViewState view;
  final double alpha;
  final Offset shift;
  _PiecePainter(this.p, this.s, this.view, this.alpha, {this.shift = Offset.zero});

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in p.cells) {
      paintHexCell(canvas, shift + hexCenter(c[0], c[1], s), s, view.colorOf(p.color),
          alpha: alpha, mark: view.markOf(p.color));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _BoardPainter extends CustomPainter {
  final _HexViewState v;
  _BoardPainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final g = v.game;
    final s = v._s;
    final o = Offset(size.width / 2, size.height / 2);
    final empty = Colors.white.withValues(alpha: 0.10);
    final rim = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, s * 0.05);
    for (var i = 0; i < g.grid.length; i++) {
      final val = g.grid[i];
      if (val < 0) continue;
      final c = o + hexCenter(g.qOf(i), g.rOf(i), s);
      if (val == HexCell.empty) {
        canvas.drawPath(hexPath(c, s * 0.93), Paint()..color = empty);
        canvas.drawPath(hexPath(c, s * 0.9), rim);
      } else {
        paintHexCell(canvas, c, s, v.colorOf(val), mark: v.markOf(val));
      }
      if (v._flash.contains(i)) {
        canvas.drawPath(hexPath(c, s * 0.93), Paint()..color = Colors.white.withValues(alpha: 0.6));
      }
    }
    // Önizleme
    final t = v._hoverTray, h = v._hover;
    if (t != null && h != null) {
      final p = g.tray[t];
      if (p != null) {
        final ok = g.canPlace(p, h.$1, h.$2);
        for (final cc in p.cells) {
          final q = h.$1 + cc[0], r = h.$2 + cc[1];
          if (!g.inside(q, r)) continue;
          paintHexCell(canvas, o + hexCenter(q, r, s), s, ok ? v.colorOf(p.color) : Colors.redAccent,
              alpha: ok ? 0.45 : 0.35);
        }
      }
    }
    // İpucu
    final hint = v._hint;
    if (hint != null) {
      final p = g.tray[hint.$1];
      if (p != null) {
        for (final cc in p.cells) {
          paintHexCell(canvas, o + hexCenter(hint.$2 + cc[0], hint.$3 + cc[1], s), s,
              Colors.amber, outline: true);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
