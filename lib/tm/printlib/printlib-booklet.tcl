# ==========================================================================
#  printlib-booklet.tcl  --  booklet printing for printlib
#
#  Deliberately NOT in the C layer: reordering pages is pure arithmetic
#  on the page list and therefore works for every backend, including lp
#  on Linux. Only writing the reordered file needs pdfiumtcl, and that
#  part is platform independent because no GDI is involved.
#
#  To be merged into printlib-0.2.tm.
# ==========================================================================


# --------------------------------------------------------------------------
# bookletOrder -- page order for a saddle-stitched booklet
#
# Result: list of page numbers (1-based), 0 = blank page.
# The length is always a multiple of 4; missing pages are padded with
# blanks, and those land at the back of the booklet, not at the front.
#
# The result is printed 2-up, duplex, flipped on the SHORT edge. With a
# long-edge flip every second page comes out upside down -- the most
# common mistake in booklet printing.
#
# Layout per sheet (four list entries):
#   [0] outer left   [1] outer right   -> front side
#   [2] inner left   [3] inner right   -> back side
#
# Example n=8:  8 1 2 7 6 3 4 5
#   sheet 1 front: 8|1   back: 2|7
#   sheet 2 front: 6|3   back: 4|5
# --------------------------------------------------------------------------
proc ::printlib::bookletOrder {n} {
    if {![string is integer -strict $n] || $n < 1} {
        error "printlib::bookletOrder: page count must be >= 1"
    }
    set N [expr {(($n + 3) / 4) * 4}]
    set out {}
    for {set i 0} {$i < $N / 4} {incr i} {
        set a [expr {$N - 2*$i}]
        set b [expr {2*$i + 1}]
        set c [expr {2*$i + 2}]
        set d [expr {$N - 2*$i - 1}]
        foreach p [list $a $b $c $d] {
            lappend out [expr {$p > $n ? 0 : $p}]
        }
    }
    return $out
}

# --------------------------------------------------------------------------
# makeBooklet -- write the reordered PDF file
#
#   makeBooklet source.pdf target.pdf ?-pages 1-12?
#
# Needs pdfiumtcl 0.4+ (importpages, newpage). Runs on every platform --
# nothing is printed here, pages are only rearranged.
#
# Returns the target path.
# --------------------------------------------------------------------------
proc ::printlib::makeBooklet {src dst args} {
    if {[catch {package require pdfiumtcl} e]} {
        error "printlib::makeBooklet: pdfiumtcl not available: $e"
    }
    if {![file exists $src]} {
        error "printlib::makeBooklet: file not found: $src"
    }

    set first 1
    set last  0
    foreach {opt val} $args {
        switch -- $opt {
            -pages {
                if {[regexp {^(\d+)-(\d+)$} $val -> first last]} {
                } elseif {[string is integer -strict $val]} {
                    set first $val ; set last $val
                } else {
                    error "printlib::makeBooklet: invalid page range: $val"
                }
            }
            default { error "printlib::makeBooklet: unknown option: $opt" }
        }
    }

    set in [::pdfium::open $src]
    set total [::pdfium::pagecount $in]
    if {$last <= 0 || $last > $total} { set last $total }
    if {$first < 1} { set first 1 }
    if {$first > $last} {
        ::pdfium::close $in
        error "printlib::makeBooklet: empty page range"
    }

    set count [expr {$last - $first + 1}]
    set order [bookletOrder $count]

    # Page size of the first page -- blank pages must use the same
    # format, otherwise the output shifts on the sheet.
    lassign [::pdfium::pagesize $in [expr {$first - 1}]] w_mm h_mm
    set mm2pt 2.8346456692913385
    set w_pt [expr {$w_mm * $mm2pt}]
    set h_pt [expr {$h_mm * $mm2pt}]

    set out [::pdfium::newdoc]
    set idx 0
    set rc [catch {
        foreach p $order {
            if {$p == 0} {
                set pg [::pdfium::newpage $out $idx $w_pt $h_pt]
                ::pdfium::generatecontent $pg
                ::pdfium::closepage $pg
            } else {
                # order counts within the selected range, importpages
                # expects the number in the source document
                set real [expr {$first + $p - 1}]
                ::pdfium::importpages $out $in $real $idx
            }
            incr idx
        }
        ::pdfium::save $out $dst
    } err]

    catch {::pdfium::close $out}
    catch {::pdfium::close $in}

    if {$rc} { error "printlib::makeBooklet: $err" }
    return $dst
}

