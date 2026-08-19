import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swf_core/swf_core.dart' show SwfKeyCode;

/// 長押しオートリピートの初回発火までの遅延。
const _autoRepeatInitialDelay = Duration(milliseconds: 300);

/// 長押しオートリピート中の発火間隔。
const _autoRepeatInterval = Duration(milliseconds: 100);

/// キーパッド筐体の背景色。
const _chassisColor = Color(0xFF232326);

/// キー本体の色。
const _keyColor = Color(0xFF3A3A3F);

/// 決定キー（センターキー）を強調する色。
const _emphasisKeyColor = Color(0xFF52525A);

/// ガラケー（日本のフィーチャーフォン）風のバーチャルキーパッド。
///
/// 上部に方向キー（十字＋決定）、下部にテンキー（3列×4行）を配置する。
/// 長押しでオートリピート発火する。
class KeypadWidget extends StatelessWidget {
  const KeypadWidget({
    super.key,
    required this.onKey,
    this.onBack,
    this.onMenu,
  });

  /// SWF CondKeyPressコードでキー押下を通知するコールバック。
  final void Function(int swfKeyCode) onKey;

  /// 左上コーナーのBackボタン（nullなら非表示）。
  final VoidCallback? onBack;

  /// 右上コーナーのMenuボタン（nullなら非表示）。
  final VoidCallback? onMenu;

  static const _maxWidth = 320.0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _chassisColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // リングの楕円の外側（四隅）にコーナーボタンを配置
              SizedBox(
                height: _NavigationRing.height,
                child: Stack(
                  children: [
                    Center(
                      child: _NavigationRing(
                        key: const ValueKey('nav-ring'),
                        onKey: onKey,
                      ),
                    ),
                    if (onBack != null)
                      Positioned(
                        left: 0,
                        top: 0,
                        child: _CornerButton(
                          key: const ValueKey('corner-back'),
                          label: 'Back',
                          onTap: onBack!,
                        ),
                      ),
                    if (onMenu != null)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: _CornerButton(
                          key: const ValueKey('corner-menu'),
                          label: 'Menu',
                          onTap: onMenu!,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _NumericPad(onKey: onKey),
            ],
          ),
        ),
      ),
    );
  }
}

/// リング四隅の小型機能ボタン（Back/Menu等）。
class _CornerButton extends StatelessWidget {
  const _CornerButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    return Material(
      color: _keyColor,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
      ),
    );
  }
}

/// ガラケー風ナビゲーションリング。
/// 楕円リングを斜め45°で4分割した上下左右キーが、中央の真円の決定キーを囲む。
class _NavigationRing extends StatefulWidget {
  const _NavigationRing({super.key, required this.onKey});

  final void Function(int swfKeyCode) onKey;

  static const width = 230.0;
  static const height = 130.0;
  static const centerDiameter = 84.0;

  @override
  State<_NavigationRing> createState() => _NavigationRingState();
}

class _NavigationRingState extends State<_NavigationRing> {
  int? _pressedKey;
  Timer? _initialTimer;
  Timer? _repeatTimer;

  void _fire(int key) {
    HapticFeedback.lightImpact();
    widget.onKey(key);
  }

  /// タップ位置がどのキー領域か判定する。
  /// 中央の真円=決定、楕円内は正規化座標の角度で4セクターに分割
  /// （±45°=右、45〜135°=下、135〜225°=左、それ以外=上）。
  int? _keyAt(Offset local) {
    final cx = _NavigationRing.width / 2;
    final cy = _NavigationRing.height / 2;
    final pdx = local.dx - cx;
    final pdy = local.dy - cy;
    const centerRadius = _NavigationRing.centerDiameter / 2;
    if (pdx * pdx + pdy * pdy <= centerRadius * centerRadius) {
      return SwfKeyCode.enter;
    }
    final nx = pdx / cx;
    final ny = pdy / cy;
    if (nx * nx + ny * ny > 1) return null; // 楕円の外
    final deg = math.atan2(ny, nx) * 180 / math.pi; // -180..180
    if (deg >= -45 && deg < 45) return SwfKeyCode.right;
    if (deg >= 45 && deg < 135) return SwfKeyCode.down;
    if (deg >= -135 && deg < -45) return SwfKeyCode.up;
    return SwfKeyCode.left;
  }

