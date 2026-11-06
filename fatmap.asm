; Read-only FAT12/16/32 mapping. One 32-bit relative LBA per cluster, in four
; DSS pages mapped into WIN1. No FAT access/allocation inside timed reads.
MapPrepare:     xor     a
                ld      (MapValid),a
                inc     a
                ld      (MapStage),a
                xor     a
                ld      hl,TestFileName
                ld      de,MapDta
                ld      bc,Dss.F_First
                rst     0x10
                jp      c,MapSkip
                ld      hl,(FileBlocks)
                ld      de,512
                call    Mul16x16
                ld      bc,(MapDta+28)
                ex      de,hl
                or      a
                sbc     hl,bc
                jp      nz,MapSkip
                ex      de,hl
                ld      bc,(MapDta+30)
                sbc     hl,bc
                jp      nz,MapSkip
                ld      a,2
                ld      (MapStage),a
                ld      hl,0
                ld      de,0
                call    MapRead
                jp      c,MapSkip
                ld      hl,(Buffer+510)
                ld      de,0xAA55
                or      a
                sbc     hl,de
                jp      nz,MapSkip
                ld      hl,(Buffer+11)
                ld      de,512
                or      a
                sbc     hl,de
                jp      nz,MapSkip
                ld      a,(Buffer+13)
                or      a
                jp      z,MapSkip
                ld      b,a
                dec     a
                and     b
                jp      nz,MapSkip
                ld      a,b
                ld      (MapSpc),a
                ld      hl,(Buffer+14)
                ld      a,h
                or      l
                jp      z,MapSkip
                ld      (MapFatStart),hl
                ld      a,(Buffer+16)
                or      a
                jp      z,MapSkip
                ld      (MapFatCount),a
                ld      hl,(Buffer+19)
                ld      a,h
                or      l
                ld      de,0
                jr      nz,.total
                ld      hl,(Buffer+32)
                ld      de,(Buffer+34)
.total:         ld      (MapTotal),hl
                ld      (MapTotal+2),de
                ld      hl,(Buffer+22)
                ld      (MapFat16Size),hl
                ld      de,0
                ld      a,h
                or      l
                jr      nz,.fatSize
                ld      hl,(Buffer+36)
                ld      de,(Buffer+38)
.fatSize:       ld      (MapFatSize),hl
                ld      (MapFatSize+2),de
                ld      a,h
                or      l
                or      d
                or      e
                jp      z,MapSkip
                ld      hl,(Buffer+40)
                ld      (MapFlags),hl
                ld      hl,(Buffer+42)
                ld      (MapVersion),hl
                ld      hl,(Buffer+17)
                ld      de,15
                add     hl,de
                jp      c,MapSkip
                REPT 4
                srl     h
                rr      l
                ENDR
                ld      (MapRootSectors),hl
                ; total must fit in the driver-reported partition
                ld      hl,(MapTotal+2)
                ld      de,(MapTotal)
                ld      ix,PartSize
                call    MapSubtract
                jp      c,.totalOk
                ld      a,h
                or      l
                or      d
                or      e
                jp      nz,MapSkip
.totalOk:       ld      hl,(MapTotal+2)
                ld      de,(MapTotal)
                ld      a,h
                or      l
                or      d
                or      e
                jp      z,MapSkip
                ; Last absolute LBA must fit in 32 bits.
                ld      ix,MapOne
                call    MapSubtract
                ld      ix,PartStart
                call    MapAdd
                jp      c,MapSkip
                ld      de,(MapFatStart)
                ld      hl,0
                ld      a,(MapFatCount)
.fats:          push    af
                ld      ix,MapFatSize
                call    MapAdd
                pop     bc
                jp      c,MapSkip
                ld      a,b
                dec     a
                jr      nz,.fats
                ld      ix,MapRootSectors
                call    MapAdd
                jp      c,MapSkip
                ld      (MapDataStart),de
                ld      (MapDataStart+2),hl
                ld      hl,(MapTotal+2)
                ld      de,(MapTotal)
                ld      ix,MapDataStart
                call    MapSubtract
                jp      c,MapSkip
                ld      a,(MapSpc)
.clusters:      srl     a
                jr      z,.clusterCount
                srl     h
                rr      l
                rr      d
                rr      e
                jr      .clusters
.clusterCount:  ld      (MapClusters),de
                ld      (MapClusters+2),hl
                ld      a,h
                or      l
                ld      a,32
                jr      nz,.type
                push    de
                ex      de,hl
                ld      bc,4085
                or      a
                sbc     hl,bc
                pop     de
                ld      a,12
                jr      c,.type
                push    de
                ex      de,hl
                ld      bc,65525
                or      a
                sbc     hl,bc
                pop     de
                ld      a,16
                jr      c,.type
                ld      a,32
