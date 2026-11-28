;=====================================================================
; WP65 - A FULL-SCREEN WORD PROCESSOR FOR THE SBC65 (FPGA, 48K)
;        UNDER THE OS-65D V3.3 ROM DOS.  WORDSTAR-STYLE KEYS.
;
; BUILD:  ca65 --cpu 65C02 WP.S -o WP.o ; ld65 -C wp.cfg WP.o -o WP.BIN
; RUN:    HL (WP65.HEX), GO 3B00.  SAVE: MS 3B00 68FF WP65, THEN MR WP65
;
; MEMORY: $3B00 PROGRAM, $7000 TRACK BUFFER (AND DIRECTORY), $7800
;         SCREEN COPY, $8200-$BFFF THE TEXT.  ZERO PAGE $30-$AF.
;
; THE TEXT IS A "GAP BUFFER": TEXT BEFORE THE CURSOR AT TBEG..GS-1,
; TEXT AFTER IT AT GE..TEND-1.  A CR ENDS A LINE (OR A PARAGRAPH IN A
; DOCUMENT, WHICH IS WORD-WRAPPED ON THE SCREEN).
;=====================================================================
        .setcpu "65C02"

ACIAS   = $C080
ACIAD   = $C081
DOCMD   = $E801
SETERR  = $E7FA
INBUF   = $E1
CMDPOS  = $2CE5
CMDLEN  = $2CED
CMDBUF  = $2E1E
KWTAB   = $0284             ; BASIC'S KEYWORDS (WHEN BASIC HAS BEEN RUN)

TRKBUF  = $7000             ; ONE TRACK (2K)
DIRB    = TRKBUF            ; THE DIRECTORY IS READ THERE TOO
SHADOW  = $7800             ; WHAT IS ON THE SCREEN, 80 x 32
MAXLN   = 32
TBEG    = $8200
TEND    = $C000

ZPBASE  = $30
ZPSIZE  = $80
CR      = $0D
SW      = 80                ; SCREEN WIDTH
WRAPW   = 79                ; TEXT COLUMNS (THE LAST ONE IS FOR THE CURSOR)

K_UP    = $80
K_DN    = $81
K_RT    = $82
K_LF    = $83

        .zeropage
MP:     .res 2
GP:     .res 2
GP2:    .res 2
ITP:    .res 2              ; TEXT ITERATOR
GS:     .res 2              ; GAP START (= CURSOR ADDRESS)
GE:     .res 2              ; GAP END

        .code
        jmp START
NLDEF:  .byte 24            ; $3B03: SCREEN LINES

        .bss
ZPSAVE: .res ZPSIZE
SAVESP: .res 1
MAINSP: .res 1
PBK:    .res 1
LCOUNT: .res 1
NLINES: .res 1
ROWS:   .res 1              ; TEXT ROWS (NLINES-1)
CPOS:   .res 1
FNAME:  .res 16
FTRK0:  .res 1
FTRKN:  .res 1
CUR:    .res 2              ; CURSOR OFFSET
TLEN:   .res 2              ; TEXT LENGTH
TOPO:   .res 2              ; FIRST SCREEN LINE
LSTART: .res (MAXLN+1)*2    ; START OF EACH SCREEN LINE
OFF:    .res 2
OFF2:   .res 2
NXT:    .res 2              ; LAYOUT: START OF THE NEXT LINE
LTYPE:  .res 1              ;         HOW IT ENDED: 0 CR, 1 WRAP, 2 END
RLEN:   .res 1              ;         CHARACTERS ON IT
ROWBUF: .res SW
CROW:   .res 1
CCOL:   .res 1
DESCOL: .res 1              ; COLUMN WANTED WHEN MOVING UP/DOWN
CURLINE: .res 2
MODF:   .res 1              ; CHANGED SINCE SAVED
INSM:   .res 1              ; 1 = INSERT, 0 = OVERWRITE
WWRAP:  .res 1              ; 1 = WORD WRAP (DOCUMENTS)
FTYPE:  .res 1              ; 0 TEXT, 1 ASSEMBLER, 2 BASIC
FBASE:  .res 1              ; PAGE THE FILE'S IMAGE STARTS IN ($XX79)
BLKB:   .res 2              ; BLOCK ($FFFF = NOT SET)
BLKE:   .res 2
BLKON:  .res 1
MSGP:   .res 2              ; A MESSAGE TO SHOW (0 = NONE)
TMP:    .res 2
TMP2:   .res 2
RDIF:   .res 1
LBUF:   .res 82
LLEN:   .res 1
CMDSP:  .res 1
EMSG:   .res 2
        .code

        .include "WPIO.S"

;=====================================================================
; START AND QUIT
;=====================================================================
START:  tsx
        stx SAVESP
        cld
        ldx #ZPSIZE-1
@z:     lda ZPBASE,x
        sta ZPSAVE,x
        dex
        bpl @z
        lda #<DSKERR
        ldy #>DSKERR
        jsr SETERR
        lda NLDEF
        cmp #MAXLN+1
        bcc @n
        lda #MAXLN
@n:     sta NLINES
        dec a
        sta ROWS
        stz PBK
        stz FNAME
        stz RESTN
        stz FLAST
        stz FINDS
        lda #1
        sta INSM
        jsr NEWDOC
        tsx
        stx MAINSP
        jsr FULLSCR
        lda #<M_HELLO
        ldy #>M_HELLO
        jsr SETMSG
        jmp MAIN
M_HELLO: .byte "WP65 - ^J for help, ^KL to load a file, ^KX to save and exit",0

QUIT:   jsr CLS
        ldx #ZPSIZE-1
@z:     lda ZPSAVE,x
        sta ZPBASE,x
        dex
        bpl @z
        ldx SAVESP
        txs
        rts

; AN EMPTY DOCUMENT
NEWDOC: lda #<TBEG
        sta GS
        lda #>TBEG
        sta GS+1
        lda #<TEND
        sta GE
        lda #>TEND
        sta GE+1
        stz CUR
        stz CUR+1
        stz TLEN
        stz TLEN+1
        stz TOPO
        stz TOPO+1
        stz CURLINE
        stz CURLINE+1
        stz MODF
        stz FTYPE
        lda #$3A
        sta FBASE
        lda #1
        sta WWRAP
        lda #$FF
        sta BLKB
        sta BLKB+1
        sta BLKE
        sta BLKE+1
        stz BLKON
        stz DESCV
        rts

; ERRORS: MESSAGE (A/Y), BACK TO EDITING
ERRMSG: jsr SETMSG
        ldx MAINSP
        txs
        jsr FULLSCR
        jmp MAIN
DSKERR: jsr BACKNAME        ; THE DOS ERROR VECTOR
        ldy #>M_DISK
        bra ERRMSG
