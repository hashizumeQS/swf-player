# swf_player

[![CI](https://github.com/hashizumeQS/swf-player/actions/workflows/ci.yaml/badge.svg)](https://github.com/hashizumeQS/swf-player/actions/workflows/ci.yaml)
[![swf_core](https://img.shields.io/pub/v/swf_core.svg?label=swf_core)](https://pub.dev/packages/swf_core)
[![swf_player](https://img.shields.io/pub/v/swf_player.svg?label=swf_player)](https://pub.dev/packages/swf_player)

Play SWF4 / **Flash Lite 1.x** content (Japanese feature-phone era games
and animations) in Dart and Flutter.

| Package | Description |
| --- | --- |
| [`packages/swf_core`](packages/swf_core) | Pure-Dart SWF4 parser, player model, and ActionScript interpreter. No Flutter dependency. |
| [`packages/swf_player`](packages/swf_player) | Flutter playback widgets: stage renderer, player controller, and a feature-phone style virtual keypad. |

See each package's README for usage, and
[`packages/swf_player/example`](packages/swf_player/example) for a complete
app that generates a demo SWF at runtime (no copyrighted content bundled).

## Development

This repository is a [pub workspace](https://dart.dev/tools/pub/workspaces):

```sh
dart pub get                                # resolve the whole workspace
cd packages/swf_core && dart test           # core tests
cd packages/swf_player && flutter test      # widget tests
```

## License

MIT
