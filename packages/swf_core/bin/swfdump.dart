import 'dart:io';

import 'package:swf_core/swf_core.dart';

/// SWFの構造をダンプするデバッグCLI。
/// 使い方: `dart run swf_core:swfdump <file.swf>`
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: swfdump <file.swf>');
    exit(64);
  }
  final movie = SwfParser.parse(File(args[0]).readAsBytesSync());
  final px = movie.stageRect.widthTwips ~/ 20;
  final py = movie.stageRect.heightTwips ~/ 20;
  print('version: ${movie.version}');
  print('stage: ${px}x${py}px  fps: ${movie.frameRate}  '
      'frames: ${movie.frameCount}');
  print('background: ${movie.backgroundColor}');
  print('dictionary: ${movie.dictionary.length} characters');

  final byType = <String, int>{};
  for (final c in movie.dictionary.values) {
    final key = c.runtimeType.toString();
    byType[key] = (byType[key] ?? 0) + 1;
  }
  for (final e in byType.entries) {
    print('  ${e.key}: ${e.value}');
  }

  final tl = movie.mainTimeline;
  print('main timeline: ${tl.frames.length} frames, '
      'labels: ${tl.labelToFrame.keys.join(", ")}');
  for (var i = 0; i < tl.frames.length; i++) {
    final f = tl.frames[i];
    if (f.ops.isEmpty && f.actions.isEmpty) continue;
    print('  frame ${i + 1}: ${f.ops.length} ops, '
        '${f.actions.length} actions'
        '${f.label != null ? '  [${f.label}]' : ''}');
  }
}
