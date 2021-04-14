                DEVICE ZXSPECTRUM128
                org	0x80EA
                include "dss_equ.asm"
                include "spr_equ.asm"
                
                
EXEhead:	db	"EXE"
		db	0			; +3
		dw	EntryExec-EXEhead
		dw	0x0000			; +4
		dw	EXEend-EntryExec	; +8
		dw	0, 0			; +10
		dw	0			; +14
		dw	EntryExec		; +16
		dw	EntryExec
		dw	0x80FF
EntryExec:	di
		ld	a,(ix-0x03)		; file handle
                ld      c,Dss.Close             ; close file
		rst     0x10
		ld	hl, CopyrightStr
		ld	c, Dss.PChars		; print text
		rst	0x10
		ld	c, Dss.Version
		rst	0x10
		LD	A, D
		OR	A
		JR	NZ, .next1
		LD	HL, IncorDosStr
		LD	C, Dss.PChars		; print text
		RST	0x10
		JP      Exit
.next1          ld      c,Dss.CurDisk
                rst     0x10
                jp      c,DiskError
                add      a,"A"
                ld      (DiskInfo.letter),a
                ld      hl,DiskInfo
                ld      c,Dss.PChars
                rst     0x10
                call    DeleteTestFile
                call    CreateFile
                jp      c,SomeErrors
                ld      hl,TestSize512BStr
                ld      de,0x0200
                call    TestConsistentRead
                jp      c,SomeErrors
                ld      hl,TestSize2KBStr
                ld      de,0x0800
                call    TestConsistentRead
                jp      c,SomeErrors
                ld      hl,TestSize4KBStr
                ld      de,0x1000
                call    TestConsistentRead
                jp      c,SomeErrors
                ld      hl,TestSize8KBStr
                ld      de,0x2000
                call    TestConsistentRead
                jp      c,SomeErrors
                ld      hl,TestSize16KBStr
                ld      de,0x4000
                call    TestConsistentRead
                jp      c,SomeErrors
                jp      Exit
;[]-------------------------------------------------------------------------[]
TestConsistentRead:
                push    de
                ld      de,ConsistentReadStr.size
                ld      bc,4
                ldir
                ld      hl,ConsistentReadStr
                ld      c,Dss.PChars
                rst     0x10
                pop     hl
                ld      (.buferSize),hl
                call    CMOSWait
                ; call    PrintCurrentTime
                call    GetCurrentTime
                push    hl
                push    bc
                ld      hl,0
                push    hl
                pop     ix
                ld      bc,Dss.Move_FP
                ld      a,(FileHandler)
                rst     0x10
                ret     c
                ld      hl,Buffer
                ld      de,0x0800
.buferSize:     equ     $-2
.loop:
                push    de
                push    hl
                ld      a,(FileHandler)
                ld      c,Dss.Read
                rst     0x10
                push    de
                ex      af,af'
                ld      c,Dss.ScanKey
                rst     0x10
                pop     bc
                pop     hl
                pop     de
                ; pop     bc
                jr      nz,.break
                ex      af,af'
                jr      c,.error
                ld      a,b
                or      c
                jr      nz,.loop
.endfile:       ld      hl,ElapsedTimeStr
                ld      c,Dss.PChars
                rst     0x10
                call    GetCurrentTime                
                pop     af
                pop     de
                ld      c,a
                call    TimeMinus
                push    hl
                push    bc
                call    PrintTime
                pop     bc
                pop     hl
                xor     a
                or      h               ;Слишком большое время
                jr      nz,.tobig
                ld      c,b
                ld      b,l
                push    bc
                ld      de,FileBlocks
                and     a
                rr      d
                rr      e
                ld      hl,0
                pop     bc
                call    div32           ;в DE - частное - KB/s
                push    de
                pop     hl
                ld      bc,SpeedNumStr
                call    PRNUM0
                ld      hl,SpeedStr
                ld      c,Dss.PChars
                rst     0x10
.tobig:         ld      hl,EnterStr
                ld      c,Dss.PChars
                rst     0x10
                and     a
                ret
.break:         xor     a
                jr      .exit
