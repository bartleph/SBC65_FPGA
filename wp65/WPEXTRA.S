;=====================================================================
; WPEXTRA.S - BLOCKS, FIND AND REPLACE, PRINTING
;=====================================================================
        .bss
FINDS:  .res 62             ; WHAT TO FIND (0-ENDED)
FLEN:   .res 1
REPS:   .res 62             ; WHAT TO PUT IN ITS PLACE
REPLN:  .res 1
FU:     .res 1              ; OPTIONS: U IGNORE CASE, G WHOLE TEXT,
FG:     .res 1              ;          N DON'T ASK
FN:     .res 1
FLAST:  .res 1              ; ^L: 1 FIND AGAIN, 2 REPLACE AGAIN
SPOS:   .res 2
SLIM:   .res 2
MATCH:  .res 2
RCOUNT: .res 2
SVB:    .res 5
MSGBUF: .res 40
        .code

;=====================================================================
; BLOCKS
;=====================================================================
K_BEGIN: lda CUR
        sta BLKB
        lda CUR+1
        sta BLKB+1
        bra BLKSHOW
K_END:  lda CUR
        sta BLKE
        lda CUR+1
        sta BLKE+1
BLKSHOW: lda #1
        sta BLKON
        jmp MAIN
K_HIDE: lda BLKON
        eor #1
        sta BLKON
        jmp MAIN
; IS THERE A BLOCK?  C=0 YES, WITH TMP = ITS LENGTH
BLKOK:  lda BLKB+1
        cmp #$FF
        beq @no
        lda BLKE+1
        cmp #$FF
        beq @no
        sec
        lda BLKE
        sbc BLKB
        sta TMP
        lda BLKE+1
        sbc BLKB+1
        sta TMP+1
        bcc @no
        ora TMP
        beq @no
        clc
        rts
@no:    lda #<M_NOBLK
        ldy #>M_NOBLK
        jmp ERRMSG
M_NOBLK: .byte "NO BLOCK: MARK ITS BEGINNING WITH ^KB AND ITS END WITH ^KK",0
; IS THE CURSOR INSIDE THE BLOCK (BLKB < CUR < BLKE)?  THEN STOP
NOTIN:  lda BLKB
        cmp CUR
        lda BLKB+1
        sbc CUR+1
        bcs @ok             ; BLKB >= CUR
        lda CUR
        cmp BLKE
        lda CUR+1
        sbc BLKE+1
        bcs @ok             ; CUR >= BLKE
        lda #<M_INBLK
        ldy #>M_INBLK
        jmp ERRMSG
@ok:    rts
M_INBLK: .byte "THE CURSOR IS INSIDE THE BLOCK",0
; ENOUGH ROOM FOR TMP MORE CHARACTERS?
ROOM:   sec
        lda GE
        sbc GS
        tax
        lda GE+1
        sbc GS+1
        cmp TMP+1
        bne @c
        cpx TMP
@c:     bcs @ok
        jmp FULL
@ok:    rts

; DELETE THE BLOCK (THE CURSOR GOES TO WHERE IT WAS)
K_BDEL: jsr BLKOK
        jsr BLKCUT
        jmp MAIN
BLKCUT: lda BLKB
        sta OFF
        lda BLKB+1
        sta OFF+1
        jsr MOVETO
        jsr BLKOK           ; (TMP = LENGTH)
        clc                 ; THE GAP SWALLOWS IT
        lda GE
        adc TMP
        sta GE
        lda GE+1
        adc TMP+1
        sta GE+1
        sec
        lda TLEN
        sbc TMP
        sta TLEN
        lda TLEN+1
        sbc TMP+1
        sta TLEN+1
        lda #$FF
        sta BLKB+1
        sta BLKE+1
        lda #1
        sta MODF
        rts

; COPY THE BLOCK TO THE CURSOR; THE COPY BECOMES THE BLOCK
K_COPY: jsr BLKCOPY
        lda SPOS            ; THE COPY BECOMES THE BLOCK
        sta BLKB
        sta OFF
        lda SPOS+1
        sta BLKB+1
        sta OFF+1
        lda CUR
        sta BLKE
        lda CUR+1
        sta BLKE+1
        jsr MOVETO
        jmp MAIN
BLKCOPY: jsr BLKOK
        jsr NOTIN
        jsr ROOM
        lda CUR             ; WHERE THE COPY GOES
        sta SPOS
        lda CUR+1
        sta SPOS+1
        lda TMP
        sta SLIM
        lda TMP+1
        sta SLIM+1
@l:     lda SLIM            ; (INSCH MOVES THE BLOCK ALONG IF IT IS AFTER)
        ora SLIM+1
        beq @d
        lda BLKB            ; COPIED SO FAR = CUR - SPOS
        clc
        adc CUR
        sta OFF
        lda BLKB+1
        adc CUR+1
        sta OFF+1
        sec
        lda OFF
        sbc SPOS
        sta OFF
        lda OFF+1
        sbc SPOS+1
        sta OFF+1
        jsr CHARAT
        jsr INSCH
        lda SLIM
        bne @1
        dec SLIM+1
@1:     dec SLIM
        bra @l
@d:     rts

