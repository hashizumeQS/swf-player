import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

void main() {
  group('FlashValue Flash4セマンティクス', () {
    test('数値解釈不能な文字列は 0 になる（NaNではない）', () {
      expect(const FlashString('abc').toNumber(), 0);
      expect(const FlashString('').toNumber(), 0);
    });

    test('数値文字列は数値になる', () {
      expect(const FlashString('12').toNumber(), 12);
      expect(const FlashString('-3.5').toNumber(), -3.5);
      expect(const FlashString('  7 ').toNumber(), 7);
    });

    test('整数値の文字列化は小数点なし', () {
      expect(const FlashNumber(12.0).toFlashString(), '12');
      expect(const FlashNumber(-3.0).toFlashString(), '-3');
    });

    test('非整数値の文字列化は小数点あり', () {
      expect(const FlashNumber(3.5).toFlashString(), '3.5');
    });

    test('真偽値は1/0', () {
      expect(FlashValue.fromBool(true).toNumber(), 1);
      expect(FlashValue.fromBool(false).toNumber(), 0);
    });

    test('truthy判定: 非ゼロ数値のみ真', () {
      expect(const FlashNumber(1).isTruthy, isTrue);
      expect(const FlashNumber(0).isTruthy, isFalse);
      expect(const FlashString('1').isTruthy, isTrue);
      expect(const FlashString('abc').isTruthy, isFalse, reason: '数値化で0');
    });
  });
}
