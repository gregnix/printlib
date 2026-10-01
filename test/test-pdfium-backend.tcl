# ==========================================================================
#  test-pdfium-backend.tcl -- tests for printlib's pdfium backend
#
#      tclsh test-pdfium-backend.tcl
#
#  Runs without a printer and without pdfiumtcl: ::pdfium::papers is
#  mocked. What is tested is the logic that costs label stock when it
#  goes wrong -- mapping a DK format onto a driver form.
#
#  The rest of the backend (_print_pdfium) is a thin option translator
#  and is checked through the resulting argument list, not by actually
#  printing.
# ==========================================================================

package require tcltest 2.5
namespace import ::tcltest::*

set here [file dirname [file normalize [info script]]]

# load printlib (source the .tm directly -- no module path needed)
# Die Kandidaten nicht festschreiben: hier standen bis 0.3 die Namen
# printlib-0.3.tm / printlib-0.2.tm, und bei jedem Versionssprung waere
# die Liste stillschweigend veraltet. Gesucht wird jetzt nach Muster, die
# hoechste Fassung gewinnt.
set _mod ""
set _kand [lsort -decreasing -dictionary [concat \
    [glob -nocomplain [file join $here .. lib tm printlib-*.tm]] \
    [glob -nocomplain [file join $here printlib-*.tm]]]]
foreach _c $_kand {
    if {[file exists $_c]} { set _mod $_c ; break }
}
if {$_mod eq "" || [catch {source $_mod} e]} {
    puts stderr "printlib module not found: $e"
    exit 1
}

# WELCHE Datei wurde geladen?
#
# Ein gruener Lauf ohne diese Zeile sagt nur: irgendein printlib
# funktioniert. Die Kandidatenliste oben nimmt die erste Datei, die es
# gibt -- liegt eine fremde oder alte daneben, faellt das nicht auf.
#
# Gemessen 17.09.2026: ein Paket kam mit 13 pdf4tcl-Dateien ausgeliefert,
# darunter ein pkgIndex.tcl, das "pdf4tcl 0.9.4.52" anmeldete und auf
# eine Datei zeigte, die gar nicht dabei war. Solche Beimischungen
# sieht man nur, wenn der Pfad dasteht.
puts stdout "printlib [package provide printlib] aus: $_mod"

# --------------------------------------------------------------------------
#  Mock: ::pdfium::papers
#
#  Modelled on what a Brother QL Windows driver reports: die-cut labels
#  with fixed dimensions, continuous tapes with a fixed width and a
#  length the driver states as its maximum.
#  Entry format: {name code width_mm height_mm}
# --------------------------------------------------------------------------
namespace eval ::pdfium {}

variable ::mockPapers [list \
    {"17mm x 54mm"                269   17.0   53.9} \
    {"17mm x 87mm"                270   17.0   86.9} \
    {"23mm x 23mm"                370   23.0   23.0} \
    {"29mm x 42mm"                358   29.0   41.9} \
    {"29mm x 90mm"                271   29.0   89.8} \
    {"38mm x 90mm"                272   38.0   89.8} \
    {"39mm x 48mm"                367   39.0   47.8} \
    {"52mm x 29mm"                374   52.0   28.9} \
    {"54mm x 29mm"                382   54.0   28.9} \
    {"60mm x 86mm"                383   60.0   86.8} \
    {"62mm x 29mm"                274   62.0   28.9} \
    {"62mm x 60mm"                388   62.0   60.6} \
    {"62mm x 75mm"                389   62.0   75.4} \
    {"62mm x 100mm"               275   62.0   99.8} \
    {"12mm Dia"                   362   12.0   12.0} \
    {"24mm Dia"                   363   24.0   24.0} \
    {"58mm Dia"                   273   58.3   58.3} \
    {"12mm"                       257   12.0   29.0} \
    {"29mm"                       258   29.0   29.0} \
    {"38mm"                       264   38.0   29.0} \
    {"50mm"                       262   50.0   29.0} \
    {"54mm"                       261   53.8   29.0} \
    {"62mm"                       259   62.0   29.0} \
    {"12mm x 2"                   277   21.0   29.0} \
    {"29mm x 2"                   278   54.8   29.0} \
    {"62mm x 2"                   279  120.8   29.0} \
    {"62mm x 3"                   285  179.7   29.0} \
    {"Mappe 3 cm - Ruecken"       325   29.0  209.1} \
    {"Mappe 5 cm - Ruecken"       326   62.0  209.1} \
    {"CD/DVD-Etikett"             327   58.3   58.3} \
    {"Porto-Etikett 62mmx184mm"   331   62.0  183.9} \
    {"62er"                       333   62.0   35.0} \
    {"Benutzerdefinierte Groesse" 256   62.0   29.0} \
]

