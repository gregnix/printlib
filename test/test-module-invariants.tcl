# ==========================================================================
#  test-module-invariants.tcl -- was ohne Drucker gelten muss
#
#      tclsh test-module-invariants.tcl
#
#  Braucht kein Drucksystem, kein pdfiumtcl und keine Anzeige. Geprueft
#  wird, was in zwei Lesungen (17.09.2026) jeweils von Hand nachgemessen
#  wurde -- damit es niemand ein drittes Mal tun muss.
# ==========================================================================

package require tcltest 2.5
namespace import ::tcltest::*

set here [file dirname [file normalize [info script]]]
set root [file dirname $here]

::tcl::tm::path add [file join $root lib tm]
package require printlib

# WELCHE Datei wurde geladen? Siehe test-pdfium-backend.tcl.
puts stdout "printlib [package provide printlib] aus:\
        [lindex [package ifneeded printlib [package provide printlib]] end]"


# --------------------------------------------------------------------------
#  1. Die Fassungsnummer steht nur an einer Stelle
#
#  Bis 17.09.2026 fuehrte status die Nummer ein zweites Mal, fest als
#  "0.2" -- waehrend package provide 0.3 sagte. Wer status auswertete,
#  bekam die falsche Fassung.
# --------------------------------------------------------------------------

test inv-version-1.0 {status version kommt aus package provide} -body {
    expr {[dict get [printlib::status] version] eq [package provide printlib]}
} -result 1


# --------------------------------------------------------------------------
#  2. Die Backend-Kette unter Unix
#
#  known nennt alle vier Backends; detect darf unter Unix nur lp oder
#  none liefern -- die Registry gibt dort nichts anderes frei. Faellt
#  dieser Fall, hat jemand pdftocairo oder pdfium in die Unix-Kette
#  gehaengt, und das gehoert gemessen, nicht angenommen.
# --------------------------------------------------------------------------

test inv-backends-1.0 {known nennt die vier Backends} -body {
    lsort [printlib::known]
} -result {lp pdfium pdftocairo sumatra}

test inv-backends-1.1 {detect gibt unter Unix nur lp oder none} \
        -constraints unix -body {
    expr {[printlib::detect] in {lp none}}
} -result 1

# 1.1 prueft den auto-Weg -- also den, der schon ging. Der andere Weg lief
# an der Registry vorbei: wer "-backend pdftocairo" sagte, bekam es unter
# Linux auch. Gemessen am 30.09.2026 unter Debian:
#
#   $ pdftocairo -h | grep -c '^  -print'   -> 0   (kann nicht drucken)
#   % printlib::_available pdftocairo       -> 1   (bis 0.3)
#
# Der naechste print scheitert dann mit einer Meldung, die nicht sagt warum.
test inv-backends-1.2 {ein ausdruecklich genanntes Backend gilt die Registry auch} \
        -constraints unix -setup {
    set alt [dict get [set ::printlib::cfg] backend]
} -body {
    printlib::configure -backend pdftocairo
    if {[catch {printlib::detect} be]} { set be abgewiesen }
    expr {$be ne "pdftocairo"}
} -cleanup {
    printlib::configure -backend $alt
} -result 1

test inv-backends-1.3 {_available folgt der Registry, nicht der Binary} \
        -constraints unix -body {
    # Auch dann, wenn pdftocairo im PATH liegt -- hier tut es das.
    list [printlib::_available pdftocairo] [printlib::_available sumatra] \
         [printlib::_available pdfium]
} -result {0 0 0}


# --------------------------------------------------------------------------
#  3. Booklet ist NICHT im Modul
#
#  bookletOrder und makeBooklet liegen als Entwurf unter doc/; das Modul
#  sourct sie nie. test-pdfium-backend.tcl traegt eine Kopie und prueft
#  den Entwurf -- das ist gewollt und dort vermerkt.
#
#  WIRD DER ENTWURF EINGEBAUT (Roadmap R3a), FAELLT DIESER FALL. Genau
#  dann gehoert die Kopie aus test-pdfium-backend.tcl geloescht und der
#  Guard auf das Modul umgebogen.
#
#  FRIST Maerz 2027 (gesetzt 17.09.2026): wird bis dahin kein Booklet
#  gebraucht, fallen Entwurf, Kopie, diese beiden Faelle und R3a weg.
# --------------------------------------------------------------------------

test inv-booklet-1.0 {bookletOrder ist nicht Teil des Moduls} -body {
    llength [info commands ::printlib::bookletOrder]
} -result 0

test inv-booklet-1.1 {makeBooklet ist nicht Teil des Moduls} -body {
    llength [info commands ::printlib::makeBooklet]
} -result 0

# --------------------------------------------------------------------------
#  4. present und can_print sind zwei verschiedene Fragen
#
#  Bis 17.09.2026 hiessen beide "_ok". Unter Linux meldete pdftocairo_ok
#  1, weil `pdftocairo -v` antwortet -- gedruckt haette es nie, weil die
#  Registry dort nur lp freigibt.
#
#  can_print folgt detect; present folgt _available. Faellt einer dieser
#  Faelle, sagt status wieder mehr, als gemessen wurde.
# --------------------------------------------------------------------------

test inv-status-1.0 {can_print folgt der Backend-Kette} -body {
    set st [printlib::status]
    expr {[dict get $st can_print] == ([printlib::detect] ne "none")}
} -result 1

# status ist eine reine AUSKUNFT und darf den Zustand nicht veraendern.
#
# detect setzt activeBackend. Ein status, der detect ruft, verschiebt
# damit still, was die naechste print-Entscheidung nimmt. Gemessen
# 17.09.2026: nach "configure -backend sumatra" sprang activeBackend
# durch einen status auf "none".
# Der Merkwert ist noetig: ein frueherer Fall ruft detect, damit steht
# activeBackend schon auf "none" -- und ein status, der detect ruft,
# setzt es wieder auf "none". Der Vergleich ginge auf, obwohl die
# Nebenwirkung da ist. Gemessen 17.09.2026 beim Gegenpruefen.
test inv-status-1.4 {status laesst activeBackend unveraendert} -setup {
    set ::printlib::activeBackend MERKWERT
} -body {
    printlib::status
    set ::printlib::activeBackend
} -cleanup {
    set ::printlib::activeBackend {}
} -result MERKWERT