  void _handleDown(TapDownDetails details) {
    final key = _keyAt(details.localPosition);
    if (key == null) return;
    setState(() => _pressedKey = key);
    _fire(key);
    _initialTimer = Timer(_autoRepeatInitialDelay, () {
      _repeatTimer = Timer.periodic(_autoRepeatInterval, (_) => _fire(key));
    });
  }

  void _release() {
    _initialTimer?.cancel();
    _repeatTimer?.cancel();
    _initialTimer = null;
    _repeatTimer = null;
    if (_pressedKey != null) setState(() => _pressedKey = null);
  }

  @override
  void dispose() {
    _initialTimer?.cancel();
    _repeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleDown,
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      child: CustomPaint(
        size: const Size(_NavigationRing.width, _NavigationRing.height),
        painter: _RingPainter(pressedKey: _pressedKey),
      ),
    );
  }
}

/// ナビゲーションリングの描画。
class _RingPainter extends CustomPainter {
  const _RingPainter({this.pressedKey});

  final int? pressedKey;

  static const _pressedColor = Color(0xFF5A5A62);
  static const _separatorWidth = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ellipseRect = Offset.zero & size;

    // 楕円リング本体
    canvas.drawOval(ellipseRect, Paint()..color = _keyColor);

    // 押下中セクターのハイライト（楕円弧のくさび形）
    final sectorAngles = <int, (double, double)>{
      SwfKeyCode.right: (-math.pi / 4, math.pi / 2),
      SwfKeyCode.down: (math.pi / 4, math.pi / 2),
      SwfKeyCode.left: (3 * math.pi / 4, math.pi / 2),
      SwfKeyCode.up: (-3 * math.pi / 4, math.pi / 2),
    };
    final pressed = sectorAngles[pressedKey];
    if (pressed != null) {
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(ellipseRect, pressed.$1, pressed.$2, false)
        ..close();
      canvas.drawPath(path, Paint()..color = _pressedColor);
    }

    // 斜め十字の分割線（中央円で上書きされるため中心まで引いてよい）
    final separator = Paint()
      ..color = _chassisColor
      ..strokeWidth = _separatorWidth;
    for (final angle in const [
      -3 * math.pi / 4,
      -math.pi / 4,
      math.pi / 4,
      3 * math.pi / 4,
    ]) {
      final edge = Offset(
        center.dx + size.width / 2 * math.cos(angle),
        center.dy + size.height / 2 * math.sin(angle),
      );
      canvas.drawLine(center, edge, separator);
    }

    // 矢印（各セクターの外周寄りに描く）
    _drawChevron(canvas, center, size, SwfKeyCode.up);
    _drawChevron(canvas, center, size, SwfKeyCode.down);
    _drawChevron(canvas, center, size, SwfKeyCode.left);
    _drawChevron(canvas, center, size, SwfKeyCode.right);

