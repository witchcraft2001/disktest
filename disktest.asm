                DEVICE ZXSPECTRUM128
                org	0x80EA
                include "dss_equ.asm"
                include "spr_equ.asm"
                include "bios_equ.asm"

Buffer:         equ     0xC000                  ;16 KiB page allocated with GetMem, mapped to window 3
TEST_FILE       equ     1
TEST_BIOS       equ     2
TEST_ATA        equ     4
TEST_CACHE      equ     8
TEST_SRAM_IO    equ     32
TEST_MAP        equ     16

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
                ld      a,(VerboseOutput)
                or      a
                jr      nz,.noLegend
                ld      hl,CompactLegend
                call    SeriesText
.noLegend:      ld      a,(TestMask)
                bit     0,a
                jr      z,.biosTests
                call    CreateFile
                jp      c,SomeErrors
                ld      a,(TestMask)
                bit     4,a
                jr      z,.fileReads
                call    BiosTestPrepare
                jr      c,.fileReads
                call    MapPrepare
.fileReads:
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
.biosTests:     call    MapRun
                jp      c,SomeErrors
                ld      a,(TestMask)
                and     TEST_BIOS | TEST_ATA | TEST_CACHE | TEST_SRAM_IO
                jp      z,Exit
                call    BiosTestPrepare         ; device + partition start for both
                jp      c,Exit
                ld      a,(TestMask)
                bit     1,a
                jr      z,.ataTests
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
.ataTests:      ld      a,(TestMask)
                and     TEST_CACHE | TEST_SRAM_IO
                call    nz,CacheInit
                ld      a,(CacheReady)
                or      a
                jr      z,.ataStart
                ld      a,(TestMask)
                and     TEST_SRAM_IO
                call    nz,SramIoInit
.ataStart:      ld      a,(TestMask)
                bit     2,a
                jr      z,.cacheTests
                call    AtaTests
                jp      c,SomeErrors
.cacheTests:    ld      a,(CachePaired)
                or      a
                jp      nz,Exit
                ld      a,(TestMask)
                bit     3,a
                jr      z,.sramIoTests
                call    CacheInit
                jp      c,Exit
                ld      a,1
                ld      (UseCache),a
                ld      hl,CacheTitleStr
                ld      c,Dss.PChars
                rst     0x10
                call    AtaTests
                jp      c,SomeErrors
.sramIoTests:   ld      a,(SramIoReady)
                or      a
                jp      z,Exit
                ld      a,1
                ld      (UseCache),a
                ld      (TargetSram),a
                ld      hl,SramIoBuffer
                ld      (AtaBuffer),hl
                call    AtaTests
                jp      c,SomeErrors
                jp      Exit
;[]-------------------------------------------------------------------------[]
;HL = block size label (4 chars), DE = block size in bytes
;CF = 1: A = 0 canceled, A = 1 disk error
FileReadPass:   call    SeriesLoad
                push    de
                ld      de,ConsistentReadStr.size
                ld      bc,4
                ldir
                ld      hl,ConsistentReadStr
                call    SeriesTitle
                pop     hl
                ld      (.buferSize),hl
                ld      a,1
                ld      (VerifyFile),a
                push    hl
                call    VerifyInit
                pop     hl
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
                ld      hl,0
                ld      (FileReadSectors),hl
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
                ld      a,e
                or      a
                jr      nz,.error
                bit     0,d
                jr      nz,.error
                push    de
                ld      a,d
                srl     a
                call    VerifyBlock
                pop     de
                ret     c

                ld      hl,(FileReadSectors)
                ld      a,d
                srl     a
                ld      e,a
                ld      d,0
                add     hl,de
                ld      (FileReadSectors),hl
                ld      de,(FileBlocks)
                or      a
                sbc     hl,de
                jr      c,.more
                jr      nz,.error
.more:          ld      a,0
.step:          equ     $-1
                call    PollKey
                jr      nz,.break
                jr      .loop