test inv-status-1.1 {backend_detected ist detect} -body {
    expr {[dict get [printlib::status] backend_detected] eq [printlib::detect]}
} -result 1

test inv-status-1.2 {backends ist known} -body {
    expr {[dict get [printlib::status] backends] eq [printlib::known]}
} -result 1

test inv-status-1.3 {die alten _ok-Schluessel sind noch da} -body {
    set st [printlib::status]
    set fehlt {}
    foreach k {pdftocairo_ok sumatra_ok lp_ok pdfium_ok} {
        if {![dict exists $st $k]} { lappend fehlt $k }
    }
    set fehlt
} -result {}

# --------------------------------------------------------------------------
#  5. -pages odd/even landet als CUPS page-set, nicht als -P
#
#  Der leere switch-Rumpf weiter oben in _print_lp sieht nach einer
#  Luecke aus und ist keine: odd/even sollen NICHT an -P, sondern
#  weiter unten als -o page-set. Die zweite Lesung (17.09.2026) las ihn
#  als stillen Volljob -- gemessen wird page-set gesetzt.
#
#  Dieser Fall haelt das fest, damit niemand den leeren Rumpf "repariert"
#  und damit doppelt setzt.
# --------------------------------------------------------------------------

test inv-pages-1.0 {odd/even werden zu page-set, Bereiche zu -P} \
        -constraints unix -setup {
    set f [file join [temporaryDirectory] inv-pages.pdf]
    set fh [open $f w] ; puts $fh "%PDF-1.4" ; close $fh
    rename ::exec ::_inv_real_exec
    proc ::exec {args} { set ::_inv_cmd $args ; return "" }
    rename ::printlib::_available ::_inv_real_available
    proc ::printlib::_available {b} { return [expr {$b eq "lp"}] }
} -body {
    set out {}
    foreach p {odd even 1-3} {
        set ::_inv_cmd {}
        catch {printlib::print $f -printer Test -backend lp -pages $p}
        lappend out [expr {[lsearch -glob $::_inv_cmd *page-set*] >= 0 ? "page-set" : \
                          ([lsearch -exact $::_inv_cmd -P] >= 0 ? "-P" : "keins")}]
    }
    set out
} -cleanup {
    rename ::exec {} ; rename ::_inv_real_exec ::exec
    rename ::printlib::_available {} ; rename ::_inv_real_available ::printlib::_available
    file delete -force $f
} -result {page-set page-set -P}

# --------------------------------------------------------------------------
#  6. pdftocairo scheitert bei odd/even/Listen laut
#
#  pdftocairo kennt nur -f/-l, also einen zusammenhaengenden Bereich.
#  Bis 17.09.2026 fielen odd, even und "1,3,5" durch beide Zweige --
#  ohne -f/-l druckt pdftocairo das GANZE Dokument.
#
#  Papier ist die einzige Ausgabe hier, die man nicht zurueckrollen
#  kann. Ein Abbruch kostet nichts, ein Volljob kostet den Stapel.
# --------------------------------------------------------------------------

test inv-pages-2.0 {pdftocairo: Bereiche ja, odd/even/Listen error} -setup {
    set f [file join [temporaryDirectory] inv-pages2.pdf]
    set fh [open $f w] ; puts $fh "%PDF-1.4" ; close $fh
    rename ::exec ::_inv2_real_exec
    proc ::exec {args} { return "" }
    rename ::printlib::_available ::_inv2_real_available
    proc ::printlib::_available {b} { return [expr {$b eq "pdftocairo"}] }
} -body {
    set out {}
    foreach p {1-3 2 odd even 1,3,5} {
        lappend out [catch {printlib::print $f -printer T \
                -backend pdftocairo -pages $p}]
    }
    set out
} -cleanup {
    rename ::exec {} ; rename ::_inv2_real_exec ::exec
    rename ::printlib::_available {} ; rename ::_inv2_real_available ::printlib::_available
    file delete -force $f
} -result {0 0 1 1 1}

# --------------------------------------------------------------------------
#  7. Die Lizenz steht an drei Stellen und muss uebereinstimmen
#
#  Bis 17.09.2026 sagte der Modulkopf BSD 2-Clause, die README MIT, und
#  eine LICENSE gab es nicht. Damit stand die Lizenz nirgends eindeutig
#  -- wer die Bibliothek benutzen wollte, wusste nicht, unter welchen
#  Bedingungen.
#
#  Entschieden: BSD 2-Clause, passend zur Nachbarschaft (Tcl, pdf4tcl,
#  tcllib sind alle BSD-artig).
# --------------------------------------------------------------------------

test inv-license-1.0 {LICENSE, Modulkopf und README nennen dieselbe Lizenz} -body {
    set fehlt {}

    set lic [file join $root LICENSE]
    if {![file exists $lic]} { lappend fehlt "LICENSE fehlt" }

    proc _liesKopf {f} {
        set ch [open $f r] ; fconfigure $ch -encoding utf-8
        set d [read $ch] ; close $ch ; return $d
    }
    if {[file exists $lic] && \
            [string first "BSD 2-Clause" [_liesKopf $lic]] < 0} {
        lappend fehlt "LICENSE nennt nicht BSD 2-Clause"
    }

    set modul [file join $root lib tm printlib-[package provide printlib].tm]
    if {[string first "BSD 2-Clause" [_liesKopf $modul]] < 0} {
        lappend fehlt "Modulkopf nennt nicht BSD 2-Clause"
    }

    set readme [file join $root README.md]
    if {[string first "BSD 2-Clause" [_liesKopf $readme]] < 0} {
        lappend fehlt "README nennt nicht BSD 2-Clause"
    }
    # Nicht jede Erwaehnung von MIT ist eine Lizenzangabe: der Absatz
    # erklaert, dass die drei Stellen frueher auseinanderliefen, und
    # nennt MIT dabei. Geprueft wird deshalb die AUSSAGE -- eine Zeile,
    # die MIT als geltende Lizenz ausgibt.
    if {[regexp -line {^\*\*MIT\*\*|^MIT --|licen[cs]e:\s*MIT} \
            [_liesKopf $readme]]} {
        lappend fehlt "README gibt MIT als Lizenz an"
    }

    rename _liesKopf {}
    set fehlt
} -result {}