M_DISK: .byte "DISK ERROR (IS THE NAME RIGHT? IS THE DISK FULL?)",0
SETMSG: sta MSGP
        sty MSGP+1
        rts

;=====================================================================
; THE GAP BUFFER
;=====================================================================
; ITERATOR: ITSET (OFF) POINTS ITP AT OFFSET OFF; ITGET -> A, C=1 AT END
ITSET:  lda OFF+1
        cmp CUR+1
        bne @c
        lda OFF
        cmp CUR
@c:     bcs @after
        clc                 ; BEFORE THE GAP
        lda OFF
        adc #<TBEG
        sta ITP
        lda OFF+1
        adc #>TBEG
        sta ITP+1
        rts
@after: sec                 ; AFTER: GE + (OFF - CUR)
        lda OFF
        sbc CUR
        sta ITP
        lda OFF+1
        sbc CUR+1
        sta ITP+1
        clc
        lda ITP
        adc GE
        sta ITP
        lda ITP+1
        adc GE+1
        sta ITP+1
        rts
ITGET:  lda ITP             ; AT THE GAP?  JUMP OVER IT
        cmp GS
        bne @1
        lda ITP+1
        cmp GS+1
        bne @1
        lda GE
        sta ITP
        lda GE+1
        sta ITP+1
@1:     lda ITP+1           ; AT THE END?
        cmp #>TEND
        bcs @end
        lda (ITP)
        inc ITP
        bne @r
        inc ITP+1
@r:     clc
        rts
@end:   sec
        rts

; A = CHARACTER AT OFFSET OFF (C=1 PAST THE END)
CHARAT: lda OFF+1
        cmp TLEN+1
        bne @c
        lda OFF
        cmp TLEN
@c:     bcc @in
        rts                 ; (C=1)
@in:    jsr ITSET
        jmp ITGET

; MOVE THE CURSOR (THE GAP) TO OFFSET OFF, COUNTING LINES CROSSED
MOVETO: lda OFF+1
        cmp CUR+1
        bne @c
        lda OFF
        cmp CUR
        bne @c
        rts
@c:     bcc @left
@rl:    lda (GE)            ; RIGHT: ONE BYTE ACROSS THE GAP
        sta (GS)
        cmp #CR
        bne @r1
        inc CURLINE
        bne @r1
        inc CURLINE+1
@r1:    inc GS
        bne @r2
        inc GS+1
@r2:    inc GE
        bne @r3
        inc GE+1
@r3:    inc CUR
        bne @r4
        inc CUR+1
@r4:    lda CUR
        cmp OFF
        bne @rl
        lda CUR+1
        cmp OFF+1
        bne @rl
        rts
@left:  lda GS              ; LEFT
        bne @l1
        dec GS+1
@l1:    dec GS
        lda GE
        bne @l2
        dec GE+1
@l2:    dec GE
        lda (GS)
        sta (GE)
        cmp #CR
        bne @l3
        lda CURLINE
        bne @l4
        dec CURLINE+1
@l4:    dec CURLINE
@l3:    lda CUR
        bne @l5
        dec CUR+1
@l5:    dec CUR
        lda CUR
        cmp OFF
        bne @left
        lda CUR+1
        cmp OFF+1
        bne @left
        rts

; INSERT A AT THE CURSOR.  C=1 IF THE TEXT IS FULL
INSCH:  pha
        lda GS
        cmp GE
        bne @ok
        lda GS+1
        cmp GE+1
        bne @ok
        pla
        sec
        rts
@ok:    pla
        sta (GS)
        cmp #CR
        bne @1
        inc CURLINE
        bne @1
        inc CURLINE+1
@1:     ldx #0              ; BLOCK MARKS AT OR AFTER THE CURSOR MOVE ON
        jsr MKINS
        ldx #2
        jsr MKINS
        inc GS
        bne @2
        inc GS+1
@2:     inc CUR
        bne @3
        inc CUR+1
@3:     inc TLEN
        bne @4
        inc TLEN+1
@4:     lda #1
        sta MODF
        clc
        rts
MKINS:  lda BLKB+1,x        ; MARK X (0 = BEGIN, 2 = END) >= CUR: +1
        cmp #$FF
        beq @r
        cmp CUR+1
        bne @c
        lda BLKB,x
        cmp CUR
@c:     bcc @r
        inc BLKB,x
        bne @r
        inc BLKB+1,x
@r:     rts
; THE CHARACTER AT OFFSET CUR WAS REMOVED: MARKS AFTER IT MOVE BACK
MKDEL:  lda BLKB+1,x
        cmp #$FF
        beq @r
        cmp CUR+1
        bne @c
        lda BLKB,x
        cmp CUR
        beq @r
@c:     bcc @r
        lda BLKB,x
        bne @d
        dec BLKB+1,x
@d:     dec BLKB,x
@r:     rts

; DELETE THE CHARACTER AT THE CURSOR -> A.  C=1 IF THERE IS NONE
DELFWD: lda GE+1
        cmp #>TEND
        bcc @ok
        sec
        rts
@ok:    lda (GE)
        pha
        inc GE
        bne @1
        inc GE+1
@1:     ldx #0
        jsr MKDEL
        ldx #2
        jsr MKDEL
        lda TLEN
        bne @2
        dec TLEN+1
@2:     dec TLEN
        lda #1
        sta MODF
        pla
        clc
        rts
; DELETE THE CHARACTER BEFORE THE CURSOR
DELBACK: lda CUR
        ora CUR+1
        bne @ok
        sec
        rts
@ok:    lda CUR             ; (MOVE LEFT ONE, THEN DELETE FORWARD)
        sec
        sbc #1
        sta OFF
        lda CUR+1
        sbc #0
        sta OFF+1
        jsr MOVETO
        jmp DELFWD

;=====================================================================
; LAYOUT: ONE SCREEN LINE FROM OFFSET OFF2 INTO ROWBUF.
; -> NXT (START OF THE NEXT LINE), LTYPE (0 CR, 1 WRAP, 2 END), RLEN
;=====================================================================
LAYOUT: lda OFF2
        sta OFF
        lda OFF2+1
        sta OFF+1
        jsr ITSET
        ldx #0              ; X = COLUMN
        lda #$FF
        sta TMP             ; LAST SPACE COLUMN
@seg:   lda ITP             ; AT THE GAP?  JUMP OVER IT
        cmp GS
        bne @ng
        lda ITP+1
        cmp GS+1
        bne @ng
        lda GE
        sta ITP
        lda GE+1
        sta ITP+1
@ng:    lda ITP+1           ; AT THE END?
        cmp #>TEND
        bcc :+
        jmp @end