.error:         ld      a,1
.exit:          pop     bc
                pop     hl
                scf
                ret
;[]-------------------------------------------------------------------------[]
CreateFile:     ld      hl,Buffer
                ld      de,Buffer+1
                ld      bc,0x1000-1
                ld      (hl),0
                ldir
                call    CMOSWait
                ; call    PrintCurrentTime
                call    GetCurrentTime
                push    hl
                push    bc
                ld      hl,CreateFileStr
                ld      c,Dss.PChars
                rst     0x10
                ld      hl,TestFileName
                ld      c,Dss.Creat_N
                xor     a
                rst     0x10
                ret     c
                ld      (FileHandler),a
                ld      bc,FileBlocks / 8
                ld      hl,Buffer
                ld      de,0x1000
.loop:          push    hl
                push    bc
                push    de
                ld      a,(FileHandler)
                ld      c,Dss.Write
                rst     0x10
                jr      c,.error
                ld      c,Dss.ScanKey
                rst     0x10
                jr      nz,.break
                pop     de
                pop     bc
                pop     hl
                dec     bc
                ld      a,b
                or      c
                jr      nz,.loop
                ld      hl,ElapsedTimeStr
                ld      c,Dss.PChars
                rst     0x10
                call    GetCurrentTime                
                pop     af
                pop     de
                ld      c,a
                call    TimeMinus
                push    hl
                push    bc
                call    PrintTime
                pop     bc
                pop     hl
                xor     a
                or      h               ;Слишком большое время
                jr      nz,.tobig
                ld      c,b
                ld      b,l
                push    bc
                ld      de,FileBlocks
                and     a
                rr      d
                rr      e
                ld      hl,0
                pop     bc
                call    div32           ;в DE - частное - Б/С
                push    de
                pop     hl
                ld      bc,SpeedNumStr
                call    PRNUM0
                ld      hl,SpeedStr
                ld      c,Dss.PChars
                rst     0x10
.tobig:         ld      hl,EnterStr
                ld      c,Dss.PChars
                rst     0x10
                and     a
                ret
.break:         xor     a
                jr      .exit
.error:         ld      a,1
.exit:          pop     de
                pop     bc
                pop     hl
                pop     bc
                pop     hl
                scf
                ret

DeleteTestFile: ld      hl,TestFileName         ;delete temp file
                ld      c,Dss.Delete
                xor     a
                rst     0x10
                ret
SomeErrors:     ld      hl,CancelStr
                and     a
                jr      z,PrintError
DiskError:      LD	HL, DiskErrorStr
PrintError:     LD	C, Dss.PChars		; print text
		RST	0x10
Exit:           ld      a,(FileHandler)
                and     a
                jr      z,.next
                ld      c,Dss.Close
                rst     0x10
.next:          call    DeleteTestFile
                LD	BC, 0xFF00 + Dss.Exit
		RST	0x10			; exit

GetCurrentTime:
                ld      c,Dss.SysTime
                rst     0x10
                ret
;Print current time
PrintCurrentTime:
                ld      c,Dss.SysTime
                rst     0x10
PrintTime:      push    bc
                ld	de,CMOSTime
	        ld      a,h
	        call	GetCMOS
	        inc     de
	        ld      a,l
	        call	GetCMOS
	        INC	DE
                pop     af
                call	GetCMOS
                ld      hl,CMOSTime
                ld      c,Dss.PChars
                rst     0x10
                ret                
GetCMOS:
	        ex	de,hl
	        ld	bc,#2F0A
	        inc	b
	        sub	c
	        jr	nc,$-2
	        add	a,c
	        ld	(hl),b
	        inc     hl
	        add	a,"0"
	        ld	(hl),a
	        inc     hl
	        ex	de,hl
	        ret
;Time = Time1 - Time2
;HL,B - Time1 (H - hours, L - minutes, B - seconds)
;DE,C - Time2 (D - hours, E - minutes, C - seconds)
;Result: HL,B
TimeMinus:      ld      a,b
                and     a
                sub     c
                ld      b,a
                jr      nc,.next
                neg
                ld      b,a
                ld      a,60
                sub     b
                ld      b,a
                inc     l
                dec     l
                jr      z,.zero
                dec     l
                jr      .next