; MOVE THE BLOCK TO THE CURSOR
K_MOVE: jsr BLKCOPY         ; COPY IT, THEN DELETE THE ORIGINAL
        lda SPOS            ; (THE COPY IS AT SPOS..CUR)
        sta MATCH
        lda SPOS+1
        sta MATCH+1
        sec
        lda CUR
        sbc SPOS
        sta RCOUNT
        lda CUR+1
        sbc SPOS+1
        sta RCOUNT+1
        lda BLKB            ; WAS THE ORIGINAL BEFORE THE COPY?
        cmp SPOS
        lda BLKB+1
        sbc SPOS+1
        php
        jsr BLKCUT
        plp
        bcs @af
        sec                 ; YES: THE COPY MOVED BACK
        lda MATCH
        sbc RCOUNT
        sta MATCH
        lda MATCH+1
        sbc RCOUNT+1
        sta MATCH+1
@af:    lda MATCH           ; THE BLOCK IS NOW THE MOVED TEXT
        sta BLKB
        sta OFF
        lda MATCH+1
        sta BLKB+1
        sta OFF+1
        clc
        lda MATCH
        adc RCOUNT
        sta BLKE
        lda MATCH+1
        adc RCOUNT+1
        sta BLKE+1
        jsr MOVETO
        jmp MAIN

;=====================================================================
; FIND AND REPLACE
;=====================================================================
; ASK FOR WHAT TO FIND.  C=1 IF NOTHING
ASKFIND: ldx #0
@c:     lda FINDS,x
        sta LBUF,x
        beq @e
        inx
        bra @c
@e:     stx LLEN
        jsr ASK
        .byte "Find:",0
        bcs @no
        lda LLEN
        beq @no
        ldx #0
@cp:    lda LBUF,x
        sta FINDS,x
        beq @d
        inx
        bra @cp
@d:     stx FLEN
        clc
        rts
@no:    sec
        rts
; THE OPTIONS AFTER THE ASK
OPTS:   stz FU
        stz FG
        stz FN
        ldx #0
@l:     lda LBUF,x
        beq @r
        jsr UPPER
        cmp #'U'
        bne @1
        inc FU
@1:     cmp #'G'
        bne @2
        inc FG
@2:     cmp #'N'
        bne @3
        inc FN
@3:     inx
        bra @l
@r:     rts
; START FROM THE TOP (G) OR THE CURSOR
FSTART: lda FG
        beq @c
        stz OFF
        stz OFF+1
        rts
@c:     jmp OFFCUR

C_FIND: jsr ASKFIND
        bcs @x
        stz LLEN
        jsr ASK
        .byte "Options (U ignore case, G from the top):",0
        bcs @x
        jsr OPTS
        lda #1
        sta FLAST
        jsr FSTART
        jmp DOFIND
@x:     jmp MAIN
DOFIND: jsr SEARCH
        bcs NOTFND
        clc                 ; CURSOR AFTER WHAT WAS FOUND
        lda MATCH
        adc FLEN
        sta OFF
        lda MATCH+1
        adc #0
        sta OFF+1
        jmp GOOFF
NOTFND: lda #<M_NOTF
        ldy #>M_NOTF
        jsr SETMSG
        jmp MAIN
M_NOTF: .byte "NOT FOUND",0

C_AGAIN: lda FLAST
        cmp #1
        bne @r
        jsr OFFCUR
        jmp DOFIND
@r:     cmp #2
        bne @x
        stz FG
        jsr OFFCUR
        jmp REPGO
@x:     jmp MAIN

C_REPL: jsr ASKFIND
        bcs @x
        ldx #0
@c:     lda REPS,x
        sta LBUF,x
        beq @e
        inx
        bra @c
@e:     stx LLEN
        jsr ASK
        .byte "Replace with:",0
        bcs @x
        ldx #0
@cp:    lda LBUF,x
        sta REPS,x
        beq @d
        inx
        bra @cp
@d:     stx REPLN
        stz LLEN
        jsr ASK
        .byte "Options (G whole text, N don't ask, U ignore case):",0
        bcs @x
        jsr OPTS
        lda #2
        sta FLAST
        jsr FSTART
        jmp REPGO
@x:     jmp MAIN

REPGO:  stz RCOUNT
        stz RCOUNT+1
@l:     jsr SEARCH
        bcc @f
        jmp @done
@f:     lda MATCH
        sta OFF
        lda MATCH+1
        sta OFF+1
        jsr MOVETO
        lda FN
        beq :+
        jmp @do
:
        ldx #4              ; SHOW IT AS A BLOCK, THEN ASK
@sv:    lda BLKB,x
        sta SVB,x
        dex
        bpl @sv
        lda MATCH
        sta BLKB
        lda MATCH+1
        sta BLKB+1
        clc
        lda MATCH
        adc FLEN
        sta BLKE
        lda MATCH+1
        adc #0
        sta BLKE+1
        lda #1
        sta BLKON
        jsr REDRAW
        jsr ASKKEY
        .byte "Replace?  Y yes   N no   A all the rest   ESC stop",0
        pha
        ldx #4
@rs:    lda SVB,x
        sta BLKB,x
        dex
        bpl @rs
        pla
        cmp #'Y'
        beq @do
        cmp #'A'
        bne @nn
        inc FN
        bra @do
