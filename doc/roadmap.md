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

Plus: the Brother QL label matcher, PPD-style config files, and a setup
GUI. Booklet imposition is a **draft**, not shipped -- see R3a.

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

**Partly there already** (measured 17.09.2026): `printercaps` and
`printercaps_all` exist and are exported; `capabilities` does not. So R2
is about the one cross-platform procedure, not about the data -- the
Windows half is in place.

### R3 -- Complete the backend registry

The registry rework (0.3) moved `detect` and the validity lists onto the list.
Still hardwired:

- `_available` -- the per-backend `switch` could read the availability check
  from the registry (each backend carrying its probe script).
- the dispatch in `print` -- the `if/elseif` chain onto `_print_$be`.

Both touch the working `print` procedure (PPD handling), so only with the
tests as a safety net.

### R3a -- Booklet imposition  *(entschieden bis Maerz 2027)*

A draft exists: `doc/printlib-booklet.tcl` with `bookletOrder` and
`makeBooklet`. It is **not** part of 0.3 -- the module never sources it,
and there is no `-booklet` option in `print`. Measured 17.09.2026: zero
occurrences of `booklet` in the module (0.3 then, 0.3.1 now).

Until 17.09.2026 this section claimed the feature as shipped. It was
not, and someone looking for `-booklet` would have found nothing.

To merge: append both procs to the module, add a `-booklet` branch in
`print`, and test `bookletOrder` -- it is pure arithmetic on the page
list, so it needs neither a printer nor pdfiumtcl. Only `makeBooklet`
writing the reordered file needs pdfiumtcl.

Merging also means the hard backend gate: `pdftocairo` and `sumatra`
cannot do n-up, so `-booklet` with them must **error**, not quietly
print 1-up. A booklet that comes out single-sided looks like an
operating mistake and is not one -- and paper is the one output here
that cannot be rolled back.

**Deadline: March 2027.** The draft has been sitting unmerged for at
least one release. If no booklet is needed by then, delete
`doc/printlib-booklet.tcl`, the eight `bookletOrder` cases in
`test-pdfium-backend.tcl`, `inv-booklet-1.0`/`1.1`, and this section.

Set on 17.09.2026 so this stops being an open question and becomes a
dated one. The eight test cases are the real asset here -- `bookletOrder`
is where booklet printing actually goes wrong, and rewriting it later
would mean rewriting them too. That is the argument for keeping the
draft rather than discarding it today.

### R4 -- Raw bytes for label printers

`printlib::print $rawbytes` for printers that speak their own language
(ESC/POS, ZPL).

## Fixed on 17.09.2026 -- no longer roadmap items

These were found by review and are done. Listed so nobody rediscovers
them as "missing features":

| What | Was | Now |
|---|---|---|
| `status` version | hard-coded `0.2` | `package provide` |
| `status` side effect | called `detect`, moved `activeBackend` | builds the chain itself |
| `*_ok` keys | one name for two questions | `*_present` vs `can_print`; old keys kept |
| `known` | not exported | exported |
| `configure` | odd option list accepted silently | errors, names the last argument |
| PPD round trip | `"` and `\` in values corrupted | escaped on write, resolved on read |
| pdftocairo `-pages odd` | printed everything | errors, and names `lp` as the way |
| README label snippet | `;#` cut the call after 4 options | fixed, comment moved below |
| Licence | header BSD, README MIT, no file | BSD 2-Clause in all three |

Guarded by `test/test-module-invariants.tcl` (16 cases, no printer
needed). Each one was measured by hand at least once before it became a
test -- the point of the file is that nobody has to do that again.

## Deliberately NOT planned

- **No real PPD format.** Too large, CUPS-specific. The lean own
  `.pdftocairo`/`.sumatra` formats stay.
- **No own rendering engine.** printlib orchestrates existing backends; it does
  not rasterise itself.
