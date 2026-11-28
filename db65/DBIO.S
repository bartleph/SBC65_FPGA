;=====================================================================
; DBIO.S - CONSOLE, LINE INPUT AND DOS CALLS FOR DB65
;=====================================================================

; ---- CONSOLE --------------------------------------------------------
OUTC:   pha
@w:     lda ACIAS
        and #2
        beq @w
        pla
        sta ACIAD
        rts

RAWKEY: lda PBK
        beq @w
        stz PBK
        rts
@w:     lda ACIAS
        lsr a
        bcc @w
        lda ACIAD
        and #$7F
        rts

; KEY WAITING?  C=1 AND A = KEY (CONSUMED), C=0 NONE
KEYHIT: lda PBK
        bne @y
        lda ACIAS
        lsr a
        bcc @n
        lda ACIAD
        and #$7F
        sec
        rts
@y:     stz PBK
        sec
        rts
@n:     clc
        rts

; A KEY: ARROWS (ESC [ A-D OR ^E ^X ^S ^D) -> K_UP..K_LF, DEL -> BS
GETKEY: jsr RAWKEY
        cmp #$1B
        bne @ctl
        ldx #0              ; ESC: IS A [ FOLLOWING QUICKLY?
        ldy #24
@t:     lda ACIAS
        lsr a
        bcs @g
        dex
        bne @t
        dey
        bne @t
        lda #$1B
        rts
@g:     lda ACIAD
        and #$7F
        cmp #'['
        beq @br
        sta PBK
        lda #$1B
        rts
@br:    jsr RAWKEY
        cmp #'A'
        bcc GETKEY
        cmp #'D'+1
        bcs GETKEY
        sec
        sbc #'A'
        tax
        lda ARRMAP,x
        rts
@ctl:   cmp #$05
        bne @1
        lda #K_UP
        rts
@1:     cmp #$18
        bne @2
        lda #K_DN
        rts
@2:     cmp #$13
        bne @3
        lda #K_LF
        rts
@3:     cmp #$04
        bne @4
        lda #K_RT
        rts
@4:     cmp #$7F
        bne @r
        lda #$08
@r:     rts
ARRMAP: .byte K_UP,K_DN,K_RT,K_LF

; PRINT THE TEXT AFTER THE JSR (0-ENDED)
PRS:    pla
        sta MP
        pla
        sta MP+1
@l:     inc MP
        bne @1
        inc MP+1
@1:     lda (MP)
        beq @e
        jsr OUTC
        bra @l
@e:     lda MP+1
        pha
        lda MP
        pha
        rts

; PRINT 0-ENDED TEXT AT (MP)
PRMP:   ldy #0
@l:     lda (MP),y
        beq @r
        jsr OUTC
        iny
        bne @l
@r:     rts

CRLF:   lda #$0D
        jsr OUTC
        lda #$0A
        jsr OUTC
        inc LCOUNT
        rts
SPACE:  lda #' '
        jmp OUTC
SPACES: tax                 ; A SPACES
        beq @r
@l:     jsr SPACE
        dex
        bne @l
@r:     rts

ESCB:   lda #$1B
        jsr OUTC
        lda #'['
        jmp OUTC
CLS:    jsr ESCB
        lda #'2'
        jsr OUTC
        lda #'J'
        jsr OUTC
        jsr ESCB
        lda #'H'
        jmp OUTC
CLEOL:  jsr ESCB
        lda #'K'
        jmp OUTC
REVON:  jsr ESCB
        lda #'7'
        jsr OUTC
        lda #'m'
        jmp OUTC
REVOFF: jsr ESCB
        lda #'0'
        jsr OUTC
        lda #'m'
        jmp OUTC
; CURSOR TO LINE X, COLUMN Y (1-BASED)
GOTO:   phy
        phx
        jsr ESCB
        pla
        jsr PRDEC
        lda #';'
        jsr OUTC
        pla
        jsr PRDEC
        lda #'H'
        jmp OUTC

; A IN DECIMAL
PRDEC:  sta T16
        stz T16+1
; T16 IN DECIMAL (NO LEADING ZEROS)
PRD16:  jsr FINT16
        lda #0
        jsr FIXSTR
PROBUF: ldx #0
@l:     cpx OLEN
        beq @r
        lda OBUF,x
        jsr OUTC
        inx
        bra @l
@r:     rts
; T16 RIGHT-ALIGNED IN A COLUMNS
PRD16R: pha
        jsr FINT16
        lda #0
        jsr FIXSTR
        pla
        sec
        sbc OLEN
        bcc PROBUF
        jsr SPACES
        bra PROBUF

UPPER:  cmp #'a'
        bcc @r
        cmp #'z'+1
        bcs @r
        and #$DF
@r:     rts

; ---- PAGING FOR LONG LISTINGS ---------------------------------------
; AFTER A SCREENFUL, WAIT FOR A KEY (ESC STOPS).  ANY KEY TYPED
; DURING A LISTING PAUSES IT TOO.
PAGECHK:
        jsr KEYHIT
        bcs @wait
        lda LCOUNT
        clc
        adc #2
        cmp NLINES
        bcc @r
@wait:  cmp #$1B
        beq @stop
        jsr PRS
        .byte "-- more (ESC stops) --",0
        jsr GETKEY
        pha
        lda #$0D
        jsr OUTC
        jsr CLEOL
        stz LCOUNT
        pla
        cmp #$1B
        beq @stop
        cmp #$03
        beq @stop
@r:     rts
@stop:  jmp ABORT

;=====================================================================
; LINE INPUT INTO LBUF (0-ENDED, LLEN).  RETURN: C=0.  ESC: C=1.
; UP ARROW BRINGS BACK THE LAST LINE.
;=====================================================================
GETLINE:
        stz LLEN
@k:     jsr GETKEY
        cmp #$0D
        beq @ok
        cmp #$1B
        bne :+
        jmp @esc
:
        cmp #$03
        beq @esc
        cmp #$08
        beq @bs
        cmp #$15
        beq @clr
        cmp #K_UP
        beq @old
        cmp #' '
        bcc @k
        cmp #$80
        bcs @k
        ldx LLEN
        cpx #LBMAX
        bcs @k
        sta LBUF,x
        inc LLEN
        jsr OUTC
        bra @k
@bs:    lda LLEN
        beq @k
        dec LLEN
        jsr BSOUT
        bra @k
@clr:   lda LLEN
        beq @k
        dec LLEN
        jsr BSOUT
        bra @clr
@old:   jsr @clr2           ; THE PREVIOUS LINE
        ldx #0
@o:     lda OLDLINE,x
        beq @k
        sta LBUF,x
        jsr OUTC
        inx
        stx LLEN
        bra @o
@clr2:  lda LLEN
        beq @r2
        dec LLEN
        jsr BSOUT
        bra @clr2
@r2:    rts
@ok:    ldx LLEN
        stz LBUF,x
        ldx #0              ; KEEP IT FOR NEXT TIME
@s:     lda LBUF,x
        sta OLDLINE,x
        beq @d
        inx
        bra @s
@d:     jsr CRLF
        clc
        rts
@esc:   ldx LLEN
        stz LBUF,x
        jsr CRLF
        sec
        rts
BSOUT:  lda #8
        jsr OUTC
        lda #' '
        jsr OUTC
        lda #8
        jmp OUTC

; ASK A QUESTION (TEXT AFTER THE JSR), READ A LINE.  C=1 = ESC
ASK:    pla
        sta MP
        pla
        sta MP+1
@l:     inc MP
        bne @1
        inc MP+1
@1:     lda (MP)
        beq @e
        jsr OUTC
        bra @l
@e:     lda MP+1
        pha
        lda MP
        pha
        jmp GETLINE

; Y/N: Z=1 FOR YES (PROMPT ALREADY PRINTED)
YESNO:  jsr GETKEY
        jsr UPPER
        pha
        jsr OUTC
        jsr CRLF
        pla
        cmp #'Y'
        rts

;=====================================================================
; DOS CALLS.  THE COMMAND LINE IS BUILT IN CMDBUF; A DOS ERROR
; GOES TO DSKERR, WHICH ABANDONS THE COMMAND.
;=====================================================================
CMDSTART:
        stz CPOS
CMDSTR: ldy #0              ; APPEND 0-ENDED TEXT AT (MP)
@l:     lda (MP),y
        beq @r
        jsr CMDCH
        iny
        bra @l
@r:     rts
CMDCH:  ldx CPOS
        sta CMDBUF,x
        inc CPOS
        rts
CMDHEX: pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr @n
        pla
        and #$0F
@n:     cmp #10
        bcc @d
        adc #6
@d:     adc #'0'
        jmp CMDCH
CMDNAME: ldx #0             ; THE FILE NAME IN FNAME, THEN CR
@l:     lda FNAME,x
        beq @e
        phx
        jsr CMDCH
        plx
        inx
        bra @l
@e:     lda #$0D
        jmp CMDCH
CMDEND: lda #$0D
        jmp CMDCH

DOSSET: lda #<CMDBUF
        sta INBUF
        lda #>CMDBUF
        sta INBUF+1
        stz CMDPOS
        lda #$28
        sta CMDLEN
        rts
DOSCALL: jsr DOSSET
        jsr DOCMD
        clc
        rts

DSKERR: lda #$FF            ; NO TRACK IS TRUSTED AFTER A DISK ERROR
        sta CXCUR
        sta CXCUR+1
        stz CXDIRTY
        stz CXDIRTY+1
        stz HDIRTY
        lda #<M_DISK
        sta EMSG
        lda #>M_DISK
        sta EMSG+1
        jmp ERRJMP2
M_DISK: .byte "DISK ERROR",0

; FIND THE FILE NAMED IN FNAME BY READING THE DIRECTORY (TRACK 12,
; SECTORS 1 AND 2) INTO DIRB.  C=0 FOUND: FTRK0 = START TRACK (BCD),
; FTRKN = NUMBER OF TRACKS.  C=1 NOT THERE.
FINDFILE:
        lda FDRV            ; ON THE NAME'S DRIVE
        jsr SETDRV
        lda #<DIRCMD1
        sta MP
        lda #>DIRCMD1
        sta MP+1
        jsr CMDSTART
        jsr DOSCALL
        lda #<DIRCMD2
        sta MP
        lda #>DIRCMD2
        sta MP+1
        jsr CMDSTART
        jsr DOSCALL
        lda #<DIRB
        sta GP
        lda #>DIRB
        sta GP+1
@e:     ldy #0              ; COMPARE 14 CHARACTERS (NAME SPACE-PADDED)
        ldx #0
@c:     lda FNAME,x
        beq @pad
        inx
        bra @cmp
@pad:   lda #' '
@cmp:   cmp (GP),y
        bne @next
        iny
        cpy #14
        bne @c
        lda (GP),y          ; FOUND
        sta FTRK0
        iny
        lda (GP),y
        sed
        sec
        sbc FTRK0
        cld
        jsr BCDBIN
        inc a
        sta FTRKN
        clc
        rts
@next:  clc
        lda GP
        adc #16
        sta GP
        bcc @e
        inc GP+1
        lda GP+1
        cmp #>(DIRB+512)
        bne @e
        sec
        rts
DIRCMD1: .byte "CA A600=12,1",13,0
DIRCMD2: .byte "CA A700=12,2",13,0

BCDBIN: pha                 ; BCD A -> BINARY
        lsr a
        lsr a
        lsr a
        lsr a
        tax
        pla
        and #$0F
@l:     cpx #0
        beq @r
        clc
        adc #10
        dex
        bra @l
@r:     rts

; SELECT DRIVE A (1-4 = A-D) WITH THE DOS "SE" COMMAND, IF IT ISN'T
; ALREADY (A DOS ERROR GOES TO DSKERR)
SETDRV: cmp DRIVE
        beq @r
        pha
        lda #<SECMD
        sta MP
        lda #>SECMD
        sta MP+1
        jsr CMDSTART
        pla
        ora #$40
        jsr CMDCH
        lda #$0D
        jsr CMDCH
        jmp DOSCALL
@r:     rts
SECMD:  .byte "SE ",0
; PRINT "B:" FOR THE FILE IN USE
PRDBDRV: lda DBNAME+16
        ora #$40
        jsr OUTC
        lda #':'
        jmp OUTC
