# printlib 0.3.3

Cross-platform PDF printing library for Tcl/Tk.

Prints PDF files directly from Tcl on Windows, Linux and macOS. Supports
office printers (with the usual options like trays, duplex, scaling) and
label printers (Brother QL series, with a DK format table).

## Installation

Put the Tcl module, named by the `name-version.tm` convention, on a tm path:

```bash
mkdir -p ~/.local/lib/tcl8/site-tcl
cp lib/tm/printlib-0.3.3.tm ~/.local/lib/tcl8/site-tcl/
```

Or leave it in place and add the path to Tcl:

```tcl
::tcl::tm::path add /path/to/printlib/lib/tm
package require printlib
```

Runs under Tcl 8.6 and Tcl 9.x.

## Platform backends

| Platform | Backend | Path |
|----------|---------|------|
| Windows | `pdfium` | direct GDI/DEVMODE printing via tclpdfium 0.6+, no external program |
| Windows | `pdftocairo` | `pdftocairo -print` straight to the Windows spooler |
| Windows | `sumatra` | SumatraPDF (bitmap fallback) |
| Linux / macOS | `lp` | CUPS, with an installed printer driver |

`detect` picks the backend per platform automatically. On Linux/macOS
`pdftocairo -print` does not work (it exists only in the Windows build), so
`lp` (CUPS) is used there.

## Quick start

### Simple printing

```tcl
package require printlib

printlib::print invoice.pdf -printer "HP LaserJet" -duplex long
```

### Label printing (Brother QL)

```tcl
package require printlib
package require pdf4tcl

# Get the label dimensions
set lbl [printlib::labelsize "DK-22205"]   ;# 62mm continuous

# Create a PDF at exactly that size
set pdf [::pdf4tcl::new %AUTO% \
    -paper [list [dict get $lbl width_pt] 71] \
    -margin 0]
$pdf startPage
$pdf setFont 10 Helvetica
$pdf text "Karl Mustermann" -x 5 -y 12
$pdf text "Hauptstr 1"      -x 5 -y 24
$pdf text "12345 Berlin"    -x 5 -y 36
$pdf write -file /tmp/label.pdf
$pdf destroy

# Resolve the printer cross-platform
set printer [printlib::resolvePrinter "QL-820NWB"]
# -> Windows: "Brother QL-820NWB"
# -> Linux:   "Brother_QL-820NWB_IPP"

# Print with the correct label settings
printlib::print /tmp/label.pdf \
    -printer     $printer \
    -paper       [printlib::labelpaper "DK-22205"] \
    -scale       origsize \
    -orientation portrait \
    -cut         auto
```

`labelpaper` liefert den Namen, den der Treiber erwartet -- aus
`DK-22205` wird `DK22205`.

Das `;#` stand bis 17.09.2026 hinter der `-paper`-Zeile, **ohne**
Fortsetzungsstrich. Gemessen: `print` bekam vier statt zehn Optionen,
danach brach es mit `invalid command name "-scale"` ab. Ein Kommentar
in einer fortgesetzten Argumentliste beendet den Aufruf.

### Default configuration per printer (PPD files)

Instead of giving the options every time, printer defaults can be stored in a
PPD file:

```tcl
# One-time setup
printlib::savePpdFile "Brother_QL-820NWB_IPP" pdftocairo {
    printer     "Brother_QL-820NWB_IPP"
    paper       DK22205
    scale       origsize
    orientation portrait
    cut         auto
    type        label
    subtype     continuous
}

# Later everywhere in the code -- explicit options suffice, the rest
# comes from the PPD:
printlib::print invoice.pdf -printer "Brother_QL-820NWB_IPP"
```

Search order for PPD files:
1. `$cfg(ppdDir)` (set via `configure -ppddir`)
2. `[pwd]/ppd/`
3. `[file dirname [info script]]/ppd/`

## API overview

### Printing

| Function | Purpose |
|----------|---------|
| `configure ?-opt val ...?` | set global default options |
| `print pdf ?-opt val ...?` | print -- returns `""`, **throws** on failure |
| `command pdf ?-opt val ...?` | build the command line and return it, **without printing** |
| `detect` | determine / check the active backend |
| `tmpdir` | a directory for work files, proven writable |
| `status` | module status + backend availability |

### Printer information

| Function | Purpose |
|----------|---------|
| `printerlist` | all available printers |
| `defaultprinter` | system default printer |
| `printerinfo printer` | basic printer info |
| `printercaps printer` | printer capabilities (paper, trays, duplex, ...) |
| `printercaps_all` | caps for all printers |
| `resolvePrinter pattern` | cross-platform lookup |
| `exportPrinterConfig printer file` | save DEVMODE (Windows, printui.dll) |
| `importPrinterConfig printer file` | set DEVMODE (Windows, admin rights) |
| `savePrinterProfile printer name` | save a setting as a named profile |
| `usePrinterProfile printer name` | apply a profile (switch format) |
| `listPrinterProfiles printer` | list available profiles |