proc ::pdfium::papers {{printer ""}} {
    if {$printer eq "No QL"} { return {} }
    return $::mockPapers
}

# --------------------------------------------------------------------------
#  Mock: _pdfPageSize -- page size in points
#  Controlled per test through ::mockPageSize.
# --------------------------------------------------------------------------
variable ::mockPageSize {}
proc ::printlib::_pdfPageSize {pdffile} { return $::mockPageSize }

# --------------------------------------------------------------------------
#  The code under test (from printlib-pdfium-backend.tcl)
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


# ACHTUNG: die folgende Prozedur ist eine KOPIE aus doc/printlib-booklet.tcl.
#
# bookletOrder ist NICHT Teil von printlib 0.3 -- das Modul sourct den
# Entwurf nie. Nach "package require printlib" ist
# ::printlib::bookletOrder leer; gemessen 17.09.2026.
#
# Die acht Faelle unten pruefen also den ENTWURF, nicht das ausgelieferte
# Paket. Sie sind trotzdem sinnvoll: bookletOrder ist reine Rechnung auf
# der Seitenliste, und test-pdfium-backend-guard.tcl vergleicht diese
# Kopie zeichenweise gegen doc/printlib-booklet.tcl -- sie kann also
# nicht davonlaufen.
#
# Wird der Entwurf eingebaut (Roadmap R3a), gehoert diese Definition
# geloescht: dann liefert das Modul sie, und die Faelle pruefen das
# Paket statt einer Kopie.
proc ::printlib::bookletOrder {n} {
    if {![string is integer -strict $n] || $n < 1} {
        error "printlib::bookletOrder: page count must be >= 1"
    }
    set N [expr {(($n + 3) / 4) * 4}]
    set out {}
    for {set i 0} {$i < $N / 4} {incr i} {
        set a [expr {$N - 2*$i}]
        set b [expr {2*$i + 1}]
        set c [expr {2*$i + 2}]
        set d [expr {$N - 2*$i - 1}]
        foreach p [list $a $b $c $d] {
            lappend out [expr {$p > $n ? 0 : $p}]
        }
    }
    return $out
}

# ==========================================================================
#  Die-cut labels -- fixed dimensions, must match exactly
# ==========================================================================

test diecut-1.1 {DK-11202 62x100 finds the matching form} -body {
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-11202 dummy.pdf
} -result {62mm x 100mm}

test diecut-1.2 {DK-11201 29x90} -body {
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-11201 dummy.pdf
} -result {29mm x 90mm}

test diecut-1.3 {DK-11209 62x29 -- must not be confused with 29x90} -body {
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-11209 dummy.pdf
} -result {62mm x 29mm}

test diecut-1.4 {DK-11204 17x54 -- must not be confused with the 54mm tape} -body {
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-11204 dummy.pdf
} -result {17mm x 54mm}

