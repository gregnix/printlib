#!/usr/bin/env wish
# printlib-gui.tcl -- Druckoberfläche mit printlib + printercaps

package require Tk
encoding system utf-8
tcl::tm::path add [file dirname [info script]]
package require printlib

# =========================================================================
# Variablen
# =========================================================================
set pdffile      ""
set printer      [printlib::defaultprinter]
set scale        noscale
set paper        A4
set source       ""
set duplex       off
set pages        ""
set backend      auto
set orientation  portrait
set cut          auto
set custom_w     ""
set custom_h     ""
set custom_pt_hint ""
set profile      ""

# Caps-Cache: printer -> dict
array set caps_cache {}

# =========================================================================
# Hilfsprocs
# =========================================================================
proc log {msg} {
    .log insert end "$msg\n"
    .log see end
}

# Fehlerdialog mit kopierbarem Text statt tk_messageBox.
# tk_messageBox erlaubt kein Strg+C aus dem Fehlertext, was die Diagnose
# erschwert. Stattdessen Text-Widget in eigenem Toplevel, Inhalt schon
# pre-selektiert.
proc show_error_text {title message} {
    set top .errdlg
    if {[winfo exists $top]} { destroy $top }
    toplevel $top
    wm title $top $title
    wm transient $top .
    wm minsize $top 480 200

    set t  $top.t
    set sb $top.sb
    text $t -wrap word -height 14 -width 80 -yscrollcommand "$sb set"
    scrollbar $sb -command "$t yview"
    $t insert end $message
    # Inhalt selektieren -- Strg+C kopiert ohne extra Klick
    $t tag add sel 1.0 end-1c
    $t configure -state disabled

    set bf $top.btns
    frame $bf
    button $bf.copy  -text "In Zwischenablage" -command [list copy_to_clipboard $t]
    button $bf.close -text "Schliessen"        -command [list destroy $top]

    grid $t  $sb -sticky nsew
    grid $bf -columnspan 2 -sticky ew -padx 4 -pady 4
    grid rowconfigure    $top 0 -weight 1
    grid columnconfigure $top 0 -weight 1

    pack $bf.close -side right -padx 2
    pack $bf.copy  -side right -padx 2

    bind $top <Escape> [list destroy $top]
    bind $top <Control-c> [list copy_to_clipboard $t]
    focus $t
}

proc copy_to_clipboard {textwidget} {
    set content [$textwidget get 1.0 end-1c]
    clipboard clear
    clipboard append $content
}

# Etiketten-Format mit Massen beschriften, z.B.:
#   "DK22205" -> "DK22205  (62mm endlos)"
#   "DK11201" -> "DK11201  (29x90mm)"
#   "DK11207" -> "DK11207  (58mm rund)"
# Bei unbekanntem Code wird er unveraendert zurueckgegeben.
proc paper_label {cupsName} {
    if {[catch {set s [printlib::labelsize $cupsName]}]} {
        return $cupsName
    }
    switch -- [dict get $s kind] {
        die_cut {
            return "$cupsName  ([dict get $s width_mm]x[dict get $s height_mm]mm)"
        }
        round {
            return "$cupsName  ([dict get $s diameter_mm]mm rund)"
        }
        continuous {
            return "$cupsName  ([dict get $s width_mm]mm endlos)"
        }
    }
    return $cupsName
}

# mm -> pt (1 mm = 2.834645... pt). Leerer/ungueltiger Wert -> "".
proc mm2pt {mm} {
    if {$mm eq "" || ![string is double -strict $mm]} { return "" }
    return [expr {round($mm * 2.8346456692913385)}]
}

# Live-Hinweis "= 176 x 82 pt" aktualisieren, wenn Custom-Felder sich aendern
proc update_custom_hint {args} {
    global custom_w custom_h custom_pt_hint
    set pw [mm2pt $custom_w]
    set ph [mm2pt $custom_h]
    if {$pw ne "" && $ph ne ""} {
        set custom_pt_hint "= $pw x $ph pt"
    } elseif {$custom_w eq "" && $custom_h eq ""} {
        set custom_pt_hint ""
    } else {
        set custom_pt_hint "(unvollstaendig)"
    }
}
trace add variable custom_w write update_custom_hint
trace add variable custom_h write update_custom_hint

