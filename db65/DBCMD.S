;=====================================================================
; DBCMD.S - DOT PROMPT COMMANDS FOR DB65
;=====================================================================

        .bss
IX:     .res 1              ; LOOP COUNTER
SKSIGN: .res 1
SEXPL:  .res 1
SMODE:  .res 1              ; SCOPE: 0 CURRENT, 1 ALL, 2 NEXT N, 3 RECORD N
SCNT:   .res 2
FORPOS: .res 1              ; START OF THE FOR CONDITION (0 = NONE)
CTP:    .res 2              ; TEXT THE CONDITION IS IN
NITEMS: .res 1
ITEMPOS: .res 24
ITP:    .res 2              ; TEXT THE ITEMS ARE IN
NOREC:  .res 1              ; LIST OFF
STOPF:  .res 1
CBVEC:  .res 2
RFROM:  .res 2
RTO:    .res 2
CNT16:  .res 2
NPAIR:  .res 1
PFLD:   .res 12             ; REPLACE: FIELD NUMBERS
PPOS:   .res 12             ;          AND WHERE THEIR VALUES START
LOCBUF: .res LBMAX+2
ITBUF:  .res 240            ; FIELD NAMES MADE UP FOR SUM / REPORT
COLW:   .res 24             ; REPORT COLUMN WIDTHS
TOTS:   .res 24*8           ; SUM / REPORT TOTALS
        .code

KW_ALL: .byte "ALL",0
KW_NEXT: .byte "NEXT",0
KW_REC: .byte "RECORD",0
KW_FOR: .byte "FOR",0
KW_OFF: .byte "OFF",0
KW_WITH: .byte "WITH",0
KW_TOP: .byte "TOP",0
KW_BOT: .byte "BOTTOM",0
KW_STRU: .byte "STRUCTURE",0
KW_STR4: .byte "STRU",0
KW_ON:  .byte "ON",0
KW_TO:  .byte "TO",0
KW_DESC: .byte "DESCENDING",0
KW_LINES: .byte "LINES",0
KW_BLANK: .byte "BLANK",0

; KEYWORD (A/Y) AT TI?  C=0 YES
KW:     sta MP
        sty MP+1
        jmp KEYWORD

NEEDOPEN:
        lda OPENF
        beq @no
        rts
@no:    lda #<M_NOUSE
        ldy #>M_NOUSE
        jmp ERRMSG
M_NOUSE: .byte "NO DATABASE IN USE - USE OR CREATE ONE",0

; THE REST OF THE LINE MUST BE EMPTY
NEEDEND: jsr PEEK
        beq @r
        jmp ESYNTAX
@r:     rts

; A FILE NAME (UP TO 14 CHARACTERS, NO SPACES) -> FNAME.  C=1 NONE
GETFNAME:
        jsr PEEK
        beq @no
        ldy TI
        ldx #0
@l:     lda (TP),y
        beq @e
        cmp #' '
        beq @e
        cpx #14
        bcs @long
        jsr UPPER
        sta FNAME,x
        inx
        iny
        bra @l
@e:     stz FNAME,x
        sty TI
        clc
        rts
@no:    sec
        rts
@long:  lda #<M_LONG
        ldy #>M_LONG
        jmp ERRMSG
M_LONG: .byte "FILE NAMES ARE AT MOST 14 CHARACTERS",0

; NUMBER EXPRESSION -> 16-BIT CNT16
GETNUM16:
        jsr EVAL
        jsr NEEDN
        lda FA_S
        bmi @bad
        jsr FINT
        stz CNT16
        stz CNT16+1
        lda FA_M
        beq @r
        lda FA_E
        cmp #6
        bcs @bad
        ldx #0              ; DIGIT BY DIGIT, * 10 EACH TIME
@l:     cpx FA_E
        beq @r
        lda CNT16           ; CNT16 * 10
        sta M1
        lda CNT16+1
        sta M1+1
        lda #10
        sta M2
        stz M2+1
        phx
        jsr MUL16
        plx
        txa
        lsr a
        tay
        lda FA_M,y
        bcs @lo
        lsr a
        lsr a
        lsr a
        lsr a
@lo:    and #$0F
        clc
        adc M3
        sta CNT16
        lda M3+1
        adc #0
        sta CNT16+1
        inx
        bra @l
@r:     rts
@bad:   lda #<M_RANGE
        ldy #>M_RANGE
        jmp ERRMSG
M_RANGE: .byte "NUMBER OUT OF RANGE",0

; SKIP AN EXPRESSION WITHOUT WORKING IT OUT: STOP AT A , OR THE END
; OR A KEYWORD (FOR ALL NEXT RECORD OFF WITH), OUTSIDE BRACKETS
SKIPEXPR:
        stz BT2             ; BRACKET DEPTH
@l:     jsr PEEK
        beq @r
        ldx BT2
        bne @in
        cmp #','
        beq @r
        jsr ISKW
        bcc @r
        jsr PEEK
@in:    cmp #'('
        bne @1
        inc BT2
        bra @n
@1:     cmp #')'
        bne @2
        lda BT2
        beq @r
        dec BT2
        bra @n
@2:     cmp #'"'
        beq @q
        cmp #$27
        beq @q
        jsr UPPER           ; A NAME: SKIP IT WHOLE
        jsr ISNAMEC
        bcs @n
        ldy TI
@nm:    iny
        lda (TP),y
        jsr UPPER
        jsr ISNAMEC
        bcc @nm
        sty TI
        bra @l
@q:     sta BT1             ; QUOTED TEXT
        ldy TI
@ql:    iny
        lda (TP),y
        beq @qe
        cmp BT1
        bne @ql
        iny
@qe:    sty TI
        bra @l
@n:     jsr NEXT
        bra @l
@r:     rts
; ONE OF THE CLAUSE KEYWORDS AT TI?  C=0 YES (TI NOT MOVED)
ISKW:   ldy TI
        phy
        ldx #0
@k:     lda KWLIST,x
        ora KWLIST+1,x
        beq @no
        lda KWLIST,x
        ldy KWLIST+1,x
        phx
        jsr KW
        plx
        bcc @yes
        inx
        inx
        bra @k
@yes:   ply
        sty TI
        clc
        rts
@no:    ply
        sty TI
        sec
        rts
KWLIST: .word KW_FOR,KW_ALL,KW_NEXT,KW_REC,KW_OFF,KW_WITH,0

