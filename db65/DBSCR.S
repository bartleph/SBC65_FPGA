;=====================================================================
; DBSCR.S - FULL-SCREEN APPEND / EDIT FORM AND BROWSE FOR DB65
;=====================================================================

DREC    = RECBUF2           ; THE FORM'S TEXT, FIELD BY FIELD ($A800-$AFFF)
FTOP    = 3                 ; FIRST FORM LINE
FCOL    = 14                ; WHERE THE VALUES START

        .bss
FF:     .res 1              ; CURRENT FIELD
FPOS:   .res 1              ; CURSOR IN IT
FCHG:   .res 1              ; THE RECORD HAS BEEN CHANGED
FMODE:  .res 1              ; 0 EDIT, 1 APPEND
FKEY:   .res 1              ; HOW THE FORM WAS LEFT
FTYPED: .res 1              ; A KEY HAS BEEN TYPED IN THIS FIELD
DOFS:   .res MAXFLD*2       ; WHERE EACH FIELD'S TEXT IS IN DREC
DWID:   .res MAXFLD         ; AND HOW WIDE IT IS ON THE FORM
FMSG:   .res 1
TOPREC: .res 2              ; BROWSE: FIRST RECORD ON THE SCREEN
CURR:   .res 2              ;         THE HIGHLIGHTED ONE
LFLD:   .res 1              ;         FIRST FIELD SHOWN
BROWS:  .res 1              ;         RECORDS ON THE SCREEN
BCOLS:  .res 1              ;         FIELDS ON THE SCREEN
        .code

; FORM KEYS
K_SAVE  = $17               ; ^W
K_NEXTR = $03               ; ^C
K_PREVR = $12               ; ^R
K_DELM  = $15               ; ^U
K_DELC  = $07               ; ^G
K_CLR   = $19               ; ^Y

;---------------------------------------------------------------------
; APPEND [BLANK]
;---------------------------------------------------------------------
H_APPEND:
        jsr NEEDOPEN
        lda #<KW_BLANK
        ldy #>KW_BLANK
        jsr KW
        bcs @form
        jsr NEEDEND
        jsr ROOM
        jsr BLANKREC
        jsr ADDREC
        jsr FLUSHALL
        jsr PRS
        .byte "Record ",0
        jmp SAYREC
@form:  jsr NEEDEND
        lda #1
        sta FMODE
@new:   jsr ROOM
        jsr BLANKREC
        clc                 ; RECNO = NREC + 1 (NOT COUNTED YET)
        lda NREC
        adc #1
        sta RECNO
        lda NREC+1
        adc #0
        sta RECNO+1
        jsr FORM
        lda FKEY
        cmp #$1B            ; ESC: DROP IT
        beq @end
        lda FCHG            ; NOTHING TYPED: STOP APPENDING
        beq @end
        jsr ADDREC
        lda FKEY
        cmp #K_SAVE
        beq @end
        bra @new
@end:   jsr FLUSHALL
        lda NREC            ; STAY ON THE LAST REAL RECORD
        ora NREC+1
        bne @last
        jsr GOTOP
        jmp ENDSCR
@last:  lda NREC+1
        cmp RECNO+1
        bne @c
        lda NREC
        cmp RECNO
@c:     bcs @here
        lda NREC
        ldy NREC+1
        jsr SETREC
        jmp ENDSCR
@here:  lda RECNO
        ldy RECNO+1
        jsr SETREC
        jmp ENDSCR

; ROOM FOR ONE MORE?
ROOM:   lda NREC+1
        cmp MAXREC+1
        bne @c
        lda NREC
        cmp MAXREC
@c:     bcs @full
        rts
@full:  jsr ENDSCR2
        lda #<M_FULL
        ldy #>M_FULL
        jmp ERRMSG
M_FULL: .byte "THE FILE IS FULL - CREATE A BIGGER ONE AND COPY (SORT TO)",0

