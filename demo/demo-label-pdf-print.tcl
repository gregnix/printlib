#!/usr/bin/env tclsh
# demo-label-pdf-print.tcl
#
# Kompletter Workflow: Etiketten-PDF erstellen und auf Brother QL drucken.
#
# Setzt voraus:
#   - printlib 0.2 (im tm-Pfad)
#   - pdf4tcl (fuer PDF-Erstellung)
#   - CUPS + Brother CUPS-Treiber fuer den QL (Linux)
#     bzw. Brother-Windows-Treiber + pdftocairo (Windows)
#
# Aufrufbeispiel:
#   tclsh demo-label-pdf-print.tcl "Brother QL-810W" DK-22205 \
#         "Karl Mustermann\nHauptstr 1\n12345 Berlin"

package require printlib    ;# 0.2 oder neuer
package require pdf4tcl     ;# fuer PDF-Erstellung

# -------------------------------------------------------------------------
# Argumente
# -------------------------------------------------------------------------
if {[llength $argv] < 2} {
    puts stderr "Aufruf: $argv0 <drucker> <dk-code> ?text?"
    puts stderr ""
    puts stderr "Drucker-Argument darf ein Substring sein -- 'QL-820NWB' wird"
    puts stderr "z.B. zu 'Brother QL-820NWB' (Windows) oder"
    puts stderr "'Brother_QL-820NWB_IPP' (Linux) aufgeloest."
    puts stderr ""
    puts stderr "Beispiel:"
    puts stderr "  $argv0 QL-820NWB DK-22205 \"Hallo Welt\""
    puts stderr ""
    puts stderr "Bekannte Drucker:"
    foreach p [printlib::printerlist] {
        if {[printlib::isLabelPrinter $p]} {
            puts stderr "  $p"
        }
    }
    exit 1
}

# Druckername aufloesen -- akzeptiert plattform-unabhaengiges Pattern
set printerArg [lindex $argv 0]
if {[catch {set printer [printlib::resolvePrinter $printerArg]} err]} {
    puts stderr "Fehler: $err"
    exit 1
}
if {$printer ne $printerArg} {
    puts "Drucker '$printerArg' aufgeloest zu '$printer'"
}
set dkcode  [lindex $argv 1]
set text    [expr {[llength $argv] >= 3 ? [lindex $argv 2] : "Test-Etikett"}]

# -------------------------------------------------------------------------
# Etiketten-Maße holen
# -------------------------------------------------------------------------
if {[catch {set lbl [printlib::labelsize $dkcode]} err]} {
    puts stderr "Fehler: $err"
    puts stderr ""
    puts stderr "Verfuegbare Formate fuer '$printer':"
    foreach f [printlib::labelformats $printer] {
        puts stderr "  $f"
    }
    exit 1
}

# Seitengroesse in Punkten bestimmen
set kind [dict get $lbl kind]
switch -- $kind {
    die_cut {
        # Feste Groesse: width x height in mm
        set w_pt [dict get $lbl width_pt]
        set h_pt [dict get $lbl height_pt]
        set descMode "[dict get $lbl width_mm] x [dict get $lbl height_mm] mm (Die-Cut)"
    }
    continuous {
        # Endlos: Breite fix, Hoehe frei waehlbar.
        # Hier: 25 mm pro Etikett als Standard.
        set w_pt [dict get $lbl width_pt]
        set h_pt [expr {round(25 * 2.8346)}]
        set descMode "[dict get $lbl width_mm] mm endlos (25 mm Etikett-Hoehe)"
    }
    round {
        # Rund: quadratische Bounding-Box
        set w_pt [dict get $lbl diameter_pt]
        set h_pt $w_pt
        set descMode "[dict get $lbl diameter_mm] mm rund"
    }
}

puts "Etikett vorbereiten:"
puts "  DK-Code:        $dkcode"
puts "  Beschreibung:   [dict get $lbl desc]"
puts "  Format:         $descMode"
puts "  Seitengroesse:  $w_pt x $h_pt pt"
puts "  CUPS-Mediaaname: [printlib::labelpaper $dkcode]"
puts ""

# -------------------------------------------------------------------------
# PDF erstellen
# -------------------------------------------------------------------------
set tmpdir [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}]
set pdfPath [file join $tmpdir "label-[clock seconds].pdf"]

set pdf [::pdf4tcl::new %AUTO% \
    -paper   [list $w_pt $h_pt] \
    -margin  0 \
    -orient  true]
$pdf startPage

# Text positionieren.
# pdf4tcl-Default: -orient true -> Origin OBEN links, y waechst nach unten.
# Erste Zeile beginnt 12 pt unter dem oberen Rand (= ca. eine Font-Hoehe).
# pdf4tcl::setFont nimmt erst Size, dann Fontname (nicht umgekehrt!).
$pdf setFont 10 Helvetica
set yPos 12
foreach line [split $text "\n"] {
    $pdf text $line -x 5 -y $yPos
    incr yPos 12        ;# naechste Zeile WEITER UNTEN (y waechst)
}

# Bei runden Etiketten: kleiner Hilfskreis als Schnittlinie
if {$kind eq "round"} {
    set r  [expr {$w_pt / 2.0 - 1}]
    set cx [expr {$w_pt / 2.0}]
    set cy [expr {$h_pt / 2.0}]
    $pdf circle $cx $cy $r
}

$pdf write -file $pdfPath
$pdf destroy

puts "PDF erstellt: $pdfPath ([file size $pdfPath] Bytes)"
puts ""

# -------------------------------------------------------------------------
# Drucken
# -------------------------------------------------------------------------
puts "Drucke auf '$printer'..."
puts "  printlib::print $pdfPath \\"
puts "      -printer \"$printer\" \\"
puts "      -paper [printlib::labelpaper $dkcode] \\"
puts "      -scale origsize"
puts ""

if {[catch {
    printlib::print $pdfPath \
        -printer $printer \
        -paper   [printlib::labelpaper $dkcode] \
        -scale   origsize
} err]} {
    puts stderr "Druckfehler: $err"
    exit 1
}

puts "OK -- Druckauftrag gesendet."
puts ""
puts "PDF aufraeumen? (Strg+C zum Behalten, Enter zum Loeschen)"
gets stdin
file delete $pdfPath
puts "PDF geloescht."