.endfile:       ld      hl,(FileReadSectors)
                ld      de,(FileBlocks)
                or      a
                sbc     hl,de
                jr      nz,.error
                ld      hl,(FileReadSectors)
                jp      SeriesFinish
.break:         xor     a
                scf
                ret
.error:         ld      a,1
                scf
                ret
;[]-------------------------------------------------------------------------[]
;CF = 1: A = 0 canceled, A = 1 disk error
CreateFile:     ld      hl,0
                ld      (PatternSector),hl
                ld      (WriteElapsed),hl
                ld      (WriteElapsed+2),hl
                ld      a,(TimerMode)
                or      a
                ld      a,0
                jr      nz,.writeClock
                inc     a
.writeClock:    ld      (WriteTimeValid),a
                ld      hl,CreateFileStr
                ld      c,Dss.PChars
                rst     0x10
                xor     a
                ld      (FileOperation),a
                call    CreateUniqueTestFile
                jp      c,.error
                ld      (FileHandler),a
                ld      a,1
                ld      (FileOwned),a
                ld      (FileOpen),a
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
.loop:         push    bc
                call    FillPattern
                ld      a,(WriteTimeValid)
                or      a
                call    nz,TimerStart
                ld      a,1
                ld      (FileOperation),a
                ld      hl,Buffer
                ld      de,0x1000
                ld      a,(FileHandler)
                ld      c,Dss.Write
                rst     0x10
                jp      c,.errorpop
                ; DSS Write: CF is the result. DE is NOT a portable byte count.
                call    WriteStop
                ld      a,0x1000/256
                call    PollKey
                jr      nz,.breakpop
                pop     bc
                dec     bc
                ld      a,b
                or      c
                jr      nz,.loop
                call    CheckWrittenLength
                ret     c
                ld      hl,EnterStr
                call    SeriesText
                call    WritePrint
                ld      a,2
                ld      (FileOperation),a
                ld      a,(FileHandler)
                ld      c,Dss.Close
                rst     0x10
                jp      c,.error
                xor     a
                ld      (FileOpen),a
                ld      a,3
                ld      (FileOperation),a
                ld      hl,TestFileName
                ld      a,FileMode.Read
                ld      c,Dss.Open
                rst     0x10
                jp      c,.error
                ld      (FileHandler),a
                ld      a,1
                ld      (FileOpen),a
                or      a
                ret
.breakpop:      pop     bc
                xor     a
                scf
                ret
.errorpop:      pop     bc
.error:         jp      PrintFileOperationError
 ; Query current position once, outside timed writes. HL:IX is the documented
 ; Move_FP result; no assumption is made about registers returned by Write.
CheckWrittenLength:
                ld      a,4
                ld      (FileOperation),a
                ld      a,(FileHandler)
                ld      hl,0
                ld      ix,0
                ld      bc,0x0100+Dss.Move_FP
                rst     0x10
                jp      c,PrintFileOperationError
                ld      (WritePosition),ix
                ld      (WritePosition+2),hl
                ld      hl,(FileBlocks)
                ld      de,512
                call    Mul16x16
                ld      (WriteExpected),de
                ld      (WriteExpected+2),hl
                ld      bc,(WritePosition+2)
                or      a
                sbc     hl,bc
                jr      nz,.mismatch
                ex      de,hl
                ld      bc,(WritePosition)
                or      a
                sbc     hl,bc
                ret     z
.mismatch:      ld      hl,WritePosition+3
                ld      de,WriteLengthStr.actual
                call    .hex32
                ld      hl,WriteExpected+3
                ld      de,WriteLengthStr.expected
                call    .hex32
                ld      hl,WriteLengthStr
                call    SeriesText
                ld      a,2
                scf
                ret
.hex32:         ld      b,4
.byte:          ld      a,(hl)
                call    PutHex2
                dec     hl
                djnz    .byte
                ret