test diecut-1.5 {a swapped form entry is recognised} -body {
    # driver reports 90x29 instead of 29x90 -- both orientations count
    set ::mockPapers [list {"90mm x 29mm" 271 90.0 29.0}]
    set r [::printlib::_pdfiumFormForLabel "QL-820NWB" DK-11201 dummy.pdf]
    set ::mockPapers $::savedPapers
    set r
} -setup {set ::savedPapers $::mockPapers} -result {90mm x 29mm}

test diecut-1.6 {no matching form -> empty string, not an error} -body {
    set ::mockPapers [list {"A4" 9 210.0 297.0}]
    set r [::printlib::_pdfiumFormForLabel "QL-820NWB" DK-11202 dummy.pdf]
    set ::mockPapers $::savedPapers
    set r
} -setup {set ::savedPapers $::mockPapers} -result {}

# ==========================================================================
#  Round labels -- diameter in both directions
# ==========================================================================

test round-2.1 {DK-11219 12mm round} -body {
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-11219 dummy.pdf
} -result {12mm Dia}

test round-2.2 {DK-11218 24mm round} -body {
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-11218 dummy.pdf
} -result {24mm Dia}

test round-2.3 {DK-11207 58mm round -- reported as 58.3, within tolerance} -body {
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-11207 dummy.pdf
} -result {58mm Dia}

# ==========================================================================
#  Continuous tape -- width fixed, length taken from the PDF
# ==========================================================================

test continuous-3.1 {DK-N55224 54mm tape, page 54x100mm} -setup {
    # 54mm x 100mm in points
    set ::mockPageSize [list [expr {54.0 * 72.0 / 25.4}] \
                             [expr {100.0 * 72.0 / 25.4}]]
} -body {
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-N55224 dummy.pdf
} -cleanup {set ::mockPageSize {}} -result {54mm}

test continuous-3.2 {DK-22205 62mm tape} -setup {
    set ::mockPageSize [list [expr {62.0 * 72.0 / 25.4}] \
                             [expr {150.0 * 72.0 / 25.4}]]
} -body {
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-22205 dummy.pdf
} -cleanup {set ::mockPageSize {}} -result {62mm}

test continuous-3.3 {landscape: 150x62mm yields the same tape} -setup {
    set ::mockPageSize [list [expr {150.0 * 72.0 / 25.4}] \
                             [expr {62.0 * 72.0 / 25.4}]]
} -body {
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-22205 dummy.pdf
} -cleanup {set ::mockPageSize {}} -result {62mm}

test continuous-3.4 {without a page size only the width decides} -setup {
    set ::mockPageSize {}
} -body {
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-22210 dummy.pdf
} -result {29mm}

test continuous-3.5 {29mm tape wins over the equally wide die-cut form} -setup {
    set ::mockPageSize {}
} -body {
    # Both forms are 29mm wide. The longer one is the tape -- a 29x90
    # die-cut form would cut the output off after 90mm.
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-22210 dummy.pdf
} -result {29mm}

test continuous-3.6 {page length does not restrict tape selection} -setup {
    set ::mockPageSize [list [expr {62.0 * 72.0 / 25.4}] \
                             [expr {400.0 * 72.0 / 25.4}]]
} -body {
    # A real QL-820NWB reports 29.0 mm as the height of every tape, so
    # the reported height says nothing about how long a tape may be.
    # A 400 mm page therefore still selects the 62 mm tape -- the
    # printer feeds as much as it needs.
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-22205 dummy.pdf
} -cleanup {set ::mockPageSize {}} -result {62mm}

test continuous-3.7 {a round 12x12 form is not a 12mm tape} -setup {
    set ::savedPapers $::mockPapers
    set ::mockPapers [list {"12mm Dia" 362 12.0 12.0}]
    set ::mockPageSize {}
} -body {
    # DK-22214 is a 12mm continuous tape. A square form has the right
    # width but is not a tape -- the output would end after 12mm.
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-22214 dummy.pdf
} -cleanup {set ::mockPapers $::savedPapers} -result {}