# Caps für aktuellen Drucker laden und UI aktualisieren
# Debounce: 150ms warten bevor geladen wird (Combobox sendet Zwischenzustände)
proc on_printer_change {args} {
    after cancel on_printer_change_do
    after 150    on_printer_change_do
}

proc on_printer_change_do {} {
    global printer caps_cache source duplex paper scale

    if {$printer eq ""} return

    # Cache prüfen
    if {![info exists caps_cache($printer)]} {
        log "Abfrage Caps: $printer ..."
        set caps_cache($printer) [printlib::printercaps $printer]
        log "Info-Quelle: [dict get $caps_cache($printer) source]"
    }

    set caps $caps_cache($printer)
    set isLabel [printlib::isLabelPrinter $printer]

    # --- Kassetten-Combobox befuellen ---
    # Etikettendrucker haben keine Kassetten (Endlosrolle/Die-Cut von Rolle)
    if {$isLabel} {
        .main.opt.ck configure -values {{}} -state disabled
        set source ""
    } else {
        if {[dict exists $caps bins] && [llength [dict get $caps bins]] > 0} {
            set bins [dict get $caps bins]
        } else {
            set bins {upper lower middle manual auto envelope}
        }
        .main.opt.ck configure -values [concat {{}} $bins] -state readonly
        if {$source ne "" && $source ni $bins} { set source "" }
    }

    # --- Duplex aktivieren/deaktivieren ---
    # Etikettendrucker drucken nie beidseitig
    if {$isLabel || ([dict exists $caps duplex] && ![dict get $caps duplex])} {
        .main.opt.cd configure -state disabled
        set duplex off
    } else {
        .main.opt.cd configure -state readonly
    }

    # --- Papier-Combobox befuellen ---
    if {$isLabel} {
        # Etiketten-Drucker: DK-Formate aus labelformats holen.
        # Anzeige mit Massen, damit man die kryptischen DK-Codes versteht.
        # Format: "DK22205  (62mm endlos)" -- der CUPS-Name ist der erste
        # Token, die Maße in Klammern. do_print extrahiert den Code via
        # [lindex $paper 0].
        set papers {}
        foreach dk [printlib::labelformats $printer] {
            lappend papers [paper_label [printlib::labelpaper $dk]]
        }
        if {[llength $papers] == 0} {
            set papers {{}}
        }
        .main.opt.cpa configure -values $papers
        # Wenn bisheriger Wert nicht in der Liste, ersten DK-Code waehlen
        set curCode [lindex $paper 0]
        set inList 0
        foreach p $papers {
            if {[lindex $p 0] eq $curCode} { set paper $p; set inList 1; break }
        }
        if {!$inList} { set paper [lindex $papers 0] }
    } elseif {[dict exists $caps papers] && [llength [dict get $caps papers]] > 0} {
        # Normaler Drucker mit Papier-Liste aus CUPS/WMI
        set papers [dict get $caps papers]
        .main.opt.cpa configure -values $papers
        # Default-Papier aus Caps uebernehmen, falls noch leer
        if {$paper eq "" && [dict exists $caps paper_default]} {
            set paper [dict get $caps paper_default]
        }
    } else {
        # Fallback: Standard-Liste
        .main.opt.cpa configure -values {A4 A3 A5 letter legal}
    }

    # --- Skalierung: bei Etiketten-Druckern ist origsize meistens richtig ---
    if {$isLabel && $scale eq "noscale"} {
        # Nur initial setzen, damit der User nicht permanent ueberschrieben wird
        global _scaleAutoSet
        if {![info exists _scaleAutoSet($printer)]} {
            set scale origsize
            set _scaleAutoSet($printer) 1
            log "Etikettendrucker erkannt -- Skalierung auf 'origsize' gesetzt"
        }
    }

    # --- Info-Panel aktualisieren ---
    show_caps $caps

    # --- Profil-Liste aktualisieren (Windows) ---
    if {[info commands refresh_profiles] ne ""} {
        refresh_profiles
    }
}

