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

printlib::print demo-001.pdf \
    -printer "Brother QL-820NWB" \
    -paper   [printlib::labelpaper "DK-22205"] \
    -scale   origsize