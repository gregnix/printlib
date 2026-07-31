# printlib-0.3.tm
#
# Plattformuebergreifende PDF-Druckbibliothek fuer Tcl/Tk
# Unterstuetzt: pdftocairo (Vektor), SumatraPDF (Bitmap-Fallback)
#
# Copyright (C) 2026 gregnix
# Lizenz: BSD 2-Clause
#
# Changelog 0.2:
#   - Eigene Konfigurationsformate .pdftocairo und .sumatra
#     (Druckername -> Datei mit Standardoptionen)
#   - Autoload: print {.pdf} -printer X liest ppd/X.{pdftocairo|sumatra}
#     automatisch, explizite Optionen ueberschreiben Datei-Werte
#   - configure -ppddir <pfad> -- explizites PPD-Verzeichnis
#   - savePpdFile / loadPpdFile -- programmatischer Zugriff
#   - info-Alias entfernt (Deprecation aus 0.1.1)
#   - copies-Workaround fuer pdftocairo (n-mal Druck)
#   - lp-Backend NEU: vollwertige CUPS-Integration fuer Linux/macOS.
#     pdftocairo -print existiert nur in der Windows-Version --
#     auf Linux/macOS wird nun lp (CUPS) automatisch bevorzugt.
#     detect() entscheidet plattformabhaengig.
#
# Changelog 0.1.1 (Bugfix-Release vor 0.2):
#   - copies-Variable in _print_sumatra korrigiert (war undefiniert)
#   - info-Funktion umbenannt in status (info kollidierte mit Tcl-Standard)
#   - fit und expand in pdftocairo unterschiedlich behandelt
#   - silent jetzt fuer beide Backends + im cfg-Dict
#   - detect: konsistentes Verhalten ohne error bei nicht verfuegbar
#   - print: activeBackend auch bei explizitem -backend aktualisiert
#   - printercaps_all: bricht nicht mehr bei einzelnem Drucker-Fehler ab
#   - redundantes variable-Statement entfernt
#   - PowerShell-Ausgabe-Parsing: Style-Fixes

package provide printlib 0.3
package require Tcl 8.6-

namespace eval ::printlib {

    # --- Interne Konfiguration ---
    variable cfg [dict create \
        backend      auto \
        printer      "" \
        source       "" \
        duplex       off \
        paper        "" \
        scale        noscale \
        copies       1 \
        silent       0 \
        orientation  portrait \
        cut          auto \
        paperw       "" \
        paperh       "" \
        ppdDir       "" \
        pdftocairo   pdftocairo \
        sumatra      SumatraPDF \
        lp           lp \
        pdfiumPrefer 0 \
    ]

    # Ermittelter Backend nach detect
    variable activeBackend ""

    # --- Backend-Registry ------------------------------------------------
    # Eine Liste als einzige Quelle der bekannten Backends. Reihenfolge =
    # Vorrang, den detect je Plattform von oben nach unten probiert.
    # Wer ein Backend hinzufuegt, ergaenzt hier einen Eintrag und die
    # zugehoerige _print_<name> / _available-Pruefung -- nicht mehr drei
    # verstreute Gueltigkeitslisten.
    # Backend-Registry. Ein Eintrag je Backend, an einer Stelle:
    #   platforms  wo das Backend ueberhaupt in Frage kommt
    #   ppd        1, wenn es eigene .<backend>-Konfigdateien liest
    #              (pdftocairo/sumatra); lp und pdfium haben keine.
    variable backends {
        pdftocairo {platforms {windows} ppd 1}
        pdfium     {platforms {windows}}
        sumatra    {platforms {windows} ppd 1}
        lp         {platforms {unix}}
    }

    # Bekannte Backend-Namen (in Registry-Reihenfolge).
    proc known {} {
        variable backends
        return [dict keys $backends]
    }

    namespace export configure print printerlist defaultprinter \
        printerinfo printercaps printercaps_all detect status \
        loadPpdFile savePpdFile findPpdFile \
        isLabelPrinter labelformats labelsize labelpaper \
        resolvePrinter exportPrinterConfig importPrinterConfig \
        savePrinterProfile usePrinterProfile listPrinterProfiles \
        openPrinterSettings
}

# -------------------------------------------------------------------------
# configure -- Optionen setzen
#
#   -scale      Skalierungsmodus:
#               noscale    -- keine Skalierung (Standard)
#               fit        -- Seite an Papier anpassen (verkleinern UND vergroessern)
#               shrink     -- nur verkleinern wenn zu gross
#               expand     -- nur vergroessern wenn zu klein (z.B. fuer randlos)
#               match      -- Papier an Seitengröße anpassen
#               origsize   -- Originalgroesse beibehalten
#   -printer    Druckername (leer = Systemstandard)
#   -source     Kassette: upper lower middle manual auto envelope ...
#               oder numerischer Wert (treiberspezifisch)
#   -duplex     off | long | short
#   -paper      A4 | A3 | letter | legal | ...
#   -copies     Anzahl Kopien
#               SumatraPDF / lp: nativ
#               pdftocairo: Workaround -- Druck wird N-mal ausgefuehrt
#   -silent     0 | 1   Fehlerdialog unterdruecken (beide Backends)
#   -orientation portrait | landscape | reverse-landscape | reverse-portrait
#               Druckorientierung. Wirkung pro Backend:
#                 lp:         -o orientation-requested=4 (CUPS-Standard)
#                 sumatra:    -print-settings "landscape|portrait"
#                 pdftocairo: nicht direkt unterstuetzt (DEVMODE)
#   -cut        auto | on | off | end
#               Auto-Cut bei Etikettendruckern (z.B. Brother QL).
#               'on'/'auto' (default) sendet sowohl CutLabel=ON als auch
#               AutoCut=ON -- gaengige Brother-CUPS-Treiber-Schalter.
#               'end' nutzt CutAtEnd=ON (nur Job-Ende schneiden).
#               Treiberspezifisch -- bei abweichendem Treiber per PPD
#               ueberschreiben.
#   -ppddir     Verzeichnis fuer .pdftocairo/.sumatra-Konfigdateien
#               (leer = automatische Suche: pwd/ppd, scriptDir/ppd)
#   -pdftocairo Pfad zur pdftocairo.exe (default: pdftocairo) -- Windows
#   -sumatra    Pfad zur SumatraPDF.exe  (default: SumatraPDF)  -- Windows
#   -lp         Pfad zum lp-Befehl       (default: lp)          -- Linux/macOS
#
# Beispiel:
#   printlib::configure -printer "HP LaserJet" -source upper -duplex long
# -------------------------------------------------------------------------
proc ::printlib::configure {args} {
    variable cfg
    if {[llength $args] == 0} {
        return $cfg
    }
    foreach {opt val} $args {
        switch -- $opt {
            -backend     { dict set cfg backend   $val }
            -printer     { dict set cfg printer   $val }
            -source      { dict set cfg source    $val }
            -duplex      { dict set cfg duplex    $val }
            -paper       { dict set cfg paper     $val }
            -scale       { dict set cfg scale     $val }
            -copies      { dict set cfg copies    $val }
            -silent      { dict set cfg silent    $val }
            -orientation { dict set cfg orientation $val }
            -cut         { dict set cfg cut       $val }
            -paperw      { dict set cfg paperw    $val }
            -paperh      { dict set cfg paperh    $val }
            -ppddir      { dict set cfg ppdDir    $val }
            -pdftocairo  { dict set cfg pdftocairo $val }
            -sumatra     { dict set cfg sumatra   $val }
            -lp          { dict set cfg lp        $val }
            -pdfiumprefer { dict set cfg pdfiumPrefer [expr {!!$val}] }
            default      { error "printlib::configure: unbekannte Option: $opt" }
        }
    }
    return
}

# -------------------------------------------------------------------------
# detect -- Backend erkennen und testen
#
# Gibt zurueck: pdftocairo | sumatra | none
# Setzt activeBackend.
# -------------------------------------------------------------------------
proc ::printlib::detect {} {
    variable cfg
    variable activeBackend

    set want [dict get $cfg backend]
    set platform $::tcl_platform(platform)

    # Explizit gewuenschtes Backend
    if {$want ne "auto"} {
        if {$want ni [known]} {
            error "printlib::detect: ungueltiges Backend '$want' (erlaubt: auto, [join [known] {, }])"
        }
        if {[_available $want]} {
            set activeBackend $want
        } else {
            set activeBackend none
        }
        return $activeBackend
    }

    # Auto: die fuer diese Plattform in Frage kommenden Backends aus der
    # Registry, in Registry-Reihenfolge, und das erste verfuegbare nehmen.
    # (pdftocairo -print existiert nur in der Windows-Version, nicht in
    # poppler-utils auf Linux/macOS -- deshalb steht dort in der Registry
    # nur lp fuer unix.)
    set chain [_backendsFor $platform]

    # pdfiumPrefer zieht pdfium unter Windows nach vorn. Ohne die Vorwahl
    # steht in der Registry pdftocairo zuerst (bessere Vektorqualitaet).
    if {$platform eq "windows" && [dict get $cfg pdfiumPrefer]} {
        set chain [linsert [lsearch -all -inline -not $chain pdfium] 0 pdfium]
    }

    set activeBackend none
    foreach be $chain {
        if {[_available $be]} { set activeBackend $be ; break }
    }
    return $activeBackend
}

# Backends, die auf dieser Plattform ueberhaupt in Frage kommen, in
# Registry-Reihenfolge. Liest nur die Registry -- kein Backend-Name faellt.
proc ::printlib::_backendsFor {platform} {
    variable backends
    set out {}
    dict for {name spec} $backends {
        if {$platform in [dict get $spec platforms]} { lappend out $name }
    }
    return $out
}

# Backends mit eigenen .<backend>-Konfigdateien (PPD), aus der Registry.
# Ersetzt die frueher mehrfach kopierte Liste {pdftocairo sumatra}.
proc ::printlib::_ppdBackends {} {
    variable backends
    set out {}
    dict for {name spec} $backends {
        if {[dict exists $spec ppd] && [dict get $spec ppd]} { lappend out $name }
    }
    return $out
}