proc show_caps {caps} {
    set lines {}

    if {[dict exists $caps driver]} {
        lappend lines "Treiber:  [dict get $caps driver]"
    }
    if {[dict exists $caps port]} {
        lappend lines "Port:     [dict get $caps port]"
    }
    if {[dict exists $caps status]} {
        lappend lines "Status:   [dict get $caps status]"
    }
    if {[dict exists $caps is_default] && [dict get $caps is_default]} {
        lappend lines "          (Standarddrucker)"
    }
    if {[dict exists $caps color]} {
        lappend lines "Farbe:    [expr {[dict get $caps color] ? {ja} : {nein (Mono)}}]"
    }
    if {[dict exists $caps duplex]} {
        lappend lines "Duplex:   [expr {[dict get $caps duplex] ? {ja} : {nein}}]"
    }
    if {[dict exists $caps dpi_x]} {
        set dy [expr {[dict exists $caps dpi_y] ? [dict get $caps dpi_y] : "?"}]
        lappend lines "DPI:      [dict get $caps dpi_x] x $dy"
    }
    if {[dict exists $caps resolutions] &&
        [llength [dict get $caps resolutions]] > 1} {
        lappend lines "          (verfuegbar: [join [dict get $caps resolutions] {, }])"
    }
    if {[dict exists $caps paper_default]} {
        lappend lines "Papier:   [dict get $caps paper_default]"
    }
    if {[dict exists $caps copies_max] && [dict get $caps copies_max] > 1} {
        lappend lines "Kopien:   max [dict get $caps copies_max]"
    }
    if {[dict exists $caps bins] && [llength [dict get $caps bins]] > 0} {
        lappend lines "Kassetten:"
        foreach b [dict get $caps bins] {
            if {[dict exists $caps bin_default] &&
                $b eq [dict get $caps bin_default]} {
                lappend lines "  * $b  (Standard)"
            } else {
                lappend lines "  - $b"
            }
        }
    } elseif {[dict exists $caps bin_default]} {
        lappend lines "Kassette: [dict get $caps bin_default] (Standard)"
    }
    if {[dict exists $caps papers] && [llength [dict get $caps papers]] > 0} {
        set p [dict get $caps papers]
        if {[llength $p] > 8} {
            lappend lines "Papier:   [join [lrange $p 0 7] {, }]..."
        } else {
            lappend lines "Papier:   [join $p {, }]"
        }
    }
    if {[dict exists $caps media_types] &&
        [llength [dict get $caps media_types]] > 0} {
        set mt [dict get $caps media_types]
        if {[llength $mt] > 5} {
            lappend lines "Material: [join [lrange $mt 0 4] {, }]..."
        } else {
            lappend lines "Material: [join $mt {, }]"
        }
    }
    lappend lines "(Quelle: [dict get $caps source])"

    .info.t configure -state normal
    .info.t delete 1.0 end
    .info.t insert end [join $lines \n]
    .info.t configure -state disabled
}

# =========================================================================
# Layout
# =========================================================================
wm title . "Drucken mit printlib"
wm resizable . 1 0

# --- Datei ---
labelframe .file -text "PDF-Datei" -padx 6 -pady 4
entry  .file.ef -textvariable pdffile -width 52
button .file.bf -text "..." -width 3 -command {
    set f [tk_getOpenFile \
        -filetypes {{"PDF-Dateien" .pdf} {"Alle Dateien" *}} \
        -title "PDF-Datei wählen"]
    if {$f ne ""} { set pdffile $f }
}
pack .file.ef -side left -fill x -expand 1 -padx 2
pack .file.bf -side left -padx 2
pack .file -fill x -padx 8 -pady 4

# --- Haupt-Frame ---
frame .main -padx 8
pack .main -fill both -expand 1

# Linke Seite: Einstellungen
labelframe .main.opt -text "Druckeinstellungen" -padx 6 -pady 4
pack .main.opt -side left -fill y -padx 4 -pady 4

# Drucker-Auswahl
label .main.opt.lp -text "Drucker:" -anchor w -width 10
ttk::combobox .main.opt.cp -textvariable printer -width 28 \
    -values [printlib::printerlist]
grid .main.opt.lp .main.opt.cp -padx 4 -pady 3 -sticky w