:
        lda ITP             ; BYTES UNTIL THE GAP (OR THE END)
        cmp GS
        lda ITP+1
        sbc GS+1
        bcs @aft
        sec
        lda GS
        sbc ITP
        sta SEGN
        lda GS+1
        sbc ITP+1
        bra @cl
@aft:   sec
        lda #<TEND
        sbc ITP
        sta SEGN
        lda #>TEND
        sbc ITP+1
@cl:    beq @n1
        lda #$FF
        sta SEGN
@n1:    ldy #0
@c:     lda (ITP),y         ; THE FAST PART: ONE PIECE OF THE TEXT
        cmp #CR
        beq @cr
        cmp #' '
        bcc @ctl
        bne @p
        stx TMP
@p:     sta ROWBUF,x
        inx
        iny
        cpx #WRAPW
        beq @full
        cpy SEGN
        bne @c
        tya                 ; THE PIECE ENDS: ON PAST THE GAP
        clc
        adc ITP
        sta ITP
        bcc @seg
        inc ITP+1
        bra @seg
@ctl:   lda #'.'            ; (OTHER CONTROL CHARACTERS)
        bra @p
@full:  stx RLEN            ; FULL: WHAT COMES NEXT?
        tya
        clc
        adc ITP
        sta ITP
        bcc @f1
        inc ITP+1
@f1:    jsr ITGET
        bcs @end
        cmp #CR
        beq @cr
        lda #1              ; WRAP
        sta LTYPE
        ldx TMP
        lda WWRAP
        beq @hard
        cpx #$FF
        beq @hard
        inx                 ; AFTER THE LAST SPACE
        stx RLEN
@hard:  lda RLEN
        bra @nx
@cr:    stx RLEN
        stz LTYPE
        txa
        inc a               ; (PAST THE CR)
        bra @nx
@end:   stx RLEN
        lda #2
        sta LTYPE
        txa
@nx:    clc
        adc OFF2
        sta NXT
        lda OFF2+1
        adc #0
        sta NXT+1
        rts
        .bss
SEGN:   .res 1
        .code

; START OF THE HARD LINE (PARAGRAPH) HOLDING OFFSET OFF -> OFF
PARSTART:
        jsr ITSET           ; (ITP = WHERE OFFSET OFF IS)
@l:     lda OFF
        ora OFF+1
        beq @r
        lda ITP             ; BACK ONE, JUMPING OVER THE GAP
        cmp GE
        bne @1
        lda ITP+1
        cmp GE+1
        bne @1
        lda GS
        sta ITP
        lda GS+1
        sta ITP+1
@1:     lda ITP
        bne @2
        dec ITP+1
@2:     dec ITP
        lda (ITP)
        cmp #CR
        beq @r
        lda OFF
        bne @3
        dec OFF+1
@3:     dec OFF
        bra @l
@r:     rts

; START OF THE SCREEN LINE HOLDING OFFSET OFF -> OFF2
DLSTART: lda OFF
        sta TMP+0
        pha
        lda OFF+1
        pha
        jsr PARSTART
        lda OFF
        sta OFF2
        lda OFF+1
        sta OFF2+1
        pla
        sta DLP+1
        pla
        sta DLP
@l:     jsr LAYOUT
        lda LTYPE
        cmp #2
        beq @r
        lda DLP+1           ; DLP < NXT?  THEN IT IS THIS LINE
        cmp NXT+1
        bne @c
        lda DLP
        cmp NXT
@c:     bcc @r
        lda NXT
        sta OFF2
        lda NXT+1
        sta OFF2+1
        bra @l
@r:     rts
        .bss
DLP:    .res 2
        .code

; START OF THE SCREEN LINE BEFORE THE ONE STARTING AT OFF2 -> OFF2
DLPREV: lda OFF2
        ora OFF2+1
        beq @r
        sec
        lda OFF2
        sbc #1
        sta OFF
        lda OFF2+1
        sbc #0
        sta OFF+1
        jmp DLSTART
@r:     rts

;=====================================================================
; THE SCREEN
;=====================================================================
; LAY OUT FROM TOPO (NO DRAWING); FIND THE CURSOR.  C=0 FOUND.
FINDCUR: lda TOPO
        sta OFF2
        lda TOPO+1
        sta OFF2+1
        stz CROW
@r:     ldx CROW
        jsr SETLS
        jsr LAYOUT
        jsr INLINE
        bcc @found
        lda LTYPE
        cmp #2
        beq @no
        lda NXT
        sta OFF2
        lda NXT+1
        sta OFF2+1
        inc CROW
        lda CROW
        cmp ROWS
        bne @r
@no:    sec
        rts
@found: sec                 ; COLUMN = CUR - LINE START
        lda CUR
        sbc OFF2
        sta CCOL
        clc
        rts
SETLS:  txa                 ; LSTART[X] = OFF2
        asl a
        tax
        lda OFF2
        sta LSTART,x
        lda OFF2+1
        sta LSTART+1,x
        rts
; IS THE CURSOR ON THE LINE JUST LAID OUT?  C=0 YES
INLINE: lda CUR+1           ; CUR < OFF2: NO
        cmp OFF2+1
        bne @1
        lda CUR
        cmp OFF2
@1:     bcc @no
        lda LTYPE
        cmp #2
        beq @yes            ; LAST LINE: ANYWHERE TO THE END
        lda CUR+1           ; CUR < NXT: YES (A CR LINE HOLDS ITS CR)
        cmp NXT+1
        bne @2
        lda CUR
        cmp NXT
@2:     bcs @no
@yes:   clc
        rts
@no:    sec
        rts

; MAKE SURE THE CURSOR IS ON THE SCREEN (MOVING TOPO)
SHOWCUR: jsr FINDCUR
        bcs :+
        jmp @r
:
        lda CUR+1           ; ABOVE THE SCREEN?
        cmp TOPO+1
        bne @c
        lda CUR
        cmp TOPO
@c:     bcs @below
        lda CUR             ; YES: ITS LINE AT THE TOP
        sta OFF
        lda CUR+1
        sta OFF+1
        jsr DLSTART
        jmp @set
@below: lda #3              ; JUST BELOW: SCROLL A LINE OR THREE
        sta RDIF
@s:     lda LSTART+2
        sta TOPO
        lda LSTART+3
        sta TOPO+1
        jsr FINDCUR
        bcc @r
        dec RDIF
        bne @s
        lda CUR             ; FAR AWAY: ITS LINE TWO-THIRDS DOWN
        sta OFF
        lda CUR+1
        sta OFF+1
        jsr DLSTART
        lda ROWS
        asl a
        sta RDIF
        lda #0
        ldx #3
        lda RDIF            ; (ROWS*2)/3
@d3:    ldx #0
@dl:    cmp #3
        bcc @dd
        sbc #3
        inx
        bra @dl
