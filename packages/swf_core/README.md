# swf_core

A pure-Dart SWF4 / Flash Lite 1.x parser, player model, and ActionScript
interpreter. No Flutter dependency — runs on the Dart VM, AOT, and Web.

`swf_core` is the runtime core behind the
[`swf_player`](https://pub.dev/packages/swf_player) Flutter widget package.
Use `swf_core` directly when you need headless parsing/execution (CLI tools,
tests, servers); use `swf_player` when you want to render and interact with
SWF content in a Flutter app.

## Scope

Targets the SWF4 feature set as used by **Flash Lite 1.x** content
(Japanese feature-phone era games and animations):

- **Parser**: shapes (with gradients and bitmap fills), lossless & JPEG
  bitmaps, static/dynamic texts, buttons, sprites, frame labels; CWS (zlib)
  decompression; Shift_JIS string decoding.
- **ActionScript VM**: SWF4-era bytecode with Flash Lite 1.x semantics —
  variables, arithmetic/string ops, `tellTarget`, `gotoAndPlay`,
  `GetURL` / `FSCommand2` via host hooks.
- **Player model** (`SwfStage`): frame advancing with correct VM/timeline
  priority semantics, key dispatch (`SwfKeyCode` — Flash Lite
  `CondKeyPress` codes), tap dispatch, button focus navigation, and
  root-timeline label notifications.

Out of scope: ActionScript 2/3, video, sound, and SWF5+ tags.

## Usage

```dart
import 'dart:io';
import 'package:swf_core/swf_core.dart';

void main() {
  final bytes = File('movie.swf').readAsBytesSync();
  final movie = SwfParser.parse(bytes);
  print('${movie.frameCount} frames @ ${movie.frameRate} fps');

  final stage = SwfStage(movie);
  stage.onRootLabel = (label) => print('reached label: $label');
  stage.advanceFrame();
  stage.dispatchKey(SwfKeyCode.enter);
}
```

Host integration (traces, `GetURL`, `FSCommand2`, time, randomness) is
injected via `SwfHost`; `DefaultSwfHost` provides sensible defaults and an
optional `log` callback.

A structure-dump CLI is included: `dart run swf_core:swfdump movie.swf`.

## License

MIT
