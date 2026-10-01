#!/usr/bin/env tclsh
# make-testpdfs.tcl
# Erzeugt Test-PDFs in verschiedenen Groessen fuer printlib scale-Demo

package require pdf4tcl

proc makePdf {filename paper label} {
    set pdf [pdf4tcl::new %AUTO% -paper $paper -compress 0]
    $pdf startPage

    set pw [lindex [$pdf getPageSize] 0]
    set ph [lindex [$pdf getPageSize] 1]

    # Rahmen
    $pdf setStrokeColor 0 0 0
    $pdf setLineWidth 2
    $pdf rectangle 10 10 [expr {$pw-20}] [expr {$ph-20}]

    # Kreuz in der Mitte
    $pdf setLineWidth 0.5
    $pdf setStrokeColor 0.7 0.7 0.7
    $pdf line [expr {$pw/2}] 20 [expr {$pw/2}] [expr {$ph-20}]
    $pdf line 20 [expr {$ph/2}] [expr {$pw-20}] [expr {$ph/2}]

    # Ecken markieren
    $pdf setStrokeColor 1 0 0
    $pdf setLineWidth 1.5
    foreach {cx cy} [list 10 10  [expr {$pw-10}] 10  10 [expr {$ph-10}]  [expr {$pw-10}] [expr {$ph-10}]] {
        $pdf line [expr {$cx-8}] $cy [expr {$cx+8}] $cy
        $pdf line $cx [expr {$cy-8}] $cx [expr {$cy+8}]
    }

    # Beschriftung
    $pdf setFont 14 Helvetica-Bold
    $pdf setFillColor 0 0 0
    $pdf text $label -x 20 -y [expr {$ph-35}]

    $pdf setFont 10 Helvetica
    $pdf text "Breite: [format %.1f $pw] pt  ([format %.0f [expr {$pw/2.8346}]] mm)" \
        -x 20 -y [expr {$ph-52}]
    $pdf text "Hoehe:  [format %.1f $ph] pt  ([format %.0f [expr {$ph/2.8346}]] mm)" \
        -x 20 -y [expr {$ph-65}]

    # Diagonale (zeigt Skalierung deutlich)
    $pdf setStrokeColor 0 0 1
    $pdf setLineWidth 1
    $pdf line 10 10 [expr {$pw-10}] [expr {$ph-10}]
    $pdf line [expr {$pw-10}] 10 10 [expr {$ph-10}]

    $pdf endPage
    $pdf write -file $filename
    $pdf destroy
    puts "Erzeugt: $filename  ($paper)"
}

# A4 (210x297mm) — Referenz
makePdf "test_a4.pdf"    a4     "A4  210x297mm"

# A5 (148x210mm) — kleiner als A4
makePdf "test_a5.pdf"    a5     "A5  148x210mm"

# A3 (297x420mm) — groesser als A4
makePdf "test_a3.pdf"    a3     "A3  297x420mm"

# Visitenkarte (85x54mm) — sehr klein
set bc_w [expr {85 * 2.8346}]
set bc_h [expr {54 * 2.8346}]
set pdf [pdf4tcl::new %AUTO% -paper [list $bc_w $bc_h] -compress 0]
$pdf startPage
set pw [lindex [$pdf getPageSize] 0]
set ph [lindex [$pdf getPageSize] 1]
$pdf setStrokeColor 0 0 0
$pdf setLineWidth 2
$pdf rectangle 5 5 [expr {$pw-10}] [expr {$ph-10}]
$pdf setStrokeColor 1 0 0
$pdf setLineWidth 1
$pdf line 5 5 [expr {$pw-5}] [expr {$ph-5}]
$pdf line [expr {$pw-5}] 5 5 [expr {$ph-5}]
$pdf setFont 8 Helvetica-Bold
$pdf setFillColor 0 0 0
$pdf text "Visitenkarte 85x54mm" -x 8 -y [expr {$ph-18}]
$pdf endPage
$pdf write -file "test_visitenkarte.pdf"
$pdf destroy
puts "Erzeugt: test_visitenkarte.pdf  (85x54mm)"

# Etikett Brother QL (62x29mm)
set ql_w [expr {62 * 2.8346}]
set ql_h [expr {29 * 2.8346}]
set pdf [pdf4tcl::new %AUTO% -paper [list $ql_w $ql_h] -compress 0]
$pdf startPage
set pw [lindex [$pdf getPageSize] 0]
set ph [lindex [$pdf getPageSize] 1]
$pdf setStrokeColor 0 0 0
$pdf setLineWidth 1.5
$pdf rectangle 3 3 [expr {$pw-6}] [expr {$ph-6}]
$pdf setStrokeColor 0 0.6 0
$pdf line 3 3 [expr {$pw-3}] [expr {$ph-3}]
$pdf line [expr {$pw-3}] 3 3 [expr {$ph-3}]
$pdf setFont 7 Helvetica-Bold
$pdf setFillColor 0 0 0
$pdf text "Etikett 62x29mm (Brother QL)" -x 5 -y [expr {$ph-14}]
$pdf endPage
$pdf write -file "test_etikett_ql.pdf"
$pdf destroy
puts "Erzeugt: test_etikett_ql.pdf  (62x29mm)"

puts "\nFertig. PDFs zum Testen:"
puts "  test_a4.pdf          -- A4, passt auf A4"
puts "  test_a5.pdf          -- A5, kleiner als A4"
puts "  test_a3.pdf          -- A3, groesser als A4"
puts "  test_visitenkarte.pdf -- 85x54mm, sehr klein"
puts "  test_etikett_ql.pdf  -- 62x29mm (Brother QL)"
puts ""
puts "Testen:"
puts "  noscale: pdftocairo -pdf -paper A4              test_a5.pdf out.pdf"
puts "  expand:  pdftocairo -pdf -paper A4 -expand      test_a5.pdf out.pdf"
puts "  shrink:  pdftocairo -pdf -paper A4 -noshrink    test_a3.pdf out.pdf"
puts "  match:   pdftocairo -pdf -paper match           test_visitenkarte.pdf out.pdf"