# -------------------------------------------------------------------------
# print -- PDF-Datei drucken
#
# Argumente:
#   pdffile         Pfad zur PDF-Datei
#   ?-option val?   Temporaere Optionen (ueberschreiben configure-Werte)
#
# Optionen wie bei configure (-printer -source -duplex -paper -copies)
# plus:
#   -backend  pdftocairo | sumatra   (einmalige Auswahl)
#   -pages    first-last             (Seitenbereich, z.B. "1-3")
#   -silent   1 | 0                  (Fehlermeldungen unterdruecken)
#
# Gibt "" zurueck bei Erfolg, Fehlermeldung bei Fehler.
# -------------------------------------------------------------------------
proc ::printlib::print {pdffile args} {
    variable cfg
    variable activeBackend

    # Datei pruefen
    if {![file exists $pdffile]} {
        error "printlib::print: Datei nicht gefunden: $pdffile"
    }
    if {[string tolower [file extension $pdffile]] ne ".pdf"} {
        error "printlib::print: Keine PDF-Datei: $pdffile"
    }

    # Temporaere Optionen parsen (ueberschreiben cfg fuer diesen Aufruf)
    set local [dict create \
        backend     [dict get $cfg backend] \
        printer     [dict get $cfg printer] \
        source      [dict get $cfg source] \
        duplex      [dict get $cfg duplex] \
        paper       [dict get $cfg paper] \
        scale       [dict get $cfg scale] \
        copies      [dict get $cfg copies] \
        silent      [dict get $cfg silent] \
        orientation [dict get $cfg orientation] \
        cut         [dict get $cfg cut] \
        paperw      [dict get $cfg paperw] \
        paperh      [dict get $cfg paperh] \
        pages       "" \
    ]
    # Tracking: welche Optionen wurden im print-Aufruf explizit gesetzt?
    # (relevant fuer 0.2 PPD-Autoload: explizite Optionen haben Vorrang
    # vor Datei-Werten, configure-Defaults nicht.)
    set cliKeys {}
    foreach {opt val} $args {
        switch -- $opt {
            -backend     { dict set local backend     $val; lappend cliKeys backend }
            -printer     { dict set local printer     $val; lappend cliKeys printer }
            -source      { dict set local source      $val; lappend cliKeys source }
            -duplex      { dict set local duplex      $val; lappend cliKeys duplex }
            -paper       { dict set local paper       $val; lappend cliKeys paper }
            -scale       { dict set local scale       $val; lappend cliKeys scale }
            -copies      { dict set local copies      $val; lappend cliKeys copies }
            -pages       { dict set local pages       $val; lappend cliKeys pages }
            -silent      { dict set local silent      $val; lappend cliKeys silent }
            -orientation { dict set local orientation $val; lappend cliKeys orientation }
            -cut         { dict set local cut         $val; lappend cliKeys cut }
            -paperw      { dict set local paperw      $val; lappend cliKeys paperw }
            -paperh      { dict set local paperh      $val; lappend cliKeys paperh }
            default      { error "printlib::print: unbekannte Option: $opt" }
        }
    }

    # Backend bestimmen
    set be [dict get $local backend]
    if {$be eq "auto"} {
        detect
        set be $activeBackend
    } else {
        # Explizit gewaehltes Backend pruefen und activeBackend aktualisieren
        # (Bugfix 0.1.1: vorher blieb activeBackend bei auto-detect-Wert stehen)
        if {$be ni [known]} {
            error "printlib::print: unbekanntes Backend: $be"
        }
        if {![_available $be]} {
            error "printlib::print: Backend '$be' nicht verfuegbar"
        }
        set activeBackend $be
    }
    if {$be eq "none"} {
        error "printlib::print: kein Druckbackend verfuegbar"
    }

    # PPD-Autoload (neu in 0.2): wenn ein -printer angegeben wurde und
    # eine passende .pdftocairo / .sumatra Datei existiert, deren Werte
    # uebernehmen -- aber nur fuer Optionen, die im print-Aufruf NICHT
    # explizit gesetzt wurden.
    # lp nutzt das gleiche PPD-Format wie pdftocairo (Linux-Konvention).
    set printer [dict get $local printer]
    if {$printer ne ""} {
        set ppdBackend [expr {$be eq "lp" ? "pdftocairo" : $be}]
        set ppdPath [findPpdFile $printer $ppdBackend]
        if {$ppdPath ne ""} {
            _applyPpdToOpts local [loadPpdFile $ppdPath] $cliKeys
        }
    }

    # Drucken
    if {$be eq "pdftocairo"} {
        return [_print_pdftocairo $pdffile $local]
    } elseif {$be eq "sumatra"} {
        return [_print_sumatra $pdffile $local]
    } elseif {$be eq "lp"} {
        return [_print_lp $pdffile $local]
    } elseif {$be eq "pdfium"} {
        return [_print_pdfium $pdffile $local]
    } else {
        error "printlib::print: unbekanntes Backend: $be"
    }
}

# -------------------------------------------------------------------------
# _pdfPageSize -- Seitengroesse der ersten PDF-Seite in Punkten ermitteln
#
# Rueckgabe: Liste {width_pt height_pt} oder {} wenn nicht ermittelbar.
#
# Versucht zuerst pdfinfo (poppler, kommt mit pdftocairo), dann als
# Fallback einen Regex auf die MediaBox.
# -------------------------------------------------------------------------
proc ::printlib::_pdfPageSize {pdffile} {
    # 1) pdfinfo, falls vorhanden
    if {[llength [auto_execok pdfinfo]] > 0} {
        if {![catch {exec pdfinfo $pdffile} out]} {
            # Zeile: "Page size:       175.745 x 82.2034 pts"
            if {[regexp {Page size:\s*([\d.]+)\s*x\s*([\d.]+)} $out -> w h]} {
                return [list $w $h]
            }
        }
    }
    # 2) Fallback: MediaBox aus der Datei lesen
    if {![catch {
        set fd [open $pdffile rb]
        set data [read $fd 65536]
        close $fd
    }]} {
        if {[regexp {/MediaBox\s*\[\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)} \
                $data -> x0 y0 x1 y1]} {
            return [list [expr {$x1 - $x0}] [expr {$y1 - $y0}]]
        }
    }
    return {}
}

# -------------------------------------------------------------------------
# _print_pdftocairo -- Drucken via pdftocairo (Vektor, Cairo Win32)
# -------------------------------------------------------------------------
proc ::printlib::_print_pdftocairo {pdffile opts} {
    variable cfg

    set exe [dict get $cfg pdftocairo]
    set cmd [list $exe -print]

    # Hinweis: pdftocairo -print hat keine direkte Option fuer
    # orientation oder cut. Auf Windows entscheidet die DEVMODE des
    # Druckers ueber die Orientierung; Cut-Verhalten ist treiber-intern
    # (Brother-Treiber-Eigenschaft). Beide Werte werden hier ignoriert,
    # ein Hinweis kommt nur, wenn sie explizit gesetzt wurden.

    # Drucker
    set printer [dict get $opts printer]
    if {$printer ne ""} {
        lappend cmd -printer $printer
    }

    # printopt: source und duplex
    set popt {}
    set source [dict get $opts source]
    if {$source ne ""} {
        lappend popt "source=$source"
    }
    set duplex [dict get $opts duplex]
    if {$duplex ne "off" && $duplex ne ""} {
        lappend popt "duplex=$duplex"
    }
    if {[llength $popt] > 0} {
        lappend cmd -printopt [join $popt ","]
    }

    # Skalierung zuerst bestimmen
    # pdftocairo-Optionen:
    #   (nichts)              = noscale: zentriert, nicht skaliert
    #   -expand               = vergroessern wenn kleiner, ggf. verkleinern
    #   -expand -noshrink     = nur vergroessern
    #   -noshrink             = nur Verkleinerung verhindern (= shrink-Modus aus)
    #   -origpagesizes        = origsize: Papier an PDF anpassen
    #   -paper match          = match: Papier = Seitengroesse
    #
    # SONDERFALL Etiketten-Drucker: Bei DK-Formaten ist immer der
    # 1:1-Druck (Originalgroesse) korrekt. Andere Scale-Modi fuehren
    # ueber -paperw/-paperh zu einer 90-Grad-Drehung und/oder Abschnitt,
    # weil pdftocairo die Seite auf ein definiertes Papier legt und der
    # QL-Treiber sie aufs Band rotiert. Daher: bei Etiketten immer
    # -origpagesizes, scale-Auswahl wird ignoriert.
    set paper [dict get $opts paper]
    set isLabelPaper [expr {![catch {labelsize $paper}]}]

    # Hoechste Prioritaet: explizite paperw/paperh (zum Experimentieren).
    # Wenn beide gesetzt sind, werden sie direkt durchgereicht -- das
    # bringt auch die (bei Etiketten gewuenschte) Drehung zurueck, weil
    # pdftocairo die Seite auf das definierte Papier legt.
    set pw [dict get $opts paperw]
    set ph [dict get $opts paperh]
    if {$pw ne "" && $ph ne ""} {
        lappend cmd -paperw $pw -paperh $ph
    } elseif {$isLabelPaper} {
        # Etiketten ohne explizite Masse: 1:1 ohne Drehung (origpagesizes).
        lappend cmd -origpagesizes
    } else {
        set scale [dict get $opts scale]
        switch -- $scale {
            fit       { lappend cmd -expand }
            expand    { lappend cmd -expand -noshrink }
            shrink    { lappend cmd -noshrink }
            match     { lappend cmd -paper match }
            origsize  { lappend cmd -origpagesizes }
            nocenter  { lappend cmd -nocenter }
            noscale   -
            default   { }
        }

        # Papier nur bei normalem Drucker und gueltiger pdftocairo-Groesse
        set validPapers {letter legal A4 A3 Letter Legal a4 a3 match}
        if {$paper ne "" && $scale ni {match origsize}} {
            if {$paper in $validPapers} {
                lappend cmd -paper $paper
            }
            # Unbekannte Groesse: bewusst nichts setzen.
        }
    }

    # Seitenbereich
    set pages [dict get $opts pages]
    if {$pages ne ""} {
        if {[regexp {^(\d+)-(\d+)$} $pages -> f l]} {
            lappend cmd -f $f -l $l
        } elseif {[string is integer $pages]} {
            lappend cmd -f $pages -l $pages
        }
    }

    lappend cmd $pdffile

    if {[dict get $opts silent]} {
        lappend cmd -q
    }

    # 2>@1: stderr auf stdout umleiten, damit Font-Warnungen von
    # pdftocairo (Symbol, ArialUnicode) keinen Tcl-Fehler ausloesen.
    # Echter Fehler: Exit-Code != 0, erkennbar an "child process exited"
    lappend cmd 2>@1

    # Kopien: pdftocairo hat keine native -copies-Option (Stand 2026).
    # Workaround: n-mal nacheinander drucken. Bei Fehler im Lauf wird
    # abgebrochen und der bisher gelaufene Druckumfang gemeldet.
    set copies [dict get $opts copies]
    if {![string is integer -strict $copies] || $copies < 1} {
        set copies 1
    }
    for {set i 1} {$i <= $copies} {incr i} {
        if {[catch {exec {*}$cmd} err]} {
            # Nur echter Fehler (Exit-Code != 0) — Warnungen durchlassen
            if {[string match "*child process exited abnormally*" $err] ||
                [string match "*Error:*" $err]} {
                if {$copies > 1} {
                    error "printlib (pdftocairo): Fehler in Kopie $i von $copies: $err"
                } else {
                    error "printlib (pdftocairo): $err"
                }
            }
        }
    }
    return ""
}

