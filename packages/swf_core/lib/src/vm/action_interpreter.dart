import 'dart:math' as math;
import 'dart:typed_data';

import '../io/sjis.dart';
import '../model/basic_types.dart';
import '../model/character.dart';
import '../player/movie_clip.dart';
import '../player/swf_host.dart';
import 'flash_value.dart';

/// Flash 4（SWF4）アクションのスタックマシンインタープリタ。
class ActionInterpreter {
  ActionInterpreter(this.host, {this.maxInstructions = 2000000});

  final SwfHost host;

  /// 無限ループ暴走の打ち切り閾値（1スクリプトあたり）。
  final int maxInstructions;

  static const _twipsPerPx = 20.0;
  static const _divisionByZeroResult = FlashString('#ERROR#');

  /// codeを、targetをカレントターゲットとして実行する。
  void run(Uint8List code, MovieClip target) {
    final stack = <FlashValue>[];
    MovieClip? current = target;
    var pc = 0;
    var executed = 0;

    FlashValue pop() =>
        stack.isEmpty ? FlashValue.emptyString : stack.removeLast();
    void push(FlashValue v) => stack.add(v);
    double popN() => pop().toNumber();
    String popS() => pop().toFlashString();

    while (pc < code.length) {
      if (++executed > maxInstructions) {
        host.trace('script aborted: instruction limit exceeded');
        return;
      }
      final op = code[pc++];
      if (op == 0) return;

      var operandStart = pc;
      var operandLength = 0;
      if (op >= 0x80) {
        operandLength = code[pc] | (code[pc + 1] << 8);
        pc += 2;
        operandStart = pc;
        pc += operandLength;
      }

      switch (op) {
        // --- タイムライン制御 ---
        case 0x04: // NextFrame
          current?.gotoFrame((current.currentFrame) + 1);
          current?.stop();
        case 0x05: // PrevFrame
          current?.gotoFrame((current.currentFrame) - 1);
          current?.stop();
        case 0x06: // Play
          current?.play();
        case 0x07: // Stop
          current?.stop();
        case 0x08: // ToggleQuality
          break;
        case 0x09: // StopSounds
          break;
        case 0x81: // GotoFrame (0-based operand)
          final frame = code[operandStart] | (code[operandStart + 1] << 8);
          current?.gotoFrame(frame + 1);
          current?.stop();
        case 0x8C: // GoToLabel
          final label = _readCString(code, operandStart);
          current?.gotoLabel(label);
          current?.stop();
        case 0x9F: // GotoFrame2
          final flags = operandLength > 0 ? code[operandStart] : 0;
          final play = flags & 0x01 != 0;
          final frameValue = pop();
          final c = current;
          if (c != null) {
            _gotoFrameValue(c, frameValue);
            play ? c.play() : c.stop();
          }
        case 0x9E: // Call: フレームのアクションをサブルーチン実行
          final frameValue = pop();
          final c = current;
          if (c != null) _callFrame(c, frameValue);
        case 0x8A: // WaitForFrame (常にロード済み: スキップしない)
          break;
        case 0x8D: // WaitForFrame2
          pop();

        // --- スタック・変数 ---
        case 0x96: // Push
          var p = operandStart;
          final end = operandStart + operandLength;
          while (p < end) {
            final type = code[p++];
            if (type == 0) {
              final start = p;
              while (p < end && code[p] != 0) {
                p++;
              }
              push(FlashString(
                  decodeSjis(Uint8List.sublistView(code, start, p))));
              p++; // null終端
            } else if (type == 1) {
              final f = ByteData.sublistView(code, p, p + 4)
                  .getFloat32(0, Endian.little);
              push(FlashNumber(f.toDouble()));
              p += 4;
            } else {
              host.trace('unknown push type: $type');
              break;
            }
          }
        case 0x17: // Pop
          pop();
        case 0x1C: // GetVariable
          push(_getVariable(popS(), current, target));
        case 0x1D: // SetVariable
          final value = pop();
          _setVariable(popS(), value, current, target);
        case 0x8B: // SetTarget
          current = _retarget(_readCString(code, operandStart), target);
        case 0x20: // SetTarget2
          current = _retarget(popS(), target);

        // --- 算術・比較（数値） ---
        case 0x0A: // Add
          final a = popN(), b = popN();
          push(FlashNumber(b + a));
        case 0x0B: // Subtract
          final a = popN(), b = popN();
          push(FlashNumber(b - a));
        case 0x0C: // Multiply
          final a = popN(), b = popN();
          push(FlashNumber(b * a));
        case 0x0D: // Divide
          final a = popN(), b = popN();
          push(a == 0 ? _divisionByZeroResult : FlashNumber(b / a));
        case 0x0E: // Equals（数値比較）
          final a = popN(), b = popN();
          push(FlashValue.fromBool(b == a));
        case 0x0F: // Less
          final a = popN(), b = popN();
          push(FlashValue.fromBool(b < a));
        case 0x10: // And
          final a = popN(), b = popN();
          push(FlashValue.fromBool(b != 0 && a != 0));
        case 0x11: // Or
          final a = popN(), b = popN();
          push(FlashValue.fromBool(b != 0 || a != 0));
        case 0x12: // Not
          push(FlashValue.fromBool(popN() == 0));
        case 0x18: // ToInteger
          push(FlashNumber(popN().truncateToDouble()));
        case 0x30: // RandomNumber
          push(FlashNumber(host.random(popN().truncate()).toDouble()));
        case 0x34: // GetTime
          push(FlashNumber(host.timeMs));

        // --- 文字列 ---
        case 0x13: // StringEquals
          final a = popS(), b = popS();
          push(FlashValue.fromBool(b == a));
        case 0x14: // StringLength（SJISバイト長）
          push(FlashNumber(encodeSjis(popS()).length.toDouble()));
        case 0x15: // StringExtract（SJISバイト単位、index 1-based）
          final count = popN().truncate();
          final index = popN().truncate();
          final bytes = encodeSjis(popS());
          final start = (index - 1).clamp(0, bytes.length);
          final end2 = (start + count).clamp(start, bytes.length);
          push(FlashString(decodeSjis(bytes.sublist(start, end2))));
        case 0x21: // StringAdd
          final a = popS(), b = popS();
          push(FlashString(b + a));
        case 0x29: // StringLess
          final a = popS(), b = popS();
          push(FlashValue.fromBool(b.compareTo(a) < 0));
        case 0x31: // MBStringLength（文字数）
          push(FlashNumber(popS().length.toDouble()));
        case 0x35: // MBStringExtract（文字単位、index 1-based）
          final count = popN().truncate();
          final index = popN().truncate();
          final s = popS();
          final start = (index - 1).clamp(0, s.length);
          final end2 = (start + count).clamp(start, s.length);
          push(FlashString(s.substring(start, end2)));
        case 0x32: // CharToAscii
          final s = popS();
          push(FlashNumber(s.isEmpty ? 0 : encodeSjis(s).first.toDouble()));
        case 0x33: // AsciiToChar
          push(FlashString(decodeSjis([popN().truncate() & 0xFF])));

        // --- プロパティ・スプライト ---
        case 0x22: // GetProperty
          final index = popN().truncate();
          final path = popS();
          push(_getProperty(_retarget(path, target) ?? current, index));
        case 0x23: // SetProperty
          final value = pop();
          final index = popN().truncate();
          final path = popS();
          _setProperty(_retarget(path, target) ?? current, index, value);
        case 0x24: // CloneSprite
          final depth = popN().truncate();
          final newName = popS();
          final sourcePath = popS();
          _cloneSprite(_retarget(sourcePath, target), newName, depth);
        case 0x25: // RemoveSprite
          final path = popS();
          final clip = _retarget(path, target);
          clip?.parent?.displayList.remove(clip.placement?.depth);

        // --- 分岐 ---
        case 0x99: // Jump
          pc += _readS16(code, operandStart);
        case 0x9D: // If
          final offset = _readS16(code, operandStart);
          if (pop().isTruthy) pc += offset;

        // --- ホスト ---
        case 0x26: // Trace
          host.trace(popS());
        case 0x83: // GetURL（インライン文字列2つ）
          final url = _readCString(code, operandStart);
          final urlEnd = operandStart + encodeSjis(url).length + 1;
          host.getUrl(url, _readCString(code, urlEnd));
        case 0x9A: // GetURL2
          final targetStr = popS();
          final url = popS();
          host.getUrl(url, targetStr);
        case 0x2D: // FSCommand2 (Flash Lite)
          final argc = popN().truncate();
          if (argc <= 0) {
            push(const FlashNumber(-1));
          } else {
            final command = popS();
            final args = [for (var i = 1; i < argc; i++) pop()];
            push(host.fsCommand2(command, args));
          }

        default:
          host.trace(
              'unimplemented action 0x${op.toRadixString(16)} (skipped)');
      }
    }
  }