# Skalierung + Papier
label .main.opt.ls  -text "Skalierung:" -anchor w -width 10
ttk::combobox .main.opt.cs -textvariable scale -width 10 -state readonly \
    -values {noscale fit shrink expand match origsize}
label .main.opt.lpa -text "Papier:" -anchor w
ttk::combobox .main.opt.cpa -textvariable paper -width 20 -state readonly \
    -values {A4 A3 A5 letter legal}
grid .main.opt.ls .main.opt.cs .main.opt.lpa .main.opt.cpa \
    -padx 4 -pady 3 -sticky w

# Kassette + Duplex
label .main.opt.lk -text "Kassette:" -anchor w -width 10
ttk::combobox .main.opt.ck -textvariable source -width 12 -state readonly \
    -values {{} upper lower middle manual auto envelope}
label .main.opt.ld -text "Duplex:" -anchor w
ttk::combobox .main.opt.cd -textvariable duplex -width 8 -state readonly \
    -values {off long short}
grid .main.opt.lk .main.opt.ck .main.opt.ld .main.opt.cd \
    -padx 4 -pady 3 -sticky w

# Seiten + Backend
label .main.opt.lse -text "Seiten:" -anchor w -width 10
entry .main.opt.ese -textvariable pages -width 8
label .main.opt.lbe -text "Backend:" -anchor w
ttk::combobox .main.opt.cbe -textvariable backend -width 10 -state readonly \
    -values {auto pdftocairo sumatra lp}
grid .main.opt.lse .main.opt.ese .main.opt.lbe .main.opt.cbe \
    -padx 4 -pady 3 -sticky w

# Orientierung + Auto-Cut (relevant fuer Etikettendrucker)
label .main.opt.lo -text "Orientierung:" -anchor w -width 10
ttk::combobox .main.opt.co -textvariable orientation -width 10 -state readonly \
    -values {portrait landscape reverse-landscape reverse-portrait}
label .main.opt.lc -text "Auto-Cut:" -anchor w
ttk::combobox .main.opt.cc -textvariable cut -width 8 -state readonly \
    -values {auto on off end}
grid .main.opt.lo .main.opt.co .main.opt.lc .main.opt.cc \
    -padx 4 -pady 3 -sticky w

# Custom-Groesse zum Experimentieren (ueberschreibt Papier/Scale).
# Werte in mm; leer = nicht verwenden. Wird zu -paperw/-paperh (pt).
label .main.opt.lcw -text "Custom (mm):" -anchor w -width 10
frame .main.opt.fcw
entry .main.opt.fcw.w -textvariable custom_w -width 6
label .main.opt.fcw.x -text " x "
entry .main.opt.fcw.h -textvariable custom_h -width 6
label .main.opt.fcw.u -text " (B x H, leer = aus)"
pack .main.opt.fcw.w .main.opt.fcw.x .main.opt.fcw.h .main.opt.fcw.u -side left
label .main.opt.lcwhint -textvariable custom_pt_hint -anchor w -foreground gray40
grid .main.opt.lcw .main.opt.fcw .main.opt.lcwhint - \
    -padx 4 -pady 3 -sticky w

# Drucker-Profile (nur Windows -- printui.dll). Erlaubt das Umschalten
# zwischen gespeicherten Treibereinstellungen (z.B. Etikettengroessen).
if {$::tcl_platform(platform) eq "windows"} {
    label .main.opt.lpr -text "Profil:" -anchor w -width 10
    frame .main.opt.fpr
    ttk::combobox .main.opt.fpr.c -textvariable profile -width 14 -state readonly
    button .main.opt.fpr.bset  -text "Einstellen"  -command do_open_settings
    button .main.opt.fpr.bsave -text "Sichern als..." -command do_save_profile
    button .main.opt.fpr.buse  -text "Anwenden"    -command do_use_profile
    pack .main.opt.fpr.c .main.opt.fpr.bset .main.opt.fpr.bsave .main.opt.fpr.buse \
        -side left -padx 2
    grid .main.opt.lpr .main.opt.fpr - - \
        -padx 4 -pady 3 -sticky w
}

# Rechte Seite: Drucker-Info
labelframe .main.info -text "Druckereigenschaften" -padx 6 -pady 4
pack .main.info -side left -fill both -expand 1 -padx 4 -pady 4