@nn:    cmp #'N'
        bne @done
        jsr OFFCUR          ; NO: LOOK ON FROM THE NEXT CHARACTER
        jsr OFFINC
        jmp @l
@do:    lda FLEN            ; DELETE IT, PUT IN THE NEW TEXT
        sta RDIF
@dl:    jsr DELFWD
        dec RDIF
        bne @dl
        ldx #0
@il:    cpx REPLN
        beq @id
        lda REPS,x
        phx
        jsr INSCH
        plx
        bcc @i2
        jmp FULL
@i2:    inx
        bra @il
@id:    inc RCOUNT
        bne @i3
        inc RCOUNT+1
@i3:    jsr OFFCUR
        jmp @l
@done:  lda RCOUNT          ; "nn REPLACED"
        sta TMP
        lda RCOUNT+1
        sta TMP+1
        jsr NUMSTR
        ldx #0
@m:     lda NUMB,x
        beq @m2
        sta MSGBUF,x
        inx
        bra @m
@m2:    ldy #0
@m3:    lda M_REPD,y
        sta MSGBUF,x
        beq @m4
        inx
        iny
        bra @m3
@m4:    lda #<MSGBUF
        ldy #>MSGBUF
        jsr SETMSG
        jsr FINDCOL
        jmp MAIN
M_REPD: .byte " REPLACED",0

; FIND FINDS FROM OFFSET OFF.  C=0: AT MATCH
SEARCH: lda OFF
        sta SPOS
        lda OFF+1
        sta SPOS+1
        sec                 ; THE LAST PLACE IT COULD START
        lda TLEN
        sbc FLEN
        sta SLIM
        lda TLEN+1
        sbc #0
        sta SLIM+1
        bcc @no
@set:   lda SPOS
        sta OFF
        lda SPOS+1
        sta OFF+1
        jsr ITSET
@l:     lda SLIM            ; SPOS > SLIM: NOT THERE
        cmp SPOS
        lda SLIM+1
        sbc SPOS+1
        bcc @no
        jsr ITGET
        ldx #0
        jsr FSAME
        beq @try
        inc SPOS
        bne @l
        inc SPOS+1
        bra @l
@try:   ldx #1              ; THE FIRST MATCHES: THE REST?
@t:     cpx FLEN
        beq @yes
        txa
        clc
        adc SPOS
        sta OFF
        lda SPOS+1
        adc #0
        sta OFF+1
        phx
        jsr CHARAT
        plx
        jsr FSAME
        bne @nx
        inx
        bra @t
@nx:    inc SPOS
        bne @set
        inc SPOS+1
        bra @set
@yes:   lda SPOS
        sta MATCH
        lda SPOS+1
        sta MATCH+1
        clc
        rts
@no:    sec
        rts
; A (TEXT) = FINDS,X ?  Z=1 YES
FSAME:  ldy FU
        beq @c
        jsr UPPER
        sta KCH
        lda FINDS,x
        jsr UPPER
        cmp KCH
        rts
@c:     cmp FINDS,x
        rts

;=====================================================================
; PRINTING.  A DOCUMENT IS FORMATTED: WORDS FILL THE LINES BETWEEN
; THE MARGINS, WITH PAGES, HEADERS AND FOOTERS AND THE DOT COMMANDS.
; ASSEMBLER AND BASIC ARE LISTED AS THEY ARE, WITH A HEADING.
;=====================================================================
        .bss
PMODE:  .res 1              ; 0 VIEW, 1 PRINT
LM:     .res 1
RM:     .res 1
PL:     .res 1
LS:     .res 1
JU:     .res 1
NF:     .res 1
CEN:    .res 1
PW:     .res 1              ; RM-LM
BODY:   .res 1              ; TEXT LINES ON A PAGE
PAGE:   .res 2
PLINE:  .res 1
INPAGE: .res 1
VLINES: .res 1
ATLS:   .res 1
INDENT: .res 1
POFF:   .res 2
HEB:    .res 62
FOB:    .res 62
OBUF:   .res 134
OLEN:   .res 1
WBUF:   .res 132
WLEN:   .res 1
JBUF:   .res 134
GAPS:   .res 1
GPER:   .res 1
GREM:   .res 1
GI:     .res 1
PCH:    .res 1
        .code

K_PRINT: jsr ASKKEY
        .byte "^KP  V view it on the screen   P print it to the console   ESC cancel",0
        ldx #0
        cmp #'V'
        beq @go
        inx
        cmp #'P'
        beq @go
        jmp MAIN
@go:    stx PMODE
        stz VLINES
        stz MERGE
        lda FTYPE           ; A DOCUMENT WITH .DF: A MAIL MERGE
        bne @one
        jsr PSCAN
@one:   jsr CLS
        lda MERGE
        bne @mm
        jsr PPASS           ; ONCE
        jmp PDONE
@mm:    jsr NEXTREC         ; ONCE FOR EACH RECORD
        bcc :+
        jmp PDONE
:
        jsr PPASS
        bra @mm