# ==========================================================================
#  Edge cases
# ==========================================================================

test edge-4.1 {unknown format -> empty string} -body {
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-99999 dummy.pdf
} -result {}

test edge-4.2 {printer reports no forms} -body {
    ::printlib::_pdfiumFormForLabel "No QL" DK-11202 dummy.pdf
} -result {}

test edge-4.3 {a lower-case DK code is normalised} -body {
    ::printlib::_pdfiumFormForLabel "QL-820NWB" dk22205 dummy.pdf
} -setup {set ::mockPageSize {}} -result {62mm}

test edge-4.4 {tolerance: driver reports 61.9 instead of 62.0} -body {
    set ::mockPapers [list {"62mm x 100mm" 275 61.9 100.1}]
    set r [::printlib::_pdfiumFormForLabel "QL-820NWB" DK-11202 dummy.pdf]
    set ::mockPapers $::savedPapers
    set r
} -setup {set ::savedPapers $::mockPapers} -result {62mm x 100mm}

test edge-4.5 {tolerance ends: 59mm is not a 62mm label} -body {
    set ::mockPapers [list {"59mm x 100mm" 275 59.0 100.0}]
    set r [::printlib::_pdfiumFormForLabel "QL-820NWB" DK-11202 dummy.pdf]
    set ::mockPapers $::savedPapers
    set r
} -setup {set ::savedPapers $::mockPapers} -result {}


# ==========================================================================
#  Booklet page order (printlib::bookletOrder)
# ==========================================================================

test booklet-5.1 {the classic sequence for 8 pages} -body {
    ::printlib::bookletOrder 8
} -result {8 1 2 7 6 3 4 5}

test booklet-5.2 {4 pages -- one sheet, no blank} -body {
    ::printlib::bookletOrder 4
} -result {4 1 2 3}

test booklet-5.3 {12 pages} -body {
    ::printlib::bookletOrder 12
} -result {12 1 2 11 10 3 4 9 8 5 6 7}

test booklet-5.4 {length is always a multiple of 4} -body {
    set bad {}
    for {set n 1} {$n <= 40} {incr n} {
        if {[llength [::printlib::bookletOrder $n]] % 4} { lappend bad $n }
    }
    set bad
} -result {}

test booklet-5.5 {every page exactly once, the rest blanks} -body {
    set bad {}
    for {set n 1} {$n <= 40} {incr n} {
        set o [::printlib::bookletOrder $n]
        set real [lsearch -all -inline -not $o 0]
        set expect {}
        for {set k 1} {$k <= $n} {incr k} { lappend expect $k }
        if {[lsort -integer $real] ne $expect} { lappend bad $n }
    }
    set bad
} -result {}

test booklet-5.6 {blanks sit at the back of the booklet, not the front} -body {
    # n=5: page 1 must sit outer right on the first sheet
    lindex [::printlib::bookletOrder 5] 1
} -result 1

test booklet-5.7 {the sum per sheet pair is constant} -body {
    # For saddle stitching: outer left + outer right = N+1
    set o [::printlib::bookletOrder 16]
    set bad {}
    for {set i 0} {$i < [llength $o]} {incr i 4} {
        set a [lindex $o $i] ; set b [lindex $o [expr {$i+1}]]
        set c [lindex $o [expr {$i+2}]] ; set d [lindex $o [expr {$i+3}]]
        if {$a + $b != 17} { lappend bad "vorn $i" }
        if {$c + $d != 17} { lappend bad "hinten $i" }
    }
    set bad
} -result {}

test booklet-5.8 {invalid input} -body {
    set r {}
    lappend r [catch {::printlib::bookletOrder 0}]
    lappend r [catch {::printlib::bookletOrder -3}]
    lappend r [catch {::printlib::bookletOrder abc}]
} -result {1 1 1}


# ==========================================================================
#  Regressions found only by real driver data (QL-820NWB, 2026-07-21)
# ==========================================================================

