# Tests

From the plugin directory, run `lua tests/run.lua` or `luajit tests/run.lua`.

The suite uses Lua 5.1 with test doubles for KOReader services, so a separate
KOReader installation is not required. It covers:

- Selection boundaries passed to the HTML API, saved markup and CSS, legacy pins,
  plain-text fallback and viewer API calls.
- Link direction and order, cycles, deletion from the correct source when IDs
  collide, navigation through another ReaderUI, unavailable files and link settings.
- Current reader fonts and style variants, fallback fonts and typography overrides.
- Viewer settings, popup geometry and painting, deferred opening, modal input,
  outside-tap dismissal, image preview, fullscreen expansion and snapshot cleanup.
- KOReader language preference, active/system locale detection, English fallback,
  complete Russian UI translations, placeholders and localized metadata/menus.

These tests verify plugin logic rather than CRe/MuPDF rendering. Check real EPUB/FB2
selections and visual output in KOReader on a device. For languages, restart with
Russian, English and an unsupported interface language, then check the selection
and image buttons, gesture actions, both viewers, settings and deletion confirmations.
