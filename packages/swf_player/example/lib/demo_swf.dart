import 'dart:typed_data';

import 'package:swf_core/swf_core.dart';
import 'package:swf_core/testing.dart';

/// スプライト内の可動シェイプが配置されるdepth。
const _movingShapeDepth = 1;

/// テンキー1/2/3・#ボタンが配置されるdepth（全シーンで共通、常時表示）。
const _digit1ButtonDepth = 90;
const _digit2ButtonDepth = 91;
const _digit3ButtonDepth = 92;
const _hashButtonDepth = 93;

/// シーン切替時にルートへ設定する変数名（[SwfPlayerController.getVariable]の
/// デモに使う）。
const _sceneVariableName = 'scene';

/// 各シーンの矩形サイズ（px）。
const _rectSizePx = 30;

/// scene変数へ[sceneNumber]を設定してStopするバイトコード。
Uint8List _setSceneAndStop(int sceneNumber) {
  return Asm()
      .pushString(_sceneVariableName)
      .pushFloat(sceneNumber.toDouble())
      .op(0x1D) // SetVariable
      .op(0x07) // Stop
      .build();
}

/// [label]へgotoするバイトコード（GotoLabelはVM内部で自動的にStopする）。
Uint8List _gotoLabelAction(String label) => Asm().gotoLabel(label).build();

/// 色違いの矩形が数フレームで位置を変える、自己ループするアニメーション
/// スプライトを定義する。（スプライトは末尾フレームに到達すると自動的に
/// 先頭フレームへループする挙動をSwfStageが持つため、ここでは単純に
/// 3フレーム分の位置違いplaceObject2を並べるだけでよい）
void _defineLoopingSprite(
  SwfBuilder builder,
  int spriteId, {
  required int shapeId,
  required List<(int, int)> positionsPx,
}) {
  builder.defineSprite(spriteId, (sprite) {
    for (var i = 0; i < positionsPx.length; i++) {
      final (x, y) = positionsPx[i];
      if (i == 0) {
        sprite.placeObject2(
          depth: _movingShapeDepth,
          characterId: shapeId,
          translateXPx: x,
          translateYPx: y,
        );
      } else {
        sprite.placeObject2(
          depth: _movingShapeDepth,
          translateXPx: x,
          translateYPx: y,
        );
      }
      sprite.showFrame();
    }
  });
}

/// pub.dev公開用サンプルデモの合成SWFを生成する。
///
/// 著作物SWFは使用せず、[SwfBuilder]で実行時に自己完結生成する。
/// 240x240 / 12fpsのステージに、色違いの矩形が数フレームでループ移動する
/// シーンを3つ('scene1'〜'scene3')持ち、テンキー1/2/3で各シーンへ、
/// #キーで終了画面('over')へ遷移する。シーン切替時に[_sceneVariableName]
/// 変数へシーン番号を設定するため、[SwfPlayerController.getVariable]の
/// デモにも使える。
Uint8List buildDemoSwf() {
  final builder = SwfBuilder(widthPx: 240, heightPx: 240, frameRate: 12);

  // シーンごとの矩形（色違い）とループ画面の静止矩形
  builder
    ..defineShapeRect(1,
        widthPx: _rectSizePx,
        heightPx: _rectSizePx,
        fillRgb: 0xE05252) // scene1: 赤
    ..defineShapeRect(2,
        widthPx: _rectSizePx,
        heightPx: _rectSizePx,
        fillRgb: 0x4CAF6D) // scene2: 緑
    ..defineShapeRect(3,
        widthPx: _rectSizePx,
        heightPx: _rectSizePx,
        fillRgb: 0x4A90D9) // scene3: 青
    ..defineShapeRect(4,
        widthPx: 60, heightPx: 60, fillRgb: 0x999999); // over: 灰

  // 各シーンのループアニメーションスプライト（3フレームで巡回）
  _defineLoopingSprite(builder, 11,
      shapeId: 1, positionsPx: const [(20, 20), (150, 20), (85, 150)]);
  _defineLoopingSprite(builder, 12,
      shapeId: 2, positionsPx: const [(190, 20), (20, 190), (190, 190)]);
  _defineLoopingSprite(builder, 13,
      shapeId: 3, positionsPx: const [(105, 20), (20, 105), (190, 105)]);

  // テンキー1/2/3・#ボタン（全シーンで常時有効。frame0で配置し以降は
  // 触れないため、gotoで前後移動しても表示リストに残り続ける）
  builder
    ..defineButton(21,
        keyPress: SwfKeyCode.digit1, actions: _gotoLabelAction('scene1'))
    ..defineButton(22,
        keyPress: SwfKeyCode.digit2, actions: _gotoLabelAction('scene2'))
    ..defineButton(23,
        keyPress: SwfKeyCode.digit3, actions: _gotoLabelAction('scene3'))
    ..defineButton(24,
        keyPress: SwfKeyCode.hash, actions: _gotoLabelAction('over'));

  builder
    ..frameLabel('scene1')
    ..placeObject2(depth: _digit1ButtonDepth, characterId: 21)
    ..placeObject2(depth: _digit2ButtonDepth, characterId: 22)
    ..placeObject2(depth: _digit3ButtonDepth, characterId: 23)
    ..placeObject2(depth: _hashButtonDepth, characterId: 24)
    ..placeObject2(depth: _movingShapeDepth, characterId: 11)
    ..doAction(_setSceneAndStop(1))
    ..showFrame() // frame0: scene1
    ..frameLabel('scene2')
    ..placeObject2(depth: _movingShapeDepth, characterId: 12)
    ..doAction(_setSceneAndStop(2))
    ..showFrame() // frame1: scene2
    ..frameLabel('scene3')
    ..placeObject2(depth: _movingShapeDepth, characterId: 13)
    ..doAction(_setSceneAndStop(3))
    ..showFrame() // frame2: scene3
    ..frameLabel('over')
    ..placeObject2(depth: _movingShapeDepth, characterId: 4)
    ..doAction(Asm().op(0x07).build()) // Stop（矩形は静止したまま留まる）
    ..showFrame(); // frame3: over

  return builder.build();
}
