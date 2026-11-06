; One line per block size, paired implementations side by side. KiB/s only:
; median [minimum..maximum], * = coarse RTC, ----- = unavailable time.
CompactSummary:
                ld      hl,CompactTemplate
                ld      de,CompactRow
                ld      bc,CompactRowSize
                ldir
                ld      hl,(SeriesWorker+1)
                ld      de,FileReadPass
                or      a
                sbc     hl,de
                ld      hl,CompactFile
                jr      z,.kind
                ld      hl,(SeriesWorker+1)
                ld      de,BiosReadPass
                or      a
                sbc     hl,de
                ld      hl,CompactBios
                jr      z,.kind
                ld      a,(SeriesArgs+4)
                and     1
                ld      hl,CompactAtaRead
                jr      z,.ata
                ld      hl,CompactAtaMulti
.ata:           ld      a,(UseCache)
                or      a
                jr      z,.kind
                ld      a,(SeriesArgs+4)
                and     1
                ld      hl,CompactSramRead
                jr      z,.kind
                ld      hl,CompactSramMulti
.kind:          ld      a,(TargetSram)
                or      a
                jr      z,.copyKind
                ld      a,(SeriesArgs+4)
                and     1
                ld      hl,CompactSsRead
                jr      z,.copyKind
                ld      hl,CompactSsMulti
.copyKind:      ld      de,CompactRow.kind
                ld      bc,6
                ldir
                ld      hl,(SeriesArgs)
                ld      de,CompactRow.size
                ld      bc,4
                ldir
                call    SeriesSort
                ld      de,CompactRow.median
                call    CompactMetrics
                ld      a,(PairType)
                or      a
                jr      z,.single
                cp      1
                jr      z,.peer
                ld      hl,CompactPeerSram
                ld      de,CompactRow.peerLabel
                ld      bc,8
                ldir
.peer:          ld      hl,SeriesPeerTimes
                ld      de,SeriesTimes
                ld      bc,20
                ldir
                ld      a,(SeriesPeerRtc)
                ld      (SeriesRtc),a
                call    SeriesSort
                ld      de,CompactRow.peerMedian
                call    CompactMetrics
                jr      .print
.single:        ld      hl,CompactRow.peerLabel
                ld      de,CompactRow.peerLabel+1
                ld      (hl)," "
                ld      bc,28
                ldir
.print:         ld      a,(ThirdEnabled)
                or      a
                jr      z,.output
                call    SeriesLoadThird
                call    SeriesSort
                ld      a,1
                ld      (SilentResult),a
                ld      a,(RepeatCount)
                srl     a
                call    SeriesPrint
                xor     a
                ld      (SilentResult),a
                ld      hl,CompactSsLabel
                ld      de,CompactRow.third
                ld      bc,5
                ldir
                ld      hl,SpeedNumStr
                ld      bc,5
                ldir
                ld      a,(SeriesRtc)
                or      a
                jr      z,.output
                ld      a,"*"
                ld      (de),a
.output:        ld      hl,CompactRow
                call    SeriesText
                or      a
                ret
CompactMetrics: ld      (CompactDestination),de
                ld      a,1
                ld      (SilentResult),a
                ld      a,(RepeatCount)
                srl     a
                call    SeriesPrint
                call    .copy
                ld      a,(RepeatCount)         ; largest time = minimum speed
                dec     a
                call    SeriesPrint
                call    .copy
                xor     a
                call    SeriesPrint
                call    .copy
                ld      hl,(CompactDestination)
                dec     hl
                ld      a,(SeriesRtc)
                or      a
                ld      a," "
                jr      z,.marker
                ld      a,"*"
.marker:        ld      (hl),a
                xor     a
                ld      (SilentResult),a
                ret
.copy:          ld      hl,SpeedNumStr
                ld      de,(CompactDestination)
                ld      bc,5
                ldir
                inc     de
                inc     de
                ld      (CompactDestination),de
                ret
CompactDestination: dw 0
CompactFile:    db "FILE  "
CompactBios:    db "BIOS  "
CompactAtaRead: db "ATA-R "
CompactAtaMulti: db "ATA-M "
CompactSramRead: db "SRAM-R"
CompactSramMulti: db "SRAM-M"
CompactSsRead: db "SS-R  "
CompactSsMulti: db "SS-M  "
CompactSsLabel: db " |SS "
CompactPeerSram: db " | SRAM "
CompactCarriage: db 13,0
CompactLegend: db "KiB/s: median [min..max]; *=RTC coarse; Esc=cancel; /V=details",13,10
                db "ATA=DRAM/DRAM; SRAM=SRAM/DRAM; SS=SRAM/SRAM median; CRC=first pass",13,10,0
CompactTemplate: db 13,"FILE  512B ----- [-----..-----]  | BIOS ----- [-----..-----]                 ",13,10,0
CompactRow:
                db 13
.kind:          ds 6
.size:          ds 4
                db " "
.median:        db "----- ["
.minimum:       db "-----.."
.maximum:       db "-----]"
.rtc:           db " "
.peerLabel:     db " | BIOS "
.peerMedian:    db "----- ["
.peerMinimum:   db "-----.."
.peerMaximum:   db "-----]"
.peerRtc:       db " "
.third:         ds 16," "
                db 13,10,0
CompactRowSize equ $-CompactRow
                ASSERT CompactRowSize == CompactRow-CompactTemplate