; RECBUF BECOMES RECORD NREC+1
ADDREC: clc
        lda NREC
        adc #1
        sta RECNO
        lda NREC+1
        adc #0
        sta RECNO+1
        lda RECNO
        ldy RECNO+1
        jsr PUTREC
        lda RECNO
        sta NREC
        lda RECNO+1
        sta NREC+1
        lda #1
        sta HDIRTY
        rts
SAYREC: lda RECNO
        sta T16
        lda RECNO+1
        sta T16+1
        jsr PRD16
        jmp CRLF

;---------------------------------------------------------------------
; EDIT [n]
;---------------------------------------------------------------------
H_EDIT: jsr NEEDOPEN
        jsr PEEK
        beq @cur
        jsr C_GOTO
@cur:   lda RECNO
        ora RECNO+1
        bne @go
        lda #<M_RECR
        ldy #>M_RECR
        jmp ERRMSG
@go:    stz FMODE
@form:  jsr FORM
        lda FKEY
        cmp #$1B
        beq @end
        lda FCHG
        beq @nos
        lda RECNO
        ldy RECNO+1
        jsr PUTREC
@nos:   lda FKEY
        cmp #K_PREVR
        beq @prev
        cmp #K_SAVE
        beq @end
        lda RECNO           ; NEXT RECORD (RETURN AT THE END OR ^C)
        cmp NREC
        bne @nx
        lda RECNO+1
        cmp NREC+1
        beq @end
@nx:    inc RECNO
        bne @rd
        inc RECNO+1
        bra @rd
@prev:  lda RECNO
        cmp #1
        bne @pv
        lda RECNO+1
        beq @form           ; ALREADY THE FIRST
@pv:    lda RECNO
        bne @p1
        dec RECNO+1
@p1:    dec RECNO
@rd:    lda RECNO
        ldy RECNO+1
        jsr SETREC
        bra @form
@end:   jsr FLUSHALL
        lda RECNO           ; READ IT BACK (ESC LEAVES IT AS IT WAS)
        ldy RECNO+1
        jsr SETREC
        jmp ENDSCR

ENDSCR: jsr ENDSCR2
        rts
ENDSCR2: jsr REVOFF
        jsr CLS
        stz LCOUNT
        rts

;---------------------------------------------------------------------
; THE FORM: RECBUF IS SHOWN AND EDITED.  ON RETURN FKEY = $1B (ESC,
; RECBUF UNCHANGED), K_SAVE, K_NEXTR, K_PREVR OR $0D (RETURN ON THE
; LAST FIELD).  WITH ANY KEY BUT ESC, RECBUF HOLDS THE NEW RECORD.
;---------------------------------------------------------------------
FORM:   stz FCHG
        stz FF
        stz FTYPED
        stz FPOS
        stz FMSG
        jsr LOADFORM
        jsr DRAWFORM
@k:     jsr FCURSOR
        jsr GETKEY
        pha
        lda FMSG            ; A KEY CLEARS A MESSAGE
        beq @k1
        jsr FHELP
@k1:    pla
        cmp #$1B
        bne @1
        sta FKEY
        rts
@1:     cmp #K_SAVE
        beq @leave
        cmp #K_NEXTR
        beq @leave
        cmp #K_PREVR
        beq @leave
        cmp #K_DELM
        bne @2
        lda RECBUF          ; MARK / UNMARK FOR DELETION
        eor #'*'^' '
        sta RECBUF
        lda #1
        sta FCHG
        jsr FTITLE
        bra @k
@2:     cmp #$0D
        beq @ret
        cmp #K_DN
        beq @down
        cmp #K_UP
        beq @up
        cmp #K_LF
        bne :+
        jmp @left
:
        cmp #K_RT
        bne :+
        jmp @right
:
        cmp #$08
        bne :+
        jmp @bs
:
        cmp #K_DELC
        bne :+
        jmp @delc
:
        cmp #K_CLR
        bne :+
        jmp @clr
