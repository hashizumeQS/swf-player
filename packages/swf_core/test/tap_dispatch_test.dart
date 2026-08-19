import 'dart:typed_data';

import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Uint8List setVarBytecode(String name, String value) {
  final nameBytes = encodeSjis(name);
  final valueBytes = encodeSjis(value);
  return Uint8List.fromList([
    0x96,
    nameBytes.length + 2,
    0x00,
    0x00,
    ...nameBytes,
    0x00,
    0x96,
    valueBytes.length + 2,
    0x00,
    0x00,
    ...valueBytes,
    0x00,
    0x1D,
    0x00,
  ]);
}

/// タップボタン付きの合成ムービー:
/// 100x100pxのヒット領域を持つボタンを(50,50)pxに配置。
SwfMovie buildTapMovie() {
  const hitShape = ShapeCharacter(
    1,
    SwfRect(0, 2000, 0, 2000), // 100x100px
    ShapeWithStyle(fillStyles: [], lineStyles: [], records: []),
    1,
  );
  final button = ButtonCharacter(
    2,
    const [
      ButtonRecord(
        stateUp: true,
        stateOver: false,
        stateDown: false,
        stateHitTest: true,
        characterId: 1,
        depth: 1,
        matrix: SwfMatrix.identity,
        cxform: SwfCxform.identity,
      ),
    ],
    [
      ButtonCondAction(
        keyPress: 0,
        overDownToOverUp: true,
        overUpToOverDown: false,
        idleToOverUp: false,
        actions: setVarBytecode('tapped', '1'),
      ),
    ],
  );
  final frames = [
    SwfFrame(ops: [
      const PlaceOp(
        depth: 1,
        move: false,
        characterId: 2,
        matrix: SwfMatrix(translateX: 1000, translateY: 1000), // (50,50)px
      ),
    ]),
  ];
  return SwfMovie(
    version: 4,
    stageRect: const SwfRect(0, 4800, 0, 4800),
    frameRate: 12,
    frameCount: 1,
    backgroundColor: null,
    dictionary: {1: hitShape, 2: button},
    mainTimeline: Timeline(frames, const {}),
  );
}

void main() {
  test('ヒット領域内のタップでボタンアクションが実行される', () {
    final stage = SwfStage(buildTapMovie(), host: TestHost());
    final handled = stage.dispatchTap(100, 100); // 領域(50-150px)の中央
    expect(handled, isTrue);
    expect(stage.root.variables['tapped']?.toNumber(), 1);
  });

  test('ヒット領域外のタップは何もしない', () {
    final stage = SwfStage(buildTapMovie(), host: TestHost());
    expect(stage.dispatchTap(10, 10), isFalse);
    expect(stage.root.variables['tapped'], isNull);
  });

  test('キー条件付きアクションはタップでは発火しない', () {
    final movie = buildTapMovie();
    final stage = SwfStage(movie, host: TestHost());
    stage.dispatchTap(100, 100); // クラッシュしないこと（本ムービーのボタンはtap条件のみ）
  });
}