# --------------------------------------------------------------------------
#  8. configure verlangt Paare
#
#  foreach {opt val} nimmt eine ungerade Liste stillschweigend an und
#  setzt den letzten Wert auf leer. Gemessen 17.09.2026:
#
#    configure -printer HP -silent   ->  rc 0, silent ''
#
#  Der Aufrufer wollte -silent 1 und bekam das Gegenteil, ohne Meldung.
#  Bei einem Drucker faellt das erst am Papier auf.
#
#  Dasselbe Muster wie in tinventar (array set opt $args) -- dort war es
#  ein Probelauf, der trotzdem importierte.
# --------------------------------------------------------------------------

test inv-configure-1.0 {ungerade Optionsliste bricht ab} -setup {
    set sicher [printlib::configure]
} -body {
    list [catch {printlib::configure -printer}] \
         [catch {printlib::configure -printer HP -silent}] \
         [catch {printlib::configure -printer HP -silent 1}] \
         [catch {printlib::configure}]
} -cleanup {
    printlib::configure {*}[concat {*}[lmap {k v} $sicher {
        list -[string map {ppdDir ppddir pdfiumPrefer pdfiumprefer} $k] $v
    }]]
} -result {1 1 0 0}

test inv-configure-1.1 {unbekannte Option bricht ab} -body {
    catch {printlib::configure -gibtsnicht 1}
} -result 1

# --------------------------------------------------------------------------
#  9. PPD-Rundlauf: was hineingeht, kommt heraus
#
#  savePpdFile quotet Werte mit Leerzeichen. Bis 17.09.2026 wurde das
#  Anfuehrungszeichen IM Wert nicht maskiert -- der gequotete Bereich
#  endete zu frueh:
#
#    'Foto "matt"'  ->  '"Foto "matt""'
#
#  Ein Druckerprofil mit einem Anfuehrungszeichen im Wert kam also
#  verfaelscht zurueck. Backslashes (Windows-Pfade!) waren derselbe Fall.
# --------------------------------------------------------------------------

test inv-ppd-1.0 {Werte ueberstehen save/load unveraendert} -setup {
    set ppdDir [file join [temporaryDirectory] inv-ppd]
    file mkdir $ppdDir
    set alt [dict get [printlib::configure] ppdDir]
    printlib::configure -ppddir $ppdDir
} -body {
    set proben [dict create \
        einfach     A4 \
        leerzeichen "Tray 2" \
        leer        "" \
        anfuehrung  {Foto "matt"} \
        backslash   {C:\Pfad} \
        beides      {a "b" c\d}]
    printlib::savePpdFile InvProbe pdftocairo $proben
    set f [lindex [glob [file join $ppdDir *]] 0]
    set zurueck [printlib::loadPpdFile $f]
    set abweichung {}
    dict for {k v} $proben {
        if {![dict exists $zurueck $k] || [dict get $zurueck $k] ne $v} {
            lappend abweichung $k
        }
    }
    set abweichung
} -cleanup {
    printlib::configure -ppddir $alt
    file delete -force $ppdDir
} -result {}

# --------------------------------------------------------------------------
#  PPD-Autoload und Backends ohne PPD
#
#  print laedt zu einem -printer automatisch die passende .pdftocairo /
#  .sumatra Datei. pdfium hat kein solches Format -- in der Registry fehlt
#  ihm das ppd-Flag -- und findPpdFile wirft fuer einen Backend-Namen, der
#  nicht in _ppdBackends steht.
#
#  Bis 0.3 stand der Autoload hinter "if {$printer ne {}}" allein. Damit
#  scheiterte print mit pdfium UND Druckernamen, bevor gedruckt wurde --
#  und das ist der Hauptweg dieses Backends unter Windows.
#
#  Die Testreihe sah es nicht, weil pdfium ohne tclpdfium nie erreicht wird.
#  Hier wird _available vorgetaeuscht und _print_pdfium ersetzt, damit der
#  Weg BIS zum Druck laeuft, ohne dass etwas gedruckt wird.
# --------------------------------------------------------------------------

test inv-ppd-2.0 {print mit pdfium und Druckername kommt bis zum Backend} -setup {
    rename ::printlib::_available    ::_ppd2_available
    rename ::printlib::_print_pdfium ::_ppd2_pdfium
    proc ::printlib::_available {b} { return [expr {$b eq "pdfium"}] }
    proc ::printlib::_print_pdfium {f o} { return "angekommen" }
    set probe [file join [temporaryDirectory] inv-ppd2.pdf]
    set fh [open $probe w] ; puts -nonewline $fh "%PDF-1.4\n%%EOF\n" ; close $fh
} -body {
    printlib::print $probe -backend pdfium -printer "Brother QL-820NWB"
} -cleanup {
    rename ::printlib::_available {}    ; rename ::_ppd2_available ::printlib::_available
    rename ::printlib::_print_pdfium {} ; rename ::_ppd2_pdfium ::printlib::_print_pdfium
    file delete -- $probe
} -result {angekommen}

test inv-ppd-2.1 {_ppdBackends nennt nur Backends mit eigenem Dateiformat} -body {
    lsort [printlib::_ppdBackends]
} -result {pdftocairo sumatra}

