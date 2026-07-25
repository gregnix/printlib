# ==========================================================================
#  printlib-pdfium-backend.tcl  --  patch for printlib-0.2.tm
#
#  Adds the "pdfium" backend: native Windows printing through pdfiumtcl
#  (GDI/DEVMODE), without any external program on PATH.
#
#  This makes a starpack printable on Windows as soon as libpdfium.dll
#  sits next to it -- which tclpdfium needs anyway.
#
#  Requires pdfiumtcl >= 0.6 with ::pdfium::print / ::pdfium::papers
#  (see pdfium-print-win.c and pdfium-print-devmode.c).
#
#  Affected places in printlib-0.2.tm:
#    1. cfg           -- new key pdfiumPrefer
#    2. configure     -- option -pdfiumprefer
#    3. _available    -- new branch
#    4. detect        -- backend list + Windows order
#    5. print         -- backend list + dispatch + PPD backend name
#    6. _print_pdfium -- new
#    7. status        -- pdfium_ok
# ==========================================================================


# --------------------------------------------------------------------------
# 1. cfg -- new key (add to the existing dict create)
# --------------------------------------------------------------------------
#
#     pdfiumPrefer 0 \
#
# 0 = pdftocairo takes precedence (better vector output, the sensible
#     default for installed desktop applications)
# 1 = pdfium takes precedence (no third-party software needed, the
#     sensible default for starpack deployment)


# --------------------------------------------------------------------------
# 2. configure -- new branch in the option loop
# --------------------------------------------------------------------------
#
#     -pdfiumprefer { dict set cfg pdfiumPrefer [expr {!!$val}] }


# --------------------------------------------------------------------------
# 3. _available -- new branch before "default"
# --------------------------------------------------------------------------

        pdfium {
            # Windows only: FPDF_RenderPage(HDC) does not exist in Linux
            # builds of libpdfium, the symbol is simply absent there.
            if {$::tcl_platform(platform) ne "windows"} { return 0 }
            if {[catch {package require pdfiumtcl}]}    { return 0 }
            if {![llength [info commands ::pdfium::canprint]]} { return 0 }
            return [::pdfium::canprint]
        }


# --------------------------------------------------------------------------
# 4. detect -- two changes
# --------------------------------------------------------------------------
#
#  a) extend the validity check:
#
#       if {$want ni {pdftocairo sumatra lp pdfium}} {
#           error "printlib::detect: invalid backend '$want'\
#                  (allowed: auto, pdftocairo, sumatra, lp, pdfium)"
#       }
#
#  b) replace the Windows branch:

    if {$platform eq "windows"} {
        set chain [expr {[dict get $cfg pdfiumPrefer]
                         ? {pdfium pdftocairo sumatra}
                         : {pdftocairo pdfium sumatra}}]
        set activeBackend none
        foreach be $chain {
            if {[_available $be]} { set activeBackend $be ; break }
        }
    } else {
        # Linux / macOS unchanged: lp (CUPS) is the native path.
        if {[_available lp]} {
            set activeBackend lp
        } else {
            set activeBackend none
        }
    }


# --------------------------------------------------------------------------
# 5. print -- three changes
# --------------------------------------------------------------------------
#
#  a) extend both validity lists with pdfium:
#
#       if {$be ni {pdftocairo sumatra lp pdfium}} { ... }
#
#  b) PPD backend name: pdfium gets its own format, because the option
#     values differ from those of the CLI backends (driver form names
#     instead of pdftocairo paper names):
#
#       set ppdBackend [expr {$be eq "lp" ? "pdftocairo" : $be}]
#       # unchanged -- pdfium falls into the else branch and looks for
#       # ppd/<printer>.pdfium
#
#  c) extend the dispatch:
#
#       } elseif {$be eq "pdfium"} {
#           return [_print_pdfium $pdffile $local]
#       } else { ... }


# ==========================================================================
# 6. _print_pdfium -- the new backend
# ==========================================================================