# -------------------------------------------------------------------------
# _print_sumatra -- Drucken via SumatraPDF (Bitmap-Fallback)
# -------------------------------------------------------------------------
proc ::printlib::_print_sumatra {pdffile opts} {
    variable cfg

    set exe [dict get $cfg sumatra]
    set cmd [list $exe]

    # Drucker
    set printer [dict get $opts printer]
    if {$printer ne ""} {
        lappend cmd -print-to $printer
    } else {
        lappend cmd -print-to-default
    }

    # print-settings aufbauen
    set settings {}

    # Kassette
    set source [dict get $opts source]
    if {$source ne ""} {
        lappend settings "bin=$source"
    }

    # Duplex
    set duplex [dict get $opts duplex]
    switch -- $duplex {
        long  { lappend settings "duplexlong" }
        short { lappend settings "duplexshort" }
    }

    # Papier
    set paper [dict get $opts paper]
    if {$paper ne ""} {
        lappend settings "paper=$paper"
    }

    # Skalierung (SumatraPDF print-settings)
    set scale [dict get $opts scale]
    switch -- $scale {
        fit      { lappend settings "fit" }
        shrink   { lappend settings "shrink" }
        expand   -
        noscale  -
        default  { lappend settings "noscale" }
    }

    # Kopien (Bugfix 0.1.1: vorher las das eine nicht definierte
    # Variable $copies, was bei jedem -copies > 1 abbrach.)
    set copies [dict get $opts copies]
    if {$copies > 1} {
        lappend settings "${copies}x"
    }

    # Orientierung (SumatraPDF unterstuetzt portrait/landscape in
    # -print-settings)
    set orient [dict get $opts orientation]
    if {$orient eq "landscape"} {
        lappend settings "landscape"
    } elseif {$orient eq "portrait"} {
        lappend settings "portrait"
    }

    # Seitenbereich
    set pages [dict get $opts pages]
    if {$pages ne ""} {
        lappend settings $pages
    }

    if {[llength $settings] > 0} {
        lappend cmd -print-settings [join $settings ","]
    }

    # silent: Fehlerdialog unterdruecken (Bugfix 0.1.1: vorher ignoriert)
    if {[dict get $opts silent]} {
        lappend cmd -silent
    }

    lappend cmd $pdffile

    if {[catch {exec {*}$cmd} err]} {
        error "printlib (SumatraPDF): $err"
    }
    return ""
}

# -------------------------------------------------------------------------
# _print_lp -- Drucken via lp (CUPS, Linux/macOS)
#
# Mappt printlib-Optionen auf lp-Argumente:
#   -printer X  -> -d X
#   -copies N   -> -n N             (nativ!)
#   -source X   -> -o InputSlot=X   (treiberspezifisch, capitalisiert)
#   -duplex Y   -> -o sides=...     (one-sided / two-sided-long-edge / two-sided-short-edge)
#   -paper X    -> -o media=X       (z.B. A4, A3, Letter)
#   -scale fit  -> -o fit-to-page
#   -pages X    -> -P X             (Range "1-3" oder Liste "1,3,5")
#                  oder -o page-set=odd|even
#
# CUPS hat keine direkten Entsprechungen fuer 'match' und 'origsize' --
# diese werden ignoriert (lp gibt das PDF dann nativ aus, der Drucker-
# treiber entscheidet ueber das Mapping aufs Papier).
#
# 'silent' ist bei lp nicht noetig: lp gibt nur eine Job-ID auf stdout
# zurueck, keine Dialoge.
# -------------------------------------------------------------------------
proc ::printlib::_print_lp {pdffile opts} {
    variable cfg

    set exe [dict get $cfg lp]
    set cmd [list $exe]

    # Drucker
    set printer [dict get $opts printer]
    if {$printer ne ""} {
        lappend cmd -d $printer
    }

    # Kopien (nativ via -n)
    set copies [dict get $opts copies]
    if {![string is integer -strict $copies] || $copies < 1} {
        set copies 1
    }
    if {$copies > 1} {
        lappend cmd -n $copies
    }

    # Seitenbereich
    set pages [dict get $opts pages]
    if {$pages ne ""} {
        switch -- $pages {
            odd  -
            even { }
            default {
                # Range "1-3" oder Liste "1,3,5" -- direkt an -P
                lappend cmd -P $pages
            }
        }
    }

    # -o Optionen sammeln
    set lpOpts {}

    # Kassette: CUPS InputSlot. Werte sind treiberabhaengig -- gaengig:
    # Upper, Lower, Middle, Manual, Auto, Envelope, Tray1, Tray2, ...
    # printlib uebergibt den Wert wie eingegeben (string totitle hilft).
    set source [dict get $opts source]
    if {$source ne ""} {
        lappend lpOpts "InputSlot=[string totitle $source]"
    }

    # Duplex: nur 'long' und 'short' aktiv setzen. 'off' (Default) bedeutet
    # "nicht ueberschreiben" -- der Drucker-Standard gilt.
    set duplex [dict get $opts duplex]
    switch -- $duplex {
        long  { lappend lpOpts "sides=two-sided-long-edge" }
        short { lappend lpOpts "sides=two-sided-short-edge" }
    }

    # Papier -- explizite paperw/paperh haben Vorrang (Custom-Media).
    # CUPS akzeptiert custom Groessen als Custom.WIDTHxHEIGHT in Punkten.
    set pw [dict get $opts paperw]
    set ph [dict get $opts paperh]
    set paper [dict get $opts paper]
    if {$pw ne "" && $ph ne ""} {
        lappend lpOpts "media=Custom.${pw}x${ph}"
    } elseif {$paper ne ""} {
        lappend lpOpts "media=$paper"
    }

    # Skalierung
    set scale [dict get $opts scale]
    switch -- $scale {
        fit    -
        shrink -
        expand { lappend lpOpts "fit-to-page" }
        match    -
        origsize -
        noscale  -
        default  { }
    }

    # Seitenbereich odd/even ueber -o page-set
    switch -- $pages {
        odd  { lappend lpOpts "page-set=odd" }
        even { lappend lpOpts "page-set=even" }
    }

    # Orientierung (CUPS-Standard: 3=portrait, 4=landscape)
    set orient [dict get $opts orientation]
    switch -- $orient {
        landscape          { lappend lpOpts "orientation-requested=4" }
        portrait           { }  ;# CUPS-Default
        reverse-landscape  { lappend lpOpts "orientation-requested=5" }
        reverse-portrait   { lappend lpOpts "orientation-requested=6" }
    }

    # Auto-Cut (Brother QL-Drucker): CUPS-Treiber-spezifisch.
    # Brother CUPS-Treiber kennen typischerweise CutLabel oder AutoCut.
    # Es werden mehrere gaengige Schalter gesetzt -- der Treiber waehlt
    # den passenden, unbekannte werden ignoriert.
    set cutMode [dict get $opts cut]
    switch -- $cutMode {
        on    -
        auto  -
        always {
            # Nach jedem Etikett schneiden
            lappend lpOpts "CutLabel=ON"
            lappend lpOpts "AutoCut=ON"
        }
        off   -
        none  -
        never {
            lappend lpOpts "CutLabel=OFF"
            lappend lpOpts "AutoCut=OFF"
        }
        end {
            # Nur am Job-Ende schneiden
            lappend lpOpts "CutAtEnd=ON"
        }
    }

    # Alle -o Optionen anhaengen
    foreach o $lpOpts {
        lappend cmd -o $o
    }

    lappend cmd $pdffile

    if {[catch {exec {*}$cmd} err]} {
        error "printlib (lp): $err"
    }
    return ""
}

# -------------------------------------------------------------------------
# printerlist -- Alle verfuegbaren Drucker auflisten
# Windows: twapi::enumerate_printers gibt ein recordarray zurueck
# -------------------------------------------------------------------------
proc ::printlib::printerlist {} {
    if {$::tcl_platform(platform) eq "windows"} {
        # twapi recordarray: fields + getlist
        catch {
            set ra   [twapi::enumerate_printers]
            set keys [twapi::recordarray fields $ra]
            set rows [twapi::recordarray getlist $ra]
            set ni   [lsearch $keys -name]
            set result {}
            foreach row $rows {
                set name [lindex $row $ni]
                if {$name ne ""} { lappend result $name }
            }
            if {[llength $result] > 0} {
                return [lsort $result]
            }
        }
        # Fallback: Registry
        package require registry
        set key {HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\Devices}
        set result {}
        catch {
            foreach item [registry values $key] {
                lappend result $item
            }
        }
        return [lsort $result]
    } else {
        if {![catch {set out [exec lpstat -a 2>@1]}]} {
            set result {}
            foreach line [split $out \n] {
                if {[regexp {^(\S+)\s} $line -> name]} {
                    lappend result $name
                }
            }
            return [lsort $result]
        }
        return {}
    }
}

# -------------------------------------------------------------------------
# defaultprinter -- Standarddrucker abfragen
#
# Windows: HKCU\...\Windows -> Device = "Name,winspool,Port:"
# Linux:   lpstat -d
# -------------------------------------------------------------------------
proc ::printlib::defaultprinter {} {
    if {$::tcl_platform(platform) eq "windows"} {
        package require registry
        set key {HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\Windows}
        if {![catch {
            set val [registry get $key {Device}]
            set name [lindex [split $val ","] 0]
        }]} {
            return [string trim $name]
        }
        return ""
    } else {
        if {![catch {set out [exec lpstat -d]}]} {
            if {[regexp {:\s+(.+)$} $out -> name]} {
                return [string trim $name]
            }
        }
        return ""
    }
}

