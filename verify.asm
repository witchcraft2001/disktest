; Pattern: word at sector byte offset 2*i = logical_sector XOR i.
; Covers every byte, distinguishes 256-byte half swaps and sector order.
FillPattern:    ld      hl,Buffer
                ld      de,(PatternSector)
                ld      b,8
.sector:        ld      c,0
.word:          ld      a,e
                xor     c
                ld      (hl),a
                inc     hl
                ld      (hl),d
                inc     hl
                inc     c
                jr      nz,.word
                inc     de
                djnz    .sector
                ld      (PatternSector),de
                ret
VerifyInit:     xor     a
                ld      (VerifyProgressPage),a
                ld      hl,0
                ld      (VerifySector),hl
                dec     hl
                ld      (VerifyCrc),hl
                ld      (VerifyCrc+2),hl
                ret
; A = sectors just transferred. Preserve BC for the caller.
VerifyBlock:    push    bc
                ld      b,a
                ld      a,(VerifyPass)
                or      a
                jr      z,.ok
                ld      a,b
                ld      (VerifyBlockCount),a
                ld      a,(TargetSram)
                or      a
                jr      z,.buffer
                call    VerifyProgress          ; each sector already hashed in SRAM
                jp      .ok
.buffer:        ld      hl,Buffer
                ld      a,(VerifyFile)
                or      a
                jr      z,.crc
                ld      de,(VerifySector)
.sector:        ld      c,0
.word:          ld      a,e
                xor     c
                cp      (hl)
                jr      nz,.bad
                inc     hl
                ld      a,d
                cp      (hl)
                jr      nz,.bad
                inc     hl
                inc     c
                jr      nz,.word
                inc     de
                djnz    .sector
                ld      (VerifySector),de
.ok:            pop     bc
                or      a
                ret
.bad:           pop     bc
                ld      hl,VerifyErrorStr
                call    SeriesText
                ld      a,2
                scf
                ret
.crc:           call    VerifyCrcBlock
                call    VerifyProgress
                jp      .ok
; HL = buffer, B = sectors. Pure CRC update, no DSS; CACHE may be enabled.
VerifyCrcBlock: ld      c,0
                sla     b                       ; B*256 bytes
.byte:          ld      a,(VerifyCrc)
                xor     (hl)
                push    hl
                ld      l,a
                ld      h,0
                add     hl,hl
                add     hl,hl
                ld      de,Crc32Table
                add     hl,de
                ; crc = (crc >> 8) XOR table[(crc XOR byte) & 255]
                ld      a,(VerifyCrc+1)
                xor     (hl)
                ld      (VerifyCrc),a
                inc     hl
                ld      a,(VerifyCrc+2)
                xor     (hl)
                ld      (VerifyCrc+1),a
                inc     hl
                ld      a,(VerifyCrc+3)
                xor     (hl)
                ld      (VerifyCrc+2),a
                inc     hl
                ld      a,(hl)
                ld      (VerifyCrc+3),a
                pop     hl
                inc     hl
                dec     c
                jr      nz,.byte
                djnz    .byte
                ret
; Untimed progress only: one dot per 128 KiB, with CACHE off.
VerifyProgress: ld      a,(VerifyBlockCount)
                ld      e,a
                ld      d,0
                ld      hl,(VerifySector)
                add     hl,de
                ld      (VerifySector),hl
                ld      a,(VerifyProgressPage)
                cp      h
                ret     z
                ld      a,h
                ld      (VerifyProgressPage),a
                ld      hl,VerifyDotStr
                jp      SeriesText
VerifyDotStr:   db ".",0
VerifyBlockCount: db 0
VerifyProgressPage: db 0
Crc32Table:
                include "crc32_table.asm"

VerifyFinish:   ld      a,(VerifyFile)
                or      a
                jr      nz,.ok
                ld      a,(ReferenceValid)
                or      a
                jr      nz,.compare
                ld      hl,VerifyCrc
                ld      de,ReferenceCrc
                ld      bc,4
                ldir
                ld      a,1
                ld      (ReferenceValid),a
                ld      hl,ReferenceStr
                call    VerifyText
                or      a
                ret
.compare:       ld      hl,VerifyCrc
                ld      de,ReferenceCrc
                ld      b,4
.loop:          ld      a,(de)
                cp      (hl)
                jr      nz,.bad
                inc     hl
                inc     de
                djnz    .loop
.ok:            ld      hl,VerifiedStr
                call    VerifyText
                or      a
                ret
.bad:           ld      hl,VerifyErrorStr
                call    SeriesText
                ld      a,2
                scf
                ret
VerifiedStr:    db "full warmup verified",13,10,0
VerifyErrorStr: db "DATA MISMATCH (full untimed pass)",13,10,0
PatternSector:  dw 0
VerifySector:   dw 0
VerifyCrc:      ds 4
ReferenceCrc:   ds 4
ReferenceValid: db 0
VerifyFile:     db 0

ReferenceStr:   db "Full warmup CRC32 reference recorded (not independently verified)",13,10,0

VerifyText:     ld      a,(VerboseOutput)
                or      a
                ret     z
                jp      SeriesText