### PPD config files

| Function | Purpose |
|----------|---------|
| `findPpdFile printer backend` | locate a PPD file |
| `loadPpdFile path` | read a PPD file (-> dict) |
| `savePpdFile printer backend opts` | write a PPD file |

### Label API

| Function | Purpose |
|----------|---------|
| `isLabelPrinter printer` | is X a label printer? (heuristic) |
| `labelformats printer ?filter ...?` | known DK codes for the model class |
| `labelsize format` | dimensions (mm + pt, all properties) |
| `labelpaper format` | CUPS media size name (e.g. `DK22205`) |

## print options

| Option | Values | Effect |
|--------|--------|--------|
| `-printer` | printer name | target printer |
| `-scale` | `noscale fit shrink expand match origsize` | scaling mode, see below |
| `-paper` | `A4 A3 ... DK22205 ...` | paper / media size |
| `-source` | `upper lower middle manual ...` | tray |
| `-duplex` | `off long short` | duplex mode |
| `-copies` | number | copies (also for pdftocairo, via a loop) |
| `-pages` | `1-3` `1,3,5` `odd` `even` | page range |
| `-silent` | `0 1` | suppress the error dialog |
| `-orientation` | `portrait landscape reverse-landscape reverse-portrait` | print orientation |
| `-cut` | `auto on off end` | auto-cut for label printers |
| `-backend` | `auto pdfium pdftocairo sumatra lp` | force a backend |

### Scaling, and why `noscale` has to say something

`noscale` is the default and means "print 1:1". Up to 0.3.1 the `lp` backend
sent **nothing** for it: the application asked for original size, and nothing
to that effect left the machine. What happened then was the filter chain's
decision, and a generic IPP Everywhere PPD without margin information scales
the page down to the printable area.

On anything measured in millimetres -- a sheet of labels above all -- that is
expensive to diagnose, because it shows up as an offset that **grows with
every item** and looks exactly like wrong geometry. Reach for the sheet
dimensions at that point and the error moves into the profile, where it is
correct for one printer and wrong everywhere else.

For pdftocairo on Windows the same trap had a second door: without
`-noshrink` pdftocairo shrinks every page larger than the paper, and the
paper is the printable area -- an A4 sheet came out at 94.2 %. Since 0.3.3
`noscale` sends `-noshrink`.

What each `-scale` value puts on the command line, per backend:

| `-scale` | pdftocairo | SumatraPDF | lp (CUPS) | pdfium |
|---|---|---|---|---|
| `noscale` (default) | `-noshrink` | `noscale` | `print-scaling=none` | `-fit 0` |
| `origsize` | `-origpagesizes` | `noscale` | `print-scaling=none` | `-fit 0` |
| `shrink` | (nothing -- pdftocairo shrinks by default) | `shrink` | `fit-to-page` | `-fit 1` |
| `fit` | `-expand` | `fit` | `fit-to-page` | `-fit 1` |

`inv-command-1.*` / `2.*` pin these lines. They prove what is **sent**, not
what is **printed**. Measured on the device ("Raster drucken" in
etikettendruck, ruler on the 100 mm scale):

| Backend | Printer | 100 mm measured | Date |
|---|---|---|---|
| pdftocairo `-noshrink` | | not measured yet | |
| SumatraPDF `noscale` | | not measured yet | |
| lp `print-scaling=none` | | not measured yet | |

Since 0.3.2, `noscale` and `origsize` send `print-scaling=none`. It goes out
unconditionally -- CUPS passes over unknown options silently -- and whether
the printer knows it is a separate question:

```sh
lpoptions -p NAME -l | grep print-scaling
```

```tcl
set caps [printlib::printercaps $name]
dict get $caps scaling_option    ;# print-scaling, if the driver offers it
dict get $caps scaling_default   ;# not "none" -> it scales unless told
```

Missing from `printercaps` means printlib still sends the option, and whether
it arrives cannot be established from here. That is the difference between
*sent* and *applied*, and it is worth keeping apart: `fit-to-page` and
`print-scaling=none` are both just text until a filter acts on them.

## Precedence with several sources

Options come from four sources, with the following precedence:

1. Explicit `-option` arguments on the `print` call (CLI)
2. Values from the PPD file (`ppd/<name>.<backend>`)
3. Global defaults set via `configure`
4. Built-in defaults

## GUI