@dd:    stx RDIF
@b:     lda RDIF
        beq @set
        jsr DLPREV
        dec RDIF
        bra @b
@set:   lda OFF2
        sta TOPO
        lda OFF2+1
        sta TOPO+1
        jsr FINDCUR
@r:     rts

; FORGET WHAT IS ON THE SCREEN (SO EVERYTHING IS DRAWN AGAIN)
FULLSCR: jsr CLS
        lda #<SHADOW
        sta GP
        lda #>SHADOW
        sta GP+1
        ldx NLINES
@r:     ldy #SW-1
        lda #' '
@c:     sta (GP),y
        dey
        bpl @c
        clc
        lda GP
        adc #SW
        sta GP
        bcc @n
        inc GP+1
@n:     dex
        bne @r
        ldx #MAXLN-1
@z:     stz SHLEN,x
        dex
        bpl @z
        stz INREV
        rts
; SHADOW ROW A IS UNKNOWN (A PROMPT WAS THERE)
DIRTYROW: pha
        jsr ROWADR
        plx
        lda #SW
        sta SHLEN,x
        ldy #SW-1
        lda #$01
@c:     sta (GP),y
        dey
        bpl @c
        rts
; GP = SHADOW ROW A
ROWADR: tax
        lda ROWLO,x
        sta GP
        lda ROWHI,x
        sta GP+1
        rts
ROWLO:
        .repeat MAXLN, I
        .byte <(SHADOW+I*SW)
        .endrepeat
ROWHI:
        .repeat MAXLN, I
        .byte >(SHADOW+I*SW)
        .endrepeat

; DRAW EVERYTHING THAT HAS CHANGED
REDRAW: jsr SHOWCUR
        jsr STATUSROW       ; ROW 0
        lda #0
        jsr PUTROW
        lda TOPO            ; THE TEXT ROWS
        sta OFF2
        lda TOPO+1
        sta OFF2+1
        stz RDIF            ; 1 = PAST THE END
        lda #1
        sta DROW
@r:     lda RDIF
        beq @lay
        stz RLEN            ; (EMPTY ROW)
        bra @put
@lay:   jsr LAYOUT
        jsr MARKBLK
        lda LTYPE
        cmp #2
        bne @put
        lda #1
        sta RDIF
@put:   lda DROW
        jsr PUTROW
        lda NXT
        sta OFF2
        lda NXT+1
        sta OFF2+1
        inc DROW
        lda DROW
        cmp NLINES
        bcc @r
        jsr REVOFF0
        ldx CROW            ; THE CURSOR
        inx
        inx
        ldy CCOL
        iny
        jmp GOTO
        .bss
DROW:   .res 1
INREV:  .res 1
        .code

; BLOCK: SET BIT 7 OF EACH CHARACTER OF THE ROW INSIDE THE BLOCK
MARKBLK: lda BLKON
        beq @r
        lda BLKB+1
        cmp #$FF
        beq @r
        lda BLKE+1
        cmp #$FF
        beq @r
        ldx #0
@c:     cpx RLEN
        beq @r
        txa                 ; OFFSET = OFF2 + X
        clc
        adc OFF2
        sta TMP
        lda OFF2+1
        adc #0
        sta TMP+1
        cmp BLKB+1          ; >= BLKB?
        bne @1
        lda TMP
        cmp BLKB
@1:     bcc @n
        lda TMP+1           ; < BLKE?
        cmp BLKE+1
        bne @2
        lda TMP
        cmp BLKE
@2:     bcs @n
        lda ROWBUF,x
        ora #$80
        sta ROWBUF,x
@n:     inx
        bra @c
@r:     rts

; SEND ROW A (ROWBUF, RLEN; BIT 7 = REVERSE) WHERE IT DIFFERS
PUTROW: sta PROW            ; (ONLY UP TO M = MAX(RLEN, SHLEN) MATTERS:
        tax                 ;  BEYOND THAT BOTH ARE SPACES)
        lda SHLEN,x
        cmp RLEN
        bcs @m
        lda RLEN
@m:     sta PM
        ldx RLEN            ; PAD WITH SPACES TO M
        cpx PM
        bcs @1
        lda #' '
@p:     sta ROWBUF,x
        inx
        cpx PM
        bcc @p
@1:     lda PROW
        jsr ROWADR
        ldy #0              ; FIRST DIFFERENCE
        cpy PM
        beq @same
@f:     lda ROWBUF,y
        cmp (GP),y
        bne @df
        iny
        cpy PM
        bne @f
@same:  rts                 ; SAME
@df:    sty PFIRST
        ldy PM              ; LAST DIFFERENCE
@l:     dey
        lda ROWBUF,y
        cmp (GP),y
        beq @l
        sty PLAST
        ldy RLEN            ; LAST NON-BLANK OF THE NEW ROW
@nb:    dey
        cpy #$FF
        beq @nf
        lda ROWBUF,y
        cmp #' '
        beq @nb
@nf:    sty PNB
        iny
        tya
        ldx PROW
        sta SHLEN,x
        lda PROW            ; CURSOR TO THE FIRST DIFFERENCE
        inc a
        tax
        lda PFIRST
        inc a
        tay
        jsr GOTO
        ldy PFIRST
@o:     tya                 ; PAST THE LAST NON-BLANK AND THE REST IS
        cmp PNB             ; DIFFERENT: CLEAR TO THE END OF THE LINE
        beq @o2
        bcc @o2
        jsr REVOFF0
        jsr CLEOL
        ldy PFIRST
@cl:    cpy PM              ; (THE COPY NOW HOLDS THE NEW ROW)
        bcs @r
        lda ROWBUF,y
        sta (GP),y
        iny
        bra @cl
@r:     rts
@o2:    lda ROWBUF,y
        sta (GP),y
        pha
        and #$80
        cmp INREV
        beq @a
        sta INREV
        cmp #0
        beq @off
        jsr REVON
        bra @a
@off:   jsr REVOFF
@a:     pla
        and #$7F
        jsr OUTC
        iny
        cpy PLAST
        beq @o
        bcc @o
        rts
        .bss
PROW:   .res 1
PFIRST: .res 1
PLAST:  .res 1
PNB:    .res 1
PM:     .res 1
SHLEN:  .res MAXLN          ; HOW MUCH OF EACH SCREEN ROW IS NOT BLANK
        .code
REVOFF0: lda INREV
        beq @r
        stz INREV
        jmp REVOFF
@r:     rts

; THE STATUS ROW, IN REVERSE, INTO ROWBUF
STATUSROW:
        stz RLEN
        lda MSGP+1          ; A MESSAGE?
        beq @st
        lda MSGP
        sta MP
        lda MSGP+1
        sta MP+1
        jsr RSTR
        jmp @fill
