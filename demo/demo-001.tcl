# Modulpfad auf den Baum, in dem diese Datei liegt.
#
# Ohne das bricht die Demo mit "can't find package printlib" ab, sobald
# printlib nicht installiert ist -- also genau nach dem Auspacken des
# Archivs. Die Testdateien machen es seit jeher selbst; die Demos nicht.
# Gemessen 17.09.2026.
::tcl::tm::path add [file join [file dirname [file dirname \
        [file normalize [info script]]]] lib tm]

package require printlib
package require pdf4tcl

set lbl [printlib::labelsize "DK-22205"]
set pdf [::pdf4tcl::new %AUTO% -paper [list [dict get $lbl width_pt] 71] -margin 0 -orient 0]
$pdf startPage
$pdf setFont 15 Helvetica
$pdf text "Karl Mustermann" -x 5 -y 50
$pdf text "Hauptstr 1"      -x 5 -y 38
$pdf text "12345 Berlin"    -x 5 -y 26
$pdf write -file demo-001.pdf
$pdf destroy

# ACHTUNG: ab hier wird WIRKLICH gedruckt.
#
# Ohne Drucksystem bricht die Zeile mit "kein Druckbackend verfuegbar"
# ab -- das ist kein Fehler der Demo, sondern die Umgebung. Wer nur die
# PDF sehen will: bis hierher laufen lassen, demo-001.pdf liegt dann da.
#
# Gemessen 17.09.2026 auf einer Maschine ohne lp: Abbruch an dieser
# Zeile, PDF vorher vollstaendig geschrieben.
if {[printlib::detect] eq "none"} {
    puts "kein Druckbackend -- demo-001.pdf geschrieben, nicht gedruckt"
    exit 0
}
printlib::print demo-001.pdf \
    -printer "Brother QL-820NWB" \
    -paper   [printlib::labelpaper "DK-22205"] \
    -scale   origsize