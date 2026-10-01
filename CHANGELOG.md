# Changelog

## 0.3.1

### Changed

- **`-orientation portrait` is now said out loud.** The `lp` backend sent
  `orientation-requested=4/5/6` for landscape and the two reverse values
  and **nothing at all** for portrait ("CUPS-Default"). Three of four
  values went out, one did not -- so there was no way to tell whether
  portrait had taken effect or whether nothing had arrived. printlib's own
  default says `orientation portrait`; that now reaches CUPS as
  `orientation-requested=3`. Note this is a behaviour change: a setup that
  relied on printlib leaving the driver's orientation untouched now gets
  portrait explicitly.

### Fixed

- **The label was never cut.** Reported from a Brother QL-820NWB on CUPS,
  01.10.2026: no cut, with any of the four settings. The driver says

  ```text
  CutMedia/CutMedia: *None Auto EndOfPage EndOfJob
  ```

  and printlib sent `CutLabel=ON` / `AutoCut=ON` / `CutAtEnd=ON` -- names
  this driver does not know. CUPS passes over unknown options silently, so
  `*None` stayed in force and the label stayed on the roll. The code said
  as much: *"mehrere gaengige Schalter ... der Treiber waehlt den
  passenden"* -- a hope, not a strategy, and the same fault as the input
  tray. `_printercaps_linux` now keeps the cut option it already parsed
  (`cut_option`, `cut_values`, `cut_default`), and `_cutLpOpts` maps the
  wanted mode onto a value the driver actually offers:

  ```text
  auto -> CutMedia=Auto        on  -> CutMedia=EndOfPage
  off  -> CutMedia=None        end -> CutMedia=EndOfJob
  ```

  A driver with no cut option gets nothing (correct for an office
  printer); a mode the driver cannot express sends nothing rather than
  something that would be ignored, and the GUI logs which option was
  found.


- **`env(TEMP)` crashed the GUI on Linux.** Reported from Debian, 01.10.2026:

  ```text
  can't read "::env(TEMP)": no such variable
    (read trace on "::env(TEMP)")
  invoked from within "file join $::env(TEMP) printlib_caps.ps1"
  ```

  `TEMP` is set by Windows; on Linux the variable does not exist, and
  reading a missing element of `::env` throws -- it does not return `""`.
  The line stood three times in the tree. New `printlib::tmpdir` picks a
  temp directory per platform and **proves it is writable by writing
  there**: `file writable` lies on Windows (ACLs, controlled folder
  access), so the only reliable test is the attempt.

- **The "Diagnose" button was Windows-only and said nothing about it.**
  Its whole content was twapi, PowerShell/WMI and recordarray; on Linux it
  printed three empty headings and then died on the line above. It now
  branches: on Windows as before, on Unix `lpstat -p -l`, `lpoptions -l`
  and what `printercaps` makes of them -- and it always names the
  platform, the backend and the temp directory first.

### Changed

- **`demo/demo-printlib.tcl` is no longer a second GUI.** It held 859
  lines that were a copy of `printlib-gui.tcl` -- its own header said
  "funktionsgleich", and measured the two differed in 20 lines (title,
  module path, comments). That is why the `env(TEMP)` fault sat in the
  tree twice, and fixing one would have left the other. The demo now
  sources the GUI and only changes the window title.


- **A failed print reported success.** `_print_pdftocairo` decided from the
  *text* of the error whether the run had failed -- it aborted only on
  `*child process exited abnormally*` or `*Error:*`. Measured with a faked
  `exec`, 30.09.2026:

  ```text
  exit 1, "I/O setup failed: cannot open printer port"
    -> print returned "", i.e. success. Nothing was printed.
  ```

  A print that did not happen and reports success is worse than one that
  fails loudly: nobody goes to look at the paper. `lp` and SumatraPDF had
  the opposite rule -- every `catch` counted as a failure, including a mere
  note on stderr at exit 0. All three now ask `_execFehler`, which reads
  `-errorcode`: `NONE` means the program ran and only wrote to stderr,
  `CHILDSTATUS` / `CHILDKILLED` / `POSIX` mean it did not.

- **The documented return contract of `print` was wrong.** The header said
  *"Gibt \"\" zurueck bei Erfolg, Fehlermeldung bei Fehler"* -- which reads
  like a return value. `print` throws. Anyone who believed the comment
  checked for an empty string and would never notice a failed print.

- **`-silent` promised more than it does.** The comment said "beide
  Backends"; there are four, and the effect differs: `-q` for pdftocairo,
  `-silent` for SumatraPDF, nothing for lp and pdfium. Now documented per
  backend; unifying it would be an API change and is not done here.

- **Error messages spoke two languages.** lp, pdftocairo and sumatra in
  German, pdfium in English (`no printer given and no system default`).
  For a caller matching on text, or for a log, that is a trap. All German
  now, and `inv-sprache-1.0` keeps it that way.


- **The platform registry now applies on the explicit path too.** Until 0.3
  only `detect` consulted it, via `_backendsFor` -- so the `auto` chain was
  safe, but `print -backend pdftocairo` on Linux was not: `_available`
  merely looked for the binary. Measured on Debian, 30.09.2026:

  ```text
  $ which pdftocairo                      /usr/bin/pdftocairo
  $ pdftocairo -h | grep -c '^  -print'   0      <- cannot print
  % printlib::_available pdftocairo       1      (0.3)
  % printlib::configure -backend pdftocairo ; printlib::detect
    -> pdftocairo                                (0.3)
  ```

  The next `print` then failed with a message that did not say why.
  `inv-backends-1.1` tested the `auto` case, i.e. the one that already
  worked; `inv-backends-1.2` and `-1.3` now cover the other.

- **PPD autoload no longer breaks pdfium.** `print` looked for a
  `.pdftocairo` / `.sumatra` file whenever `-printer` was given, and
  `findPpdFile` throws for a backend that has no such format. So

  ```tcl
  print datei.pdf -backend pdfium -printer "Brother QL-820NWB"
  ```

  died with `findPpdFile: ungueltiges Backend 'pdfium'` **before printing**
  -- and that is the main path of this backend: pdfium is the Windows label
  route, and a printer name belongs to it. Without `-printer` it worked,
  with `-printer` never. The suite could not see it because `_print_pdfium`
  is never reached without tclpdfium; `inv-ppd-2.0` now fakes `_available`
  and checks the path up to the backend.

### Added

- **`command`** -- builds the command line and returns it **without
  printing**. The option build, above all the input tray, was otherwise
  only testable on paper, and paper cannot be rolled back. Taken from the
  etikettendruck branch, where it carried its own copy of the option list;
  here `print` and `command` share `_parseOpts`, the PPD autoload and the
  `_cmd_*` procedures, so the line that comes out is the line that would
  run. 10 test cases (`inv-command-1.0` .. `-1.8`, `inv-ppd-2.1`).
- `_print_pdftocairo` / `_print_sumatra` / `_print_lp` split into "build
  the line" (`_cmd_*`) and "run it".

### Changed

- The test files derive the module filename from `package provide` instead
  of spelling `printlib-0.3.tm`. A guard that watches the wrong file is not
  a guard, and a hardcoded name goes stale at the next version bump.

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
