; osi_test.s - simulation test program for OSI mode (not for the real board)
; Results go to $0300-$031F in RAM, where the testbench checks them.
        .setcpu "65C02"
ACIAS   = $C080
ACIAD   = $C081
BANK    = $C0A0
VID     = $D000
KBD     = $DF00
RES     = $0300

        .segment "DOSX"          ; stands in for the DOSX ROM at $D000
DOSX:   jsr EREAD                ; like DOSX calling PRINT in the $E000 ROM,
        rts                      ; which reads DOSX's message text
DXDATA: .byte $5C

        .segment "CODE"
RESET:  sei
        cld
        ldx #$FF
        txs
        lda #$03
        sta ACIAS
        lda #$15
        sta ACIAS
        lda #$0C                 ; clear screen, home
        jsr PUTC
        jsr SETTLE               ; (the clear takes 82 us; at this fast test
                                 ;  baud rate the terminal's FIFO would overflow)
        ldx #0
@p:     lda MSG,x
        beq @pd
        jsr PUTC
        inx
        bra @p
@pd:    jsr SETTLE
        lda #$02                 ; OSI mode on
        sta BANK
        lda BANK
        sta RES+0                ; expect $FA
        ldx #0                   ; PEEK what the terminal printed on row 0
@r:     lda VID,x
        sta RES+1,x              ; expect HELLO
        inx
        cpx #5
        bne @r
        lda #$AA                 ; POKE row 1 col 1, row 31 col 63
        sta VID+$41
        lda #$55
        sta $D7FF
        lda VID+$41
        sta RES+6                ; expect $AA
        lda $D7FF
        sta RES+7                ; expect $55
        lda #$0D                 ; PRINT CR LF Z in OSI mode -> row 1 col 0
        jsr PUTC
        lda #$0A
        jsr PUTC
        lda #'Z'
        jsr PUTC
        jsr SETTLE
        lda VID+$40
        sta RES+8                ; expect 'Z' ($5A)
        lda VID+$41
        sta RES+9                ; expect $AA (still there)
        ; picture for the frame grab: graphics codes on row 3, text at the
        ; far right of row 4
        ldx #0
@g:     txa
        ora #$80
        sta VID+$C0,x
        inx
        cpx #64
        bne @g
        ldx #0                   ; all 256 codes on rows 8-11
@all:   txa
        sta VID+$200,x
        inx
        bne @all
        lda #'E'
        sta VID+$13F             ; row 4, col 63
        lda #'W'
        sta VID+$100             ; row 4, col 0
        ; keyboard: wait until the testbench holds 'A' (row 1 bit 6)
        lda #$01
        sta RES+$1F
@k:     lda #$FD
        sta KBD
        lda KBD
        cmp #$BF
        bne @k
        sta RES+10               ; $BF
        lda #$FE                 ; row 0: SHIFT LOCK (Caps Lock on)
        sta KBD
        lda KBD
        sta RES+11               ; expect $FE
        lda #$FF                 ; no row selected
        sta KBD
        lda KBD
        sta RES+12               ; expect $FF
        lda $D800                ; $D800 mirrors $DF00
        sta RES+24               ; expect $FF
        lda #$06                 ; inverted polarity
        sta BANK
        lda #$02                 ; row 1 selected by a 1
        sta KBD
        lda KBD
        sta RES+13               ; expect $40
        lda #$02
        sta BANK
        ; the same through (zp),Y, as BASIC's PEEK and POKE do it
        lda #$00
        sta $F0
        lda #$DF
        sta $F1
        ldy #0
        lda #$FD
        sta ($F0),y
        lda ($F0),y
        sta RES+17               ; expect $BF
        lda BANK
        sta RES+18               ; expect $FA (still in OSI mode)
        lda #$41
        sta $F0
        lda #$D0
        sta $F1
        lda ($F0),y
        sta RES+19               ; expect $AA ($D041)
        lda BANK
        sta RES+20               ; expect $FA
        ; let the testbench grab a frame, then wait for 'Q' (row 1 bit 7)
        lda #$01
        sta RES+$1E
@q:     lda #$FD
        sta KBD
        lda KBD
        and #$80
        bne @q
        lda KBD+1
        sta RES+23               ; expect $15 (Q was the last key pressed)
        jsr DOSX                 ; DOSX -> $E000 routine reading DOSX data
        sta RES+21               ; expect $5C
        lda VID                  ; ROM code, nothing run from RAM since:
        sta RES+22               ; expect $20 (the ROM byte: JSR)
        ldx #3                   ; now run code from RAM, as BASIC does
@cp:    lda STUB,x
        sta $0400,x
        dex
        bpl @cp
        jsr $0400
        sta RES+15               ; expect $48 (the screen again)
        lda BANK
        sta RES+14               ; expect $FA (still OSI mode)
        lda #$A5
        sta RES+16               ; finished
@h:     bra @h

PUTC:   pha
@w:     lda ACIAS
        and #$02
        beq @w
        pla
        sta ACIAD
        rts

SETTLE: lda ACIAS               ; wait for the last byte, then a little more
        and #$02
        beq SETTLE
        ldy #0
@d:     dey
        bne @d
        rts

MSG:    .byte "HELLO", 0
STUB:   lda VID                  ; copied to $0400 and run there
        rts
EREAD:  lda DXDATA               ; $E000 code reading DOSX data
        rts

NMI:    rti

        .segment "VECTORS"
        .word NMI, RESET, NMI
