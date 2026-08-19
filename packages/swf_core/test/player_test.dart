import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// 合成タイムライン: frame1でShape配置(depth1)、frame2でmove、frame3でremove
SwfMovie buildPlacementMovie() {
  const shape = ShapeCharacter(
    1,
    SwfRect(0, 200, 0, 200),
    ShapeWithStyle(fillStyles: [], lineStyles: [], records: []),
    1,
  );
  final frames = [
    SwfFrame(ops: [
      const PlaceOp(
          depth: 1,
          move: false,
          characterId: 1,
          matrix: SwfMatrix(translateX: 100, translateY: 0)),
    ]),
    SwfFrame(ops: [
      const PlaceOp(
          depth: 1,
          move: true,
          matrix: SwfMatrix(translateX: 500, translateY: 300)),
    ]),
    SwfFrame(ops: [const RemoveOp(1)]),
  ];
  return SwfMovie(
    version: 4,
    stageRect: const SwfRect(0, 4800, 0, 4800),
    frameRate: 12,
    frameCount: 3,
    backgroundColor: null,
    dictionary: {1: shape},
    mainTimeline: Timeline(frames, const {}),
  );
}

void main() {
  group('MovieClip 配置セマンティクス', () {
    test('frame1: 新規配置がrenderTreeに現れる', () {
      final stage = SwfStage(buildPlacementMovie(), host: TestHost());
      final nodes = stage.buildRenderTree();
      expect(nodes, hasLength(1));
      expect(nodes.single.character.id, 1);
      expect(nodes.single.matrix.translateX, 100);
    });

    test('frame2: moveで行列のみ更新（キャラクタ維持）', () {
      final stage = SwfStage(buildPlacementMovie(), host: TestHost());
      stage.advanceFrame();
      final nodes = stage.buildRenderTree();
      expect(nodes, hasLength(1));
      expect(nodes.single.character.id, 1);
      expect(nodes.single.matrix.translateX, 500);
      expect(nodes.single.matrix.translateY, 300);
    });

    test('frame3: removeで消える', () {
      final stage = SwfStage(buildPlacementMovie(), host: TestHost());
      stage.advanceFrame();
      stage.advanceFrame();
      expect(stage.buildRenderTree(), isEmpty);
    });

    test('最終フレーム後はframe1へループし再配置される', () {
      final stage = SwfStage(buildPlacementMovie(), host: TestHost());
      stage.advanceFrame(); // 2
      stage.advanceFrame(); // 3
      stage.advanceFrame(); // 1へループ
      expect(stage.root.currentFrame, 1);
      final nodes = stage.buildRenderTree();
      expect(nodes, hasLength(1));
      expect(nodes.single.matrix.translateX, 100);
    });

    test('同depthへのmove無し差し替えは既存の行列を引き継ぐ', () {
      // ドラえもんのダメージ演出で発生: キャラ差し替え時に(0,0)へ飛ぶバグの回帰テスト
      const shapeA = ShapeCharacter(1, SwfRect(0, 100, 0, 100),
          ShapeWithStyle(fillStyles: [], lineStyles: [], records: []), 1);
      const shapeB = ShapeCharacter(2, SwfRect(0, 100, 0, 100),
          ShapeWithStyle(fillStyles: [], lineStyles: [], records: []), 1);
      final frames = [
        SwfFrame(ops: [
          const PlaceOp(
              depth: 1,
              move: false,
              characterId: 1,
              matrix: SwfMatrix(translateX: 2000, translateY: 3000)),
        ]),
        SwfFrame(ops: [
          // 行列指定なしの差し替え（move=false・同depth・別キャラ）
          const PlaceOp(depth: 1, move: false, characterId: 2),
        ]),
      ];
      final movie = SwfMovie(
        version: 4,
        stageRect: const SwfRect(0, 4800, 0, 4800),
        frameRate: 12,
        frameCount: 2,
        backgroundColor: null,
        dictionary: const {1: shapeA, 2: shapeB},
        mainTimeline: Timeline(frames, const {}),
      );
      final stage = SwfStage(movie, host: TestHost());
      stage.advanceFrame(); // frame2: 差し替え
      final node = stage.buildRenderTree().single;
      expect(node.character.id, 2, reason: 'キャラは差し替わる');
      expect(node.matrix.translateX, 2000, reason: '行列は引き継がれるはず');
      expect(node.matrix.translateY, 3000);
      // ループで戻っても同様（リコンサイル経路の回帰確認）
      stage.advanceFrame(); // frame1へループ
      stage.advanceFrame(); // frame2
      final node2 = stage.buildRenderTree().single;
      expect(node2.matrix.translateX, 2000);
    });

    test('gotoFrame 後方: 表示リストが巻き戻る', () {
      final stage = SwfStage(buildPlacementMovie(), host: TestHost());
      stage.advanceFrame(); // frame2
      stage.root.gotoFrame(1);
      final nodes = stage.buildRenderTree();
      expect(nodes.single.matrix.translateX, 100);
    });
  });
}
