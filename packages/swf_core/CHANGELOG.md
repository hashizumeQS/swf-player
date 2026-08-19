# Changelog

## 0.1.0

- Initial release.
- SWF4 / Flash Lite 1.x parser (shapes, bitmaps, buttons, texts, sprites,
  sound-less tag set), including CWS (zlib) decompression and Shift_JIS
  string decoding.
- ActionScript (SWF4-era bytecode) interpreter with Flash Lite 1.x
  semantics: variables, arithmetic/string ops, `tellTarget`, `gotoFrame`,
  `GetURL`/`FSCommand2` host hooks.
- `SwfStage` player model: frame advancing, timeline/VM priority semantics,
  key dispatch (`SwfKeyCode`), tap dispatch, button focus navigation,
  root-timeline label notifications.
- Pure Dart (no Flutter dependency); runs on VM, AOT, and Web.
