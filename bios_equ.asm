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

; IDE registers as 16-bit ports, LD BC,port / IN|OUT (C) (sprinter_bios SP2000.inc,
; MODULE IDE). The register is selected by the low address byte and the transfer
; direction, the high byte is ignored - so INI/OUTI may count in B.
Ide.WriteData           EQU     0x0150          ; 1F0
Ide.WriteFeatures       EQU     0x0151          ; 1F1
Ide.WriteCounter        EQU     0x0152          ; 1F2
Ide.WriteSector         EQU     0x0153          ; 1F3  LBA 0..7
Ide.WriteCylLow         EQU     0x0154          ; 1F4  LBA 8..15
Ide.WriteCylHigh        EQU     0x0155          ; 1F5  LBA 16..23
Ide.WriteDevHead        EQU     0x4152          ; 1F6  device | LBA 24..27
Ide.WriteCommand        EQU     0x4153          ; 1F7
Ide.ReadData            EQU     0x0050          ; 1F0
Ide.ReadError           EQU     0x0051          ; 1F1
Ide.ReadCounter         EQU     0x0052          ; 1F2
Ide.ReadDevHead         EQU     0x4052          ; 1F6
Ide.ReadStatus          EQU     0x4053          ; 1F7
Ide.ChanelPort          EQU     0xBC            ; out (#BC),a
Ide.Primary             EQU     0x21
Ide.Secondary           EQU     0x01
Ide.DevHeadLBA          EQU     0xE0            ; master, LBA; | 0x10 = slave
IdeSt.BSY               EQU     0x80
IdeSt.RDY               EQU     0x40
IdeSt.DRQ               EQU     0x08
IdeSt.ERR               EQU     0x01
IdeCmd.ReadSectors      EQU     0x20            ; with retry
IdeCmd.ReadMultiple     EQU     0xC4
IdeCmd.SetMultiple      EQU     0xC6
IdeCmd.Identify         EQU     0xEC

; Z84C15 CTC channel ports (channel 0 is the mouse SIO baud generator)
CTC_CH0         EQU     0x10
CTC_CH1         EQU     0x11
CTC_CH2         EQU     0x12
CTC_CH3         EQU     0x13
