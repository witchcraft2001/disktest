;-------------------------------------------------------------------------------		
; DE = HLDE/BC, HL = HLDE%BC
;1456t
div32:
		ld a,10h
.div321:	sla e
		rl d
		adc hl,hl
		jr c, .div322
		sbc hl,bc
		jr nc, .div323
		add hl,bc
		dec a
		jr nz, .div321
		ret
.div322:	ccf
		sbc hl,bc
.div323:	inc de
		dec a
		jr nz, .div321
		ret
;-------------------------------------------------------------------------------
;hlde=hlde/512	;bc=остаток
div512:		ld c,e		;младшие 8 бит остатка
		ld b,0
		ld e,d
		ld d,l
		ld l,h
		ld h,b		;сдвинули делитель на 8 бит вправо
		srl l		;и ещё на 1
		rr d
		rr e
		rl b
		ret
;====================================
;	16 bit multiply
;====================================
; mul16:		ld hl,0
; mul_hlbc_de:	ld a,b
; 		ld b,0x11
; 		jr .mul16_3
; .mul16_1:	jr nc,.mul16_2
; 		add hl,de
; .mul16_2:	rr h
; 		rr l
; .mul16_3:	rra
; 		rr c
; 		djnz .mul16_1
; 		ld b,a
; 		ret
;-------------------------------------------------------------------------------
;HL=X, DE=Y -> HL:DE = X*Y (HL=high word, DE=low word, matches div32's dividend)
;Horner's method on Y's bits, MSB first: P = P*2 + bit*X. Destroys AF,BC.
Mul16x16:       ld      (MulX),hl
                ld      b,d
                ld      c,e                     ;BC = Y, shifted left each iteration
                ld      hl,0
                ld      de,0                    ;DE:HL = P (accumulator), DE=high,HL=low
                ld      a,16
.loop:          sla     c
                rl      b                       ;Y <<= 1; CF = bit now being processed
                jr      c,.bit1
.bit0:          add     hl,hl
                ex      de,hl
                adc     hl,hl
                ex      de,hl                   ;P *= 2
                jr      .next
.bit1:          add     hl,hl
                ex      de,hl
                adc     hl,hl
                ex      de,hl                   ;P *= 2
                push    de
                ld      de,(MulX)
                add     hl,de
                pop     de
                jr      nc,.next
                inc     de
.next:          dec     a
                jr      nz,.loop
                ex      de,hl                   ;P was DE=high,HL=low -> HL=high,DE=low
                ret
MulX:           dw      0
