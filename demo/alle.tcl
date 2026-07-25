package provide app-alle 1.0



package require Tk
package require BWidget
package require Wcb
package require twapi_com
# package require fileutil
proc pfelderloeschen {artikel} {
global etikettARR
set foraVAR ""
foreach foraVAR { gewicht zusatz1 zusatz2 artikel dose datum kornjegramm jahr klasse} {
set etikettARR($foraVAR) ""
 }
set foraVAR ""
focus -force $artikel.e
update
}

proc ausdrucken {} {
global etikettARR
global anzahl
set brother [twapi::comobj bpac.Document]

## Initialierung der Etikett Vorlage
# Name des Etiketts f\xfcr ql550 Drucker (b-PAC 3 / .lbx-Format)
set namelbl "550-6238.lbl"

set dirlbl "[string map { / \\} [pwd]]\\$namelbl"
puts [$brother Open $dirlbl]

## Ende Initialierung

# set anzahl 1
$brother settext 0 "$etikettARR(klasse)"
$brother settext 1 "$etikettARR(jahr)"
$brother settext 2 "$etikettARR(kornjegramm)"
$brother settext 3 "$etikettARR(datum)"
$brother settext 4 "$etikettARR(dose)"
$brother settext 5 "$etikettARR(zusatz2)"
$brother settext 6 "$etikettARR(zusatz1)"
$brother settext 7 "$etikettARR(artikel)"
$brother settext 8 "$etikettARR(gewicht)"
$brother doPrint 0 1,$anzahl
$brother close

$brother -destroy
}


proc saatetikett {} {

global etikettARR
global anzahl
#set top .saatetikett
#if {[winfo exists $top]} {return}
# toplevel $top
#wm title $top "Blanko Etikett"
#wm   geometry  $top +200+0

set top ""

set artikel [LabelEntry $top.artikel -label "Artikel   " -textvariable etikettARR(artikel) ]
wcb::callback $artikel.e before insert {wcb::checkEntryLen 24}
set gewicht [LabelEntry $top.gewicht -label "Gewicht" -textvariable etikettARR(gewicht) ] 
wcb::callback $gewicht.e before insert {wcb::checkEntryLen 12}
set zusatz1 [LabelEntry $top.zusatz1 -label "Zusatz 1" -textvariable etikettARR(zusatz1) ]
wcb::callback $zusatz1.e before insert {wcb::checkEntryLen 11}
set zusatz2 [LabelEntry $top.zusatz2 -label "Zusatz 2" -textvariable etikettARR(zusatz2) ]
wcb::callback $zusatz2.e before insert {wcb::checkEntryLen 11}
set dose [LabelEntry $top.dose -label "Dose     " -textvariable etikettARR(dose)]
wcb::callback $dose.e before insert {wcb::checkEntryLen 25}
set datum [LabelEntry $top.datum -label "Datum" -textvariable etikettARR(datum)]
set kornjegramm [LabelEntry $top.kornjegramm -label "KornJeGramm" -textvariable etikettARR(kornjegramm)]
wcb::callback $kornjegramm.e before insert {wcb::checkEntryLen 13}
set jahr [LabelEntry $top.jahr -label "Jahr" -textvariable etikettARR(jahr)]
set klasse [LabelEntry $top.klasse -label "Klasse" -textvariable etikettARR(klasse)]
wcb::callback $klasse.e before insert {wcb::checkEntryLen 11}

set btnloeschen [Button $top.btnloeschen -text "L\xf6schen (F8)" -command [list pfelderloeschen $artikel]]
set btndrucken [Button $top.btndrucken -text "Drucken (F5)" -command {ausdrucken}]
set btnexit [Button $top.btnexit -text "Exit (F10)" -command [list exit]]
#set btnexit [Button $top.btnexit -text "Exit" -command [list destroy $top]]


grid $artikel -column 0 -row 0 -columnspan 3 -stick snew
grid $gewicht -column 0 -row 1 -columnspan 2 -rowspan 2 -stick snew
grid $zusatz1 -column 2 -row 1 -stick snew
grid $zusatz2 -column 2 -row 2 -stick snew
grid $dose -column 0 -row 3 -columnspan 2 -stick snew
grid $datum -column 2 -row 3 -stick snew
grid $kornjegramm -column 0 -row 4 -stick snew 
grid $jahr -column 1 -row 4 -stick snew 
grid $klasse -column 2 -row 4 -stick snew 

grid $btnloeschen -column 0 -row 6 -stick snew
grid $btndrucken -column 1 -row 6 -stick snew
grid $btnexit -column 2 -row 6 -stick snew
# wm attributes . -toolwindow 1
focus -force $artikel.e
}

tk appname "Blanko etikett ver 1.0 / 2009"
wm   geometry  . +0+0


bind all <Control-Alt-d> {console show; console title debug}




## Initialsierungen
# etikettARR Array 
set foraVAR ""
foreach foraVAR { gewicht zusatz1 zusatz2 artikel dose datum kornjegramm jahr klasse} {
set etikettARR($foraVAR) ""
 }
set foraVAR ""

set anzahl 1

saatetikett

bind all <F8> {
pfelderloeschen .artikel
}

bind all <F5> {
ausdrucken
}

bind all <F10> {
exit
}
