import 'dart:typed_data';

import 'package:swf_core/swf_core.dart';

/// テスト用バイトコードアセンブラ。
class Asm {
  final List<int> _bytes = [];

  /// ActionPush(オペコード0x96)。型タグ0（文字列）+ SJISエンコードした[s]のnull終端
  /// バイト列をオペランドとして書き込む。実行時にスタックへ文字列値をPUSHする。
  Asm pushString(String s) {
    final data = encodeSjis(s);
    _op(0x96, [0, ...data, 0]);
    return this;
  }

  /// ActionPush(オペコード0x96)。型タグ1（浮動小数点数）+ [v]をFLOAT（4byte・
  /// リトルエンディアン単精度）にエンコードしたバイト列をオペランドとして書き込む。
  /// 実行時にスタックへ数値をPUSHする。
  Asm pushFloat(double v) {
    final bd = ByteData(4)..setFloat32(0, v, Endian.little);
    _op(0x96, [1, ...bd.buffer.asUint8List()]);
    return this;
  }

  /// [code]をオペランドなしの1byteアクションレコードとしてそのまま書き込む。
  /// Play(0x06)・Stop(0x07)など、オペコードが0x80未満で可変長オペランドを
  /// 持たないアクション用。
  Asm op(int code) {
    _bytes.add(code);
    return this;
  }

  /// ActionJump(オペコード0x99)。SI16（符号付き16bit・リトルエンディアン）の
  /// [offset]をオペランドとして書き込む。実行時、このアクションレコード終端位置
  /// からのバイトオフセットとして無条件にプログラムカウンタへ加算される。
  Asm jump(int offset) {
    _op(0x99, [offset & 0xFF, (offset >> 8) & 0xFF]);
    return this;
  }

  /// ActionIf(オペコード0x9D)。SI16（符号付き16bit・リトルエンディアン）の
  /// [offset]をオペランドとして書き込む。実行時、スタックからPOPした値が真の場合に
  /// このアクションレコード終端位置から[offset]バイト分岐する。
  Asm iff(int offset) {
    _op(0x9D, [offset & 0xFF, (offset >> 8) & 0xFF]);
    return this;
  }

  /// ActionSetTarget(オペコード0x8B)。以降のアクションのカレントターゲットとする
  /// [path]をSJISのnull終端文字列としてオペランドに書き込む。
  Asm setTarget(String path) {
    _op(0x8B, [...encodeSjis(path), 0]);
    return this;
  }

  /// ActionGotoLabel(オペコード0x8C)。ジャンプ先の[label]をSJISのnull終端文字列
  /// としてオペランドに書き込む。実行時、カレントターゲットを該当ラベルのフレームへ
  /// 移動し停止させる。
  Asm gotoLabel(String label) {
    _op(0x8C, [...encodeSjis(label), 0]);
    return this;
  }

  /// ActionGotoFrame(オペコード0x81)。UI16（リトルエンディアン）の0始まりフレーム
  /// 番号[frame0]をオペランドとして書き込む。実行時、カレントターゲットを該当フレーム
  /// へ移動し停止させる。
  Asm gotoFrame(int frame0) {
    _op(0x81, [frame0 & 0xFF, (frame0 >> 8) & 0xFF]);
    return this;
  }

  /// ActionGetURL2(オペコード0x9A)。UI8 1byteの[flags]をオペランドとして書き込む。
  /// 実行時、呼び出し先URLとターゲットはこのアクション実行前にスタックへ積んでおく
  /// 必要がある（POP順はターゲット→URL、つまりURL→ターゲットの順にPUSHする）。
  Asm getUrl2({int flags = 0}) {
    _op(0x9A, [flags]);
    return this;
  }

  /// 現在のバイト位置（後方ジャンプのオフセット計算用）。
  int get length => _bytes.length;

  void _op(int code, List<int> operand) {
    _bytes.add(code);
    _bytes.add(operand.length & 0xFF);
    _bytes.add((operand.length >> 8) & 0xFF);
    _bytes.addAll(operand);
  }

  /// これまでに積んだActionRecord列の末尾にオペコード0x00（アクション列の終端
  /// マーカー）を1byte追加し、DoActionタグのボディとして使えるバイト列を返す。
  Uint8List build() => Uint8List.fromList([..._bytes, 0]);
}