.type:          ld      (MapFatType),a
                cp      32
                jr      nz,.oldFat
                ld      hl,(MapFat16Size)
                ld      a,h
                or      l
                jp      nz,MapSkip
                ld      hl,(MapRootSectors)
                ld      a,h
                or      l
                jp      nz,MapSkip
                ld      hl,(MapVersion)
                ld      a,h
                or      l
                jp      nz,MapSkip
                ld      hl,(MapDta+20)
                ld      (MapCluster+2),hl
                ld      a,(MapFlags)
                bit     7,a
                jr      z,.allocate
                and     15
                ld      b,a
                ld      a,(MapFatCount)
                cp      b
                jp      z,MapSkip
                jp      c,MapSkip
                ld      a,b
                or      a
                jr      z,.allocate
                ld      de,(MapFatStart)
                ld      hl,0
.active:        push    af
                ld      ix,MapFatSize
                call    MapAdd
                pop     bc
                jp      c,MapSkip
                ld      a,b
                dec     a
                jr      nz,.active
                ld      (MapFatStart),de
                ld      (MapFatStart+2),hl
                jr      .allocate
.oldFat:        ld      hl,(MapFat16Size)
                ld      a,h
                or      l
                jp      z,MapSkip
                ld      hl,(MapRootSectors)
                ld      a,h
                or      l
                jp      z,MapSkip
                ld      hl,0
                ld      (MapCluster+2),hl
.allocate:      ld      a,3
                ld      (MapStage),a
                ld      hl,(MapDta+26)
                ld      (MapCluster),hl
                ld      b,4
                ld      c,Dss.GetMem
                rst     0x10
                jp      c,MapSkip
                ld      (MapMem),a
                in      a,(WIN1_PORT)
                ld      (MapSavedWin),a
                ld      b,0
.pages:         push    bc
                ld      a,(MapMem)
                ld      c,Dss.SetWin1
                rst     0x10
                pop     bc
                jp      c,MapSkipRestore
                in      a,(WIN1_PORT)
                ld      hl,MapPages
                ld      e,b
                ld      d,0
                add     hl,de
                ld      (hl),a
                inc     b
                ld      a,b
                cp      4
                jr      nz,.pages
                ld      hl,0
                ld      (MapIndex),hl
                ld      hl,(FileBlocks)
                ld      (MapRemaining),hl
.chain:         ld      a,4
                ld      (MapStage),a
                call    MapClusterLba
                jp      c,MapSkipRestore
                push    hl
                push    de
                call    MapPointer
                pop     de
                ld      (hl),e
                inc     hl
                ld      (hl),d
                inc     hl
                pop     de
                ld      (hl),e
                inc     hl
                ld      (hl),d
                ld      hl,(MapIndex)
                inc     hl
                ld      (MapIndex),hl
                call    MapNextCluster
                jp      c,MapSkipRestore
                ld      hl,(MapRemaining)
                ld      a,(MapSpc)
                ld      e,a
                ld      d,0
                or      a
                sbc     hl,de
                jr      c,.last
                jr      z,.last
                ld      (MapRemaining),hl
                jr      .chain
.last:          ; Exact chain termination also rejects cycles and overlong chains.
                ld      hl,(MapCluster+2)
                ld      de,(MapCluster)
                ld      a,(MapFatType)
                cp      32
                jr      nz,.end16
                ld      bc,0x0FFF
                or      a
                sbc     hl,bc
                jp      nz,MapSkipRestore
                jr      .endCommon
.end16:         ld      a,h
                or      l
                jp      nz,MapSkipRestore
                ld      a,(MapFatType)
                cp      12
                jr      nz,.endCommon
                ld      a,d
                cp      0x0F
                jp      nz,MapSkipRestore
                ld      d,0xFF
.endCommon:     ld      a,d
                cp      0xFF
                jp      nz,MapSkipRestore
                ld      a,e
                cp      0xF8
                jp      c,MapSkipRestore
                ld      a,(MapSavedWin)
                out     (WIN1_PORT),a
                ld      a,1
                ld      (MapValid),a
                or      a
                ret
MapSkipRestore: ld      a,(MapSavedWin)
                out     (WIN1_PORT),a
MapSkip:        ld      a,(MapStage)
                ld      de,MapSkipStr.stage
                call    PutHex2
                ld      hl,MapSkipStr
                call    SeriesText
                scf
                ret