:
        cmp #' '
        bcc @k
        cmp #$80
        bcs @k
        jsr FTYPE           ; TYPE A CHARACTER
        bra @k
@leave: sta FKEY
        jsr FVALID          ; THIS FIELD MUST BE RIGHT FIRST
        bcs @k
        jsr SAVEFORM
        bcc :+
        jmp @k
:
        rts
@ret:   lda FF              ; RETURN: NEXT FIELD, OR DONE AT THE LAST
        inc a
        cmp NFLD
        bcc @down
        lda #$0D
        bra @leave
@down:  jsr FVALID
        bcc :+
        jmp @k
:
        lda FF
        inc a
        cmp NFLD
        bcc :+
        jmp @k
:
        sta FF
        stz FTYPED
        stz FPOS
        jmp @k
@up:    jsr FVALID
        bcc :+
        jmp @k
:
        lda FF
        bne :+
        jmp @k
:
        dec FF
        stz FTYPED
        stz FPOS
        jmp @k
@left:  lda FPOS
        beq @lp
        dec FPOS
@lp:    jmp @k
@right: inc FPOS
        ldx FF
        lda FPOS
        cmp DWID,x
        bcc @lp
        dec FPOS
        jmp @down
@bs:    lda FPOS            ; BACKSPACE: BACK ONE AND BLANK IT
        beq @lp
        dec FPOS
        jsr FADDR
        lda #' '
        ldy FPOS
        sta (GP),y
        lda #1
        sta FCHG
        jsr FDRAW
        jmp @k
@delc:  jsr FADDR           ; ^G: DELETE AT THE CURSOR, CLOSE UP
        ldx FF
        ldy FPOS
@dc:    iny
        tya
        cmp DWID,x
        bcs @de
        lda (GP),y
        dey
        sta (GP),y
        iny
        bra @dc
@de:    dey
        lda #' '
        sta (GP),y
        lda #1
        sta FCHG
        jsr FDRAW
        jmp @k
@clr:   jsr FADDR           ; ^Y: BLANK THE FIELD
        ldx FF
        ldy #0
        lda #' '
@cl:    tya
        cmp DWID,x
        bcs @ce
        lda #' '
        sta (GP),y
        iny
        bra @cl
@ce:    stz FPOS
        lda #1
        sta FCHG
        jsr FDRAW
        jmp @k

; A TYPED CHARACTER INTO THE FIELD.  THE FIRST KEY TYPED INTO A
; NUMBER OR DATE FIELD (AT ITS START) CLEARS IT FIRST.
FTYPE:  pha
        ldx FF
        jsr FLDPTR
        ldy #F_TYPE
        lda (FP),y
        cmp #'L'
        bne @1
        pla
        jsr UPPER
        pha
        bra @2
@1:     cmp #'C'
        beq @2
        lda FPOS
        ora FTYPED
        bne @2
        jsr FADDR
        ldx FF
        ldy #0
        lda #' '
@cl:    sta (GP),y
        iny
        pha
        tya
        cmp DWID,x
        pla
        bcc @cl
@2:     lda #1
        sta FTYPED
        jsr FADDR
        pla
        ldy FPOS
        sta (GP),y
        lda #1
        sta FCHG
        jsr FDRAW
        inc FPOS            ; AT THE END: ON TO THE NEXT FIELD
        ldx FF
        lda FPOS
        cmp DWID,x
        bcc @r
        dec FPOS
        jsr FVALID
        bcs @r
        lda FF
        inc a
        cmp NFLD
        bcs @r
        sta FF
        stz FTYPED
        stz FPOS
@r:     rts

; GP = FIELD FF'S TEXT IN DREC
FADDR:  lda FF
        asl a
        tax
        clc
        lda DOFS,x
        adc #<DREC
        sta GP
        lda DOFS+1,x
        adc #>DREC
        sta GP+1
        rts

; RECBUF -> DREC (DATES AS DD/MM/YYYY)
LOADFORM:
        stz IX
        stz M1              ; OFFSET IN DREC
        stz M1+1