# --------------------------------------------------------------------------
# _pdfiumFormForLabel -- map a DK format onto a driver form
#
# This is the core of Windows label support. The Brother driver exposes
# its tapes as named forms ("62mm x 100mm"), not as free dimensions; a
# DMPAPER_USER with -paperw/-paperh is ignored by it. labelpaper() does
# not help here -- that is a CUPS convention (DK22205) and never appears
# in the Windows form list.
#
# So the match is numeric: dimensions from _dkLabels against those
# reported by ::pdfium::papers, with a tolerance.
#
# Returns a form name, or "" when nothing fits.
# --------------------------------------------------------------------------
proc ::printlib::_pdfiumFormForLabel {printer paper pdffile} {
    if {[catch {labelsize $paper} meta]} { return "" }
    if {[catch {::pdfium::papers $printer} forms]} { return "" }
    if {![llength $forms]} { return "" }

    set tol 2.0
    set kind [dict get $meta kind]

    # DMPAPER_USER (256) is not a form. It reports whatever custom size
    # was last configured in the driver -- on this QL-820NWB that happens
    # to be 62 x 29, which would beat the real "62mm x 29mm" form for
    # DK-11209. Drop it before matching anything.
    set usable {}
    foreach f $forms {
        if {[lindex $f 1] == 256} continue
        lappend usable $f
    }
    set forms $usable
    if {![llength $forms]} { return "" }

    # --- continuous tape ------------------------------------------------
    #
    # The height a driver reports for a continuous form is NOT a usable
    # length. A Brother QL-820NWB reports 29.0 mm for every tape,
    # regardless of width -- "29mm" even comes out square at 29 x 29.
    # Neither the reported height nor an aspect ratio can therefore tell
    # a tape from a die-cut label.
    #
    # The name can: a tape is listed as bare width ("62mm"), a die-cut
    # label as width and height ("62mm x 100mm"), a round one with a
    # diameter marker. That pattern is numeric, not localised, so it
    # survives a German or Japanese driver.
    if {$kind eq "continuous"} {
        set tw [dict get $meta width_mm]

        # 1. exact name match: <width>mm and nothing else
        set best ""
        set bestDiff 1e9
        foreach f $forms {
            lassign $f name code fw fh
            if {![regexp {^\s*([0-9]+(?:[.,][0-9]+)?)\s*mm\s*$} $name -> n]} {
                continue
            }
            set n [string map {, .} $n]
            set diff [expr {abs($n - $tw)}]
            if {$diff <= $tol && $diff < $bestDiff} {
                set bestDiff $diff
                set best $name
            }
        }
        if {$best ne ""} { return $best }

        # 2. fallback for drivers naming their tapes differently: match on
        #    width alone and exclude anything that looks like a die-cut or
        #    round form. The reported height is ignored on purpose.
        foreach f $forms {
            lassign $f name code fw fh
            # Note: \b is BACKSPACE in Tcl regular expressions, not a
            # word boundary. Plain substrings with -nocase instead.
            if {[regexp -nocase {[0-9] *mm *x|dia|\u00f8} $name]} continue
            if {abs($fw - $tw) <= $tol} { return $name }
        }
        return ""
    }

    # --- die-cut / round: both dimensions are fixed ----------------------
    switch -- $kind {
        round {
            set tw [dict get $meta diameter_mm]
            set th $tw
        }
        die_cut {
            set tw [dict get $meta width_mm]
            set th [dict get $meta height_mm]
        }
        default { return "" }
    }

    set best ""
    set bestScore 1e9
    foreach f $forms {
        lassign $f name code fw fh

        # Skip continuous tapes here. A QL-820NWB reports the 62 mm tape
        # as 62.0 x 29.0 -- numerically a *better* match for the die-cut
        # DK-11209 (62 x 29) than its own form "62mm x 29mm", which the
        # driver states as 62.0 x 28.9. Without this the tape wins and
        # the labels come out misfed.
        if {[regexp {^\s*[0-9]+(?:[.,][0-9]+)?\s*mm\s*$} $name]} continue

        foreach {aw ah} [list $fw $fh $fh $fw] {
            if {abs($aw - $tw) > $tol} continue
            if {abs($ah - $th) > $tol} continue
            set score [expr {abs($aw - $tw) + abs($ah - $th)}]

            # Several forms often report identical dimensions: a
            # QL-820NWB lists "62mm x 100mm" alongside the presets
            # "Versand-Etikett (Paeckchen)" and "Namensschild", all at
            # 62.0 x 99.8. Prefer the technical form -- the presets may
            # carry extra driver settings, and relying on the order in
            # which the driver happens to list them is fragile.
            if {![regexp -nocase {^ *[0-9]+(?:[.,][0-9]+)? *mm *(x *[0-9]+(?:[.,][0-9]+)? *mm|dia) *$} $name]} {
                set score [expr {$score + 0.01}]
            }

            if {$score < $bestScore} { set bestScore $score ; set best $name }
        }
    }
    return $best
}

