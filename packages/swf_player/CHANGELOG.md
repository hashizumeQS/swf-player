# Changelog

## 0.1.2

- `SwfPlayerView`: clip the stage rendering to the widget bounds. Shapes placed
  outside the SWF stage rectangle no longer paint over surrounding widgets
  (visible when the view sits inside a wider parent, e.g. a desktop browser
  window).

## 0.1.1

- Documentation: expanded README (screenshot, input/advanced-hooks guides,
  Japanese summary), added pub.dev topics, and filled in member-level API
  docs for the rendering layer.

## 0.1.0

- Initial release.
- `SwfPlayerController`: SWF loading (FWS/CWS), frame advancing, key/tap
  dispatch with remapping, root-label notifications, variable access,
  render options, and resource cleanup.
- `SwfPlayerView`: frame-rate-accurate playback via `Ticker`, physical
  keyboard mapping, tap-to-stage coordinate conversion, and
  `CustomPainter`-based stage rendering.
- `KeypadWidget`: feature-phone style virtual keypad (D-pad ring +
  numeric keys with auto-repeat).
- Rendering layer: shapes (gradients, bitmap fills), lossless/JPEG/JPEG3
  bitmaps, static and dynamic texts, buttons, color transforms, and
  clip-depth masks.
