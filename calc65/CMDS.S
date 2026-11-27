;=====================================================================
; CMDS.S - THE / COMMANDS, REFERENCE ADJUSTING, DISK
;=====================================================================

COMMAND:
        jsr PROMPT
        .byte "/ Blank Copy Delete Edit Format Global Insert Load Quit Replicate Save Zap? ",0
        jsr GETKEY
        jsr UPPER
        ldx #0
@f:     ldy CMDTAB,x
        beq @no
        cmp CMDTAB,x
        beq @hit
        inx
        inx
        inx
        bra @f
@hit:   lda CMDTAB+2,x
        pha
        lda CMDTAB+1,x
        pha
        rts
@no:    jmp MAIN

CMDTAB: .byte 'B'
        .word C_BLANK-1
        .byte 'C'
        .word C_COPY-1
        .byte 'R'
        .word C_REPL-1
        .byte 'D'
        .word C_DEL-1
        .byte 'I'
        .word C_INS-1
        .byte 'E'
        .word C_EDIT-1
        .byte 'F'
        .word C_FMT-1
        .byte 'G'
        .word C_GLOB-1
        .byte 'S'
        .word C_SAVE-1
        .byte 'L'
        .word C_LOAD-1
        .byte 'Z'
        .word C_ZAP-1
        .byte 'Q'
        .word C_QUIT-1
        .byte 0

; Y/N QUESTION (PROMPT ALREADY SHOWN): Z=1 FOR YES
YESNO:  jsr GETKEY
        jsr UPPER
        cmp #'Y'
        rts

; ASK FOR A RANGE AFTER A PROMPT.  C=1 = CANCELLED OR BAD
ASKRANGE:
        stz ELEN
        jsr EDIT
        bcs @x
        jsr PARSERANGE
        bcc @x
        jsr MSG
        .byte "NOT A CELL OR RANGE",0
        sec
@x:     rts

; DECIMAL NUMBER IN EBUF -> A.  C=1 IF NOT A NUMBER
GETNUM: ldx #0
        stz U1
        lda EBUF
        beq @bad
@l:     lda EBUF,x
        beq @ok
        cmp #'0'
        bcc @bad
        cmp #'9'+1
        bcs @bad
        and #$0F
        sta U2
        lda U1
        cmp #26
        bcs @bad
        asl a
        asl a
        adc U1
        asl a
        adc U2
        bcs @bad
        sta U1
        inx
        bra @l
@ok:    lda U1
        clc
        rts
@bad:   sec
        rts

;---------------------------------------------------------------------
; /B  BLANK
;---------------------------------------------------------------------
C_BLANK:
        jsr PROMPT
        .byte "Blank range (RETURN = this cell): ",0
        jsr ASKRANGE
        bcs @x
        lda SR1
        sta QR
@r:     lda SC1
        sta QC
@c:     ldx QC
        lda QR
        jsr DELCELL
        lda QC
        inc QC
        cmp SC2
        bne @c
        lda QR
        inc QR
        cmp SR2
        bne @r
        lda GAUTO
        beq @f
        jsr RECALC
@f:     lda #1
        sta FULL
@x:     jmp MAIN

;---------------------------------------------------------------------
; /E  EDIT THE CURSOR CELL
;---------------------------------------------------------------------
C_EDIT: stz ELEN
        ldx CCOL
        lda CROW
        jsr GETCELL
        bcs @go
        ldx #0
        ldy #R_TYPE
        lda (RP),y
        and #$7F
        bne @f
        lda #'"'
        sta EBUF
        inx
@f:     ldy #R_TEXT
@c:     lda (RP),y
        sta EBUF,x
        beq @e
        iny
        inx
        cpx #70
        bcc @c
@e:     stx ELEN
@go:    jmp ENTRY

;---------------------------------------------------------------------
; /F  FORMAT
;---------------------------------------------------------------------
C_FMT:  jsr PROMPT
        .byte "Format: Global, Column or Entry? ",0
        jsr YESNO           ; (JUST READS A KEY)
        cmp #'G'
        beq @g
        cmp #'C'
        beq @c
        cmp #'E'
        bne :+
        jmp @e
:
        jmp MAIN