; ONE PRINTING OF THE WHOLE TEXT, FROM THE DEFAULTS
PPASS:  lda #5              ; THE DEFAULTS
        sta LM
        lda #75
        sta RM
        lda #66
        sta PL
        lda #1
        sta LS
        stz JU
        stz NF
        stz CEN
        stz HEB
        ldx #5
@f:     lda DEFFO,x
        sta FOB,x
        dex
        bpl @f
        lda #1
        sta PAGE
        stz PAGE+1
        stz INPAGE
        stz OLEN
        stz WLEN
        stz SUBN
        stz SUBI
        lda FTYPE           ; A LISTING: NAME AND PAGE AT THE TOP
        beq @doc
        stz LM
        lda #132
        sta RM
        lda #1
        sta NF
        stz FOB
        ldx #0
@n:     lda FNAME,x
        sta HEB,x
        beq @n2
        inx
        bra @n
@n2:    ldy #0
@n3:    lda M_PG,y
        sta HEB,x
        beq @doc
        inx
        iny
        bra @n3
@doc:   jsr SETPW
        stz OFF
        stz OFF+1
        stz POFF
        stz POFF+1
        jsr ITSET
        lda #1
        sta ATLS
        jsr FORMAT
        jsr FLUSHW          ; THE LAST LINE
        jsr ENDLINE
        lda INPAGE          ; AND THE LAST PAGE
        beq @r
        jsr FILLPG
        jmp PBOT
@r:     rts
PDONE:  ldx MAINSP          ; (ESC COMES HERE TOO)
        txs
        lda PMODE
        bne @p
        jsr PRS
        .byte 13,10,"End of the text - press a key",0
        jsr GETKEY
@p:     jsr FULLSCR
        jmp MAIN
DEFFO:  .byte "- # -",0
M_PG:   .byte "      Page #",0

SETPW:  lda RM              ; PRINT WIDTH, LINES OF TEXT ON A PAGE
        sec
        sbc LM
        bcc @s
        cmp #10
        bcs @1
@s:     lda #10
@1:     cmp #131
        bcc @2
        lda #130
@2:     sta PW
        lda PL
        cmp #12
        bcs @3
        lda #12
        sta PL
@3:     sec
        sbc #7
        sta BODY
        rts

; THE TEXT, A CHARACTER AT A TIME
FORMAT:
@l:     jsr PGET
        bcc @c
        rts
@c:     sta PCH
        ldx ATLS
        beq @mid
        stz ATLS            ; AT THE START OF A LINE
        cmp #'.'
        bne @nd
        lda FTYPE
        ora SUBF            ; (NOT A "." FROM A FIELD)
        bne @nd
        jsr ISDOT
        bcs @nd
        jsr DOTCMD
        lda #1
        sta ATLS
        bra @l
@nd:    lda PCH
        cmp #CR             ; AN EMPTY LINE
        bne @ns
        jsr FLUSHW
        jsr ENDLINE
        jsr BLANKL
        lda #1
        sta ATLS
        bra @l
@ns:    stz INDENT          ; LEADING SPACES: AN INDENT
        lda NF
        ora CEN
        bne @mid
@ind:   lda PCH
        cmp #' '
        bne @mid
        inc INDENT
        ldx OLEN
        sta OBUF,x
        inc OLEN
        jsr PGET
        bcc @i2
        rts
@i2:    sta PCH
        bra @ind
@mid:   lda PCH
        cmp #CR
        bne @nc
        jsr FLUSHW          ; THE END OF A PARAGRAPH (OR LINE)
        jsr ENDLINE
        lda #1
        sta ATLS
        bra @l
@nc:    ldx NF              ; AS IT IS (NO FILL, CENTRED)
        bne @raw
        ldx CEN
        bne @raw
        cmp #' '
        bne @w
        jsr FLUSHW          ; A SPACE ENDS A WORD
        jmp @l
@w:     ldx WLEN
        cpx #130
        bcs @j
        sta WBUF,x
        inc WLEN
@j:     jmp @l
@raw:   ldx OLEN
        cpx #132
        bcs @j
        sta OBUF,x
        inc OLEN
        jmp @l

PGET:   stz SUBF
        ldx SUBI            ; A FIELD'S TEXT BEING PRINTED?
        cpx SUBN
        bcs @t
        lda VALB,x
        inc SUBI
        inc SUBF
        clc
        rts
@t:     jsr ITGET
        bcs @r
        inc POFF
        bne @1
        inc POFF+1
@1:     cmp #'&'            ; &FIELD& IN A MAIL MERGE
        bne @ok
        ldx MERGE
        beq @ok
        jsr FIELDREF
        bcs @amp
        bra PGET            ; (ITS TEXT, WHICH MAY BE EMPTY)
@amp:   lda #'&'
@ok:    clc
@r:     rts

; A WORD IS COMPLETE: ADD IT TO THE LINE (PRINTING THE LINE IF FULL)
FLUSHW: lda WLEN
        beq @r
        lda OLEN            ; EMPTY (OR ONLY THE INDENT): NO SPACE
        cmp INDENT
        beq @put
        clc                 ; OLEN + 1 + WLEN > PW?  PRINT THE LINE FIRST
        adc WLEN
        bcs @full
        cmp PW
        bcc @sp