# --------------------------------------------------------------------------
#  command -- die Zeile bauen, ohne zu drucken
#
#  Neu in 0.3.1, uebernommen aus dem Etikettendruck-Zweig. Der Sinn: die
#  Zufuhr ist sonst nur auf Papier pruefbar, und Papier laesst sich nicht
#  zurueckrollen.
#
#  command und print teilen sich _parseOpts, den PPD-Autoload und die
#  _cmd_*-Prozeduren. Faellt einer dieser Faelle, ist die gebaute Zeile
#  nicht mehr die, die gedruckt wuerde -- und dann prueft command das
#  Falsche.
# --------------------------------------------------------------------------

test inv-command-1.0 {lp: Drucker und Datei stehen in der Zeile} -body {
    printlib::command bogen.pdf -backend lp -printer kluniversal
} -match glob -result {lp -d kluniversal *bogen.pdf}

test inv-command-1.1 {die Zufuhr wird zu InputSlot} -body {
    set z [printlib::command bogen.pdf -backend lp -printer kl -source manual]
    expr {[lsearch -exact $z "InputSlot=Manual"] >= 0}
} -result 1

test inv-command-1.2 {ohne Zufuhr steht kein InputSlot in der Zeile} -body {
    string match {*InputSlot*} \
        [printlib::command bogen.pdf -backend lp -printer kl]
} -result 0

test inv-command-1.2b {die Schreibweise des Treibers bleibt erhalten} -body {
    # "string totitle" machte aus MultiPurpose ein Multipurpose -- und
    # genau diese Namen stehen in den PPDs von HP und Brother und kommen
    # aus printercaps. CUPS nimmt den unbekannten Schacht nicht und druckt
    # aus dem Standardfach; gemerkt haette man es am Papier.
    set aus {}
    foreach v {manual Manual MultiPurpose PhotoTray LargeCapacity Tray2} {
        set z [printlib::command bogen.pdf -backend lp -printer kl -source $v]
        foreach e $z {
            if {[string match "InputSlot=*" $e]} {
                lappend aus [string range $e 10 end]
            }
        }
    }
    set aus
} -result {Manual Manual MultiPurpose PhotoTray LargeCapacity Tray2}

test inv-command-1.3 {Kopien nativ ueber -n} -body {
    set z [printlib::command bogen.pdf -backend lp -printer kl -copies 3]
    expr {[lsearch -exact $z "-n"] >= 0 && [lsearch -exact $z "3"] >= 0}
} -result 1

test inv-command-1.4 {command druckt nicht -- die Datei muss nicht existieren} -body {
    # print verlangt eine vorhandene .pdf; command baut nur.
    set z [printlib::command /gibt/es/nicht.pdf -backend lp -printer kl]
    lindex $z end
} -result {/gibt/es/nicht.pdf}

test inv-command-1.5 {die Windows-Zeilen lassen sich auch unter Linux bauen} -body {
    # Ohne das waere der Optionsbau der Windows-Backends nur auf Windows
    # pruefbar -- und die Testreihe laeuft hier.
    set a [printlib::command bogen.pdf -backend pdftocairo -printer HP -source manual]
    set b [printlib::command bogen.pdf -backend sumatra -printer HP -source manual]
    list [lindex $a 0] [string match {*source=manual*} $a] \
         [lindex $b 0] [string match {*bin=manual*} $b]
} -result {pdftocairo 1 SumatraPDF 1}

test inv-command-1.6 {pdfium hat keine Zeile und sagt das} -body {
    catch {printlib::command bogen.pdf -backend pdfium -printer X} e
    string match {*keine Kommandozeile*} $e
} -result 1

test inv-command-1.7 {unbekanntes Backend und unbekannte Option brechen ab} -body {
    catch {printlib::command bogen.pdf -backend gibtsnicht} e1
    catch {printlib::command bogen.pdf -backend lp -gibtsnicht 1} e2
    catch {printlib::command bogen.pdf -backend lp -printer} e3
    list [string match {*unbekanntes Backend*} $e1] \
         [string match {*unbekannte Option*} $e2] \
         [string match {*ungerade*} $e3]
} -result {1 1 1}

test inv-command-1.8 {command und print nehmen dieselben Optionsnamen} -body {
    # Zwei Listen, die auseinanderlaufen koennen, gibt es seit 0.3.1 nicht
    # mehr -- beide gehen durch _parseOpts. Der Fall haelt das fest.
    set p [::printlib::_parseOpts print   {} k1]
    set c [::printlib::_parseOpts command {} k2]
    expr {[lsort [dict keys $p]] eq [lsort [dict keys $c]]}
} -result 1

# --------------------------------------------------------------------------
#  Wann hat ein Druck versagt?
#
#  exec wirft in drei ganz verschiedenen Faellen, und -errorcode sagt, in
#  welchem: NONE (lief, Exit 0, hat auf stderr geredet), CHILDSTATUS
#  (Exit != 0), POSIX (liess sich nicht starten).
#
#  Bis 0.3.1 entschied _print_pdftocairo das am TEXT der Fehlermeldung --
#  abgebrochen wurde nur bei "*child process exited abnormally*" oder
#  "*Error:*". Gemessen mit vorgetaeuschtem exec am 30.09.2026:
#
#    Exit 1, Text "I/O setup failed: cannot open printer port"
#      -> print gab "" zurueck, also Erfolg. Gedruckt wurde nichts.
#
#  Ein Druck, der nicht stattgefunden hat und Erfolg meldet, ist schlimmer
#  als einer, der laut scheitert: niemand sieht nach dem Papier.
#
#  Bei lp und SumatraPDF stand das Gegenteil: jedes catch galt als Fehler,
#  auch eine blosse Meldung auf stderr bei Exit 0.
# --------------------------------------------------------------------------