; HLDE += / -= little endian dword at IX; CF reports overflow/underflow.
MapAdd:         ld      c,(ix+0)
                ld      b,(ix+1)
                ex      de,hl
                add     hl,bc
                ex      de,hl
                ld      c,(ix+2)
                ld      b,(ix+3)
                adc     hl,bc
                ret
MapSubtract:    ld      c,(ix+0)
                ld      b,(ix+1)
                ex      de,hl
                or      a
                sbc     hl,bc
                ex      de,hl
                ld      c,(ix+2)
                ld      b,(ix+3)
                sbc     hl,bc
                ret
; Validate cluster [2, count+1], return relative LBA.
MapClusterLba:  ; FAT reserved/bad/EOC markers are never data clusters, even
                ; when a borderline BPB's cluster count includes their numbers.
                ld      hl,(MapCluster+2)
                ld      de,(MapCluster)
                ld      a,(MapFatType)
                cp      32
                jr      z,.limit32
                ld      a,h
                or      l
                jr      nz,.invalid
                ld      a,(MapFatType)
                cp      12
                ld      hl,0x0FF0
                jr      z,.limit16
                ld      hl,0xFFF0
.limit16:       or      a
                sbc     hl,de
                jr      c,.invalid
                jr      z,.invalid
                jr      .validated
.limit32:       ld      bc,0x0FFF
                or      a
                sbc     hl,bc
                jr      c,.validated
                jr      nz,.invalid
                ld      hl,0xFFF0
                or      a
                sbc     hl,de
                jr      c,.invalid
                jr      z,.invalid
.validated:     ld      hl,(MapCluster+2)
                ld      de,(MapCluster)
                ld      ix,MapTwo
                call    MapSubtract
                ret     c
                push    hl
                push    de
                ld      ix,MapClusters
                call    MapSubtract
                pop     de
                pop     hl
                ccf
                ret     c
                ld      a,(MapSpc)
.mul:           srl     a
                jr      z,.lba
                sla     e
                rl      d
                rl      l
                rl      h
                ret     c
                jr      .mul
.lba:           ld      ix,MapDataStart
                jp      MapAdd
.invalid:       scf
                ret
; HLDE partition-relative sector -> Buffer, bounds checked.
MapRead:        push    hl
                push    de
                ld      ix,PartSize
                call    MapSubtract
                pop     de
                pop     hl
                ccf
                ret     c
                ld      ix,PartStart
                call    MapAdd
                ret     c
                push    de
                pop     ix
                ld      de,Buffer
                ld      a,(PhysDrive)
                ld      b,1
                ld      c,Bios.DrvRead
                push    iy
                rst     ToBIOS
                pop     iy
                ret
; MapIndex -> HL address, mapping proper page (four-byte entries).
MapPointer:     ld      hl,(MapIndex)
                ld      a,h
                REPT 4
                rrca
                ENDR
                and     3
                ld      e,a
                ld      d,0
                push    hl
                ld      hl,MapPages
                add     hl,de
                ld      a,(hl)
                out     (WIN1_PORT),a
                pop     hl
                add     hl,hl
                add     hl,hl
                res     7,h
                set     6,h
                ret

MapNextCluster: ld      hl,(MapCluster+2)
                ld      de,(MapCluster)
                ld      a,(MapFatType)
                cp      12
                jr      z,.fat12
                sla     e
                rl      d
                rl      l
                rl      h
                cp      16
                jr      z,.offset
                sla     e
                rl      d
                rl      l
                rl      h
                jr      .offset
.fat12:         srl     h
                rr      l
                rr      d
                rr      e
                ld      ix,MapCluster
                call    MapAdd
.offset:        ld      a,d
                and     1
                ld      (MapOffset+1),a
                ld      a,e
                ld      (MapOffset),a
                ld      b,9
.shift:         srl     h
                rr      l
                rr      d
                rr      e
                djnz    .shift
                push    hl
                push    de
                ld      ix,MapFatSize
                call    MapSubtract
                pop     de
                pop     hl
                ccf
                ret     c
                ld      ix,MapFatStart
                call    MapAdd
                ret     c
                ld      (MapFatSector),de
                ld      (MapFatSector+2),hl
                call    MapRead
                ret     c
                ld      hl,(MapOffset)
                ld      de,Buffer
                add     hl,de
                ld      e,(hl)
                inc     hl
                ld      d,(hl)
                ld      a,(MapFatType)
                cp      12
                jr      z,.decode12
                cp      16
                ld      bc,0
                jr      z,.store
                inc     hl
                ld      c,(hl)
                inc     hl
                ld      a,(hl)
                and     15
                ld      b,a
