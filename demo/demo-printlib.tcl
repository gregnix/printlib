#!/usr/bin/env wish
# demo-printlib.tcl -- die Druckoberflaeche zum Ausprobieren
#
# 01.10.2026: hier lagen 859 Zeilen, die eine Kopie von printlib-gui.tcl
# waren. Der Kopf sagte es selbst -- "funktionsgleich zu printlib-gui.tcl;
# eigene Datei zum Ausprobieren" --, und gemessen unterschieden sich die
# beiden Dateien in 20 Zeilen: Fenstertitel, Modulpfad, Kommentare. Alles
# andere war doppelt.
#
# Aufgefallen ist es an einem Absturz: "can't read ::env(TEMP): no such
# variable" beim Knopf "Diagnose" unter Linux. Die Stelle gab es ZWEIMAL,
# und wer nur eine repariert, hat den Fehler noch.
#
# Das ist derselbe Fall, fuer den in diesem Baum schon ein Waechter steht
# (test-pdfium-backend-guard.tcl: Testkopien gegen das Modul). Fuer 859
# Zeilen ist ein Waechter aber die schlechtere Antwort als gar keine
# Kopie. Darum laedt die Demo jetzt die Oberflaeche, statt sie
# nachzubauen.
#
# Was dabei bleibt: der Modulpfad. printlib-gui.tcl setzt ihn relativ zu
# [info script], und waehrend eines source zeigt das auf die geladene
# Datei -- also auf printlib-gui.tcl selbst. Der Weg stimmt damit von
# hier aus genauso.

set ::printlib_demo 1

source [file join [file dirname [file dirname [file normalize [info script]]]] \
        printlib-gui.tcl]

wm title . "Drucken mit printlib (demo)"
