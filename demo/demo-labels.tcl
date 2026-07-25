#!/usr/bin/env tclsh
# demo-labels.tcl
#
# Demonstriert die printlib-Etiketten-API.
# Funktioniert standalone -- braucht keinen echten Brother-Drucker.

package require printlib   ;# 0.2 oder neuer

puts "=== Welche Etikettendrucker werden erkannt? ==="
foreach p {
    "Brother QL-810W"
    "Brother QL-1110NWB"
    "Brother QL-820NWB"
    "Brother QL-700"
    "Dymo LabelWriter 450"
    "Zebra ZT230"
    "HP LaserJet"
    "PDF"
} {
    puts [format "  %-22s -> isLabelPrinter %s   model=%s   class=%s" \
        $p \
        [printlib::isLabelPrinter $p] \
        [printlib::_qlModelFromPrinter $p] \
        [printlib::_qlModelClass $p]]
}
puts ""

puts "=== Brother QL-810W: alle verfuegbaren Formate ==="
foreach dk [printlib::labelformats "Brother QL-810W"] {
    set s [printlib::labelsize $dk]
    set kind [dict get $s kind]
    set desc [dict get $s desc]
    if {$kind eq "die_cut"} {
        set dim "[dict get $s width_mm]x[dict get $s height_mm] mm"
    } elseif {$kind eq "round"} {
        set dim "[dict get $s diameter_mm] mm rund"
    } else {
        set dim "[dict get $s width_mm] mm endlos"
    }
    puts [format "  %-10s %-18s %s" $dk $dim $desc]
}
puts ""

puts "=== Nur Endlos-Etiketten ==="
foreach dk [printlib::labelformats "Brother QL-810W" kind continuous] {
    set s [printlib::labelsize $dk]
    puts [format "  %-10s %-3s mm  ql_id=%-6s %s" \
        $dk [dict get $s width_mm] [dict get $s ql_id] [dict get $s desc]]
}
puts ""

puts "=== Brother-CUPS-Mediagroessen ==="
foreach dk {DK-22205 DK-N55224 DK-11201 DK-11247 DK-22251} {
    puts "  $dk -> lp -o media=[printlib::labelpaper $dk]"
}
puts ""

puts "=== Beispiel: 62mm Endlos-Etikett 200pt lang vorbereiten ==="
set s [printlib::labelsize "DK-22205"]
puts "  Breite:           [dict get $s width_mm] mm = [dict get $s width_pt] pt"
puts "  Rollenlaenge:     [dict get $s length_m] m"
puts "  Material:         [dict get $s material]"
puts "  Klebe-Eigenschaft: [dict get $s adhesion]"
puts "  brother_ql ID:    [dict get $s ql_id]   ;# fuer Python brother_ql -l ..."
puts "  CUPS-Mediaaname:  [printlib::labelpaper {DK-22205}]"
puts ""

puts "=== Welche Formate sind QL-Modell-spezifisch? ==="
puts "  Large-only (QL-1050+):    [printlib::labelformats {Brother QL-1110NWB} model_class large]"
puts "  Two-color (QL-800+):      [printlib::labelformats {Brother QL-810W} model_class two_color]"
puts ""

puts "=== Druckaufruf (lp-Backend) ==="
puts "  printlib::print etikett.pdf -printer \"Brother QL-810W\" \\"
puts "      -paper [printlib::labelpaper DK-22205] -scale origsize"