@st:    lda #' '
        jsr RCH
        lda FNAME           ; NAME
        bne @nm
        lda #<M_NONAME
        sta MP
        lda #>M_NONAME
        sta MP+1
        jsr RSTR
        bra @ty
@nm:    lda #<FNAME
        sta MP
        lda #>FNAME
        sta MP+1
        jsr RSTR
@ty:    lda MODF
        beq @t2
        lda #'*'
        jsr RCH
@t2:    lda #' '
        jsr RCH
        lda #' '
        jsr RCH
        lda FTYPE           ; TYPE
        asl a
        tax
        lda TYPNAMES,x
        sta MP
        lda TYPNAMES+1,x
        sta MP+1
        jsr RSTR
        lda #<M_LINE
        sta MP
        lda #>M_LINE
        sta MP+1
        jsr RSTR
        lda CURLINE         ; LINE (1-BASED)
        clc
        adc #1
        sta TMP
        lda CURLINE+1
        adc #0
        sta TMP+1
        jsr RNUM
        lda #<M_COL
        sta MP
        lda #>M_COL
        sta MP+1
        jsr RSTR
        lda CUR             ; COLUMN IN THE HARD LINE
        sta OFF
        lda CUR+1
        sta OFF+1
        jsr PARSTART
        sec
        lda CUR
        sbc OFF
        sta TMP
        lda CUR+1
        sbc OFF+1
        sta TMP+1
        inc TMP
        bne @c1
        inc TMP+1
@c1:    jsr RNUM
        lda #' '
        jsr RCH
        lda #' '
        jsr RCH
        lda #<M_INS
        ldy #>M_INS
        ldx INSM
        bne @i
        lda #<M_OVR
        ldy #>M_OVR
@i:     sta MP
        sty MP+1
        jsr RSTR
        lda #<M_FREE
        sta MP
        lda #>M_FREE
        sta MP+1
        jsr RSTR
        sec
        lda GE
        sbc GS
        sta TMP
        lda GE+1
        sbc GS+1
        sta TMP+1
        jsr RNUM
        lda #<M_HLP
        sta MP
        lda #>M_HLP
        sta MP+1
        jsr RSTR
@fill:  ldx RLEN            ; ALL OF IT IN REVERSE
@f:     cpx #SW
        bcs @rv
        lda #' '
        sta ROWBUF,x
        inx
        bra @f
@rv:    ldx #SW-1
@v:     lda ROWBUF,x
        ora #$80
        sta ROWBUF,x
        dex
        bpl @v
        lda #SW
        sta RLEN
        rts
M_NONAME: .byte "(no name)",0
M_LINE: .byte "  Line ",0
M_COL:  .byte "  Col ",0
M_INS:  .byte "Insert",0
M_OVR:  .byte "Over  ",0
M_FREE: .byte "  Free ",0
M_HLP:  .byte "   ^J help",0
TYPNAMES: .word T_TEXT, T_ASM, T_BAS
T_TEXT: .byte "Document",0
T_ASM:  .byte "Assembler",0
T_BAS:  .byte "BASIC",0

; ADD TO ROWBUF: A CHARACTER, A STRING AT (MP), A NUMBER (TMP)
RCH:    ldx RLEN
        cpx #SW
        bcs @r
        sta ROWBUF,x
        inc RLEN
@r:     rts
RSTR:   ldy #0
@l:     lda (MP),y
        beq @r
        phy
        jsr RCH
        ply
        iny
        bra @l
@r:     rts
RNUM:   jsr NUMSTR          ; TMP -> NUMB (TEXT)
        ldx #0
@l:     lda NUMB,x
        beq @r
        phx
        jsr RCH
        plx
        inx
        bra @l
@r:     rts
; 16-BIT TMP -> DECIMAL TEXT IN NUMB (0-ENDED)
NUMSTR: ldy #0
        ldx #4              ; 10000, 1000, 100, 10, 1
        stz NZ
@p:     lda #0
        sta NDIG
@s:     lda TMP+1           ; TMP >= POWER?
        cmp P10H,x
        bne @c
        lda TMP
        cmp P10L,x
@c:     bcc @dg
        lda TMP
        sbc P10L,x
        sta TMP
        lda TMP+1
        sbc P10H,x
        sta TMP+1
        inc NDIG
        bra @s
@dg:    lda NDIG
        ora NZ
        bne @put
        cpx #0
        bne @nx
@put:   lda NDIG
        ora #'0'
        sta NUMB,y
        iny
        sta NZ
@nx:    dex
        bpl @p
        lda #0
        sta NUMB,y
        rts
P10L:   .byte <1,<10,<100,<1000,<10000
P10H:   .byte >1,>10,>100,>1000,>10000
        .bss
NUMB:   .res 7
NZ:     .res 1
NDIG:   .res 1
        .code

; PRINT A (0-255) IN DECIMAL (FOR GOTO)
PRDEC:  ldx #0
        stz NZ
@h:     cmp #100
        bcc @h2
        sbc #100
        inx
        bra @h
@h2:    jsr @dig
        ldx #0
@t:     cmp #10
        bcc @t2
        sbc #10
        inx
        bra @t
@t2:    jsr @dig
        tax
        inc NZ
@dig:   pha
        txa
        ora NZ
        beq @z
        txa
        ora #'0'
        jsr OUTC
        inc NZ
@z:     pla
        rts

;=====================================================================
; A ONE-LINE QUESTION ON THE STATUS ROW.  TEXT AFTER THE JSR.
; THE ANSWER IS IN LBUF/LLEN (0-ENDED).  C=1 IF ESC.
; LBUF MAY ALREADY HOLD A SUGGESTION (LLEN > 0).
;=====================================================================
ASK:    pla
        sta MP
        pla
        sta MP+1
        inc MP
        bne @1
        inc MP+1
@1:     lda MP
        sta ASKP
        lda MP+1
        sta ASKP+1
@e:     lda (MP)            ; RETURN PAST THE TEXT
        beq @2
        inc MP
        bne @e
        inc MP+1
        bra @e
@2:     lda MP+1
        pha
        lda MP
        pha
ASKAGAIN:
        ldx #1
        ldy #1
        jsr GOTO
        jsr REVON
        lda ASKP
        sta MP
        lda ASKP+1
        sta MP+1
        jsr PRMP
        jsr REVOFF
        jsr SPACE
        ldx #0
@sh:    cpx LLEN
        beq @sd
        lda LBUF,x
        jsr OUTC
        inx
        bra @sh
@sd:    jsr CLEOL
        lda #0
        jsr DIRTYROW
