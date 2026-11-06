;[]-------------------------------------------------------------------------[]
; Direct ATA port test stand: READ SECTORS (#20) against READ MULTIPLE (#C4),
; bypassing the BIOS. The port protocol is the one sprinter_bios uses
; (ATA_DRV.ASM RW_ATA_SECTORs/PRESET, shared.asm SELECT_DRIVE): select the
; channel through port #BC, write the LBA registers, issue the command, wait
; for DRQ and move 512 bytes per sector with INI from port #0050.
; READ SECTORS raises DRQ once per sector, READ MULTIPLE once per block of
; AtaMultiN sectors (SET MULTIPLE MODE), which is the difference being measured.
; The transfer loop runs from the program page (DRAM) while the BIOS one runs
; from ROM. The identical core can also run from SRAM for /C.
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
                ld      a,(AtaMultiOld+1)
                and     1
                jr      z,.nomulti
                ld      a,(AtaMultiN)
                call    AtaSetMultiple
                jr      c,.nomulti
                ld      c,ATA_MULTI
                call    AtaRunSet
                push    af
                call    AtaRestoreMultiple
                jr      c,.restoreFailed
                pop     af
                ret
.restoreFailed: pop     af
                ld      a,2
                scf
                ret
.nomulti:       call    AtaRestoreMultiple
                ret     c
                ld      hl,AtaSetMultiFailStr
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
AtaReadPass:    call    SeriesLoad
                ld      a,e
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
                call    SeriesTitle
                ld      hl,(PartStart)
                ld      (CurLBA),hl
                ld      hl,(PartStart+2)
                ld      (CurLBA+2),hl
                ld      hl,(BiosSectors)
                ld      (Remaining),hl
                xor     a
                ld      (KeyCount),a
                ld      (VerifyFile),a
                call    VerifyInit
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
.cmd:           call    AtaTransfer
                jr      c,.ataerr
                ld      a,(AtaCmdCount)
                call    VerifyBlock
                ret     c
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
                jp      SeriesFinish
.break:         xor     a
                scf
                ret
.ataerr:        call    AtaRecover
                ld      a,(AtaStatus)
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
.error:         call    AtaRecover
                ld      hl,AtaIdentifyFailStr
                ld      c,Dss.PChars
                rst     0x10
                jp      AtaReadPass.ataerr

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

 ; Restore valid word 59, including 0100h (MULTIPLE disabled), then verify.
AtaRestoreMultiple:
                ld      hl,(AtaMultiOld)
                bit     0,h
                ret     z
                ld      a,l
                call    AtaSetMultiple
                jr      c,.failed
                ld      a,IdeCmd.Identify
                ld      bc,Ide.WriteCommand
                out     (c),a
                call    AtaWaitDrq
                jr      c,.failed
                ld      hl,Buffer
                call    AtaReadSector
                ld      hl,(Buffer+118)
                ld      de,(AtaMultiOld)
                ld      a,h
                and     1
                cp      1
                jr      nz,.failed
                ld      a,l
                cp      e
                ret     z
.failed:        call    AtaRecover
                ld      hl,AtaRestoreFailStr
                ld      c,Dss.PChars
                rst     0x10
                ld      a,2
                scf
                ret

AtaSelect:      push    af
                ld      a,(UseCache)
                or      a
                jr      nz,.cache
                pop     af
                jp      Dram.Select
.cache:         di
                in      a,(0xFB)
                ld      a,1
                ld      (CacheActive),a
                pop     af
                ei
                call    Sram.Select
                di
                push    af
                in      a,(0x7B)
                xor     a
                ld      (CacheActive),a
                pop     af
                ei
                ret
AtaCommand:     jp      Dram.Command
AtaWaitReady:   jp      Dram.WaitReady
AtaWaitDone:    jp      Dram.WaitDone
AtaWaitDrq:     jp      Dram.WaitDrq
AtaReadSector:  jp      Dram.ReadSector

AtaTransfer:    push    af
                xor     a
                ld      (AtaTransferError),a
                ld      a,(UseCache)
                or      a
                jr      nz,.cache
                pop     af
                jp      Dram.Transfer
.cache:         di
                in      a,(0xFB)
                ld      a,1
                ld      (CacheActive),a
                pop     af
                ei
                call    Sram.Transfer
                di
                push    af
                in      a,(0x7B)
                xor     a
                ld      (CacheActive),a
                pop     af
                ei
                ret

                MODULE Dram
                include "ata_core.asm"
                ENDMODULE
SramImage:
                DISP 0x0200
                MODULE Sram
                include "ata_core.asm"
SramEnd:
                ENDMODULE
                ENT
SramSize        equ Sram.SramEnd-0x0200
                ASSERT SramSize < 0x3E00

AtaRestoreFailStr: db "MULTIPLE restore/verify failed; device state uncertain",13,10,0
AtaWaitSecond:  db 0
AtaWaitSeconds: db 0
AtaTransferError: db 0

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

; Finish a failed read before any DSS call. ERR/DF without BSY/DRQ is idle.
; An unresponsive controller cannot safely be returned to DOS: restore SRAM,
; stop our timer, and signal a fatal error with a red border until reset.
AtaRecover:     ld      a,(AtaStatus)
                push    af
                ld      a,(AtaError)
                push    af
                ld      b,0                     ; no command has >256 sectors
.loop:          push    bc
                call    Dram.WaitNotBusy
                ld      bc,Ide.ReadStatus
                in      a,(c)
                pop     bc
                bit     7,a
                jr      nz,.fatal
                bit     3,a
                jr      z,.idle
                push    bc
                ld      hl,Buffer
                call    AtaReadSector
                pop     bc
                djnz    .loop
.fatal:         call    CacheDeinit
                call    TimerDeinit
                di
                ld      a,2
                out     (0xFE),a
.halt:          halt
                jr      .halt
.idle:          pop     af
                ld      (AtaError),a
                pop     af
                ld      (AtaStatus),a
                ret
