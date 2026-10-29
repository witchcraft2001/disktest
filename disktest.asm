                DEVICE ZXSPECTRUM128
                org	0x80EA
                include "dss_equ.asm"
                include "spr_equ.asm"
                include "bios_equ.asm"

Buffer:         equ     0xC000                  ;16 KiB page allocated with GetMem, mapped to window 3
TEST_FILE       equ     1
TEST_BIOS       equ     2

EXEhead:	db	"EXE"
		db	0			; +3
		dw	EntryExec-EXEhead
		dw	0x0000			; +4
		dw	EXEend-EntryExec	; +8
		dw	0, 0			; +10
		dw	0			; +14
		dw	EntryExec		; +16
		dw	EntryExec
		dw	0xBFFF			; stack: top of window 2, above the IM2 table
EntryExec:	di
                push    ix
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
                pop     hl
		LD	HL, IncorDosStr
		LD	C, Dss.PChars		; print text
		RST	0x10
		JP      Exit
.next1:         ld      c,Dss.CurDisk
                rst     0x10
                jp      c,DiskError
                pop     hl
                ld      (WorkDriveNumber),a
                add     a,"A"
                ld      (DiskInfo.letter),a
                call    ParseArguments
                jp      c,Exit
                ld      hl,DiskInfo
                ld      c,Dss.PChars
                rst     0x10
                ld      a,(WorkDriveNumber)
                ld      c,Dss.ChDisk
                rst     0x10
                jp      c,DiskError
                ld      a,"\\"
                ld      (DiskInfo.letter+2),a
                xor     a
                ld      (DiskInfo.letter+3),a
                ld      hl,DiskInfo.letter
                ld      c,Dss.ChDir
                rst     0x10
                jp      c,DiskError
                ; 16 KiB I/O buffer: own page in window 3 (the EXE gets window 2 only)
                ld      b,1
                ld      c,Dss.GetMem
                rst     0x10
                jp      c,MemError
                ld      b,0
                ld      c,Dss.SetWin3
                rst     0x10
                jp      c,MemError
                call    TimerInit
                call    TimerCalibrate
                ld      hl,FileSizeStr
                ld      c,Dss.PChars
                rst     0x10
                ld      hl,EnterStr
                ld      c,Dss.PChars
                rst     0x10
                ld      a,(TestMask)
                bit     0,a
                jr      z,.biosTests
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
.biosTests:     ld      a,(TestMask)
                bit     1,a
                jp      z,Exit
                call    BiosTestPrepare
                jp      c,Exit
                ld      hl,TestSize512BStr
                ld      e,1
                call    TestBiosRead
                jp      c,SomeErrors
                ld      hl,TestSize2KBStr
                ld      e,4
                call    TestBiosRead
                jp      c,SomeErrors
                ld      hl,TestSize4KBStr
                ld      e,8
                call    TestBiosRead
                jp      c,SomeErrors
                ld      hl,TestSize8KBStr
                ld      e,16
                call    TestBiosRead
                jp      c,SomeErrors
                ld      hl,TestSize16KBStr
                ld      e,32
                call    TestBiosRead
                jp      c,SomeErrors
                jp      Exit
;[]-------------------------------------------------------------------------[]
;HL = block size label (4 chars), DE = block size in bytes
;CF = 1: A = 0 canceled, A = 1 disk error
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
                ld      a,h
                ld      (.step),a               ; block size / 256 for PollKey
                xor     a
                ld      (KeyCount),a
                ld      ix,0
                ld      hl,0
                ld      bc,Dss.Move_FP
                ld      a,(FileHandler)
                rst     0x10
                jr      c,.error
                call    TimerStart
.loop:          ld      hl,Buffer
                ld      de,0x0800
.buferSize:     equ     $-2
                ld      a,(FileHandler)
                ld      c,Dss.Read
                rst     0x10
                jr      c,.error
                ld      a,d                     ; DE = bytes read, 0 = end of file
                or      e
                jr      z,.endfile
                ld      a,0
.step:          equ     $-1
                call    PollKey
                jr      nz,.break
                jr      .loop
.endfile:       ld      hl,(FileBlocks)
                call    PrintResult
                and     a
                ret
.break:         xor     a
                scf
                ret
.error:         ld      a,1
                scf
                ret
