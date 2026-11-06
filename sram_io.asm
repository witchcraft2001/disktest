; 512-byte receive ring in WIN0 SRAM. Command sizes remain 1..32 sectors.
; Backup lives in a DSS page, never in the transfer buffer or WIN0.
SramIoBuffer equ 0x3E00
                ASSERT 0x0200+SramSize <= SramIoBuffer
                ASSERT SramIoBuffer+512 <= 0x4000
SramIoInit:     ld      a,(SramIoReady)
                or      a
                ret     nz
                ld      b,1
                ld      c,Dss.GetMem
                rst     0x10
                jp      c,.skip
                ld      b,0
                ld      c,Dss.SetWin1
                rst     0x10
                jp      c,.skip
                ; SetWin1 returns the previous physical WIN1 page in A.
                ld      (SramIoSavedWin),a
                in      a,(WIN1_PORT)
                ld      (SramIoBackupPage),a
                di
                ld      a,(SramIoBuffer)
                ld      (SramIoNormal),a
                in      a,(0xFB)
                ld      hl,SramIoBuffer
                ld      de,0x4000
                ld      bc,512
                ldir
                ld      a,(SramIoBuffer)
                cpl
                ld      (SramIoBuffer),a
                ld      b,a
                ld      a,(SramIoBuffer)
                cp      b
                jr      nz,.badRing
                in      a,(0x7B)
                ld      a,(SramIoNormal)
                ld      b,a
                ld      a,(SramIoBuffer)
                cp      b
                jr      nz,.badRing
                in      a,(0xFB)
                ld      a,(0x4000)
                ld      (SramIoBuffer),a
                in      a,(0x7B)
                ld      a,(SramIoSavedWin)
                out     (WIN1_PORT),a
                ld      a,1
                ld      (SramIoReady),a
                ei
                or      a
                ret
.badRing:       in      a,(0xFB)
                ld      hl,0x4000
                ld      de,SramIoBuffer
                ld      bc,512
                ldir
                in      a,(0x7B)
                ld      a,(SramIoNormal)
                ld      (SramIoBuffer),a
                ld      a,(SramIoSavedWin)
                out     (WIN1_PORT),a
                ei
.skip:          ld      hl,SramIoSkipStr
                call    SeriesText
                scf
                ret
; No DSS here: also called by ATA fatal recovery.
SramIoDeinit:   ld      a,(SramIoReady)
                or      a
                ret     z
                di
                in      a,(WIN1_PORT)
                ld      (SramIoSavedWin),a
                ld      a,(SramIoBackupPage)
                out     (WIN1_PORT),a
                in      a,(0xFB)
                ld      hl,0x4000
                ld      de,SramIoBuffer
                ld      bc,512
                ldir
                in      a,(0x7B)
                ld      a,(SramIoSavedWin)
                out     (WIN1_PORT),a
                xor     a
                ld      (SramIoReady),a
                ld      (TargetSram),a
                ld      hl,Buffer
                ld      (AtaBuffer),hl
                ei
                ret
; Called with CACHE on in untimed warmup only. No DSS or progress output.
VerifySramSector:
                ld      hl,SramIoBuffer
                ld      b,1
                jp      VerifyCrcBlock
TargetSram:     db 0
AtaBuffer:      dw Buffer
SramIoReady:    db 0
SramIoBackupPage: db 0
SramIoSavedWin: db 0
SramIoSkipStr:  db "SS skipped: SRAM ring/backup unavailable",13,10,0

SramIoNormal:  db 0