@g:     jsr PROMPT
        .byte "Global format (G $ I L R D) or column width: ",0
        jsr ASKFMT
        bcc :+
        jmp @x
:
        bne @gw
        lda GFMT
        jsr FMTCODES
        bcc :+
        jmp @badf
:
        sta GFMT
        jmp @done
@gw:    ldx #NCOL-1         ; WIDTH FOR EVERY COLUMN
@gl:    sta COLW,x
        dex
        bpl @gl
        jmp @done
@c:     jsr PROMPT
        .byte "Column format (G $ I L R D) or width: ",0
        jsr ASKFMT
        bcc :+
        jmp @x
:
        bne @cw
        ldx CCOL
        lda COLF,x
        jsr FMTCODES
        bcc :+
        jmp @badf
:
        ldx CCOL
        sta COLF,x
        jmp @done
@cw:    ldx CCOL
        sta COLW,x
        jmp @done
@e:     jsr PROMPT
        .byte "Format range (RETURN = this cell): ",0
        jsr ASKRANGE
        bcs @x
        jsr PROMPT
        .byte "Entry format (G $ I L R D): ",0
        stz ELEN
        jsr EDIT
        bcs @x
        lda SR1
        sta QR
@er:    lda SC1
        sta QC
@ec:    ldx QC
        lda QR
        jsr GETCELL
        bcs @en
        ldy #R_FMT
        lda (RP),y
        jsr FMTCODES
        bcs @badf
        ldy #R_FMT
        sta (RP),y
@en:    lda QC
        inc QC
        cmp SC2
        bne @ec
        lda QR
        inc QR
        cmp SR2
        bne @er
@done:  lda #1
        sta FULL
@x:     jmp MAIN
@badf:  jsr MSG
        .byte "FORMATS ARE G $ I L R D",0
        jmp MAIN

; READ A FORMAT LINE.  C=1 CANCELLED.  Z=1: CODES IN EBUF.
; Z=0: A WIDTH (1-72) IN A.
ASKFMT: stz ELEN
        jsr EDIT
        bcs @x
        lda EBUF
        cmp #'0'
        bcc @codes
        cmp #'9'+1
        bcs @codes
        jsr GETNUM
        bcs @bad
        cmp #1
        bcc @bad
        cmp #73
        bcs @bad
        ldx #1              ; Z=0
        clc
        rts
@codes: lda #0              ; Z=1
        clc
@x:     rts
@bad:   jsr MSG
        .byte "WIDTH MUST BE 1-72",0
        sec
        rts

; APPLY THE CODES IN EBUF TO FORMAT A.  C=1 IF ONE IS NOT KNOWN
FMTCODES:
        sta U3
        ldx #0
@l:     lda EBUF,x
        beq @ok
        jsr UPPER
        ldy #0
@f:     cmp FCODES,y
        beq @hit
        iny
        cpy #6
        bne @f
        cmp #' '
        beq @nx
        sec
        rts
@hit:   lda U3
        and FCMASK,y
        ora FCVAL,y
        sta U3
@nx:    inx
        bra @l
@ok:    lda U3
        clc
        rts
FCODES: .byte "G$ILRD"
FCMASK: .byte $F0,$F0,$F0,$0F,$0F,$00
FCVAL:  .byte $01,$02,$03,$10,$20,$00

;---------------------------------------------------------------------
; /G  GLOBAL OPTIONS
;---------------------------------------------------------------------
C_GLOB: jsr PROMPT
        .byte "Global: Lines on the screen, Auto or Manual recalculation? ",0
        jsr YESNO
        cmp #'A'
        beq @a
        cmp #'M'
        beq @m
        cmp #'L'
        beq @l
        jmp MAIN
@a:     lda #1
        sta GAUTO
        jsr RECALC
        bra @f
@m:     stz GAUTO
        bra @f
@l:     jsr PROMPT
        .byte "Screen lines (12-60): ",0
        stz ELEN
        jsr EDIT
        bcs @x
        jsr GETNUM
        bcs @bl
        cmp #12
        bcc @bl
        cmp #61
        bcs @bl
        sta NLINES
        sta NLDEF           ; (KEPT IF THE PROGRAM IS SAVED AGAIN)
@f:     lda #1
        sta FULL
