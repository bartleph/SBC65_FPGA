; term_test.s - terminal-mode picture for comparing old and new VHDL
        .setcpu "65C02"
ACIAS   = $C080
ACIAD   = $C081
        .segment "CODE"
RESET:  sei
        cld
        ldx #$FF
        txs
        lda #$03
        sta ACIAS
        lda #$15
        sta ACIAS
        lda #$0C
        jsr PUTC
        jsr SETTLE
        lda #$20                 ; every printable character
@a:     jsr PUTC
        jsr SETTLE
        clc
        adc #1
        cmp #$7F
        bne @a
        ldx #0
@m:     lda MSG,x                ; inverse text, more lines, an 80+ char line
        beq @md
        jsr PUTC
        jsr SETTLE
        inx
        bne @m
@md:    lda #$01
        sta $031E
@h:     bra @h
PUTC:   pha
@w:     lda ACIAS
        and #$02
        beq @w
        pla
        sta ACIAD
        rts
SETTLE: pha
@s:     lda ACIAS
        and #$02
        beq @s
        phy
        ldy #40
@d:     dey
        bne @d
        ply
        pla
        rts
MSG:    .byte $0D,$0A,"normal ",$1B,"[7m","INVERSE",$1B,"[0m"," normal",$0D,$0A
        .byte "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234"
        .byte $1B,"[5;10H","cursor here",0
NMI:    rti
        .segment "VECTORS"
        .word NMI, RESET, NMI
