# printlib 0.3

Cross-platform PDF printing library for Tcl/Tk.

Prints PDF files directly from Tcl on Windows, Linux and macOS. Supports
office printers (with the usual options like trays, duplex, scaling) and
label printers (Brother QL series, with a DK format table).

## Installation

Put the Tcl module, named by the `name-version.tm` convention, on a tm path:

```bash
mkdir -p ~/.local/lib/tcl8/site-tcl
cp lib/tm/printlib-0.3.tm ~/.local/lib/tcl8/site-tcl/
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
    -paper       [printlib::labelpaper "DK-22205"]  ;# -> "DK22205"
    -scale       origsize \
    -orientation portrait \
    -cut         auto
```

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
| `print pdf ?-opt val ...?` | print |
| `detect` | determine / check the active backend |
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
| `-scale` | `noscale fit shrink expand match origsize` | scaling mode |
| `-paper` | `A4 A3 ... DK22205 ...` | paper / media size |
| `-source` | `upper lower middle manual ...` | tray |
| `-duplex` | `off long short` | duplex mode |
| `-copies` | number | copies (also for pdftocairo, via a loop) |
| `-pages` | `1-3` `1,3,5` `odd` `even` | page range |
| `-silent` | `0 1` | suppress the error dialog |
| `-orientation` | `portrait landscape reverse-landscape reverse-portrait` | print orientation |
| `-cut` | `auto on off end` | auto-cut for label printers |
| `-backend` | `auto pdfium pdftocairo sumatra lp` | force a backend |

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

## Versions

- **0.3** (current): pdfium backend, backend registry, runs under Tcl 9,
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

MIT -- see [LICENSE](LICENSE).