@x:     jmp MAIN
@bl:    jsr MSG
        .byte "LINES MUST BE 12-60",0
        jmp MAIN

;---------------------------------------------------------------------
; /Z  ZAP,  /Q  QUIT
;---------------------------------------------------------------------
C_ZAP:  jsr PROMPT
        .byte "Clear the whole sheet? (Y/N) ",0
        jsr YESNO
        bne @x
        jsr NEWSHEET
        stz CCOL
        stz CROW
        stz LCOL
        stz TROW
        lda #1
        sta FULL
@x:     jmp MAIN

C_QUIT: jsr PROMPT
        .byte "Quit to the DOS? (Y/N) ",0
        jsr YESNO
        bne @x
        jmp QUIT
@x:     jmp MAIN

;---------------------------------------------------------------------
; /R  REPLICATE,  /C  COPY  (THE SAME: SOURCE RANGE TO TARGET RANGE)
;---------------------------------------------------------------------
C_COPY: jsr PROMPT
        .byte "Copy from (RETURN = this cell): ",0
        bra REPL1
C_REPL: jsr PROMPT
        .byte "Replicate from (RETURN = this cell): ",0
REPL1:  jsr ASKRANGE
        bcs @x
        jsr PROMPT
        .byte "To (cell or range): ",0
        lda SC1             ; KEEP THE SOURCE
        pha
        lda SR1
        pha
        lda SC2
        pha
        lda SR2
        pha
        jsr ASKRANGE
        lda SC1
        sta TC1
        lda SR1
        sta TR1
        lda SC2
        sta TC2
        lda SR2
        sta TR2
        pla
        sta SR2
        pla
        sta SC2
        pla
        sta SR1
        pla
        sta SC1
        bcs @x
        jsr REPLICATE
        lda GAUTO
        beq @f
        jsr RECALC
@f:     lda #1
        sta FULL
@x:     jmp MAIN

REPLICATE:
        lda TR1             ; EACH TARGET POSITION
        sta QR
@tr:    lda TC1
        sta QC
@tc:    sec                 ; OFFSET FROM THE SOURCE
        lda QC
        sbc SC1
        sta DC
        sec
        lda QR
        sbc SR1
        sta DR
        ora DC
        beq @skip           ; THE SOURCE ITSELF
        jsr COPYBLOCK
        bcs @full
@skip:  lda QC
        inc QC
        cmp TC2
        bne @tc
        lda QR
        inc QR
        cmp TR2
        bne @tr
        rts
@full:  jsr MSG
        .byte "MEMORY FULL",0
        rts

; COPY THE SOURCE RANGE BY DC,DR.  BACKWARDS WHEN MOVING DOWN/RIGHT
; SO AN OVERLAPPING COPY READS EACH CELL BEFORE IT IS OVERWRITTEN.
COPYBLOCK:
        lda #1
        sta CSTEP
        lda DR
        bmi @fw
        bne @bw
        lda DC
        bmi @fw
@bw:    lda #$FF
        sta CSTEP
        lda SR2
        sta CR0
        lda SR1
        sta CREND
        lda SC2
        sta CC0
        lda SC1
        sta CCEND
        bra @go
@fw:    lda SR1
        sta CR0
        lda SR2
        sta CREND
        lda SC1
        sta CC0
        lda SC2
        sta CCEND
@go:    lda CR0
        sta CRR
@row:   lda CC0
        sta CCC
@col:   jsr COPY1
        bcs @r
        lda CCC
        cmp CCEND
        beq @nr
        clc
        adc CSTEP
        sta CCC
        bra @col
@nr:    lda CRR
        cmp CREND
        beq @ok
        clc
        adc CSTEP
        sta CRR
        bra @row
@ok:    clc
@r:     rts

; COPY CELL CCC,CRR TO CCC+DC, CRR+DR (IF THAT IS ON THE SHEET)
COPY1:  clc
        lda CCC
        adc DC
        cmp #NCOL
        bcs @off            ; (ALSO CATCHES < 0)
        sta SCOL
        clc
        lda CRR
        adc DR
        cmp #NROW
        bcs @off
        sta SROW
        ldx CCC
        lda CRR
        jsr GETCELL
        bcc @have
        ldx SCOL            ; EMPTY SOURCE: EMPTY THE TARGET
        lda SROW
        jsr DELCELL