WritePosition:  dd 0
WriteExpected:  dd 0
WriteLengthStr: db 13,10,"Written file length: #"
.actual:        db "00000000 bytes, expected #"
.expected:      db "00000000",13,10,0

 ; Exclusive creation; retain existing files and try another 8.3 name.
 ; Retry only FILE_EXISTS (#07); propagate all other DSS errors unchanged.
CreateUniqueTestFile:
.try:           ld      hl,TestFileName
                ld      c,Dss.Creat_N
                xor     a
                rst     0x10
                ret     nc
                cp      7
                scf
                ret     nz
                ld      a,(TempNameNumbered)
                or      a
                jr      nz,.increment
                ld      hl,NumberedTestName
                ld      de,TestFileName
                ld      bc,13
                ldir
                ld      a,1
                ld      (TempNameNumbered),a
                jr      .try
.increment:     ld      hl,TestFileName+7
                ld      b,3
.digit:         inc     (hl)
                ld      a,(hl)
                cp      "9"+1
                jr      c,.try
                ld      (hl),"0"
                dec     hl
                djnz    .digit
                ld      a,7                       ; all 1001 candidate names occupied
                scf
                ret
PrintFileOperationError:
                push    af
                ld      hl,FileOperationPrefix
                call    SeriesText
                ld      a,(FileOperation)
                add     a,a
                ld      e,a
                ld      d,0
                ld      hl,FileOperationNames
                add     hl,de
                ld      e,(hl)
                inc     hl
                ld      d,(hl)
                ex      de,hl
                call    SeriesText
                ld      hl,TestFileName
                call    SeriesText
                pop     af
                ld      de,FileOperationCode.hex
                call    PutHex2
                ld      hl,FileOperationCode
                call    SeriesText
                ld      a,2
                scf
                ret
FileOperationPrefix: db 13,10,"File error: ",0
FileOperationNames: dw FileCreateOp,FileWriteOp,FileCloseOp,FileOpenOp,FilePositionOp
FileCreateOp:   db "create ",0
FileWriteOp:    db "write ",0
FileCloseOp:    db "close ",0
FileOpenOp:     db "open for reading ",0
FilePositionOp: db "query written length ",0
FileOperationCode: db ": DSS #"
.hex:           db "00",13,10,0
FileOperation:  db 0
TempNameNumbered: db 0
NumberedTestName: db "DISKT000.$$$",0

 ; Pattern generation and timing syscalls stay outside each write interval.
 ; RTC's one-second resolution cannot time individual 4KB writes reliably.
WriteStop:      ld      a,(WriteTimeValid)
                or      a
                ret     z
                call    TimerStop
                ld      a,(TimerMode)
                or      a
                jr      nz,.invalid
                ld      a,(RtcUsed)
                or      a
                jr      nz,.invalid
                ld      hl,(WriteElapsed)
                ld      de,(Elapsed)
                add     hl,de
                ld      (WriteElapsed),hl
                ld      hl,(WriteElapsed+2)
                ld      de,(Elapsed+2)
                adc     hl,de
                ld      (WriteElapsed+2),hl
                ret
.invalid:       xor     a
                ld      (WriteTimeValid),a
                ret
WritePrint:     ld      hl,WriteResultStr
                call    SeriesText
                ld      a,(WriteTimeValid)
                or      a
                ld      hl,NoTimeStr
                jp      z,SeriesText
                xor     a
                ld      (RtcUsed),a
                ld      hl,WriteElapsed
                ld      de,Elapsed
                ld      bc,4
                ldir
                ld      hl,(FileBlocks)
                push    hl
                jp      PrintStopped
WriteResultStr: db "Write 4KB: ",0
WriteElapsed:   dd 0
WriteTimeValid: db 0

DeleteTestFile: ld      a,(FileOwned)
                or      a
                ret     z
                xor     a
                ld      (FileOwned),a
                ld      hl,TestFileName         ;delete temp file
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
Exit:           ld      a,(FileOpen)
                and     a
                jr      z,.next
                ld      a,(FileHandler)
                ld      c,Dss.Close
                rst     0x10
.next:          call    CacheDeinit
                call    DeleteTestFile
                call    TimerDeinit             ; the buffer page is released by DSS on exit
                LD	BC, 0xFF00 + Dss.Exit
		RST	0x10			; exit

;[]-------------------------------------------------------------------------[]
;Print "Elapsed: SSSSS.hh s  Speed: NNNNN KiB/s" for HL sectors (512 bytes)
;transferred since TimerStart. Time comes from the CTC ticks unless the RTC
;shows more than one extra second (ticks lost while a driver kept interrupts
;disabled) or the CTC is not used - then the RTC seconds are used.
TimerStop:      call    TimerRead               ; HLDE = now
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
.rtc:           ld      a,1
                ld      (RtcUsed),a
                ld      hl,(RtcSecs)            ; elapsed = RTC seconds in ticks
                ld      de,(TicksPerSec)
                call    Mul16x16
                ld      (Elapsed),de
                ld      (Elapsed+2),hl
.ticks:         ret

PrintResult:    push    hl
                call    TimerStop
PrintStopped:   ld      a,(TimerMode)
                cp      2
                jr      z,.invalid
                ld      de,(Elapsed)
                ld      hl,(Elapsed+2)
                ld      a,h
                or      l
                or      d
                or      e
                jr      nz,.nonzero
.invalid:       pop     hl
                ld      hl,UnavailableNumber
                ld      de,SpeedNumStr
                ld      bc,5
                ldir
                ld      hl,NoTimeStr
                call    ResultText
                ret
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
                call    ResultText
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
                call    ResultText
                ld      a,(RtcUsed)
                and     a
                jr      z,.suffix
                ld      hl,RtcUsedStr
                call    ResultText
.suffix:        ld      hl,(ResultSuffix)       ; e.g. the data checksum
                ld      a,h
                or      l
                jr      z,.eol
                call    ResultText
                ld      hl,0
                ld      (ResultSuffix),hl
.eol:           ld      hl,EnterStr
                call    ResultText
                ret

ResultText:     ld      a,(SilentResult)
                or      a
                ret     nz
                jp      SeriesText
SilentResult:   db 0
UnavailableNumber: db "-----"
VerboseOutput:  db 0

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
                ret     z                       ; no key: A is not a key code
                cp      0x1B                    ; Esc only
                jr      z,.escape
                xor     a                       ; consume/ignore other keys
                ret
.escape:        ld      a,1
                or      a                       ; NZ = cancel
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
                jp      z,.help
                res     5,a
                cp      "H"
                jp      z,.help
                cp      "S"
                jp      z,.size
                cp      "F"
                jp      z,.fileonly
                cp      "B"
                jp      z,.biosonly
                cp      "A"
                jp      z,.ataonly
                cp      "C"
                jp      z,.cacheonly
                cp      "D"
                jp      z,.sramioonly
                cp      "V"
                jp      z,.verbose
                cp      "M"
                jp      z,.maponly
                cp      "R"
                jp      z,.repeat
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
.repeat:        ld      a,(hl)
                cp      " "
                jr      nz,.repeatValue
                inc     hl
                jr      .repeat
.repeatValue:   sub     "0"
                cp      1
                jr      z,.repeatOk
                cp      3
                jr      z,.repeatOk
                cp      5
                jp      nz,.help
.repeatOk:      ld      (RepeatCount),a
                inc     hl
                ld      a,(hl)
                or      a
                ret     z
                cp      " "
                jp      nz,.help
                jp      .loop
.sramioonly:    ld      a,TEST_SRAM_IO
                ld      (TestMask),a
                jp      .skip
.verbose:       ld      a,1
                ld      (VerboseOutput),a
                jp      .skip
.maponly:       ld      a,TEST_FILE | TEST_MAP
                ld      (TestMask),a
                jp      .skip
.cacheonly:     ld      a,TEST_CACHE
                ld      (TestMask),a
                jr      .skip
.ataonly:       ld      a,TEST_ATA
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
                db      "Default: prepare 2MB file, compare file/mapped BIOS and ATA DRAM/SRAM,",13,10
                db      "plus raw BIOS. Three reads after a verified warmup; median and range.",13,10
                db      "Existing DISKTEST.$$$ is never overwritten or deleted.",13,10,13,10
                db      "Usage: X:       specify test disk letter", 0x0D, 0x0A
                db      "       /H, /?   help page", 0x0D, 0x0A
                db      "       /S       specify the test file size (512K, 1M, 2M, 4M, 8M).", 0x0D, 0x0A
                db      "                Default test file size is 2M", 0x0D, 0x0A
                db      "       /F       file system test only", 0x0D, 0x0A
                db      "       /B       BIOS sector read test only (IDE drives)", 0x0D, 0x0A
                db      "       /A       direct ATA port test only: READ SECTORS vs READ MULTIPLE", 0x0D, 0x0A, 0x0D, 0x0A
                db      "       /M       file / BIOS comparison using the same file sectors",13,10
                db      "       /D       ATA code and 512-byte receive ring in SRAM",13,10
                db      "       /V       verbose output (default: compact KiB/s table)",13,10
                db      "                Esc cancels; other keys are ignored",13,10
                db      "       /R 1|3|5  measured reads (default 3) after verified warmup",13,10
                db      "       /C       same ATA core in SRAM CACHE",13,10
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
CopyrightStr:   db "DiskTest 0.8.1 (Alpha) - Hard/WCG",13,10,0
IncorDosStr:	db	"Incorrect DOS version, need DOS 1.00 or high.", 0x0D, 0x0A, 0x00
MemErrorStr:    db      "Not enough memory for the 16 KiB buffer.", 0x0D, 0x0A, 0x00
CreateFileStr:  db      "Preparing patterned file (4KB writes) ... ", 0x00
DiskInfo:       db      "Testing disk: "
.letter:        db      "A:", 0x0D, 0x0A, 0x00
EnterStr:       db      0x0D, 0x0A, 0x00
ElapsedStr:     db      "Elapsed: "
ElapsedNumStr:  db      "00000."
ElapsedFracStr: db      "00 s  ", 0x00
CancelStr:      db      13,10,"Canceled (Esc)", 0x0D, 0x0A, 0x00
SpeedStr:       db      "Speed: "
SpeedNumStr:    db      "00000 KiB/s", 0x00
NoTimeStr:      db      "Time unavailable/below resolution; speed omitted",13,10,0
RtcUsedStr:     db      " (RTC, coarse)", 0x00
SumStr:         db      " ["
.hex:           db      "0000]", 0x00

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
FileReadSectors: dw     0
FileOwned:      db      0
FileOpen:       db      0
FileHandler:    db      0                       ;file handler
WorkDriveNumber:
                db      0xFF
TestMask:       db      TEST_FILE | TEST_BIOS | TEST_ATA | TEST_CACHE | TEST_MAP | TEST_SRAM_IO        ;/F, /B, /A
KeyCount:       db      0                       ;PollKey: bytes/256 since the last poll
Elapsed:        dw      0, 0                    ;PrintResult scratch
RtcSecs:        dw      0
RtcUsed:        db      0                       ;1: result timed by the RTC (ticks were lost)
ResultSuffix:   dw      0                       ;string printed after the speed, 0 = none
                ;Division routines
                include "muldiv.asm"
                include "PRNUM.ASM"
                include "timer.asm"
                include "biosread.asm"
                include "atatest.asm"
                include "cache.asm"
                include "sram_io.asm"
                include "series.asm"
                include "compact.asm"
                include "verify.asm"
                include "fatmap.asm"

EXEend:
                ASSERT IM2_TABLE+257 <= 0xBE00 ; reserve at least 512 bytes for stack
                ASSERT  EXEend <= IM2_DEFAULT   ; code must stay below the IM2 jump/table/stack
                savebin	"DISKTEST.EXE",EXEhead,EXEend-EXEhead