@full:  lda #1
        jsr OUTLINE
        bra @put
@sp:    ldx OLEN
        lda #' '
        sta OBUF,x
        inc OLEN
@put:   ldx OLEN
        ldy #0
@c:     cpy WLEN
        beq @d
        cpx #132
        bcs @d
        lda WBUF,y
        sta OBUF,x
        inx
        iny
        bra @c
@d:     stx OLEN
        stz WLEN
@r:     rts
; THE END OF A PARAGRAPH: PRINT WHAT IS LEFT (NOT JUSTIFIED)
ENDLINE: lda OLEN
        beq @r
        lda #0
        jmp OUTLINE
@r:     rts

; PRINT OBUF.  A=1: JUSTIFY IT (IF .JU IS ON)
OUTLINE: ldx CEN
        beq @nc
        dec CEN             ; CENTRED: SPACES IN FRONT
        jsr TRIMO
        lda PW
        sec
        sbc OLEN
        bcc @plain
        lsr a
        tax
        jsr BODYTOP
        txa
        clc
        adc LM
        jsr SPACES
        bra @text
@nc:    cmp #0
        beq @plain
        lda JU
        beq @plain
        jsr JUSTIFY
@plain: jsr BODYTOP
        lda LM
        jsr SPACES
@text:  ldx #0
@c:     cpx OLEN
        beq @e
        lda OBUF,x
        jsr OUTC
        inx
        bra @c
@e:     stz OLEN
        stz INDENT
        jsr BODYEND
        lda LS              ; LINE SPACING
@ls:    dec a
        beq @r
        pha
        jsr BLANKL
        pla
        bra @ls
@r:     rts
; TRAILING SPACES OFF OBUF
TRIMO:  ldx OLEN
        beq @r
        lda OBUF-1,x
        cmp #' '
        bne @r
        dec OLEN
        bra TRIMO
@r:     rts

; SPREAD THE SPACES SO THE LINE IS PW WIDE
JUSTIFY: jsr TRIMO
        ldx INDENT          ; COUNT THE GAPS AFTER THE INDENT
        stz GAPS
@g:     cpx OLEN
        beq @gd
        lda OBUF,x
        cmp #' '
        bne @g1
        inc GAPS
@g1:    inx
        bra @g
@gd:    lda GAPS
        beq @r
        lda PW
        sec
        sbc OLEN
        bcc @r
        beq @r
        ldx #0              ; PER GAP AND THE REMAINDER
@dv:    cmp GAPS
        bcc @dd
        sbc GAPS
        inx
        bra @dv
@dd:    sta GREM
        stx GPER
        ldx #0
        ldy #0
        stz GI
@cp:    cpx OLEN
        beq @fin
        lda OBUF,x
        sta JBUF,y
        iny
        cmp #' '
        bne @n
        cpx INDENT
        bcc @n
        lda GPER            ; EXTRA SPACES FOR THIS GAP
        sta TMP
        lda GI
        cmp GREM
        bcs @e1
        inc TMP
@e1:    inc GI
@e2:    lda TMP
        beq @n
        lda #' '
        sta JBUF,y
        iny
        dec TMP
        bra @e2
@n:     inx
        bra @cp
@fin:   sty OLEN
@m:     dey
        bmi @r
        lda JBUF,y
        sta OBUF,y
        bra @m
@r:     rts

; A BLANK LINE OF TEXT (NOT AT THE TOP OF A PAGE)
BLANKL: lda INPAGE
        beq @r
        jsr BODYTOP
        jmp BODYEND
@r:     rts
; BEFORE A LINE OF TEXT: THE TOP OF THE PAGE IF NEEDED
BODYTOP: phx
        lda INPAGE
        bne @r
        lda #1
        sta INPAGE
        stz PLINE
        jsr PNL
        jsr PNL
        lda #<HEB
        sta MP
        lda #>HEB
        sta MP+1
        jsr CENLINE
        jsr PNL
        jsr PNL
@r:     plx
        rts
; AFTER A LINE OF TEXT: THE BOTTOM OF THE PAGE IF FULL
BODYEND: jsr PNL
        inc PLINE
        lda PLINE
        cmp BODY
        bcc @r
        jmp PBOT
@r:     rts
PBOT:   jsr PNL
        lda #<FOB
        sta MP
        lda #>FOB
        sta MP+1
        jsr CENLINE
        jsr PNL
        jsr PNL
        inc PAGE
        bne @1
        inc PAGE+1
@1:     stz INPAGE
        lda PMODE           ; ON THE SCREEN: WHERE THE PAGE ENDS
        bne @r
        jsr REVON
        jsr PRS
        .byte "-------- end of page --------",0
        jsr REVOFF
        jsr PNL
@r:     rts
; PRINTING: BLANK LINES TO THE BOTTOM OF THE PAGE
FILLPG: lda PMODE
        beq @r
@l:     lda PLINE
        cmp BODY
        bcs @r
        jsr PNL
        inc PLINE
        bra @l
@r:     rts

; A HEADER OR FOOTER AT (MP), # = THE PAGE NUMBER, CENTRED, THEN CR LF
CENLINE: stz RLEN           ; (BUILT IN ROWBUF)
        ldy #0