@off:   clc
        rts
@have:  ldy #R_TYPE
        lda (RP),y
        sta STYPE
        iny
        lda (RP),y
        sta SFMT
        lda RP              ; VALUE
        clc
        adc #R_VAL
        sta PTR
        lda RP+1
        adc #0
        sta PTR+1
        jsr FLDA
        lda STYPE
        and #$7F
        beq @text
        stz ADJM            ; FORMULA: MOVE ITS REFERENCES
        lda DC
        sta ADJDC
        lda DR
        sta ADJDR
        jsr RECTEXT
        jsr ADJTEXT
        bra @put
@text:  ldy #R_TEXT
        ldx #0
@t:     lda (RP),y
        sta TBUF,x
        beq @put
        iny
        inx
        cpx #80
        bcc @t
        stz TBUF,x
@put:   ldx #0              ; TBUF -> EBUF
@p:     lda TBUF,x
        sta EBUF,x
        beq @st
        inx
        bra @p
@st:    jmp PUTCELL

        .bss
CSTEP:  .res 1
CR0:    .res 1
CREND:  .res 1
CC0:    .res 1
CCEND:  .res 1
CRR:    .res 1
CCC:    .res 1
REFCTX: .res 1
        .code

; TP = THE TEXT OF RECORD RP
RECTEXT:
        clc
        lda RP
        adc #R_TEXT
        sta TP
        lda RP+1
        adc #0
        sta TP+1
        rts

;---------------------------------------------------------------------
; ADJUST THE CELL REFERENCES IN THE TEXT AT TP, INTO TBUF.
; ADJM: 0 MOVE BY ADJDC,ADJDR (NOT $ PARTS)   1 ROW INSERTED AT ADJK
;       2 ROW ADJK DELETED   3 COLUMN INSERTED AT ADJK   4 COLUMN DELETED
; A REFERENCE THAT FALLS OFF THE SHEET BECOMES #REF (SHOWS ERROR).
;---------------------------------------------------------------------
ADJTEXT:
        stz TI
        stz SPOS            ; OUTPUT POSITION
        lda #0
        sta U4              ; PREVIOUS CHARACTER
@l:     ldy TI
        lda (TP),y
        bne @1
        ldx SPOS
        stz TBUF,x
        rts
@1:     cmp #' '
        beq @copy
        ldx U4              ; ONLY AFTER A NON-NAME CHARACTER
        jsr ISNAMECH
        bcc @copy
        jsr CELLREF
        bcs @copyr
        ldx #0              ; CONTEXT: 1 = RANGE START, 2 = RANGE END
        lda U4
        cmp #':'
        bne @c1
        ldx #2
@c1:    ldy TI
        lda (TP),y
        cmp #':'
        bne @c2
        ldx #1
@c2:    stx REFCTX
        jsr ADJREF
        bcs @bad
        jsr EMITREF
        bra @l
@bad:   ldx #0              ; #REF
@b:     lda REFTXT,x
        beq @bl
        jsr EMIT
        inx
        bra @b
@bl:    bra @l
@copy:
@copyr: ldy TI
        lda (TP),y
        jsr EMIT
        inc TI
        bra @l
REFTXT: .byte "#REF",0

; A INTO TBUF (KEEPS X); REMEMBERS IT AS THE PREVIOUS CHARACTER
EMIT:   sta U4
        phx
        ldx SPOS
        cpx #79
        bcs @r
        sta TBUF,x
        inc SPOS
@r:     plx
        rts

; C=0 IF X CAN BE PART OF A NAME OR NUMBER (A REF CANNOT START AFTER IT)
ISNAMECH:
        txa
        cmp #'$'
        beq @y
        cmp #'.'
        beq @y
        cmp #'0'
        bcc @n
        cmp #'9'+1
        bcc @y
        jsr UPPER
        cmp #'A'
        bcc @n
        cmp #'Z'+1
        bcc @y
@n:     sec
        rts
@y:     clc
        rts

; RCOL/RROW/RABS AFTER THE ADJUST MODE.  C=1 = OFF THE SHEET
ADJREF: lda ADJM
        bne @ins
        lda RABS            ; MOVE
        and #1
        bne @r1
        lda RCOL
        ldx ADJDC
        ldy #NCOL
        jsr ADDS
        bcs @x
        sta RCOL
