import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

import 'package:swf_core/testing.dart';

void main() {
  group('SwfBuilder ヘッダ・基本タグ', () {
    test('version/幅高さ/フレームレートがパース結果に反映される', () {
      final builder = SwfBuilder(
        version: 4,
        widthPx: 100,
        heightPx: 50,
        frameRate: 15,
      );
      builder.showFrame();
      final movie = SwfParser.parse(builder.build());

      expect(movie.version, 4);
      expect(movie.stageRect.widthTwips, 2000);
      expect(movie.stageRect.heightTwips, 1000);
      expect(movie.frameRate, closeTo(15.0, 1e-9));
      expect(movie.frameCount, 1);
      expect(movie.mainTimeline.frames, hasLength(1));
    });

    test('setBackgroundColorが反映される', () {
      final builder = SwfBuilder()
        ..setBackgroundColor(10, 20, 30)
        ..showFrame();
      final movie = SwfParser.parse(builder.build());

      expect(movie.backgroundColor, isNotNull);
      expect(movie.backgroundColor!.r, 10);
      expect(movie.backgroundColor!.g, 20);
      expect(movie.backgroundColor!.b, 30);
    });
  });

  group('SwfBuilder defineShapeRect', () {
    test('矩形シェイプが辞書に入りShapeCharacterになる', () {
      final builder = SwfBuilder()
        ..defineShapeRect(1, widthPx: 80, heightPx: 40, fillRgb: 0xFF0000)
        ..showFrame();
      final movie = SwfParser.parse(builder.build());

      final character = movie.dictionary[1];
      expect(character, isA<ShapeCharacter>());
      final shape = character as ShapeCharacter;
      expect(shape.shapeVersion, 1);
      expect(shape.bounds.widthTwips, 1600);
      expect(shape.bounds.heightTwips, 800);
      expect(shape.shape.fillStyles, hasLength(1));
      final fill = shape.shape.fillStyles.single as SolidFill;
      expect(fill.color.r, 0xFF);
      expect(fill.color.g, 0x00);
      expect(fill.color.b, 0x00);
      // 4本の直線エッジ + スタイル変更レコード
      expect(
        shape.shape.records.whereType<StraightEdgeRecord>(),
        hasLength(4),
      );
    });
  });

  group('SwfBuilder ロングフォームタグ', () {
    test('タグ本体が62バイト超でもパースできる（DoActionで検証）', () {
      var asm = Asm();
      for (var i = 0; i < 20; i++) {
        asm = asm.pushString('variable$i').pushFloat(i.toDouble()).op(0x1D);
      }
      final bytecode = asm.build();
      expect(bytecode.length, greaterThan(62)); // ロングフォーム対象であることの前提確認

      final builder = SwfBuilder()
        ..doAction(bytecode)
        ..showFrame();
      final movie = SwfParser.parse(builder.build());

      expect(movie.mainTimeline.frames.single.actions.single, bytecode);
    });
  });

  group('SwfBuilder placeObject2/removeObject2', () {
    test('placeObject2+showFrameでフレームに配置が現れる', () {
      final builder = SwfBuilder()
        ..defineShapeRect(1, widthPx: 10, heightPx: 10)
        ..placeObject2(
          depth: 1,
          characterId: 1,
          translateXPx: 5,
          translateYPx: 7,
          name: 'shape1',
        )
        ..showFrame();
      final movie = SwfParser.parse(builder.build());

      expect(movie.mainTimeline.frames, hasLength(1));
      final ops = movie.mainTimeline.frames.single.ops;
      expect(ops, hasLength(1));
      final place = ops.single as PlaceOp;
      expect(place.depth, 1);
      expect(place.characterId, 1);
      expect(place.name, 'shape1');
      expect(place.matrix, isNotNull);
      expect(place.matrix!.translateX, 100); // 5px = 100twips
      expect(place.matrix!.translateY, 140); // 7px = 140twips
    });

    test('removeObject2でRemoveOpが現れる', () {
      final builder = SwfBuilder()
        ..defineShapeRect(1, widthPx: 10, heightPx: 10)
        ..placeObject2(depth: 1, characterId: 1)
        ..showFrame()
        ..removeObject2(depth: 1)
        ..showFrame();
      final movie = SwfParser.parse(builder.build());

      expect(movie.mainTimeline.frames, hasLength(2));
      final removeOps = movie.mainTimeline.frames[1].ops.whereType<RemoveOp>();
      expect(removeOps, hasLength(1));
      expect(removeOps.single.depth, 1);
    });
  });

  group('SwfBuilder frameLabel/doAction', () {
    test('frameLabel+doAction(gotoラベル)を含むムービーがパースできる', () {
      final gotoActions = Asm().gotoFrame(0).build();
      final builder = SwfBuilder()
        ..frameLabel('start')
        ..doAction(gotoActions)
        ..showFrame();
      final movie = SwfParser.parse(builder.build());

      expect(movie.mainTimeline.labelToFrame['start'], 0);
      final frame = movie.mainTimeline.frames.single;
      expect(frame.label, 'start');
      expect(frame.actions, hasLength(1));
      expect(frame.actions.single, gotoActions);
    });
  });

  group('SwfBuilder defineButton', () {
    test('CondKeyPressコードが読める', () {
      final actions = Asm().pushString('x').pushFloat(1).op(0x1D).build();
      final builder = SwfBuilder()
        ..defineShapeRect(1, widthPx: 20, heightPx: 20)
        ..defineButton(
          2,
          keyPress: SwfKeyCode.enter,
          actions: actions,
          shapeId: 1,
        )
        ..showFrame();
      final movie = SwfParser.parse(builder.build());

      final character = movie.dictionary[2];
      expect(character, isA<ButtonCharacter>());
      final button = character as ButtonCharacter;
      expect(button.condActions, hasLength(1));
      expect(button.condActions.single.keyPress, SwfKeyCode.enter);
      expect(button.condActions.single.actions, actions);
      expect(button.records, hasLength(1));
      expect(button.records.single.characterId, 1);
      expect(button.records.single.stateUp, isTrue);
      expect(button.records.single.stateHitTest, isTrue);
    });
  });

  group('SwfBuilder defineSprite', () {
    test('入れ子のタイムラインが読める', () {
      final builder = SwfBuilder()
        ..defineShapeRect(1, widthPx: 10, heightPx: 10)
        ..defineSprite(5, (sprite) {
          sprite
            ..placeObject2(depth: 1, characterId: 1)
            ..showFrame()
            ..showFrame();
        })
        ..placeObject2(depth: 1, characterId: 5)
        ..showFrame();
      final movie = SwfParser.parse(builder.build());

      final character = movie.dictionary[5];
      expect(character, isA<SpriteCharacter>());
      final sprite = character as SpriteCharacter;
      expect(sprite.timeline.frames, hasLength(2));
      expect(sprite.timeline.frames.first.ops, hasLength(1));
    });
  });

  group('SwfBuilder buildCompressed', () {
    test('CWS版（version 6）もパースできる', () {
      final builder = SwfBuilder(version: 6)
        ..setBackgroundColor(1, 2, 3)
        ..showFrame();
      final movie = SwfParser.parse(builder.buildCompressed());

      expect(movie.backgroundColor, isNotNull);
      expect(movie.backgroundColor!.r, 1);
      expect(movie.frameCount, 1);
    });

    test('version 6未満でのCWS組み立ては拒否する（仕様上不正）', () {
      final builder = SwfBuilder()..showFrame();
      expect(builder.buildCompressed, throwsArgumentError);
    });
  });

  group('SwfBuilder スモーク: SwfStageでのフレーム進行', () {
    test('1フレーム進めてrenderTreeが構築できる', () {
      final builder = SwfBuilder()
        ..defineShapeRect(1, widthPx: 20, heightPx: 20, fillRgb: 0x00FF00)
        ..placeObject2(depth: 1, characterId: 1)
        ..showFrame();
      final movie = SwfParser.parse(builder.build());

      final stage = SwfStage(movie);
      stage.advanceFrame();
      final tree = stage.buildRenderTree();

      expect(tree, hasLength(1));
      expect(tree.single.character, isA<ShapeCharacter>());
      expect(tree.single.depth, 1);
    });
  });
}
