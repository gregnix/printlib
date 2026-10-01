#!/usr/bin/env tclsh
# twapi-diag.tcl -- Diagnosiert verfuegbare twapi Drucker-Befehle

package require twapi_printer

puts "=== twapi Version ==="
catch { puts "twapi: [package present twapi]" }
catch { puts "twapi_printer: [package present twapi_printer]" }

puts "\n=== Alle twapi::*print* und *printer* Befehle ==="
foreach c [lsort [concat \
    [info commands twapi::*print*] \
    [info commands twapi::*printer*]]] {
    puts "  $c"
}

puts "\n=== enumerate_printers ohne Optionen ==="
catch {
    set printers [twapi::enumerate_printers]
    puts "Anzahl: [llength $printers]"
    if {[llength $printers] > 0} {
        set first [lindex $printers 0]
        puts "Keys erster Eintrag: [dict keys $first]"
        dict for {k v} $first {
            puts "  $k = [string range $v 0 60]"
        }
    }
} err
if {$err ne ""} { puts "Fehler: $err" }

puts "\n=== enumerate_printers -proximity local ==="
catch {
    set printers [twapi::enumerate_printers -proximity local]
    puts "Anzahl local: [llength $printers]"
    if {[llength $printers] > 0} {
        set first [lindex $printers 0]
        puts "Keys: [dict keys $first]"
        dict for {k v} $first {
            puts "  $k = [string range $v 0 60]"
        }
    }
} err
if {$err ne ""} { puts "Fehler: $err" }

puts "\n=== get_default_printer ==="
catch { puts [twapi::get_default_printer] } err
if {$err ne ""} { puts "Fehler: $err" }

puts "\ndone."
