; ============================================================================
; testrom.s - bring-up test ROM for the SBC65 FPGA build  ($E000-$FFFF)
;
;  1. Initialises the ACIA at $8000 (master reset, then /16 8N1)
;  2. Clears the terminal screen and prints a banner
;  3. Runs a few 65C02-only instructions and checks the results
;  4. Tests the SRAM $0200-$7FFF with two patterns, prints OK or the failing
;     address
;  5. Shows the terminal features (inverse video, cursor positioning)
;  6. Echoes everything typed (serial or PS/2 keyboard) exactly as received
;
; Everything goes out through the ACIA, so it appears on the serial terminal
; and on the built-in composite screen.
;
; Assemble with ca65:  ca65 --cpu 65C02 testrom.s && ld65 -C testrom.cfg testrom.o -o testrom.bin
; ============================================================================
        .setcpu "65C02"

ACIAS   = $8000                 ; status / control
ACIAD   = $8001                 ; data

PTR     = $00                   ; zero-page pointer
TMP     = $02

        .segment "CODE"

RESET:  sei
        cld
        ldx     #$FF
        txs
        lda     #$03            ; ACIA master reset
        sta     ACIAS
        lda     #$15            ; /16, 8N1, RTS low, no interrupts
        sta     ACIAS

        ldx     #<BANNER
        ldy     #>BANNER
        jsr     PUTS

; ---- 65C02 instruction check ----------------------------------------------
        ldx     #<C02MSG
        ldy     #>C02MSG
        jsr     PUTS
        stz     TMP             ; STZ zp
        lda     #$0F
        tsb     TMP             ; TMP = $0F
        lda     #$03
        trb     TMP             ; TMP = $0C
        ldx     #$5A
        phx
        ply                     ; Y = $5A
        cpy     #$5A
        bne     C02BAD
        lda     TMP
        cmp     #$0C
        bne     C02BAD
        lda     #$80
        bit     #$80            ; BIT immediate
        beq     C02BAD
        bra     C02OK           ; BRA
C02BAD: ldx     #<FAILMSG
        ldy     #>FAILMSG
        jsr     PUTS
        bra     RAMTST
C02OK:  ldx     #<OKMSG
        ldy     #>OKMSG
        jsr     PUTS

; ---- RAM test $0200-$7FFF -----------------------------------------------------
RAMTST: ldx     #<RAMMSG
        ldy     #>RAMMSG
        jsr     PUTS
        lda     #$55
        jsr     FILLCHK
        bcs     RAMBAD
        lda     #$AA
        jsr     FILLCHK
        bcs     RAMBAD
        ldx     #<OKMSG
        ldy     #>OKMSG
        jsr     PUTS
        bra     DEMO
RAMBAD: lda     PTR+1           ; save failing address before PUTS uses PTR/Y
        sta     TMP
        sty     TMP+1
        ldx     #<BADAT
        ldy     #>BADAT
        jsr     PUTS
        lda     TMP
        jsr     PUTHEX
        lda     TMP+1
        jsr     PUTHEX
        lda     #13
        jsr     PUTC
        lda     #10
        jsr     PUTC

; ---- terminal demo ---------------------------------------------------------------
DEMO:   ldx     #<DEMOMSG
        ldy     #>DEMOMSG
        jsr     PUTS

; ---- echo loop -----------------------------------------------------------------
ECHO:   ldx     #<ECHOMSG
        ldy     #>ECHOMSG
        jsr     PUTS
@loop:  jsr     GETC
        jsr     PUTC
        cmp     #13
        bne     @loop
        lda     #10
        jsr     PUTC
        bra     @loop

; ---- fill $0200-$7FFF with A (address-mixed), then verify. C=1 on error -------
FILLCHK:
        sta     TMP
        stz     PTR
        lda     #$02
        sta     PTR+1
@fill:  ldy     #0
@f1:    tya
        eor     PTR+1
        eor     TMP
        sta     (PTR),y
        iny
        bne     @f1
        inc     PTR+1
        bpl     @fill           ; stop at $8000
        lda     #$02
        sta     PTR+1
@chk:   ldy     #0
@c1:    tya
        eor     PTR+1
        eor     TMP
        cmp     (PTR),y
        bne     @bad
        iny
        bne     @c1
        inc     PTR+1
        bpl     @chk
        clc
        rts
@bad:   sec
        rts

; ---- console I/O ---------------------------------------------------------------
PUTC:   pha
@w:     lda     ACIAS
        and     #$02
        beq     @w
        pla
        sta     ACIAD
        rts

GETC:   lda     ACIAS
        lsr     a
        bcc     GETC
        lda     ACIAD
        rts

PUTS:   stx     PTR             ; X/Y -> zero-terminated string
        sty     PTR+1
        ldy     #0
@l:     lda     (PTR),y
        beq     @d
        jsr     PUTC
        iny
        bne     @l
@d:     rts

PUTHEX: pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     @nib
        pla
        and     #$0F
@nib:   cmp     #10
        bcc     @dig
        adc     #6
@dig:   adc     #'0'
        jmp     PUTC

NMI:
IRQ:    rti

ESC     = 27
BANNER: .byte   ESC,"[2J",ESC,"[H"           ; clear screen, home
        .byte   "SBC65 FPGA - Cyclone 10 LP",13,10,0
C02MSG: .byte   "65C02 opcodes: ",0
RAMMSG: .byte   "SRAM $0200-$7FFF: ",0
OKMSG:  .byte   "OK",13,10,0
FAILMSG:.byte   "FAIL",13,10,0
BADAT:  .byte   "FAIL at $",0
DEMOMSG:.byte   "Terminal: ",ESC,"[7m"," inverse ",ESC,"[0m"," normal"
        .byte   ESC,"[s"                     ; (ignored: unsupported)
        .byte   ESC,"[20;45H","<- row 20 col 45"
        .byte   ESC,"[6;1H",0                ; back to row 6
ECHOMSG:.byte   "Type something:",13,10,0

        .segment "VECTORS"
        .word   NMI
        .word   RESET
        .word   IRQ
