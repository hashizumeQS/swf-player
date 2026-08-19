import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:swf_core/testing.dart';
import 'package:swf_player/swf_player.dart';

/// 変数セット: `score = 42` を実行するDoAction付き1フレームSWF。
///
/// frame0のDoActionはSwfStage構築時（=load完了時）に実行される。
Uint8List buildVariableSwf() {
  final builder = SwfBuilder()
    ..doAction(Asm().pushString('score').pushFloat(42).op(0x1D).build())
    ..showFrame();
  return builder.build();
}

/// frame0は空、frame1で `score = 42` を設定する2フレームSWF（進行検証用）。
Uint8List buildDeferredVariableSwf() {
  final builder = SwfBuilder()
    ..showFrame()
    ..doAction(Asm().pushString('score').pushFloat(42).op(0x1D).build())
    ..showFrame();
  return builder.build();
}

/// ラベル2枚構成: frame0(start) → frame1(over)。
Uint8List buildLabeledSwf() {
  final builder = SwfBuilder()
    ..frameLabel('start')
    ..showFrame()
    ..frameLabel('over')
    ..showFrame();
  return builder.build();
}

/// prime()が必ず失敗するレジストリ（デコード失敗の再現用）。
class ThrowingRegistry extends BitmapRegistry {
  bool disposed = false;