@k:     jsr GETKEY
        cmp #$0D
        beq @ok
        cmp #$1B
        beq @esc
        cmp #$08
        beq @bs
        cmp #$15            ; ^U CLEARS
        beq @clr
        cmp #' '
        bcc @k
        cmp #$80
        bcs @k
        ldx LLEN
        cpx #60
        bcs @k
        sta LBUF,x
        inc LLEN
        jsr OUTC
        bra @k
@bs:    lda LLEN
        beq @k
        dec LLEN
        lda #8
        jsr OUTC
        jsr SPACE
        lda #8
        jsr OUTC
        bra @k
@clr:   stz LLEN
        bra ASKAGAIN
@ok:    ldx LLEN
        stz LBUF,x
        clc
        rts
@esc:   ldx LLEN
        stz LBUF,x
        sec
        rts
        .bss
ASKP:   .res 2
        .code

; ASK (TEXT AFTER THE JSR) FOR ONE KEY ON THE STATUS ROW -> A (UPPER)
ASKKEY: pla
        sta MP
        pla
        sta MP+1
        inc MP
        bne @1
        inc MP+1
@1:     lda MP
        sta ASKP
        lda MP+1
        sta ASKP+1
@e:     lda (MP)
        beq @2
        inc MP
        bne @e
        inc MP+1
        bra @e
@2:     lda MP+1
        pha
        lda MP
        pha
        ldx #1
        ldy #1
        jsr GOTO
        jsr REVON
        lda ASKP
        sta MP
        lda ASKP+1
        sta MP+1
        jsr PRMP
        jsr REVOFF
        jsr CLEOL
        lda #0
        jsr DIRTYROW
        jsr RAWKEY
        jmp UPPER

;=====================================================================
; THE MAIN LOOP
;=====================================================================
MAIN:   ldx MAINSP
        txs
        jsr KEYHIT          ; ANOTHER KEY ALREADY?  THEN DRAW LATER
        bcc @dr
        sta PBK
        bra @gk
@dr:    jsr REDRAW
@gk:    jsr GETKEY
        pha
        stz MSGP+1          ; A KEY CLEARS A MESSAGE
        pla
        cmp #K_LF
        bne @1
        jmp C_LEFT
@1:     cmp #K_RT
        bne @2
        jmp C_RIGHT
@2:     cmp #K_UP
        bne @3
        jmp C_UP
@3:     cmp #K_DN
        bne @4
        jmp C_DOWN
@4:     cmp #$0D
        bne @5
        jmp C_RET
@5:     cmp #$08
        bne @6
        jmp C_BS
@6:     cmp #' '
        bcc @ctl
        cmp #$80
        bcs MAIN
        jmp C_TYPE
@ctl:   cmp #$1B            ; CONTROL KEYS: ^A..^Z
        bcs CTLNO
        asl a
        tax
        lda CTLTAB+1,x
        beq CTLNO
        pha
        lda CTLTAB,x
        pha
        rts
CTLTAB: .word 0             ; ^@
        .word C_WLEFT-1     ; ^A WORD LEFT
        .word 0             ; ^B
        .word C_PGDN-1      ; ^C PAGE DOWN
        .word 0             ; ^D (RIGHT)
        .word 0             ; ^E (UP)
        .word C_WRIGHT-1    ; ^F WORD RIGHT
        .word C_DEL-1       ; ^G DELETE CHARACTER
        .word 0             ; ^H (BACKSPACE)
        .word 0             ; ^I
        .word C_HELP-1      ; ^J HELP
        .word C_K-1         ; ^K FILE / BLOCK
        .word C_AGAIN-1     ; ^L FIND AGAIN
        .word 0             ; ^M (RETURN)
        .word C_SPLIT-1     ; ^N SPLIT THE LINE
        .word 0             ; ^O
        .word 0             ; ^P
        .word C_Q-1         ; ^Q QUICK
        .word C_PGUP-1      ; ^R PAGE UP
        .word 0             ; ^S (LEFT)
        .word C_DELW-1      ; ^T DELETE WORD
        .word 0             ; ^U
        .word C_INSM-1      ; ^V INSERT / OVERWRITE
        .word 0             ; ^W
        .word 0             ; ^X (DOWN)
        .word C_DELL-1      ; ^Y DELETE LINE
        .word 0             ; ^Z
CTLNO:  jmp MAIN

; ---- MOVING ----------------------------------------------------------
GOOFF:  jsr MOVETO          ; CURSOR TO OFF, REMEMBER THE COLUMN
        jsr FINDCOL
        jmp MAIN
FINDCOL: stz DESCV          ; THE COLUMN FOR UP/DOWN IS WORKED OUT AGAIN
        rts
        .bss
DESCV:  .res 1
        .code
; OFF2 = START OF THE CURSOR'S SCREEN LINE; SET DESCOL IF NEEDED
CURLS:  jsr OFFCUR
        jsr DLSTART
        lda DESCV
        bne @r
        inc DESCV
        sec
        lda CUR
        sbc OFF2
        sta DESCOL
@r:     rts

C_LEFT: lda CUR
        ora CUR+1
        beq @r
        jsr OFFCUR
        jsr OFFDEC
        jmp GOOFF
@r:     jmp MAIN
C_RIGHT: jsr ATEND
        bcs @r
        jsr OFFCUR
        jsr OFFINC
        jmp GOOFF
@r:     jmp MAIN
OFFCUR: lda CUR
        sta OFF
        lda CUR+1
        sta OFF+1
        rts
OFFINC: inc OFF
        bne @r
        inc OFF+1
@r:     rts
OFFDEC: lda OFF
        bne @1
        dec OFF+1
@1:     dec OFF
        rts
; C=1 IF THE CURSOR IS AT THE END OF THE TEXT
ATEND:  lda CUR
        cmp TLEN
        bne @n
        lda CUR+1
        cmp TLEN+1
        bne @n
        sec
        rts
@n:     clc
        rts

C_UP:   jsr LINEUP
        jmp MAIN
C_DOWN: jsr LINEDN
        jmp MAIN
; UP ONE SCREEN LINE, KEEPING THE COLUMN.  C=1 IF AT THE TOP
LINEUP: jsr CURLS
        lda OFF2
        ora OFF2+1
        bne @1
        sec
        rts
@1:     jsr DLPREV
        bra TOCOL
; DOWN ONE SCREEN LINE.  C=1 IF AT THE BOTTOM
LINEDN: jsr CURLS
        jsr LAYOUT
        lda LTYPE
        cmp #2
        bne @1
        sec
        rts
@1:     lda NXT
        sta OFF2
        lda NXT+1
        sta OFF2+1
; CURSOR TO COLUMN DESCOL OF THE SCREEN LINE AT OFF2
TOCOL:  jsr LAYOUT
        lda RLEN            ; LAST COLUMN ALLOWED
        ldx LTYPE
        cpx #1
        bne @c
        dec a               ; (A WRAPPED LINE: NOT PAST ITS END)