proc _execProbe {backend errorcode text} {
    # Laesst print mit vorgetaeuschtem exec laufen und sagt, ob es warf.
    rename ::exec ::_ep_exec
    rename ::printlib::_available ::_ep_available
    proc ::printlib::_available {b} { return 1 }
    proc ::exec {args} [list return -code error -errorcode $errorcode $text]
    set f [file join [::tcltest::temporaryDirectory] execprobe.pdf]
    set fh [open $f w] ; puts -nonewline $fh "%PDF-1.4\n%%EOF\n" ; close $fh
    set ergebnis [expr {[catch {::printlib::print $f -backend $backend -printer HP}]
                        ? "wirft" : "Erfolg"}]
    rename ::exec {} ; rename ::_ep_exec ::exec
    rename ::printlib::_available {} ; rename ::_ep_available ::printlib::_available
    file delete -- $f
    return $ergebnis
}

test inv-exec-1.0 {Exit != 0 ist ein Fehler, auch ohne bekanntes Textmuster} -body {
    list [_execProbe pdftocairo {CHILDSTATUS 4711 1} \
              "I/O setup failed: cannot open printer port"] \
         [_execProbe lp {CHILDSTATUS 4711 1} "lp: Error - unknown destination"] \
         [_execProbe sumatra {CHILDSTATUS 4711 2} "irgendwas"]
} -result {wirft wirft wirft}

test inv-exec-1.1 {Ausgabe auf stderr bei Exit 0 ist kein Fehler} -body {
    # pdftocairo meldet Font-Warnungen so, und mit 2>@1 landen sie im
    # catch. Ein Druck, der gelaufen ist, darf nicht als Fehler gelten.
    list [_execProbe pdftocairo NONE "Syntax Warning: Invalid Font Weight"] \
         [_execProbe lp NONE "lp: hint: using default media"] \
         [_execProbe sumatra NONE "note"]
} -result {Erfolg Erfolg Erfolg}

test inv-exec-1.2 {ein Programm, das sich nicht starten laesst, ist ein Fehler} -body {
    _execProbe lp {POSIX ENOENT {no such file or directory}} \
        "couldn't execute \"lp\": no such file or directory"
} -result {wirft}

test inv-exec-1.3 {_execFehler entscheidet allein am errorcode} -body {
    list [printlib::_execFehler {-errorcode NONE}] \
         [printlib::_execFehler {-errorcode {CHILDSTATUS 1 1}}] \
         [printlib::_execFehler {-errorcode {POSIX ENOENT x}}] \
         [printlib::_execFehler {-errorcode {CHILDKILLED 1 SIGTERM x}}] \
         [printlib::_execFehler {}]
} -result {0 1 1 1 1}

# --------------------------------------------------------------------------
#  Die Fehlertexte sprechen eine Sprache
#
#  lp, pdftocairo und sumatra meldeten deutsch, pdfium englisch ("no
#  printer given and no system default"). Fuer den Aufrufer und fuer ein
#  Protokoll ist das eine Fundgrube fuer falsche Mustervergleiche.
# --------------------------------------------------------------------------

test inv-sprache-1.0 {keine englischen Standardwendungen in den Fehlertexten} -body {
    set modul [file join $root lib tm printlib-[package provide printlib].tm]
    set fh [open $modul] ; fconfigure $fh -encoding utf-8
    set zeilen [split [read $fh] \n] ; close $fh
    set treffer {}
    set nr 0
    foreach z $zeilen {
        incr nr
        if {![string match "*error \"printlib*" $z]} continue
        foreach muster {"not available" "no printer" "invalid " "unknown " \
                        "missing " "no driver"} {
            if {[string match "*$muster*" [string tolower $z]]} {
                lappend treffer "$nr: [string trim $z]"
            }
        }
    }
    set treffer
} -result {}

# --------------------------------------------------------------------------
#  Temp-Verzeichnis
#
#  01.10.2026, gemeldet aus der GUI auf Debian:
#
#    can't read "::env(TEMP)": no such variable
#      (read trace on "::env(TEMP)")
#    invoked from within "file join $::env(TEMP) printlib_caps.ps1"
#
#  TEMP setzt Windows. Unter Linux gibt es die Variable nicht, und der
#  Zugriff auf ein fehlendes Element von ::env wirft -- er liefert kein
#  "". Die Stelle stand dreimal im Baum: im Modul, in der GUI und in
#  deren Kopie unter demo/.
# --------------------------------------------------------------------------

test inv-tmp-1.0 {tmpdir liefert ein Verzeichnis, in das sich schreiben laesst} -body {
    set d [printlib::tmpdir]
    set p [file join $d inv-tmp-probe.txt]
    set fh [open $p w] ; puts $fh x ; close $fh
    set ok [file exists $p]
    file delete -- $p
    list [file isdirectory $d] $ok
} -result {1 1}

test inv-tmp-1.1 {ohne TEMP faellt es nicht um} -constraints unix -setup {
    set gab [info exists ::env(TEMP)]
    if {$gab} { set alt $::env(TEMP) ; unset ::env(TEMP) }
    set ::printlib::tmpdirGemerkt ""
} -body {
    file isdirectory [printlib::tmpdir]
} -cleanup {
    if {$gab} { set ::env(TEMP) $alt }
    set ::printlib::tmpdirGemerkt ""
} -result 1

test inv-tmp-1.2 {ein unbrauchbarer Wert wird uebergangen, nicht geglaubt} -setup {
    set var [expr {$::tcl_platform(platform) eq "windows" ? "TEMP" : "TMPDIR"}]
    set gab [info exists ::env($var)]
    if {$gab} { set alt $::env($var) }
    set ::env($var) [file join [temporaryDirectory] gibt-es-nicht-[clock clicks]]
    set ::printlib::tmpdirGemerkt ""
} -body {
    # "file writable" wuerde hier luegen; geprueft wird mit einem Versuch.
    set d [printlib::tmpdir]
    list [file isdirectory $d] [expr {$d eq $::env($var) ? "geglaubt" : "uebergangen"}]
} -cleanup {
    if {$gab} { set ::env($var) $alt } else { unset ::env($var) }
    set ::printlib::tmpdirGemerkt ""
} -result {1 uebergangen}

