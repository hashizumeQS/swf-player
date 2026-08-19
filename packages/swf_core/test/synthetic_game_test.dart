import 'dart:typed_data';

import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

import 'package:swf_core/testing.dart';
import 'helpers.dart';

/// score変数へ[amount]を加算するバイトコード
/// （push name, push name, GetVariable, push amount, Add, SetVariable）。
Uint8List _addScoreBytecode(double amount) {
  return Asm()
      .pushString('score')
      .pushString('score')
      .op(0x1C) // GetVariable
      .pushFloat(amount)
      .op(0x0A) // Add
      .op(0x1D) // SetVariable
      .build();
}

/// タイトル→決定キーでゲーム開始(ラベルgoto)→スコア加算ボタン→放置で
/// overラベルへ到達する合成ミニゲーム。ヘッドレスプレイスルーの
/// 合成版（実SWF依存のgame_integration_test.dartの代替）。
SwfMovie buildSyntheticGame() {
  final titleActions = Asm()
      .pushString('score')
      .pushFloat(0)
      .op(0x1D) // SetVariable: score = 0
      .op(0x07) // Stop
      .build();
  final startActions = Asm()
      .gotoLabel('game') // ラベルgoto
      .op(0x06) // Play: 放置進行を再開
      .build();
  final scoreActions = _addScoreBytecode(10);

  final builder = SwfBuilder()
    ..showFrame() // frame0: 導入（無地）
    ..frameLabel('title')
    ..defineButton(1, keyPress: SwfKeyCode.enter, actions: startActions)
    ..placeObject2(depth: 1, characterId: 1)
    ..doAction(titleActions)
    ..showFrame() // frame1: title
    ..frameLabel('game')
    ..defineButton(2, keyPress: SwfKeyCode.down, actions: scoreActions)
    ..placeObject2(depth: 2, characterId: 2)
    ..showFrame() // frame2: game
    ..showFrame() // frame3: game(idle)
    ..showFrame() // frame4: game(idle)
    ..frameLabel('over')
    ..showFrame(); // frame5: over

  return SwfParser.parse(builder.build());
}

void main() {
  test('タイトル→決定キーでゲーム開始→スコア加算→放置でoverラベルへ到達する', () {
    final movie = buildSyntheticGame();
    final stage = SwfStage(movie, host: TestHost());
    final seen = <String>[];
    stage.onRootLabel = seen.add;

    stage.advanceFrame(); // frame0 -> frame1(title)
    expect(seen, contains('title'));
    expect(stage.root.variables['score']?.toNumber(), 0);

    final handled = stage.dispatchKey(SwfKeyCode.enter); // ゲーム開始
    expect(handled, isTrue, reason: '決定キーがボタンに届くはず');
    expect(seen, contains('game'), reason: 'ラベルgotoでgameへ遷移するはず');

    stage.dispatchKey(SwfKeyCode.down); // スコア+10
    stage.dispatchKey(SwfKeyCode.down); // スコア+10
    expect(stage.root.variables['score']?.toNumber(), 20,
        reason: 'CondKeyPressボタンでスコアが加算されるはず');

    for (var i = 0; i < 10 && !seen.contains('over'); i++) {
      stage.advanceFrame();
    }
    expect(seen, contains('over'), reason: '放置でゲームオーバーラベルへ到達するはず');
    expect(stage.root.variables['score']?.toNumber(), 20,
        reason: 'over到達までの加算が保持されている');
  });
}
