        .setcpu "65C02"
        .zeropage
PTR:    .res 2
TP:     .res 2
        .code
        jmp TWRAP
TVEC:   .word 0
TWRAP:  jsr TIN
        lda #0
        rol a
        sta TRES
        rts
TIN:    tsx
        stx ERRSP
        jsr TJMP
        sta TAV
        clc
        rts
TJMP:   jmp (TVEC)
TRES:   .byte 0
TAV:    .byte 0
TW:     .byte 0
TPAR:   ldy #0
        jsr FPARSE
        bcc @k
        ldy #$FF
@k:     tya
        rts
TGEN:   lda TW
        jmp GENSTR
TFIX:   lda TW
        jmp FIXSTR
TSCI:   lda TW
        jmp SCISTR
        .include "BCD.S"
