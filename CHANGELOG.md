# Changelog

## 0.3

- **pdfium backend (Windows).** Direct GDI/DEVMODE printing via tclpdfium
  0.6+, no external program. `detect` considers it depending on
  `pdfiumPrefer`; `status` reports `pdfium_ok`. The Brother QL label matcher
  (`_pdfiumFormForLabel`) resolves continuous tapes by name.
- **Runs under Tcl 9.** The version requirement was `package require Tcl 8.6`
  (exactly 8.6) and failed under 9; now `8.6-`.
- **36 tests** (runnable without a printer) plus a guard test that keeps the
  test copies identical to the shipped procedures.
- **Backend registry (internal cleanup).** The known backends now live in a
  list (`variable backends`); `detect` derives the per-platform chain from it
  instead of hardwiring it in three places. Behaviour unchanged -- a new
  backend needs a registry entry instead of scattered edits. Confirmed along
  the way: pdftocairo only applies on Windows (the `-print` is missing from
  the poppler-utils on Linux/macOS).
- Merged the two 0.2 lines: GUI/PPD/profiles/demos and the pdfium backend now
  live in one module.

## 0.2

- **Printer config export/import (Windows).** `exportPrinterConfig` /
  `importPrinterConfig` save and restore the full DEVMODE (including
  driver-private data like the Brother label format) via `printui.dll` --
  distribute a once-configured label size across machines without opening the
  driver dialog. Import may need administrator rights.
- **Printer profiles (Windows).** Keep several label sizes as named profiles
  (`savePrinterProfile` / `usePrinterProfile` / `listPrinterProfiles`) and
  switch before printing; `openPrinterSettings` opens the Windows driver
  dialog so a profile can be captured. The GUI exposes the whole workflow.
- **lp backend (CUPS) for Linux/macOS**, plus a Linux capabilities parser
  (`lpoptions`) and `resolvePrinter` for cross-platform printer lookup.
- **Label printer API** (`isLabelPrinter`, `labelformats`, `labelsize`,
  `labelpaper`) with the Brother DK format table.
- **Own config formats** (`.pdftocairo` / `.sumatra`) with per-printer PPD
  files, plus explicit `-paperw`/`-paperh`, the `-orientation` and `-cut`
  options, and an expanded GUI.
- Several label-printing bugfixes (90-degree rotation, "invalid paper size").

## 0.1.1

- Bugfixes: undefined `copies` variable in `_print_sumatra`; the `info`
  procedure was wrongly exported; `fit` vs `expand` mapped identically; a
  redundant absolute-path `variable cfg`.
- Consistency: `detect` no longer throws asymmetrically; `print -backend xyz`
  updates `activeBackend`; `printercaps_all` no longer aborts on a single bad
  printer.

## 0.1

- First version: Windows printing via pdftocairo and SumatraPDF, with
  registry-based printer enumeration.