frame .info
pack .info -in .main.info -fill both -expand 1
text .info.t -width 30 -height 12 -bg #f8f8f8 \
    -font {Courier 9} -state disabled -relief flat \
    -wrap word
scrollbar .info.s -command {.info.t yview}
.info.t configure -yscrollcommand {.info.s set}
pack .info.s -side right -fill y
pack .info.t -fill both -expand 1

# Drucker-Änderung beobachten
trace add variable ::printer write on_printer_change

# --- Buttons ---
frame .btns -padx 8 -pady 4
pack .btns -fill x

button .btns.bprint -text "Drucken" -width 12 -command do_print \
    -bg #2196F3 -fg white -font {TkDefaultFont 10 bold}
button .btns.bprev  -text "Vorschau" -width 10 -command do_preview
button .btns.brefr  -text "Caps neu" -width 10 -command {
    global printer caps_cache
    array unset caps_cache $printer
    on_printer_change_do
    log "Caps neu geladen für: $printer"
}
button .btns.bdiag  -text "Diagnose" -width 10 -command {
    global printer
    log "--- Diagnose: $printer ---"

    # twapi_printer laden
    catch { package require twapi_printer }
    log "--- twapi Befehle ---"
    foreach c [lsort [concat \
        [info commands twapi::*print*] \
        [info commands twapi::*printer*]]] {
        log "  $c"
    }

    # PowerShell WMI testen
    log "--- PowerShell Win32_PrinterConfiguration ---"
    set ::env(PRINTLIB_PRINTER) $printer
    set ps1 [file join $::env(TEMP) printlib_caps.ps1]
    set fd [open $ps1 w]
    puts $fd {$name = $env:PRINTLIB_PRINTER}
    puts $fd {Get-WmiObject Win32_PrinterConfiguration |}
    puts $fd {  Where-Object {$_.Name -eq $name} |}
    puts $fd {  Select-Object Color,Duplex,YResolution |}
    puts $fd {  ConvertTo-Csv -NoTypeInformation}
    close $fd
    catch {
        set out [exec powershell -NonInteractive             -ExecutionPolicy Bypass -File $ps1 2>@1]
        foreach line [split $out \n] {
            log "  [string trim $line]"
        }
    } ps_err
    if {$ps_err ne ""} { log "  PS Fehler: $ps_err" }

    # recordarray fields + getlist testen
    log "--- recordarray fields/getlist ---"
    catch {
        set ra   [twapi::enumerate_printers]
        set keys [twapi::recordarray fields $ra]
        set rows [twapi::recordarray getlist $ra]
        log "  Keys: $keys"
        log "  Anzahl Zeilen: [llength $rows]"
        set ni [lsearch $keys -name]
        set ai [lsearch $keys -attrs]
        foreach row [lrange $rows 0 2] {
            log "  [lindex $row $ni] | [lindex $row $ai]"
        }
    } err2
    if {$err2 ne ""} { log "  Fehler: $err2" }

    log "--- Ende Diagnose ---"
}
button .btns.bsave -text "Konfig speichern" -width 14 \
    -command do_save_ppd
button .btns.bstat -text "Status" -width 10 \
    -command do_show_status
button .btns.bclear -text "Log loeschen" -width 12 \
    -command {.log delete 1.0 end}
pack .btns.bprint .btns.bprev .btns.brefr .btns.bsave .btns.bstat .btns.bdiag .btns.bclear \
    -side left -padx 4

# --- Log ---
labelframe .logf -text "Log" -padx 4 -pady 2
pack .logf -fill both -expand 1 -padx 8 -pady 4

text .log -height 6 -bg #1e1e1e -fg #d4d4d4 \
    -font {Courier 9}
scrollbar .logs -command {.log yview}
.log configure -yscrollcommand {.logs set}
pack .logs -in .logf -side right -fill y
pack .log  -in .logf -fill both -expand 1

