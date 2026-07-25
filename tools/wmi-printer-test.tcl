#!/usr/bin/env tclsh
# wmi-printer-test.tcl -- korrekte twapi 5.x WMI Syntax

package require twapi

puts "=== twapi [package version twapi] WMI Win32_Printer ==="

# Korrekte twapi WMI Syntax: _wmi + -with + ExecQuery + -iterate
catch {
    set wmi [twapi::_wmi]
    $wmi -with {{ExecQuery "SELECT Name,DriverName,PortName,ColorSupported,Duplex,HorizontalResolution,VerticalResolution,Default FROM Win32_Printer"}} -iterate printer {
        set name  [$printer Name]
        set driver [$printer DriverName]
        set port  [$printer PortName]
        set color [$printer ColorSupported]
        set duplex [$printer Duplex]
        set dpi_h  [$printer HorizontalResolution]
        set dpi_v  [$printer VerticalResolution]
        set def    [$printer Default]
        puts "\nDrucker: $name"
        puts "  Treiber:  $driver"
        puts "  Port:     $port"
        puts "  Farbe:    $color"
        puts "  Duplex:   $duplex"
        puts "  DPI:      ${dpi_h} x ${dpi_v}"
        puts "  Standard: $def"
    }
} err
if {$err ne ""} { puts "Fehler: $err" }

puts "\n=== Win32_PrinterConfiguration (Kassetten etc.) ==="
catch {
    set wmi2 [twapi::_wmi]
    $wmi2 -with {{ExecQuery "SELECT Name,Color,Duplex,PaperSize,YResolution FROM Win32_PrinterConfiguration"}} -iterate pc {
        set name  [$pc Name]
        set color [$pc Color]
        set dup   [$pc Duplex]
        set paper [$pc PaperSize]
        set dpi   [$pc YResolution]
        puts "  $name | Color=$color Duplex=$dup Paper=$paper DPI=$dpi"
    }
} err2
if {$err2 ne ""} { puts "Fehler: $err2" }

puts "\ndone."

