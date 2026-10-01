#!/usr/bin/env tclsh
# test-pdfium-backend-guard.tcl -- keep the copies honest
#
# test-pdfium-backend.tcl does not exercise printlib-0.2.tm directly. It
# pastes two procedures under "The code under test" and tests those pastes:
#   ::printlib::_pdfiumFormForLabel   (from printlib-0.2.tm)
#   ::printlib::bookletOrder          (from printlib-booklet.tcl)
#
# That is fine only as long as paste and original agree. The moment someone
# edits the module and forgets the test copy, the suite stays green while the
# shipped code is wrong -- a silent divergence.
#
# This guard compares the two, character for character, and fails loudly if
# they drift apart. Run it alongside the backend test.
#
#   tclsh test-pdfium-backend-guard.tcl

set here [file dirname [file normalize [info script]]]
set root [file dirname $here]        ;# repo root (test/ is one below)

# Find a shipped file across the possible layouts (0.3 repo uses lib/tm;
# the old vendor/ layout kept everything next to the test).
#
# doc/ is in the list since 17.09.2026: printlib-booklet.tcl moved there
# because it is a draft, not shipped code -- the module never sources it.
# The guard still compares the test copy against it, so the copy cannot
# drift away from the draft either.
proc _find {name} {
    global here root
    foreach cand [list \
            [file join $root lib tm $name] \
            [file join $root lib tm printlib $name] \
            [file join $root doc $name] \
            [file join $here $name] \
            [file join $root $name]] {
        if {[file exists $cand]} { return $cand }
    }
    return [file join $root lib tm $name]
}

# Cut a proc body by lines: from `proc ::printlib::NAME ` to the next line
# that is exactly `}` at column 0 -- the file's own convention.
proc cutProc {file name} {
    set fh [open $file]; fconfigure $fh -encoding utf-8
    set lines [split [read $fh] \n]; close $fh
    set out {}; set inside 0
    foreach z $lines {
        if {!$inside && [string match "proc ::printlib::$name *" $z]} {
            set inside 1
        }
        if {$inside} {
            lappend out $z
            if {$z eq "\}"} break
        }
    }
    return $out
}

set testFile   [file join $here test-pdfium-backend.tcl]
# Den Dateinamen ABLEITEN, nicht festschreiben. Hier stand
# "_find printlib-0.3.tm"; beim Sprung auf 0.3.1 haette der Waechter
# die alte Datei gesucht, nicht gefunden und -- je nach Lage -- entweder
# laut gefehlt oder eine danebenliegende alte Fassung verglichen.
# Ein Waechter, der die falsche Datei bewacht, ist keiner.
if {[catch {package require printlib}]} {
    # Nicht im Modulpfad: dann ueber die Datei selbst gehen.
    foreach cand [glob -nocomplain [file join $root lib tm printlib-*.tm]] {
        if {![catch {source $cand}]} { break }
    }
}
set moduleFile [_find printlib-[package provide printlib].tm]
set bookletFile [_find printlib-booklet.tcl]

# name -> file that holds the real definition
set pairs {
    _pdfiumFormForLabel  $moduleFile
    bookletOrder         $bookletFile
}

set fail 0
foreach {name fileVar} $pairs {
    set original [subst $fileVar]
    set copy [cutProc $testFile $name]
    set real [cutProc $original $name]

    if {![llength $copy]} {
        puts "  ✗ $name: no copy found in the test file"
        incr fail ; continue
    }
    if {![llength $real]} {
        puts "  ✗ $name: not found in [file tail $original]"
        incr fail ; continue
    }
    if {[join $copy \n] eq [join $real \n]} {
        puts "  ✓ $name: copy matches [file tail $original] ([llength $real] lines)"
    } else {
        puts "  ✗ $name: DIVERGED from [file tail $original]"
        puts "      copy [llength $copy] lines, original [llength $real] lines"
        # first differing line, to make the fix obvious
        set n [expr {min([llength $copy],[llength $real])}]
        for {set i 0} {$i < $n} {incr i} {
            if {[lindex $copy $i] ne [lindex $real $i]} {
                puts "      first diff at line [expr {$i+1}] of the proc:"
                puts "        test:   [string trim [lindex $copy $i]]"
                puts "        module: [string trim [lindex $real $i]]"
                break
            }
        }
        incr fail
    }
}

puts ""
if {$fail} {
    puts "GUARD FAILED: $fail procedure(s) out of sync."
    puts "The test copy and the shipped code must be kept identical, or the"
    puts "backend test is checking dead code. Update whichever is stale."
    exit 1
}
puts "guard ok: test copies are identical to the shipped procedures."
exit 0