    // 中央の決定キー（真円）
    const centerRadius = _NavigationRing.centerDiameter / 2;
    canvas.drawCircle(
      center,
      centerRadius,
      Paint()
        ..color =
            pressedKey == SwfKeyCode.enter ? _pressedColor : _emphasisKeyColor,
    );
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '決定',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
    textPainter.dispose();
  }

  /// セクター内に山型（チェブロン）矢印を描く。
  void _drawChevron(Canvas canvas, Offset center, Size size, int key) {
    // セクター中心方向の単位ベクトルと、外周からの描画位置
    final (dx, dy) = switch (key) {
      SwfKeyCode.up => (0.0, -1.0),
      SwfKeyCode.down => (0.0, 1.0),
      SwfKeyCode.left => (-1.0, 0.0),
      _ => (1.0, 0.0),
    };
    final pos = Offset(
      center.dx + size.width / 2 * 0.82 * dx,
      center.dy + size.height / 2 * 0.72 * dy,
    );
    const arm = 7.0;
    // 進行方向に凸の山型: 左腕・頂点・右腕
    final tip = pos + Offset(dx, dy) * (arm * 0.6);
    final side = Offset(-dy, dx) * arm; // 直交方向
    final back = Offset(dx, dy) * (-arm * 0.6);
    final path = Path()
      ..moveTo(pos.dx + side.dx + back.dx, pos.dy + side.dy + back.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(pos.dx - side.dx + back.dx, pos.dy - side.dy + back.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.pressedKey != pressedKey;
}

class _NumericKeyDef {
  const _NumericKeyDef(this.label, this.swfKeyCode);

  final String label;
  final int swfKeyCode;
}

/// テンキー部（3列×4行）に並ぶキー定義。
const _numericKeyDefs = [
  _NumericKeyDef('1', SwfKeyCode.digit1),
  _NumericKeyDef('2', SwfKeyCode.digit2),
  _NumericKeyDef('3', SwfKeyCode.digit3),
  _NumericKeyDef('4', SwfKeyCode.digit4),
  _NumericKeyDef('5', SwfKeyCode.digit5),
  _NumericKeyDef('6', SwfKeyCode.digit6),
  _NumericKeyDef('7', SwfKeyCode.digit7),
  _NumericKeyDef('8', SwfKeyCode.digit8),
  _NumericKeyDef('9', SwfKeyCode.digit9),
  _NumericKeyDef('*', SwfKeyCode.asterisk),
  _NumericKeyDef('0', SwfKeyCode.digit0),
  _NumericKeyDef('#', SwfKeyCode.hash),
];

/// テンキー部（3列×4行）: [1][2][3] / [4][5][6] / [7][8][9] / [*][0][#]。
class _NumericPad extends StatelessWidget {
  const _NumericPad({required this.onKey});

  final void Function(int swfKeyCode) onKey;

  static const _columns = 3;

  /// 最小タップターゲット44pt（Apple HIG）を等倍表示時に満たす高さ。
  static const _keyHeight = 44.0;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < _numericKeyDefs.length; i += _columns) {
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: 6));
      }
      final rowDefs = _numericKeyDefs.skip(i).take(_columns);
      rows.add(
        SizedBox(
          height: _keyHeight,
          child: Row(
            children: [
              for (final def in rowDefs) ...[
                if (def != rowDefs.first) const SizedBox(width: 6),
                Expanded(
                  child: _RepeatKey(
                    swfKeyCode: def.swfKeyCode,
                    onKey: onKey,
                    child: Text(
                      def.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

/// 単一キー（テンキー用）。タップで即時発火、長押しでオートリピート発火する。
/// 親（[Expanded]等）から与えられるサイズいっぱいに広がる。
class _RepeatKey extends StatefulWidget {
  const _RepeatKey({
    required this.swfKeyCode,
    required this.onKey,
    required this.child,
  });

  final int swfKeyCode;
  final void Function(int swfKeyCode) onKey;
  final Widget child;

  @override
  State<_RepeatKey> createState() => _RepeatKeyState();
}

class _RepeatKeyState extends State<_RepeatKey> {
  Timer? _initialTimer;
  Timer? _repeatTimer;

  void _fire() {
    HapticFeedback.lightImpact();
    widget.onKey(widget.swfKeyCode);
  }

  void _handleTapDown(TapDownDetails details) {
    _fire();
    _initialTimer = Timer(_autoRepeatInitialDelay, () {
      _repeatTimer = Timer.periodic(_autoRepeatInterval, (_) => _fire());
    });
  }

  void _cancelTimers() {
    _initialTimer?.cancel();
    _repeatTimer?.cancel();
    _initialTimer = null;
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shapeBorder = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    return Material(
      key: ValueKey(widget.swfKeyCode),
      color: _keyColor,
      shape: shapeBorder,
      child: InkWell(
        customBorder: shapeBorder,
        onTapDown: _handleTapDown,
        onTapUp: (_) => _cancelTimers(),
        onTapCancel: _cancelTimers,
        onTap: () {},
        child: Center(child: widget.child),
      ),
    );
  }
}