# -------------------------------------------------------------------------
# resolvePrinter -- Logischen Druckernamen plattformübergreifend aufloesen
#
# Hintergrund: derselbe physische Drucker hat oft unterschiedliche Namen,
# je nach System -- z.B.:
#   Windows: "Brother QL-820NWB"
#   Linux:   "Brother_QL-820NWB_IPP"
# Mit dieser Funktion kann ein gemeinsames Skript auf beiden Plattformen
# funktionieren:
#   set printer [printlib::resolvePrinter "QL-820NWB"]
#   printlib::print pdf -printer $printer
#
# Suche:
#   1. Exakter Match in printerlist
#   2. Case-insensitive Match
#   3. Substring-Match (case-insensitive): "QL-820NWB" matched
#      "Brother QL-820NWB" und "Brother_QL-820NWB_IPP"
#   4. Normalisiert (Leerzeichen, Unterstrich, Bindestrich entfernt)
#
# Eindeutigkeit erforderlich -- bei mehrfachem Treffer wird ein Fehler
# geworfen, damit der Aufrufer den Pattern praeziser macht.
# -------------------------------------------------------------------------
proc ::printlib::resolvePrinter {pattern} {
    set printers [printerlist]
    if {[llength $printers] == 0} {
        error "printlib::resolvePrinter: keine Drucker bekannt (printerlist leer)"
    }

    # 1) Exakter Match
    if {$pattern in $printers} {
        return $pattern
    }

    # 2) Case-insensitive exakt
    foreach p $printers {
        if {[string equal -nocase $pattern $p]} {
            return $p
        }
    }

    # 3) Substring (case-insensitive)
    set matches {}
    foreach p $printers {
        if {[string match -nocase "*$pattern*" $p]} {
            lappend matches $p
        }
    }
    if {[llength $matches] == 1} {
        return [lindex $matches 0]
    }
    if {[llength $matches] > 1} {
        error "printlib::resolvePrinter: '$pattern' matched mehrere Drucker:\
               [join $matches {, }]"
    }

    # 4) Normalisiert: Sonderzeichen ignorieren
    # "QL 820 NWB" matched "Brother_QL-820NWB_IPP"
    set normPat [string toupper [regsub -all {[\s_\-]+} $pattern ""]]
    set matches {}
    foreach p $printers {
        set normP [string toupper [regsub -all {[\s_\-]+} $p ""]]
        if {[string match "*${normPat}*" $normP]} {
            lappend matches $p
        }
    }
    if {[llength $matches] == 1} {
        return [lindex $matches 0]
    }
    if {[llength $matches] > 1} {
        error "printlib::resolvePrinter: '$pattern' (normalisiert) matched mehrere:\
               [join $matches {, }]"
    }

    error "printlib::resolvePrinter: '$pattern' nicht gefunden -- verfuegbar:\
           [join $printers {, }]"
}

# -------------------------------------------------------------------------
# exportPrinterConfig / importPrinterConfig (nur Windows)
#
# Sichert bzw. setzt die kompletten Druckereinstellungen (DEVMODE,
# inklusive der treiber-privaten Brother-Etiketten-Daten) ueber
# printui.dll. Anwendungsfall: eine einmal im Treiber-Dialog korrekt
# eingestellte Etikettengroesse maschinenuebergreifend automatisch
# verteilen, ohne dass ein Nutzer den Treiber-Dialog oeffnen muss.
#
# Workflow:
#   1. Drucker einmal manuell korrekt einstellen (Etikettengroesse etc.)
#   2. exportPrinterConfig "Brother QL-820NWB" ql-settings.dat
#   3. Auf Zielmaschine (gleicher Treiber/Drucker):
#      importPrinterConfig "Brother QL-820NWB" ql-settings.dat
#
# Hinweis: Das Setzen der globalen DEVMODE erfordert in der Regel
# Administrator-Rechte. Bei fehlenden Rechten schlaegt der Import fehl.
#
# Die Datentyp-Flags steuern, was gesichert/gesetzt wird. Default "" =
# printui.dll-Standardumfang (Speichern: alles). Flags (kombinierbar,
# mit Leerzeichen getrennt) laut printui.dll-Hilfe:
#   2  PRINTER_INFO_2 (Geraetestatus, Eigenschaften)
#   7  PRINTER_INFO_7 (Verzeichnis-/Plug&Play-Daten)
#   c  Farbprofil
#   d  Druckerdaten
#   s  Sicherheitsbeschreibung
#   g  DevMode (global)   <- Treiber-Default, enthaelt Etikettengroesse
#   u  DevMode (Benutzer)
#   m  Minimale Einstellungen
#   r,f,p,i  Konflikt-/Port-Aufloesung beim Wiederherstellen
#
# Empfehlung fuer Etiketten-Einstellung (in der Praxis bestaetigt):
#   Speichern:        exportPrinterConfig $p $f       (alles sichern)
#   Wiederherstellen: importPrinterConfig $p $f       (alles, OHNE Flags)
# Der Standard-Umfang von /Sr stellt die komplette Einstellung
# inklusive Etikettengroesse wieder her. Die Datentyp-Flags (g d u
# usw.) sind nur noetig, wenn man gezielt EINSCHRAENKEN will, was
# wiederhergestellt wird -- fuer den Normalfall leer lassen.
# -------------------------------------------------------------------------
proc ::printlib::exportPrinterConfig {printer file {datatypes ""}} {
    if {$::tcl_platform(platform) ne "windows"} {
        error "printlib::exportPrinterConfig: nur unter Windows verfuegbar"
    }
    set cmd [list rundll32 printui.dll,PrintUIEntry \
                  /Ss /n $printer /a [file nativename $file]]
    if {$datatypes ne ""} {
        lappend cmd {*}$datatypes
    }
    if {[catch {exec {*}$cmd} err]} {
        error "printlib::exportPrinterConfig fehlgeschlagen: $err"
    }
    return $file
}

proc ::printlib::importPrinterConfig {printer file {datatypes ""}} {
    if {$::tcl_platform(platform) ne "windows"} {
        error "printlib::importPrinterConfig: nur unter Windows verfuegbar"
    }
    if {![file exists $file]} {
        error "printlib::importPrinterConfig: Datei nicht gefunden: $file"
    }
    set cmd [list rundll32 printui.dll,PrintUIEntry \
                  /Sr /n $printer /a [file nativename $file]]
    if {$datatypes ne ""} {
        lappend cmd {*}$datatypes
    }
    if {[catch {exec {*}$cmd} err]} {
        error "printlib::importPrinterConfig fehlgeschlagen\
               (evtl. Admin-Rechte noetig): $err"
    }
    return $file
}

# -------------------------------------------------------------------------
# Drucker-Profile (nur Windows)
#
# Ein Profil ist eine gespeicherte Druckereinstellung (.dat aus
# exportPrinterConfig). Damit lassen sich verschiedene Etikettengroessen
# fuer denselben Drucker vorhalten und vor dem Druck umschalten -- ein
# pragmatischer Weg fuer wechselnde Formate ohne Raster-Protokoll.
#
# Profile liegen als <profilDir>/<normPrinter>__<profil>.dat
# profilDir-Suche analog PPD: cfg(ppdDir) -> [pwd]/profiles ->
# [scriptDir]/profiles
#
# Beispiel:
#   # Aktuelle Treibereinstellung als Profil "klein" sichern:
#   printlib::savePrinterProfile "Brother QL-820NWB" klein
#   # ... Treiber auf anderes Format stellen ...
#   printlib::savePrinterProfile "Brother QL-820NWB" versand
#
#   # Vor dem Druck umschalten:
#   printlib::usePrinterProfile "Brother QL-820NWB" klein
#   printlib::print etikett.pdf -printer "Brother QL-820NWB"
# -------------------------------------------------------------------------
proc ::printlib::_profileDirs {} {
    variable cfg
    set dirs {}
    set pd [dict get $cfg ppdDir]
    if {$pd ne ""} { lappend dirs [file join $pd profiles] }
    lappend dirs [file join [pwd] profiles]
    set sd [file dirname [info script]]
    if {$sd ne "" && $sd ne "."} {
        lappend dirs [file join $sd profiles]
    }
    return $dirs
}

proc ::printlib::_profilePath {printer profile {forWrite 0}} {
    set fname "[_normPpdName $printer]__${profile}.dat"
    foreach dir [_profileDirs] {
        set full [file join $dir $fname]
        if {[file exists $full]} { return $full }
    }
    if {$forWrite} {
        # Erstes Verzeichnis, das existiert oder anlegbar ist
        set dir [lindex [_profileDirs] 0]
        file mkdir $dir
        return [file join $dir $fname]
    }
    return ""
}

# Aktuelle Druckereinstellung als benanntes Profil sichern
proc ::printlib::savePrinterProfile {printer profile} {
    set path [_profilePath $printer $profile 1]
    exportPrinterConfig $printer $path
    return $path
}

# Druckeinstellungs-Dialog oeffnen (Printing Preferences, /e).
# Dort stellt man Papier-/Etikettenformat ein. Oeffnet asynchron --
# der Aufrufer ruft danach savePrinterProfile auf, wenn er fertig ist.
# Workflow fuer mehrere Groessen:
#   openPrinterSettings "Brother QL-820NWB"        ;# 62x29 einstellen, OK
#   savePrinterProfile  "Brother QL-820NWB" klein
#   openPrinterSettings "Brother QL-820NWB"        ;# 62x100 einstellen, OK
#   savePrinterProfile  "Brother QL-820NWB" versand
proc ::printlib::openPrinterSettings {printer} {
    if {$::tcl_platform(platform) ne "windows"} {
        error "printlib::openPrinterSettings: nur unter Windows verfuegbar"
    }
    # Asynchron starten (Dialog blockiert sonst die Tcl-Session)
    exec rundll32 printui.dll,PrintUIEntry /e /n $printer &
    return
}

# Benanntes Profil anwenden (importiert die .dat). Optional Spooler-
# Neustart, falls die Einstellung sonst nicht sofort greift.
proc ::printlib::usePrinterProfile {printer profile {restartSpooler 0}} {
    set path [_profilePath $printer $profile]
    if {$path eq ""} {
        error "printlib::usePrinterProfile: Profil '$profile' fuer\
               '$printer' nicht gefunden"
    }
    importPrinterConfig $printer $path
    if {$restartSpooler} {
        catch {exec net stop spooler}
        catch {exec net start spooler}
    }
    return $path
}