@l:     lda (MP),y
        beq @e
        cmp #'#'
        bne @c
        phy
        lda PAGE
        sta TMP
        lda PAGE+1
        sta TMP+1
        lda MP
        pha
        lda MP+1
        pha
        jsr RNUM
        pla
        sta MP+1
        pla
        sta MP
        ply
        bra @n
@c:     phy
        jsr RCH
        ply
@n:     iny
        bra @l
@e:     lda RLEN
        beq @r
        lda PW
        sec
        sbc RLEN
        bcs @1
        lda #0
@1:     lsr a
        clc
        adc LM
        jsr SPACES
        ldx #0
@o:     cpx RLEN
        beq @r
        lda ROWBUF,x
        jsr OUTC
        inx
        bra @o
@r:     rts

; A NEW LINE ON THE OUTPUT.  ON THE SCREEN, STOP WHEN IT IS FULL;
; ESC STOPS EITHER WAY
PNL:    jsr CRLF
        jsr KEYHIT
        bcc @1
        cmp #$1B
        bne @1
        jmp PDONE
@1:     lda PMODE
        bne @r
        inc VLINES
        lda VLINES
        cmp ROWS
        bcc @r
        stz VLINES
        jsr REVON
        jsr PRS
        .byte "-- more: a key, ESC stops --",0
        jsr REVOFF
        jsr GETKEY
        cmp #$1B
        bne @2
        jmp PDONE
@2:     lda #$0D
        jsr OUTC
        jsr CLEOL
@r:     rts

; ---- DOT COMMANDS ---------------------------------------------------------
; A "." AT THE START OF A LINE: IS IT ONE OF OURS?  C=0 YES (X = WHICH)
ISDOT:  lda POFF
        sta OFF
        lda POFF+1
        sta OFF+1
        jsr CHARAT
        jsr UPPER
        sta TMP
        jsr OFFINC
        jsr CHARAT
        jsr UPPER
        sta TMP+1
        lda POFF            ; (BACK TO WHERE WE WERE)
        sta OFF
        lda POFF+1
        sta OFF+1
        jsr ITSET
        ldx #0
@l:     lda DOTTAB,x
        beq @no
        cmp TMP
        bne @n
        lda DOTTAB+1,x
        cmp TMP+1
        beq @yes
@n:     inx
        inx
        bra @l
@yes:   clc
        rts
@no:    sec
        rts
DOTTAB: .byte "LMRMPLLSHEFOCEPASPJUNJNFFIDF",0
; DO IT: THE REST OF THE LINE INTO LB2 FIRST
DOTCMD: stx GI
        jsr FLUSHW
        jsr ENDLINE
        stz LBL
@r:     jsr PGET
        bcs @g
        cmp #CR
        beq @g
        ldx LBL
        cpx #250
        bcs @r
        sta LB2,x
        inc LBL
        bra @r
@g:     ldx #2              ; ARGUMENT FROM AFTER THE TWO LETTERS
        stx TI
        jsr DOTNUM
        lda GI
        lsr a
        tax
        lda TMP             ; (THE NUMBER, IF ANY)
        cpx #0
        bne @1
        sta LM              ; .LM
        bra @pw
@1:     cpx #1
        bne @2
        sta RM              ; .RM
        bra @pw
@2:     cpx #2
        bne @3
        sta PL              ; .PL
@pw:    jmp SETPW
@3:     cpx #3
        bne @4
        cmp #1              ; .LS
        bcs @3a
        lda #1
@3a:    sta LS
        rts
@4:     cpx #4
        bne @5
        lda #<HEB           ; .HE
        bra @txt
@5:     cpx #5
        bne @6
        lda #<FOB           ; .FO
@txt:   sta GP
        lda #>HEB
        cpx #5
        bne @t0
        lda #>FOB
@t0:    sta GP+1
        ldx #2              ; SKIP ONE SPACE
        cpx LBL
        beq @t1
        lda LB2,x
        cmp #' '
        bne @t1
        inx
@t1:    ldy #0
@t2:    cpx LBL
        beq @t3
        cpy #60
        bcs @t3
        lda LB2,x
        sta (GP),y
        inx
        iny
        bra @t2
@t3:    lda #0
        sta (GP),y
        rts
@6:     cpx #6
        bne @7
        cmp #1              ; .CE [N]
        bcs @6a
        lda #1
@6a:    sta CEN
        rts
@7:     cpx #7
        bne @8
        lda INPAGE          ; .PA
        beq @r7
        jsr FILLPG
        jmp PBOT
@r7:    rts
@8:     cpx #8
        bne @9
        cmp #1              ; .SP [N]
        bcs @8a
        lda #1
@8a:    sta GI
@8b:    jsr BODYTOP
        jsr BODYEND
        dec GI
        bne @8b
        rts
@9:     cpx #9
        bne @10
        lda #1              ; .JU
        sta JU
        rts
@10:    cpx #10
        bne @11
        stz JU              ; .NJ
        rts
@11:    cpx #11
        bne @12
        lda #1              ; .NF
        sta NF
        rts
@12:    cpx #12
        bne @13
        stz NF              ; .FI
