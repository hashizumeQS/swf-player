import 'dart:typed_data';

import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Flash実機セマンティクス: ActionScriptでプロパティを変更した
/// 表示オブジェクトは、以後タイムラインのMOVEタグ・後方goto再構築で
/// 行列・cxformを上書きされない（Ruffleのtransformed_by_scriptと同等）。
///
/// 実例: あるタイトルの黒帯演出。ASがオブジェクトを変形して帯を作るが、
/// ループ中のGoToLabelでタイムライン座標に戻されて1tickで帯が消えていた。

/// Push（文字列）
List<int> _pushStr(String s) {
  final b = encodeSjis(s);
  return [0x96, b.length + 2, 0x00, 0x00, ...b, 0x00];
}

/// SetProperty: target.prop = value
Uint8List setPropBytecode(String target, int prop, String value) =>
    Uint8List.fromList([
      ..._pushStr(target),
      ..._pushStr('$prop'),
      ..._pushStr(value),
      0x23,
      0x00,
    ]);

/// CloneSprite: duplicateMovieClip(source, newName, depth)
Uint8List cloneBytecode(String source, String newName, int depth) =>
    Uint8List.fromList([
      ..._pushStr(source),
      ..._pushStr(newName),
      ..._pushStr('$depth'),
      0x24,
      0x00,
    ]);

/// GotoFrame(1-basedフレーム) + Play
Uint8List gotoAndPlayBytecode(int frame) => Uint8List.fromList([
      0x81,
      0x02,
      0x00,
      (frame - 1) & 0xFF,
      ((frame - 1) >> 8) & 0xFF,
      0x06,
      0x00,
    ]);

const _propX = 0;
const _propAlpha = 6;

SwfMovie _movie(List<SwfFrame> frames) => SwfMovie(
      version: 4,
      stageRect: const SwfRect(0, 4800, 0, 4800),
      frameRate: 12,
      frameCount: frames.length,
      backgroundColor: null,
      dictionary: {
        10: SpriteCharacter(10, Timeline([SwfFrame()], const {})),
        11: SpriteCharacter(11, Timeline([SwfFrame()], const {})),
      },
      mainTimeline: Timeline(frames, const {}),
    );

const _placeAt100 = PlaceOp(
  depth: 1,
  move: false,
  characterId: 10,
  name: 'mc',
  matrix: SwfMatrix(
    scaleX: 1,
    scaleY: 1,
    rotateSkew0: 0,
    rotateSkew1: 0,
    translateX: 2000, // 100px
    translateY: 0,
  ),
);

int _mcX(SwfStage stage) =>
    stage.root.childByName('mc')!.placement!.matrix.translateX;