  // --- 変数解決 ---

  /// "var" / "/mc1/mc2:var" / "../mc:var" を (クリップ, 変数名) に分解。
  (MovieClip?, String) _splitVariablePath(
      String name, MovieClip? current, MovieClip origin) {
    final colon = name.lastIndexOf(':');
    if (colon < 0) return (current, name);
    final targetPath = name.substring(0, colon);
    final varName = name.substring(colon + 1);
    return (_retarget(targetPath, origin, from: current), varName);
  }

  FlashValue _getVariable(String name, MovieClip? current, MovieClip origin) {
    final (clip, varName) = _splitVariablePath(name, current, origin);
    return clip?.getVariable(varName) ?? FlashValue.emptyString;
  }

  void _setVariable(
      String name, FlashValue value, MovieClip? current, MovieClip origin) {
    final (clip, varName) = _splitVariablePath(name, current, origin);
    clip?.setVariable(varName, value);
  }

  /// スラッシュ構文のターゲットパスを解決する。
  /// 空文字はスクリプト本来のターゲット（SetTarget "" の復帰動作）。
  MovieClip? _retarget(String path, MovieClip origin, {MovieClip? from}) {
    if (path.isEmpty) return origin;
    var clip = path.startsWith('/') ? origin.root : (from ?? origin);
    for (final seg in path.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        clip = clip.parent ?? clip;
      } else {
        final child = clip.childByName(seg);
        if (child == null) return null;
        clip = child;
      }
    }
    return clip;
  }

  // --- タイムライン補助 ---

  void _gotoFrameValue(MovieClip clip, FlashValue frameValue) {
    if (frameValue is FlashString) {
      final s = frameValue.value;
      final n = double.tryParse(s);
      if (n == null) {
        clip.gotoLabel(s);
        return;
      }
      clip.gotoFrame(n.truncate());
      return;
    }
    clip.gotoFrame(frameValue.toNumber().truncate());
  }

  /// ActionCall: 指定フレームのアクションをその場で実行（再生ヘッドは動かさない）。
  void _callFrame(MovieClip clip, FlashValue frameValue) {
    int? frameIndex;
    if (frameValue is FlashString) {
      frameIndex = clip.timeline.labelToFrame[frameValue.value];
      frameIndex ??= (double.tryParse(frameValue.value)?.truncate() ?? 0) - 1;
    } else {
      frameIndex = frameValue.toNumber().truncate() - 1;
    }
    if (frameIndex < 0 || frameIndex >= clip.timeline.frameCount) return;
    for (final actions in clip.timeline.frames[frameIndex].actions) {
      run(actions, clip);
    }
  }

  // --- プロパティ ---

  /// 行列のX軸スケール成分（回転を考慮した大きさ）。
  static double _scaleXOf(SwfMatrix m) =>
      math.sqrt(m.scaleX * m.scaleX + m.rotateSkew0 * m.rotateSkew0);

  static double _scaleYOf(SwfMatrix m) =>
      math.sqrt(m.scaleY * m.scaleY + m.rotateSkew1 * m.rotateSkew1);

  /// 回転角（度）。Flashの_rotationと同じ定義（X軸方向の向き）。
  static double _rotationOf(SwfMatrix m) =>
      math.atan2(m.rotateSkew0, m.scaleX) * 180 / math.pi;

  /// スケールと回転から行列を再構成（平行移動は維持）。
  static SwfMatrix _composeMatrix(
      double sx, double sy, double rotationDeg, int tx, int ty) {
    final r = rotationDeg * math.pi / 180;
    return SwfMatrix(
      scaleX: sx * math.cos(r),
      rotateSkew0: sx * math.sin(r),
      rotateSkew1: -sy * math.sin(r),
      scaleY: sy * math.cos(r),
      translateX: tx,
      translateY: ty,
    );
  }

  /// クリップ内容の外接矩形（twips、自身の行列適用前）。
  SwfRect? _contentBounds(MovieClip clip) {
    int? xMin, xMax, yMin, yMax;
    void merge(SwfRect r, SwfMatrix m) {
      for (final (px, py) in [
        (r.xMin, r.yMin),
        (r.xMax, r.yMin),
        (r.xMin, r.yMax),
        (r.xMax, r.yMax),
      ]) {
        final x = (m.scaleX * px + m.rotateSkew1 * py).round() + m.translateX;
        final y = (m.rotateSkew0 * px + m.scaleY * py).round() + m.translateY;
        xMin = xMin == null ? x : math.min(xMin!, x);
        xMax = xMax == null ? x : math.max(xMax!, x);
        yMin = yMin == null ? y : math.min(yMin!, y);
        yMax = yMax == null ? y : math.max(yMax!, y);
      }
    }

    for (final obj in clip.displayList.values) {
      final c = obj.character;
      final bounds = switch (c) {
        final ShapeCharacter s => s.bounds,
        final EditTextCharacter t => t.bounds,
        final StaticTextCharacter t => t.bounds,
        SpriteCharacter() when obj.clip != null => _contentBounds(obj.clip!),
        _ => null,
      };
      if (bounds != null) merge(bounds, obj.matrix);
    }
    if (xMin == null) return null;
    return SwfRect(xMin!, xMax!, yMin!, yMax!);
  }

  FlashValue _getProperty(MovieClip? clip, int index) {
    if (clip == null) return FlashValue.emptyString;
    final placement = clip.placement;
    final m = placement?.matrix ?? SwfMatrix.identity;
    switch (index) {
      case 0: // _x
        return FlashNumber(m.translateX / _twipsPerPx);
      case 1: // _y
        return FlashNumber(m.translateY / _twipsPerPx);
      case 2: // _xscale
        return FlashNumber(_scaleXOf(m) * 100);
      case 3: // _yscale
        return FlashNumber(_scaleYOf(m) * 100);
      case 4: // _currentframe
        return FlashNumber(clip.currentFrame.toDouble());
      case 5: // _totalframes
        return FlashNumber(clip.totalFrames.toDouble());
      case 6: // _alpha
        final aMult = placement?.cxform.aMult ?? 256;
        return FlashNumber(aMult / 256 * 100);
      case 7: // _visible
        return FlashValue.fromBool(placement?.visible ?? true);
      case 8: // _width
      case 9: // _height
        final bounds = _contentBounds(clip);
        if (bounds == null) return FlashValue.zero;
        // 自身の行列で変換した外接矩形のサイズ（px）
        final corners = [
          (bounds.xMin, bounds.yMin),
          (bounds.xMax, bounds.yMin),
          (bounds.xMin, bounds.yMax),
          (bounds.xMax, bounds.yMax),
        ].map((p) => (
              m.scaleX * p.$1 + m.rotateSkew1 * p.$2,
              m.rotateSkew0 * p.$1 + m.scaleY * p.$2,
            ));
        if (index == 8) {
          final xs = corners.map((c) => c.$1);
          return FlashNumber(
              (xs.reduce(math.max) - xs.reduce(math.min)) / _twipsPerPx);
        }
        final ys = corners.map((c) => c.$2);
        return FlashNumber(
            (ys.reduce(math.max) - ys.reduce(math.min)) / _twipsPerPx);
      case 10: // _rotation
        return FlashNumber(_rotationOf(m));
      case 11: // _target
        return FlashString(clip.targetPath);
      case 12: // _framesloaded
        return FlashNumber(clip.totalFrames.toDouble());
      case 13: // _name
        return FlashString(clip.name);
      case 16: // _highquality
        return FlashValue.one;
      case 19: // _quality
        return const FlashString('HIGH');
      default:
        return FlashValue.zero;
    }
  }

  void _setProperty(MovieClip? clip, int index, FlashValue value) {
    final placement = clip?.placement;
    if (clip == null || placement == null) return;
    final m = placement.matrix;
    // AS変更を記録し、以後タイムラインのMOVE/goto再構築による上書きを
    // 禁止する（Flash実機セマンティクス）。行列とcxformは独立に保護。
    const matrixProps = {0, 1, 2, 3, 10};
    if (matrixProps.contains(index)) {
      placement.matrixTransformedByScript = true;
    } else if (index == 6) {
      placement.cxformTransformedByScript = true;
    }
    switch (index) {
      case 0: // _x
        placement.matrix = SwfMatrix(
          scaleX: m.scaleX,
          scaleY: m.scaleY,
          rotateSkew0: m.rotateSkew0,
          rotateSkew1: m.rotateSkew1,
          translateX: (value.toNumber() * _twipsPerPx).round(),
          translateY: m.translateY,
        );
      case 1: // _y
        placement.matrix = SwfMatrix(
          scaleX: m.scaleX,
          scaleY: m.scaleY,
          rotateSkew0: m.rotateSkew0,
          rotateSkew1: m.rotateSkew1,
          translateX: m.translateX,
          translateY: (value.toNumber() * _twipsPerPx).round(),
        );
      case 2: // _xscale（回転を維持してX軸スケールのみ変更）
        placement.matrix = _composeMatrix(
          value.toNumber() / 100,
          _scaleYOf(m),
          _rotationOf(m),
          m.translateX,
          m.translateY,
        );
      case 3: // _yscale
        placement.matrix = _composeMatrix(
          _scaleXOf(m),
          value.toNumber() / 100,
          _rotationOf(m),
          m.translateX,
          m.translateY,
        );
      case 10: // _rotation（スケールを維持して回転のみ変更）
        placement.matrix = _composeMatrix(
          _scaleXOf(m),
          _scaleYOf(m),
          value.toNumber(),
          m.translateX,
          m.translateY,
        );
      case 6: // _alpha
        final cx = placement.cxform;
        placement.cxform = SwfCxform(
          rMult: cx.rMult,
          gMult: cx.gMult,
          bMult: cx.bMult,
          aMult: (value.toNumber() * 256 / 100).round().clamp(0, 256),
          rAdd: cx.rAdd,
          gAdd: cx.gAdd,
          bAdd: cx.bAdd,
          aAdd: cx.aAdd,
        );
      case 7: // _visible
        placement.visible = value.isTruthy;
      case 13: // _name
        placement.name = value.toFlashString();
        clip.name = value.toFlashString();
      default:
        break;
    }
  }

  // --- スプライト複製 ---

  void _cloneSprite(MovieClip? source, String newName, int depth) {
    final parent = source?.parent;
    final srcPlacement = source?.placement;
    if (source == null || parent == null || srcPlacement == null) return;
    final placed = PlacedObject(
      depth: depth,
      character: srcPlacement.character,
      matrix: srcPlacement.matrix,
      cxform: srcPlacement.cxform,
      name: newName,
    );
    // 行列・cxformとともにAS変更保護状態も複製する
    // （AS変形済みソースのcloneがタイムラインMOVEで戻されないため）
    placed.matrixTransformedByScript = srcPlacement.matrixTransformedByScript;
    placed.cxformTransformedByScript = srcPlacement.cxformTransformedByScript;
    final character = srcPlacement.character;
    if (character is SpriteCharacter) {
      placed.clip = MovieClip(character.timeline, parent.dictionary,
          name: newName, parent: parent, placement: placed);
    }
    parent.displayList[depth] = placed;
  }

  // --- バイト列補助 ---

  static int _readS16(Uint8List code, int pos) {
    final v = code[pos] | (code[pos + 1] << 8);
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  static String _readCString(Uint8List code, int pos) {
    var end = pos;
    while (end < code.length && code[end] != 0) {
      end++;
    }
    return decodeSjis(Uint8List.sublistView(code, pos, end));
  }
}