@13:    rts                 ; (.DF WAS DEALT WITH BEFORE PRINTING)
; A NUMBER IN LB2 FROM TI -> TMP (0 IF NONE, 255 AT MOST)
DOTNUM: stz TMP
        ldx TI
@sp:    cpx LBL
        beq @r
        lda LB2,x
        cmp #' '
        bne @d
        inx
        bra @sp
@d:     cpx LBL
        beq @r
        lda LB2,x
        jsr ISDIG
        bcs @r
        and #$0F
        sta TMP+1
        lda TMP             ; TMP*10 + DIGIT
        cmp #26
        bcs @big
        asl a
        asl a
        adc TMP
        asl a
        adc TMP+1
        bcs @big
        sta TMP
        inx
        bra @d
@big:   lda #255
        sta TMP
@r:     rts

;=====================================================================
; MAIL MERGE.  A DOCUMENT WITH A LINE  .DF B:PEOPLE  IS PRINTED ONCE FOR
; EACH RECORD OF THAT DB65 DATABASE (DELETED ONES ARE LEFT OUT), WITH
; &NAME& REPLACED BY THE RECORD'S NAME FIELD, AND SO ON.
;
; THE DB65 FILE: TRACK 0 BYTES 0-511 THE HEADER ("DB65", +4 RECORD
; COUNT, +6 RECORD LENGTH, +8 FIELD COUNT, +16 FIELDS OF 16 BYTES:
; NAME 11, TYPE, WIDTH, DECIMALS, OFFSET 2), THEN THE RECORDS, WHICH
; NEVER CROSS A TRACK.  EACH IS A DELETE FLAG AND THE FIELDS AS TEXT.
;=====================================================================
MHDR    = SHADOW            ; (THE SCREEN COPY IS FREE WHILE PRINTING)
MREC    = SHADOW+512
MRECMAX = 1024
        .bss
MERGE:  .res 1
SUBF:   .res 1              ; THE CHARACTER CAME FROM A FIELD
SUBI:   .res 1
SUBN:   .res 1
VALB:   .res 130            ; A FIELD'S TEXT
MLEFT:  .res 2              ; RECORDS STILL TO READ
MTRK:   .res 1
MOFF:   .res 2
MNAME:  .res 12
        .code

; LOOK FOR A .DF LINE; IF THERE IS ONE, OPEN THE DATABASE
PSCAN:  stz OFF
        stz OFF+1
        jsr ITSET
@line:  jsr ITGET           ; THE START OF A LINE
        bcs @none
        cmp #'.'
        bne @skip
        jsr ITGET
        bcs @none
        jsr UPPER
        cmp #'D'
        bne @skip
        jsr ITGET
        bcs @none
        jsr UPPER
        cmp #'F'
        beq @df
@skip:  cmp #CR             ; TO THE NEXT LINE
        beq @line
        jsr ITGET
        bcs @none
        bra @skip
@none:  rts
@df:    ldx #0              ; THE NAME INTO LBUF
@n:     jsr ITGET
        bcs @e
        cmp #CR
        beq @e
        cpx #60
        bcs @n
        sta LBUF,x
        inx
        bra @n
@e:     stz LBUF,x
        jsr KEEPNAME
        jsr SETNAME
        bcc @o
        lda #<M_NODF
        ldy #>M_NODF
        jmp FERR
@o:     lda FDRV
        jsr SETDRV
        jsr FINDFILE
        bcc @f
        lda #<M_NODB
        ldy #>M_NODB
        jmp FERR
@f:     jsr BACKNAME
        lda #$FF
        sta RDIDX
        lda #0
        jsr LOADTRK
        ldx #3              ; IS IT A DB65 FILE?
@sig:   lda TRKBUF,x
        cmp DBSIG,x
        bne @bad
        dex
        bpl @sig
        lda TRKBUF+7        ; RECORD LENGTH 2 TO MRECMAX
        cmp #>MRECMAX
        bcs @bad
        ldx #0              ; KEEP THE HEADER
@h:     lda TRKBUF,x
        sta MHDR,x
        lda TRKBUF+256,x
        sta MHDR+256,x
        inx
        bne @h
        lda MHDR+4
        sta MLEFT
        lda MHDR+5
        sta MLEFT+1
        stz MTRK
        stz MOFF
        lda #>512
        sta MOFF+1
        lda #1
        sta MERGE
        rts
@bad:   lda #<M_NOTDB
        ldy #>M_NOTDB
        jmp ERRMSG
DBSIG:  .byte "DB65"
M_NODF: .byte "THE .DF LINE NEEDS THE NAME OF A DB65 DATABASE",0
M_NODB: .byte "THE DATABASE IN THE .DF LINE IS NOT ON THE DISK",0
M_NOTDB: .byte "THE .DF FILE IS NOT A DB65 DATABASE",0

; THE NEXT RECORD (NOT DELETED) INTO MREC.  C=1 WHEN THERE ARE NO MORE
NEXTREC:
@l:     lda MLEFT
        ora MLEFT+1
        bne @1
        sec
        rts
@1:     lda MLEFT
        bne @2
        dec MLEFT+1
