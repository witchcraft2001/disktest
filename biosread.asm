;[]-------------------------------------------------------------------------[]
; Raw sector read test: the partition the work drive maps to is read from its
; first sector straight through BIOS DrvRead, bypassing DSS and the FAT layer.
;[]-------------------------------------------------------------------------[]
;Resolve work drive -> BIOS device + partition start, clamp the test length.
;CF = 1: not an IDE drive (message printed), test skipped
BiosTestPrepare:
                ld      a,(WorkDriveNumber)
                ld      bc,DssDrv.GetParams
                call    DssDrvCall
                jr      c,.unsupported
                ld      a,b
                cp      4                       ; 512-byte sectors only
                jr      nz,.unsupported
                ex      af,af'
                ld      (PhysDrive),a
                and     0xF0
                cp      0x80                    ; IDE device class
                jr      nz,.unsupported
                push    hl
                ld      hl,(FileBlocks)
                ld      (BiosSectors),hl
                pop     hl
                ld      a,h                     ; HL:DE = partition size in sectors
                or      l
                jr      nz,.sizeok              ; > 65535 sectors, no clamp needed
                ld      hl,(FileBlocks)
                and     a
                sbc     hl,de
                jr      c,.sizeok
                ld      (BiosSectors),de
.sizeok:        ld      a,(WorkDriveNumber)
                ld      bc,DssDrv.GetMoreParams
                call    DssDrvCall
                jr      c,.unsupported
                ld      (PartStart),de
                ld      (PartStart+2),hl
                and     a
                ret
.unsupported:   ld      hl,BiosUnsupportedStr
                ld      c,Dss.PChars
                rst     0x10
                scf
                ret

;A = DSS drive, BC = function; IY preserved
;CF is cleared before the call: GetMoreParams returns without ever setting
;it explicitly, and INC/DEC/BIT (used by the GenIOCTL dispatch chain) leave
;carry untouched, so an unrelated CF=1 left over from earlier code would
;otherwise be read back as a bogus error.
DssDrvCall:     push    iy
                and     a
                rst     ToDssDrv
                pop     iy
                ret

;HL = block size label (4 chars), E = sectors per BIOS call (1..32)
;CF = 1: A = 0 canceled, A = 2 BIOS error (already printed)
TestBiosRead:   push    de
                ld      de,BiosReadStr.size
                ld      bc,4
                ldir
                ld      hl,BiosReadStr
                ld      c,Dss.PChars
                rst     0x10
                pop     de
                ld      a,e
                ld      (BiosBlock),a
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
                call    TimerStart
.loop:          ld      hl,(Remaining)
                ld      a,h
                or      l
                jr      z,.done
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
                push    bc
                ld      a,(PhysDrive)
                ld      hl,(CurLBA+2)
                ld      ix,(CurLBA)
                ld      de,Buffer
                ld      c,Bios.DrvRead
                push    iy
                rst     ToBIOS
                pop     iy
                jr      c,.bioserr
                pop     bc
                call    TakeResultSum           ; first command only
                ld      hl,(CurLBA)             ; next sector, computed here so it does
                ld      e,b                     ; not depend on the BIOS exit path
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
                jr      .loop
.done:          ld      hl,(BiosSectors)
                call    PrintResult
                and     a
                ret
.break:         xor     a
                scf
                ret
.bioserr:       pop     bc
                ld      de,BiosErrorStr.code
                call    PutHex2
                ld      hl,BiosErrorStr
                ld      c,Dss.PChars
                rst     0x10
                ld      a,2
                scf
                ret

;Write A as two hex digits at (DE); DE advances by 2
PutHex2:        push    af
                rrca
                rrca
                rrca
                rrca
                call    .digit
                pop     af
.digit:         and     0x0F
                add     a,0x90
                daa
                adc     a,0x40
                daa
                ld      (de),a
                inc     de
                ret

BiosReadStr:    db      "Test: BIOS read, block "
.size:          db      "512B ... ", 0x00
BiosUnsupportedStr:
                db      "BIOS/ATA sector read tests: IDE drives only, skipped.", 0x0D, 0x0A, 0x00
BiosErrorStr:   db      "BIOS error #"
.code:          db      "00", 0x0D, 0x0A, 0x00

PhysDrive:      db      0                       ;BIOS device number (0x80..)
PartStart:      dw      0, 0                    ;partition start LBA
BiosSectors:    dw      0                       ;sectors per test pass
CurLBA:         dw      0, 0
Remaining:      dw      0
BiosBlock:      db      0                       ;sectors per BIOS call
