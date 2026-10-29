;[]-------------------------------------------------------------------------[]
; Millisecond timer.
; Z84C15 CTC channel 3 runs in timer mode and raises an IM2 interrupt about
; 1000 times a second; TickHandler counts them in Ticks (32 bit).
; The IM2 vector table and both handlers live in window 2 (our page), so the
; ticks keep counting while DSS (window 0 = DSS/driver page) or BIOS
; (window 0 = ROM) code runs. Every vector other than the CTC one lands on
; IM2_DEFAULT, which jumps to 0x0038 - the DSS IM1 handler (keyboard scan,
; cursor) keeps working unchanged.
; The tick rate is calibrated against the RTC seconds, so it does not matter
; whether the CTC clock follows the CPU turbo mode or not.
; Overwriting the table entry for vector 0x86 breaks odd vectors 0x85/0x87;
; only Zilog peripherals supply vectors (always even) and DSS polls the SIO,
; so in practice only the CTC (0x86) and the floating bus (0xFF) occur - the
; same trade-off as the Sprinter SDK's IM2 setup.
; Some drivers (the DSS floppy driver) transfer sectors with interrupts
; disabled, so ticks can be lost: TimerStart also records the RTC time and
; PrintResult falls back to it when the two disagree.
;[]-------------------------------------------------------------------------[]
IM2_TABLE       EQU     0xBC00                  ; 257 bytes, I = 0xBC
IM2_FILL        EQU     0xBB
IM2_DEFAULT     EQU     IM2_FILL*256+IM2_FILL   ; 0xBBBB: JP 0x0038
CTC_VECTOR      EQU     0x80                    ; D7..D3 of the CTC interrupt vector
CTC_CH3_VECTOR  EQU     CTC_VECTOR + 3*2        ; channel number in D2..D1
CTC_CTRL_INIT   EQU     %10100111               ; INT, timer, /256, TC follows, reset
CTC_CTRL_OFF    EQU     %00000011               ; reset channel, no INT
CTC_TIME_CONST  EQU     27                      ; 7 MHz / 256 / 27 = 1013 Hz
TIMER_MIN_HZ    EQU     100                     ; below this the CTC is not ticking

;Install IM2 table and start CTC channel 3
TimerInit:      di
                ld      a,i
                ld      (SavedI),a
                ld      hl,IM2_TABLE
                ld      de,IM2_TABLE+1
                ld      bc,256
                ld      (hl),IM2_FILL
                ldir
                ld      a,0xC3                  ; JP 0x0038
                ld      (IM2_DEFAULT),a
                ld      hl,0x0038
                ld      (IM2_DEFAULT+1),hl
                ld      hl,TickHandler
                ld      (IM2_TABLE+CTC_CH3_VECTOR),hl
                ld      hl,0
                ld      (Ticks),hl
                ld      (Ticks+2),hl
                ld      a,IM2_TABLE>>8
                ld      i,a
                im      2
                ld      a,CTC_VECTOR
                out     (CTC_CH0),a             ; D0 = 0: CTC interrupt vector register
                ld      a,CTC_CTRL_INIT
                out     (CTC_CH3),a
                ld      a,CTC_TIME_CONST
                out     (CTC_CH3),a
                ld      a,1
                ld      (TimerActive),a
                ei
                ret

;Stop CTC channel 3 and return to IM1 (safe to call when TimerInit did not run)
TimerDeinit:    ld      a,(TimerActive)
                and     a
                ret     z
                di
                ld      a,CTC_CTRL_OFF
                out     (CTC_CH3),a
                im      1
                ld      a,(SavedI)
                ld      i,a
                xor     a
                ld      (TimerActive),a
                ei
                ret

;CTC channel 3 interrupt: Ticks += 1
TickHandler:    push    af
                push    hl
                ld      hl,Ticks
                inc     (hl)
                jr      nz,.done
                inc     hl
                inc     (hl)
                jr      nz,.done
                inc     hl
                inc     (hl)
                jr      nz,.done
                inc     hl
                inc     (hl)
.done:          pop     hl
                pop     af
                ei
                reti

;Measure ticks per second against the RTC; falls back to RTC seconds when the
;CTC interrupt does not arrive (TimerMode = 1, TicksPerSec = 1)
TimerCalibrate: ld      hl,CalibratingStr
                ld      c,Dss.PChars
                rst     0x10
                call    CMOSWait
                call    TimerRead
                push    de
                call    CMOSWait
                call    TimerRead
                pop     bc
                ex      de,hl
                and     a
                sbc     hl,bc                   ; HL = ticks in one second
                ld      (TicksPerSec),hl
                ld      bc,TIMER_MIN_HZ
                and     a
                sbc     hl,bc
                jr      c,.fallback
                ld      hl,(TicksPerSec)
                ld      bc,TimerHzNumStr
                call    PRNUM0
                ld      hl,TimerHzStr
                ld      c,Dss.PChars
                rst     0x10
                ret