.zero:          ld      l,59
                dec     h
.next:          ld      a,l
                and     a
                sub     e
                ld      l,a
                jr      nc,.next1
                neg
                ld      l,a
                ld      a,60
                sub     l
                inc     h
                dec     h
                jr      nz,.nozero
                ld      h,24
.nozero:        dec     h
.next1:         ld      a,h
                and     a
                sub     d
                ld      h,a
                ret     nc
                ld      h,23
                ret

;Convert Time (hours, minutes, seconds) to seconds
;HL,B - Time1 (H - hours, L - minutes, B - seconds)
;Result - HL,DE 32bit result
TimeInSeconds:  push    bc
                push    hl
                ld      a,h
                ld      bc,3600
                ld      hl,0
                and     a
                ld      d,a
                ld      e,a
                jr      z,.next
.loop:          add     hl,bc
                jr      nc,.loop1
                inc     d
.loop1:         dec     a
                jr      nz,.loop
.next:          ex      (sp),hl
                ld      a,l
                ld      l,e
                ld      h,e
                ld      bc,60
                and     a
                jr      z,.next2
.loop2:         add     hl,bc
                dec     a
                jr      nz,.loop2
.next2:         ex      hl,de
                pop     hl
                and     a
                add     hl,de
                jr      nc,.next3
                inc     b
.next3:         ld      e,b
                ld      d,0
                pop     bc
                ld      c,b
                ld      b,d
                and     a
                add     hl,bc
                jr      nc,.next4
                inc     de
.next4:         ex      hl,de
                ret

;Ожидание до начала секунды
CMOSWait:       di
                ld      bc,CMOS_AWR        ;далее не портится
                ld      a,0
                out     (c),a
                ld      a,0FFh
                in      a,(0xBD)
                ld      e,a
.loop0:         ld      bc,CMOS_AWR        ;далее не портится
                ld      a,0
                out     (c),A
                ld      a,0xff
                in      a,(0xBD)        ;отфильтруем тик (на тот случай если попали в его конец)
                cp      e            ;
                jr      z,.loop0        ;
                ld      e,a            ;4, а вот от сюда и начинается отсчёт тактов
                ret

CopyrightStr:	db	0x0D, 0x0A
		db	"DiskTest, ver 0.4a (Alpha)", 0x0D, 0x0A
		db	"(C) 2021, Mikhaltchenkov Dmitry aka Hard/WCG, Rostov-on-Don.", 0x0D, 0x0A, 0x0D, 0x0A, 0x00
IncorDosStr:	db	"Incorrect DOS version, need DOS 1.00 or high.", 0x0D, 0x0A, 0x00
CreateFileStr:  db      "Creating test file 2Mb ...        ", 0x00
DiskInfo:       db      "Testing disk: "
.letter:        db      "A:"
EnterStr:       db      0x0D, 0x0A, 0x00
ElapsedTimeStr: db      "Elapsed: ", 0x00
CancelStr:      db      "Canceled", 0x0D, 0x0A, 0x00
SpeedStr:       db      "Speed: "
SpeedNumStr:    db      "00000 KiB/s", 0x00
CMOSTime:       db      "00:00:00 ", 0x00

TestSize512BStr:
                db      "512B"
TestSize2KBStr:
                db      " 2KB"
TestSize4KBStr:
                db      " 4KB"
TestSize8KBStr:
                db      " 8KB"
TestSize16KBStr:
                db      "16KB"
ConsistentReadStr:
                db      "Test: Consistent reading "
.size:          db      "512B ... ", 0x00
DiskErrorStr:   db      "PANIC: Disk error!", 0x0D, 0x0A, 0x00
TestFileName:   db      "DISKTEST.$$$",0
FileBlocks:     equ     0x1000                  ;file lenght in 512 bytes blocks
FileHandler:    db      0                       ;file handler

                ;Division routines
                include "muldiv.asm"
                include "prnum.asm"                

Buffer:         equ     $
EXEend:
                savebin	"DISKTEST.EXE",EXEhead,EXEend-EXEhead