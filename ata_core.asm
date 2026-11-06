;Select channel and device from PhysDrive (0x80..: bit0 slave, bit1 secondary)
;and wait until it is ready
Select:      ld      a,(PhysDrive)
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
                jp      WaitReady

;A = command, B = sector count; LBA taken from CurLBA. CF = 1 on error
Command:     ld      (AtaCmd),a
                ld      hl,(CurLBA+2)
                ld      a,h
                and     0xF0
                jp      nz,RangeError
                ld      hl,(CurLBA)
                ld      e,b
                ld      d,0
                dec     de
                add     hl,de
                ld      hl,(CurLBA+2)
                ld      de,0
                adc     hl,de
                jp      c,RangeError
                ld      a,h
                and     0xF0
                jp      nz,RangeError
                ld      a,b
                or      a
                jp      z,RangeError
                ld      a,b
                ld      (AtaCount),a
                call    WaitReady
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
WaitReady:   ld      de,256*(IdeSt.BSY+IdeSt.DF+IdeSt.DRQ+IdeSt.RDY)+IdeSt.RDY
                jr      Wait
WaitNotBusy: ld      de,256*IdeSt.BSY
                jr      Wait
;After a non-data command: RDY, or ERR if the device rejected it
WaitDone:    ld      de,256*(IdeSt.BSY+IdeSt.DF+IdeSt.DRQ+IdeSt.RDY+IdeSt.ERR)+IdeSt.RDY
                jr      Wait
;the device needs up to 400 ns after the last word of a block to drop DRQ /
;raise BSY: a dummy status read first, so a stale DRQ is never taken for the
;next block
WaitDrq:     ld      bc,Ide.ReadStatus
                in      a,(c)
                ld      de,256*(IdeSt.BSY+IdeSt.DF+IdeSt.DRQ+IdeSt.ERR)+IdeSt.DRQ
Wait:        push    hl
                push    de
                call    ReadSecond
                ld      (AtaWaitSecond),a
                ld      a,10
                ld      (AtaWaitSeconds),a
                pop     de
                ld      b,255                   ; watchdog only if RTC stops
.outer:         push    bc
                ld      hl,0
                ld      bc,Ide.ReadStatus
.loop:          in      a,(c)
                bit     7,a                     ; BSY
                jr      nz,.next
                and     d
                cp      e
                jr      z,.ok
                and     IdeSt.DF+IdeSt.ERR
                jr      nz,.error
.next:          push    bc
                call    ReadSecond
                ld      c,a
                ld      a,(AtaWaitSecond)
                cp      c
                jr      z,.sameSecond
                ld      a,c
                ld      (AtaWaitSecond),a
                ld      a,(AtaWaitSeconds)
                dec     a
                ld      (AtaWaitSeconds),a
                jr      nz,.sameSecond
                pop     bc
                jr      .error
.sameSecond:    pop     bc
                dec     hl
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
ReadSector:  ld      bc,Ide.ReadData
                IFDEF ATA_FULL_UNROLL
                DUP 512
                ini
                EDUP
                ret
                ELSE
.loop1:         DUP     16
                ini
                EDUP
                jp      nz,.loop1
.loop2:         DUP     16
                ini
                EDUP
                jp      nz,.loop2
                ret
                ENDIF

ReadSecond:     push    bc
                di
                xor     a
                ld      bc,CMOS_AWR
                out     (c),a
                ld      bc,CMOS_DRD
                in      a,(c)
                pop     bc
                ei
                ret
RangeError:     ld      a,0xFF
                ld      (AtaStatus),a
                ld      (AtaError),a
                scf
                ret

; Entire command/PIO exchange; never call DSS with CACHE enabled.
; On DRQ+ERR/DF consume the advertised block before reporting failure.
Transfer:       call    Command
                ret     c
                ld      hl,(AtaBuffer)
.next:          call    WaitDrq
                jr      nc,.block
                ld      a,(AtaStatus)
                bit     7,a
                jr      nz,.failed
                bit     3,a
                jr      z,.failed
                ld      a,1
                ld      (AtaTransferError),a
.block:         ld      b,1
                ld      a,(AtaMode)
                or      a
                jr      z,.count
                ld      a,(AtaMultiN)
                ld      b,a
                ld      a,(AtaLeft)
                cp      b
                jr      nc,.count
                ld      b,a
.count:         ld      a,(AtaLeft)
                sub     b
                ld      (AtaLeft),a
.sector:        push    bc
                call    ReadSector
                ld      a,(TargetSram)
                or      a
                jr      z,.receiverDone
                ld      a,(VerifyPass)
                or      a
                call    nz,VerifySramSector
                ld      hl,SramIoBuffer
.receiverDone:  pop     bc
                djnz    .sector
                ld      a,(AtaLeft)
                or      a
                jr      nz,.next
                call    WaitDone
                ret     c
                ld      a,(AtaTransferError)
                or      a
                ret     z
.failed:        scf
                ret