.store:         ld      (MapCluster),de
                ld      (MapCluster+2),bc
                or      a
                ret
.decode12:      ld      hl,(MapOffset)
                inc     hl
                bit     1,h                      ; offset was 511
                jr      z,.packed
                ld      a,e
                ld      (MapPacked),a
                ld      de,(MapFatSector)
                ld      hl,(MapFatSector+2)
                inc     de
                ld      a,d
                or      e
                jr      nz,.readNext
                inc     hl
.readNext:      push    hl
                push    de
                ld      ix,MapFatStart
                call    MapSubtract
                ld      ix,MapFatSize
                call    MapSubtract
                pop     de
                pop     hl
                ccf
                ret     c
                call    MapRead
                ret     c
                ld      a,(MapPacked)
                ld      e,a
                ld      a,(Buffer)
                ld      d,a
.packed:        ld      a,(MapCluster)
                and     1
                jr      z,.even
                REPT 4
                srl     d
                rr      e
                ENDR
.even:          ld      a,d
                and     15
                ld      d,a
                ld      bc,0
                jr      .store

; Mapped BIOS iterator. Advance by the previous chunk, then load cluster.
MapBegin:       in      a,(WIN1_PORT)
                ld      (MapSavedWin),a
                xor     a
                ld      (MapOffsetInCluster),a
                ld      hl,0
                ld      (MapIndex),hl
                ret
MapChunk:       call    MapPointer
                ld      e,(hl)
                inc     hl
                ld      d,(hl)
                inc     hl
                ld      c,(hl)
                inc     hl
                ld      b,(hl)
                ld      a,(MapOffsetInCluster)
                ld      l,a
                ld      h,0
                add     hl,de
                ld      (CurLBA),hl
                ld      h,b
                ld      l,c
                jr      nc,.high
                inc     hl
.high:          ld      de,(CurLBA)
                ld      ix,PartStart
                call    MapAdd
                ld      (CurLBA),de
                ld      (CurLBA+2),hl
                ld      a,(MapOffsetInCluster)
                ld      b,a
                ld      a,(MapSpc)
                sub     b
                ld      b,a
                ld      a,(BiosBlock)
                cp      b
                jr      nc,.chosen
                ld      b,a
.chosen:        ret
MapAdvance:     ld      a,(MapOffsetInCluster)
                add     a,b
                ld      c,a
                ld      a,(MapSpc)
                cp      c
                ld      a,c
                jr      nz,.save
                ld      hl,(MapIndex)
                inc     hl
                ld      (MapIndex),hl
                xor     a
.save:          ld      (MapOffsetInCluster),a
                ret
MapEnd:         ld      a,(MapSavedWin)
                out     (WIN1_PORT),a
                ret
MapRun:         ld      a,(MapPaired)
                or      a
                ret     nz
                ld      a,(MapValid)
                or      a
                ret     z
                inc     a
                ld      (MapMode),a
                ld      hl,MapTitleStr
                call    SeriesText
                ld      ix,AtaSizeTable
                ld      b,5
.loop:          push    bc
                push    ix
                ld      l,(ix+0)
                ld      h,(ix+1)
                ld      e,(ix+2)
                call    TestBiosRead
                pop     ix
                pop     bc
                jr      c,.failed
                ld      de,3
                add     ix,de
                djnz    .loop
                xor     a
                ld      (MapMode),a
                ret
.failed:        push    af
                call    MapEnd
                pop     af
                ret
MapSkipStr:     db "File/BIOS pair skipped (map stage "
.stage:         db "00).",13,10
                db "1=file info, 2=volume metadata, 3=memory, 4=cluster chain",13,10,0
MapStage:       db 0
MapTitleStr:    db "BIOS reading mapped test file",13,10,0
MapDta:        ds 44
MapValid:      db 0
MapMode:       db 0
MapMem:        db 0
MapSavedWin:   db 0
MapPages:      ds 4
MapIndex:      dw 0
MapRemaining:  dw 0
MapSpc:        db 0
MapFatCount:   db 0
MapFatType:    db 0
MapFlags:      dw 0
MapVersion:    dw 0
MapFatStart:   dd 0
MapFatSize:    dd 0
MapDataStart:  dd 0
MapRootSectors: dd 0
MapTotal:      dd 0
MapClusters:   dd 0
MapCluster:    dd 0
MapTwo:        dd 2
MapOffset:     dw 0
MapPacked:     db 0
MapFatSector:  dd 0
MapOffsetInCluster: db 0

MapFat16Size:   dw 0

MapOne:         dd 1