  @override
  Future<void> prime(SwfMovie movie) async {
    throw StateError('decode failure');
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  group('SwfPlayerController ロード', () {
    test('合成SWFをロードするとstage/bitmapsが使え、リスナーに通知される', () async {
      final controller = SwfPlayerController();
      var notified = 0;
      controller.addListener(() => notified++);

      expect(controller.isLoaded, isFalse);
      await controller.load(buildVariableSwf());

      expect(controller.isLoaded, isTrue);
      expect(controller.loadError, isNull);
      expect(controller.stage, isNotNull);
      expect(controller.bitmaps, isNotNull);
      expect(notified, greaterThan(0));
      controller.dispose();
    });

    test('壊れたバイト列はloadErrorに入りisLoadedはfalseのまま', () async {
      final controller = SwfPlayerController();
      await controller.load(Uint8List.fromList([1, 2, 3]));

      expect(controller.isLoaded, isFalse);
      expect(controller.loadError, isA<SwfParseException>());
      controller.dispose();
    });

    test('ビットマップ準備の失敗はloadErrorに入り、レジストリは破棄される', () async {
      final spy = ThrowingRegistry();
      final controller = SwfPlayerController(bitmapRegistryFactory: () => spy);
      await controller.load(buildVariableSwf());

      expect(controller.isLoaded, isFalse);
      expect(controller.loadError, isA<StateError>());
      expect(spy.disposed, isTrue);
      controller.dispose();
    });

    test('movieTransformerがパース直後のムービーに適用される', () async {
      SwfMovie? seen;
      final controller = SwfPlayerController(movieTransformer: (m) => seen = m);
      await controller.load(buildVariableSwf());

      expect(seen, isNotNull);
      expect(seen, same(controller.stage!.movie));
      controller.dispose();
    });
  });

  group('SwfPlayerController フレーム進行と変数', () {
    test('advanceFrame()でDoActionが実行されgetVariableで読める', () async {
      final controller = SwfPlayerController();
      await controller.load(buildDeferredVariableSwf());

      expect(controller.getVariable('score'), isNull);
      controller.advanceFrame();
      expect(controller.getVariable('score')?.toNumber(), 42);
      controller.dispose();
    });

    test('advanceFrame()はrepaint通知を増やす', () async {
      final controller = SwfPlayerController();
      await controller.load(buildVariableSwf());

      final before = controller.repaint.value;
      controller.advanceFrame();
      expect(controller.repaint.value, greaterThan(before));
      controller.dispose();
    });
  });

  group('SwfPlayerController ラベル通知', () {
    test('load前に設定したonRootLabelがラベル到達で発火する', () async {
      final labels = <String>[];
      final controller = SwfPlayerController();
      controller.onRootLabel = labels.add;
      await controller.load(buildLabeledSwf());

      // 構築時点でframe0(start)に位置するため、進行で frame1(over) →
      // ラップして frame0(start) の順に入る
      controller.advanceFrame();
      controller.advanceFrame();
      expect(labels, unorderedEquals(['start', 'over']));
      expect(labels.first, 'over');
      controller.dispose();
    });
  });

  group('SwfPlayerController キー入力', () {
    test('dispatchKeyはkeyMap適用後のコードをステージへ配送しrepaintを増やす', () async {
      // CondKeyPress(enter)で score=1 を実行するボタンを配置
      final builder = SwfBuilder()
        ..defineShapeRect(1, widthPx: 10, heightPx: 10)
        ..defineButton(
          2,
          keyPress: SwfKeyCode.enter,
          actions: Asm().pushString('score').pushFloat(1).op(0x1D).build(),
          shapeId: 1,
        )
        ..placeObject2(depth: 1, characterId: 2)
        ..showFrame();
      final controller = SwfPlayerController();
      await controller.load(builder.build());
      controller.advanceFrame();

      // digit5 → enter に再マップして配送
      controller.keyMap = {SwfKeyCode.digit5: SwfKeyCode.enter};
      final before = controller.repaint.value;
      controller.dispatchKey(SwfKeyCode.digit5);

      expect(controller.getVariable('score')?.toNumber(), 1);
      expect(controller.repaint.value, greaterThan(before));
      controller.dispose();
    });

    test('paused中はdispatchKeyを配送しない', () async {
      final builder = SwfBuilder()
        ..defineShapeRect(1, widthPx: 10, heightPx: 10)
        ..defineButton(
          2,
          keyPress: SwfKeyCode.enter,
          actions: Asm().pushString('score').pushFloat(1).op(0x1D).build(),
          shapeId: 1,
        )
        ..placeObject2(depth: 1, characterId: 2)
        ..showFrame();
      final controller = SwfPlayerController();
      await controller.load(builder.build());
      controller.advanceFrame();

      controller.paused = true;
      controller.dispatchKey(SwfKeyCode.enter);
      expect(controller.getVariable('score'), isNull);

      controller.paused = false;
      controller.dispatchKey(SwfKeyCode.enter);
      expect(controller.getVariable('score')?.toNumber(), 1);
      controller.dispose();
    });
  });

  group('SwfPlayerController 描画オプション', () {
    test('hiddenCharacterIdsはステージの入力無効IDにも同期される', () async {
      final controller = SwfPlayerController();
      await controller.load(buildVariableSwf());

      controller.hiddenCharacterIds = {7, 8};
      expect(controller.stage!.inputDisabledCharacterIds, {7, 8});
      controller.dispose();
    });

    test('overridePositionsPxの変更はrepaint通知を増やす', () async {
      final controller = SwfPlayerController();
      await controller.load(buildVariableSwf());

      final before = controller.repaint.value;
      controller.overridePositionsPx = {1: (x: 5.0, y: 5.0)};
      expect(controller.repaint.value, greaterThan(before));
      controller.dispose();
    });
  });

  group('SwfPlayerController 並行load', () {
    test('後発のloadが常に勝ち、先行loadの中間状態は通知されない', () async {
      // frameCountで区別できる2本（A=1フレーム, B=2フレーム）
      final bytesA = buildVariableSwf();
      final bytesB = buildDeferredVariableSwf();

      final controller = SwfPlayerController();
      final seenFrameCounts = <int>[];
      controller.addListener(() {
        final stage = controller.stage;
        if (stage != null) seenFrameCounts.add(stage.movie.frameCount);
      });

      // Aをawaitせずに開始し、直後にBを開始する
      final first = controller.load(bytesA);
      final second = controller.load(bytesB);
      await first;
      await second;

      // 最終状態はB。破棄されたAのステージが通知に現れてはならない
      expect(controller.stage!.movie.frameCount, 2);
      expect(seenFrameCounts, [2]);
      controller.dispose();
    });
  });

  group('SwfPlayerController dispose', () {
    test('dispose後はstage/bitmapsがnullになり二重disposeも安全', () async {
      final controller = SwfPlayerController();
      await controller.load(buildVariableSwf());

      controller.dispose();
      expect(controller.stage, isNull);
      expect(controller.bitmaps, isNull);
    });
  });
}
