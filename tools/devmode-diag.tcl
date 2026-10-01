#!/usr/bin/env tclsh
# devmode-diag.tcl -- DEVMODE Struct fuer einen Drucker analysieren

package require registry

set printer "kllaserdrucker"
if {[llength $argv] > 0} { set printer [lindex $argv 0] }

set base {HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Print\Printers}
set pkey "$base\\$printer"

puts "Drucker: $printer"

catch {
    set dm [registry get $pkey "Default DevMode"]
    set len [string length $dm]
    puts "DEVMODE Laenge: $len Bytes"

    # Ersten 128 Bytes als Hex ausgeben
    puts "\nBytes 80-110 (Color/Duplex/DPI Bereich):"
    for {set i 80} {$i < 112 && $i < $len} {incr i} {
        binary scan [string index $dm $i] cu byte
        puts [format "  Offset %3d: %3d (0x%02X)" $i $byte $byte]
    }

    # DEVMODEW Offsets (Unicode, Struct nach MSDN):
    # 0-63:   dmDeviceName (WCHAR[32] = 64 bytes)
    # 64-65:  dmSpecVersion
    # 66-67:  dmDriverVersion
    # 68-69:  dmSize
    # 70-71:  dmDriverExtra
    # 72-75:  dmFields (DWORD)
    # 76-77:  dmOrientation
    # 78-79:  dmPaperSize
    # 80-81:  dmPaperLength
    # 82-83:  dmPaperWidth
    # 84-85:  dmScale
    # 86-87:  dmCopies
    # 88-89:  dmDefaultSource  <- Kassette
    # 90-91:  dmPrintQuality   <- DPI (negativ = enum: -1=draft,-2=low,-3=med,-4=high)
    # 92-93:  dmColor          <- 1=Mono, 2=Farbe
    # 94-95:  dmDuplex         <- 1=Simplex, 2=Vertikal, 3=Horizontal
    # 96-97:  dmYResolution    <- DPI Y
    # 98-99:  dmTTOption
    # 100-101: dmCollate

    puts "\n--- Interpretierte Werte ---"
    binary scan $dm @64s  specVersion
    binary scan $dm @68s  dmSize
    puts "dmSpecVersion: $specVersion"
    puts "dmSize:        $dmSize"

    binary scan $dm @86s  copies
    binary scan $dm @88s  defaultSource
    binary scan $dm @90s  printQuality
    binary scan $dm @92s  color
    binary scan $dm @94s  duplex
    binary scan $dm @96s  yResolution

    puts "dmCopies:         $copies"
    puts "dmDefaultSource:  $defaultSource"
    puts "dmPrintQuality:   $printQuality"
    puts "dmColor:          $color  (1=Mono, 2=Farbe)"
    puts "dmDuplex:         $duplex  (1=Simplex, 2=VertDuplex, 3=HorzDuplex)"
    puts "dmYResolution:    $yResolution"

    # DPI X aus dmPrintQuality (wenn positiv) oder dmYResolution
    if {$printQuality > 0} {
        puts "DPI X (dmPrintQuality): $printQuality"
    } else {
        puts "DPI X (enum): [expr {$printQuality}] (negativ = Qualitaetsstufe)"
    }

} err
if {$err ne ""} { puts "Fehler: $err" }

puts "\n--- WMI Vergleich ---"
catch {
    package require twapi
    set wmi [twapi::_wmi]
    $wmi -with {{ExecQuery \
        "SELECT Name,Color,Duplex,YResolution FROM Win32_PrinterConfiguration"}} \
        -iterate pc {
        catch {
            if {[$pc Name] eq $printer} {
                puts "WMI Color:       [$pc Color]  (1=Mono, 2=Farbe)"
                puts "WMI Duplex:      [$pc Duplex]  (0=nein, 1=ja)"
                puts "WMI YResolution: [$pc YResolution]"
            }
        }
    }
} err
if {$err ne ""} { puts "WMI Fehler: $err" }

puts "\ndone."
