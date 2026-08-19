import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// 入力無効キャラクタ（inputDisabledCharacterIds）。
///
/// アプリ側の互換パッチhiddenCharacterIdsは描画のみをスキップするため、
/// 非表示にした旧ランキングUIのボタンがキー・タップ・フォーカスの対象と
/// して残ってしまう。指定キャラクタ（とその子孫）を入力配送からも
/// 除外できるようにする。

const _shapeId = 1;

ButtonCharacter _button(int id, {int keyPress = 0, bool rollover = false}) {
  return ButtonCharacter(
    id,
    [
      const ButtonRecord(
        stateUp: true,
        stateOver: true,
        stateDown: true,
        stateHitTest: true,
        characterId: _shapeId,
        depth: 1,
        matrix: SwfMatrix.identity,
        cxform: SwfCxform.identity,
      ),
    ],
    [
      ButtonCondAction(
        keyPress: keyPress,
        overDownToOverUp: keyPress != 0,
        overUpToOverDown: false,
        idleToOverUp: rollover,
        actions: setVarBytecode('/:fired$id', 'yes'),
      ),
    ],
  );
}

SwfMovie _movie() {
  // スプライト#30の中にCondKeyPress('#'=35)ボタン#20を内包。
  // rolloverボタン#21はルート直置き（フォーカス収集の検証用）。
  final sprite = SpriteCharacter(
    30,
    Timeline([
      SwfFrame(ops: [
        const PlaceOp(depth: 1, move: false, characterId: 20),
      ]),
    ], const {}),
  );
  return SwfMovie(
    version: 4,
    stageRect: const SwfRect(0, 4800, 0, 4800),
    frameRate: 12,
    frameCount: 1,
    backgroundColor: null,
    dictionary: {
      _shapeId: ShapeCharacter(
        _shapeId,
        const SwfRect(0, 200, 0, 200),
        const ShapeWithStyle(fillStyles: [], lineStyles: [], records: []),
        1,
      ),
      20: _button(20, keyPress: 35),
      21: _button(21, rollover: true),
      30: sprite,
    },
    mainTimeline: Timeline([
      SwfFrame(ops: [
        const PlaceOp(depth: 1, move: false, characterId: 30),
        PlaceOp(
          depth: 3,
          move: false,
          characterId: 21,
          matrix: const SwfMatrix(
            scaleX: 1,
            scaleY: 1,
            rotateSkew0: 0,
            rotateSkew1: 0,
            translateX: 2000,
            translateY: 2000,
          ),
        ),
      ]),
    ], const {}),
  );
}

String? _fired(SwfStage stage, int id) =>
    stage.root.getVariable('fired$id')?.toFlashString();

void main() {
  group('inputDisabledCharacterIds', () {
    test('無効化したスプライト内のCondKeyPressは発火しない', () {
      final stage = SwfStage(_movie(), host: TestHost())
        ..inputDisabledCharacterIds = {30};
      expect(stage.dispatchKey(35), isFalse);
      expect(_fired(stage, 20), isNull);
    });

    test('無効化したボタンはタップに反応しない', () {
      final stage = SwfStage(_movie(), host: TestHost())
        ..inputDisabledCharacterIds = {30, 21};
      // #20はスプライト#30内(0,0)-(10,10)px、#21は(100,100)px
      expect(stage.dispatchTap(5, 5), isFalse);
      expect(stage.dispatchTap(105, 105), isFalse);
    });

    test('無効化したボタンはフォーカス対象にならない', () {
      final stage = SwfStage(_movie(), host: TestHost())
        ..inputDisabledCharacterIds = {30, 21};
      // フォーカス可能な#20(スプライト#30内)と#21を両方無効化
      // → 方向キーは未処理になる
      expect(stage.dispatchKey(15), isFalse);
      expect(_fired(stage, 21), isNull);
    });

    test('無効化しなければ従来どおり入力に反応する', () {
      final stage = SwfStage(_movie(), host: TestHost());
      expect(stage.dispatchKey(35), isTrue);
      expect(_fired(stage, 20), 'yes');
      stage.dispatchKey(15); // 読み順先頭#20へフォーカス
      stage.dispatchKey(15); // → #21（rollover発火）
      expect(_fired(stage, 21), 'yes');
    });
  });
}
