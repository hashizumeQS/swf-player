import 'package:swf_core/src/io/sjis.dart';
import 'package:test/test.dart';

void main() {
  group('decodeSjis / encodeSjis 往復テスト', () {
    final cases = <String, List<int>>{
      'あ': [0x82, 0xA0],
      'ＭＳ ゴシック': [
        0x82, 0x6C, //Ｍ
        0x82, 0x72, //Ｓ
        0x20, // (半角スペース)
        0x83, 0x53, //ゴ
        0x83, 0x56, //シ
        0x83, 0x62, //ッ
        0x83, 0x4E, //ク
      ],
      'サクランボジュース': [
        0x83, 0x54, //サ
        0x83, 0x4E, //ク
        0x83, 0x89, //ラ
        0x83, 0x93, //ン
        0x83, 0x7B, //ボ
        0x83, 0x57, //ジ
        0x83, 0x85, //ュ
        0x81, 0x5B, //ー
        0x83, 0x58, //ス
      ],
      'ｱｲｳ': [0xB1, 0xB2, 0xB3],
      'abc123': [0x61, 0x62, 0x63, 0x31, 0x32, 0x33],
      '！＃＊': [0x81, 0x49, 0x81, 0x94, 0x81, 0x96],
    };

    cases.forEach((text, expectedBytes) {
      test('encodeSjis("$text") はCP932バイト列と一致する', () {
        expect(encodeSjis(text), equals(expectedBytes));
      });

      test('decodeSjis(<バイト列>) は"$text"に戻る', () {
        expect(decodeSjis(expectedBytes), equals(text));
      });

      test('"$text" は encode->decode の往復で一致する', () {
        expect(decodeSjis(encodeSjis(text)), equals(text));
      });
    });
  });

  group('未定義バイト・エンコード不能文字の扱い', () {
    test('リードバイトとして未定義の単独バイト (0x80) はU+FFFDに置換される', () {
      expect(decodeSjis([0x80]), equals('�'));
    });

    test('リードバイトとして未定義の単独バイト (0xA0) はU+FFFDに置換される', () {
      expect(decodeSjis([0xA0]), equals('�'));
    });

    test('リードバイトとして未定義の単独バイト (0xFD-0xFF) はU+FFFDに置換される', () {
      expect(decodeSjis([0xFD]), equals('�'));
      expect(decodeSjis([0xFE]), equals('�'));
      expect(decodeSjis([0xFF]), equals('�'));
    });

    test('有効なリードバイトに対応する未定義のトレイルバイトはU+FFFDに置換される', () {
      // 0x81 は有効なリードバイトだが、0x00 は有効なトレイルバイトではない。
      expect(decodeSjis([0x81, 0x00]), equals('�'));
    });

    test('入力末尾で単独になったリードバイトはU+FFFDに置換される', () {
      expect(decodeSjis([0x41, 0x82]), equals('A�'));
    });

    test('未定義バイトの前後にある正常な文字は保持される', () {
      expect(decodeSjis([0x41, 0x80, 0x42]), equals('A�B'));
    });

    test('CP932に存在しない文字 (絵文字) はエンコード時に "?" (0x3F) になる', () {
      expect(encodeSjis('😀'), equals([0x3F]));
    });

    test('エンコード不能文字と通常文字が混在しても正しく変換される', () {
      expect(encodeSjis('A😀B'), equals([0x41, 0x3F, 0x42]));
    });
  });

  group('空文字列・空バイト列', () {
    test('空文字列のエンコードは空バイト列になる', () {
      expect(encodeSjis(''), isEmpty);
    });

    test('空バイト列のデコードは空文字列になる', () {
      expect(decodeSjis(<int>[]), isEmpty);
    });
  });
}