@r1:    lda RABS
        and #2
        bne @ok
        lda RROW
        ldx ADJDR
        ldy #NROW
        jsr ADDS
        bcs @x
        sta RROW
@ok:    clc
@x:     rts
@ins:   cmp #1
        bne @dr
        lda RROW            ; ROW INSERTED
        cmp ADJK
        bcc @ok
        inc a
        cmp #NROW
        bcs @x
        sta RROW
        clc
        rts
@dr:    cmp #2
        bne @ic
        lda RROW            ; ROW DELETED
        jsr ADJDEL
        bcs @x
        sta RROW
        rts
@ic:    cmp #3
        bne @dc
        lda RCOL            ; COLUMN INSERTED
        cmp ADJK
        bcc @ok
        inc a
        cmp #NCOL
        bcs @x
        sta RCOL
        clc
        rts
@dc:    lda RCOL            ; COLUMN DELETED
        jsr ADJDEL
        bcs @x
        sta RCOL
        rts

; A + SIGNED X, MUST BE 0..Y-1.  C=1 IF NOT
ADDS:   sty U3
        stx U2
        clc
        adc U2
        ldx U2
        bmi @neg
        bcs @bad            ; PAST 255
        bra @chk
@neg:   bcc @bad            ; BELOW 0
@chk:   cmp U3
        bcs @bad
        clc
        rts
@bad:   sec
        rts

; POSITION A AFTER ROW/COLUMN ADJK WAS DELETED.  C=1 = IT WAS DELETED
ADJDEL: cmp ADJK
        bcc @same           ; BEFORE IT
        bne @less           ; AFTER IT: ONE LESS
        ldx REFCTX          ; THE DELETED ONE ITSELF
        cpx #1
        beq @same           ; RANGE START: THE NEXT ONE MOVES UP INTO IT
        cpx #2
        bne @gone
        cmp #0              ; RANGE END: THE ONE BEFORE
        beq @gone
@less:  dec a
@same:  clc
        rts
@gone:  sec
        rts

; WRITE RCOL,RROW,RABS AS TEXT INTO TBUF
EMITREF:
        lda RABS
        and #1
        beq @1
        lda #'$'
        jsr EMIT
@1:     lda RCOL
        clc
        adc #'A'
        jsr EMIT
        lda RABS
        and #2
        beq @2
        lda #'$'
        jsr EMIT
@2:     lda RROW
        inc a
        ldx #0
@h:     cmp #100
        bcc @t
        sbc #100
        inx
        bra @h
@t:     sta U2
        txa
        beq @t0
        ora #'0'
        jsr EMIT
@t0:    lda U2
        ldy #0
@tl:    cmp #10
        bcc @u
        sbc #10
        iny
        bra @tl
@u:     sta U2
        tya
        bne @t1
        cpx #0
        beq @t2
@t1:    ora #'0'
        jsr EMIT
@t2:    lda U2
        ora #'0'
        jmp EMIT

;---------------------------------------------------------------------
; /I  INSERT,  /D  DELETE  (THE CURSOR ROW OR COLUMN)
;---------------------------------------------------------------------
C_INS:  jsr PROMPT
        .byte "Insert a Row or a Column here? ",0
        jsr YESNO
        cmp #'R'
        beq @r
        cmp #'C'
        beq @c
        jmp MAIN
@r:     lda #NROW-1         ; THE LAST ROW MUST BE EMPTY
        jsr ROWEMPTY
        bcs @full
        lda CROW
        sta ADJK
        jsr ROWADDR         ; SRC = ROW K
        jsr ROWLEN          ; CNT = BYTES IN ROWS K..126
        clc
        lda SRC
        adc #NCOL*2
        sta DST
        lda SRC+1
        adc #0
        sta DST+1
        jsr MEMMOVE
        lda ADJK            ; ROW K EMPTY
        jsr CLRROW
        lda #1
        jmp ADJALL
@c:     lda #NCOL-1         ; THE LAST COLUMN MUST BE EMPTY
        jsr COLEMPTY
        bcs @full
        lda CCOL
        sta ADJK
        jsr COLINS
        lda #3
        jmp ADJALL