@f:     ldx IX
        cpx NFLD
        beq @r
        txa
        asl a
        tay
        lda M1
        sta DOFS,y
        lda M1+1
        sta DOFS+1,y
        jsr FLDPTR
        jsr FLDADDR         ; GP = IN RECBUF, A = WIDTH
        sta BT1
        ldy #F_TYPE
        lda (FP),y
        cmp #'D'
        bne @raw
        jsr DATETEXT
        lda #10
        sta BT1
        ldy #0
@dc:    lda DSPBUF,y
        sta DSPBUF+128,y
        iny
        cpy #10
        bne @dc
        lda #<(DSPBUF+128)
        sta GP
        lda #>(DSPBUF+128)
        sta GP+1
@raw:   ldx IX
        lda BT1
        sta DWID,x
        clc                 ; GP2 = DREC + OFFSET
        lda M1
        adc #<DREC
        sta GP2
        lda M1+1
        adc #>DREC
        sta GP2+1
        ldy #0
@c:     cpy BT1
        beq @n
        lda (GP),y
        sta (GP2),y
        iny
        bra @c
@n:     clc
        lda M1
        adc BT1
        sta M1
        bcc @n2
        inc M1+1
@n2:    inc IX
        bra @f
@r:     rts

; CHECK FIELD FF (AND TIDY IT, E.G. A NUMBER IS RIGHT-ALIGNED).
; C=1 IF IT IS WRONG (A MESSAGE IS SHOWN)
FVALID: ldx FF
        jsr FLDPTR
        jsr FADDR
        ldy #F_TYPE
        lda (FP),y
        cmp #'N'
        beq @n
        cmp #'D'
        beq @d
        cmp #'L'
        beq @l
        clc
        rts
@n:     ldx FF              ; A NUMBER: READ IT, PUT IT BACK FORMATTED
        lda DWID,x
        jsr NUMTEXT
        bcs @badn
        lda GP              ; STOREFLD WRITES INTO RECBUF: USE A COPY
        pha
        lda GP+1
        pha
        lda #'N'
        sta VT
        jsr FLDADDR
        pha
        jsr STOREFLD        ; (INTO RECBUF - SAVEFORM DOES IT AGAIN)
        pla
        sta BT1
        jsr FLDADDR
        pla
        sta GP2+1
        pla
        sta GP2
        ldy #0              ; AND BACK INTO THE FORM
@nc:    cpy BT1
        beq @nd
        lda (GP),y
        sta (GP2),y
        iny
        bra @nc
@nd:    jsr FDRAW
        clc
        rts
@badn:  jsr FERRM
        .byte "Not a number",0
@d:     lda #10
        jsr TEXTDATE
        bcc @ok
        jsr FERRM
        .byte "Dates are dd/mm/yyyy",0
@l:     lda (GP)
        cmp #' '
        beq @ok
        cmp #'T'
        beq @ok
        cmp #'F'
        beq @lf
        cmp #'Y'
        beq @lt
        cmp #'N'
        beq @lf2
        jsr FERRM
        .byte "Y or N (T or F)",0
@lt:    lda #'T'
        bra @ls
@lf2:   lda #'F'
@ls:    sta (GP)
        jsr FDRAW
@lf:
@ok:    clc
        rts

; MESSAGE (AFTER THE JSR) ON THE BOTTOM LINE; C=1 BACK TO THE CALLER'S
; CALLER
FERRM:  pla
        sta MP
        pla
        sta MP+1
        inc MP
        bne @1
        inc MP+1
@1:     ldx NLINES
        ldy #1
        jsr GOTO
        jsr REVON
        jsr PRMP
        jsr REVOFF
        jsr CLEOL
        lda #1
        sta FMSG
        stz FPOS            ; BACK TO THE START: THE NEXT KEY RETYPES IT
        stz FTYPED
        sec
        rts

