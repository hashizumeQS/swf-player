import 'dart:typed_data';

import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Flash Lite 1.xのキーフォーカスナビゲーション。
/// ガラケー実機では↑↓←→キーがボタン間のフォーカス移動で、
/// フォーカスインした（Idle→Over）ボタンのrolloverアクションが発火する。
/// 端まで来たら反対側へラップする。CondKeyPress付きボタンがそのキーを
/// 処理する場合はフォーカス移動しない（キー条件が優先）。
///
/// 実例: あるタイトルのモード選択画面はrolloverボタン数個の
/// 縦カルーセルで、↑↓のフォーカス移動が唯一の切替手段。

const _shapeId = 1;

/// 最小バイトコード: /:order = /:order + suffix（発火順の記録用）
Uint8List appendOrderBytecode(String suffix) {
  List<int> pushStr(String s) {
    final b = encodeSjis(s);
    return [0x96, b.length + 2, 0x00, 0x00, ...b, 0x00];
  }

  return Uint8List.fromList([
    ...pushStr('/:order'),
    ...pushStr('/:order'),
    0x1C, // GetVariable
    ...pushStr(suffix),
    0x21, // StringAdd
    0x1D, // SetVariable
    0x00,
  ]);
}

/// フォーカス実験用ボタン: 10x10pxのhit領域、rolloverで/:selに[id]を設定。
ButtonCharacter navButton(int id, String selValue) {
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
        keyPress: 0,
        overDownToOverUp: false,
        overUpToOverDown: false,
        idleToOverUp: true,
        actions: setVarBytecode('/:sel', selValue),
      ),
    ],
  );
}

PlaceOp placeAt(int depth, int characterId, int xTwips, int yTwips) => PlaceOp(
      depth: depth,
      move: false,
      characterId: characterId,
      matrix: SwfMatrix(
        scaleX: 1,
        scaleY: 1,
        rotateSkew0: 0,
        rotateSkew1: 0,
        translateX: xTwips,
        translateY: yTwips,
      ),
    );

SwfMovie buildMovie({
  Map<int, Character> extraCharacters = const {},
  List<FrameOp> extraOps = const [],
}) {
  // 縦に3ボタン: #20(y=10px) #21(y=30px) #22(y=50px)
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
      20: navButton(20, '1'),
      21: navButton(21, '2'),
      22: navButton(22, '3'),
      ...extraCharacters,
    },
    mainTimeline: Timeline([
      SwfFrame(ops: [
        placeAt(1, 20, 1000, 200),
        placeAt(3, 21, 1000, 600),
        placeAt(5, 22, 1000, 1000),
        ...extraOps,
      ]),
    ], const {}),
  );
}

String? sel(SwfStage stage) => stage.root.getVariable('sel')?.toFlashString();

