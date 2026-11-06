; One untimed validation/warmup, then /R samples. Buffer checks never run
; inside measured samples. SeriesTimes sorted as unsigned 32-bit ticks.
TestConsistentRead:
                ld      ix,FileReadPass
                jp      RunSeries
TestBiosRead:   ld      ix,BiosReadPass
                jp      RunSeries
TestAtaRead:    ld      ix,AtaReadPass
RunSeries:      ld      (SeriesArgs),hl
                ld      (SeriesArgs+2),de
                ld      (SeriesArgs+4),bc
                ld      (SeriesWorker+1),ix
                ld      (SeriesOriginalDE),de
                call    SeriesChoosePair
                xor     a
                ld      (SeriesIndex),a
                ld      (SeriesRtc),a
                ld      (SeriesPeerRtc),a
                ld      (SeriesThirdRtc),a
                inc     a
                ld      (VerifyPass),a
                call    SeriesRound
                ret     c
                xor     a
                ld      (VerifyPass),a
.loop:          call    SeriesRound
                ret     c
                ld      a,(SeriesIndex)
                inc     a
                ld      (SeriesIndex),a
                ld      b,a
                ld      a,(RepeatCount)
                cp      b
                jr      nz,.loop
                ld      a,(VerboseOutput)
                or      a
                jp      z,CompactSummary
                ld      a,(PairType)
                or      a
                jr      z,.summary
                cp      1
                ld      hl,FilePrimaryStr
                jr      z,.primary
                ld      hl,DramPrimaryStr
.primary:       call    SeriesText
.summary:       call    SeriesSummary
                ld      a,(PairType)
                or      a
                ret     z
                cp      1
                ld      hl,MapPeerStr
                jr      z,.peerTitle
                ld      hl,CachePeerStr
.peerTitle:     call    SeriesText
                ld      a,(SeriesPeerRtc)
                ld      (SeriesRtc),a
                ld      hl,SeriesPeerTimes
                ld      de,SeriesTimes
                ld      bc,20
                ldir
                call    SeriesSummary
                ld      a,(ThirdEnabled)
                or      a
                ret     z
                ld      hl,ThirdTitleStr
                call    SeriesText
                call    SeriesLoadThird
                call    SeriesSummary
                or      a
                ret
SeriesSummary:  call    SeriesSort
                jp      SeriesVerboseStats
SeriesSort:     ; bubble sort; at most five samples
                ld      a,(RepeatCount)
                dec     a
                jr      z,.sorted
                ld      b,a
.outer:         push    bc
                ld      ix,SeriesTimes
                ld      a,(RepeatCount)
                dec     a
                ld      b,a
.inner:         ld      l,(ix+2)
                ld      h,(ix+3)
                ld      e,(ix+6)
                ld      d,(ix+7)
                or      a
                sbc     hl,de
                jr      c,.noswap
                jr      nz,.swap
                ld      l,(ix+0)
                ld      h,(ix+1)
                ld      e,(ix+4)
                ld      d,(ix+5)
                or      a
                sbc     hl,de
                jr      c,.noswap
                jr      z,.noswap
.swap:          push    bc
                push    ix
                pop     hl
                push    hl
                ld      de,4
                add     hl,de
                ex      de,hl
                pop     hl
                ld      b,4
.bytes:         ld      a,(de)
                ld      c,(hl)
                ld      (hl),a
                ld      a,c
                ld      (de),a
                inc     hl
                inc     de
                djnz    .bytes
                pop     bc
.noswap:        ld      de,4
                add     ix,de
                djnz    .inner
                pop     bc
                djnz    .outer
.sorted:        ret
SeriesVerboseStats:
                ld      hl,MedianStr
                call    SeriesText
                ld      a,(RepeatCount)
                srl     a
                call    SeriesPrint
                ld      hl,FastestStr
                call    SeriesText
                xor     a
                call    SeriesPrint
                ld      hl,SlowestStr
                call    SeriesText
                ld      a,(RepeatCount)
                dec     a
                call    SeriesPrint
                or      a
                ret
SeriesChoosePair:
                xor     a
                ld      (PairType),a
                ld      (ThirdEnabled),a
                ld      hl,(SeriesWorker+1)
                ld      de,FileReadPass
                or      a
                sbc     hl,de
                jr      nz,.ata
                ld      a,(MapValid)
                or      a
                ret     z
                ld      a,1
                ld      (PairType),a
                ld      (MapPaired),a
                ret
.ata:           ld      hl,(SeriesWorker+1)
                ld      de,AtaReadPass
                or      a
                sbc     hl,de
                ret     nz
                ld      a,(UseCache)
                or      a
                ret     nz
                ld      a,(CacheReady)
                or      a
                ret     z
                ld      a,2
                ld      (PairType),a
                ld      (CachePaired),a
                ld      a,(SramIoReady)
                ld      (ThirdEnabled),a
                ret
SeriesRound:    ld      a,(ThirdEnabled)
                or      a
                jr      z,.pair
                ld      a,(SeriesIndex)
.mod3:          cp      3
                jr      c,.start3
                sub     3
                jr      .mod3
.start3:        ld      (PeerNow),a
                ld      b,3