void main() {
  group('script-transformed オブジェクトとタイムラインの優先関係', () {
    test('後方goto再構築でAS設定の_xが維持される（mselループ相当）', () {
      // f1: 配置(x=100) + AS: mc._x=30 / f2: 空 / f3: goto f2 + Play
      final stage = SwfStage(
        _movie([
          SwfFrame(
            ops: [_placeAt100],
            actions: [setPropBytecode('mc', _propX, '30')],
          ),
          SwfFrame(),
          SwfFrame(actions: [gotoAndPlayBytecode(2)]),
        ]),
        host: TestHost(),
      );
      expect(_mcX(stage), 600, reason: 'ASで30pxへ移動済み');
      for (var i = 0; i < 6; i++) {
        stage.advanceFrame(); // f2↔f3ループを数周
        expect(_mcX(stage), 600, reason: '後方gotoでタイムライン座標(100px)に戻ってはいけない');
      }
    });

    test('MOVEタグはAS変更済みオブジェクトの行列を上書きしない', () {
      const moveTo200 = PlaceOp(
        depth: 1,
        move: true,
        matrix: SwfMatrix(
          scaleX: 1,
          scaleY: 1,
          rotateSkew0: 0,
          rotateSkew1: 0,
          translateX: 4000, // 200px
          translateY: 0,
        ),
      );
      final stage = SwfStage(
        _movie([
          SwfFrame(
            ops: [_placeAt100],
            actions: [setPropBytecode('mc', _propX, '30')],
          ),
          SwfFrame(ops: [moveTo200]),
        ]),
        host: TestHost(),
      );
      stage.advanceFrame(); // f2: MOVE
      expect(_mcX(stage), 600, reason: 'AS変更済みなのでMOVEは無視される');
    });

    test('AS未変更ならMOVEタグは従来どおり適用される', () {
      const moveTo200 = PlaceOp(
        depth: 1,
        move: true,
        matrix: SwfMatrix(
          scaleX: 1,
          scaleY: 1,
          rotateSkew0: 0,
          rotateSkew1: 0,
          translateX: 4000,
          translateY: 0,
        ),
      );
      final stage = SwfStage(
        _movie([
          SwfFrame(ops: [_placeAt100]),
          SwfFrame(ops: [moveTo200]),
        ]),
        host: TestHost(),
      );
      stage.advanceFrame();
      expect(_mcX(stage), 4000, reason: 'script未介入ならタイムラインが有効');
    });

    test('_x変更後もタイムラインのcxformは適用される（行列とcxformは独立）', () {
      const moveMatrixAndAlpha = PlaceOp(
        depth: 1,
        move: true,
        matrix: SwfMatrix(
          scaleX: 1,
          scaleY: 1,
          rotateSkew0: 0,
          rotateSkew1: 0,
          translateX: 4000,
          translateY: 0,
        ),
        cxform: SwfCxform(aMult: 128),
      );
      final stage = SwfStage(
        _movie([
          SwfFrame(
            ops: [_placeAt100],
            actions: [setPropBytecode('mc', _propX, '30')],
          ),
          SwfFrame(ops: [moveMatrixAndAlpha]),
        ]),
        host: TestHost(),
      );
      stage.advanceFrame();
      final placement = stage.root.childByName('mc')!.placement!;
      expect(placement.matrix.translateX, 600, reason: '_x変更済みなので行列は維持');
      expect(placement.cxform.aMult, 128, reason: 'cxformはAS未変更なのでタイムラインが有効');
    });

    test('_alpha変更後もタイムラインの行列は適用される（行列とcxformは独立）', () {
      const moveMatrixAndAlpha = PlaceOp(
        depth: 1,
        move: true,
        matrix: SwfMatrix(
          scaleX: 1,
          scaleY: 1,
          rotateSkew0: 0,
          rotateSkew1: 0,
          translateX: 4000,
          translateY: 0,
        ),
        cxform: SwfCxform(aMult: 64),
      );
      final stage = SwfStage(
        _movie([
          SwfFrame(
            ops: [_placeAt100],
            actions: [setPropBytecode('mc', _propAlpha, '50')],
          ),
          SwfFrame(ops: [moveMatrixAndAlpha]),
        ]),
        host: TestHost(),
      );
      stage.advanceFrame();
      final placement = stage.root.childByName('mc')!.placement!;
      expect(placement.matrix.translateX, 4000, reason: '行列はAS未変更なのでタイムラインが有効');
      expect(placement.cxform.aMult, 128,
          reason: '_alpha=50(=128/256)変更済みなのでcxformは維持');
    });

    test('remove後に再配置した別ライフタイムへはAS変形を引き継がない', () {
      // f1: 配置 / f2: remove / f3: 再配置+AS移動 / f4: goto f1
      // f3のインスタンスとf1のインスタンスは別物なので、
      // 後方gotoではタイムライン座標(100px)の新規インスタンスになる。
      final stage = SwfStage(
        _movie([
          SwfFrame(ops: [_placeAt100]),
          SwfFrame(ops: [const RemoveOp(1)]),
          SwfFrame(
            ops: [_placeAt100],
            actions: [setPropBytecode('mc', _propX, '30')],
          ),
          SwfFrame(actions: [gotoAndPlayBytecode(1)]),
        ]),
        host: TestHost(),
      );
      for (var i = 0; i < 3; i++) {
        stage.advanceFrame(); // f2, f3, f4(goto f1)
      }
      expect(stage.root.currentFrame, 1);
      expect(_mcX(stage), 2000, reason: '別ライフタイムなのでAS変形(30px)を引き継がず配置座標に戻る');
    });

    test('キャラクタ差し替えを挟む後方gotoでAS変形を引き継がない', () {
      // f1: char10配置 / f2: char11へ差し替え /
      // f3: char10へ差し替え直し → AS移動 / f4: goto f1
      // f3で差し替え後のインスタンスへのAS変形は、f1の別ライフタイムに
      // 引き継がれてはいけない。
      final stage = SwfStage(
        _movie([
          SwfFrame(ops: [_placeAt100]),
          SwfFrame(ops: [
            const PlaceOp(depth: 1, move: true, characterId: 11),
          ]),
          SwfFrame(
            ops: [
              const PlaceOp(depth: 1, move: true, characterId: 10),
            ],
            actions: [setPropBytecode('mc', _propX, '30')],
          ),
          SwfFrame(actions: [gotoAndPlayBytecode(1)]),
        ]),
        host: TestHost(),
      );
      for (var i = 0; i < 3; i++) {
        stage.advanceFrame();
      }
      expect(stage.root.currentFrame, 1);
      expect(_mcX(stage), 2000, reason: 'f1時点のライフタイムとは別物なので配置座標に戻る');
    });

    test('AS変形済みソースのcloneはタイムラインMOVEに上書きされない', () {
      // f1: 配置 → AS移動 → clone(d2) / f2: d2へのMOVEタグ
      // cloneはAS変形後の行列を複製して生まれるので、保護状態も引き継ぐ。
      const moveTo200At2 = PlaceOp(
        depth: 2,
        move: true,
        matrix: SwfMatrix(
          scaleX: 1,
          scaleY: 1,
          rotateSkew0: 0,
          rotateSkew1: 0,
          translateX: 4000,
          translateY: 0,
        ),
      );
      final stage = SwfStage(
        _movie([
          SwfFrame(
            ops: [_placeAt100],
            actions: [
              setPropBytecode('mc', _propX, '30'),
              cloneBytecode('mc', 'mc2', 2),
            ],
          ),
          SwfFrame(ops: [moveTo200At2]),
        ]),
        host: TestHost(),
      );
      final clone = stage.root.childByName('mc2')!.placement!;
      expect(clone.matrix.translateX, 600, reason: 'cloneはAS変形後の座標');
      stage.advanceFrame(); // f2: MOVE
      expect(clone.matrix.translateX, 600, reason: 'ソースのAS変形保護を引き継ぎMOVEは無視される');
    });

    test('後方goto再構築でAS設定の_alphaが維持される', () {
      final stage = SwfStage(
        _movie([
          SwfFrame(
            ops: [_placeAt100],
            actions: [setPropBytecode('mc', _propAlpha, '50')],
          ),
          SwfFrame(),
          SwfFrame(actions: [gotoAndPlayBytecode(2)]),
        ]),
        host: TestHost(),
      );
      for (var i = 0; i < 6; i++) {
        stage.advanceFrame();
      }
      final aMult = stage.root.childByName('mc')!.placement!.cxform.aMult;
      expect(aMult, 128, reason: '_alpha=50(=128/256)が維持されるはず');
    });
  });
}