# =========================================================================
# Aktionen
# =========================================================================
proc do_print {} {
    global pdffile printer scale paper source duplex pages backend orientation cut
    global custom_w custom_h

    if {$pdffile eq "" || ![file exists $pdffile]} {
        tk_messageBox -icon warning \
            -message "Bitte zuerst eine PDF-Datei wählen." \
            -title "Keine Datei"
        return
    }

    log "--- Drucken ---"
    log "Datei:   $pdffile"
    log "Drucker: $printer"
    # Papier-Wert kann bei Etiketten "DK22205  (62mm endlos)" sein --
    # nur der erste Token (DK-Code / CUPS-Name) geht an printlib.
    set realPaper [lindex $paper 0]
    log "Scale:   $scale   Papier: $realPaper   Orient: $orientation"
    if {$source ne ""}      { log "Kassette: $source" }
    if {$duplex ne "off"}   { log "Duplex:   $duplex" }
    if {$pages  ne ""}      { log "Seiten:   $pages"  }
    if {$cut    ne "auto"}  { log "Auto-Cut: $cut"    }

    set opts [list \
        -printer     $printer \
        -scale       $scale   \
        -paper       $realPaper \
        -duplex      $duplex  \
        -orientation $orientation \
        -cut         $cut     \
        -backend     $backend]
    if {$source ne ""} { lappend opts -source $source }
    if {$pages  ne ""} { lappend opts -pages  $pages  }

    # Custom-Groesse (mm -> pt) -- ueberschreibt Papier/Scale, bringt
    # bei Etiketten die Drehung zurueck. Nur wenn BEIDE Felder gesetzt.
    set pw [mm2pt $custom_w]
    set ph [mm2pt $custom_h]
    if {$pw ne "" && $ph ne ""} {
        lappend opts -paperw $pw -paperh $ph
        log "Custom:  ${custom_w}x${custom_h} mm = ${pw}x${ph} pt"
    }

    if {[catch {printlib::print $pdffile {*}$opts} err opts_dict]} {
        log "FEHLER: $err"
        # Vollstaendige Fehlermeldung incl. Stacktrace -- kopierbar
        set details "Druckfehler:\n$err\n\n"
        append details "Aufrufkontext:\n"
        append details "  Datei:    $pdffile\n"
        append details "  Drucker:  $printer\n"
        append details "  Backend:  $backend\n"
        append details "  Scale:    $scale\n"
        append details "  Papier:   $realPaper\n"
        append details "  Orient:   $orientation\n"
        append details "  Auto-Cut: $cut\n"
        if {$source ne ""}    { append details "  Kassette: $source\n" }
        if {$duplex ne "off"} { append details "  Duplex:   $duplex\n" }
        if {$pages  ne ""}    { append details "  Seiten:   $pages\n"  }
        append details "\nStacktrace:\n"
        append details [dict get $opts_dict -errorinfo]
        show_error_text "Druckfehler" $details
    } else {
        log "OK — Druckauftrag gesendet."
    }
}

proc do_preview {} {
    global pdffile

    if {$pdffile eq "" || ![file exists $pdffile]} {
        tk_messageBox -icon warning \
            -message "Bitte zuerst eine PDF-Datei wählen." \
            -title "Keine Datei"
        return
    }

    # Temp-Verzeichnis plattformübergreifend
    set tmpdir [expr {[info exists ::env(TEMP)] ? $::env(TEMP) : "/tmp"}]
    set tmp [file join $tmpdir printlib_preview]

    log "--- Vorschau ---"
    catch { exec pdftocairo -png -r 120 -singlefile $pdffile $tmp 2>@1 }

    set png "${tmp}.png"
    if {![file exists $png]} {
        log "Vorschau fehlgeschlagen."
        return
    }

    log "Vorschau: $png"
    if {[winfo exists .prev]} { destroy .prev }
    toplevel .prev
    wm title .prev "Vorschau — [file tail $pdffile]"

    set img [image create photo -file $png]
    set iw  [image width  $img]
    set ih  [image height $img]

    # Auf max 700px Breite skalieren
    if {$iw > 700} {
        set factor [expr {int(ceil($iw / 700.0))}]
        set img2 [image create photo \
            -width  [expr {$iw / $factor}] \
            -height [expr {$ih / $factor}]]
        $img2 copy $img -subsample $factor
        image delete $img
        set img $img2
    }

    label .prev.img -image $img
    pack  .prev.img
    set ::previewimg $img
}