.triple:        push    bc
                call    SeriesCall
                pop     bc
                ret     c
                ld      a,(PeerNow)
                inc     a
                cp      3
                jr      c,.next3
                xor     a
.next3:         ld      (PeerNow),a
                djnz    .triple
                or      a
                ret
.pair:    ld      a,(PairType)
                or      a
                jr      z,.single
                ld      a,(SeriesIndex)
                and     1
                ld      (PeerNow),a
                call    SeriesCall
                ret     c
                ld      a,(PeerNow)
                xor     1
                ld      (PeerNow),a
                jp      SeriesCall
.single:        xor     a
                ld      (PeerNow),a
                jp      SeriesCall
SeriesCall:     ld      a,(PeerNow)
                or      a
                jp      z,SeriesWorker
                ld      a,(PairType)
                cp      1
                jr      nz,.cache
                ld      hl,(SeriesOriginalDE)
                ld      a,h
                srl     a
                ld      l,a
                ld      h,0
                ld      (SeriesArgs+2),hl
                ld      a,1
                ld      (MapMode),a
                call    BiosReadPass
                push    af
                ld      hl,(SeriesOriginalDE)
                ld      (SeriesArgs+2),hl
                xor     a
                ld      (MapMode),a
                call    MapEnd
                pop     af
                ret
.cache:         ld      a,(PeerNow)
                cp      2
                jr      nz,.cacheDram
                ld      a,1
                ld      (TargetSram),a
                ld      hl,SramIoBuffer
                ld      (AtaBuffer),hl
.cacheDram:     ld      a,1
                ld      (UseCache),a
                call    SeriesWorker
                push    af
                xor     a
                ld      (UseCache),a
                ld      (TargetSram),a
                ld      hl,Buffer
                ld      (AtaBuffer),hl
                pop     af
                ret
SeriesWorker:   jp      0

SeriesLoad:     ld      hl,(SeriesArgs)
                ld      de,(SeriesArgs+2)
                ld      bc,(SeriesArgs+4)
                ret
SeriesTitle:    ld      a,(VerifyPass)
                or      a
                ret     z
                push    hl
                ld      a,(VerboseOutput)
                or      a
                jr      nz,.title
                ld      hl,CompactCarriage
                call    SeriesText
.title:         pop     hl
                call    SeriesText
                ld      hl,VerifyStartStr
SeriesText:     ld      c,Dss.PChars
                rst     0x10
                ret
SeriesFinish:   ld      (SeriesSectors),hl
                ld      a,(VerifyPass)
                or      a
                jr      nz,.verified
                call    TimerStop
                ld      hl,SeriesRtc
                ld      a,(PeerNow)
                or      a
                jr      z,.rtcBank
                ld      hl,SeriesPeerRtc
                cp      2
                jr      nz,.rtcBank
                ld      hl,SeriesThirdRtc
.rtcBank:       ld      a,(RtcUsed)
                or      (hl)
                ld      (hl),a
                ld      a,(SeriesIndex)
                add     a,a
                add     a,a
                ld      e,a
                ld      d,0
                ld      hl,SeriesTimes
                ld      a,(PeerNow)
                or      a
                jr      z,.bank
                ld      hl,SeriesPeerTimes
                cp      2
                jr      nz,.bank
                ld      hl,SeriesThirdTimes
.bank:          add     hl,de
                ex      de,hl
                ld      hl,Elapsed
                ld      bc,4
                ldir
                or      a
                ret
.verified:      jp      VerifyFinish
SeriesPrint:    add     a,a
                add     a,a
                ld      e,a
                ld      d,0
                ld      hl,SeriesTimes
                add     hl,de
                ld      de,Elapsed
                ld      bc,4
                ldir
                ld      a,(SeriesRtc)
                ld      (RtcUsed),a
                ld      hl,(SeriesSectors)
                push    hl
                jp      PrintStopped
MedianStr:      db "Median: ",0
FastestStr:     db "Minimum time: ",0
SlowestStr:     db "Maximum time: ",0
RepeatCount:    db 3
VerifyPass:     db 0
SeriesIndex:    db 0
SeriesRtc:      db 0
SeriesArgs:     ds 6
SeriesTimes:    ds 20
SeriesPeerTimes: ds 20
SeriesSectors:  dw 0

SeriesOriginalDE: dw 0
PairType:       db 0
PeerNow:        db 0
MapPaired:      db 0
CachePaired:    db 0
FilePrimaryStr: db "File results (alternating with mapped BIOS):",13,10,0
DramPrimaryStr: db "ATA DRAM results (alternating with SRAM):",13,10,0
MapPeerStr:     db "Mapped BIOS results:",13,10,0
CachePeerStr:   db "ATA SRAM results:",13,10,0

SeriesPeerRtc:  db 0

VerifyStartStr: db "checking full data ",0

ThirdEnabled:   db 0
SeriesThirdRtc: db 0
SeriesThirdTimes: ds 20
SeriesLoadThird:
                ld      hl,SeriesThirdTimes
                ld      de,SeriesTimes
                ld      bc,20
                ldir
                ld      a,(SeriesThirdRtc)
                ld      (SeriesRtc),a
                ret
ThirdTitleStr:  db "SS: SRAM code -> SRAM buffer:",13,10,0