;[]-------------------------------------------------------------------------[]
;CF = 1: A = 0 canceled, A = 1 disk error
CreateFile:     ld      hl,Buffer
                ld      de,Buffer+1
                ld      bc,0x1000-1
                ld      (hl),0
                ldir
                ld      hl,CreateFileStr
                ld      c,Dss.PChars
                rst     0x10
                ld      hl,TestFileName
                ld      c,Dss.Creat_N
                xor     a
                rst     0x10
                jr      c,.error
                ld      (FileHandler),a
                ld      hl,(FileBlocks)         ;512-byte blocks -> 4 KiB writes
                and     a
                rr      h
                rr      l
                rr      h
                rr      l
                rr      h
                rr      l
                ld      b,h
                ld      c,l
                xor     a
                ld      (KeyCount),a
                call    TimerStart
.loop:          push    bc
                ld      hl,Buffer
                ld      de,0x1000
                ld      a,(FileHandler)
                ld      c,Dss.Write
                rst     0x10
                jr      c,.errorpop
                ld      a,0x1000/256
                call    PollKey
                jr      nz,.breakpop
                pop     bc
                dec     bc
                ld      a,b
                or      c
                jr      nz,.loop
                ld      hl,(FileBlocks)
                call    PrintResult
                and     a
                ret
.breakpop:      pop     bc
                xor     a
                scf
                ret
.errorpop:      pop     bc
.error:         ld      a,1
                scf
                ret

DeleteTestFile: ld      hl,TestFileName         ;delete temp file
                ld      c,Dss.Delete
                xor     a
                rst     0x10
                ret
;A = 0 canceled, 1 disk error, 2 error message already printed
SomeErrors:     and     a
                jr      z,.cancel
                dec     a
                jr      nz,Exit
                jr      DiskError
.cancel:        ld      hl,CancelStr
                jr      PrintError
MemError:       ld      hl,MemErrorStr
                jr      PrintError
DiskError:      LD	HL, DiskErrorStr
PrintError:     LD	C, Dss.PChars		; print text
		RST	0x10
Exit:           ld      a,(FileHandler)
                and     a
                jr      z,.next
                ld      c,Dss.Close
                rst     0x10
.next:          call    DeleteTestFile
                call    TimerDeinit             ; the buffer page is released by DSS on exit
                LD	BC, 0xFF00 + Dss.Exit
		RST	0x10			; exit

;[]-------------------------------------------------------------------------[]
;Print "Elapsed: SSSSS.hh s  Speed: NNNNN KiB/s" for HL sectors (512 bytes)
;transferred since TimerStart. Time comes from the CTC ticks unless the RTC
;shows more than one extra second (ticks lost while a driver kept interrupts
;disabled) or the CTC is not used - then the RTC seconds are used.
PrintResult:    push    hl
                call    TimerRead               ; HLDE = now
                push    hl
                push    de
                call    RtcElapsed
                ld      (RtcSecs),hl
                pop     de
                pop     hl
                ld      bc,(StartTicks)
                ex      de,hl
                and     a
                sbc     hl,bc
                ex      de,hl                   ; DE = elapsed low word
                ld      bc,(StartTicks+2)
                sbc     hl,bc                   ; HL = elapsed high word
                ld      (Elapsed),de
                ld      (Elapsed+2),hl
                xor     a
                ld      (RtcUsed),a
                ld      a,(TimerMode)
                and     a
                jr      nz,.rtc
                ld      bc,(TicksPerSec)
                call    div32                   ; DE = whole seconds counted by the CTC
                inc     de                      ; RTC granularity is 1 s
                ld      hl,(RtcSecs)
                and     a
                sbc     hl,de
                jr      c,.ticks
                jr      z,.ticks
                ld      a,1
                ld      (RtcUsed),a
.rtc:           ld      hl,(RtcSecs)            ; elapsed = RTC seconds in ticks
                ld      de,(TicksPerSec)
                call    Mul16x16
                ld      (Elapsed),de
                ld      (Elapsed+2),hl
.ticks:         ld      de,(Elapsed)
                ld      hl,(Elapsed+2)
                ld      a,h
                or      l
                or      d
                or      e
                jr      nz,.nonzero
                inc     de                      ; never divide by zero
                ld      (Elapsed),de
.nonzero:       ld      bc,(TicksPerSec)
                call    div32                   ; DE = seconds, HL = remainder
                push    hl
                ex      de,hl
                ld      bc,ElapsedNumStr
                call    PRNUM0
                pop     hl
                ld      de,100                  ; hundredths = remainder * 100 / TicksPerSec
                call    Mul16x16
                ld      bc,(TicksPerSec)
                call    div32
                ld      a,e
                ld      de,ElapsedFracStr
                call    Put2Digits
                ld      hl,ElapsedStr
                ld      c,Dss.PChars
                rst     0x10
                pop     hl                      ; speed = KiB * TicksPerSec / elapsed
                srl     h
                rr      l
                ld      de,(TicksPerSec)
                call    Mul16x16                ; HLDE = KiB * TicksPerSec