# Verfuegbare Profile fuer einen Drucker auflisten
proc ::printlib::listPrinterProfiles {printer} {
    set prefix "[_normPpdName $printer]__"
    set result {}
    foreach dir [_profileDirs] {
        if {![file isdirectory $dir]} continue
        foreach f [glob -nocomplain -directory $dir "${prefix}*.dat"] {
            set base [file rootname [file tail $f]]
            set name [string range $base [string length $prefix] end]
            if {$name ni $result} { lappend result $name }
        }
    }
    return $result
}

# -------------------------------------------------------------------------
# printerinfo -- Basis-Info zu einem Drucker aus der Registry
#
# Gibt ein Dict zurueck mit:
#   name        Druckername
#   portName    Port (USB001, LPT1, \\server\name)
#   driverName  Treibername
#   description Beschreibung
#   location    Standort (wenn gesetzt)
#   isNetwork   1 wenn Netzwerkdrucker
#   isShared    1 wenn freigegeben
#   isDefault   1 wenn Standarddrucker
# -------------------------------------------------------------------------
proc ::printlib::printerinfo {printername} {
    if {$::tcl_platform(platform) ne "windows"} {
        return [dict create name $printername]
    }
    package require registry
    set base {HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Print\Printers}
    set result [dict create name $printername]

    # Attributes-Flags (DWORD)
    catch {
        set attr [registry get "$base\\$printername" "Attributes"]
        dict set result isShared  [expr {($attr & 0x08) != 0}]
        dict set result isNetwork [expr {($attr & 0x10) != 0}]
    }

    # DsSpooler: portName, driverName, description, location, uNCName
    set sp "$base\\$printername\\DsSpooler"
    foreach key {portName driverName description location uNCName} {
        catch { dict set result $key [registry get $sp $key] }
    }

    # Standarddrucker markieren
    dict set result isDefault [expr {$printername eq [::printlib::defaultprinter]}]

    return $result
}

# -------------------------------------------------------------------------
# -------------------------------------------------------------------------
# printercaps -- Faehigkeiten eines Druckers ermitteln
#
# Strategie Windows:
#   - Registry + DEVMODE: immer (Treiber, Port, Farbe, Duplex, DPI)
#   - SumatraPDF -enum-printers: wenn verfuegbar (Kassettennamen)
#   - twapi: NUR fuer defaultprinter (zu alte API fuer Caps)
#
# Rueckgabe-Dict:
#   name, driver, port, color, duplex, copies_max,
#   dpi_x, dpi_y, bin_default, bins, source
# -------------------------------------------------------------------------
proc ::printlib::printercaps {printername} {
    if {$::tcl_platform(platform) ne "windows"} {
        return [::printlib::_printercaps_linux $printername]
    }

    # WMI Win32_PrinterConfiguration -- zuverlaessige Hardware-Eigenschaften
    # (DEVMODE enthaelt Job-Einstellungen, nicht Hardware-Caps)
    set result [::printlib::_printercaps_wmi $printername]

    # Kassettennamen via SumatraPDF ergaenzen (wenn verfuegbar)
    if {[::printlib::_available sumatra]} {
        catch {
            set out [exec [dict get $::printlib::cfg sumatra] \
                -enum-printers 2>@1]
            foreach line [split $out \n] {
                set parts [split [string trim $line] \t]
                if {[lindex $parts 0] eq $printername} {
                    set bins [lrange $parts 1 end]
                    if {[llength $bins] > 0} {
                        dict set result bins $bins
                    }
                    break
                }
            }
        }
    }

    return $result
}

# -------------------------------------------------------------------------
# printercaps_all -- Alle Drucker mit Faehigkeiten
#
# Bugfix 0.1.1: Wenn ein einzelner Drucker bei printercaps fehlschlaegt
# (Zugriff verweigert, Treiber kaputt, Drucker offline), wird der Eintrag
# uebersprungen statt die ganze Funktion abzubrechen.
# -------------------------------------------------------------------------
proc ::printlib::printercaps_all {} {
    set result {}
    foreach name [::printlib::printerlist] {
        if {[catch {::printlib::printercaps $name} caps]} {
            # Defekter Drucker -- Minimal-Eintrag statt Abbruch
            lappend result [dict create name $name source error error $caps]
        } else {
            lappend result $caps
        }
    }
    return $result
}