# -------------------------------------------------------------------------
# Profil-Handler (nur Windows)
# -------------------------------------------------------------------------

# Druckeinstellungs-Dialog oeffnen (zum Umstellen der Etikettengroesse)
proc do_open_settings {} {
    global printer
    if {$printer eq ""} {
        show_error_text "Profil" "Bitte zuerst einen Drucker auswaehlen."
        return
    }
    if {[catch {printlib::openPrinterSettings $printer} err]} {
        show_error_text "Einstellungen oeffnen" $err
        return
    }
    log "Druckeinstellungs-Dialog geoeffnet fuer: $printer"
    log "  -> Format einstellen, OK klicken, dann 'Sichern als...'"
}

# Aktuelle Treibereinstellung als benanntes Profil sichern
proc do_save_profile {} {
    global printer profile
    if {$printer eq ""} {
        show_error_text "Profil" "Bitte zuerst einen Drucker auswaehlen."
        return
    }
    # Profilname abfragen (Vorschlag: aktueller Combobox-Wert)
    set name [ask_profile_name $profile]
    if {$name eq ""} return

    if {[catch {set path [printlib::savePrinterProfile $printer $name]} err]} {
        show_error_text "Profil sichern" $err
        return
    }
    log "Profil '$name' gesichert: $path"
    refresh_profiles
    set profile $name
}

# Gewaehltes Profil anwenden
proc do_use_profile {} {
    global printer profile
    if {$printer eq ""} {
        show_error_text "Profil" "Bitte zuerst einen Drucker auswaehlen."
        return
    }
    if {$profile eq ""} {
        show_error_text "Profil" "Bitte zuerst ein Profil auswaehlen."
        return
    }
    if {[catch {printlib::usePrinterProfile $printer $profile} err]} {
        show_error_text "Profil anwenden" $err
        return
    }
    log "Profil '$profile' angewendet fuer: $printer"
}

# Profil-Combobox aus den vorhandenen Profilen befuellen
proc refresh_profiles {} {
    global printer
    if {![winfo exists .main.opt.fpr.c]} return
    if {$printer eq ""} {
        .main.opt.fpr.c configure -values {}
        return
    }
    set profs {}
    catch {set profs [printlib::listPrinterProfiles $printer]}
    .main.opt.fpr.c configure -values $profs
}

# Kleinen modalen Dialog fuer den Profilnamen anzeigen
proc ask_profile_name {default} {
    set w .profname
    catch {destroy $w}
    toplevel $w
    wm title $w "Profil sichern"
    wm transient $w .
    grab $w

    label $w.l -text "Profilname (z.B. klein, versand, endlos):"
    entry $w.e -width 30
    $w.e insert 0 $default
    pack $w.l -padx 10 -pady {10 4} -anchor w
    pack $w.e -padx 10 -pady 4 -fill x

    set ::_profname_result ""
    frame $w.b
    button $w.b.ok -text "Sichern" -width 10 -command {
        set ::_profname_result [.profname.e get]
        destroy .profname
    }
    button $w.b.cancel -text "Abbrechen" -width 10 -command {
        set ::_profname_result ""
        destroy .profname
    }
    pack $w.b.ok $w.b.cancel -side left -padx 4
    pack $w.b -pady 8
    bind $w.e <Return> { set ::_profname_result [.profname.e get]; destroy .profname }
    bind $w <Escape>   { set ::_profname_result ""; destroy .profname }

    focus $w.e
    tkwait window $w
    return [string trim $::_profname_result]
}