@c:     cmp DESCOL
        bcc @s
        lda DESCOL
@s:     clc
        adc OFF2
        sta OFF
        lda OFF2+1
        adc #0
        sta OFF+1
        jsr MOVETO
        clc
        rts

; PAGES: THE TEXT MOVES A SCREEN, THE CURSOR STAYS ON ITS ROW
C_PGDN: jsr PGPREP
@l:     lda TOPO
        sta OFF2
        lda TOPO+1
        sta OFF2+1
        jsr LAYOUT
        lda LTYPE
        cmp #2
        beq @e
        lda NXT
        sta TOPO
        lda NXT+1
        sta TOPO+1
        inc PGMOV
        dec RDIF
        bne @l
@e:     lda PGMOV
        bne PGROW
@lst:   jsr LINEDN          ; THE END WAS ON THE SCREEN: GO TO IT
        bcc @lst
        jmp MAIN
C_PGUP: jsr PGPREP
@l:     lda TOPO
        ora TOPO+1
        beq @e
        lda TOPO
        sta OFF2
        lda TOPO+1
        sta OFF2+1
        jsr DLPREV
        lda OFF2
        sta TOPO
        lda OFF2+1
        sta TOPO+1
        inc PGMOV
        dec RDIF
        bne @l
@e:     lda PGMOV
        bne PGROW
@fst:   jsr LINEUP          ; ALREADY AT THE TOP: TO THE FIRST LINE
        bcc @fst
        jmp MAIN
PGPREP: jsr SHOWCUR         ; CROW = THE CURSOR'S ROW
        jsr CURLS           ; (DESCOL)
        lda ROWS
        dec a
        sta RDIF
        stz PGMOV
        rts
PGROW:  lda TOPO            ; THE LINE ON ROW CROW, AT COLUMN DESCOL
        sta OFF2
        lda TOPO+1
        sta OFF2+1
        lda CROW
        sta RDIF
@l:     lda RDIF
        beq @t
        jsr LAYOUT
        lda LTYPE
        cmp #2
        beq @t
        lda NXT
        sta OFF2
        lda NXT+1
        sta OFF2+1
        dec RDIF
        bra @l
@t:     jsr TOCOL
        jmp MAIN
        .bss
PGMOV:  .res 1
        .code

; WORDS: LETTERS, DIGITS AND OTHERS; SPACES AND CR SEPARATE THEM
ISSEP:  cmp #' '            ; Z=1 FOR A SPACE OR CR
        beq @r
        cmp #CR
@r:     rts
C_WRIGHT:
        jsr OFFCUR
@a:     jsr CHARAT          ; PAST THE REST OF THIS WORD
        bcs @g
        jsr ISSEP
        beq @b
        jsr OFFINC
        bra @a
@b:     jsr CHARAT          ; AND THE SPACES AFTER IT
        bcs @g
        jsr ISSEP
        bne @g
        jsr OFFINC
        bra @b
@g:     jmp GOOFF
C_WLEFT:
        jsr OFFCUR
@a:     lda OFF             ; BACK OVER SPACES
        ora OFF+1
        beq @g
        jsr OFFDEC
        jsr CHARAT
        jsr ISSEP
        beq @a
@b:     lda OFF             ; THEN TO THE START OF THE WORD
        ora OFF+1
        beq @g
        jsr OFFDEC
        jsr CHARAT
        jsr ISSEP
        bne @b
        jsr OFFINC
@g:     jmp GOOFF

; ---- TYPING ----------------------------------------------------------
C_TYPE: pha
        lda INSM            ; OVERWRITE: REPLACE (BUT NOT A CR)
        bne @ins
        jsr ATEND
        bcs @ins
        jsr OFFCUR
        jsr CHARAT
        cmp #CR
        beq @ins
        jsr DELFWD
@ins:   pla
        jsr INSCH
        bcs FULL
        jsr FINDCOL
        jmp MAIN
FULL:   lda #<M_FULL
        ldy #>M_FULL
        jsr SETMSG
        jmp MAIN
M_FULL: .byte "THE TEXT IS FULL",0

C_RET:  lda #CR
        jsr INSCH
        bcs FULL
        stz DESCV
        jmp MAIN
C_SPLIT: lda #CR            ; ^N: A CR AFTER THE CURSOR
        jsr INSCH
        bcs FULL
        jsr OFFCUR
        jsr OFFDEC
        jmp GOOFF
C_BS:   jsr DELBACK
        jsr FINDCOL
        jmp MAIN
C_DEL:  jsr DELFWD
        jmp MAIN
C_INSM: lda INSM
        eor #1
        sta INSM
        jmp MAIN
C_DELW: jsr OFFCUR          ; ^T: THE WORD (AND SPACES) TO THE RIGHT
        jsr CHARAT
        bcs @e
        cmp #CR
        bne @w
        jsr DELFWD          ; AT A CR: JOIN THE LINES
        bra @e
@w:     jsr ISSEP
        beq @sp
@a:     jsr OFFCUR
        jsr CHARAT
        bcs @e
        jsr ISSEP
        beq @sp
        jsr DELFWD
        bra @a
@sp:    jsr OFFCUR
        jsr CHARAT
        bcs @e
        cmp #' '
        bne @e
        jsr DELFWD
        bra @sp
@e:     jmp MAIN
C_DELL: jsr OFFCUR          ; ^Y: THE WHOLE HARD LINE
        jsr PARSTART
        jsr MOVETO
@d:     jsr DELFWD
        bcs @e
        cmp #CR
        bne @d
@e:     stz DESCV
        jmp MAIN

; ---- ^Q QUICK MOVES -----------------------------------------------------
C_Q:    jsr ASKKEY
        .byte "^Q  S/D line start/end  R/C top/end  F find  A replace  B/K block",0
        and #$1F            ; (^S AND S THE SAME)
        ora #$40
        cmp #'S'
        bne @1
        jsr OFFCUR
        jsr PARSTART
        jmp GOOFF
@1:     cmp #'D'
        bne @2
        jsr OFFCUR
@d:     jsr CHARAT
        bcs @dg
        cmp #CR
        beq @dg
        jsr OFFINC
        bra @d
@dg:    jmp GOOFF
@2:     cmp #'R'
        bne @3
        stz OFF
        stz OFF+1
        jmp GOOFF
@3:     cmp #'C'
        bne @4
        lda TLEN
        sta OFF
        lda TLEN+1
        sta OFF+1
        jmp GOOFF
@4:     cmp #'F'
        bne @5
        jmp C_FIND
@5:     cmp #'A'
        bne @6
        jmp C_REPL
@6:     cmp #'B'
        bne @7
        lda BLKB+1
        cmp #$FF
        beq @x
        lda BLKB
        sta OFF
        lda BLKB+1
        sta OFF+1
        jmp GOOFF