test inv-tmp-1.3 {kein env(TEMP) mehr im Code -- nur noch in Kommentaren} -body {
    set gefunden {}
    foreach datei [list [file join $root lib tm printlib-[package provide printlib].tm] \
                        [file join $root printlib-gui.tcl] \
                        {*}[glob -nocomplain [file join $root demo *.tcl]] \
                        {*}[glob -nocomplain [file join $root tools *.tcl]]] {
        set fh [open $datei] ; fconfigure $fh -encoding utf-8
        set nr 0
        foreach z [split [read $fh] \n] {
            incr nr
            if {[string index [string trimleft $z] 0] eq "#"} continue
            if {[string match {*env(TEMP)*} $z] || [string match {*env(TMP)*} $z]} {
                lappend gefunden "[file tail $datei]:$nr"
            }
        }
        close $fh
    }
    set gefunden
} -result {}

# --------------------------------------------------------------------------
#  Keine zweite Oberflaeche
#
#  demo/demo-printlib.tcl trug 859 Zeilen, die eine Kopie von
#  printlib-gui.tcl waren -- der eigene Kopf sagte "funktionsgleich".
#  Gemessen unterschieden sie sich in 20 Zeilen (Titel, Modulpfad,
#  Kommentare). Die TEMP-Stelle steckte darum zweimal im Baum, und wer
#  eine repariert, hat den Fehler noch.
# --------------------------------------------------------------------------

test inv-demo-1.0 {die Demo laedt die Oberflaeche, statt sie nachzubauen} -body {
    set d [file join $root demo demo-printlib.tcl]
    set fh [open $d] ; fconfigure $fh -encoding utf-8
    set text [read $fh] ; close $fh
    set zeilen [llength [split [string trim $text] \n]]
    list [expr {$zeilen < 60 ? "duenn" : "$zeilen Zeilen -- wieder eine Kopie?"}] \
         [string match {*source *printlib-gui.tcl*} $text]
} -result {duenn 1}

# --------------------------------------------------------------------------
#  Schneiden: die Option heisst bei jedem Treiber anders
#
#  01.10.2026, gemeldet von einem Brother QL-820NWB unter CUPS: kein
#  Schnitt, bei keiner der vier Einstellungen. Die Diagnose zeigte, warum:
#
#    CutMedia/CutMedia: *None Auto EndOfPage EndOfJob
#
#  printlib schickte CutLabel=ON / AutoCut=ON / CutAtEnd=ON -- Namen, die
#  dieser Treiber nicht kennt. CUPS uebergeht unbekannte Optionen
#  stillschweigend, es blieb bei *None, das Etikett blieb an der Rolle.
#
#  Im Code stand dazu: "Es werden mehrere gaengige Schalter gesetzt -- der
#  Treiber waehlt den passenden". Das ist keine Strategie, sondern eine
#  Hoffnung. Derselbe Fall wie beim Schacht: der Wert muss vom Treiber
#  kommen, nicht aus einer Liste im Kopf.
# --------------------------------------------------------------------------

test inv-cut-1.0 {Brother QL: die Werte des Treibers werden benutzt} -body {
    set werte {None Auto EndOfPage EndOfJob}
    set aus {}
    foreach m {auto on off end} {
        lappend aus [printlib::_cutLpOpts $m CutMedia $werte]
    }
    set aus
} -result {CutMedia=Auto CutMedia=EndOfPage CutMedia=None CutMedia=EndOfJob}

test inv-cut-1.1 {Gross/Kleinschreibung des Treibers bleibt stehen} -body {
    # Wie beim InputSlot: der Wert kommt aus lpoptions, also vom Treiber.
    printlib::_cutLpOpts on CutMedia {none auto endofpage endofjob}
} -result {CutMedia=endofpage}

test inv-cut-1.2 {ohne Auskunft bleibt das alte Raten} -body {
    list [printlib::_cutLpOpts on "" {}] [printlib::_cutLpOpts off "" {}] \
         [printlib::_cutLpOpts end "" {}]
} -result {{CutLabel=ON AutoCut=ON} {CutLabel=OFF AutoCut=OFF} CutAtEnd=ON}

test inv-cut-1.3 {ein Wert, den der Treiber nicht hat, wird nicht erfunden} -body {
    # "end" bei einem Treiber, der nur ON/OFF kennt: lieber nichts senden
    # als etwas, das ohnehin uebergangen wird.
    printlib::_cutLpOpts end CutLabel {ON OFF}
} -result {}

test inv-cut-1.4 {ein unbekannter Modus liefert nichts} -body {
    printlib::_cutLpOpts vielleicht CutMedia {None Auto}
} -result {}

test inv-cut-1.5 {_printercaps_linux behaelt die Schneide-Option} -setup {
    rename ::exec ::_cut_exec
    proc ::exec {args} {
        if {[lindex $args 0] ne "lpoptions"} { error "nicht vorgesehen: $args" }
        return "PageSize/Media Size: 29x42mm *29x90mm Custom.WIDTHxHEIGHT\nMediaType/Media Type: *Labels Roll\nColorModel/Output Mode: *Gray\nCutMedia/CutMedia: *None Auto EndOfPage EndOfJob"
    }
} -body {
    set caps [printlib::_printercaps_linux ProbeQL]
    list [dict get $caps cut_option] [dict get $caps cut_values] \
         [dict get $caps cut_default]
} -cleanup {
    rename ::exec {} ; rename ::_cut_exec ::exec
} -result {CutMedia {None Auto EndOfPage EndOfJob} None}

