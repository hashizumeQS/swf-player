import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

import 'package:swf_core/testing.dart';
import 'helpers.dart';

MovieClip makeClip({int frames = 1}) {
  final timeline = Timeline(List.generate(frames, (_) => SwfFrame()), const {});
  return MovieClip(timeline, const {}, name: '_root');
}

void main() {
  late TestHost host;
  late ActionInterpreter vm;
  late MovieClip clip;

  setUp(() {
    host = TestHost();
    vm = ActionInterpreter(host);
    clip = makeClip();
  });

  group('変数', () {
    test('SetVariable/GetVariable', () {
      vm.run(
          Asm()
              .pushString('score')
              .pushFloat(42)
              .op(0x1D) // SetVariable
              .build(),
          clip);
      expect(clip.variables['score']!.toNumber(), 42);

      vm.run(
          Asm()
              .pushString('out')
              .pushString('score')
              .op(0x1C) // GetVariable
              .op(0x1D)
              .build(),
          clip);
      expect(clip.variables['out']!.toNumber(), 42);
    });

    test('未定義変数は空文字', () {
      vm.run(
          Asm()
              .pushString('out')
              .pushString('nothing')
              .op(0x1C)
              .op(0x1D)
              .build(),
          clip);
      expect(clip.variables['out']!.toFlashString(), '');
    });
  });

  group('Flash4特性: 比較・算術', () {
    test('Equalsは数値比較: "012" == "12" は真', () {
      vm.run(
          Asm()
              .pushString('r')
              .pushString('012')
              .pushString('12')
              .op(0x0E) // Equals
              .op(0x1D)
              .build(),
          clip);
      expect(clip.variables['r']!.toNumber(), 1);
    });

    test('Equalsは数値比較: 非数文字列同士は0==0で真', () {
      vm.run(
          Asm()
              .pushString('r')
              .pushString('abc')
              .pushString('xyz')
              .op(0x0E)
              .op(0x1D)
              .build(),
          clip);
      expect(clip.variables['r']!.toNumber(), 1);
    });

    test('StringEqualsは文字列比較: "abc" != "xyz"', () {
      vm.run(
          Asm()
              .pushString('r')
              .pushString('abc')
              .pushString('xyz')
              .op(0x13) // StringEquals
              .op(0x1D)
              .build(),
          clip);
      expect(clip.variables['r']!.toNumber(), 0);
    });

    test('Subtract/Divide のオペランド順（b op a）', () {
      vm.run(
          Asm()
              .pushString('r')
              .pushFloat(10)
              .pushFloat(3)
              .op(0x0B) // Subtract → 10-3
              .op(0x1D)
              .build(),
          clip);
      expect(clip.variables['r']!.toNumber(), 7);
    });

    test('ゼロ除算は#ERROR#', () {
      vm.run(
          Asm()
              .pushString('r')
              .pushFloat(5)
              .pushFloat(0)
              .op(0x0D) // Divide
              .op(0x1D)
              .build(),
          clip);
      expect(clip.variables['r']!.toFlashString(), '#ERROR#');
    });

    test('StringAddは連結', () {
      vm.run(
          Asm()
              .pushString('r')
              .pushString('スコア:')
              .pushString('100')
              .op(0x21) // StringAdd
              .op(0x1D)
              .build(),
          clip);
      expect(clip.variables['r']!.toFlashString(), 'スコア:100');
    });
  });

  group('Flash4特性: 文字列（SJISバイト単位）', () {
    test('StringLengthはSJISバイト長: "あa" → 3', () {
      vm.run(
          Asm()
              .pushString('r')
              .pushString('あa')
              .op(0x14) // StringLength
              .op(0x1D)
              .build(),
          clip);
      expect(clip.variables['r']!.toNumber(), 3);
    });

    test('MBStringLengthは文字数: "あa" → 2', () {
      vm.run(Asm().pushString('r').pushString('あa').op(0x31).op(0x1D).build(),
          clip);
      expect(clip.variables['r']!.toNumber(), 2);
    });

    test('MBStringExtractは1-based文字単位', () {
      vm.run(
          Asm()
              .pushString('r')
              .pushString('あいうえお')
              .pushFloat(2) // index
              .pushFloat(3) // count
              .op(0x35)
              .op(0x1D)
              .build(),
          clip);
      expect(clip.variables['r']!.toFlashString(), 'いうえ');
    });
  });

  group('分岐・ループ', () {
    test('If: 真なら分岐、1+2+...+5=15', () {
      // i=0; sum=0; do { i++; sum+=i } while(i<5)
      final a = Asm()
          .pushString('i')
          .pushFloat(0)
          .op(0x1D)
          .pushString('sum')
          .pushFloat(0)
          .op(0x1D);
      final loopStart = a.length;
      a
          .pushString('i')
          .pushString('i')
          .op(0x1C)
          .pushFloat(1)
          .op(0x0A) // i+1
          .op(0x1D) // i=i+1
          .pushString('sum')
          .pushString('sum')
          .op(0x1C)
          .pushString('i')
          .op(0x1C)
          .op(0x0A)
          .op(0x1D) // sum=sum+i
          .pushString('i')
          .op(0x1C)
          .pushFloat(5)
          .op(0x0F); // i<5
      // iff命令は5バイト（op+len+offset）: 実行後のpc基準で先頭へ戻る
      a.iff(loopStart - (a.length + 5));
      final code = a.build();
      vm.run(code, clip);
      expect(clip.variables['i']!.toNumber(), 5);
      expect(clip.variables['sum']!.toNumber(), 15);
    });

    test('命令数上限で暴走スクリプトを打ち切る', () {
      final looping = ActionInterpreter(host, maxInstructions: 1000);
      looping.run(Asm().jump(-5).build(), clip); // 無限ループ
      expect(host.traces.last, contains('instruction limit'));
    });
  });

  group('ターゲット・プロパティ', () {
    late MovieClip rootClip;

    setUp(() {
      // root > sprite "mc"（depth1に配置）
      const spriteChar = SpriteCharacter(10, Timeline([], {}));
      final frames = [
        SwfFrame(ops: [
          const PlaceOp(depth: 1, move: false, characterId: 10, name: 'mc'),
        ]),
      ];
      final movie = SwfMovie(
        version: 4,
        stageRect: const SwfRect(0, 4800, 0, 4800),
        frameRate: 12,
        frameCount: 1,
        backgroundColor: null,
        dictionary: const {10: spriteChar},
        mainTimeline: Timeline(frames, const {}),
      );
      rootClip = SwfStage(movie, host: host).root;
    });

    test('スラッシュ構文で子クリップの変数を読み書き', () {
      vm.run(
          Asm().pushString('/mc:hp').pushFloat(3).op(0x1D).build(), rootClip);
      expect(rootClip.childByName('mc')!.variables['hp']!.toNumber(), 3);

      vm.run(
          Asm()
              .pushString('out')
              .pushString('/mc:hp')
              .op(0x1C)
              .op(0x1D)
              .build(),
          rootClip);
      expect(rootClip.variables['out']!.toNumber(), 3);
    });

    test('SetTargetで以降の変数操作が対象クリップに向く', () {
      vm.run(
          Asm()
              .setTarget('/mc')
              .pushString('v')
              .pushFloat(9)
              .op(0x1D)
              .setTarget('')
              .pushString('w')
              .pushFloat(1)
              .op(0x1D)
              .build(),
          rootClip);
      expect(rootClip.childByName('mc')!.variables['v']!.toNumber(), 9);
      expect(rootClip.variables['w']!.toNumber(), 1);
    });

    test('SetProperty/GetProperty: _x (px単位)', () {
      vm.run(
          Asm()
              .pushString('/mc')
              .pushFloat(0) // _x
              .pushFloat(120)
              .op(0x23) // SetProperty
              .build(),
          rootClip);
      final placed = rootClip.displayList[1]!;
      expect(placed.matrix.translateX, 2400); // 120px = 2400twips

      vm.run(
          Asm()
              .pushString('r')
              .pushString('/mc')
              .pushFloat(0)
              .op(0x22) // GetProperty
              .op(0x1D)
              .build(),
          rootClip);
      expect(rootClip.variables['r']!.toNumber(), 120);
    });
  });

  group('タイムライン制御', () {
    test('GotoFrameは移動して停止', () {
      final c = makeClip(frames: 10);
      vm.run(Asm().gotoFrame(4).build(), c); // 0-based 4 → frame5
      expect(c.currentFrame, 5);
      expect(c.isPlaying, isFalse);
    });

    test('GotoFrame+Playで再生継続', () {
      final c = makeClip(frames: 10);
      vm.run(Asm().gotoFrame(4).op(0x06).build(), c);
      expect(c.isPlaying, isTrue);
    });
  });

  group('ホスト連携', () {
    test('Traceはホストへ', () {
      vm.run(Asm().pushString('hello').op(0x26).build(), clip);
      expect(host.traces, contains('hello'));
    });

    test('RandomNumberはホストの乱数', () {
      host.nextRandom = 7;
      vm.run(
          Asm().pushString('r').pushFloat(10).op(0x30).op(0x1D).build(), clip);
      expect(host.lastRandomMax, 10);
      expect(clip.variables['r']!.toNumber(), 7);
    });

    test('FSCommand2: GetDateDayが実値を返す', () {
      vm.run(
          Asm()
              .pushString('d')
              .pushString('GetDateDay')
              .pushFloat(1) // argc
              .op(0x2D)
              .op(0x1D)
              .build(),
          clip);
      expect(clip.variables['d']!.toNumber(), 15); // TestHostの固定日
    });

    test('GetURL2はホストへスタブ送信', () {
      vm.run(
          Asm()
              .pushString('http://example.com/entry.cgi')
              .pushString('_blank')
              .getUrl2()
              .build(),
          clip);
      expect(host.urls.single.$1, 'http://example.com/entry.cgi');
    });
  });
}