; DREC -> RECBUF.  C=1 IF A FIELD IS WRONG (FF IS SET TO IT)
SAVEFORM:
        lda FF
        pha
        stz FF
@f:     lda FF
        cmp NFLD
        beq @ok
        jsr FVALID
        bcs @bad
        ldx FF
        jsr FLDPTR
        jsr FADDR
        lda GP
        sta GP2
        lda GP+1
        sta GP2+1
        jsr FLDADDR         ; GP = IN RECBUF, A = WIDTH
        sta BT1
        ldy #F_TYPE
        lda (FP),y
        cmp #'D'
        bne @c
        lda GP              ; DATE: CONVERT
        pha
        lda GP+1
        pha
        lda GP2
        sta GP
        lda GP2+1
        sta GP+1
        lda #10
        jsr TEXTDATE
        pla
        sta GP+1
        pla
        sta GP
        ldy #7
@d:     lda DATEB,y
        sta (GP),y
        dey
        bpl @d
        bra @n
@c:     ldy #0              ; OTHERS: AS THEY ARE
@cc:    cpy BT1
        beq @n
        lda (GP2),y
        sta (GP),y
        iny
        bra @cc
@n:     inc FF
        bra @f
@ok:    pla
        sta FF
        clc
        rts
@bad:   pla                 ; STAY ON THE BAD FIELD
        stz FPOS
        sec
        rts

; ---- DRAWING THE FORM ------------------------------------------------
DRAWFORM:
        jsr CLS
        jsr FTITLE
        stz IX
@f:     ldx IX
        cpx NFLD
        beq @h
        jsr FLDPTR
        txa
        clc
        adc #FTOP
        tax
        ldy #1
        jsr GOTO
        jsr PRFNAME
        jsr NAMELEN
        sta BT1
        lda #FCOL-3
        sec
        sbc BT1
        jsr SPACES
        lda #':'
        jsr OUTC
        lda IX
        sta FF
        jsr FDRAW
        inc IX
        bra @f
@h:     stz FF
FHELP:  ldx NLINES
        ldy #1
        jsr GOTO
        jsr PRS
        .byte "RETURN/arrows move  ^W save+exit  ESC drop changes  "
        .byte "^C/^R next/prev  ^U delete",0
        stz FMSG
        jmp CLEOL

FTITLE: ldx #1
        ldy #1
        jsr GOTO
        jsr REVON
        jsr PRS
        .byte " Record ",0
        lda RECNO
        sta T16
        lda RECNO+1
        sta T16+1
        jsr PRD16
        lda FMODE
        beq @1
        jsr PRS
        .byte " (new) ",0
@1:     lda RECBUF
        cmp #'*'
        bne @2
        jsr PRS
        .byte "  DELETED ",0
@2:     jsr SPACE
        jsr REVOFF
        jsr CLEOL
        ldx #0
        ldy #60
        inx
        jsr GOTO
        jsr PRDBDRV
        ldx #0
@n:     lda DBNAME,x
        beq @r
        jsr OUTC
        inx
        bra @n
@r:     rts

; DRAW FIELD FF
FDRAW:  lda FF
        clc
        adc #FTOP
        tax
        ldy #FCOL
        jsr GOTO
        jsr REVON
        jsr FADDR
        ldx FF
        ldy #0
@c:     tya
        cmp DWID,x
        bcs @e
        lda (GP),y
        jsr OUTC
        iny
        bra @c
@e:     jmp REVOFF

FCURSOR: lda FF
        clc
        adc #FTOP
        tax
        lda FPOS
        clc
        adc #FCOL
        tay
        jmp GOTO

;---------------------------------------------------------------------
; BROWSE
;---------------------------------------------------------------------
H_BROWSE:
        jsr NEEDOPEN
        jsr NEEDEND
        lda NREC
        ora NREC+1
        bne @go
        lda #<M_EMPTY
        ldy #>M_EMPTY
        jmp ERRMSG
@go:    lda RECNO
        ora RECNO+1
        bne @r
        lda #1
        sta RECNO