;---------------------------------------------------------------------
; SCOPE AND CONDITION:  [ALL | NEXT n | RECORD n] [OFF] [items] [FOR c]
; A = 1 IF A LIST OF ITEMS IS ALLOWED.  (SMODE IS SET BY THE CALLER
; TO THE COMMAND'S DEFAULT FIRST)
;---------------------------------------------------------------------
PARSESCOPE:
        sta BT4
        stz FORPOS
        stz NITEMS
        stz SEXPL
        stz NOREC
        lda #<LBUF
        sta CTP
        sta ITP
        lda #>LBUF
        sta CTP+1
        sta ITP+1
@l:     jsr PEEK
        bne @1
        rts
@1:     lda #<KW_ALL
        ldy #>KW_ALL
        jsr KW
        bcs @2
        lda #1
        sta SMODE
        sta SEXPL
        bra @l
@2:     lda #<KW_NEXT
        ldy #>KW_NEXT
        jsr KW
        bcs @3
        lda BT4
        pha
        jsr GETNUM16
        pla
        sta BT4
        lda CNT16
        sta SCNT
        lda CNT16+1
        sta SCNT+1
        lda #2
        sta SMODE
        sta SEXPL
        bra @l
@3:     lda #<KW_REC
        ldy #>KW_REC
        jsr KW
        bcs @4
        lda BT4
        pha
        jsr GETNUM16
        pla
        sta BT4
        lda CNT16
        sta SCNT
        lda CNT16+1
        sta SCNT+1
        lda #3
        sta SMODE
        sta SEXPL
        bra @l
@4:     lda #<KW_OFF
        ldy #>KW_OFF
        jsr KW
        bcs @5
        lda #1
        sta NOREC
        bra @l
@5:     lda #<KW_FOR
        ldy #>KW_FOR
        jsr KW
        bcs @6
        jsr PEEK            ; THE REST OF THE LINE IS THE CONDITION
        bne @f
        jmp ESYNTAX
@f:     lda TI
        sta FORPOS
        lda SEXPL           ; FOR WITH NO SCOPE: ALL RECORDS
        bne @fr
        lda #1
        sta SMODE
@fr:    rts
@6:     lda BT4             ; AN ITEM
        bne @it
        jmp ESYNTAX
@it:    ldx NITEMS
        cpx #20
        bcc @i2
        jmp ESYNTAX
@i2:    jsr PEEK
        lda TI
        sta ITEMPOS,x
        inc NITEMS
        jsr SKIPEXPR
        jsr PEEK
        cmp #','
        beq :+
        jmp @l
:
        jsr NEXT
        jmp @l

;---------------------------------------------------------------------
; DO (CBVEC) FOR EACH RECORD IN THE SCOPE THAT PASSES THE CONDITION
;---------------------------------------------------------------------
FOREACH:
        stz STOPF
        lda SMODE
        bne @1
        lda RECNO           ; CURRENT RECORD
        ora RECNO+1
        bne @c
        rts
@c:     lda RECNO
        sta RFROM
        sta RTO
        lda RECNO+1
        sta RFROM+1
        sta RTO+1
        jmp @go
@1:     cmp #1
        bne @2
        lda NREC            ; ALL
        ora NREC+1
        bne @a
        rts
@a:     lda #1
        sta RFROM
        stz RFROM+1
        lda NREC
        sta RTO
        lda NREC+1
        sta RTO+1
        bra @go
@2:     cmp #2
        bne @3
        lda RECNO           ; NEXT N
        sta RFROM
        lda RECNO+1
        sta RFROM+1
        ora RFROM
        bne @n1
        inc RFROM
@n1:    lda SCNT
        ora SCNT+1
        bne @n2
        rts
@n2:    clc                 ; TO = FROM + N - 1, AT MOST NREC
        lda RFROM
        adc SCNT
        sta RTO
        lda RFROM+1
        adc SCNT+1
        sta RTO+1
        lda RTO
        bne @n3
        dec RTO+1
@n3:    dec RTO
        jsr CLIPTO
        bra @go
@3:     cmp #4
        bne @3r
        lda RECNO           ; FROM HERE TO THE END
        sta RFROM
        lda RECNO+1
        sta RFROM+1
        lda NREC
        sta RTO
        lda NREC+1
        sta RTO+1
        bra @go
@3r:    lda SCNT            ; RECORD N
        sta RFROM
        sta RTO
        lda SCNT+1
        sta RFROM+1
        sta RTO+1
        jsr CHKREC
@go:    lda RTO+1           ; NOTHING IF FROM > TO
        cmp RFROM+1
        bne @g1
        lda RTO
        cmp RFROM
@g1:    bcs @loop
        rts
@loop:  lda RFROM
        ldy RFROM+1
        jsr SETREC
        lda FORPOS
        beq @do
        jsr TESTFOR
        beq @skip
@do:    jsr @cb
        lda STOPF
        bne @r
@skip:  jsr KEYHIT          ; ESC STOPS
        bcc @k
        cmp #$1B
        bne @k
        jmp ABORT
@k:     lda RFROM           ; NEXT
        cmp RTO
        bne @inc
        lda RFROM+1
        cmp RTO+1
        beq @r
@inc:   inc RFROM
        bne @loop
        inc RFROM+1
        bra @loop
@r:     rts
@cb:    jmp (CBVEC)

; THE FOR CONDITION ON THE CURRENT RECORD: Z=0 TRUE, Z=1 FALSE
TESTFOR: lda CTP
        sta TP
        lda CTP+1
        sta TP+1
        lda FORPOS
        sta TI
        jsr EVAL
        jsr NEEDL
        jsr NEEDEND
        lda FA
        rts

; RTO = MIN(RTO, NREC)
CLIPTO: lda NREC+1
        cmp RTO+1
        bne @c
        lda NREC
        cmp RTO
@c:     bcs @r
        lda NREC
        sta RTO
        lda NREC+1
        sta RTO+1
@r:     rts
; RFROM MUST BE 1..NREC
CHKREC: lda RFROM
        ora RFROM+1
        beq @bad
        lda NREC+1
        cmp RFROM+1
        bne @c
        lda NREC
        cmp RFROM
@c:     bcs @r
@bad:   lda #<M_RECR
        ldy #>M_RECR
        jmp ERRMSG
@r:     rts
M_RECR: .byte "NO SUCH RECORD",0

;=====================================================================
; USE, CLOSE, CREATE
;=====================================================================
H_USE:  jsr GETFNAME
        bcc @f
        jmp CLOSEFILE
@f:     jsr NEEDEND
        jsr OPENFILE
SAYCOUNT:
        lda NREC
        sta T16
        lda NREC+1
        sta T16+1
        jsr PRD16
        jsr PRS
        .byte " records",0
        jmp CRLF

H_CLOSE: jmp CLOSEFILE

H_CREATE:
        jsr GETFNAME
        bcc @f
        lda #<M_NAME
        ldy #>M_NAME
        jmp ERRMSG
@f:     jsr NEEDEND
        jsr CLOSEFILE
        jsr FINDFILE        ; ALREADY THERE?
        bcs @new
        jsr PRS
        .byte "That file exists - replace it? (Y/N) ",0
        jsr YESNO
        beq @new
        rts
@new:   ldx #0              ; CLEAR THE HEADER
@z:     stz HDR,x
        stz HDR+256,x
        inx
        bne @z
        jsr PRS
        .byte "Enter the fields as  NAME,TYPE,WIDTH,DECIMALS",13,10
        .byte "TYPE: C text, N number, D date, L logical (Y/N)",13,10
        .byte "Press RETURN on an empty line when done.",13,10,0
        lda #1
        sta RECLEN          ; THE DELETE FLAG
        stz RECLEN+1
@fld:   lda NFLD
        cmp #MAXFLD
        bcs @size
        inc a
        sta T16
        stz T16+1
        jsr PRS
        .byte "Field ",0
        lda #2
        jsr PRD16R
        jsr PRS
        .byte ": ",0
        jsr GETLINE
        bcs @cancel
        lda LLEN
        beq @size
        jsr DEFFIELD
        bcc @fld
        jsr PRS
        .byte "  ?? ",0
        lda EMSG
        sta MP
        lda EMSG+1
        sta MP+1
        jsr PRMP
        jsr CRLF
        bra @fld
@cancel: rts
@size:  lda NFLD
        bne @s1
        rts
@s1:    lda RECLEN+1        ; RECORD LENGTH AT MOST 1000
        cmp #>1001
        bcc @s2
        bne @big
        lda RECLEN
        cmp #<1001
        bcc @s2
@big:   lda #<M_RLEN
        ldy #>M_RLEN
        jmp ERRMSG
@s2:    jsr PRS
        .byte "Room for how many records? ",0
        jsr GETLINE
        bcs @cancel
        lda #<LBUF
        sta TP
        lda #>LBUF
        sta TP+1
        stz TI
        jsr GETNUM16
        lda #32             ; WORK OUT THE TRACKS (AT MOST 32)
        sta CXNT
        jsr SETGEOM
        lda CNT16           ; TRACKS = 1, PLUS (N-R0)/RPT ROUNDED UP
        sec
        sbc R0
        sta M1
        lda CNT16+1
        sbc R0+1
        sta M1+1
        lda #1
        sta FTRKN
        bcc @t1             ; FITS IN TRACK 0
        lda M1
        ora M1+1
        beq @t1
        lda RPT
        sta M2
        lda RPT+1
        sta M2+1
        jsr DIV16
        lda M4
        ora M4+1
        beq @t0
        inc M1
        bne @t0
        inc M1+1
@t0:    lda M1+1
        beq :+
        jmp @toobig
:
        lda M1
        cmp #32
        bcc :+
        jmp @toobig
:
        inc a
        sta FTRKN
@t1:    lda FTRKN           ; MS 0000 (TRACKS*8-1 PAGES) NAME
        asl a
        asl a
        asl a
        sec
        sbc #2
        sta IX             ; END PAGE
        lda #<MSCMD
        sta MP
        lda #>MSCMD
        sta MP+1
        jsr CMDSTART
        lda IX
        jsr CMDHEX
        lda #$FF
        jsr CMDHEX
        lda #' '
        jsr CMDCH
        jsr CMDNAME
        jsr DOSCALL
        jsr FINDFILE        ; WHERE DID IT GO?
        bcc @w
        jmp DSKERR
@w:     lda FTRK0
        sta CXSTART
        lda FTRKN
        sta CXNT
        ldx #3              ; THE HEADER
@m:     lda MAGIC,x
        sta HDR,x
        dex
        bpl @m
        stz NREC
        stz NREC+1
        ldx #0              ; TRACK 0 = HEADER + ZEROS
@c:     lda HDR,x
        sta TRKBUF0,x
        lda HDR+256,x
        sta TRKBUF0+256,x
        lda #' '
        sta TRKBUF0+512,x
        sta TRKBUF0+768,x
        sta TRKBUF0+1024,x
        sta TRKBUF0+1280,x
        sta TRKBUF0+1536,x
        sta TRKBUF0+1792,x
        inx
        bne @c
        stz CXCUR
        lda #1
        sta CXDIRTY
        lda #1
        sta OPENF
        ldx #0
        jsr CXFLUSH
        jsr CLOSEFILE
        jsr OPENFILE        ; AND USE IT
        jsr PRS
        .byte "Created. Room for ",0
        lda MAXREC
        sta T16
        lda MAXREC+1
        sta T16+1
        jsr PRD16
        jsr PRS
        .byte " records.",13,10,0
        rts
@toobig: lda #<M_TBIG
        ldy #>M_TBIG
        jmp ERRMSG
MSCMD:  .byte "MS 0000 ",0
M_NAME: .byte "NEEDS A FILE NAME",0
M_RLEN: .byte "RECORDS ARE AT MOST 1000 CHARACTERS",0
M_TBIG: .byte "TOO MANY RECORDS (A FILE IS AT MOST 32 TRACKS)",0

; ONE FIELD DEFINITION FROM LBUF: NAME,TYPE,WIDTH[,DECIMALS]
; C=1 WITH EMSG SET IF IT IS WRONG
DEFFIELD:
        lda #<LBUF
        sta TP
        lda #>LBUF
        sta TP+1
        stz TI
        jsr GETNAME
        bcc :+
        jmp @bad
:
        jsr FINDFLD         ; NOT ALREADY USED
        bcs @nu
        lda #<M_DUP
        ldy #>M_DUP
        jmp @err
@nu:    ldx NFLD
        jsr FLDPTR
        ldy #0
@n:     lda NAMEB,y
        sta (FP),y
        iny
        cpy #11
        bne @n
        lda #','
        jsr @exp
        bcc :+
        jmp @bad
:
        jsr PEEK
        jsr UPPER
        ldy #F_TYPE
        sta (FP),y
        jsr NEXT
        cmp #'D'
        beq @d
        cmp #'L'
        beq @lg
        cmp #'C'
        beq @wid
        cmp #'N'
        beq :+
        jmp @bad
:
@wid:   lda #','
        jsr @exp
        bcc :+
        jmp @bad
:
        jsr @int
        bcc :+
        jmp @bad
:
        ldy #F_WID
        sta (FP),y
        beq @bad
        ldy #F_TYPE
        lda (FP),y
        cmp #'N'
        beq @num
        ldy #F_WID          ; TEXT: 1-64
        lda (FP),y
        cmp #65
        bcs @bad
        bra @add
@num:   ldy #F_WID          ; NUMBER: 1-18
        lda (FP),y
        cmp #19
        bcs @bad
        jsr PEEK
        beq @add
        lda #','
        jsr @exp
        bcs @bad
        jsr @int
        bcs @bad
        cmp #10
        bcs @bad
        ldy #F_DEC
        sta (FP),y
        cmp #0
        beq @add
        inc a               ; ROOM FOR DIGITS AND THE POINT
        inc a
        ldy #F_WID
        cmp (FP),y
        beq @add
        bcs @bad
        bra @add
@d:     lda #8
        bra @fw
@lg:    lda #1
@fw:    ldy #F_WID
        sta (FP),y
@skp:   jsr PEEK            ; (A WIDTH AFTER D OR L IS IGNORED)
        beq @add
        jsr NEXT
        bra @skp
@add:   jsr PEEK
        bne @bad
        ldy #F_OFS          ; OFFSET = RECORD LENGTH SO FAR
        lda RECLEN
        sta (FP),y
        iny
        lda RECLEN+1
        sta (FP),y
        ldy #F_WID
        clc
        lda (FP),y
        adc RECLEN
        sta RECLEN
        bcc @a1
        inc RECLEN+1
@a1:    inc NFLD
        clc
        rts
@bad:   lda #<M_FDEF
        ldy #>M_FDEF
@err:   sta EMSG
        sty EMSG+1
        ldx NFLD            ; FORGET THE HALF-MADE FIELD
        jsr FLDPTR
        lda #0
        tay
@cl:    sta (FP),y
        iny
        cpy #16
        bne @cl
        sec
        rts
@exp:   sta BT1             ; EXPECT A CHARACTER: C=1 IF NOT THERE
        jsr PEEK
        cmp BT1
        bne @ex
        jsr NEXT
        clc
        rts
@ex:    sec
        rts
@int:   jsr PEEK            ; A SMALL WHOLE NUMBER -> A, C=1 IF NOT
        cmp #'0'
        bcc @ix
        cmp #'9'+1
        bcs @ix
        stz BT2
@il:    jsr PEEK
        cmp #'0'
        bcc @ie
        cmp #'9'+1
        bcs @ie
        and #$0F
        sta BT1
        lda BT2
        cmp #26
        bcs @ix
        asl a
        asl a
        adc BT2
        asl a
        adc BT1
        sta BT2
        jsr NEXT
        bra @il
@ie:    lda BT2
        clc
        rts
@ix:    sec
        rts
M_DUP:  .byte "THAT NAME IS ALREADY USED",0
M_FDEF: .byte "TRY e.g. NAME,C,20  AGE,N,3  PRICE,N,8,2  BORN,D  PAID,L",0

;=====================================================================
; LIST, DISPLAY, REPORT
;=====================================================================
H_DISP: lda #0              ; DISPLAY: THIS RECORD UNLESS TOLD
        bra LISTGO
H_LIST: lda #1
LISTGO: sta SMODE
        jsr NEEDOPEN
        lda #<KW_STRU       ; LIST STRUCTURE
        ldy #>KW_STRU
        jsr KW
        bcs :+
        jmp STRUCT
:
        lda #<KW_STR4
        ldy #>KW_STR4
        jsr KW
        bcs :+
        jmp STRUCT
:
        lda #1
        jsr PARSESCOPE
        lda #<LISTCB
        sta CBVEC
        lda #>LISTCB
        sta CBVEC+1
        jmp FOREACH

LISTCB: lda NOREC
        bne @f
        lda RECNO
        sta T16
        lda RECNO+1
        sta T16+1
        lda #5
        jsr PRD16R
        jsr SPACE
@f:     lda RECBUF          ; DELETED?
        jsr OUTC
        lda NITEMS
        bne @items
        stz IX             ; EVERY FIELD
@af:    ldx IX
        cpx NFLD
        beq @end
        jsr FLDPTR
        jsr FLDTEXT
        jsr PRDSP
        jsr SPACE
        inc IX
        bra @af
@items: stz IX
@it:    ldx IX
        cpx NITEMS
        beq @end
        jsr ITEMTEXT
        jsr PRDSP
        jsr SPACE
        inc IX
        bra @it
@end:   jsr CRLF
        jmp PAGECHK

; ITEM X AS TEXT IN DSPBUF.  A FIELD NAME ON ITS OWN IS SHOWN AS
; STORED (SO NUMBERS KEEP THEIR WIDTH AND DECIMALS).
ITEMTEXT:
        lda ITP
        sta TP
        lda ITP+1
        sta TP+1
        lda ITEMPOS,x
        sta TI
        jsr ITEMFLD
        bcs @exp
        jmp FLDTEXT
@exp:   jsr EVAL
        jmp VALTEXT
; IS THE ITEM AT TI JUST A FIELD NAME?  C=0: YES, FP SET.  TI KEPT
ITEMFLD: lda TI
        pha
        jsr GETNAME
        bcs @no
        jsr PEEK
        beq @chk
        cmp #','
        beq @chk
        jsr ISKW
        bcs @no
@chk:   jsr FINDFLD
        bcs @no
        pla
        sta TI
        clc
        rts
@no:    pla
        sta TI
        sec
        rts

; FIELD FP OF RECBUF, AS SHOWN, IN DSPBUF
FLDTEXT: jsr FLDADDR        ; GP, A = WIDTH
        sta BT1
        ldy #F_TYPE
        lda (FP),y
        cmp #'D'
        bne @1
        jmp DATETEXT
@1:     cmp #'L'
        bne @2
        lda (GP)
        jsr UPPER
        ldx #4
        cmp #'T'
        beq @l
        cmp #'Y'
        beq @l
        ldx #0
@l:     ldy #0
@lc:    lda LTXT,x
        sta DSPBUF,y
        inx
        iny
        cpy #3
        bne @lc
        sty DSPLEN
        rts
@2:     ldy #0
@c:     cpy BT1
        beq @e
        lda (GP),y
        sta DSPBUF,y
        iny
        bra @c
@e:     sty DSPLEN
        rts

; DISPLAY STRUCTURE
STRUCT: jsr PRS
        .byte "Database: ",0
        ldx #0
@n:     lda DBNAME,x
        beq @n2
        jsr OUTC
        inx
        bra @n
@n2:    jsr CRLF
        jsr PRS
        .byte "Records:  ",0
        jsr SAYCOUNT
        jsr PRS
        .byte "Room for: ",0
        lda MAXREC
        sta T16
        lda MAXREC+1
        sta T16+1
        jsr PRD16
        jsr CRLF
        jsr PRS
        .byte "Field  Name        Type  Width  Dec",13,10,0
        stz IX
@f:     ldx IX
        cpx NFLD
        beq @end
        jsr FLDPTR
        inx
        stx T16
        stz T16+1
        lda #5
        jsr PRD16R
        lda #2
        jsr SPACES
        ldy #0              ; NAME, PADDED TO 12
@nm:    lda (FP),y
        beq @np
        jsr OUTC
        iny
        bra @nm
@np:    sty BT1
        lda #12
        sec
        sbc BT1
        jsr SPACES
        ldy #F_TYPE
        lda (FP),y
        ldx #0
@tn:    cmp TYPCH,x
        beq @tf
        inx
        bra @tn
@tf:    txa
        asl a
        asl a
        asl a
        tax
        ldy #0
@tp:    lda TYPNM,x
        jsr OUTC
        inx
        iny
        cpy #8
        bne @tp
        ldy #F_WID
        lda (FP),y
        sta T16
        stz T16+1
        lda #3
        jsr PRD16R
        ldy #F_TYPE
        lda (FP),y
        cmp #'N'
        bne @nd
        ldy #F_DEC
        lda (FP),y
        sta T16
        stz T16+1
        lda #5
        jsr PRD16R
@nd:    jsr CRLF
        jsr PAGECHK
        inc IX
        jmp @f
@end:   jsr PRS
        .byte "Record length ",0
        lda RECLEN
        sta T16
        lda RECLEN+1
        sta T16+1
        jsr PRD16
        jmp CRLF
TYPCH:  .byte "CNDL"
TYPNM:  .byte "Text    Number  Date    Logical "

; REPORT [fields] [scope] [FOR c]: COLUMNS WITH HEADINGS AND TOTALS
H_REPORT:
        jsr NEEDOPEN
        lda #1
        sta SMODE
        lda #1
        jsr PARSESCOPE
        jsr ALLFLDS         ; NO LIST: EVERY FIELD
        stz IX             ; EACH ITEM MUST BE A FIELD: WIDTHS
@w:     ldx IX
        cpx NITEMS
        beq @hd
        jsr ITEMFP
        bcc @ok
        lda #<M_RFLD
        ldy #>M_RFLD
        jmp ERRMSG
@ok:    jsr DSPWID          ; A = SHOWN WIDTH
        sta BT1
        jsr NAMELEN
        cmp BT1
        bcc @w1
        sta BT1
@w1:    ldx IX
        lda BT1
        sta COLW,x
        inc IX
        bra @w
@hd:    jsr CLRTOTS
        lda #7              ; HEADINGS
        jsr SPACES
        stz IX
@h:     ldx IX
        cpx NITEMS
        beq @h2
        jsr ITEMFP
        jsr NAMELEN
        sta BT1
        ldy #F_TYPE         ; NUMBERS: HEADING ON THE RIGHT
        lda (FP),y
        cmp #'N'
        bne @hl
        ldx IX
        lda COLW,x
        sec
        sbc BT1
        jsr SPACES
        jsr PRFNAME
        bra @hn
@hl:    jsr PRFNAME
        ldx IX
        lda COLW,x
        sec
        sbc BT1
        jsr SPACES
@hn:    jsr SPACE
        inc IX
        bra @h
@h2:    jsr CRLF
        lda #7
        jsr SPACES
        stz IX
@u:     ldx IX
        cpx NITEMS
        beq @u2
        lda COLW,x
        tax
        lda #'-'
@ul:    jsr OUTC
        dex
        bne @ul
        jsr SPACE
        inc IX
        bra @u
@u2:    jsr CRLF
        stz CNT16
        stz CNT16+1
        lda #<REPCB
        sta CBVEC
        lda #>REPCB
        sta CBVEC+1
        jsr FOREACH
        lda #7              ; TOTALS
        jsr SPACES
        stz IX
@t:     ldx IX
        cpx NITEMS
        beq @t2
        jsr ITEMFP
        ldy #F_TYPE
        lda (FP),y
        cmp #'N'
        beq @tn
        ldx IX
        lda COLW,x
        inc a
        jsr SPACES
        bra @tx
@tn:    jsr TOTFA
        ldy #F_DEC
        lda (FP),y
        jsr FIXSTR
        ldx IX
        lda COLW,x
        sec
        sbc OLEN
        bcc @tw
        jsr SPACES
@tw:    jsr PROBUF
        jsr SPACE
@tx:    inc IX
        bra @t
@t2:    jsr CRLF
        lda CNT16
        sta T16
        lda CNT16+1
        sta T16+1
        jsr PRD16
        jsr PRS
        .byte " records",0
        jmp CRLF
M_RFLD: .byte "REPORT LISTS FIELDS ONLY",0

REPCB:  inc CNT16
        bne @c
        inc CNT16+1
@c:     lda RECNO
        sta T16
        lda RECNO+1
        sta T16+1
        lda #5
        jsr PRD16R
        lda RECBUF
        jsr OUTC
        jsr SPACE
        stz IX
@i:     ldx IX
        cpx NITEMS
        beq @e
        jsr ITEMFP
        jsr FLDTEXT
        ldy #F_TYPE
        lda (FP),y
        cmp #'N'
        bne @p
        jsr FLDVAL          ; ADD IT TO ITS TOTAL
        jsr TOTADD
        jsr FLDTEXT
@p:     jsr PRDSP
        ldx IX
        lda COLW,x
        sec
        sbc DSPLEN
        bcc @s
        jsr SPACES
@s:     jsr SPACE
        inc IX
        bra @i
@e:     jsr CRLF
        jmp PAGECHK

; FP = THE FIELD THAT ITEM X NAMES.  C=1 IF IT IS NOT A FIELD
ITEMFP: lda ITP
        sta TP
        lda ITP+1
        sta TP+1
        lda ITEMPOS,x
        sta TI
        jmp ITEMFLD
; A = WIDTH FIELD FP IS SHOWN IN
DSPWID: ldy #F_TYPE
        lda (FP),y
        cmp #'D'
        bne @1
        lda #10
        rts
@1:     cmp #'L'
        bne @2
        lda #3
        rts
@2:     ldy #F_WID
        lda (FP),y
        rts
; A = LENGTH OF FIELD FP'S NAME
NAMELEN: ldy #0
@l:     lda (FP),y
        beq @r
        iny
        bra @l
@r:     tya
        rts
PRFNAME: ldy #0
@l:     lda (FP),y
        beq @r
        jsr OUTC
        iny
        bra @l
@r:     rts

; NO ITEMS GIVEN: MAKE "F1,F2,..." IN ITBUF AND USE THAT
ALLFLDS: lda NITEMS
        bne @r
        lda #<ITBUF
        sta ITP
        lda #>ITBUF
        sta ITP+1
        stz IX             ; FIELD
        ldx #0              ; POSITION IN ITBUF
@f:     lda IX
        cmp NFLD
        beq @e
        phx
        ldx IX
        jsr FLDPTR
        plx
        ldy NITEMS          ; THIS ITEM STARTS HERE
        txa
        sta ITEMPOS,y
        inc NITEMS
        ldy #0
@c:     lda (FP),y
        beq @cm
        sta ITBUF,x
        inx
        iny
        bra @c
@cm:    lda #','
        sta ITBUF,x
        inx
        inc IX
        bra @f
@e:     stz ITBUF-1,x       ; (OVER THE LAST COMMA)
@r:     rts
; ONLY THE NUMBER FIELDS (FOR SUM AND AVERAGE WITH NO LIST)
NUMFLDS: lda NITEMS
        bne @r
        lda #<ITBUF
        sta ITP
        lda #>ITBUF
        sta ITP+1
        stz IX
        ldx #0
@f:     lda IX
        cmp NFLD
        beq @e
        phx
        ldx IX
        jsr FLDPTR
        plx
        ldy #F_TYPE
        lda (FP),y
        cmp #'N'
        bne @n
        ldy NITEMS
        txa
        sta ITEMPOS,y
        inc NITEMS
        ldy #0
@c:     lda (FP),y
        beq @cm
        sta ITBUF,x
        inx
        iny
        bra @c
@cm:    lda #','
        sta ITBUF,x
        inx
@n:     inc IX
        bra @f
@e:     cpx #0
        beq @r
        stz ITBUF-1,x
@r:     rts

; TOTALS: TOTS + 8*IX
CLRTOTS: ldx #0
@l:     stz TOTS,x
        inx
        cpx #24*8
        bne @l
        rts
TOTPTR: lda IX
        asl a
        asl a
        asl a
        clc
        adc #<TOTS
        sta PTR
        lda #>TOTS
        adc #0
        sta PTR+1
        rts
TOTADD: jsr TOTPTR          ; TOTAL += FA
        jsr FLDB
        jsr FADD
        jsr TOTPTR
        jmp FSTA
TOTFA:  jsr TOTPTR
        jmp FLDA

;=====================================================================
; COUNT, SUM, AVERAGE
;=====================================================================
H_COUNT: jsr NEEDOPEN
        lda #1
        sta SMODE
        lda #0
        jsr PARSESCOPE
        jsr DOCOUNT
        lda CNT16
        sta T16
        lda CNT16+1
        sta T16+1
        jsr PRD16
        jsr PRS
        .byte " records",0
        jmp CRLF
DOCOUNT: stz CNT16
        stz CNT16+1
        lda #<CNTCB
        sta CBVEC
        lda #>CNTCB
        sta CBVEC+1
        jmp FOREACH
CNTCB:  inc CNT16
        bne @r
        inc CNT16+1
@r:     rts

H_AVG:  lda #1
        bra SUMGO
H_SUM:  lda #0
SUMGO:  pha
        jsr NEEDOPEN
        lda #1
        sta SMODE
        lda #1
        jsr PARSESCOPE
        jsr NUMFLDS
        jsr CLRTOTS
        stz CNT16
        stz CNT16+1
        lda #<SUMCB
        sta CBVEC
        lda #>SUMCB
        sta CBVEC+1
        jsr FOREACH
        stz IX             ; SHOW EACH: ITEM = VALUE
@s:     ldx IX
        cpx NITEMS
        bne :+
        jmp @c
:
        lda ITP             ; THE ITEM'S TEXT
        sta TP
        lda ITP+1
        sta TP+1
        lda ITEMPOS,x
        sta TI
        sta BT3
        jsr SKIPEXPR        ; FIND WHERE THE ITEM ENDS
        ldy TI
@tb:    cpy BT3             ; (NOT ITS TRAILING SPACES)
        beq @te0
        dey
        lda (TP),y
        cmp #' '
        beq @tb
        iny
@te0:   sty BT4
        ldy BT3
@t:     cpy BT4
        beq @te
        lda (TP),y
        jsr OUTC
        iny
        bra @t
@te:    jsr PRS
        .byte " = ",0
        jsr TOTFA
        pla
        pha
        beq @pr
        lda CNT16           ; AVERAGE
        ora CNT16+1
        beq @pr
        jsr FAB
        lda CNT16
        sta T16
        lda CNT16+1
        sta T16+1
        jsr FINT16
        jsr FSWAP
        jsr FDIV
@pr:    lda #'N'
        sta VT
        pla                 ; AVERAGE: AS MANY DIGITS AS NEEDED
        pha
        bne @gen
        jsr FAB             ; A FIELD ON ITS OWN: ITS DECIMAL PLACES
        ldx IX
        lda ITEMPOS,x
        sta TI
        jsr ITEMFLD
        jsr FBA
        bcs @gen
        ldy #F_DEC
        lda (FP),y
        jsr FIXSTR
        jsr PROBUF
        bra @pe
@gen:   jsr VALTEXT
        jsr PRDSP
@pe:    jsr CRLF
        inc IX
        jmp @s
@c:     pla
        lda CNT16
        sta T16
        lda CNT16+1
        sta T16+1
        jsr PRD16
        jsr PRS
        .byte " records",0
        jmp CRLF
SUMCB:  inc CNT16
        bne @c
        inc CNT16+1
@c:     stz IX
@l:     ldx IX
        cpx NITEMS
        beq @r
        lda ITP
        sta TP
        lda ITP+1
        sta TP+1
        lda ITEMPOS,x
        sta TI
        jsr EVAL
        jsr NEEDN
        jsr TOTADD
        inc IX
        bra @l
@r:     rts

;=====================================================================
; GO, SKIP, ?, LOCATE, CONTINUE
;=====================================================================
H_GO:   jsr NEEDOPEN
        lda #<KW_TOP
        ldy #>KW_TOP
        jsr KW
        bcs @1
        jmp GOTOP
@1:     lda #<KW_BOT
        ldy #>KW_BOT
        jsr KW
        bcs C_GOTO
        lda NREC
        ldy NREC+1
        bne @g
        cmp #0
        bne @g
        jmp GOTOP
@g:     jmp SETREC
C_GOTO: jsr NEEDOPEN
        jsr GETNUM16
        jsr NEEDEND
        lda CNT16
        sta RFROM
        lda CNT16+1
        sta RFROM+1
        jsr CHKREC
        lda RFROM
        ldy RFROM+1
        jmp SETREC

H_SKIP: jsr NEEDOPEN
        lda #1              ; SKIP [N]  (N CAN BE NEGATIVE)
        sta CNT16
        stz CNT16+1
        stz SKSIGN
        jsr PEEK
        beq @go
        cmp #'-'
        bne @n
        inc SKSIGN
        jsr NEXT
@n:     jsr GETNUM16
@go:    lda SKSIGN
        bne @back
        clc                 ; FORWARD
        lda RECNO
        adc CNT16
        sta RFROM
        lda RECNO+1
        adc CNT16+1
        sta RFROM+1
        lda NREC+1          ; PAST THE END?
        cmp RFROM+1
        bne @c
        lda NREC
        cmp RFROM
@c:     bcs @set
        lda NREC
        ldy NREC+1
        jsr SETREC
        lda #1
        sta EOFF
        jsr PRS
        .byte "End of file",13,10,0
        rts
@back:  sec
        lda RECNO
        sbc CNT16
        sta RFROM
        lda RECNO+1
        sbc CNT16+1
        sta RFROM+1
        bcc @bof
        ora RFROM
        bne @set
@bof:   lda #1
        sta RFROM
        stz RFROM+1
        jsr PRS
        .byte "Top of file",13,10,0
@set:   lda RFROM
        ora RFROM+1
        bne @s2
        rts
@s2:    lda RFROM
        ldy RFROM+1
        jmp SETREC

; ? expr, expr ...
C_PRINT:
@l:     jsr PEEK
        beq @e
        jsr EVALX0
        jsr VALTEXT
        jsr PRDSP
        jsr PEEK
        cmp #','
        bne @e
        jsr NEXT
        jsr SPACE
        bra @l
@e:     jsr NEEDEND
        jmp CRLF
EVALX0: stz VSP             ; EVAL, KEEPING THE TEXT WORK AREA
        jmp EVALX           ; (SO EARLIER VALUES ON THE LINE STAY)

H_LOCATE:
        jsr NEEDOPEN
        lda #1
        sta SMODE
        lda #0
        jsr PARSESCOPE
        lda FORPOS
        bne @k
        jmp ESYNTAX
@k:     ldx #LBMAX          ; KEEP THE LINE FOR CONTINUE
@c:     lda LBUF,x
        sta LOCBUF,x
        dex
        bpl @c
        lda #<LOCBUF
        sta CTP
        lda #>LOCBUF
        sta CTP+1
        lda FORPOS
        sta LOCPOS
        lda SMODE
        sta LOCMODE
        bra LOCGO
H_CONT: jsr NEEDOPEN
        lda LOCPOS
        bne @k
        lda #<M_NOLOC
        ldy #>M_NOLOC
        jmp ERRMSG
@k:     sta FORPOS
        lda #<LOCBUF
        sta CTP
        lda #>LOCBUF
        sta CTP+1
        lda #4              ; FROM THE NEXT RECORD TO THE END
        sta SMODE
        inc RECNO
        bne @n
        inc RECNO+1
@n:     lda NREC+1
        cmp RECNO+1
        bne @c2
        lda NREC
        cmp RECNO
@c2:    bcs LOCGO
        jmp LOCEND
LOCGO:  lda #<LOCCB
        sta CBVEC
        lda #>LOCCB
        sta CBVEC+1
        jsr FOREACH
        lda STOPF
        bne LOCFND
LOCEND: lda NREC
        ldy NREC+1
        jsr SETREC
        lda #1
        sta EOFF
        jsr PRS
        .byte "End of locate",13,10,0
        rts
LOCFND: jsr PRS
        .byte "Record = ",0
        lda RECNO
        sta T16
        lda RECNO+1
        sta T16+1
        jsr PRD16
        jmp CRLF
LOCCB:  lda #1
        sta STOPF
        rts
M_NOLOC: .byte "NO LOCATE TO CONTINUE",0
        .bss
LOCPOS: .res 1
LOCMODE: .res 1
        .code

;=====================================================================
; REPLACE [scope] field WITH expr [, field WITH expr] [FOR c]
;=====================================================================
H_REPL: jsr NEEDOPEN
        stz SMODE
        stz NPAIR
        stz FORPOS
        lda #<LBUF
        sta CTP
        lda #>LBUF
        sta CTP+1
@l:     jsr PEEK
        bne @0
        jmp @do
@0:     lda #<KW_ALL
        ldy #>KW_ALL
        jsr KW
        bcs @1
        lda #1
        sta SMODE
        bra @l
@1:     lda #<KW_NEXT
        ldy #>KW_NEXT
        jsr KW
        bcs @2
        jsr GETNUM16
        lda CNT16
        sta SCNT
        lda CNT16+1
        sta SCNT+1
        lda #2
        sta SMODE
        bra @l
@2:     lda #<KW_FOR
        ldy #>KW_FOR
        jsr KW
        bcs @3
        lda TI
        sta FORPOS
        lda SMODE           ; FOR WITH NO SCOPE: ALL RECORDS
        bne @do
        lda #1
        sta SMODE
        bra @do
@3:     jsr GETNAME         ; FIELD WITH EXPR
        bcc @f
        jmp ESYNTAX
@f:     jsr FINDFLD
        bcc @f2
        jmp NOVAR
@f2:    ldy NPAIR
        cpy #12
        bcc @f3
        jmp ESYNTAX
@f3:    txa
        sta PFLD,y
        lda #<KW_WITH
        ldy #>KW_WITH
        jsr KW
        bcc @w
        jmp ESYNTAX
@w:     jsr PEEK
        ldy NPAIR
        lda TI
        sta PPOS,y
        inc NPAIR
        jsr SKIPEXPR
        jsr PEEK
        cmp #','
        beq :+
        jmp @l
:
        jsr NEXT
        jmp @l
@do:    lda NPAIR
        bne @d
        jmp ESYNTAX
@d:     stz CNT16
        stz CNT16+1
        lda #<REPLCB
        sta CBVEC
        lda #>REPLCB
        sta CBVEC+1
        jsr FOREACH
        lda CNT16
        sta T16
        lda CNT16+1
        sta T16+1
        jsr PRD16
        jsr PRS
        .byte " records replaced",0
        jsr CRLF
        jmp FLUSHALL
REPLCB: stz IX
@l:     ldx IX
        cpx NPAIR
        beq @w
        lda #<LBUF
        sta TP
        lda #>LBUF
        sta TP+1
        lda PPOS,x
        sta TI
        jsr EVAL
        ldx IX
        lda PFLD,x
        tax
        jsr FLDPTR
        jsr STOREFLD
        inc IX
        bra @l
@w:     lda RECNO
        ldy RECNO+1
        jsr PUTREC
        inc CNT16
        bne @r
        inc CNT16+1
@r:     rts

;=====================================================================
; DELETE, RECALL, PACK, ZAP
;=====================================================================
H_DELETE: lda #'*'
        bra DELGO
H_RECALL: lda #' '
DELGO:  sta DELCH
        jsr NEEDOPEN
        stz SMODE
        lda #0
        jsr PARSESCOPE
        stz CNT16
        stz CNT16+1
        lda #<DELCB
        sta CBVEC
        lda #>DELCB
        sta CBVEC+1
        jsr FOREACH
        lda CNT16
        sta T16
        lda CNT16+1
        sta T16+1
        jsr PRD16
        lda DELCH
        cmp #'*'
        bne @r
        jsr PRS
        .byte " records deleted",0
        bra @e
@r:     jsr PRS
        .byte " records recalled",0
@e:     jsr CRLF
        jmp FLUSHALL
DELCB:  lda DELCH
        cmp RECBUF
        beq @r
        sta RECBUF
        lda RECNO
        ldy RECNO+1
        jsr PUTREC
        inc CNT16
        bne @r
        inc CNT16+1
@r:     rts
        .bss
DELCH:  .res 1
        .code

; PACK: SLIDE THE RECORDS UP OVER THE DELETED ONES.  CONTEXT 0 READS,
; CONTEXT 1 (THE SAME FILE) WRITES; THE WRITE POSITION IS NEVER AHEAD.
H_PACK: jsr NEEDOPEN
        jsr NEEDEND
        jsr FLUSHALL
        lda CXSTART
        sta CXSTART+1
        lda CXNT
        sta CXNT+1
        lda #$FF
        sta CXCUR+1
        stz CXDIRTY+1
        stz RFROM           ; READ POSITION (0-BASED)
        stz RFROM+1
        stz RTO             ; WRITE POSITION
        stz RTO+1
@l:     lda RFROM
        cmp NREC
        bne @rd
        lda RFROM+1
        cmp NREC+1
        beq @done
@rd:    lda RFROM
        sta RN
        lda RFROM+1
        sta RN+1
        ldx #0
        jsr RECADDR
        lda (GP)
        cmp #'*'
        beq @next           ; DELETED: DROP IT
        lda RFROM           ; SAME PLACE: NOTHING TO MOVE
        cmp RTO
        bne @mv
        lda RFROM+1
        cmp RTO+1
        beq @kept
@mv:    lda GP              ; (GP) -> RECBUF2
        pha
        lda GP+1
        pha
        lda #<RECBUF2
        sta GP2
        lda #>RECBUF2
        sta GP2+1
        jsr CPYREC
        pla
        pla
        lda RTO
        sta RN
        lda RTO+1
        sta RN+1
        ldx #1
        jsr RECADDR
        lda GP
        sta GP2
        lda GP+1
        sta GP2+1
        lda #<RECBUF2
        sta GP
        lda #>RECBUF2
        sta GP+1
        jsr CPYREC
        lda #1
        sta CXDIRTY+1
@kept:  inc RTO
        bne @next
        inc RTO+1
@next:  inc RFROM
        bne @l
        inc RFROM+1
        jmp @l
@done:  ldx #1
        jsr CXFLUSH
        lda #$FF            ; CONTEXT 0'S COPY IS OLD NOW
        sta CXCUR
        sta CXCUR+1
        lda RTO
        sta NREC
        lda RTO+1
        sta NREC+1
        lda #1
        sta HDIRTY
        jsr FLUSHALL
        jsr GOTOP
        jmp SAYCOUNT

H_ZAP:  jsr NEEDOPEN
        jsr NEEDEND
        jsr PRS
        .byte "Remove ALL the records? (Y/N) ",0
        jsr YESNO
        beq @y
        rts
@y:     stz NREC
        stz NREC+1
        lda #1
        sta HDIRTY
        jsr FLUSHALL
        jmp GOTOP

;=====================================================================
; SORT ON field TO file [DESCENDING]
; KEYS (RECORD NUMBER + UP TO 16 BYTES OF THE FIELD) ARE SORTED IN
; MEMORY; THEN THE NEW FILE IS WRITTEN IN PASSES, EACH PASS READING
; THE OLD FILE IN ORDER AND COLLECTING THE RECORDS FOR A STRETCH OF
; THE NEW ONE.
;=====================================================================
        .bss
SKL:    .res 1              ; KEY LENGTH
SEL:    .res 1              ; ENTRY LENGTH (KEY + 2)
SDESC:  .res 1
STYP:   .res 1
SFLD:   .res 1
SGAP:   .res 2
SI:     .res 2
SJ:     .res 2
WREC:   .res 2              ; RECORDS PER PASS
WBASE:  .res 2              ; WINDOW BUFFER
PSTART: .res 2
RANKP:  .res 2
TMPE:   .res 20
        .code

H_SORT: jsr NEEDOPEN
        lda #<KW_ON
        ldy #>KW_ON
        jsr KW
        bcc @on
@syn:   jmp ESYNTAX
@on:    jsr GETNAME
        bcs @syn
        jsr FINDFLD
        bcc @f
        jmp NOVAR
@f:     stx SFLD
        lda #<KW_TO
        ldy #>KW_TO
        jsr KW
        bcs @syn
        jsr GETFNAME
        bcs @syn
        stz SDESC
        lda #<KW_DESC
        ldy #>KW_DESC
        jsr KW
        bcs @nd
        inc SDESC
@nd:    jsr NEEDEND
        ldx #0              ; NOT ONTO ITSELF
@sm:    lda FNAME,x
        cmp DBNAME,x
        bne @diff
        cmp #0
        beq @same
        inx
        bra @sm
@same:  lda #<M_SELF
        ldy #>M_SELF
        jmp ERRMSG
@diff:  jsr FLUSHALL
        ldx SFLD            ; KEY SIZE
        jsr FLDPTR
        ldy #F_TYPE
        lda (FP),y
        sta STYP
        ldx #8
        cmp #'N'
        beq @kl
        cmp #'D'
        beq @kl
        ldy #F_WID
        lda (FP),y
        tax
        cpx #13
        bcc @kl
        ldx #12
@kl:    stx SKL
        inx
        inx
        stx SEL
        lda NREC            ; ENOUGH ROOM?  ENTRIES*N <= 8K
        sta M1
        lda NREC+1
        sta M1+1
        lda SEL
        sta M2
        stz M2+1
        jsr MUL16
        lda M3+1
        cmp #>(SORTEND-SORTMEM)
        bcc @room
        lda #<M_SBIG
        ldy #>M_SBIG
        jmp ERRMSG
@room:  jsr PRS
        .byte "Reading keys...",13,10,0
        lda #<SORTMEM       ; 1. READ THE KEYS
        sta KP
        lda #>SORTMEM
        sta KP+1
        lda #1
        sta SI
        stz SI+1
@rk:    lda NREC+1
        cmp SI+1
        bne @rk1
        lda NREC
        cmp SI
@rk1:   bcc @sort
        lda SI
        ldy SI+1
        jsr GETREC
        lda SI              ; RECORD NUMBER
        sta (KP)
        ldy #1
        lda SI+1
        sta (KP),y
        ldx SFLD
        jsr FLDPTR
        lda STYP
        cmp #'N'
        bne @kc
        jsr FLDVAL          ; NUMBER: THE 8-BYTE VALUE
        ldy #2
        ldx #0
@kn:    lda FA,x
        sta (KP),y
        iny
        inx
        cpx #8
        bne @kn
        bra @kx
@kc:    jsr FLDADDR         ; TEXT / DATE / LOGICAL: THE CHARACTERS
        ldy #0
@kt:    lda (GP),y
        iny
        iny
        sta (KP),y
        dey
        cpy SKL
        bne @kt
@kx:    clc
        lda KP
        adc SEL
        sta KP
        bcc @k2
        inc KP+1
@k2:    inc SI
        bne @rk
        inc SI+1
        bra @rk
@sort:  jsr PRS
        .byte "Sorting...",13,10,0
        jsr SHELL           ; 2. SORT THEM
        jsr PRS             ; 3. THE NEW FILE
        .byte "Writing...",13,10,0
        jsr MAKECOPY
        jsr RANKS           ; RECORD NUMBER -> NEW POSITION
        jsr COPYPASS        ; 4. COPY IN PASSES
        lda #$FF
        sta CXCUR
        jsr PRS
        .byte "Sorted into ",0
        ldx #0
@pn:    lda FNAME,x
        beq @pe
        jsr OUTC
        inx
        bra @pn
@pe:    jsr CRLF
        jmp GOTOP
M_SELF: .byte "SORT TO A DIFFERENT FILE",0
M_SBIG: .byte "TOO MANY RECORDS TO SORT",0

; ENTRY I (SI) ADDRESS -> GP, J (SJ) -> GP2
ENTADR: lda SI
        sta M1
        lda SI+1
        sta M1+1
        lda SEL
        sta M2
        stz M2+1
        jsr MUL16
        clc
        lda M3
        adc #<SORTMEM
        sta GP
        lda M3+1
        adc #>SORTMEM
        sta GP+1
        lda SJ
        sta M1
        lda SJ+1
        sta M1+1
        jsr MUL16
        clc
        lda M3
        adc #<SORTMEM
        sta GP2
        lda M3+1
        adc #>SORTMEM
        sta GP2+1
        rts

; COMPARE KEYS (GP) AND (GP2): C=1 IF (GP) SHOULD COME AFTER (GP2)
KEYGT:  lda STYP
        cmp #'N'
        beq @n
        ldy #2
        ldx SKL
@c:     lda (GP),y
        cmp (GP2),y
        bne @d
        iny
        dex
        bne @c
@eq:    clc                 ; EQUAL: NOT AFTER
        rts
@d:     lda #0
        rol a               ; 1 IF GREATER
        eor SDESC
        lsr a
        rts
@n:     ldy #9              ; NUMBERS
        ldx #7
@nl:    lda (GP),y
        sta FA,x
        lda (GP2),y
        sta FB,x
        dey
        dex
        bpl @nl
        jsr FCMP
        cmp #0
        beq @eq
        cmp #1
        beq @gt
        lda SDESC           ; LESS
        lsr a
        rts
@gt:    lda SDESC
        eor #1
        lsr a
        rts

; SHELL SORT OF THE NREC ENTRIES
SHELL:  lda NREC
        sta SGAP
        lda NREC+1
        sta SGAP+1
@gap:   lsr SGAP+1          ; GAP = GAP / 2
        ror SGAP
        lda SGAP
        ora SGAP+1
        bne @g1
        rts
@g1:    lda SGAP            ; I FROM GAP TO N-1
        sta SI
        lda SGAP+1
        sta SI+1
@i:     lda SI+1
        cmp NREC+1
        bne @i1
        lda SI
        cmp NREC
@i1:    bcs @gap
        lda SI              ; J = I
        sta TJ
        lda SI+1
        sta TJ+1
@j:     sec                 ; WHILE J >= GAP AND E[J-GAP] > E[J]: SWAP
        lda TJ
        sbc SGAP
        sta SJ
        lda TJ+1
        sbc SGAP+1
        sta SJ+1
        bcc @ni
        lda SI              ; (ENTADR WORKS ON SI/SJ: USE SI = J)
        pha
        lda SI+1
        pha
        lda TJ
        sta SI
        lda TJ+1
        sta SI+1
        jsr ENTADR          ; GP = E[J], GP2 = E[J-GAP]
        pla
        sta SI+1
        pla
        sta SI
        jsr @swapgt         ; IS E[J-GAP] > E[J]?
        bcc @ni
        lda SJ
        sta TJ
        lda SJ+1
        sta TJ+1
        bra @j
@ni:    inc SI
        bne @i
        inc SI+1
        bra @i
@swapgt: lda GP             ; COMPARE (GP2) WITH (GP): SWAP GP/GP2
        pha
        lda GP+1
        pha
        lda GP2
        sta GP
        lda GP2+1
        sta GP+1
        pla
        sta GP2+1
        pla
        sta GP2
        jsr KEYGT           ; E[J-GAP] AFTER E[J]?
        bcc @no
        ldy #0              ; SWAP THE ENTRIES
@sw:    lda (GP),y
        tax
        lda (GP2),y
        sta (GP),y
        txa
        sta (GP2),y
        iny
        cpy SEL
        bne @sw
        sec
@no:    rts
        .bss
TJ:     .res 2
        .code

; MAKE THE NEW FILE (SAME SIZE AND FIELDS), CONTEXT 1 ON IT
MAKECOPY:
        lda CXNT            ; MS 0000 (TRACKS*8-2)FF NAME
        asl a
        asl a
        asl a
        sec
        sbc #2
        sta IX
        lda #<MSCMD
        sta MP
        lda #>MSCMD
        sta MP+1
        jsr CMDSTART
        lda IX
        jsr CMDHEX
        lda #$FF
        jsr CMDHEX
        lda #' '
        jsr CMDCH
        jsr CMDNAME
        jsr DOSCALL
        jsr FINDFILE
        bcc @f
        jmp DSKERR
@f:     lda FTRK0
        sta CXSTART+1
        lda FTRKN
        sta CXNT+1
        ldx #0              ; ITS TRACK 0: THE HEADER, SAME COUNT
@c:     lda HDR,x
        sta TRKBUF1,x
        lda HDR+256,x
        sta TRKBUF1+256,x
        inx
        bne @c
        stz CXCUR+1
        lda #1
        sta CXDIRTY+1
        rts

; RANKS: THE SORTED ENTRIES BECOME A LIST OF RECORD NUMBERS (2 BYTES
; EACH) AT SORTMEM, THEN RANKP[RECORD] = NEW POSITION (0-BASED)
RANKS:  lda #<SORTMEM
        sta GP
        sta GP2
        lda #>SORTMEM
        sta GP+1
        sta GP2+1
        lda NREC
        sta SI
        lda NREC+1
        sta SI+1
@c:     lda SI
        ora SI+1
        beq @r0
        ldy #0
        lda (GP),y
        sta (GP2),y
        iny
        lda (GP),y
        sta (GP2),y
        clc
        lda GP
        adc SEL
        sta GP
        bcc @c1
        inc GP+1
@c1:    clc
        lda GP2
        adc #2
        sta GP2
        bcc @c2
        inc GP2+1
@c2:    lda SI
        bne @c3
        dec SI+1
@c3:    dec SI
        bra @c
@r0:    lda GP2             ; RANK TABLE FOLLOWS THE LIST
        sta RANKP
        lda GP2+1
        sta RANKP+1
        stz SI              ; POSITION
        stz SI+1
        lda #<SORTMEM
        sta GP
        lda #>SORTMEM
        sta GP+1
@r:     lda SI
        cmp NREC
        bne @r1
        lda SI+1
        cmp NREC+1
        beq @w
@r1:    ldy #0              ; RECORD NUMBER
        lda (GP),y
        sta M1
        iny
        lda (GP),y
        sta M1+1
        lda M1              ; RANKP + (REC-1)*2
        bne @r2
        dec M1+1
@r2:    dec M1
        asl M1
        rol M1+1
        clc
        lda M1
        adc RANKP
        sta GP2
        lda M1+1
        adc RANKP+1
        sta GP2+1
        lda SI
        sta (GP2)
        ldy #1
        lda SI+1
        sta (GP2),y
        clc
        lda GP
        adc #2
        sta GP
        bcc @r3
        inc GP+1
@r3:    inc SI
        bne @r
        inc SI+1
        bra @r
@w:     lda NREC            ; WINDOW AFTER THE RANKS: RANKP + 2*NREC
        asl a
        sta WBASE
        lda NREC+1
        rol a
        sta WBASE+1
        clc
        lda WBASE
        adc RANKP
        sta WBASE
        lda WBASE+1
        adc RANKP+1
        sta WBASE+1
        sec                 ; RECORDS THAT FIT = (SORTEND-WBASE)/RECLEN
        lda #<SORTEND
        sbc WBASE
        sta M1
        lda #>SORTEND
        sbc WBASE+1
        sta M1+1
        lda RECLEN
        sta M2
        lda RECLEN+1
        sta M2+1
        jsr DIV16
        lda M1
        sta WREC
        lda M1+1
        sta WREC+1
        ora WREC
        bne @ok
        lda #<M_SBIG
        ldy #>M_SBIG
        jmp ERRMSG
@ok:    rts

; THE PASSES
COPYPASS:
        stz PSTART
        stz PSTART+1
@pass:  lda PSTART+1        ; DONE?
        cmp NREC+1
        bne @p1
        lda PSTART
        cmp NREC
@p1:    bcc @p2
        ldx #1
        jsr CXFLUSH
        rts
@p2:    stz SI              ; READ EVERY RECORD, IN ORDER
        stz SI+1
        lda RANKP
        sta GP2
        lda RANKP+1
        sta GP2+1
@rd:    lda SI
        cmp NREC
        bne @rd1
        lda SI+1
        cmp NREC+1
        bne :+
        jmp @wr
:
@rd1:   ldy #0              ; ITS NEW POSITION - PSTART
        sec
        lda (GP2),y
        sbc PSTART
        sta M1
        iny
        lda (GP2),y
        sbc PSTART+1
        sta M1+1
        bcc @nx             ; BEFORE THIS PASS
        lda M1+1
        cmp WREC+1
        bne @w1
        lda M1
        cmp WREC
@w1:    bcs @nx             ; AFTER THIS PASS
        lda RECLEN          ; INTO THE WINDOW AT M1*RECLEN
        sta M2
        lda RECLEN+1
        sta M2+1
        jsr MUL16
        clc                 ; WHERE IN THE WINDOW
        lda M3
        adc WBASE
        sta SP2
        lda M3+1
        adc WBASE+1
        sta SP2+1
        lda SI
        sta RN
        lda SI+1
        sta RN+1
        lda GP2
        pha
        lda GP2+1
        pha
        ldx #0
        jsr RECADDR         ; GP = THE OLD RECORD
        lda SP2
        sta GP2
        lda SP2+1
        sta GP2+1
        jsr CPYREC
        pla
        sta GP2+1
        pla
        sta GP2
@nx:    clc
        lda GP2
        adc #2
        sta GP2
        bcc @n2
        inc GP2+1
@n2:    inc SI
        beq :+
        jmp @rd
:
        inc SI+1
        jmp @rd
@wr:    stz SJ              ; WRITE THE WINDOW TO THE NEW FILE
        stz SJ+1
        lda WBASE
        sta SP1
        lda WBASE+1
        sta SP1+1
@wl:    clc                 ; POSITION = PSTART + SJ
        lda PSTART
        adc SJ
        sta RN
        lda PSTART+1
        adc SJ+1
        sta RN+1
        lda RN+1            ; PAST THE END, OR THE WINDOW?
        cmp NREC+1
        bne @wl1
        lda RN
        cmp NREC
@wl1:   bcs @next
        lda SJ+1
        cmp WREC+1
        bne @wl2
        lda SJ
        cmp WREC
@wl2:   bcs @next
        ldx #1
        jsr RECADDR
        lda GP
        sta GP2
        lda GP+1
        sta GP2+1
        lda SP1
        sta GP
        lda SP1+1
        sta GP+1
        jsr CPYREC
        lda #1
        sta CXDIRTY+1
        clc
        lda SP1
        adc RECLEN
        sta SP1
        lda SP1+1
        adc RECLEN+1
        sta SP1+1
        inc SJ
        bne @wl
        inc SJ+1
        bra @wl
@next:  clc
        lda PSTART
        adc WREC
        sta PSTART
        lda PSTART+1
        adc WREC+1
        sta PSTART+1
        jmp @pass

;=====================================================================
; DIR, SET, HELP, QUIT
;=====================================================================
H_DIR:  jsr FLUSHALL
        lda #<DICMD
        sta MP
        lda #>DICMD
        sta MP+1
        jsr CMDSTART
        jsr DOSCALL
        jmp CRLF
DICMD:  .byte "DI",13,0

H_SET:  lda #<KW_LINES
        ldy #>KW_LINES
        jsr KW
        bcc @l
        jmp ESYNTAX
@l:     jsr GETNUM16
        lda CNT16+1
        bne @bad
        lda CNT16
        cmp #12
        bcc @bad
        cmp #61
        bcs @bad
        sta NLINES
        sta NLDEF
        rts
@bad:   lda #<M_LINES
        ldy #>M_LINES
        jmp ERRMSG
M_LINES: .byte "LINES MUST BE 12-60",0

H_QUIT: jmp QUIT

H_HELP: lda #<HELPTXT
        sta GP
        lda #>HELPTXT
        sta GP+1
@l:     lda (GP)
        beq @e
        cmp #$0A
        bne @c
        jsr CRLF
        jsr PAGECHK         ; (PAGECHK USES MP, SO GP IS USED HERE)
        bra @n
@c:     jsr OUTC
@n:     inc GP
        bne @l
        inc GP+1
        bra @l
@e:     rts

HELPTXT:
        .byte "CREATE name        new database (asks for the fields)",$0A
        .byte "USE name           open a database (USE alone closes it)",$0A
        .byte "APPEND [BLANK]     add records on a form",$0A
        .byte "EDIT [n]           change records on a form",$0A
        .byte "BROWSE             a table of records (RETURN edits one)",$0A
        .byte "LIST / DISPLAY [scope] [fields] [OFF] [FOR condition]",$0A
        .byte "LIST STRUCTURE     the fields",$0A
        .byte "REPORT [fields] [FOR c]   columns with totals",$0A
        .byte "GO n / TOP / BOTTOM,  SKIP [n],  n alone goes to record n",$0A
        .byte "LOCATE FOR c,  CONTINUE",$0A
        .byte "REPLACE [scope] field WITH value [, ...] [FOR c]",$0A
        .byte "DELETE / RECALL [scope] [FOR c],  PACK,  ZAP",$0A
        .byte "COUNT [FOR c],  SUM / AVERAGE [fields] [FOR c]",$0A
        .byte "SORT ON field TO newname [DESCENDING]",$0A
        .byte "? value, value     print values",$0A
        .byte "DIR,  SET LINES n,  CLOSE,  QUIT",$0A
        .byte "scope: ALL, NEXT n, RECORD n   (DISPLAY/DELETE: this record)",$0A
        .byte "values: fields, 12.5, ",$22,"text",$22,", .T. .F., + - * /",$0A
        .byte "  = <> < > <= >= $ (contained in)  .AND. .OR. .NOT.",$0A
        .byte "  UPPER LOWER TRIM LEN SUBSTR VAL STR INT ABS ROUND",$0A
        .byte "  RECNO() DELETED() CTOD(",$22,"dd/mm/yyyy",$22,") DTOC IIF SPACE",$0A
        .byte 0