@2:     dec MLEFT
        clc                 ; DOES IT FIT IN THIS TRACK?
        lda MOFF
        adc MHDR+6
        sta TMP
        lda MOFF+1
        adc MHDR+7
        sta TMP+1
        cmp #>2048
        bcc @in
        bne @nt
        lda TMP
        beq @in
@nt:    inc MTRK            ; NO: THE START OF THE NEXT
        stz MOFF
        stz MOFF+1
        lda MHDR+6
        sta TMP
        lda MHDR+7
        sta TMP+1
@in:    lda MTRK
        jsr LOADTRK
        clc                 ; GP2 = THE RECORD IN TRKBUF
        lda MOFF
        adc #<TRKBUF
        sta GP2
        lda MOFF+1
        adc #>TRKBUF
        sta GP2+1
        lda TMP             ; (THE NEXT ONE STARTS AT THE END OF IT)
        sta MOFF
        lda TMP+1
        sta MOFF+1
        lda #<MREC
        sta GP
        lda #>MREC
        sta GP+1
        lda MHDR+6          ; COPY IT
        sta TMP
        lda MHDR+7
        sta TMP+1
        ldy #0
@c:     lda TMP
        ora TMP+1
        beq @d
        lda (GP2),y
        sta (GP),y
        iny
        bne @c2
        inc GP+1
        inc GP2+1
@c2:    lda TMP
        bne @c3
        dec TMP+1
@c3:    dec TMP
        bra @c
@d:     lda MREC            ; DELETED?  THEN THE NEXT
        cmp #'*'
        bne :+
        jmp @l
:
        clc
        rts

; "&" WAS JUST READ.  IF A FIELD NAME AND "&" FOLLOW, SKIP THEM AND PUT
; THE FIELD'S TEXT IN VALB.  C=1 IF NOT (THE "&" IS PRINTED AS IT IS)
FIELDREF:
        lda POFF
        sta OFF
        lda POFF+1
        sta OFF+1
        ldx #0
@n:     phx
        jsr CHARAT
        plx
        bcs @no
        cmp #'&'
        beq @end
        jsr UPPER
        cpx #11
        bcs @no
        sta MNAME,x
        inx
        jsr OFFINC
        bra @n
@end:   cpx #0
        beq @no
        stz MNAME,x
        stx GI
        jsr FINDFLD
        bcs @no
        jsr OFFINC          ; FOUND: GO ON AFTER THE SECOND "&"
        lda OFF
        sta POFF
        lda OFF+1
        sta POFF+1
        jsr ITSET
        jsr FLDTEXT
        clc
        rts
@no:    lda POFF            ; (BACK TO JUST AFTER THE "&")
        sta OFF
        lda POFF+1
        sta OFF+1
        jsr ITSET
        sec
        rts

; MNAME (GI LONG) IN THE HEADER?  C=0: GP = ITS 16-BYTE ENTRY
FINDFLD: lda #<(MHDR+16)
        sta GP
        lda #>(MHDR+16)
        sta GP+1
        ldx MHDR+8          ; HOW MANY FIELDS
        beq @no
@f:     ldy #0
@c:     lda (GP),y
        cmp MNAME,y
        bne @nx
        cmp #0
        beq @yes
        iny
        cpy #11
        bne @c
        lda MNAME,y         ; (AN 11-LETTER NAME)
        beq @yes
@nx:    clc
        lda GP
        adc #16
        sta GP
        bcc @1
        inc GP+1
@1:     dex
        bne @f
@no:    sec
        rts
@yes:   clc
        rts

; THE FIELD AT (GP) OF MREC -> VALB/SUBN, TIDIED:
; TEXT WITHOUT THE SPACES AROUND IT, DATES AS DD/MM/YYYY
FLDTEXT: ldy #14            ; GP2 = MREC + OFFSET
        clc
        lda (GP),y
        adc #<MREC
        sta GP2
        iny
        lda (GP),y
        adc #>MREC
        sta GP2+1
        ldy #12
        lda (GP),y          ; WIDTH
        cmp #128
        bcc @w
        lda #128
@w:     sta TI
        ldy #11
        lda (GP),y
        sta KCH             ; TYPE
        ldy #0              ; SKIP THE SPACES IN FRONT
@s:     cpy TI
        beq @e
        lda (GP2),y
        cmp #' '
        bne @e
        iny
        bra @s
@e:     ldx #0
@c:     cpy TI
        beq @t
        lda (GP2),y
        sta VALB,x
        inx
        iny
        bra @c
@t:     cpx #0              ; AND THE SPACES AFTER IT
        beq @z
        lda VALB-1,x
        cmp #' '
        bne @z
        dex
        bra @t
@z:     stx SUBN
        stz SUBI
        lda KCH             ; A DATE: YYYYMMDD -> DD/MM/YYYY
        cmp #'D'
        bne @r
        cpx #8
        bne @r
        ldx #7
@d:     lda VALB,x
        sta LB2,x
        dex
        bpl @d
        ldx #0
@o:     ldy DATEORD,x
        lda LB2,y
        cpy #$FF
        bne @p
        lda #'/'
@p:     sta VALB,x
        inx
        cpx #10
        bne @o
        stx SUBN
@r:     rts
DATEORD: .byte 6,7,$FF,4,5,$FF,0,1,2,3