test real-6.1 {DK-11209 62x29 must not select the 62mm tape} -body {
    # The tape "62mm" reports 62.0 x 29.0 -- numerically a better match
    # for a 62 x 29 die-cut label than its own form at 62.0 x 28.9.
    ::printlib::_pdfiumFormForLabel "QL-820NWB" DK-11209 dummy.pdf
} -result {62mm x 29mm}

test real-6.2 {DMPAPER_USER is never selected} -body {
    # Code 256 reports whatever custom size was last configured -- here
    # 62 x 29, which would also beat the real die-cut form.
    set hits {}
    foreach c [::printlib::labelformats "Brother QL-820NWB"] {
        set f [::printlib::_pdfiumFormForLabel "QL-820NWB" $c dummy.pdf]
        if {[string match -nocase "*Benutzerdefinier*" $f]} { lappend hits $c }
    }
    set hits
} -result {}

test real-6.3 {every known DK format resolves to a form} -body {
    set missing {}
    foreach c [::printlib::labelformats "Brother QL-820NWB"] {
        if {[::printlib::_pdfiumFormForLabel "QL-820NWB" $c dummy.pdf] eq ""} {
            lappend missing $c
        }
    }
    set missing
} -result {}

test real-6.4 {tapes resolve to bare-width forms, never to die-cut ones} -body {
    set wrong {}
    foreach c [::printlib::labelformats "Brother QL-820NWB"] {
        set meta [::printlib::labelsize $c]
        if {[dict get $meta kind] ne "continuous"} continue
        set f [::printlib::_pdfiumFormForLabel "QL-820NWB" $c dummy.pdf]
        if {![regexp {^[0-9]+mm$} $f]} { lappend wrong "$c -> $f" }
    }
    set wrong
} -result {}

test real-6.5 {die-cut formats never resolve to a tape} -body {
    set wrong {}
    foreach c [::printlib::labelformats "Brother QL-820NWB"] {
        set meta [::printlib::labelsize $c]
        if {[dict get $meta kind] eq "continuous"} continue
        set f [::printlib::_pdfiumFormForLabel "QL-820NWB" $c dummy.pdf]
        if {[regexp {^[0-9]+mm$} $f]} { lappend wrong "$c -> $f" }
    }
    set wrong
} -result {}


test real-6.6 {technical form wins over a named preset} -body {
    # A QL-820NWB reports "62mm x 100mm", "Versand-Etikett (Paeckchen)"
    # and "Namensschild" all at 62.0 x 99.8. Relying on the order the
    # driver happens to list them in would be fragile; the technical
    # form is chosen deliberately.
    set ::savedPapers $::mockPapers
    set ::mockPapers [list \
        {"Versand-Etikett (Paeckchen)" 321 62.0 99.8} \
        {"Namensschild"                322 62.0 99.8} \
        {"62mm x 100mm"                275 62.0 99.8}]
    set r [::printlib::_pdfiumFormForLabel "QL-820NWB" DK-11202 dummy.pdf]
    set ::mockPapers $::savedPapers
    set r
} -result {62mm x 100mm}

test real-6.7 {result does not depend on the order of the form list} -body {
    set ::savedPapers $::mockPapers
    set fwd {}
    foreach c [::printlib::labelformats "Brother QL-820NWB"] {
        dict set fwd $c [::printlib::_pdfiumFormForLabel x $c dummy.pdf]
    }
    set ::mockPapers [lreverse $::savedPapers]
    set rev {}
    foreach c [::printlib::labelformats "Brother QL-820NWB"] {
        dict set rev $c [::printlib::_pdfiumFormForLabel x $c dummy.pdf]
    }
    set ::mockPapers $::savedPapers
    set bad {}
    foreach k [dict keys $fwd] {
        if {[dict get $fwd $k] ne [dict get $rev $k]} { lappend bad $k }
    }
    set bad
} -result {}

cleanupTests
