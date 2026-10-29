;[]-------------------------------------------------------------------------[]
; Direct ATA port test stand: READ SECTORS (#20) against READ MULTIPLE (#C4),
; bypassing the BIOS. The port protocol is the one sprinter_bios uses
; (ATA_DRV.ASM RW_ATA_SECTORs/PRESET, shared.asm SELECT_DRIVE): select the
; channel through port #BC, write the LBA registers, issue the command, wait
; for DRQ and move 512 bytes per sector with INI from port #0050.
; READ SECTORS raises DRQ once per sector, READ MULTIPLE once per block of
; AtaMultiN sectors (SET MULTIPLE MODE), which is the difference being measured.
; The transfer loop runs from the program page (DRAM) while the BIOS one runs
; from ROM, so in turbo the absolute numbers are above the BIOS test's; compare
; SECTORS against MULTI within this stand, not against the BIOS test.
; The device control register (nIEN/SRST) is left alone, like the BIOS does.
;[]-------------------------------------------------------------------------[]
ATA_SECTORS     equ     0
ATA_MULTI       equ     1
ATA_TITLE_LEN   equ     23                      ;"Test: ATA read,  block "

;Run the whole stand. CF = 1: A = 0 canceled, A = 2 error already printed
AtaTests:       call    AtaIdentify
                ret     c
                ld      a,(AtaLba)
                and     a
                ret     z                       ; CHS-only device, message printed
                ld      c,ATA_SECTORS
                call    AtaRunSet
                ret     c
                ld      a,(AtaMultiMax)
                and     a
                ret     z                       ; READ MULTIPLE not supported
                ld      a,(AtaMultiN)
                call    AtaSetMultiple
                jr      c,.nomulti
                ld      c,ATA_MULTI
                call    AtaRunSet
                push    af
                call    AtaRestoreMultiple
                pop     af
                ret
.nomulti:       ld      hl,AtaSetMultiFailStr
                ld      c,Dss.PChars
                rst     0x10
                and     a
                ret

;C = mode; runs the five block sizes
AtaRunSet:      ld      ix,AtaSizeTable
                ld      b,5
.loop:          push    bc
                push    ix
                ld      l,(ix+0)
                ld      h,(ix+1)
                ld      e,(ix+2)
                call    TestAtaRead
                pop     ix
                pop     bc
                ret     c
                ld      de,3
                add     ix,de
                djnz    .loop
                and     a
                ret
AtaSizeTable:   dw      TestSize512BStr
                db      1
                dw      TestSize2KBStr
                db      4
                dw      TestSize4KBStr
                db      8
                dw      TestSize8KBStr
                db      16
                dw      TestSize16KBStr
                db      32

;HL = block size label (4 chars), E = sectors per command (1..32), C = mode
;CF = 1: A = 0 canceled, A = 2 ATA error (already printed)
TestAtaRead:    ld      a,e
                ld      (BiosBlock),a
                ld      a,c
                ld      (AtaMode),a
                ld      de,AtaReadStr.size
                and     a
                jr      z,.copy
                ld      de,AtaMultiStr.size
.copy:          push    de
                ld      bc,4
                ldir
                pop     hl
                ld      bc,-ATA_TITLE_LEN
                add     hl,bc
                ld      c,Dss.PChars
                rst     0x10
                ld      hl,(PartStart)
                ld      (CurLBA),hl
                ld      hl,(PartStart+2)
                ld      (CurLBA+2),hl
                ld      hl,(BiosSectors)
                ld      (Remaining),hl
                xor     a
                ld      (KeyCount),a
                inc     a
                ld      (SumPending),a
                call    AtaSelect
                jp      c,.ataerr
                call    TimerStart
.loop:          ld      hl,(Remaining)
                ld      a,h
                or      l
                jp      z,.done
                ld      a,(BiosBlock)
                ld      b,a
                ld      a,h                     ; B = min(block, remaining)
                or      a
                jr      nz,.count
                ld      a,l
                cp      b
                jr      nc,.count
                ld      b,l
.count:         ld      a,l
                sub     b
                ld      l,a
                jr      nc,.nb
                dec     h
.nb:            ld      (Remaining),hl
                ld      a,b
                ld      (AtaCmdCount),a
                ld      (AtaLeft),a
                ld      a,(AtaMode)
                and     a
                ld      a,IdeCmd.ReadSectors
                jr      z,.cmd
                ld      a,IdeCmd.ReadMultiple
.cmd:           call    AtaCommand              ; B = count
                jr      c,.ataerr
                ld      hl,Buffer
.drq:           call    AtaWaitDrq
                jr      c,.ataerr
                ld      b,1                     ; READ SECTORS: one sector per DRQ
                ld      a,(AtaMode)
                and     a
                jr      z,.block
                ld      a,(AtaMultiN)           ; READ MULTIPLE: a block per DRQ
                ld      b,a
                ld      a,(AtaLeft)
                cp      b
                jr      nc,.block
                ld      b,a                     ; last, shorter block
.block:         ld      a,(AtaLeft)
                sub     b
                ld      (AtaLeft),a
.sector:        push    bc
                call    AtaReadSector           ; HL += 512, no status polling
                pop     bc
                djnz    .sector
                ld      a,(AtaLeft)
                and     a
                jr      nz,.drq
                call    TakeResultSum           ; first command only
                ld      a,(AtaCmdCount)
                ld      b,a
                ld      hl,(CurLBA)             ; next sector
                ld      e,b
                ld      d,0
                add     hl,de
                ld      (CurLBA),hl
                jr      nc,.lbaok
                ld      hl,(CurLBA+2)
                inc     hl
                ld      (CurLBA+2),hl
.lbaok:         ld      a,b                     ; sectors * 2 = bytes / 256
                add     a,a
                call    PollKey
                jr      nz,.break
                jp      .loop
.done:          ld      hl,(BiosSectors)
                call    PrintResult
                and     a
                ret
.break:         xor     a
                scf
                ret
.ataerr:        ld      a,(AtaStatus)
                ld      de,AtaErrorStr.status
                call    PutHex2
                ld      a,(AtaError)
                ld      de,AtaErrorStr.error
                call    PutHex2
                ld      hl,AtaErrorStr
                ld      c,Dss.PChars
                rst     0x10
                ld      a,2
                scf
                ret

;IDENTIFY DEVICE into Buffer: model, max sectors per DRQ block (word 47) and
;the current multiple setting (word 59). Prints them. CF = 1: error printed
AtaIdentify:    call    AtaSelect
                jp      c,.error
                ld      a,IdeCmd.Identify
                ld      bc,Ide.WriteCommand
                out     (c),a
                call    AtaWaitDrq
                jp      c,.error
                ld      hl,Buffer
                call    AtaReadSector
                ld      hl,Buffer+27*2          ; model: words 27..46, chars swapped
                ld      de,AtaModelStr
                ld      b,20
.model:         ld      c,(hl)
                inc     hl
                ld      a,(hl)
                inc     hl
                ld      (de),a
                inc     de
                ld      a,c
                ld      (de),a
                inc     de
                djnz    .model
                ld      hl,AtaModelStr+39       ; trim trailing spaces
                ld      b,40
.trim:          ld      a,(hl)
                cp      " "
                jr      nz,.trimmed
                ld      (hl),0
                dec     hl
                djnz    .trim
.trimmed:       ld      a,(Buffer+49*2+1)       ; word 49 bit 9: LBA supported
                and     0x02
                ld      (AtaLba),a
                ld      a,(Buffer+47*2)         ; max sectors per DRQ block
                ld      (AtaMultiMax),a
                ld      hl,(Buffer+59*2)        ; bit 8: valid, bits 0..7: current
                ld      (AtaMultiOld),hl
                cp      33
                jr      c,.fits
                ld      a,32                    ; 16 KiB buffer
.fits:          ld      (AtaMultiN),a
                ld      hl,AtaDeviceStr
                ld      c,Dss.PChars
                rst     0x10
                ld      hl,AtaModelStr
                ld      c,Dss.PChars
                rst     0x10
                ld      hl,EnterStr
                ld      c,Dss.PChars
                rst     0x10
                ld      a,(AtaLba)
                and     a
                ld      hl,AtaNoLbaStr
                jr      z,.print                ; the stand addresses in LBA only
                ld      a,(AtaMultiMax)
                and     a
                ld      hl,AtaNoMultiStr
                jr      z,.print
                ld      l,a
                ld      bc,AtaMultiInfoStr.max
                call    PRNUM
                ld      a,(AtaMultiN)
                ld      l,a
                ld      bc,AtaMultiInfoStr.n
                call    PRNUM
                ld      hl,AtaMultiInfoStr
.print:         ld      c,Dss.PChars
                rst     0x10
                and     a
                ret
.error:         ld      hl,AtaIdentifyFailStr
                ld      c,Dss.PChars
                rst     0x10
                jp      TestAtaRead.ataerr

;SET MULTIPLE MODE, A = sectors per block. CF = 1: rejected (ERR/abort)
AtaSetMultiple: push    af
                call    AtaWaitReady
                pop     bc                      ; B = block
                ret     c
                ld      a,b
                ld      bc,Ide.WriteCounter
                out     (c),a
                ld      a,IdeCmd.SetMultiple
                ld      bc,Ide.WriteCommand
                out     (c),a
                jp      AtaWaitDone

;Put the setting found by IDENTIFY back, if there was a valid one
AtaRestoreMultiple:
                ld      hl,(AtaMultiOld)
                bit     0,h
                ret     z
                ld      a,l
                and     a
                ret     z
                jp      AtaSetMultiple

;Select channel and device from PhysDrive (0x80..: bit0 slave, bit1 secondary)
;and wait until it is ready
AtaSelect:      ld      a,(PhysDrive)
                ld      e,a
                ld      a,Ide.Primary
                bit     1,e
                jr      z,.chan
                ld      a,Ide.Secondary
.chan:          out     (Ide.ChanelPort),a
                ld      a,Ide.DevHeadLBA
                bit     0,e
                jr      z,.dev
                or      0x10
.dev:           ld      (AtaDevHead),a
                ld      bc,Ide.WriteDevHead
                out     (c),a
                jp      AtaWaitReady

;A = command, B = sector count; LBA taken from CurLBA. CF = 1 on error
AtaCommand:     ld      (AtaCmd),a
                ld      a,b
                ld      (AtaCount),a
                call    AtaWaitReady
                ret     c
                ld      a,(AtaCount)
                ld      bc,Ide.WriteCounter
                out     (c),a
                ld      hl,(CurLBA)
                ld      bc,Ide.WriteSector
                out     (c),l                   ; LBA 0..7
                inc     c                       ; Ide.WriteCylLow
                out     (c),h                   ; LBA 8..15
                ld      hl,(CurLBA+2)
                inc     c                       ; Ide.WriteCylHigh
                out     (c),l                   ; LBA 16..23
                ld      a,h
                and     0x0F
                ld      hl,AtaDevHead
                or      (hl)                    ; device | LBA 24..27
                ld      bc,Ide.WriteDevHead
                out     (c),a
                ld      a,(AtaCmd)
                ld      bc,Ide.WriteCommand
                out     (c),a
                and     a
                ret

;Poll Status until (S & D) == E; while BSY is set the other bits are not valid.
;With ERR in the mask D an error ends the wait. CF = 1 on that error or on a
;timeout, AtaStatus/AtaError filled. HL preserved; AF, BC, DE destroyed.
;Before a command only RDY counts: ERR may be left over from the previous
;command (DSS's, for example) and is cleared by the next one - the BIOS does
;not look at it there either.
AtaWaitReady:   ld      de,256*(IdeSt.BSY+IdeSt.RDY)+IdeSt.RDY
                jr      AtaWait
;After a non-data command: RDY, or ERR if the device rejected it
AtaWaitDone:    ld      de,256*(IdeSt.BSY+IdeSt.RDY+IdeSt.ERR)+IdeSt.RDY
                jr      AtaWait
;the device needs up to 400 ns after the last word of a block to drop DRQ /
;raise BSY: a dummy status read first, so a stale DRQ is never taken for the
;next block
AtaWaitDrq:     ld      bc,Ide.ReadStatus
                in      a,(c)
                ld      de,256*(IdeSt.BSY+IdeSt.DRQ+IdeSt.ERR)+IdeSt.DRQ
AtaWait:        push    hl
                ld      b,8                     ; 8 * 65536 polls
.outer:         push    bc
                ld      hl,0
                ld      bc,Ide.ReadStatus
.loop:          in      a,(c)
                bit     7,a                     ; BSY
                jr      nz,.next
                and     d
                cp      e
                jr      z,.ok
                rra                             ; ERR, only left in A when in the mask
                jr      c,.error
.next:          dec     hl
                ld      a,h
                or      l
                jr      nz,.loop
                pop     bc
                djnz    .outer
                ld      bc,Ide.ReadStatus       ; timeout
                in      a,(c)
                jr      .fail
.error:         pop     bc
                ld      bc,Ide.ReadStatus       ; the full status for the report
                in      a,(c)
.fail:          ld      (AtaStatus),a
                ld      bc,Ide.ReadError
                in      a,(c)
                ld      (AtaError),a
                pop     hl
                scf
                ret
.ok:            pop     bc
                pop     hl
                and     a
                ret

;Read one 512-byte sector from the data port into (HL), HL += 512.
;The BIOS loop: B counts 256 -> 0 twice, the port's high byte is ignored
AtaReadSector:  ld      bc,Ide.ReadData
.loop1:         DUP     16
                ini
                EDUP
                jp      nz,.loop1
.loop2:         DUP     16
                ini
                EDUP
                jp      nz,.loop2
                ret

AtaReadStr:     db      "Test: ATA read,  block "
.size:          db      "512B ... ", 0x00
AtaMultiStr:    db      "Test: ATA multi, block "
.size:          db      "512B ... ", 0x00
AtaDeviceStr:   db      "ATA device: ", 0x00
AtaMultiInfoStr:
                db      "Multiple: max"
.max:           db      "000 sectors per DRQ, test uses"
.n:             db      "000", 0x0D, 0x0A, 0x00
AtaNoMultiStr:  db      "Multiple: not supported, READ MULTIPLE tests skipped", 0x0D, 0x0A, 0x00
AtaNoLbaStr:    db      "No LBA support, ATA tests skipped", 0x0D, 0x0A, 0x00
AtaSetMultiFailStr:
                db      "SET MULTIPLE MODE rejected, READ MULTIPLE tests skipped", 0x0D, 0x0A, 0x00
AtaIdentifyFailStr:
                db      "IDENTIFY DEVICE failed", 0x0D, 0x0A, 0x00
AtaErrorStr:    db      "ATA error: status="
.status:        db      "00 error="
.error:         db      "00", 0x0D, 0x0A, 0x00
AtaModelStr:    ds      40
                db      0

AtaDevHead:     db      0                       ;0xE0 master / 0xF0 slave
AtaStatus:      db      0
AtaError:       db      0
AtaMode:        db      0                       ;ATA_SECTORS / ATA_MULTI
AtaCmd:         db      0
AtaCount:       db      0
AtaCmdCount:    db      0                       ;sectors in the current command
AtaLeft:        db      0                       ;sectors still to read in it
AtaMultiMax:    db      0                       ;IDENTIFY word 47 low byte
AtaMultiN:      db      0                       ;block used by the MULTI tests
AtaMultiOld:    dw      0                       ;IDENTIFY word 59
AtaLba:         db      0                       ;IDENTIFY word 49 bit 9 (nonzero: LBA)