# --------------------------------------------------------------------------
# Merging into ::printlib::print
# --------------------------------------------------------------------------
#
#  a) extend the local dict with "booklet 0", plus the option branch:
#
#       -booklet { dict set local booklet $val; lappend cliKeys booklet }
#
#  b) insert directly before the backend dispatch:

    # --- booklet ----------------------------------------------------------
    #
    # Reordering happens before the backend so that it applies to all of
    # them. Afterwards the page range is cleared -- it is already baked
    # into the new file, and applying it a second time would cut the
    # sheet sequence apart.
    set tmpBooklet ""
    if {[dict get $local booklet]} {
        set tmpBooklet [file join [_tmpDir] \
                            "printlib-booklet-[pid]-[clock clicks].pdf"]
        set mkArgs {}
        if {[dict get $local pages] ne ""} {
            lappend mkArgs -pages [dict get $local pages]
        }
        makeBooklet $pdffile $tmpBooklet {*}$mkArgs
        set pdffile $tmpBooklet
        dict set local pages ""

        # 2-up landscape, short-edge flip. These are enforced, not
        # suggested: a booklet with -nup 1 or -duplex long is not a
        # booklet, it is waste paper.
        dict set local nup         2
        dict set local orientation landscape
        dict set local duplex      short
        dict set local scale       fit
    }

#  c) clean up after the dispatch -- today it ends with
#     "return [_print_...]", which has to be restructured:
#
#       set rc [catch {
#           switch -- $be {
#               pdftocairo { _print_pdftocairo $pdffile $local }
#               sumatra    { _print_sumatra    $pdffile $local }
#               lp         { _print_lp         $pdffile $local }
#               pdfium     { _print_pdfium     $pdffile $local }
#               default    { error "unknown backend: $be" }
#           }
#       } res]
#       if {$tmpBooklet ne ""} { catch {file delete $tmpBooklet} }
#       if {$rc} { return -code error $res }
#       return $res
#
#  d) _tmpDir does not exist in printlib yet -- take the variant from
#     pdf2imgprint:
#
#       proc ::printlib::_tmpDir {} {
#           foreach v {TMPDIR TEMP TMP} {
#               if {[info exists ::env($v)] &&
#                   [file isdirectory $::env($v)]} { return $::env($v) }
#           }
#           return [expr {$::tcl_platform(platform) eq "windows"
#                         ? "C:/Temp" : "/tmp"}]
#       }

# --------------------------------------------------------------------------
# Backend support for -nup
# --------------------------------------------------------------------------
#
#   pdfium      -> pass -nup through (see pdfium-print-layout.c)
#   lp          -> lp -o number-up=2 -o number-up-layout=lrtb
#   pdftocairo  -> no n-up. Either impose beforehand with pdfjam/pdftk
#                  or switch to another backend for booklets.
#   sumatra     -> no n-up.
#
# Consequence: -booklet only makes sense with pdfium (Windows) and lp
# (Linux/macOS). print() therefore needs a check:
#
#     if {[dict get $local booklet] && $be ni {pdfium lp}} {
#         error "printlib::print: -booklet needs backend pdfium or lp\
#                (active: $be)"
#     }
#
# A deliberate error instead of a silent fallback to single-sided 1-up
# output -- that would ruin the sheet sequence and only become obvious
# at the paper stack.

# --------------------------------------------------------------------------
# Examples
# --------------------------------------------------------------------------
#
#   # 12-page booklet on A4 landscape, 2-up, short edge
#   ::printlib::print manual.pdf -printer $p -booklet 1
#
#   # just the reordering, without printing
#   ::printlib::makeBooklet manual.pdf booklet.pdf
#
#   # check the order before any paper is used
#   puts [::printlib::bookletOrder [::pdfium::pagecount $doc]]