# --- WMI Win32_PrinterConfiguration ---
# Color: 1=Mono, 2=Farbe
# Duplex: 0=nein, 1=ja, leer=unbekannt
# PaperSize: "A4 210 x 297 mm" etc.
# YResolution: DPI
proc ::printlib::_printercaps_wmi {printername} {
    set result [dict create name $printername source wmi]

    # twapi_printer laden
    catch { package require twapi_printer }

    # twapi recordarray: getlist liefert {keys} {datenliste}
    # keys = {-name -server -attrs}
    # Jeder Eintrag = {name server attrs}
    catch {
        set ra   [twapi::enumerate_printers]
        set keys [twapi::recordarray fields $ra]
        set rows [twapi::recordarray getlist $ra]
        set ni [lsearch $keys -name]
        set ai [lsearch $keys -attrs]
        set si [lsearch $keys -server]
        foreach row $rows {
            if {[lindex $row $ni] eq $printername} {
                if {$ai >= 0} {
                    set attrs [lindex $row $ai]
                    dict set result isNetwork [expr {"network" in $attrs}]
                    dict set result isShared  [expr {"shared"  in $attrs}]
                }
                if {$si >= 0} {
                    set srv [lindex $row $si]
                    if {$srv ne ""} { dict set result server $srv }
                }
                break
            }
        }
    }

    # Registry: Treiber + Port aus DsSpooler
    package require registry
    set base {HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Print\Printers}
    catch {dict set result driver \
        [registry get "$base\\$printername\\DsSpooler" driverName]}
    catch {dict set result port   \
        [registry get "$base\\$printername\\DsSpooler" portName]}

    # WMI via PowerShell (funktioniert in tclsh UND wish)
    # twapi::_wmi ist nur in tclsh verfuegbar, nicht in wish
    # PowerShell Get-WmiObject ist immer verfuegbar
    # Color/Duplex: WMI Win32_Printer via PowerShell .ps1
    # Hinweis: viele Treiber (z.B. Kyocera) fuellen ColorSupported/Duplex nicht.
    # In dem Fall bleibt color/duplex leer -- kein Fehler.
    set ::env(PRINTLIB_PRINTER) $printername
    set ps1 [file join $::env(TEMP) printlib_caps.ps1]
    catch {
        set fd [open $ps1 w]
        puts $fd {$n = $env:PRINTLIB_PRINTER}
        puts $fd {Get-WmiObject Win32_Printer |}
        puts $fd {  Where-Object {$_.Name -eq $n} |}
        puts $fd {  Select-Object ColorSupported,Duplex,HorizontalResolution,VerticalResolution |}
        puts $fd {  ConvertTo-Csv -NoTypeInformation}
        close $fd
        set out [exec powershell -NonInteractive -ExecutionPolicy Bypass -File $ps1 2>@1]
        set lines [split [string trim $out] "\n"]
        if {[llength $lines] >= 2} {
            set hdr [lmap h [split [lindex $lines 0] ,] {string trim $h \"}]
            set val [lmap v [split [lindex $lines 1] ,] {string trim $v \"}]
            set ci [lsearch -nocase $hdr ColorSupported]
            set di [lsearch -nocase $hdr Duplex]
            set xi [lsearch -nocase $hdr HorizontalResolution]
            set yi [lsearch -nocase $hdr VerticalResolution]
            catch {
                set c [lindex $val $ci]
                if {$c ne "" && $c ne "NULL"} {
                    dict set result color  [expr {$c eq "True" || int($c)}]
                }
            }
            catch {
                set d [lindex $val $di]
                if {$d ne "" && $d ne "NULL"} {
                    dict set result duplex [expr {$d eq "True" || int($d)}]
                }
            }
            catch {
                set x [lindex $val $xi]
                if {$x ne "" && $x ne "NULL" && int($x) > 0} {
                    dict set result dpi_x $x
                }
            }
            catch {
                set y [lindex $val $yi]
                if {$y ne "" && $y ne "NULL" && int($y) > 0} {
                    dict set result dpi_y $y
                }
            }
        }
    }

        # Fallback: DEVMODE fuer DPI wenn PowerShell nichts liefert
    if {![dict exists $result dpi_x]} {
        catch {
            set dm [registry get "$base\\$printername" "Default DevMode"]
            if {[string length $dm] >= 98} {
                binary scan $dm @90s dpi_x_val
                binary scan $dm @96s dpi_y_val
                if {$dpi_x_val > 0} {
                    dict set result dpi_x [expr {abs($dpi_x_val)}]
                }
                if {$dpi_y_val > 0} { dict set result dpi_y $dpi_y_val }
            }
        }
    }

    return $result
}

# --- twapi (nicht mehr aktiv genutzt) ---
proc ::printlib::_printercaps_twapi {printername} {
    return [::printlib::_printercaps_wmi $printername]
}

# --- SumatraPDF -enum-printers ---
proc ::printlib::_printercaps_sumatra {printername sumatra} {
    set result [dict create name $printername source sumatra]
    catch {
        set out [exec $sumatra -enum-printers 2>@1]
        foreach line [split $out \n] {
            set parts [split [string trim $line] \t]
            if {[lindex $parts 0] eq $printername} {
                dict set result bins [lrange $parts 1 end]
                break
            }
        }
    }
    # DEVMODE aus Registry ergaenzen
    set reg [::printlib::_printercaps_registry $printername]
    foreach key {driver port color duplex dpi_x dpi_y copies_max bin_default} {
        if {![dict exists $result $key] && [dict exists $reg $key]} {
            dict set result $key [dict get $reg $key]
        }
    }
    return $result
}

# --- Registry + DEVMODEW-Struct parsen ---
# Offsets gemaess MSDN DEVMODEW (nach 64 Byte dmDeviceName):
# 64-65  dmSpecVersion   66-67  dmDriverVersion  68-69  dmSize
# 72-75  dmFields(DWORD) 76-77  dmOrientation    78-79  dmPaperSize
# 86-87  dmCopies        88-89  dmDefaultSource  90-91  dmPrintQuality
# 92-93  dmColor         94-95  dmDuplex         96-97  dmYResolution
proc ::printlib::_printercaps_registry {printername} {
    package require registry
    set result [dict create name $printername source registry]
    set base {HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Print\Printers}
    set pkey "$base\\$printername"

    catch {dict set result driver [registry get "$pkey\\DsSpooler" driverName]}
    catch {dict set result port   [registry get "$pkey\\DsSpooler" portName]}

    catch {
        set dm  [registry get $pkey "Default DevMode"]
        set len [string length $dm]
        if {$len >= 98} {
            binary scan $dm @86s copies_val
            binary scan $dm @88s bin_val
            binary scan $dm @90s dpi_x_val
            binary scan $dm @92s color_val
            binary scan $dm @94s duplex_val
            binary scan $dm @96s dpi_y_val

            if {$copies_val > 0} { dict set result copies_max $copies_val }
            if {$dpi_x_val  > 0} { dict set result dpi_x      [expr {abs($dpi_x_val)}] }
            if {$dpi_y_val  > 0} { dict set result dpi_y      $dpi_y_val  }
            dict set result color       [expr {$color_val  == 2}]
            dict set result duplex      [expr {$duplex_val >  1}]
            dict set result bin_default [::printlib::_devmode_bin_name $bin_val]
        }
    }
    return $result
}

# =========================================================================
# Etiketten-Drucker-API (neu in 0.2)
# =========================================================================
#
# Etikettendrucker (z.B. Brother QL-Reihe, Dymo LabelWriter, Zebra) sind
# fundamental anders als Buero-Drucker: feste Materialbreite via Rolle,
# variable Etikettlaenge bei Endlos-Bandern, Sondergroessen bei Die-Cut.
#
# Die Tabellen unten beruhen auf der offiziellen Brother-Doku
# "Technische Daten der DK-Etiketten" (autoritativ) sowie dem
# brother_ql-Quellcode (labels.py). Siehe Anhang C des QL-Buchs.
#
# Format-Identifizierungssysteme im Brother-Universum:
#   - Brother-DK-Code:       DK-11201, DK-N55224  (auf der Verpackung)
#   - brother_ql-Identifier: 29x90, 62, d58       (Python-Treiber)
#   - SDK-Media-ID:          259, 333             (b-PAC, bitness-abhaengig)
# Die Drei sind nicht ineinander umrechenbar (siehe Kapitel 7).
# =========================================================================

# QL-Modell-Klassen: 'small' fuer 12-62mm Drucker, 'large' fuer bis 103mm,
# 'two_color' fuer Modelle mit Schwarz-Rot-Druck (QL-800/810W/820NWB).
variable ::printlib::_qlModelClass [dict create \
    QL-500       small  QL-550       small  QL-560       small \
    QL-570       small  QL-580N      small  QL-650TD     small \
    QL-700       small  QL-710W      small  QL-720NW     small \
    QL-800       two_color  QL-810W   two_color  QL-810Wc  two_color \
    QL-820NWB    two_color  QL-820NWBc two_color \
    QL-1050      large  QL-1050N     large  QL-1060N     large \
    QL-1100      large  QL-1100c     large \
    QL-1110NWB   large  QL-1110NWBc  large \
]

# DK-Format-Tabelle: alle bekannten Brother-DK-Etiketten.
# Felder pro DK-Code:
#   kind         die_cut | continuous | round
#   width_mm     Breite (alle Typen)
#   height_mm    Hoehe (nur die_cut)
#   diameter_mm  Durchmesser (nur round)
#   length_m     Rollenlaenge (nur continuous, in Metern)
#   pieces       Stueck pro Rolle (nur die_cut/round)
#   ql_id        brother_ql-Identifier (zum Mapping mit Python-Tool)
#   model_class  any | small | large | two_color
#                'any'       = alle QL-Modelle koennen das
#                'small'     = nur 12-62mm-Modelle
#                'large'     = nur QL-1050+ (102/103mm Druckbreite)
#                'two_color' = nur QL-800-Reihe (Schwarz-Rot)
#   material     paper | film
#   adhesion     selfadhesive | nonadhesive | reusable
#   color        white | yellow | transparent | "white red/black"
#   desc         menschenlesbare Beschreibung
variable ::printlib::_dkLabels [dict create \
    DK-11201 {kind die_cut    width_mm 29  height_mm 90  pieces 400  ql_id 29x90   model_class any   material paper adhesion selfadhesive color white desc "Adresse"} \
    DK-11202 {kind die_cut    width_mm 62  height_mm 100 pieces 300  ql_id 62x100  model_class any   material paper adhesion selfadhesive color white desc "Versand"} \
    DK-11203 {kind die_cut    width_mm 17  height_mm 87  pieces 300  ql_id 17x87   model_class any   material paper adhesion selfadhesive color white desc "Ordnerregister"} \
    DK-11204 {kind die_cut    width_mm 17  height_mm 54  pieces 400  ql_id 17x54   model_class any   material paper adhesion selfadhesive color white desc "Mehrzweck"} \
    DK-11207 {kind round      diameter_mm 58             pieces 100  ql_id d58     model_class any   material film  adhesion selfadhesive color white desc "CD/DVD"} \
    DK-11208 {kind die_cut    width_mm 38  height_mm 90  pieces 400  ql_id 39x90   model_class any   material paper adhesion selfadhesive color white desc "Adresse"} \
    DK-11209 {kind die_cut    width_mm 62  height_mm 29  pieces 800  ql_id 62x29   model_class any   material paper adhesion selfadhesive color white desc "Adresse klein"} \
    DK-11218 {kind round      diameter_mm 24             pieces 1000 ql_id d24     model_class any   material paper adhesion selfadhesive color white desc "rund"} \
    DK-11219 {kind round      diameter_mm 12             pieces 1200 ql_id d12     model_class any   material paper adhesion selfadhesive color white desc "rund klein"} \
    DK-11221 {kind die_cut    width_mm 23  height_mm 23  pieces 1000 ql_id 23x23   model_class any   material paper adhesion selfadhesive color white desc "quadratisch"} \
    DK-11234 {kind die_cut    width_mm 60  height_mm 86  pieces 260  ql_id 60x86   model_class any   material paper adhesion selfadhesive color white desc "Besucher"} \
    DK-11240 {kind die_cut    width_mm 102 height_mm 51  pieces 600  ql_id 102x51  model_class large material paper adhesion selfadhesive color white desc "Versand gross"} \
    DK-11247 {kind die_cut    width_mm 103 height_mm 164 pieces 180  ql_id 103x164 model_class large material paper adhesion selfadhesive color white desc "Versand sehr gross"} \
    DK-22214 {kind continuous width_mm 12  length_m 30.48 ql_id 12   model_class any   material paper adhesion selfadhesive color white desc "Endlos selbstklebend"} \
    DK-22210 {kind continuous width_mm 29  length_m 30.48 ql_id 29   model_class any   material paper adhesion selfadhesive color white desc "Endlos selbstklebend"} \
    DK-22225 {kind continuous width_mm 38  length_m 30.48 ql_id 38   model_class any   material paper adhesion selfadhesive color white desc "Endlos selbstklebend"} \
    DK-22223 {kind continuous width_mm 50  length_m 30.48 ql_id 50   model_class any   material paper adhesion selfadhesive color white desc "Endlos selbstklebend"} \
    DK-N55224 {kind continuous width_mm 54 length_m 30.48 ql_id 54   model_class any   material paper adhesion nonadhesive  color white desc "Endlos nicht-klebend"} \
    DK-22205 {kind continuous width_mm 62  length_m 30.48 ql_id 62   model_class any   material paper adhesion selfadhesive color white desc "Endlos selbstklebend"} \
    DK-44205 {kind continuous width_mm 62  length_m 30.48 ql_id 62   model_class any   material paper adhesion reusable    color white desc "Endlos wiederabloesbar"} \
    DK-44605 {kind continuous width_mm 62  length_m 30.48 ql_id 62   model_class any   material paper adhesion reusable    color yellow desc "Endlos wiederabloesbar gelb"} \
    DK-22246 {kind continuous width_mm 103 length_m 30.48 ql_id 103  model_class large material paper adhesion selfadhesive color white desc "Endlos breit"} \
    DK-22211 {kind continuous width_mm 29  length_m 15.24 ql_id 29   model_class any   material film  adhesion selfadhesive color white desc "Endlos Film"} \
    DK-22212 {kind continuous width_mm 62  length_m 15.24 ql_id 62   model_class any   material film  adhesion selfadhesive color white desc "Endlos Film"} \
    DK-22606 {kind continuous width_mm 62  length_m 15.24 ql_id 62   model_class any   material film  adhesion selfadhesive color yellow desc "Endlos Film gelb"} \
    DK-22113 {kind continuous width_mm 62  length_m 15.24 ql_id 62   model_class any   material film  adhesion selfadhesive color transparent desc "Endlos Film transparent"} \
    DK-22251 {kind continuous width_mm 62  length_m 15.24 ql_id 62red model_class two_color material film  adhesion selfadhesive color "white red/black" desc "Endlos Film Schwarz-Rot-Druck"} \
]

# -------------------------------------------------------------------------
# _normDkCode -- DK-Code normalisieren (Gross-Schreibung)
# "dk-22205" -> "DK-22205", "dk22205" -> "DK-22205"
# -------------------------------------------------------------------------
proc ::printlib::_normDkCode {code} {
    set code [string toupper [string trim $code]]
    # "DK22205" ohne Bindestrich -> "DK-22205"
    if {[regexp {^(DK)(N?\d+)$} $code -> prefix num]} {
        set code "${prefix}-${num}"
    }
    return $code
}

# -------------------------------------------------------------------------
# _qlModelFromPrinter -- Modell aus Druckername extrahieren
# "Brother QL-810W"    -> "QL-810W"
# "Brother_QL-1100c"   -> "QL-1100c"
# "Dymo LabelWriter"   -> ""  (kein QL)
# -------------------------------------------------------------------------
proc ::printlib::_qlModelFromPrinter {printer} {
    if {[regexp -nocase {(QL-\d+[A-Za-z]*)} $printer -> model]} {
        # Mixed case beibehalten: QL-810W bleibt QL-810W, QL-1100c bleibt QL-1100c
        # nur Praefix gross
        regsub -nocase {^ql-} $model "QL-" model
        return $model
    }
    return ""
}

# -------------------------------------------------------------------------
# _qlModelClass -- Modell-Klasse fuer einen Druckernamen
# Liefert: 'small' | 'large' | 'two_color' | 'any' (unbekannt)
# -------------------------------------------------------------------------
proc ::printlib::_qlModelClass {printer} {
    variable _qlModelClass
    set model [_qlModelFromPrinter $printer]
    if {$model eq ""} { return "any" }
    if {[dict exists $_qlModelClass $model]} {
        return [dict get $_qlModelClass $model]
    }
    return "any"
}

# -------------------------------------------------------------------------
# isLabelPrinter -- Heuristische Erkennung: ist X ein Etiketten-Drucker?
#
# Erkennungsreihenfolge:
#   1. PPD-Datei mit 'type label' (explizit gesetzt)
#   2. Druckername matched bekannten Etikettendrucker (Brother QL,
#      Dymo LabelWriter, Zebra ZT/GT, Brother QL-Reihe)
#
# Rueckgabe: 0 / 1
# -------------------------------------------------------------------------
proc ::printlib::isLabelPrinter {printer} {
    # 1) PPD pruefen (alle Backends mit Konfigdateien)
    foreach be [_ppdBackends] {
        set p [findPpdFile $printer $be]
        if {$p ne ""} {
            if {![catch {set ppd [loadPpdFile $p]}]} {
                if {[dict exists $ppd type] &&
                    [string equal -nocase [dict get $ppd type] "label"]} {
                    return 1
                }
            }
        }
    }
    # 2) Namens-Heuristik
    if {[regexp -nocase {brother.*ql-|dymo.*labelwriter|zebra.*z[tg]|brother\s*p-?touch} $printer]} {
        return 1
    }
    return 0
}

# -------------------------------------------------------------------------
# labelformats -- Liste der bekannten Etiketten-Formate fuer einen Drucker
#
# Filtert die DK-Tabelle nach Modell-Kompatibilitaet:
#   - QL-1050+ (large)   -> alle Formate inklusive DK-11240, DK-11247, DK-22246
#   - kleinere Modelle   -> nur Formate mit model_class 'any'
#   - QL-800/810W/820NWB -> zusaetzlich DK-22251 (Rot-Schwarz)
#
# Aufrufer kann optional ein Filter-Dict uebergeben:
#   labelformats $printer kind die_cut
#   labelformats $printer material film
#
# Bei nicht-Brother-QL-Druckern (z.B. Dymo) wird leere Liste zurueckgegeben
# -- diese sind im Modul (noch) nicht datenbankseitig erfasst.
# -------------------------------------------------------------------------
proc ::printlib::labelformats {printer args} {
    variable _dkLabels
    if {![isLabelPrinter $printer]} {
        return {}
    }
    # Brother-QL? Sonst keine Daten
    if {[_qlModelFromPrinter $printer] eq "" &&
        ![regexp -nocase {brother.*ql} $printer]} {
        return {}
    }

    set class [_qlModelClass $printer]
    set filters [dict create {*}$args]

    set result {}
    dict for {dk meta} $_dkLabels {
        set mc [dict get $meta model_class]
        # Modell-Kompatibilitaet
        set ok 0
        switch -- $mc {
            any        { set ok 1 }
            small      { set ok [expr {$class ne "large"}] }
            large      { set ok [expr {$class eq "large"}] }
            two_color  { set ok [expr {$class eq "two_color"}] }
        }
        if {!$ok} continue

        # Optionale Filter (kind, material, color, ...)
        set passFilter 1
        dict for {fk fv} $filters {
            if {[dict exists $meta $fk]} {
                if {![string equal -nocase [dict get $meta $fk] $fv]} {
                    set passFilter 0 ; break
                }
            } else {
                set passFilter 0 ; break
            }
        }
        if {$passFilter} {
            lappend result $dk
        }
    }
    return $result
}

# -------------------------------------------------------------------------
# labelsize -- Abmessungen eines Etiketten-Formats
#
# Eingaben:
#   format  -- DK-Code (case-insensitive, mit/ohne Bindestrich)
#
# Rueckgabe: Dict mit allen bekannten Eigenschaften, plus berechnete
#            Punkt-Werte (width_pt / height_pt / diameter_pt):
#   kind, width_mm, height_mm (oder diameter_mm), pieces, length_m,
#   ql_id, model_class, material, adhesion, color, desc,
#   width_pt, height_pt, diameter_pt
#
# Punkt-Umrechnung: 1 mm = 72 / 25.4 pt = 2.8346 pt
# -------------------------------------------------------------------------
proc ::printlib::labelsize {format} {
    variable _dkLabels
    set code [_normDkCode $format]
    if {![dict exists $_dkLabels $code]} {
        error "printlib::labelsize: unbekanntes Etiketten-Format '$format' (normalisiert: '$code')"
    }
    set d [dict get $_dkLabels $code]
    dict set d code $code
    # Punkte ergaenzen
    set mmToPt 2.8346456692913385
    foreach {mmKey ptKey} {width_mm width_pt height_mm height_pt diameter_mm diameter_pt} {
        if {[dict exists $d $mmKey]} {
            dict set d $ptKey [expr {round([dict get $d $mmKey] * $mmToPt)}]
        }
    }
    return $d
}

# -------------------------------------------------------------------------
# labelpaper -- CUPS-/Treiber-Mediagrossenname fuer ein DK-Format
#
# Wird typischerweise als 'lp -o media=...' Argument verwendet.
# Brother CUPS-Treiber-Konvention: DK-Code ohne Bindestrich, z.B.:
#   DK-22205   -> DK22205
#   DK-N55224  -> DKN55224
#
# Manche Treiber benutzen auch das brother_ql-Identifier-Format
# (62 fuer DK-22205) -- bei Bedarf via PPD-Datei ueberschreiben.
# -------------------------------------------------------------------------
proc ::printlib::labelpaper {format} {
    variable _dkLabels
    set code [_normDkCode $format]
    if {![dict exists $_dkLabels $code]} {
        error "printlib::labelpaper: unbekanntes Etiketten-Format '$format'"
    }
    return [string map {- ""} $code]
}

# -------------------------------------------------------------------------
# _printercaps_linux -- Druckerfaehigkeiten via CUPS (Linux/macOS)
#
# Quellen:
#   - lpoptions -p X -l    : alle PPD-Optionen mit Default + Werten
#   - lpstat -p X          : Status (idle/busy/disabled)
#   - lpstat -d            : ist X der Default-Drucker?
#
# Format von lpoptions -p X -l:
#   OptName/HumanLabel: [*]Wert1 [*]Wert2 ...
#   Sternchen markiert den Default. Werte i.d.R. ohne Leerzeichen
#   (CUPS-Konvention: EnvelopeDL, DuplexNoTumble, etc.).
#
# Erweitert in 0.2 (vorher nur grobe Regex).
# -------------------------------------------------------------------------
proc ::printlib::_printercaps_linux {printername} {
    set result [dict create name $printername source cups]

    # 1) lpoptions -l: alle Optionen parsen
    set lpopts [dict create]
    catch {
        set out [exec lpoptions -p $printername -l 2>@1]
        foreach line [split $out "\n"] {
            set line [string trim $line]
            if {$line eq ""} continue
            # OptName/Label: Wert1 Wert2 ...
            if {![regexp {^([A-Za-z][A-Za-z0-9_]*)[^:]*:\s*(.+)$} $line -> opt vals]} {
                continue
            }
            set values {}
            set default ""
            foreach v [split [string trim $vals]] {
                if {$v eq ""} continue
                if {[string index $v 0] eq "*"} {
                    set default [string range $v 1 end]
                    lappend values $default
                } else {
                    lappend values $v
                }
            }
            dict set lpopts $opt [dict create default $default values $values]
        }
    }

    # 2) Mapping auf printlib-Caps-Schema
    # InputSlot -> bins / bin_default
    if {[dict exists $lpopts InputSlot]} {
        set i [dict get $lpopts InputSlot]
        dict set result bins        [dict get $i values]
        dict set result bin_default [dict get $i default]
    }

    # PageSize -> papers / paper_default
    if {[dict exists $lpopts PageSize]} {
        set p [dict get $lpopts PageSize]
        dict set result papers        [dict get $p values]
        dict set result paper_default [dict get $p default]
    }

    # Duplex: boolean + verfuegbare Werte
    if {[dict exists $lpopts Duplex]} {
        set d [dict get $lpopts Duplex]
        set vals [dict get $d values]
        # "None" allein = kein Duplex-Hardware. Alles andere = duplex-faehig.
        set hasDuplex 0
        foreach v $vals {
            if {[string match -nocase "Duplex*" $v]} { set hasDuplex 1 ; break }
        }
        dict set result duplex        $hasDuplex
        dict set result duplex_values $vals
    } else {
        dict set result duplex 0
    }

    # ColorModel -> color (boolean)
    if {[dict exists $lpopts ColorModel]} {
        set c [dict get $lpopts ColorModel]
        set vals [dict get $c values]
        # Gray/Mono/Black-Only = nicht-farbig; RGB/CMYK/Color = farbig
        set hasColor 0
        foreach v $vals {
            if {[regexp -nocase {color|rgb|cmyk} $v]} { set hasColor 1 ; break }
        }
        dict set result color $hasColor
    }

    # Resolution -> dpi
    if {[dict exists $lpopts Resolution]} {
        set r [dict get $lpopts Resolution]
        set def [dict get $r default]
        if {$def ne "" && [regexp {(\d+)} $def -> dpi]} {
            dict set result dpi_x $dpi
            dict set result dpi_y $dpi
        }
        dict set result resolutions [dict get $r values]
    }

    # MediaType -> media_types
    if {[dict exists $lpopts MediaType]} {
        set m [dict get $lpopts MediaType]
        dict set result media_types        [dict get $m values]
        dict set result media_type_default [dict get $m default]
    }

    # 3) Status (lpstat -p X)
    catch {
        set out [exec lpstat -p $printername 2>@1]
        if {[regexp -nocase {is idle}        $out]} { dict set result status idle }
        if {[regexp -nocase {now printing}   $out]} { dict set result status busy }
        if {[regexp -nocase {disabled}       $out]} { dict set result status disabled }
    }

    # 4) Default-Drucker?
    catch {
        set def [exec lpstat -d 2>@1]
        if {[regexp "system default destination:\\s*$printername" $def]} {
            dict set result is_default 1
        }
    }

    return $result
}

# --- DEVMODE dmDefaultSource -> lesbarer Name ---
proc ::printlib::_devmode_bin_name {val} {
    set bins {1 upper 2 lower 3 middle 4 manual 5 envelope
              6 envmanual 7 auto 8 tractor 9 smallfmt 10 largefmt
              11 largecapacity 14 cassette 15 formsource}
    if {[dict exists $bins $val]} { return [dict get $bins $val] }
    return "bin$val"
}


# -------------------------------------------------------------------------
# status -- Modul-Info und Backend-Status
#
# (frueher in 0.1: ::printlib::info -- umbenannt in 0.1.1, weil "info"
# der Name des eingebauten Tcl-Befehls ist und bei "namespace import"
# den Standard-Befehl ueberschreiben wuerde.)
# -------------------------------------------------------------------------
proc ::printlib::status {} {
    variable cfg
    variable activeBackend

    set hasCairo   [_available pdftocairo]
    set hasSumatra [_available sumatra]
    set hasLp      [_available lp]
    set hasPdfium  [_available pdfium]

    return [dict create \
        version        0.2 \
        backend_active $activeBackend \
        pdftocairo_ok  $hasCairo \
        sumatra_ok     $hasSumatra \
        lp_ok          $hasLp \
        pdfium_ok      $hasPdfium \
        config         $cfg \
    ]
}

# =========================================================================
# PPD-Konfigurationsdateien (neu in 0.2)
# =========================================================================
#
# Format: schlanke Schluessel-Wert-Dateien, eine pro Drucker und Backend.
# Beispiel:
#
#   # printlib Druckerkonfiguration fuer pdftocairo
#   printer   "HP LaserJet P2055"
#   source    upper
#   duplex    long
#   paper     A4
#   scale     fit
#
# Dateinamen-Konvention:
#   ppd/<normalisierter_name>.pdftocairo   (fuer pdftocairo-Backend)
#   ppd/<normalisierter_name>.sumatra      (fuer SumatraPDF-Backend)
#
# Suchreihenfolge fuer das ppd/-Verzeichnis:
#   1. dict get $cfg ppdDir   (gesetzt per configure -ppddir)
#   2. [pwd]/ppd/             (relativ zum Arbeitsverzeichnis)
#   3. [scriptDir]/ppd/       (neben dem printlib-Modul)
# =========================================================================

# -------------------------------------------------------------------------
# _normPpdName -- Druckername zu einem dateisystem-tauglichen Namen normalisieren
#
# "HP LaserJet P2055"  ->  "HP_LaserJet_P2055"
# "Drucker (Buero)"    ->  "Drucker__Buero_"  (Sonderzeichen zu _)
# -------------------------------------------------------------------------
proc ::printlib::_normPpdName {printer} {
    return [regsub -all {[^A-Za-z0-9_-]} $printer "_"]
}

# -------------------------------------------------------------------------
# _ppdSearchDirs -- Liste der Suchverzeichnisse (in Prioritaet)
#
# Eine Anwendung kann via configure -ppddir <pfad> den Standardpfad
# erzwingen; sonst werden zwei Fallback-Verzeichnisse durchsucht.
# Nicht-existente Verzeichnisse werden trotzdem gelistet -- findPpdFile
# filtert sie via [file exists].
# -------------------------------------------------------------------------
proc ::printlib::_ppdSearchDirs {} {
    variable cfg
    set dirs {}
    set ppdDir [dict get $cfg ppdDir]
    if {$ppdDir ne ""} {
        lappend dirs $ppdDir
    }
    lappend dirs [file join [pwd] ppd]
    # info script gibt den Pfad des aktuell geladenen Tcl-Scripts/Moduls
    set scriptDir [file dirname [::info script]]
    if {$scriptDir ne "" && $scriptDir ne "."} {
        lappend dirs [file join $scriptDir ppd]
    }
    return $dirs
}

# -------------------------------------------------------------------------
# findPpdFile -- PPD-Datei fuer Drucker und Backend finden
#
# Gibt den vollen Pfad zurueck wenn die Datei existiert, sonst "".
#
# Beispiel:
#   findPpdFile "HP LaserJet P2055" pdftocairo
#   -> /pfad/zu/ppd/HP_LaserJet_P2055.pdftocairo
# -------------------------------------------------------------------------
proc ::printlib::findPpdFile {printer backend} {
    if {$backend ni [_ppdBackends]} {
        error "printlib::findPpdFile: ungueltiges Backend '$backend'"
    }
    set name [_normPpdName $printer]
    set ext  [expr {$backend eq "pdftocairo" ? ".pdftocairo" : ".sumatra"}]
    foreach dir [_ppdSearchDirs] {
        set path [file join $dir "${name}${ext}"]
        if {[file exists $path]} {
            return $path
        }
    }
    return ""
}

# -------------------------------------------------------------------------
# loadPpdFile -- PPD-Datei einlesen und als Dict zurueckgeben
#
# Eingabe: voller Pfad zu einer .pdftocairo oder .sumatra-Datei.
# Rueckgabe: Dict {schluessel wert schluessel wert ...}.
#
# Format-Regeln:
#   - Eine Option pro Zeile: schluessel wert
#   - Werte mit Leerzeichen in Anfuehrungszeichen: printer "Mit Leerzeichen"
#   - Kommentare ab #
#   - Leere Zeilen erlaubt
#
# Unbekannte Schluessel werden gelesen (kein Fehler) -- der Aufrufer
# verwendet sie ggf. nicht.
# -------------------------------------------------------------------------
proc ::printlib::loadPpdFile {path} {
    if {![file exists $path]} {
        error "printlib::loadPpdFile: Datei nicht gefunden: $path"
    }
    set result [dict create]
    set fd [open $path r]
    try {
        foreach line [split [read $fd] "\n"] {
            set line [string trim $line]
            if {$line eq "" || [string match "#*" $line]} continue
            # Zuerst quoted-Form versuchen, dann Standard
            if {[regexp {^(\S+)\s+"([^"]*)"\s*$} $line -> key val] ||
                [regexp {^(\S+)\s+(.+)$}         $line -> key val]} {
                dict set result $key [string trim $val]
            }
        }
    } finally {
        close $fd
    }
    return $result
}

# -------------------------------------------------------------------------
# savePpdFile -- Druckerkonfiguration als PPD-Datei schreiben
#
# Eingaben:
#   printer  -- Druckername (wird normalisiert)
#   backend  -- pdftocairo | sumatra
#   opts     -- Dict mit den zu speichernden Optionen
#
# Schreibt nach <ppdDir>/<normName>.<backend>. Das Zielverzeichnis ist:
#   - das erste existente Verzeichnis aus _ppdSearchDirs, oder
#   - falls keines existiert: das erste, neu angelegt.
#
# Rueckgabe: voller Pfad der geschriebenen Datei.
#
# Beispiel:
#   savePpdFile "HP LaserJet" pdftocairo \
#       {printer "HP LaserJet" source upper paper A4 scale fit}
# -------------------------------------------------------------------------
proc ::printlib::savePpdFile {printer backend opts} {
    if {$backend ni {pdftocairo sumatra}} {
        error "printlib::savePpdFile: ungueltiges Backend '$backend'"
    }
    set name [_normPpdName $printer]
    set ext  [expr {$backend eq "pdftocairo" ? ".pdftocairo" : ".sumatra"}]

    # Zielverzeichnis: erstes existentes aus _ppdSearchDirs, sonst erstes neu
    set targetDir ""
    foreach dir [_ppdSearchDirs] {
        if {[file isdirectory $dir]} {
            set targetDir $dir
            break
        }
    }
    if {$targetDir eq ""} {
        set targetDir [lindex [_ppdSearchDirs] 0]
        file mkdir $targetDir
    }

    set path [file join $targetDir "${name}${ext}"]
    set fd [open $path w]
    try {
        puts $fd "# printlib Druckerkonfiguration fuer $backend"
        # Timestamp robust: wenn clock format wegen msgcat-Init-Problemen
        # zickt (headless tclsh ohne msgcat-Setup), fallen wir auf den
        # rohen Unix-Timestamp zurueck.
        if {[catch {clock format [clock seconds] -format "%Y-%m-%d %H:%M" -gmt 1} ts]} {
            set ts "ts=[clock seconds] UTC"
        } else {
            append ts " UTC"
        }
        puts $fd "# Erzeugt: $ts"
        puts $fd ""
        dict for {key val} $opts {
            # Werte mit Leerzeichen oder Anfuehrungszeichen quoten
            if {[regexp {[\s"]} $val] || $val eq ""} {
                puts $fd "$key \"$val\""
            } else {
                puts $fd "$key $val"
            }
        }
    } finally {
        close $fd
    }
    return $path
}

# -------------------------------------------------------------------------
# _applyPpdToOpts -- PPD-Werte in opts-Dict einsetzen, aber nur fuer
#                    Optionen, die NICHT in cliKeys aufgefuehrt sind.
#
# Wird intern von print aufgerufen. Priorisierung:
#   1. Explizite Argumente vom print-Aufruf (in cliKeys gelistet) -- behalten
#   2. PPD-Datei-Werte -- einsetzen wenn key nicht in cliKeys
#   3. configure-Defaults -- bleiben stehen wenn PPD nichts dazu sagt
# -------------------------------------------------------------------------
proc ::printlib::_applyPpdToOpts {optsVar ppd cliKeys} {
    upvar 1 $optsVar opts
    set ppdKeys {source duplex paper scale copies silent orientation cut}
    foreach key $ppdKeys {
        if {[dict exists $ppd $key] && $key ni $cliKeys} {
            dict set opts $key [dict get $ppd $key]
        }
    }
}

# -------------------------------------------------------------------------
# _available -- Prueft ob ein Backend-Executable gefunden wird
# -------------------------------------------------------------------------
proc ::printlib::_available {which} {
    variable cfg
    switch -- $which {
        pdftocairo {
            set exe [dict get $cfg pdftocairo]
            return [expr {![catch {exec $exe -v 2>@1}] ||
                         ![catch {exec $exe -h 2>@1}] ||
                         [file executable $exe]}]
        }
        sumatra {
            set exe [dict get $cfg sumatra]
            return [expr {![catch {exec $exe -h 2>@1}] ||
                         [file executable $exe]}]
        }
        lp {
            set exe [dict get $cfg lp]
            # auto_execok liefert leere Liste wenn das Kommando nicht im PATH ist
            return [expr {[llength [auto_execok $exe]] > 0}]
        }
        pdfium {
            if {$::tcl_platform(platform) ne "windows"} { return 0 }
            if {[catch {package require pdfiumtcl}]}    { return 0 }
            if {![llength [info commands ::pdfium::canprint]]} { return 0 }
            return [::pdfium::canprint]
        }
        default { return 0 }
    }
}

# =====================================================================
# pdfium backend (Windows, GDI) -- eingebaut aus
# vendor/printlib/printlib-pdfium-backend.tcl (Stelle 6)
# Freistehend mit ::printlib::-Prefix, wie _print_lp/_print_sumatra.
# =====================================================================

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