@7:     cmp #'K'
        bne @x
        lda BLKE+1
        cmp #$FF
        beq @x
        lda BLKE
        sta OFF
        lda BLKE+1
        sta OFF+1
        jmp GOOFF
@x:     jmp MAIN

; ---- ^K FILES AND BLOCKS ------------------------------------------------
C_K:    jsr ASKKEY
        .byte "^K S save X exit Q quit L load R read T type P print F files Z size B K C V Y H",0
        and #$1F
        ora #$40
        ldx #0
@f:     ldy KTAB,x
        beq @x
        cmp KTAB,x
        beq @hit
        inx
        inx
        inx
        bra @f
@hit:   lda KTAB+2,x
        pha
        lda KTAB+1,x
        pha
        rts
@x:     jmp MAIN
KTAB:   .byte 'S'
        .word K_SAVE-1
        .byte 'X'
        .word K_EXIT-1
        .byte 'D'
        .word K_EXIT-1
        .byte 'Q'
        .word K_QUIT-1
        .byte 'L'
        .word K_LOAD-1
        .byte 'O'
        .word K_LOAD-1
        .byte 'R'
        .word K_READ-1
        .byte 'T'
        .word K_TYPE-1
        .byte 'P'
        .word K_PRINT-1
        .byte 'F'
        .word K_FILES-1
        .byte 'B'
        .word K_BEGIN-1
        .byte 'K'
        .word K_END-1
        .byte 'C'
        .word K_COPY-1
        .byte 'V'
        .word K_MOVE-1
        .byte 'Y'
        .word K_BDEL-1
        .byte 'H'
        .word K_HIDE-1
        .byte 'Z'
        .word K_SIZE-1
        .byte 0

; CHANGES WOULD BE LOST: ASK.  C=1 TO STOP
SURELOSE:
        lda MODF
        bne @a
        clc
        rts
@a:     jsr ASKKEY
        .byte "The text has changed and is not saved. Lose the changes? (Y/N)",0
        cmp #'Y'
        beq @y
        sec
        rts
@y:     clc
        rts

K_QUIT: jsr SURELOSE
        bcs @x
        jmp QUIT
@x:     jmp MAIN
K_EXIT: jsr SAVEDOC
        jmp QUIT
K_SAVE: jsr SAVEDOC
        lda #<M_SAVED
        ldy #>M_SAVED
        jsr SETMSG
        jmp MAIN
M_SAVED: .byte "SAVED",0
K_TYPE: jsr ASKKEY
        .byte "File type: D document (word wrap), A assembler, B BASIC",0
        ldx #0
        cmp #'D'
        beq @s
        inx
        cmp #'A'
        beq @s
        inx
        cmp #'B'
        bne @x
@s:     stx FTYPE
        lda #1              ; ONLY DOCUMENTS WRAP AT WORDS
        cpx #0
        beq @w
        lda #0
@w:     sta WWRAP
        lda #$3A            ; THE USUAL PLACES
        sta FBASE
        cpx #1
        bne @b
        lda #$32
        sta FBASE
@b:     lda #1
        sta MODF
        jsr FULLSCR
@x:     jmp MAIN
K_FILES: jsr CLS            ; THE DOS DIRECTORY
        lda #<DICMD
        sta MP
        lda #>DICMD
        sta MP+1
        jsr CMDSTART
        jsr DOSCALL
        jsr PRS
        .byte 13,10,"Press any key",0
        jsr GETKEY
        jsr FULLSCR
        jmp MAIN
DICMD:  .byte "DI",13,0

; ^KZ: SCREEN LINES (SAVE THE PROGRAM AFTERWARDS TO KEEP IT)
K_SIZE: stz LLEN
        jsr ASK
        .byte "Screen lines (10-32, 24 for PuTTY, 32 for the FPGA screen):",0
        bcs @x
        stz TI
        ldx #0
@c:     lda LBUF,x
        beq @e
        sta LB2,x
        inx
        bra @c
@e:     stx LBL
        jsr DOTNUM
        lda TMP
        cmp #10
        bcc @x
        cmp #MAXLN+1
        bcs @x
        sta NLDEF
        sta NLINES
        dec a
        sta ROWS
        stz TOPO
        stz TOPO+1
        jsr FULLSCR
@x:     jmp MAIN

; ---- HELP ---------------------------------------------------------------
C_HELP: jsr CLS
        lda #<HELPTXT
        sta GP
        lda #>HELPTXT
        sta GP+1
@l:     lda (GP)
        beq @e
        cmp #$0A
        bne @c
        lda #$0D
        jsr OUTC
        lda #$0A
@c:     jsr OUTC
        inc GP
        bne @l
        inc GP+1
        bra @l
@e:     jsr GETKEY
        jsr FULLSCR
        jmp MAIN
HELPTXT:
        .byte "WP65 KEYS  (^ = CTRL)",$0A,$0A
        .byte "Move   arrows or ^E ^X ^S ^D   ^A ^F word   ^R ^C page",$0A
        .byte "       ^QS ^QD line start/end   ^QR ^QC top/end of the text",$0A
        .byte "Edit   type to insert (^V insert/overwrite)   RETURN new line",$0A
        .byte "       BS delete left   ^G delete   ^T delete word   ^Y delete line",$0A
        .byte "       ^N split the line here",$0A
        .byte "Find   ^QF find   ^QA find and replace   ^L again",$0A
        .byte "Block  ^KB begin  ^KK end  ^KC copy  ^KV move  ^KY delete  ^KH hide",$0A
        .byte "       ^QB ^QK go to the begin/end of the block",$0A
        .byte "Files  ^KL load  ^KR read a file in here  ^KS save  ^KX save+exit",$0A
        .byte "       ^KQ quit  ^KT type: Document / Assembler / BASIC  ^KF files",$0A
        .byte "       ^KZ screen lines (24 or 32)",$0A
        .byte "Print  ^KP preview on the screen, or print",$0A,$0A
        .byte "Print commands (on their own line in a document):",$0A
        .byte "  .LM n  .RM n  left/right margin    .PL n  page length",$0A
        .byte "  .HE text  .FO text  header/footer (# = page number)",$0A
        .byte "  .CE  centre the next line   .JU / .NJ  justify on/off",$0A
        .byte "  .PA  new page   .SP n  blank lines   .LS n  line spacing",$0A,$0A
        .byte "Press any key",0

        .include "WPFILE.S"
        .include "WPEXTRA.S"

        .import __BSS_RUN__, __BSS_SIZE__
        .assert __BSS_RUN__+__BSS_SIZE__ <= TRKBUF, lderror, "PROGRAM TOO BIG FOR TRKBUF"