.norm:          ld      bc,(Elapsed+2)          ; div32 needs a 16-bit divisor:
                ld      a,b                     ; halve both while elapsed > 0xFFFF
                or      c
                jr      z,.divide
                srl     h
                rr      l
                rr      d
                rr      e
                srl     b
                rr      c
                ld      (Elapsed+2),bc
                ld      bc,(Elapsed)
                rr      b
                rr      c
                ld      (Elapsed),bc
                jr      .norm
.divide:        ld      bc,(Elapsed)
                call    div32                   ; DE = KiB/s
                ex      de,hl
                ld      bc,SpeedNumStr
                call    PRNUM0
                ld      hl,SpeedStr
                ld      c,Dss.PChars
                rst     0x10
                ld      a,(RtcUsed)
                and     a
                jr      z,.eol
                ld      hl,RtcUsedStr
                ld      c,Dss.PChars
                rst     0x10
.eol:           ld      hl,EnterStr
                ld      c,Dss.PChars
                rst     0x10
                ret

;Poll the keyboard once per 32 KiB transferred; A = bytes just transferred / 256.
;ZF = 0: key pressed. Destroys HL, C. Cheap between polls (it runs inside the
;timed loops).
PollKey:        ld      hl,KeyCount
                add     a,(hl)
                cp      128
                jr      nc,.scan
                ld      (hl),a
                xor     a
                ret
.scan:          ld      (hl),0
                ld      c,Dss.ScanKey
                rst     0x10
                ret

;Write A (0..99) as two decimal digits at (DE); DE advances by 2
Put2Digits:
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

;Parse Arguments in Command line
ParseArguments:
                ld      a,(hl)
                or      a
                ret     z
                inc     hl
                inc     hl
                ld      bc,0x2f20
                ld      e,"-"
.loop:          ld      a,(hl)
                inc     hl
                and     a
                ret     z
                cp      c
                jr      z,.loop
                cp      b
                jr      z,.argument
                cp      e
                jr      z,.argument
                res     5,a
                cp      "A"
                jr      c,.skip
                cp      "Z" + 1
                jr      nc,.skip
                ld      d,a
                ld      a,(hl)
                inc     hl
                cp      ":"
                jr      nz,.skip
                ld      a,d
                ld      (DiskInfo.letter),a
                sub     "A"
                ld      (WorkDriveNumber),a
                jr      .loop
.argument:      ld      a,(hl)
                inc     hl
                cp      "?"
                jr      z,.help
                res     5,a
                cp      "H"
                jr      z,.help
                cp      "S"
                jr      z,.size
                cp      "F"
                jr      z,.fileonly
                cp      "B"
                jr      z,.biosonly
.skip:          ld      a,(hl)
                cp      c
                jr      z,.loop
                and     a
                ret     z
                inc     hl
                jr      .skip
.fileonly:      ld      a,TEST_FILE
                ld      (TestMask),a
                jr      .skip
.biosonly:      ld      a,TEST_BIOS
                ld      (TestMask),a
                jr      .skip
.help:          ld      hl,HelpStr
                ld      c,Dss.PChars
                rst     0x10
                scf
                ret
.size:          inc     hl
                push    de
                push    bc
                ex      hl,de
                push    de
                ld      hl,S512KStr
                push    hl
                call    CheckParam
                ld      hl,0x0400
                jr      nc,.found
                pop     de
                pop     de
                push    de
                ld      hl,S1MStr
                push    hl
                call    CheckParam
                ld      hl,0x0800
                jr      nc,.found
                pop     de
                pop     de
                push    de
                ld      hl,S2MStr
                push    hl
                call    CheckParam
                ld      hl,0x1000
                jr      nc,.found
                pop     de
                pop     de
                push    de
                ld      hl,S4MStr
                push    hl
                call    CheckParam
                ld      hl,0x2000
                jr      nc,.found
                pop     de
                pop     de
                push    de
                ld      hl,S8MStr
                push    hl
                call    CheckParam
                ld      hl,0x4000
                jr      c,.notfound
.found:         ld      (FileBlocks),hl
                pop     hl
                ld      de,FileSizeStr.size
                ld      bc,4
                ldir
                pop     hl
                pop     bc
                pop     de
                jp      .skip