test inv-cut-1.5b {die Option landet wirklich in der lp-Zeile} -setup {
    # Die Abbildung allein nuetzt nichts, wenn _cmd_lp sie nicht benutzt.
    # Darum der Weg bis zur fertigen Zeile, mit vorgetaeuschtem lpoptions.
    array unset ::printlib::cutCapsCache
    rename ::exec ::_cut3_exec
    proc ::exec {args} {
        if {[lindex $args 0] ne "lpoptions"} { error "nicht vorgesehen: $args" }
        return "PageSize/Media Size: *29x90mm\nCutMedia/CutMedia: *None Auto EndOfPage EndOfJob"
    }
} -body {
    set aus {}
    foreach m {auto on off end} {
        set z [printlib::command demo.pdf -backend lp -printer QLprobe -cut $m]
        foreach e $z {
            if {[string match "CutMedia=*" $e]} { lappend aus $e }
        }
    }
    set aus
} -cleanup {
    rename ::exec {} ; rename ::_cut3_exec ::exec
    array unset ::printlib::cutCapsCache
} -result {CutMedia=Auto CutMedia=EndOfPage CutMedia=None CutMedia=EndOfJob}

test inv-cut-1.6 {ein Drucker ohne Schneide-Option bekommt keine} -setup {
    rename ::exec ::_cut2_exec
    proc ::exec {args} {
        return "PageSize/Media Size: *A4 Letter\nInputSlot/Media Source: *Auto Tray1\nDuplex/Duplex: *None DuplexNoTumble"
    }
} -body {
    set caps [printlib::_printercaps_linux ProbeBuero]
    dict exists $caps cut_option
} -cleanup {
    rename ::exec {} ; rename ::_cut2_exec ::exec
} -result 0

# --------------------------------------------------------------------------
#  Orientierung: alle vier Werte werden ausgesprochen
#
#  01.10.2026: fuer portrait stand ein leerer Zweig ("CUPS-Default"). Drei
#  Werte gingen als orientation-requested=4/5/6 hinaus, der vierte gar
#  nicht. Damit war nicht mehr unterscheidbar, ob portrait gewirkt hat
#  oder ob nur nichts angekommen ist -- und gemeldet wurde genau das:
#  portrait und landscape ergaben denselben Druck, reverse-* nicht.
#
#  Ob das die Ursache war, entscheidet das Etikett; dass eine Option
#  manchmal geschickt wird und manchmal nicht, ist unabhaengig davon
#  nichts, worauf man eine Messung stuetzen kann.
# --------------------------------------------------------------------------

test inv-orient-1.0 {jede der vier Orientierungen steht in der Zeile} -body {
    set aus {}
    foreach o {portrait landscape reverse-landscape reverse-portrait} {
        set z [printlib::command demo.pdf -backend lp -printer P -orientation $o]
        set gefunden ""
        foreach e $z {
            if {[string match "orientation-requested=*" $e]} { set gefunden $e }
        }
        lappend aus $gefunden
    }
    set aus
} -result {orientation-requested=3 orientation-requested=4 orientation-requested=5 orientation-requested=6}

test inv-orient-1.1 {die Zahlen folgen IPP, nicht einer eigenen Zaehlung} -body {
    # 3=portrait 4=landscape 5=reverse-landscape 6=reverse-portrait
    # (RFC 8011, orientation-requested). Faellt dieser Fall, stimmt die
    # Zuordnung nicht mehr mit dem ueberein, was CUPS versteht.
    set z [printlib::command demo.pdf -backend lp -printer P -orientation landscape]
    expr {[lsearch -exact $z "orientation-requested=4"] >= 0}
} -result 1

# --------------------------------------------------------------------------
# Skalierung: "noscale" muss auch etwas SENDEN (01.10.2026)
# --------------------------------------------------------------------------
#
# "-scale noscale" ist die Vorgabe von printlib und heisst "1:1 drucken".
# Fuer lp wurde dafuer gar nichts gesendet: die Anwendung bat um
# Originalgroesse, und auf dem Weg nach draussen stand nichts davon. Was
# dann geschieht, entscheidet der Filterweg -- und ein generisches
# IPP-Everywhere-PPD ohne Randangaben verkleinert auf den bedruckbaren
# Bereich.
#
# Auf einem Etikettenbogen sieht das aus wie ein Versatz, der mit jedem
# Etikett waechst, und man sucht den Fehler in der Geometrie. Genau das ist
# am 01.10.2026 im Etikettendruck passiert: dort wurden Luecken von
# 1,9 / 0,6 mm eingetragen, um rund 96 % Verkleinerung auszugleichen.

test inv-scale-1.0 {noscale sendet print-scaling=none} -body {
    set z [printlib::command demo.pdf -backend lp -printer P -scale noscale]
    expr {[lsearch -exact $z "print-scaling=none"] >= 0}
} -result 1

test inv-scale-1.1 {noscale ist die Vorgabe -- auch ohne -scale} -body {
    # Sonst waere die Zusage nur da, wo jemand sie ausdruecklich nennt.
    set z [printlib::command demo.pdf -backend lp -printer P]
    expr {[lsearch -exact $z "print-scaling=none"] >= 0}
} -result 1

test inv-scale-1.2 {origsize heisst dasselbe und sendet dasselbe} -body {
    set z [printlib::command demo.pdf -backend lp -printer P -scale origsize]
    expr {[lsearch -exact $z "print-scaling=none"] >= 0}
} -result 1

test inv-scale-1.3 {fit/shrink/expand bleiben bei fit-to-page} -body {
    # Das laeuft und ist hier nicht nachgemessen. Eine Umstellung ohne
    # Messung waere genau der Fehler, den inv-scale-1.0 gerade behebt.
    set schief {}
    foreach s {fit shrink expand} {
        set z [printlib::command demo.pdf -backend lp -printer P -scale $s]
        if {[lsearch -exact $z "fit-to-page"] < 0} { lappend schief $s }
        if {[lsearch -exact $z "print-scaling=none"] >= 0} { lappend schief "$s+none" }
    }
    set schief
} -result {}