@r:     lda RECNO
        sta CURR
        sta TOPREC
        lda RECNO+1
        sta CURR+1
        sta TOPREC+1
        stz LFLD
        sec
        lda NLINES
        sbc #3
        sta BROWS
@draw:  jsr BPAGE
        jsr BROWON
@k:     jsr BCURS
        jsr GETKEY
        cmp #$1B
        beq @end
        cmp #K_SAVE
        beq @end
        cmp #K_DN
        beq @dn
        cmp #K_UP
        beq @up
        cmp #K_NEXTR
        beq @pgdn
        cmp #K_PREVR
        bne :+
        jmp @pgup
:
        cmp #K_RT
        bne :+
        jmp @rt
:
        cmp #K_LF
        bne :+
        jmp @lf
:
        cmp #$0D
        bne :+
        jmp @ed
:
        cmp #K_DELM
        bne :+
        jmp @del
:
        bra @k
@end:   lda CURR
        ldy CURR+1
        jsr SETREC
        jsr FLUSHALL
        jmp ENDSCR
@dn:    lda CURR            ; LAST?
        cmp NREC
        bne @d1
        lda CURR+1
        cmp NREC+1
        beq @k
@d1:    jsr BROWOFF
        inc CURR
        bne @d2
        inc CURR+1
@d2:    jsr BSCROLL
        bra @k
@up:    lda CURR
        cmp #1
        bne @u1
        lda CURR+1
        beq @k
@u1:    jsr BROWOFF
        lda CURR
        bne @u2
        dec CURR+1
@u2:    dec CURR
        jsr BSCROLL
        jmp @k
@pgdn:  ldx BROWS
@pd:    lda CURR
        cmp NREC
        bne @pd1
        lda CURR+1
        cmp NREC+1
        beq @pdx
@pd1:   inc CURR
        bne @pd2
        inc CURR+1
@pd2:   dex
        bne @pd
@pdx:   lda CURR
        sta TOPREC
        lda CURR+1
        sta TOPREC+1
        jmp @draw
@pgup:  ldx BROWS
@pu:    lda CURR
        cmp #1
        bne @pu1
        lda CURR+1
        beq @pux
@pu1:   lda CURR
        bne @pu2
        dec CURR+1
@pu2:   dec CURR
        dex
        bne @pu
@pux:   lda CURR
        sta TOPREC
        lda CURR+1
        sta TOPREC+1
        jmp @draw
@rt:    lda LFLD
        inc a
        cmp NFLD
        bcs @k2
        sta LFLD
        jmp @draw
@lf:    lda LFLD
        beq @k2
        dec LFLD
        jmp @draw
@k2:    jmp @k
@ed:    lda CURR            ; EDIT THIS ONE ON THE FORM
        ldy CURR+1
        jsr SETREC
        stz FMODE
        jsr FORM
        lda FKEY
        cmp #$1B
        beq @ed2
        lda FCHG
        beq @ed2
        lda CURR
        ldy CURR+1
        jsr PUTREC
@ed2:   jmp @draw
@del:   lda CURR            ; MARK / UNMARK
        ldy CURR+1
        jsr SETREC
        lda RECBUF
        eor #'*'^' '
        sta RECBUF
        lda CURR
        ldy CURR+1
        jsr PUTREC
        jsr BROWON
        jmp @k
M_EMPTY: .byte "THE FILE IS EMPTY - USE APPEND",0

; IF CURR IS OFF THE SCREEN, MOVE THE PAGE; ELSE REDRAW ITS ROW LIT
BSCROLL:
        sec                 ; ROW = CURR - TOPREC
        lda CURR
        sbc TOPREC
        sta M1
        lda CURR+1
        sbc TOPREC+1
        bcc @top            ; ABOVE THE PAGE
        bne @bot
        lda M1
        cmp BROWS
        bcs @bot
        jmp BROWON
