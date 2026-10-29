; Sprinter BIOS / DSS driver gate / Z84C15 equates
ToBIOS          EQU     0x08            ; RST 0x08 - BIOS API, C = function
ToDssDrv        EQU     0x18            ; RST 0x18 - DSS drive driver gate, A = drive (0 = A:), C = function

; BIOS drive functions (RST 0x08)
; DrvRead: A = device (0x80.. IDE), HL:IX = LBA, DE = buffer, B = sectors (0 = 256)
;          CF = 0: HL:IX = next sector, DE = next address; CF = 1: A = error code
;          Destroys IY, BC, AF'. Buffer must not cross 0xFFFF, stack must not be in window 3.
Bios.DrvRead    EQU     0x55

; DSS driver gate functions (RST 0x18), BC = subfunction*256 + function
DssDrv.GenIOCTL         EQU     0x08
DssDrv.GetParams        EQU     0x00*256 + DssDrv.GenIOCTL      ; A' = BIOS device, B = sector size code (4 = 512),
                                                                ; HL:DE = partition size in sectors, C = MBR partition
DssDrv.GetMoreParams    EQU     0x03*256 + DssDrv.GenIOCTL      ; HL:DE = partition start LBA (IDE only)
DssDrv.ErrMask          EQU     0x80                            ; on CF = 1, A = BIOS error | 0x80

; Z84C15 CTC channel ports (channel 0 is the mouse SIO baud generator)
CTC_CH0         EQU     0x10
CTC_CH1         EQU     0x11
CTC_CH2         EQU     0x12
CTC_CH3         EQU     0x13
