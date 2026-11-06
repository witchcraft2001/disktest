; WIN0 SRAM, current ROM_RG bank. All setup/cleanup runs from WIN2.
CacheInit:      ld      a,(CacheReady)
                or      a
                ret     nz
                ld      b,1
                ld      c,Dss.GetMem
                rst     0x10
                jp      c,.noBackup
                ld      b,0
                ld      c,Dss.SetWin1
                rst     0x10
                jp      c,.noBackup
                ld      (CacheSavedWin),a
                in      a,(WIN1_PORT)
                ld      (CacheBackupPage),a
                di
                ld      a,(0x0200)
                ld      (CacheNormal),a
                in      a,(0xFB)
                ld      a,(0x0200)
                ld      (CacheOriginal),a
                ld      a,(CacheNormal)
                cpl
                ld      (0x0200),a
                ld      b,a
                ld      a,(0x0200)
                cp      b
                jr      nz,.bad
                in      a,(0x7B)
                ld      a,(CacheNormal)
                ld      b,a
                ld      a,(0x0200)
                cp      b
                jr      nz,.bad
                in      a,(0xFB)
                ld      a,(CacheOriginal)
                ld      (0x0200),a
                ld      hl,0x0200
                ld      de,CacheBackup
                ld      bc,SramSize
                ldir
                ld      hl,SramImage
                ld      de,0x0200
                ld      bc,SramSize
                ldir
                ld      hl,SramImage
                ld      de,0x0200
                ld      bc,SramSize
.verify:        ld      a,(de)
                cp      (hl)
                jr      nz,.copyFailed
                inc     hl
                inc     de
                dec     bc
                ld      a,b
                or      c
                jr      nz,.verify
                in      a,(0x7B)
                ld      a,1
                ld      (CacheReady),a
                ld      a,(CacheSavedWin)
                out     (WIN1_PORT),a
                ei
                or      a
                ret
.copyFailed:    ld      hl,CacheBackup
                ld      de,0x0200
                ld      bc,SramSize
                ldir
.bad:           in      a,(0xFB)
                ld      a,(CacheOriginal)
                ld      (0x0200),a
                in      a,(0x7B)
                ; Also restore normal WIN0 if the probe exposed an alias.
                ld      a,(CacheNormal)
                ld      (0x0200),a
                ld      a,(CacheSavedWin)
                out     (WIN1_PORT),a
                ei
.noBackup:      ld      hl,CacheSkipStr
                ld      c,Dss.PChars
                rst     0x10
                scf
                ret
CacheDeinit:    call    SramIoDeinit
                ld      a,(CacheReady)
                or      a
                ret     z
                di
                in      a,(WIN1_PORT)
                ld      (CacheSavedWin),a
                ld      a,(CacheBackupPage)
                out     (WIN1_PORT),a
                in      a,(0xFB)
                ld      hl,CacheBackup
                ld      de,0x0200
                ld      bc,SramSize
                ldir
                in      a,(0x7B)
                xor     a
                ld      (CacheReady),a
                ld      (CacheActive),a
                ld      a,(CacheSavedWin)
                out     (WIN1_PORT),a
                ei
                ret

; The DSS handler ends EI/RETI. DI immediately after CALL prevents nesting
; before mapping is restored; RETI has already acknowledged the peripheral.
DefaultHandler: push    af
                ld      a,(CacheActive)
                push    af
                xor     a
                ld      (CacheActive),a         ; nested IRQ must leave CACHE off
                in      a,(0x7B)
                call    0x0038
                di
                pop     af
                ld      (CacheActive),a
                or      a
                jr      z,.off
                in      a,(0xFB)
.off:           pop     af
                ei
                ret
CacheSkipStr:   db "SRAM setup/backup unavailable; CACHE tests skipped",13,10,0
CacheTitleStr:  db "ATA SRAM CACHE",13,10,0
UseCache:       db 0
CacheActive:    db 0
CacheReady:     db 0
CacheNormal:    db 0
CacheOriginal:  db 0
CacheBackup     equ 0x4000
CacheBackupPage: db 0
CacheSavedWin:  db 0
