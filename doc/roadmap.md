# printlib -- roadmap and design notes

**Version:** 0.3

## Where printlib stands today

printlib prints PDF files through a per-platform backend. Backends are kept in
a registry (`variable backends`):

| Backend | Platform | Path |
|---------|----------|------|
| `pdfium` | Windows | GDI/DEVMODE via tclpdfium 0.6+, no external program |
| `pdftocairo` | Windows | `pdftocairo -print` to the spooler |
| `sumatra` | Windows | SumatraPDF (bitmap fallback) |
| `lp` | Linux/macOS | CUPS |

Plus: the Brother QL label matcher, booklet imposition (`-booklet`),
PPD-style config files, and a setup GUI.

## Roadmap

### R1 -- Widget printing

Today `printlib::print` takes a PDF file. A polymorphic `print` would recognise
the source:

```tcl
::printlib::print "document.pdf"   ;# file       -> pdfium/pdftocairo/lp
::printlib::print $pdfobj          ;# pdf4tcl     -> direct, no temp file
::printlib::print .mycanvas        ;# Tk canvas  -> tk print / tkprintcompat
::printlib::print .mytext          ;# Tk text    -> ditto
::printlib::print $rawbytes        ;# raw bytes  -> label printer
```

The existing backends all take a file. A canvas is not a file. `tk print` (from
Tk 9, backported to 8.6 by
[`tkprintcompat`](https://github.com/gregnix/tkprintcompat)) takes a widget and
not a file. The two meet only after rendering -- a canvas becomes a PDF, then
the file chain takes over.

Implementation, in small steps:

1. `printlib::print` detects the source: if `$arg` exists as a widget
   (`winfo exists`), it is a canvas/text -> widget branch; otherwise
   file/object as before.
2. Widget branch via `tk print` / `tkprintcompat` where available (check the
   capability, not the version).
3. Optionally, as an alternative path for callers who need programmatic control
   over margins and scaling without a dialog: render the canvas to PDF via
   pdf4tcl and feed it into the file chain.

Open decision: whether widget printing moves into `print` (polymorphic) or sits
beside it as `printlib::printwidget`. `tk print` presents its own print dialog,
whereas printlib's file backends print without one; the API should make that
difference in behaviour predictable for callers.

### R2 -- Capabilities API

`printlib::capabilities ?printer?` -- returns paper sizes, trays, duplex,
colour, borderless per printer. On Windows `::pdfium::printercaps` returns this
data (margins, DPI, borderless) and `::pdfium::papers` the form list. The task
is to bundle it cross-platform behind one procedure (Windows via pdfium, Linux
via CUPS/lpoptions).

### R3 -- Complete the backend registry

The registry rework (0.3) moved `detect` and the validity lists onto the list.
Still hardwired:

- `_available` -- the per-backend `switch` could read the availability check
  from the registry (each backend carrying its probe script).
- the dispatch in `print` -- the `if/elseif` chain onto `_print_$be`.

Both touch the working `print` procedure (PPD handling, booklet branch), so
only with the tests as a safety net.

### R4 -- Raw bytes for label printers

`printlib::print $rawbytes` for printers that speak their own language
(ESC/POS, ZPL).

## Deliberately NOT planned

- **No real PPD format.** Too large, CUPS-specific. The lean own
  `.pdftocairo`/`.sumatra` formats stay.
- **No own rendering engine.** printlib orchestrates existing backends; it does
  not rasterise itself.