@top:   lda CURR
        sta TOPREC
        lda CURR+1
        sta TOPREC+1
        jsr BPAGE
        jmp BROWON
@bot:   sec                 ; BELOW: CURR AT THE BOTTOM
        lda CURR
        sbc BROWS
        sta TOPREC
        lda CURR+1
        sbc #0
        sta TOPREC+1
        inc TOPREC
        bne @b
        inc TOPREC+1
@b:     jsr BPAGE
        jmp BROWON

; WHOLE PAGE
BPAGE:  jsr CLS
        jsr BHEAD
        stz IX
@r:     lda IX
        cmp BROWS
        beq @h
        clc
        lda TOPREC
        adc IX
        sta RFROM
        lda TOPREC+1
        adc #0
        sta RFROM+1
        lda NREC+1          ; PAST THE LAST RECORD?
        cmp RFROM+1
        bne @c
        lda NREC
        cmp RFROM
@c:     bcc @h
        stz INREV
        jsr BROW
        inc IX
        bra @r
@h:     ldx NLINES
        ldy #1
        jsr GOTO
        jsr PRS
        .byte "arrows move  ^C/^R page  RETURN edit  ^U delete  ESC exit",0
        rts

BROWON: lda #1
        sta INREV
        bra BROW1
BROWOFF: stz INREV
BROW1:  sec
        lda CURR
        sbc TOPREC
        sta IX
        lda CURR
        sta RFROM
        lda CURR+1
        sta RFROM+1
        ; (FALLS INTO BROW)
; DRAW RECORD RFROM ON SCREEN ROW IX (REVERSE IF INREV)
BROW:   lda IX
        clc
        adc #2
        tax
        ldy #1
        jsr GOTO
        lda RFROM
        ldy RFROM+1
        jsr GETREC
        lda INREV
        beq @n
        jsr REVON
@n:     lda RFROM
        sta T16
        lda RFROM+1
        sta T16+1
        lda #5
        jsr PRD16R
        lda RECBUF
        jsr OUTC
        lda #6              ; COLUMNS USED
        sta BT4
        ldx LFLD
@f:     cpx NFLD
        beq @e
        phx
        jsr FLDPTR
        jsr BCOLW           ; A = COLUMN WIDTH
        sta BT3
        clc
        adc BT4
        cmp #80
        bcs @full
        sta BT4
        dec BT3
        jsr SPACE
        jsr FLDTEXT
        ldy #0              ; THE VALUE, PADDED TO THE COLUMN
@c:     cpy BT3
        beq @nx
        lda #' '
        cpy DSPLEN
        bcs @p
        lda DSPBUF,y
@p:     jsr OUTC
        iny
        bra @c
@nx:    plx
        inx
        bra @f
@full:  plx
@e:     jsr REVOFF
        jmp CLEOL
        .bss
INREV:  .res 1
        .code

; COLUMN WIDTH FOR FIELD FP: SPACE + MAX(NAME, VALUE)
BCOLW:  jsr DSPWID
        sta BT1
        jsr NAMELEN
        cmp BT1
        bcs @n
        lda BT1
@n:     inc a
        rts

BHEAD:  ldx #1
        ldy #1
        jsr GOTO
        jsr REVON
        jsr PRS
        .byte "Record",0
        lda #6
        sta BT4
        ldx LFLD
@f:     cpx NFLD
        beq @e
        phx
        jsr FLDPTR
        jsr BCOLW
        sta BT3
        clc
        adc BT4
        cmp #80
        bcs @full
        sta BT4
        jsr SPACE
        jsr PRFNAME
        jsr NAMELEN
        sta BT1
        sec
        lda BT3
        sbc BT1
        dec a
        jsr SPACES
        plx
        inx
        bra @f
@full:  plx
@e:     jsr REVOFF
        jmp CLEOL

; CURSOR TO THE START OF THE CURRENT ROW
BCURS:  sec
        lda CURR
        sbc TOPREC
        clc
        adc #2
        tax
        ldy #1
        jmp GOTO