# --------------------------------------------------------------------------
# _print_pdfium -- print through pdfiumtcl (Windows, GDI)
#
# Known limits compared with pdftocairo:
#   - Vector fidelity depends on the print mode. FPDF_PRINTMODE_EMF (the
#     default) lets the driver rasterise complex pages; only the
#     PostScript passthrough sends real vector data. For text and simple
#     graphics EMF is unremarkable, for transparency and blend modes it
#     is not.
#   - -cut is ignored (internal to the Brother driver, it lives in
#     dmDriverExtra). Route around it: savePrinterProfile /
#     usePrinterProfile.
#   - -silent has no effect: there is no child process whose output
#     could be suppressed. Failures always surface as Tcl errors.
# --------------------------------------------------------------------------
proc ::printlib::_print_pdfium {pdffile opts} {
    variable cfg

    if {[catch {package require pdfiumtcl} e]} {
        error "printlib (pdfium): pdfiumtcl not available: $e"
    }

    set printer [dict get $opts printer]
    if {$printer eq ""} {
        if {[catch {::pdfium::defaultprinter} printer]} {
            error "printlib (pdfium): no printer given and no system default"
        }
    }

    set a [list -printer $printer]

    # --- copies ----------------------------------------------------------
    set copies [dict get $opts copies]
    if {![string is integer -strict $copies] || $copies < 1} { set copies 1 }
    lappend a -copies $copies

    # --- page range: printlib counts from 1, pdfium from 0 ---------------
    set pages [dict get $opts pages]
    if {$pages ne ""} {
        if {[regexp {^(\d+)-(\d+)$} $pages -> f l]} {
            lappend a -from [expr {$f - 1}] -to [expr {$l - 1}]
        } elseif {[string is integer -strict $pages]} {
            lappend a -from [expr {$pages - 1}] -to [expr {$pages - 1}]
        } else {
            error "printlib (pdfium): invalid page range: $pages"
        }
    }

    # --- orientation -----------------------------------------------------
    set orientation [dict get $opts orientation]
    if {$orientation in {portrait landscape}} {
        lappend a -orientation $orientation
    }

    # --- duplex ----------------------------------------------------------
    set duplex [dict get $opts duplex]
    switch -- $duplex {
        long  - vertical   { lappend a -duplex long  }
        short - horizontal { lappend a -duplex short }
        off   - ""         { }
        default {
            error "printlib (pdfium): invalid duplex value: $duplex"
        }
    }

    # --- paper source ----------------------------------------------------
    set source [dict get $opts source]
    if {$source ne ""} { lappend a -source $source }

    # --- paper and scaling -----------------------------------------------
    #
    # Same precedence as in the pdftocairo backend:
    #   1. explicit paperw/paperh
    #   2. label format -> driver form, always 1:1
    #   3. ordinary paper + scale mode
    #
    set paper [dict get $opts paper]
    set pw    [dict get $opts paperw]
    set ph    [dict get $opts paperh]

    if {$pw ne "" && $ph ne ""} {
        lappend a -paperw $pw -paperh $ph -fit 0

    } elseif {$paper ne "" && ![catch {labelsize $paper}]} {
        # Label: resolve the form, and report a failure rather than
        # quietly ending up on the driver default.
        set form [_pdfiumFormForLabel $printer $paper $pdffile]
        if {$form eq ""} {
            set meta [labelsize $paper]
            error "printlib (pdfium): no driver form for $paper\
                   ([dict get $meta width_mm] mm) on '$printer' --\
                   available forms: ::pdfium::papers"
        }
        # Labels always print 1:1 -- any scaling shifts the output on
        # the tape.
        lappend a -paper $form -fit 0

    } else {
        if {$paper ne ""} { lappend a -paper $paper }

        set scale [dict get $opts scale]
        switch -- $scale {
            noscale - origsize - "" { lappend a -fit 0 }
            fit - expand - shrink - match - nocenter { lappend a -fit 1 }
            default { lappend a -fit 1 }
        }
    }

    # --- print mode ------------------------------------------------------
    # 0 = EMF. The PostScript passthrough (5) would be better in quality
    # but needs a PostScript-capable driver; on GDI printers nothing
    # would come out at all. Hence the conservative default.
    lappend a -mode 0

    lappend a -docname [file tail $pdffile]

    # --- print -----------------------------------------------------------
    set doc [::pdfium::open $pdffile]
    set rc [catch {::pdfium::print $doc {*}$a} res]
    catch {::pdfium::close $doc}

    if {$rc} { error "printlib (pdfium): $res" }
    return ""
}


# --------------------------------------------------------------------------
# 7. status -- add pdfium_ok
# --------------------------------------------------------------------------
#
#     set hasPdfium [_available pdfium]
#     ...
#         pdfium_ok      $hasPdfium \


# ==========================================================================
#  Examples
# ==========================================================================
#
#   package require printlib
#
#   # Starpack deployment: prefer pdfium
#   ::printlib::configure -pdfiumprefer 1
#   puts [::printlib::detect]              ;# -> pdfium (Windows)
#
#   # Ordinary printing
#   ::printlib::print invoice.pdf -printer "HP LaserJet" \
#       -paper a4 -duplex long -copies 2 -scale fit
#
#   # Label -- the form is resolved automatically
#   ::printlib::print label54.pdf -printer "Brother QL-820NWB" \
#       -paper DK-N55224
#
#   # Force a backend (e.g. to compare output quality)
#   ::printlib::print test.pdf -backend pdfium     -printer $p
#   ::printlib::print test.pdf -backend pdftocairo -printer $p
#
# ==========================================================================
#  ppd/Brother_QL-820NWB.pdfium
# ==========================================================================
#
#   # printlib printer configuration for pdfium
#   printer   "Brother QL-820NWB"
#   paper     DK-N55224
#   scale     noscale
#   copies    1
#
# ==========================================================================
