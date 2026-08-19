import 'dart:typed_data';

import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Uint8List bytecode(List<int> ops) => Uint8List.fromList([...ops, 0x00]);

List<int> pushString(String s) {
  final b = encodeSjis(s);
  return [0x96, b.length + 2, 0x00, 0x00, ...b, 0x00];
}

void main() {
  late TestHost host;
  late ActionInterpreter vm;
  late MovieClip clip;

  setUp(() {
    host = TestHost();
    vm = ActionInterpreter(host);
    clip = MovieClip(Timeline([SwfFrame()], const {}), const {});
  });

  group('Flash4の大文字小文字非区別', () {
    test('変数: SetRotで代入しSetrotで読める', () {
      // SetRot = '45'
      vm.run(
          bytecode([...pushString('SetRot'), ...pushString('45'), 0x1D]), clip);
      // r = Setrot
      vm.run(
          bytecode([
            ...pushString('r'),
            ...pushString('Setrot'),
            0x1C,
            0x1D,
          ]),
          clip);
      expect(clip.getVariable('r')?.toNumber(), 45,
          reason: 'Flash4変数は大小文字を区別しない');
      expect(clip.getVariable('SETROT')?.toNumber(), 45);
    });

    test('インスタンス名: childByNameが大小無視で解決する', () {
      const sprite = SpriteCharacter(10, Timeline([], {}));
      final frames = [
        SwfFrame(ops: [
          const PlaceOp(depth: 1, move: false, characterId: 10, name: 'Player'),
        ]),
      ];
      final movie = SwfMovie(
        version: 4,
        stageRect: const SwfRect(0, 4800, 0, 4800),
        frameRate: 12,
        frameCount: 1,
        backgroundColor: null,
        dictionary: const {10: sprite},
        mainTimeline: Timeline(frames, const {}),
      );
      final stage = SwfStage(movie, host: host);
      expect(stage.root.childByName('player'), isNotNull);
      expect(stage.root.childByName('PLAYER'), isNotNull);
    });

    test('フレームラベル: gotoLabelが大小無視で解決する', () {
      final movie = SwfMovie(
        version: 4,
        stageRect: const SwfRect(0, 4800, 0, 4800),
        frameRate: 12,
        frameCount: 3,
        backgroundColor: null,
        dictionary: const {},
        mainTimeline: Timeline(
          [SwfFrame(), SwfFrame(label: 'GameOver'), SwfFrame()],
          const {'GameOver': 1},
        ),
      );
      final stage = SwfStage(movie, host: host);
      expect(stage.root.gotoLabel('gameover'), isTrue);
      expect(stage.root.currentFrame, 2);
    });
  });
}
