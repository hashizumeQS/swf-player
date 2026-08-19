import 'dart:typed_data';

import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

import 'package:swf_core/testing.dart';
import 'helpers.dart';

/// ラベル付きの合成ムービー: frame2に"mid"、frame3に"over"
SwfMovie buildLabeledMovie({List<SwfFrame>? frames}) {
  final f = frames ??
      [
        SwfFrame(),
        SwfFrame(label: 'mid'),
        SwfFrame(label: 'over'),
      ];
  final labels = <String, int>{
    for (var i = 0; i < f.length; i++)
      if (f[i].label != null) f[i].label!: i,
  };
  return SwfMovie(
    version: 4,
    stageRect: const SwfRect(0, 4800, 0, 4800),
    frameRate: 12,
    frameCount: f.length,
    backgroundColor: null,
    dictionary: const {},
    mainTimeline: Timeline(f, labels),
  );
}

/// 最小バイトコード: Push文字列2つ + SetVariable + End
Uint8List setVarBytecode(String name, String value) {
  final nameBytes = encodeSjis(name);
  final valueBytes = encodeSjis(value);
  return Uint8List.fromList([
    0x96, nameBytes.length + 2, 0x00, 0x00, ...nameBytes, 0x00,
    0x96, valueBytes.length + 2, 0x00, 0x00, ...valueBytes, 0x00,
    0x1D, // SetVariable
    0x00,
  ]);
}

void main() {
  test('advanceFrameでラベル到達が通知される', () {
    final stage = SwfStage(buildLabeledMovie(), host: TestHost());
    final seen = <String>[];
    stage.onRootLabel = seen.add;
    stage.advanceFrame(); // frame2 "mid"
    expect(seen, ['mid']);
    stage.advanceFrame(); // frame3 "over"
    expect(seen, ['mid', 'over']);
  });

  test('プログラム的gotoFrameはflushLabelEventsで通知される', () {
    final stage = SwfStage(buildLabeledMovie(), host: TestHost());
    final seen = <String>[];
    stage.onRootLabel = seen.add;
    stage.root.gotoFrame(3);
    stage.flushLabelEvents();
    expect(seen, ['over']);
  });

  test('stop中は再通知しない', () {
    final stage = SwfStage(buildLabeledMovie(), host: TestHost());
    final seen = <String>[];
    stage.onRootLabel = seen.add;
    stage.root.gotoFrame(3);
    stage.flushLabelEvents();
    stage.root.stop();
    stage.advanceFrame();
    stage.advanceFrame();
    expect(seen, ['over']);
  });

  test('ループ再入では再通知される（1周ごとに到達扱い）', () {
    final stage = SwfStage(buildLabeledMovie(), host: TestHost());
    final seen = <String>[];
    stage.onRootLabel = seen.add;
    for (var i = 0; i < 6; i++) {
      stage.advanceFrame(); // 2(mid) 3(over) 1 2(mid) 3(over) 1
    }
    expect(seen, ['mid', 'over', 'mid', 'over']);
  });

  test('通知はフレームのDoAction消化後（スコア確定後）に発火する', () {
    // frame2 "over" のDoActionが score=42 を設定する
    final frames = [
      SwfFrame(),
      SwfFrame(label: 'over', actions: [setVarBytecode('score', '42')]),
    ];
    final stage = SwfStage(buildLabeledMovie(frames: frames), host: TestHost());
    double? scoreAtNotify;
    stage.onRootLabel = (label) {
      if (label == 'over') {
        scoreAtNotify = stage.root.variables['score']?.toNumber();
      }
    };
    stage.advanceFrame();
    expect(scoreAtNotify, 42, reason: '通知時点でDoAction設定済みの値が読めるはず');
  });

  test(
      '起動キー押下→放置でoverラベルに到達し通知される'
      '（タイトル→決定→ゲーム→放置の合成再現）', () {
    final startActions = Asm().op(0x06).build(); // Play: 放置進行を再開
    final builder = SwfBuilder()
      ..showFrame() // frame0: 導入（無地）
      ..frameLabel('title')
      ..doAction(Asm().op(0x07).build()) // Stop: タイトルで待機
      ..defineButton(1, keyPress: SwfKeyCode.enter, actions: startActions)
      ..placeObject2(depth: 1, characterId: 1)
      ..showFrame() // frame1: title
      ..showFrame() // frame2: game(idle)
      ..showFrame() // frame3: game(idle)
      ..frameLabel('over')
      ..doAction(setVarBytecode('score', '42'))
      ..showFrame(); // frame4: over
    final movie = SwfParser.parse(builder.build());
    final stage = SwfStage(movie, host: TestHost());
    final seen = <String>[];
    stage.onRootLabel = seen.add;

    stage.advanceFrame(); // frame0 -> frame1(title)
    expect(seen, contains('title'));

    stage.dispatchKey(SwfKeyCode.enter); // 決定キーでゲーム開始
    for (var i = 0; i < 10 && !seen.contains('over'); i++) {
      stage.advanceFrame();
    }
    expect(seen, contains('over'), reason: 'ゲームオーバー到達で通知されるはず');

    // over時点のスコア変数が読めること
    expect(stage.root.variables['score']?.toNumber(), 42);
  });
}
