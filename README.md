[Русский](README.ru.md)

# pin.koplugin for KOReader

Pin selected text and images in KOReader. Save passages and browse them without
returning to their original page. The default viewer is fullscreen; an optional compact
panel appears in the bottom-right corner over the book page.

## Features

1. Pin selected text from the selection menu.
2. Pin images from KOReader's image viewer (long-press an image in the book → **Pin**).
3. Browse pins from newest to oldest in fullscreen or in a compact popup panel.
4. Scroll long text within the viewer.
5. Open pinned images fullscreen and zoom them.
6. Return to the original passage with **Go to passage**.
7. Delete individual pins or all pins in the current book.
8. Preserve HTML markup and styles in new EPUB and FB2 text pins: paragraphs,
   indentation, italics, bold text, quotations and poetry.
9. Add one-way links to pins from other books, including previous volumes.
10. Use the current book's font and text size in both viewing modes.
11. Automatically display the plugin interface in English or Russian.

## Installation

1. Copy the `pin.koplugin` folder into KOReader's plugins directory:
   `koreader/plugins/pin.koplugin/`.
2. Restart KOReader.
3. Enable **Pin** in KOReader's plugin management menu under **More tools**.

## Usage

- **Text:** select a passage and tap **Pin** in the selection menu.
- **Image:** long-press an image and tap **Pin** in the image viewer.
- **Browse:** **Menu → Tools → Pins → View pins**.
  Use **Prev.** / **Next** or swipe left/right to switch between pins.
- **Gestures:** the gesture settings offer **Show pins** and **Pin selection** actions.

Pins are stored in `koreader/settings/pin.lua`, images in
`koreader/settings/pin_media/`, and book links in
`koreader/settings/pin_links.lua`. Pins and links are associated with the book's
file path. The viewer mode is stored in `koreader/settings/pin_options.lua`
and applies to all books.

## Interface language

The plugin follows KOReader's interface language: Russian for Russian, English for
English and all other languages. If no language is explicitly selected in KOReader,
the plugin uses the system locale available to KOReader. English is the fallback when
the language cannot be detected. No separate plugin language setting is needed.
Restart KOReader after changing its language, as requested by KOReader itself.
The interface language does not change saved passages, book filenames or file paths.

## Compact viewer

Enable **Menu → Tools → Pins → Viewer mode → Popup in the bottom-right corner**.
Choose **Fullscreen** to return to the default viewer. Fullscreen remains the default
on a fresh installation or an upgrade without a saved mode setting. Both modes open
through the same menu entry or the **Show pins** gesture action.

The panel has an opaque white background, a thin border, and margins from the right
and bottom edges. In portrait orientation it occupies approximately two thirds of the
screen height and 65% of its width. In landscape orientation it uses 78% of the height
to leave room for content and controls. The **⋮** menu and **×** close button are at
the top; **‹ / ›** arrows, the pin number, page and source filename are at the bottom.
A snapshot of the book page remains visible outside the panel. Book controls are
blocked while the viewer is open. A single tap outside the panel closes it and is
consumed, so it does not turn a book page. Other gestures outside the panel are consumed.

- Switch pins with the bottom arrows or a horizontal swipe inside the panel.
- Scroll text with vertical swipes within the text area or page buttons.
  On devices with buttons, the menu, close button and arrows support D-pad navigation.
- Tap an image to open KOReader's fullscreen image viewer with zoom controls.
  Closing it returns to the compact panel.
- The **⋮** menu offers **Go to passage**, **Open fullscreen**, **Details** and **Delete**.
  Expanding a text pin keeps the selected pin without changing the saved viewer mode;
  the next viewing session uses compact mode again. **Details** shows the full source
  path, page and date the pin was saved.

Opening waits for the redraw triggered by a gesture or menu to finish. The panel
restores the background snapshot and paints opaque content over it so that book text
does not show through the pin on later redraws. The snapshot stays in memory for the
viewing session and is freed on close; it is not written to storage.
Rotating the screen closes the compact viewer; reopen it in the new orientation.
If a snapshot cannot be captured or the panel does not fit, the plugin uses fullscreen.
The compact layout still needs visual verification on a physical device.

## Text formatting

For EPUB and FB2, the plugin captures the selected passage's markup from KOReader's
document engine, including ancestor elements and available book stylesheets. Markup
and CSS are saved with the pin, so viewing it does not require reopening the source book.
Additional styles support FB2 elements such as emphasis, epigraphs and poetry.
Scroll long text using vertical swipes or page buttons. On devices with a keyboard,
Shift/ScreenKB + a page button switches between pins.

The current open book supplies the font and text size each time the viewer opens.
This works in both modes, for older text pins and pins from linked books; they do not
need to be saved again. Font declarations in the saved passage are overridden for
display, while italics, bold text and indentation remain. Available files for the
selected font and its styles are used; MuPDF synthesizes missing styles. If the font
cannot be obtained, a fallback is used. Selecting a non-default face inside a TTC font
collection (an index other than 0) is currently unsupported for HTML pins.

Older pins remain readable as plain text. To preserve their original formatting,
select and pin the passage again. If the HTML API is unavailable (for example, for PDF)
or markup cannot be displayed, the saved plain text is used. The viewer uses MuPDF,
so contrast, CRe weight/antialiasing settings, complex CSS effects and book resources
embedded in the text may differ from the original page.

## Linked books

Open the book where you want to see another volume's pins, then choose
**Menu → Tools → Pins → Linked books → Add a book with pins**. The list contains books
with pins already saved by this plugin. Alternatively, choose **Choose a book file…**
and long-press the desired file; you can add a link before the source book has any pins.
On devices without a touchscreen, select the file with the normal selection button.

For example, linking volume 1 from volume 2 makes both volumes' pins visible in
volume 2. Volume 1 does not gain access to volume 2's pins. Add a separate link in
volume 1 for the reverse direction. Links are **not transitive**: if volume 3 links to
volume 2 and volume 2 links to volume 1, explicitly link volume 1 from volume 3 to see it.

The viewing order is: current book's pins from newest to oldest, then linked books in
the order their links were added, with each book's pins from newest to oldest.
The source filename is displayed with the pin's metadata. New source pins appear
the next time the viewer is opened.

- **Go to passage** opens the source book and jumps to the saved position.
- **Delete** removes the pin from its source book. For linked pins, the confirmation
  shows the source path and explains that the pin will disappear there too.
- **Delete all pins in this book** affects only the current book.
- **Linked books → desired book → Remove link** hides that book's pins while retaining
  the saved data. Change link order by removing and adding links again.

If a source book is moved or deleted, saved text and separately saved images remain
available, but jumping to the passage will fail. Pins and links do not automatically
follow a moved book to its new path. For backups, keep `pin.lua`,
`pin_links.lua`, `pin_options.lua` and the `pin_media/` directory.

## Development

Run `lua tests/run.lua` or `luajit tests/run.lua` from the plugin directory.
See [tests/README.md](tests/README.md) for coverage and device verification notes.
Plugin UI strings use English message keys; their Russian translations and language
detection are maintained in `pinlocale.lua`.