.notfound       pop     hl
                push    de
                ld      hl,UnknownSizeStr
                ld      c,Dss.PChars
                rst     0x10
                pop     hl
                pop     de
                pop     bc
                pop     de
                jp      .skip
CheckParam:     ld      b,0x20
.loop:          ld      a,(hl)
                or      a
                ret     z
                ld      a,(de)
                cp      b
                jr      z,.end
                and     a
                jr      z,.end
                cp      (hl)
                jr      z,.next
                cp      "A"
                jr      c,.end
                res     5,a
                cp      (hl)
                jr      nz,.end
.next:          inc     hl
                inc     de
                jr      .loop
.end:           scf
                ret
HelpStr:        db      "Disk perfomance testing utility.", 0x0D, 0x0A
                db      "With no command line parameters, the utility will perform a file-system based", 0x0D, 0x0A
                db      "performance test (write + read) with a test file size of 2MB and a raw BIOS", 0x0D, 0x0A
                db      "sector read test on disk from which utility was started.", 0x0D, 0x0A, 0x0D, 0x0A
                db      "Usage: X:       specify test disk letter", 0x0D, 0x0A
                db      "       /H, /?   help page", 0x0D, 0x0A
                db      "       /S       specify the test file size (512K, 1M, 2M, 4M, 8M).", 0x0D, 0x0A
                db      "                Default test file size is 2M", 0x0D, 0x0A
                db      "       /F       file system test only", 0x0D, 0x0A
                db      "       /B       BIOS sector read test only (IDE drives)", 0x0D, 0x0A, 0x0D, 0x0A
                db      "Example: DISKTEST.EXE C: /S 4M /B", 0x0D, 0x0A, 0x0D, 0x0A, 0x00
FileSizeStr:    db      "Test file size: "
.size:          db      "2M  ", 0x00
S512KStr:       db      "512K", 0x00
S1MStr:         db      "1M", 0x00,0x00
S2MStr:         db      "2M", 0x00,0x00
S4MStr:         db      "4M", 0x00,0x00
S8MStr:         db      "8M", 0x00,0x00
UnknownSizeStr: db      "The value of the size parameter is not correct, please read the help (start app", 0x0D, 0x0A
                db      "with /? argument).", 0x0D, 0x0A, 0x00
CopyrightStr:	db	0x0D, 0x0A
		db	"DiskTest, ver 0.7 (Alpha)", 0x0D, 0x0A
		db	"(C) 2021, Mikhaltchenkov Dmitry aka Hard/WCG, Rostov-on-Don.", 0x0D, 0x0A, 0x0D, 0x0A, 0x00
IncorDosStr:	db	"Incorrect DOS version, need DOS 1.00 or high.", 0x0D, 0x0A, 0x00
MemErrorStr:    db      "Not enough memory for the 16 KiB buffer.", 0x0D, 0x0A, 0x00
CreateFileStr:  db      "Test: File write, block  4KB ... ", 0x00
DiskInfo:       db      "Testing disk: "
.letter:        db      "A:", 0x0D, 0x0A, 0x00
EnterStr:       db      0x0D, 0x0A, 0x00
ElapsedStr:     db      "Elapsed: "
ElapsedNumStr:  db      "00000."
ElapsedFracStr: db      "00 s  ", 0x00
CancelStr:      db      "Canceled", 0x0D, 0x0A, 0x00
SpeedStr:       db      "Speed: "
SpeedNumStr:    db      "00000 KiB/s", 0x00
RtcUsedStr:     db      " (RTC)", 0x00

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
                db      "Test: File read, block "
.size:          db      "512B ... ", 0x00
DiskErrorStr:   db      "PANIC: Disk error!", 0x0D, 0x0A, 0x00
TestFileName:   db      "DISKTEST.$$$",0
FileBlocks:     dw      0x1000                  ;file lenght in 512 bytes blocks
FileHandler:    db      0                       ;file handler
WorkDriveNumber:
                db      0xFF
TestMask:       db      TEST_FILE | TEST_BIOS   ;/F, /B
KeyCount:       db      0                       ;PollKey: bytes/256 since the last poll
Elapsed:        dw      0, 0                    ;PrintResult scratch
RtcSecs:        dw      0
RtcUsed:        db      0                       ;1: result timed by the RTC (ticks were lost)
                ;Division routines
                include "muldiv.asm"
                include "prnum.asm"
                include "timer.asm"
                include "biosread.asm"

EXEend:
                ASSERT  EXEend <= IM2_DEFAULT   ; code must stay below the IM2 jump/table/stack
                savebin	"DISKTEST.EXE",EXEhead,EXEend-EXEhead
