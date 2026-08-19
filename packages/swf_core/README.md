# swf_core

[![pub package](https://img.shields.io/pub/v/swf_core.svg)](https://pub.dev/packages/swf_core)
[![CI](https://github.com/hashizumeQS/swf-player/actions/workflows/ci.yaml/badge.svg)](https://github.com/hashizumeQS/swf-player/actions/workflows/ci.yaml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/hashizumeQS/swf-player/blob/main/packages/swf_core/LICENSE)

A pure-Dart SWF4 / **Flash Lite 1.x** parser, player model, and ActionScript
interpreter. No Flutter dependency — runs on the Dart VM, AOT, and Web.

`swf_core` is the runtime core behind the
[`swf_player`](https://pub.dev/packages/swf_player) Flutter widget package.
Use `swf_core` directly when you need headless parsing/execution (CLI tools,
tests, servers); use `swf_player` when you want to render and interact with
SWF content in a Flutter app.

*[日本語の説明は下にあります](#日本語)*

## Scope

Targets the SWF4 feature set as used by **Flash Lite 1.x** content
(Japanese feature-phone era games and animations).

### Parser

| Area | Supported |
| --- | --- |
| File formats | `FWS` (uncompressed) and `CWS` (zlib-compressed) |
| Shapes | `DefineShape` 1–3: solid / gradient / bitmap fills, line styles, quadratic Bézier edges |
| Bitmaps | `DefineBitsLossless` 1–2 (zlib), `DefineBitsJPEG3` (JPEG + zlib alpha channel) |
| Text | `DefineEditText` (dynamic text with variable binding), `DefineText` + `DefineFont2` (static glyph text) |
| Buttons | `DefineButton2` with `ButtonCondAction` (`CondKeyPress`, over/press transitions) |
| Timeline | `DefineSprite` (nested timelines), `PlaceObject2` / `RemoveObject2`, `FrameLabel`, `SetBackgroundColor` |
| Strings | Shift_JIS decoding (the encoding used by Japanese feature-phone content) |

### ActionScript VM

SWF4-era bytecode with Flash Lite 1.x semantics: variables,
arithmetic/string/comparison ops, branches, `gotoFrame`/`gotoLabel`,
`play`/`stop`, `tellTarget` (slash and dot paths), `GetProperty` /
`SetProperty`, `RandomNumber`, `GetTime`, and `GetURL` / `FSCommand2`
via host hooks (`SwfHost`). `DefaultSwfHost` answers the date/time
`FSCommand2` queries with real values.

### Player model (`SwfStage`)

Frame advancing with correct VM/timeline priority semantics, key dispatch
(`SwfKeyCode` — Flash Lite `CondKeyPress` codes), tap dispatch with
hit-testing, button focus navigation (4-way key movement between buttons,
as on real handsets), and root-timeline label notifications.

### Out of scope

ActionScript 2/3, video, sound, morph shapes, clip actions, and SWF5+ tags.

## Usage

```dart
import 'dart:io';
import 'package:swf_core/swf_core.dart';

void main() {
  final bytes = File('movie.swf').readAsBytesSync();
  final movie = SwfParser.parse(bytes); // FWS and CWS both accepted
  print('${movie.frameCount} frames @ ${movie.frameRate} fps');

  final stage = SwfStage(movie);
  stage.onRootLabel = (label) => print('reached label: $label');
  stage.advanceFrame();
  stage.dispatchKey(SwfKeyCode.enter);
  print(stage.root.getVariable('score'));
}
```

Host integration (traces, `GetURL`, `FSCommand2`, time, randomness) is
injected via `SwfHost`; `DefaultSwfHost` provides sensible defaults and an
optional `log` callback.

### Building synthetic SWFs (`package:swf_core/testing.dart`)

The `testing` library ships a byte-level SWF builder and an SWF4 bytecode
assembler, so you can write fully self-contained tests — or generate demo
content — without any real SWF assets:

```dart
import 'package:swf_core/testing.dart';

final swfBytes = (SwfBuilder()
      ..defineShapeRect(1, widthPx: 40, heightPx: 40, fillRgb: 0xCC5544)
      ..placeObject2(depth: 1, characterId: 1, translateXPx: 100)
      ..frameLabel('start')
      ..doAction(Asm().pushString('score').pushFloat(0).op(0x1D).build())
      ..showFrame())
    .build();
```

### CLI

A structure-dump tool is included:

```sh
dart run swf_core:swfdump movie.swf
```

## Known limitations

- Button rollout (`OverUpToIdle`) actions are not fired on focus-out
  (the parser does not retain that flag); content that resets state on
  rollout may keep the rollover state.
- Tap hit-testing approximates the hit shape with its transformed
  bounding box.

## 日本語

ガラケー時代の **Flash Lite 1.x（SWF4）** コンテンツを扱うPure Dart
ランタイムです。パーサ・ActionScriptインタープリタ・プレイヤーモデル
（フレーム進行/キー/タップ/フォーカスナビゲーション）を含み、Flutter非依存
なのでCLI・サーバ・テストからも使えます。FlutterでのUI再生には
[`swf_player`](https://pub.dev/packages/swf_player) を使ってください。
`package:swf_core/testing.dart` の `SwfBuilder`/`Asm` で合成SWFを生成でき、
著作物に依存しないテスト・デモが書けます。音声・動画・ActionScript 2/3は
対象外です。

## License

MIT