@full:  jsr MSG
        .byte "THE LAST ROW/COLUMN IS NOT EMPTY",0
        jmp MAIN

C_DEL:  jsr PROMPT
        .byte "Delete this Row or this Column? ",0
        jsr YESNO
        cmp #'R'
        beq @r
        cmp #'C'
        beq @c
        jmp MAIN
@r:     lda CROW
        sta ADJK
        jsr ROWADDR         ; DST = ROW K, SRC = ROW K+1
        lda SRC
        sta DST
        lda SRC+1
        sta DST+1
        clc
        lda SRC
        adc #NCOL*2
        sta SRC
        bcc @r1
        inc SRC+1
@r1:    jsr ROWLEN
        jsr MEMMOVE
        lda #NROW-1
        jsr CLRROW
        lda #2
        jmp ADJALL
@c:     lda CCOL
        sta ADJK
        jsr COLDEL
        lda #4
        ; (FALLS INTO ADJALL)

; AFTER AN INSERT/DELETE: FIX THE RECORDS AND EVERY FORMULA
ADJALL: sta ADJM
        jsr FIXBACK
        jsr CALCGARB
        stz QR
@r:     stz QC
@c:     ldx QC
        lda QR
        jsr GETCELL
        bcs @n
        ldy #R_TYPE
        lda (RP),y
        and #$7F
        beq @n
        jsr RECTEXT
        jsr ADJTEXT
        ldy #R_TEXT         ; CHANGED?
        ldx #0
@cmp:   lda TBUF,x
        cmp (RP),y
        bne @chg
        cmp #0
        beq @n
        iny
        inx
        bra @cmp
@chg:   ldy #R_TYPE
        lda (RP),y
        sta STYPE
        iny
        lda (RP),y
        sta SFMT
        jsr FZERO
        ldx #0
@cp:    lda TBUF,x
        sta EBUF,x
        beq @put
        inx
        bra @cp
@put:   lda QC
        sta SCOL
        lda QR
        sta SROW
        jsr PUTCELL
        bcc @n
        jsr MSG
        .byte "MEMORY FULL",0
        bra @end
@n:     inc QC
        lda QC
        cmp #NCOL
        bne @c
        inc QR
        lda QR
        cmp #NROW
        beq :+
        jmp @r
:
@end:   jsr RECALC
        lda #1
        sta FULL
        jmp MAIN

; SRC = TABLE ADDRESS OF ROW A... (ROW ADJK)
ROWADDR:
        lda ADJK
        ldx #0
        jsr CIDX
        lda SLOT
        sta SRC
        lda SLOT+1
        sta SRC+1
        rts
; CNT = (127 - ADJK) * 52
ROWLEN: stz CNT
        stz CNT+1
        sec
        lda #NROW-1
        sbc ADJK
        beq @r
        tax
@l:     clc
        lda CNT
        adc #NCOL*2
        sta CNT
        bcc @n
        inc CNT+1
@n:     dex
        bne @l
@r:     rts

; Z... C=1 IF ROW A HAS ANYTHING IN IT
ROWEMPTY:
        ldx #0
        jsr CIDX
        ldy #NCOL*2-1
@l:     lda (SLOT),y
        bne @no
        dey
        bpl @l
        clc
        rts
@no:    sec
        rts
COLEMPTY:
        sta U1
        stz U2
@l:     ldx U1
        lda U2
        jsr GETCELL
        bcc @no
        inc U2
        lda U2
        cmp #NROW
        bne @l
        clc
        rts
@no:    sec
        rts

CLRROW: ldx #0
        jsr CIDX
        ldy #NCOL*2-1
        lda #0
@l:     sta (SLOT),y
        dey
        bpl @l
        rts

; COLUMN ADJK INSERTED: EVERY ROW MOVES RIGHT FROM ADJK
COLINS: stz U2
@r:     ldy #NCOL*2-1       ; ENTRIES (25..ADJK+1) = (24..ADJK)
        ldx U2
        lda U2
        ldx #0
        jsr CIDX            ; SLOT = START OF THE ROW
        lda ADJK
        asl a
        sta U1              ; BYTE OFFSET OF COLUMN K
        ldy #NCOL*2-1