# -------------------------------------------------------------------------
# do_save_ppd -- Aktuelle Einstellungen als PPD-Datei fuer Drucker speichern.
# Die naechsten print-Aufrufe mit -printer X laden diese Werte automatisch.
# -------------------------------------------------------------------------
proc do_save_ppd {} {
    global printer source duplex paper scale backend pages orientation cut

    if {$printer eq ""} {
        show_error_text "Konfig speichern" \
            "Bitte zuerst einen Drucker auswaehlen."
        return
    }

    # Backend bestimmen -- bei "auto" das aktuell aktive nehmen
    set be $backend
    if {$be eq "auto"} {
        set be [printlib::detect]
        if {$be eq "none"} {
            show_error_text "Konfig speichern" \
                "Kein aktives Backend -- weder pdftocairo noch sumatra noch lp gefunden."
            return
        }
    }

    # lp und pdftocairo teilen sich das gleiche PPD-Format unter Linux
    set ppdBackend [expr {$be eq "lp" ? "pdftocairo" : $be}]

    # Konfig zusammenstellen -- Papier-Wert auf DK-Code/CUPS-Namen reduzieren
    set realPaper [lindex $paper 0]
    set opts [dict create \
        printer $printer \
        scale   $scale \
        paper   $realPaper \
    ]
    if {$source ne ""}        { dict set opts source      $source }
    if {$duplex ne "off"}     { dict set opts duplex      $duplex }
    if {$pages  ne ""}        { dict set opts pages       $pages  }
    if {$orientation ne "portrait"} { dict set opts orientation $orientation }
    if {$cut ne "auto"}       { dict set opts cut         $cut }

    if {[catch {
        set path [printlib::savePpdFile $printer $ppdBackend $opts]
    } err opts_dict]} {
        show_error_text "Konfig speichern" \
            "Fehler beim Speichern:\n$err\n\nStacktrace:\n[dict get $opts_dict -errorinfo]"
        return
    }

    log "Konfig gespeichert: $path"
    log "  (wird beim naechsten Druck mit -printer \"$printer\" automatisch geladen)"
}

# -------------------------------------------------------------------------
# do_show_status -- printlib::status im kopierbaren Dialog anzeigen
# -------------------------------------------------------------------------
proc do_show_status {} {
    set st [printlib::status]
    set text "printlib Status\n"
    append text "================\n\n"
    dict for {key val} $st {
        if {$key eq "config"} {
            append text "config:\n"
            dict for {ck cv} $val {
                append text [format "  %-12s = %s\n" $ck $cv]
            }
        } else {
            append text [format "%-16s = %s\n" $key $val]
        }
    }
    # PPD-Datei fuer aktuellen Drucker pruefen
    global printer backend
    if {$printer ne ""} {
        set be $backend
        if {$be eq "auto"} { set be [printlib::detect] }
        set ppdBackend [expr {$be eq "lp" ? "pdftocairo" : $be}]
        if {$be ne "none"} {
            append text "\nPPD-Datei fuer '$printer' (Backend $ppdBackend):\n"

            # Normalisierter Dateiname
            set normName [::printlib::_normPpdName $printer]
            append text "  Erwarteter Dateiname: ${normName}.${ppdBackend}\n\n"

            # Alle Suchpfade durchgehen und anzeigen, ob die Datei da ist
            append text "  Durchsuchte Verzeichnisse:\n"
            set found ""
            foreach dir [::printlib::_ppdSearchDirs] {
                set full [file join $dir "${normName}.${ppdBackend}"]
                if {[file exists $full]} {
                    append text "    \[X\] $full  (gefunden!)\n"
                    if {$found eq ""} { set found $full }
                } elseif {[file isdirectory $dir]} {
                    append text "    \[ \] $dir/  (Verzeichnis vorhanden, Datei fehlt)\n"
                } else {
                    append text "    \[ \] $dir/  (Verzeichnis existiert nicht)\n"
                }
            }

            if {$found ne ""} {
                append text "\n  Aktive Konfiguration:\n"
                catch {
                    set ppd [printlib::loadPpdFile $found]
                    dict for {pk pv} $ppd {
                        append text [format "    %-12s = %s\n" $pk $pv]
                    }
                }
            } else {
                append text "\n  Hinweis: 'Konfig speichern'-Button erzeugt die Datei\n"
                append text "  im ersten existenten Verzeichnis aus der Liste oben.\n"
                append text "  Sonst wird das erste neu angelegt.\n"
            }
        }
    }
    show_error_text "printlib Status" $text
}

# =========================================================================
# Start
# =========================================================================
log "printlib [package require printlib] geladen"
log "Backend: [printlib::detect]"
log "Standarddrucker: [printlib::defaultprinter]"
log "Drucker: [join [printlib::printerlist] {, }]"

# Caps fuer Standarddrucker beim Start laden
after 200 on_printer_change_do

log "--- bereit ---"