`printlib-gui.tcl` provides a Tk-based example GUI:
- printer selection with caps display
- all the important print options as comboboxes
- "save config" -> `savePpdFile`
- "status" -> diagnostic dialog (module status, PPD search paths)
- copyable error dialogs (text widget instead of `tk_messageBox`)

```bash
tclsh printlib-gui.tcl
```

## Example scripts

- **`demo/demo-labels.tcl`** -- lists everything printlib knows (no printer
  needed, no pdf4tcl needed). For exploring.
- **`demo/demo-label-pdf-print.tcl`** -- complete workflow: argv = printer +
  DK code + text -> creates PDF -> prints. For actually printing.
- **`demo/demo-printlib.tcl`** -- the older demo GUI (basic functions).
- **`tools/twapi-diag.tcl`** -- diagnostics for the Windows print APIs (twapi).

## Example PPDs

In `ppd/`:
- `HP_LaserJet_P2055.pdftocairo` -- ordinary office printer
- `Brother_QL-820NWB.pdftocairo` -- QL label printer (Linux/lp)
- `Brother_QL-820NWB.sumatra` -- QL label printer (Windows/sumatra)

### Errors

`print` returns `""` and **throws** when the job failed -- there is no
error return value:

```tcl
if {[catch {printlib::print $file -printer $p} err]} { ... }
```

What counts as a failure is decided by the backend's exit code, not by the
text of its output: a program that only writes to stderr and exits 0 has
printed. Font warnings from pdftocairo are the everyday case.

`-silent` is a wish, not a promise -- the effect differs per backend
(`-q` for pdftocairo, `-silent` for SumatraPDF, nothing for lp and
pdfium).

### Checking the options without printing

`command` builds exactly the line `print` would execute and hands it back.
Paper is the one output that cannot be rolled back, so the option build --
above all the input tray -- deserves a test that costs no sheet:

```tcl
printlib::command bogen.pdf -backend lp -printer kluniversal -source manual
# -> lp -d kluniversal -o InputSlot=Manual -o CutLabel=ON -o AutoCut=ON bogen.pdf
```

Two deliberate differences from `print`: `command` does not require the
backend to be available on this machine (otherwise the Windows line could
not be tested on Linux, which is where the suite runs), and it does not
require the file to exist. `pdfium` has no command line -- it prints via
GDI/DEVMODE in-process -- and `command` says so instead of inventing one.

## Versions

- **0.3.3** (current): pdftocairo `-scale noscale` now sends `-noshrink`
  (it sent nothing, and pdftocairo shrinks to the printable area by default --
  measured 94.2 % on a label sheet); `shrink` sends nothing.
- **0.3.2**: `-scale noscale` actually sends `print-scaling=none`
  (it sent nothing); `lpoptions` option names with a hyphen are no longer
  merged onto one key -- on a driverless IPP printer `print-scaling`,
  `print-quality` and `print-color-mode` all became `print`; `printercaps`
  reports `scaling_option`/`scaling_values`/`scaling_default` and carries the
  raw `lpoptions` table; the GUI diagnosis prints the scaling option
- **0.3.1**: `command`; `_available` obeys the platform registry
  on the explicit path too; PPD autoload no longer breaks `print` with
  pdfium + printer name; a failed print no longer reports success
  (exit code instead of text matching); `print`'s documented return
  contract corrected; error messages in one language; `tmpdir` instead of
  `env(TEMP)` (which threw on Linux); the diagnostics button works on both
  platforms; the demo no longer duplicates the GUI
- **0.3**: pdfium backend, backend registry, runs under Tcl 9,
  the two 0.2 lines merged into one module
- **0.2**: PPD format, lp backend, label API, orientation/cut,
  resolvePrinter, expanded GUI
- **0.1.1**: bugfix release (copies variable, info conflict, ...)
- **0.1**: first version (Windows pdftocairo + sumatra)

Full changelog: `CHANGELOG.md`

## Roadmap

Planned extensions -- widget printing via `tk print`/tkprintcompat, a
capabilities API, completing the backend registry -- are in
[`doc/roadmap.md`](doc/roadmap.md).

## License

**BSD 2-Clause** -- see [LICENSE](LICENSE). The module header says the
same; decided 17.09.2026, after the three places had disagreed (header
BSD, this line MIT, no `LICENSE` file at all).

BSD 2-Clause fits the neighbourhood: Tcl itself, pdf4tcl and tcllib are
all under BSD-style licences, so anyone shipping printlib beside them
has one licence family rather than two.

### Third-party parts

`pdftocairo`, `lp` and SumatraPDF are called as **external programs** --
printlib does not link them, and their licences do not reach into code
that uses printlib.

`pdfiumtcl` is different: it is loaded into the process, and PDFium's
own licence (BSD-style) applies to it. Anyone redistributing printlib
together with pdfiumtcl should ship that licence too.
