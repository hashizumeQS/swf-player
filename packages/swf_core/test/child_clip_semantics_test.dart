import 'dart:typed_data';

import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// 3フレームのスプライト（各フレームで /:log に自分のフレーム番号を追記相当）
SpriteCharacter buildChildSprite() {
  return SpriteCharacter(
    10,
    Timeline([
      SwfFrame(actions: [setVarBytecode('/:childF1', 'ran')]),
      SwfFrame(actions: [setVarBytecode('/:childF2', 'ran')]),
      SwfFrame(),
    ], const {}),
  );
}

SwfMovie buildMovie() {
  // rootは3フレーム: frame2で子スプライトを配置
  final frames = [
    SwfFrame(),
    SwfFrame(ops: [
      const PlaceOp(depth: 1, move: false, characterId: 10, name: 'mc'),
    ]),
    SwfFrame(),
  ];
  return SwfMovie(
    version: 4,
    stageRect: const SwfRect(0, 4800, 0, 4800),
    frameRate: 12,
    frameCount: 3,
    backgroundColor: null,
    dictionary: {10: buildChildSprite()},
    mainTimeline: Timeline(frames, const {}),
  );
}

void main() {
  group('新規配置クリップのフレームセマンティクス', () {
    test('配置フレーム中はframe1のまま（同フレームで進まない）', () {
      final stage = SwfStage(buildMovie(), host: TestHost());
      stage.advanceFrame(); // root f2: 子を配置
      final child = stage.root.childByName('mc')!;
      expect(child.currentFrame, 1, reason: '配置フレーム中はframe1のはず');
    });

    test('配置フレームで子のframe1アクションが実行される', () {
      final stage = SwfStage(buildMovie(), host: TestHost());
      stage.advanceFrame(); // 配置
      expect(stage.root.getVariable('childF1')?.toFlashString(), 'ran',
          reason: '子のframe1アクションが実行されるはず');
      expect(stage.root.getVariable('childF2'), isNull,
          reason: 'frame2はまだ実行されないはず');
    });

    test('次のフレームでframe2へ進みそのアクションが実行される', () {
      final stage = SwfStage(buildMovie(), host: TestHost());
      stage.advanceFrame(); // 配置(子f1)
      stage.advanceFrame(); // 子f2
      final child = stage.root.childByName('mc')!;
      expect(child.currentFrame, 2);
      expect(stage.root.getVariable('childF2')?.toFlashString(), 'ran');
    });
  });

  group('プロパティ: 回転・スケール・サイズ', () {
    late SwfStage stage;
    late ActionInterpreter vm;
    late TestHost host;

    setUp(() {
      host = TestHost();
      const shape = ShapeCharacter(
        20,
        SwfRect(0, 2000, 0, 1000), // 100x50px
        ShapeWithStyle(fillStyles: [], lineStyles: [], records: []),
        1,
      );
      const sprite = SpriteCharacter(
        21,
        Timeline([], {}),
      );
      final frames = [
        SwfFrame(ops: [
          const PlaceOp(depth: 1, move: false, characterId: 21, name: 'mc'),
        ]),
      ];
      final movie = SwfMovie(
        version: 4,
        stageRect: const SwfRect(0, 4800, 0, 4800),
        frameRate: 12,
        frameCount: 1,
        backgroundColor: null,
        dictionary: const {20: shape, 21: sprite},
        mainTimeline: Timeline(frames, const {}),
      );
      stage = SwfStage(movie, host: host);
      vm = ActionInterpreter(host);
    });

    // SetProperty(path, index, value) を実行するヘルパー
    void setProp(String path, int index, double value) {
      final pathBytes = encodeSjis(path);
      final bd = ByteData(4)..setFloat32(0, index.toDouble(), Endian.little);
      final vd = ByteData(4)..setFloat32(0, value, Endian.little);
      vm.run(
        Uint8List.fromList([
          0x96, pathBytes.length + 2, 0x00, 0x00, ...pathBytes, 0x00,
          0x96, 5, 0x00, 0x01, ...bd.buffer.asUint8List(),
          0x96, 5, 0x00, 0x01, ...vd.buffer.asUint8List(),
          0x23, // SetProperty
          0x00,
        ]),
        stage.root,
      );
    }

    double getProp(String path, int index) {
      final pathBytes = encodeSjis(path);
      final bd = ByteData(4)..setFloat32(0, index.toDouble(), Endian.little);
      vm.run(
        Uint8List.fromList([
          0x96, 3, 0x00, 0x00, 0x72, 0x00, // Push 'r'
          0x96, pathBytes.length + 2, 0x00, 0x00, ...pathBytes, 0x00,
          0x96, 5, 0x00, 0x01, ...bd.buffer.asUint8List(),
          0x22, // GetProperty
          0x1D, // SetVariable
          0x00,
        ]),
        stage.root,
      );
      return stage.root.variables['r']!.toNumber();
    }

    test('_rotationのset/getが機能する', () {
      setProp('/mc', 10, 90);
      expect(getProp('/mc', 10), closeTo(90, 0.01));
      final m = stage.root.displayList[1]!.matrix;
      // 90度回転: scaleX≈0, rotateSkew0≈1
      expect(m.scaleX, closeTo(0, 0.001));
      expect(m.rotateSkew0, closeTo(1, 0.001));
    });

    test('回転後も_xscaleが維持され、setで回転が壊れない', () {
      setProp('/mc', 10, 45); // 45度回転
      setProp('/mc', 2, 200); // xscale 200%
      expect(getProp('/mc', 2), closeTo(200, 0.1));
      expect(getProp('/mc', 10), closeTo(45, 0.1), reason: '回転が維持されるはず');
    });
  });
}
