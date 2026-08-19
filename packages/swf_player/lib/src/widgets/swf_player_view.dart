import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../controller/swf_player_controller.dart';
import '../keyboard/swf_key_mapping.dart';
import '../render/shape_path_builder.dart';
import '../render/stage_painter.dart';

/// キャッチアップで一度に進める最大フレーム数（それ以上の遅延は破棄）。
const _maxCatchUpFrames = 2;

/// SWFステージを描画し、フレーム進行と入力を仲介するウィジェット。
///
/// 状態は[SwfPlayerController]が所有する。本ウィジェットの責務は
/// (a) Tickerによるフレームレート追従（[SwfPlayerController.paused]中は
/// 蓄積時間を破棄して停止）、(b) 物理キーボード入力の変換・配送、
/// (c) タップのステージ座標変換・配送、(d) [StagePainter]での描画。
///
/// レイアウトは親の制約に従う。ステージのアスペクト比維持は利用側で
/// `AspectRatio`等を使って行う。
class SwfPlayerView extends StatefulWidget {
  const SwfPlayerView({
    super.key,
    required this.controller,
    this.autofocus = true,
    this.enableKeyboard = true,
    this.enableTap = true,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final SwfPlayerController controller;

  /// 物理キーボード入力用のフォーカスを自動取得するか。
  final bool autofocus;

  /// 物理キーボード入力をSWFキーコードへ変換して配送するか。
  final bool enableKeyboard;

  /// タップをステージ座標へ変換して配送するか。
  final bool enableTap;

  /// ロード完了前の表示（既定はローディングインジケータ）。
  final WidgetBuilder? loadingBuilder;

  /// ロード失敗時の表示（既定はエラー内容のテキスト）。
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  State<SwfPlayerView> createState() => _SwfPlayerViewState();
}

class _SwfPlayerViewState extends State<SwfPlayerView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ShapePathBuilder _pathBuilder = ShapePathBuilder();
  Duration _lastTick = Duration.zero;
  Duration _accumulator = Duration.zero;

  SwfPlayerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _controller.addListener(_onControllerChanged);
    _syncTicker();
  }

  @override
  void didUpdateWidget(SwfPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      // 旧controllerの蓄積時間・基準時刻を新controllerへ持ち越さない
      _ticker.stop();
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _ticker.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(_syncTicker);
  }

  void _syncTicker() {
    if (_controller.isLoaded && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _accumulator = Duration.zero;
      _ticker.start();
    } else if (!_controller.isLoaded && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final stage = _controller.stage;
    if (stage == null) return;
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;
    // 一時停止中は蓄積時間も捨て、再開直後のキャッチアップ進行を防ぐ
    if (_controller.paused) {
      _accumulator = Duration.zero;
      return;
    }
    final frameDuration = Duration(
      microseconds:
          (Duration.microsecondsPerSecond / stage.movie.frameRate).round(),
    );
    _accumulator += delta;
    var advanced = 0;
    while (_accumulator >= frameDuration && advanced < _maxCatchUpFrames) {
      _controller.advanceFrame();
      _accumulator -= frameDuration;
      advanced++;
    }
    if (_accumulator > frameDuration * _maxCatchUpFrames) {
      _accumulator = Duration.zero;
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enableKeyboard || _controller.paused) {
      // 一時停止中（オーバーレイ表示等）はTextField等へイベントを流す
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final code = swfKeyCodeForLogicalKey(event.logicalKey);
      if (code != null) {
        _controller.dispatchKey(code);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final error = _controller.loadError;
    if (error != null) {
      return widget.errorBuilder?.call(context, error) ??
          Center(
            child: Text('$error', key: const Key('swfPlayerError')),
          );
    }
    final stage = _controller.stage;
    final bitmaps = _controller.bitmaps;
    if (stage == null || bitmaps == null) {
      return widget.loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator());
    }

    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _onKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // StagePainterと同じ幅基準の等倍スケールで逆変換する
          final stageWidthPx = stage.movie.stageRect.widthTwips / 20;
          final scale = constraints.maxWidth / stageWidthPx;
          return GestureDetector(
            onTapUp: widget.enableTap
                ? (details) => _controller.dispatchTap(
                      details.localPosition.dx / scale,
                      details.localPosition.dy / scale,
                    )
                : null,
            child: CustomPaint(
              painter: StagePainter(
                stage: stage,
                pathBuilder: _pathBuilder,
                bitmaps: bitmaps,
                hiddenCharacterIds: _controller.hiddenCharacterIds,
                overridePositionsPx: _controller.overridePositionsPx,
                repaint: _controller.repaint,
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }
}