@m:     cpy U1
        bcc @z
        beq @z
        dey
        dey
        lda (SLOT),y
        iny
        iny
        sta (SLOT),y
        dey
        bra @m
@z:     lda #0              ; COLUMN K EMPTY
        ldy U1
        sta (SLOT),y
        iny
        sta (SLOT),y
        inc U2
        lda U2
        cmp #NROW
        bne @r
        ldx #NCOL-1         ; WIDTHS AND FORMATS MOVE TOO
@w:     cpx ADJK
        beq @wz
        lda COLW-1,x
        sta COLW,x
        lda COLF-1,x
        sta COLF,x
        dex
        bra @w
@wz:    lda #9
        sta COLW,x
        stz COLF,x
        rts

; COLUMN ADJK DELETED: EVERY ROW MOVES LEFT
COLDEL: stz U2
@r:     lda U2
        ldx #0
        jsr CIDX
        lda ADJK
        asl a
        tay
@m:     cpy #NCOL*2-2
        bcs @z
        iny
        iny
        lda (SLOT),y
        dey
        dey
        sta (SLOT),y
        iny
        bra @m
@z:     lda #0
        ldy #NCOL*2-2
        sta (SLOT),y
        iny
        sta (SLOT),y
        inc U2
        lda U2
        cmp #NROW
        bne @r
        ldx ADJK
@w:     cpx #NCOL-1
        beq @wz
        lda COLW+1,x
        sta COLW,x
        lda COLF+1,x
        sta COLF,x
        inx
        bra @w
@wz:    lda #9
        sta COLW,x
        stz COLF,x
        rts

; COPY CNT BYTES FROM SRC TO DST (EITHER DIRECTION)
MEMMOVE:
        lda CNT
        ora CNT+1
        beq @r
        lda DST+1
        cmp SRC+1
        bne @d
        lda DST
        cmp SRC
@d:     bcc @fwd
        clc                 ; BACKWARDS: START AT THE ENDS
        lda SRC
        adc CNT
        sta SRC
        lda SRC+1
        adc CNT+1
        sta SRC+1
        clc
        lda DST
        adc CNT
        sta DST
        lda DST+1
        adc CNT+1
        sta DST+1
@bl:    lda SRC
        bne @b1
        dec SRC+1
@b1:    dec SRC
        lda DST
        bne @b2
        dec DST+1
@b2:    dec DST
        lda (SRC)
        sta (DST)
        jsr @dec
        bne @bl
@r:     rts
@fwd:   lda (SRC)
        sta (DST)
        inc SRC
        bne @f1
        inc SRC+1
@f1:    inc DST
        bne @f2
        inc DST+1
@f2:    jsr @dec
        bne @fwd
        rts
@dec:   lda CNT
        bne @d1
        dec CNT+1
@d1:    dec CNT
        lda CNT
        ora CNT+1
        rts

; EVERY RECORD'S TABLE INDEX AFTER THE TABLE HAS MOVED
FIXBACK:
        lda #<TABLE
        sta SLOT
        lda #>TABLE
        sta SLOT+1
        stz IDX
        stz IDX+1
@l:     ldy #0
        lda (SLOT),y
        sta RP
        iny
        lda (SLOT),y
        sta RP+1
        ora RP
        beq @n
        ldy #R_IDX
        lda IDX
        sta (RP),y
        iny
        lda IDX+1
        sta (RP),y
@n:     clc
        lda SLOT
        adc #2
        sta SLOT
        bcc @s
        inc SLOT+1
@s:     inc IDX
        bne @t
        inc IDX+1
@t:     lda IDX
        cmp #<NCELL
        bne @l
        lda IDX+1
        cmp #>NCELL
        bne @l
        rts

;---------------------------------------------------------------------
; /S SAVE  AND  /L LOAD  (THROUGH THE DOS MS AND ML COMMANDS)
;---------------------------------------------------------------------
C_SAVE: jsr PROMPT
        .byte "Save as: ",0
        jsr ASKNAME
        bcs @x
        jsr COMPACT
        lda #<SAVCMD        ; "MS 7700 " + END + " " + NAME
        sta MP
        lda #>SAVCMD
        sta MP+1
        jsr CMDSTART
        sec                 ; END = TOP - 1
        lda H_TOP
        sbc #1
        sta U1
        lda H_TOP+1
        sbc #0
        jsr CMDHEX
        lda U1
        jsr CMDHEX
        lda #' '
        jsr CMDCH
        jsr CMDNAME
        jsr DOSCALL
        bcs @err
        jsr MSG
        .byte "SAVED",0
        bra @f
