import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

void main() {
  group('DefaultSwfHost', () {
    test('logコールバックを注入するとtrace/getUrlがそこへ出力される', () {
      final lines = <String>[];
      final host = DefaultSwfHost(log: lines.add);
      host.trace('hello');
      host.getUrl('http://example.com', '_self');
      expect(lines, hasLength(2));
      expect(lines[0], contains('hello'));
      expect(lines[1], contains('http://example.com'));
    });

    test('log未指定ではtrace/getUrlは何も出力せず例外も投げない(no-op)', () {
      final host = DefaultSwfHost();
      expect(() {
        host.trace('silent');
        host.getUrl('http://example.com', '_self');
      }, returnsNormally);
    });
  });
}