.fallback:      ld      a,1
                ld      (TimerMode),a
                ld      hl,1
                ld      (TicksPerSec),hl
                ld      hl,TimerRtcStr
                ld      c,Dss.PChars
                rst     0x10
                ret

;Remember the current time in StartTicks and StartRtc; all registers but AF
;preserved. In RTC mode waits for the next second first, so the measurement
;starts on a second boundary.
TimerStart:     push    hl
                push    de
                push    bc
                push    ix
                ld      a,(TimerMode)
                and     a
                call    nz,CMOSWait
                call    RtcSeconds
                ld      (StartRtc),de
                ld      (StartRtc+2),hl
                call    TimerRead               ; ticks last: SysTime stays outside the interval
                ld      (StartTicks),de
                ld      (StartTicks+2),hl
                pop     ix
                pop     bc
                pop     de
                pop     hl
                ret

;HLDE = current time in ticks (TimerMode 0: CTC ticks, 1: RTC seconds)
;IX is destroyed in RTC mode
TimerRead:      ld      a,(TimerMode)
                and     a
                jr      nz,.rtc
                di
                ld      de,(Ticks)
                ld      hl,(Ticks+2)
                ei
                ret
.rtc:           push    bc
                call    RtcSeconds
                pop     bc
                ret

;HLDE = RTC seconds since midnight; destroys BC, IX
RtcSeconds:     ld      c,Dss.SysTime
                rst     0x10
                jp      TimeToSeconds

;HL = whole RTC seconds since TimerStart (midnight wrap handled, capped at
;0xFFFF); destroys BC, DE, IX
RtcElapsed:     call    RtcSeconds
                ld      bc,(StartRtc)
                ex      de,hl
                and     a
                sbc     hl,bc
                ex      de,hl
                ld      bc,(StartRtc+2)
                sbc     hl,bc                   ; HL:DE = now - start
                jr      nc,.nowrap
                ex      de,hl                   ; crossed midnight: += 86400
                ld      bc,86400 & 0xFFFF
                add     hl,bc
                ex      de,hl
                ld      bc,86400 >> 16
                adc     hl,bc
.nowrap:        ld      a,h
                or      l
                ex      de,hl
                ret     z
                ld      hl,0xFFFF
                ret

;H = hours, L = minutes, B = seconds -> HLDE = seconds since midnight
TimeToSeconds:  push    bc
                push    hl
                ld      a,h
                ld      hl,0
                ld      de,0
                ld      bc,3600
                call    .addmul
                ex      (sp),hl                 ; HL = hours/minutes, (SP) = result high
                ld      a,l
                ex      (sp),hl
                ld      bc,60
                call    .addmul
                pop     af                      ; drop hours/minutes
                pop     bc
                ld      c,b
                ld      b,0
                ex      de,hl
                add     hl,bc
                ex      de,hl
                ret     nc
                inc     hl
                ret
;HLDE += BC * A
.addmul:        and     a
                ret     z
.loop:          ex      de,hl
                add     hl,bc
                ex      de,hl
                jr      nc,.next
                inc     hl
.next:          dec     a
                jr      nz,.loop
                ret

;Ожидание до начала секунды (interrupts stay enabled between the port accesses)
CMOSWait:       call    .read
                ld      e,a
.loop:          call    .read
                cp      e
                jr      z,.loop
                ret
.read:          di
                ld      bc,CMOS_AWR
                xor     a                       ; register 0 - seconds
                out     (c),a
                ld      bc,CMOS_DRD
                in      a,(c)
                ei
                ret

CalibratingStr: db      "Calibrating timer ... ", 0x00
TimerHzStr:
TimerHzNumStr:  db      "00000 Hz (CTC channel 3)", 0x0D, 0x0A, 0x00
TimerRtcStr:    db      "CTC interrupt not detected, using RTC (1 s resolution)", 0x0D, 0x0A, 0x00

Ticks:          dw      0, 0                    ;CTC ticks since TimerInit (32 bit)
StartTicks:     dw      0, 0                    ;TimerStart snapshot
StartRtc:       dw      0, 0                    ;TimerStart snapshot, RTC seconds since midnight
TicksPerSec:    dw      1
TimerMode:      db      0                       ;0 - CTC ticks, 1 - RTC seconds
TimerActive:    db      0
SavedI:         db      0