@err:   jsr MSG
        .byte "DISK ERROR - NOT SAVED",0
@f:     lda #1
        sta FULL
@x:     jmp MAIN
SAVCMD: .byte "MS 7700 ",0

C_LOAD: jsr PROMPT
        .byte "Load file: ",0
        jsr ASKNEW
        bcc :+
        jmp @x
:
        lda #<LODCMD        ; "ML " + NAME
        sta MP
        lda #>LODCMD
        sta MP+1
        jsr CMDSTART
        jsr CMDNAME
        jsr CHKFILE         ; IS IT A CALC65 SHEET?
        bcs @err
        bne @not
        jsr DOSCALL         ; LOAD IT
        bcs @err
        jsr CHKSHEET
        bcs @bad
        jsr CALCGARB
        stz CCOL
        stz CROW
        stz LCOL
        stz TROW
        jsr MSG
        .byte "LOADED",0
        bra @f
@bad:   jsr NEWSHEET
        jsr MSG
        .byte "THAT FILE IS NOT A CALC65 SHEET",0
        bra @f
@not:   jsr MSG
        .byte "THAT FILE IS NOT A CALC65 SHEET",0
        bra @f
@err:   jsr MSG
        .byte "DISK ERROR (IS THE NAME RIGHT?)",0
@f:     lda #1
        sta FULL
@x:     jmp MAIN
LODCMD: .byte "ML ",0

; FILE NAME INTO EBUF/FNAME (THE LAST ONE IS OFFERED).  C=1 CANCELLED
ASKNEW: stz ELEN            ; (LOAD: START EMPTY)
        bra ASKN2
ASKNAME:
        ldx #0
@c:     lda FNAME,x
        sta EBUF,x
        beq @e
        inx
        bra @c
@e:     stx ELEN
ASKN2:  jsr EDIT
        bcs @x
        lda ELEN
        beq @no
        cmp #15
        bcs @no
        ldx #0
@s:     lda EBUF,x
        jsr UPPER
        sta FNAME,x
        cmp #0
        beq @ok
        inx
        bra @s
@ok:    clc
@x:     rts
@no:    sec
        rts

; BUILD A DOS COMMAND LINE IN CMDBUF
CMDSTART:
        stz CPOS
        ldy #0
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
CMDNAME: ldx #0
@l:     lda FNAME,x
        beq @e
        phx
        jsr CMDCH
        plx
        inx
        bra @l
@e:     lda #$0D
        jmp CMDCH
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
        .bss
CPOS:   .res 1
        .code

; RUN THE COMMAND IN CMDBUF.  C=1 IF THE DOS GAVE AN ERROR
DOSCALL: jsr DOSSET
        tsx
        stx DSKSP
        jsr DOCMD
        clc
        rts
DSKERR: ldx DSKSP           ; THE DOS ERROR VECTOR COMES HERE
        txs
        sec
        rts
DOSSET: lda #<CMDBUF
        sta INBUF
        lda #>CMDBUF
        sta INBUF+1
        stz CMDPOS
        lda #$28
        sta CMDLEN
        rts

; READ THE FIRST SECTOR OF THE FILE NAMED IN CMDBUF (AS ML DOES).
; C=1 DISK ERROR.  Z=1 IF IT IS A MACHINE-CODE FILE LOADING AT $7700.
CHKFILE: jsr DOSSET
        tsx
        stx DSKSP
        jsr CHK2
        clc
        rts
CHK2:   jsr FINDNM
        ldy #$0E
        lda (ENTPL),y
        jsr SEEK
        stz MEMLO
        lda #>DOSHDR
        sta MEMLO+1
        lda #1
        jsr RDSEC1
        lda DOSHDR
        cmp #'M'
        bne @r
        lda DOSHDR+1
        cmp #'C'
        bne @r
        lda DOSHDR+2
        cmp #<HDR
        bne @r
        lda DOSHDR+3
        cmp #>HDR
@r:     rts