test inv-scale-1.4 {kein Modus sendet zwei widerspruechliche Angaben} -body {
    set schief {}
    foreach s {noscale fit shrink expand match origsize} {
        set z [printlib::command demo.pdf -backend lp -printer P -scale $s]
        if {[lsearch -exact $z "fit-to-page"] >= 0
            && [lsearch -exact $z "print-scaling=none"] >= 0} {
            lappend schief $s
        }
    }
    set schief
} -result {}

# --------------------------------------------------------------------------
# lpoptions: Optionsnamen mit Bindestrich (01.10.2026)
# --------------------------------------------------------------------------
#
# Die Regex in _printercaps_linux liess keinen Bindestrich im Namen zu. Bei
# einem treiberlosen IPP-Drucker heissen die Optionen aber genau so.
# Gemessen an echten Zeilen:
#
#   print-color-mode/Print Color Mode: ...  -> erkannt als "print"
#   print-scaling/Print Scaling: ...        -> erkannt als "print"
#   print-quality/Print Quality: ...        -> erkannt als "print"
#
# Drei Optionen auf EINEN Schluessel, jede ueberschreibt die vorige. Kein
# Fehler, keine Luecke -- nur eine Faehigkeit namens "print", die nichts
# bedeutet. CutMedia und InputSlot kamen durch, weil sie keinen Bindestrich
# tragen; darum fiel es bei den Schneidetests nicht auf.
#
# Geprueft wird mit einem lpoptions auf dem PATH -- kein Drucker noetig,
# und gemessen wird genau der Weg, den printercaps im Ernstfall geht.

proc lpoptionsStub {text} {
    set d [makeDirectory lpstub]
    set p [file join $d lpoptions]
    set fh [open $p w]
    chan configure $fh -translation lf
    puts $fh "#!/bin/sh"
    puts $fh "cat <<'OUT'"
    puts $fh $text
    puts $fh "OUT"
    close $fh
    file attributes $p -permissions 0755
    return $d
}

set ippZeilen {InputSlot/Media Source: *Auto Manual
PageSize/Media Size: *29x90mm 62x100mm
CutMedia/CutMedia: *None Auto EndOfPage EndOfJob
print-color-mode/Print Color Mode: *monochrome auto
print-scaling/Print Scaling: *auto auto-fit fill fit none
print-quality/Print Quality: *4 3 5}

test inv-caps-2.0 {Optionsnamen mit Bindestrich kommen vollstaendig an} \
  -constraints unix -setup {
    set ::altPath $::env(PATH)
    set ::env(PATH) "[lpoptionsStub $::ippZeilen]:$::altPath"
} -body {
    set caps [::printlib::_printercaps_linux QL820]
    list [dict exists $caps scaling_option] \
         [expr {[dict exists $caps scaling_option]
                ? [dict get $caps scaling_option] : ""}]
} -cleanup {set ::env(PATH) $::altPath} -result {1 print-scaling}

test inv-caps-2.1 {die Werte der Option gehen nicht verloren} \
  -constraints unix -setup {
    set ::altPath $::env(PATH)
    set ::env(PATH) "[lpoptionsStub $::ippZeilen]:$::altPath"
} -body {
    set caps [::printlib::_printercaps_linux QL820]
    list [dict get $caps scaling_values] [dict get $caps scaling_default]
} -cleanup {set ::env(PATH) $::altPath} -result {{auto auto-fit fill fit none} auto}

test inv-caps-2.2 {die drei print-* Optionen bleiben drei} -constraints unix -setup {
    set ::altPath $::env(PATH)
    set ::env(PATH) "[lpoptionsStub $::ippZeilen]:$::altPath"
} -body {
    # Der Kern des alten Fehlers: drei Optionen fielen auf EINEN Schluessel
    # "print" zusammen, jede ueberschrieb die vorige.
    #
    # Der erste Anlauf dieses Falls fragte "dict exists $caps print" -- und
    # bestand auch gegen die alte Fassung, weil der falsche Schluessel in
    # einer internen Tabelle landete und nie im Ergebnis. Ein Test, der
    # aus dem falschen Grund gruen ist, ist schlimmer als keiner. Seitdem
    # gibt printercaps die gelesene Tabelle mit, und hier wird sie gezaehlt.
    set caps [::printlib::_printercaps_linux QL820]
    set opts [dict get $caps lpoptions]
    set da {}
    foreach n {print-scaling print-quality print-color-mode} {
        if {[dict exists $opts $n]} { lappend da $n }
    }
    list [lsort $da] [dict exists $opts print]
} -cleanup {set ::env(PATH) $::altPath} \
  -result {{print-color-mode print-quality print-scaling} 0}

test inv-caps-2.3 {Namen OHNE Bindestrich kommen weiter durch} \
  -constraints unix -setup {
    set ::altPath $::env(PATH)
    set ::env(PATH) "[lpoptionsStub $::ippZeilen]:$::altPath"
} -body {
    # Gegenprobe zur Regex-Aenderung: sie darf nichts kaputtmachen, was
    # vorher ging. CutMedia ist der Fall, an dem der Schnitt haengt.
    set caps [::printlib::_printercaps_linux QL820]
    list [dict get $caps cut_option] [dict get $caps bins]
} -cleanup {set ::env(PATH) $::altPath} -result {CutMedia {Auto Manual}}

test inv-caps-2.4 {ein Drucker ohne print-scaling meldet es auch nicht} \
  -constraints unix -setup {
    set ::altPath $::env(PATH)
    set ::env(PATH) "[lpoptionsStub "InputSlot/Media Source: *Auto Manual
PageSize/Media Size: *A4 Letter"]:$::altPath"
} -body {
    # Wichtig fuer den Aufrufer: "nicht gemeldet" heisst, dass
    # print-scaling=none zwar gesendet, aber vermutlich uebergangen wird.
    # Das ist der Unterschied zwischen gesendet und angekommen.
    set caps [::printlib::_printercaps_linux P]
    dict exists $caps scaling_option
} -cleanup {set ::env(PATH) $::altPath} -result 0

cleanupTests
