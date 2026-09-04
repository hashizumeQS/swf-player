import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swf_core/testing.dart';
import 'package:swf_player/swf_player.dart';

/// 変数セット `score = 42` のDoAction付き1フレームSWF（240x240 / 12fps）。
///
/// frame0のDoActionはSwfStage構築時（=load完了時）に実行される。
Uint8List buildVariableSwf() {
  final builder = SwfBuilder()
    ..doAction(Asm().pushString('score').pushFloat(42).op(0x1D).build())
    ..showFrame();
  return builder.build();
}

/// frame0は空、frame1で `score = 42` を設定する2フレームSWF。
/// フレーム進行が起きて初めて変数が入る（進行検証用）。
Uint8List buildDeferredVariableSwf() {
  final builder = SwfBuilder()
    ..showFrame()
    ..doAction(Asm().pushString('score').pushFloat(42).op(0x1D).build())
    ..showFrame();
  return builder.build();
}

/// dispatchKey/dispatchTapの呼び出しを記録するテストダブル。
class RecordingController extends SwfPlayerController {
  final keys = <int>[];
  final taps = <Offset>[];

  @override
  void dispatchKey(int swfKeyCode) {
    keys.add(swfKeyCode);
    super.dispatchKey(swfKeyCode);
  }

  @override
  void dispatchTap(double stageXPx, double stageYPx) {
    taps.add(Offset(stageXPx, stageYPx));
    super.dispatchTap(stageXPx, stageYPx);
  }
}

Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 240, height: 240, child: child),
        ),
      ),
    );

void main() {
  testWidgets('未ロード中はローディング表示、ロード後はCustomPaintが出る', (tester) async {
    final controller = SwfPlayerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(wrap(SwfPlayerView(controller: controller)));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.runAsync(() => controller.load(buildVariableSwf()));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is StagePainter),
      findsOneWidget,
    );
  });

  testWidgets('ステージ描画はViewの枠でクリップされる（枠外にはみ出さない）', (tester) async {
    // SWFの図形はステージ矩形の外まで置かれることがあり、CustomPaintは既定で
    // クリップしないため、Viewより広い親（横長ウィンドウ等）に描画が漏れていた
    final controller = SwfPlayerController();
    addTearDown(controller.dispose);
    await tester.runAsync(() => controller.load(buildVariableSwf()));
    await tester.pumpWidget(wrap(SwfPlayerView(controller: controller)));

    final clip = find.descendant(
      of: find.byType(SwfPlayerView),
      matching: find.ancestor(
        of: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is StagePainter),
        matching: find.byType(ClipRect),
      ),
    );
    expect(clip, findsOneWidget);
    expect(tester.getSize(clip), const Size(240, 240));
  });

  testWidgets('ロード失敗時はエラー表示になる', (tester) async {
    final controller = SwfPlayerController();
    addTearDown(controller.dispose);
    await tester.runAsync(() => controller.load(Uint8List.fromList([1, 2, 3])));
    await tester.pumpWidget(wrap(SwfPlayerView(controller: controller)));

    expect(find.byKey(const Key('swfPlayerError')), findsOneWidget);
  });

  testWidgets('Tickerがフレームレートに従ってフレームを進める', (tester) async {
    final controller = SwfPlayerController();
    addTearDown(controller.dispose);
    await tester.runAsync(() => controller.load(buildDeferredVariableSwf()));
    await tester.pumpWidget(wrap(SwfPlayerView(controller: controller)));

    expect(controller.getVariable('score'), isNull);
    // 12fps = 約83ms/フレーム。100ms進めれば1フレーム進行しDoActionが走る
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.getVariable('score')?.toNumber(), 42);
  });

  testWidgets('paused中はフレームが進まない', (tester) async {
    final controller = SwfPlayerController()..paused = true;
    addTearDown(controller.dispose);
    await tester.runAsync(() => controller.load(buildDeferredVariableSwf()));
    await tester.pumpWidget(wrap(SwfPlayerView(controller: controller)));

    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.getVariable('score'), isNull);
  });

  testWidgets('controller差し替え時に蓄積時間を持ち越さない', (tester) async {
    final a = SwfPlayerController();
    final b = SwfPlayerController();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await tester.runAsync(() => a.load(buildDeferredVariableSwf()));
    await tester.runAsync(() => b.load(buildDeferredVariableSwf()));

    await tester.pumpWidget(wrap(SwfPlayerView(controller: a)));
    // 1フレーム(約83ms)未満だけ進めて蓄積を作る
    await tester.pump(const Duration(milliseconds: 70));
    expect(a.getVariable('score'), isNull);

    // ロード済み同士でcontrollerを差し替える
    await tester.pumpWidget(wrap(SwfPlayerView(controller: b)));
    await tester.pump(const Duration(milliseconds: 16));
    // 旧controllerの蓄積(70ms)を持ち越すと16msで1フレーム進んでしまう
    expect(b.getVariable('score'), isNull);

    await tester.pump(const Duration(milliseconds: 100));
    expect(b.getVariable('score')?.toNumber(), 42);
  });

  testWidgets('物理キーがSWFキーコードに変換されて配送される', (tester) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    await tester.runAsync(() => controller.load(buildVariableSwf()));
    await tester.pumpWidget(wrap(SwfPlayerView(controller: controller)));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);

    expect(
        controller.keys, [SwfKeyCode.enter, SwfKeyCode.digit5, SwfKeyCode.up]);
  });

  testWidgets('タップがステージ座標（幅基準の等倍逆算）で配送される', (tester) async {
    final controller = RecordingController();
    addTearDown(controller.dispose);
    await tester.runAsync(() => controller.load(buildVariableSwf()));
    await tester.pumpWidget(wrap(SwfPlayerView(controller: controller)));
    await tester.pump();

    // ステージは240px基準・表示も240pxなので等倍。中央タップ=(120,120)
    await tester.tapAt(tester.getCenter(find.byType(SwfPlayerView)));
    expect(controller.taps, hasLength(1));
    expect(controller.taps.single.dx, closeTo(120, 1));
    expect(controller.taps.single.dy, closeTo(120, 1));
  });

  group('swfKeyCodeForLogicalKey', () {
    test('方向・決定・数字・記号キーを変換し、対象外はnull', () {
      expect(swfKeyCodeForLogicalKey(LogicalKeyboardKey.arrowLeft),
          SwfKeyCode.left);
      expect(
          swfKeyCodeForLogicalKey(LogicalKeyboardKey.space), SwfKeyCode.enter);
      expect(swfKeyCodeForLogicalKey(LogicalKeyboardKey.numpad7),
          SwfKeyCode.digit7);
      expect(swfKeyCodeForLogicalKey(LogicalKeyboardKey.numberSign),
          SwfKeyCode.hash);
      expect(swfKeyCodeForLogicalKey(LogicalKeyboardKey.keyA), isNull);
    });
  });
}
