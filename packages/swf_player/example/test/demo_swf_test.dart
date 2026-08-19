import 'package:flutter_test/flutter_test.dart';
import 'package:swf_player/swf_player.dart';

import 'package:swf_player_example/demo_swf.dart';

void main() {
  group('buildDemoSwf', () {
    test('SwfParserで読め、シーンラベルが期待通り存在する', () {
      final movie = SwfParser.parse(buildDemoSwf());

      expect(movie.mainTimeline.labelToFrame.keys,
          containsAll(['scene1', 'scene2', 'scene3', 'over']));
    });

    test('SwfStageで数フレーム進めてもクラッシュしない', () {
      final movie = SwfParser.parse(buildDemoSwf());
      final stage = SwfStage(movie);

      for (var i = 0; i < 10; i++) {
        stage.advanceFrame();
      }

      // クラッシュせず初期シーンのラベルに留まっている
      expect(stage.root.currentFrameLabel, 'scene1');
    });

    test('digit1キーのdispatchKeyでscene変数がscene1(1)へ変わる', () {
      final movie = SwfParser.parse(buildDemoSwf());
      final stage = SwfStage(movie);
      expect(stage.root.variables['scene']?.toNumber(), 1);

      // 一旦scene3へ移動してから、digit1でscene1へ戻れることを確認する
      final movedTo3 = stage.dispatchKey(SwfKeyCode.digit3);
      expect(movedTo3, isTrue);
      expect(stage.root.variables['scene']?.toNumber(), 3);

      final movedTo1 = stage.dispatchKey(SwfKeyCode.digit1);
      expect(movedTo1, isTrue);
      expect(stage.root.variables['scene']?.toNumber(), 1);
    });

    test('hashキーのdispatchKeyでoverラベルへ到達する', () {
      final movie = SwfParser.parse(buildDemoSwf());
      final stage = SwfStage(movie);
      final seen = <String>[];
      stage.onRootLabel = seen.add;

      final handled = stage.dispatchKey(SwfKeyCode.hash);

      expect(handled, isTrue);
      expect(seen, contains('over'));
    });
  });
}
