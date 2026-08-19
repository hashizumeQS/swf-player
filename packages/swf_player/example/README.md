# swf_player example

A minimal demo of the `swf_player` public API: `SwfPlayerController`,
`SwfPlayerView`, and `KeypadWidget`.

The demo content is not a real SWF asset — it is generated at runtime by
`lib/demo_swf.dart` using `swf_core`'s `SwfBuilder`/`Asm` testing utilities,
so no copyrighted content is bundled with this example.

It shows a 240x240 stage with three looping, color-coded "scenes". Press
`1`/`2`/`3` on the on-screen keypad to switch scenes, and `#` to jump to an
"over" screen (which pops a `SnackBar`).

## Run

```sh
flutter create . --platforms=macos  # or ios/android/etc. (first time only)
flutter run
```