void main() {
  group('キーフォーカスナビゲーション', () {
    test('フォーカス無しで↓を押すと先頭（最上部）のボタンにrollover発火', () {
      final stage = SwfStage(buildMovie(), host: TestHost());
      expect(stage.dispatchKey(15), isTrue, reason: 'キーは処理されるはず');
      expect(sel(stage), '1');
    });

    test('初期フォーカスは押した方向に依らず読み順（上→下、左→右）の先頭', () {
      for (final key in const [14, 1, 2]) {
        // ↑ ← →
        final stage = SwfStage(buildMovie(), host: TestHost());
        expect(stage.dispatchKey(key), isTrue);
        expect(sel(stage), '1', reason: 'キー$keyの初回押下も読み順先頭にフォーカスする');
      }
    });

    test('同じY座標のボタンはXが小さい方が読み順で先', () {
      final movie = SwfMovie(
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
          20: navButton(20, '1'),
          21: navButton(21, '2'),
        },
        mainTimeline: Timeline([
          SwfFrame(ops: [
            placeAt(1, 21, 3000, 200), // 右
            placeAt(3, 20, 1000, 200), // 左（depthは後）
          ]),
        ], const {}),
      );
      final stage = SwfStage(movie, host: TestHost());
      stage.dispatchKey(15);
      expect(sel(stage), '1', reason: '同じ行では左のボタンが先頭');
    });

    test('↓で下のボタンへ移動し、末尾からはラップして先頭へ', () {
      final stage = SwfStage(buildMovie(), host: TestHost());
      stage.dispatchKey(15); // → #20
      stage.dispatchKey(15); // → #21
      expect(sel(stage), '2');
      stage.dispatchKey(15); // → #22
      expect(sel(stage), '3');
      stage.dispatchKey(15); // ラップ → #20
      expect(sel(stage), '1');
    });

    test('↑は上へ移動し、先頭からはラップして末尾へ', () {
      final stage = SwfStage(buildMovie(), host: TestHost());
      stage.dispatchKey(15); // → #20
      stage.dispatchKey(14); // ラップ → #22
      expect(sel(stage), '3');
      stage.dispatchKey(14); // → #21
      expect(sel(stage), '2');
    });

    test('進行方向の最近傍は横ずれ込みの距離で選ぶ', () {
      // #20(50,50)にフォーカス後、→キー:
      //   #21(52,220)は前方2twipだが横に大きくずれている
      //   #22(150,50)は前方100twipで同じ行 → こちらが近い
      final movie = SwfMovie(
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
          20: navButton(20, '1'),
          21: navButton(21, '2'),
          22: navButton(22, '3'),
        },
        mainTimeline: Timeline([
          SwfFrame(ops: [
            placeAt(1, 20, 1000, 1000),
            placeAt(3, 21, 1040, 4400),
            placeAt(5, 22, 3000, 1000),
          ]),
        ], const {}),
      );
      final stage = SwfStage(movie, host: TestHost());
      stage.dispatchKey(15); // 読み順先頭 → #20
      expect(sel(stage), '1');
      stage.dispatchKey(2); // → 同じ行の#22へ（#21は横ずれが大きい）
      expect(sel(stage), '3');
    });

    test('ラップは同じ列（横ずれ最小）の反対端へ移動する', () {
      // 2列レイアウト: 左列 #20(50,10) #21(50,80)、右列 #22(200,5)
      // 左列の下端#21から↓でラップ → 同じ列の#20へ
      // （前方距離だけで選ぶと、より後方にある右列#22が選ばれてしまう）
      final movie = SwfMovie(
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
          20: navButton(20, '1'),
          21: navButton(21, '2'),
          22: navButton(22, '3'),
        },
        mainTimeline: Timeline([
          SwfFrame(ops: [
            placeAt(1, 20, 1000, 200),
            placeAt(3, 21, 1000, 1600),
            placeAt(5, 22, 4000, 100),
          ]),
        ], const {}),
      );
      final stage = SwfStage(movie, host: TestHost());
      // ↓を繰り返して左列下端#21に到達させる
      var guard = 0;
      while (sel(stage) != '2' && guard++ < 5) {
        stage.dispatchKey(15);
      }
      expect(sel(stage), '2', reason: '前提: 左列下端#21にフォーカス');
      stage.dispatchKey(15); // 下端からラップ → 同じ列の#20
      expect(sel(stage), '1');
    });

    test('ステージ外に退避されたボタンはフォーカス対象にならない', () {
      // よくあるオーサリング: 未使用UIボタンをステージ外に退避しておく
      final stage = SwfStage(
        buildMovie(
          extraCharacters: {23: navButton(23, 'offstage')},
          extraOps: [placeAt(7, 23, 1000, 6000)], // y=300px（ステージ240px外）
        ),
        host: TestHost(),
      );
      stage.dispatchKey(15); // → #20
      stage.dispatchKey(15); // → #21
      stage.dispatchKey(15); // → #22
      stage.dispatchKey(15); // ステージ外#23を飛ばしてラップ → #20
      expect(sel(stage), '1');
    });

    test('同一depthのキャラクタ差し替えでフォーカスは無効になる', () {
      // f1: #20を配置しフォーカス / f2: 同depthを#21に差し替え
      // → 旧フォーカスは無効。Enterで#21のpressが誤発火してはいけない
      final pressButton = ButtonCharacter(
        21,
        navButton(21, '2').records,
        [
          ButtonCondAction(
            keyPress: 0,
            overDownToOverUp: false,
            overUpToOverDown: true,
            idleToOverUp: false,
            actions: setVarBytecode('/:fired', 'yes'),
          ),
        ],
      );
      final movie = SwfMovie(
        version: 4,
        stageRect: const SwfRect(0, 4800, 0, 4800),
        frameRate: 12,
        frameCount: 2,
        backgroundColor: null,
        dictionary: {
          _shapeId: ShapeCharacter(
            _shapeId,
            const SwfRect(0, 200, 0, 200),
            const ShapeWithStyle(fillStyles: [], lineStyles: [], records: []),
            1,
          ),
          20: navButton(20, '1'),
          21: pressButton,
        },
        mainTimeline: Timeline([
          SwfFrame(ops: [placeAt(1, 20, 1000, 200)]),
          SwfFrame(ops: [
            const PlaceOp(depth: 1, move: true, characterId: 21),
          ]),
        ], const {}),
      );
      final stage = SwfStage(movie, host: TestHost());
      stage.dispatchKey(15); // #20にフォーカス
      expect(sel(stage), '1');
      stage.advanceFrame(); // f2: #21へ差し替え
      stage.dispatchKey(13); // Enter
      expect(stage.root.getVariable('fired'), isNull,
          reason: '差し替え後の別ボタンにpressが誤発火してはいけない');
    });

    test('一部だけステージ内のボタンもフォーカス対象になる', () {
      // #23はhit領域(10x10px)の中心がステージ外(y242.5px)だが
      // 上端2.5px分はステージ内 → 対象に含める（AABB交差判定）
      final stage = SwfStage(
        buildMovie(
          extraCharacters: {23: navButton(23, 'partial')},
          extraOps: [placeAt(7, 23, 1000, 4750)],
        ),
        host: TestHost(),
      );
      stage.dispatchKey(15); // → #20
      stage.dispatchKey(15); // → #21
      stage.dispatchKey(15); // → #22
      stage.dispatchKey(15); // → #23（部分的にステージ内）
      expect(sel(stage), 'partial');
    });

    test('CondKeyPressがそのキーを処理する場合はフォーカス移動しない', () {
      final keyButton = ButtonCharacter(
        30,
        const [],
        [
          ButtonCondAction(
            keyPress: 15, // ↓
            overDownToOverUp: false,
            overUpToOverDown: false,
            idleToOverUp: false,
            actions: setVarBytecode('/:pressed', 'yes'),
          ),
        ],
      );
      final stage = SwfStage(
        buildMovie(
          extraCharacters: {30: keyButton},
          extraOps: [placeAt(7, 30, 2000, 2000)],
        ),
        host: TestHost(),
      );
      stage.dispatchKey(15);
      expect(stage.root.getVariable('pressed')?.toFlashString(), 'yes');
      expect(sel(stage), isNull, reason: 'CondKeyPress優先でrollover無し');
    });

    test('Enterはフォーカス中ボタンのpress/releaseアクションを発火する', () {
      final actionButton = ButtonCharacter(
        20,
        navButton(20, '1').records,
        [
          ButtonCondAction(
            keyPress: 0,
            overDownToOverUp: false,
            overUpToOverDown: false,
            idleToOverUp: true,
            actions: setVarBytecode('/:sel', '1'),
          ),
          ButtonCondAction(
            keyPress: 0,
            overDownToOverUp: true,
            overUpToOverDown: false,
            idleToOverUp: false,
            actions: setVarBytecode('/:fired', 'yes'),
          ),
        ],
      );
      final stage = SwfStage(
        buildMovie(extraCharacters: {20: actionButton}),
        host: TestHost(),
      );
      stage.dispatchKey(13);
      expect(stage.root.getVariable('fired'), isNull,
          reason: 'フォーカスが無ければEnterは何もしない');
      stage.dispatchKey(15); // → #20にフォーカス
      stage.dispatchKey(13);
      expect(stage.root.getVariable('fired')?.toFlashString(), 'yes');
    });
  });

  group('Enterのpress/release実行仕様', () {
    // 単発イベントAPI（キー押下/解放を区別しない）のため、Enterは
    // press(OverUpToOverDown)→release(OverDownToOverUp)を同一ディスパッチ
    // 内で連続実行する。格納順に依らずpress→releaseの順を保証する。
    test('condActionsの格納順に依らずpress→releaseの順で発火する', () {
      final button = ButtonCharacter(
        20,
        navButton(20, '1').records,
        [
          ButtonCondAction(
            keyPress: 0,
            overDownToOverUp: true, // release（格納順は先頭）
            overUpToOverDown: false,
            idleToOverUp: false,
            actions: appendOrderBytecode('r'),
          ),
          ButtonCondAction(
            keyPress: 0,
            overDownToOverUp: false,
            overUpToOverDown: true, // press（格納順は後）
            idleToOverUp: false,
            actions: appendOrderBytecode('p'),
          ),
          ButtonCondAction(
            keyPress: 0,
            overDownToOverUp: false,
            overUpToOverDown: false,
            idleToOverUp: true,
            actions: setVarBytecode('/:sel', '1'),
          ),
        ],
      );
      final stage = SwfStage(
        buildMovie(extraCharacters: {20: button}),
        host: TestHost(),
      );
      stage.dispatchKey(15); // #20にフォーカス
      stage.dispatchKey(13);
      expect(stage.root.getVariable('order')?.toFlashString(), 'pr',
          reason: '実機のキー押下→解放と同じ順序で実行する');
    });
  });
}
