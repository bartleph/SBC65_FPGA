;=====================================================================
; WPFILE.S - LOADING AND SAVING.
;
; A FILE IS AN OS-65D WORKSPACE IMAGE OF MEMORY FROM $XX79, ONE 2K
; SECTOR (SECTOR 1) PER TRACK:
;   +0/1 START  +2/3 END  +4 TRACKS
;   START $XX7D  A WP65 DOCUMENT: THE TEXT FROM +5, LINES END IN CR
;   START $327E  ASSEMBLER SOURCE: LINES OF  NUMBER(LO,HI) TEXT CR,
;                A BYTE $80-$FF REPEATS THE CHARACTER BEFORE IT
;                256-N MORE TIMES
;   START $3A7F  BASIC: +5 = 0, THEN LINES OF  LINK(2) NUMBER(2)
;                TOKENS 0, ENDING WITH A LINK OF 0
;=====================================================================
        .bss
LTYP:   .res 1              ; THE FILE BEING READ: TYPE, BASE PAGE
LBSPG:  .res 1
DST:    .res 2              ;   ITS TEXT: FROM DST TO DEN IN THE IMAGE
DEN:    .res 2
RDOFF:  .res 2
RDIDX:  .res 1              ;   TRACK NOW IN TRKBUF ($FF = NONE)
LAST:   .res 1
RCNT:   .res 1
ONAME:  .res 16
RESTN:  .res 1
RSTART: .res 2
WMODE:  .res 1              ; WRITING: 0 = COUNT ONLY, 1 = WRITE
WOFF:   .res 2
WIDX:   .res 1
WEND:   .res 2
WT:     .res 1
LNUM:   .res 2
PRVNUM: .res 2
PRVSET: .res 1
DOFF:   .res 2
DOFFL:  .res 2
LB2:    .res 252
LBL:    .res 1
RLEND:  .res 1
TOKB:   .res 252
TLN:    .res 1
TI:     .res 1
TQ:     .res 1
TD:     .res 1
TOKREM: .res 1
TOKDAT: .res 1
TOKPRT: .res 1
        .code

; ---- FILE NAMES ------------------------------------------------------
; LBUF -> FNAME (UPPER CASE, AT MOST 14).  C=1 IF THERE IS NONE
SETNAME: ldx #0
        ldy #0
@sk:    lda LBUF,x          ; (LEADING SPACES)
        cmp #' '
        bne @c
        inx
        bra @sk
@c:     lda LBUF,x
        beq @e
        cmp #' '
        beq @e
        jsr UPPER
        sta FNAME,y
        inx
        iny
        cpy #14
        bne @c
@e:     lda #0
        sta FNAME,y
        cpy #0
        bne @ok
        sec
        rts
@ok:    clc
        rts
KEEPNAME: ldx #15           ; FNAME -> ONAME, TO PUT BACK IF THINGS FAIL
@l:     lda FNAME,x
        sta ONAME,x
        dex
        bpl @l
        lda #1
        sta RESTN
        rts
BACKNAME: lda RESTN
        beq @r
        stz RESTN
        ldx #15
@l:     lda ONAME,x
        sta FNAME,x
        dex
        bpl @l
@r:     rts
; ASK FOR A FILE NAME.  C=1 IF NONE
ASKLOAD: stz LLEN
        jsr ASK
        .byte "File to load:",0
        bcs @r
        jmp SETNAME
@r:     rts

; ---- ^KL LOAD ---------------------------------------------------------
K_LOAD: jsr SURELOSE
        bcs @x
        jsr KEEPNAME
        jsr ASKLOAD
        bcs @b
        jsr OPENRD
        jsr NEWDOC
        lda LTYP
        sta FTYPE
        lda LBSPG
        sta FBASE
        lda #1
        ldx LTYP
        beq @w
        lda #0
@w:     sta WWRAP
        stz RESTN           ; (THE NEW NAME STAYS)
        jsr READIN
        stz OFF
        stz OFF+1
        jsr MOVETO
        stz MODF
        jsr FULLSCR
        lda #<M_LOADED
        ldy #>M_LOADED
        jsr SETMSG
@x:     jmp MAIN
@b:     jsr BACKNAME
        jmp MAIN
M_LOADED: .byte "LOADED",0

; ---- ^KR READ A FILE IN AT THE CURSOR (IT BECOMES THE BLOCK) -------------
K_READ: jsr KEEPNAME
        jsr ASKLOAD
        bcs @b
        jsr OPENRD
        jsr BACKNAME
        lda CUR
        sta RSTART
        lda CUR+1
        sta RSTART+1
        lda #$FF
        sta BLKB+1
        sta BLKE+1
        jsr READIN
        lda CUR
        sta BLKE
        lda CUR+1
        sta BLKE+1
        lda RSTART
        sta BLKB
        lda RSTART+1
        sta BLKB+1
        lda #1
        sta BLKON
        lda BLKB
        sta OFF
        lda BLKB+1
        sta OFF+1
        jsr MOVETO
        jsr FULLSCR
        jmp MAIN
@b:     jsr BACKNAME
        jmp MAIN

; ---- OPEN A FILE: FIND IT, READ ITS FIRST TRACK, CHECK THE HEADER -------
OPENRD: jsr FINDFILE
        bcc @f
        lda #<M_NOFILE
        ldy #>M_NOFILE
        jmp FERR
@f:     lda #$FF
        sta RDIDX
        lda #0
        jsr LOADTRK
        lda TRKBUF          ; TYPE FROM THE START ADDRESS
        sec
        sbc #$7D
        cmp #3
        bcs BADF
        sta LTYP
        lda TRKBUF+1
        sta LBSPG
        lda #5              ; WHERE THE TEXT STARTS
        ldx LTYP
        cpx #2
        bne @d
        lda #6
@d:     sta DST
        stz DST+1
        sec                 ; END - $XX79
        lda TRKBUF+2
        sbc #$79
        sta DEN
        lda TRKBUF+3
        sbc LBSPG
        sta DEN+1
        bcc BADF
        lda DEN+1           ; DEN >= DST
        bne @2
        lda DEN
        cmp DST
        bcc BADF
@2:     lda FTRKN           ; AND INSIDE THE FILE: DEN <= TRACKS*2048
        asl a
        asl a
        asl a
        cmp DEN+1
        bcc BADF
        bne @3
        lda DEN
        bne BADF
@3:     lda DST
        sta RDOFF
        stz RDOFF+1
        lda LTYP
        cmp #2
        bne @r
        jsr KWCHECK
@r:     rts
BADF:   lda #<M_BADF
        ldy #>M_BADF
FERR:   pha
        phy
        jsr BACKNAME
        ply
        pla
        jmp ERRMSG
M_NOFILE: .byte "THERE IS NO FILE OF THAT NAME",0
M_BADF: .byte "THAT IS NOT A DOCUMENT, ASSEMBLER OR BASIC FILE",0

; BASIC'S KEYWORD TABLE MUST BE IN MEMORY
KWCHECK: lda KWTAB
        cmp #'E'
        bne @no
        lda KWTAB+1
        cmp #'N'
        bne @no
        lda KWTAB+2
        cmp #'D'|$80
        bne @no
        rts
@no:    lda #<M_NOKW
        ldy #>M_NOKW
        jmp FERR
M_NOKW: .byte "FOR BASIC FILES, RUN BASIC (BA) ONCE FIRST, THEN EXIT AND RUN WP65",0

; TRACK FTRK0 + A (BCD) -> A
TRKNUM: tax
        lda FTRK0
        sed
@l:     cpx #0
        beq @r
        clc
        adc #1
        dex
        bra @l
@r:     cld
        rts
; READ TRACK NUMBER A OF THE FILE INTO TRKBUF ("CA 6000=TT,1")
LOADTRK: cmp RDIDX
        beq @r
        sta RDIDX
        jsr TRKNUM
        pha
        lda #<CACMD
        sta MP
        lda #>CACMD
        sta MP+1
        jsr CMDSTART
        lda #>TRKBUF
        jsr CMDHEX
        lda #<TRKBUF
        jsr CMDHEX
        lda #'='
        jsr CMDCH
        pla
        jsr CMDHEX
        lda #<SEC1
        sta MP
        lda #>SEC1
        sta MP+1
        jsr CMDSTR
        jsr CMDEND
        jmp DOSCALL
@r:     rts
CACMD:  .byte "CA ",0
SEC1:   .byte ",1",0

; THE NEXT BYTE OF THE FILE'S TEXT -> A.  C=1 AT THE END
FGETB:  lda RDOFF
        cmp DEN
        bne @1
        lda RDOFF+1
        cmp DEN+1
        bne @1
        sec
        rts
@1:     lda RDOFF+1
        lsr a
        lsr a
        lsr a
        jsr LOADTRK
        lda RDOFF
        sta GP2
        lda RDOFF+1
        and #$07
        clc
        adc #>TRKBUF
        sta GP2+1
        lda (GP2)
        inc RDOFF
        bne @2
        inc RDOFF+1
@2:     clc
        rts

; ---- READ THE TEXT INTO THE DOCUMENT AT THE CURSOR ------------------------
READIN: lda LTYP
        beq RDTEXT
        cmp #1
        beq RDASM
        jmp RDBAS
PUTIN:  jsr INSCH
        bcs @full
        rts
@full:  lda #<M_PART
        ldy #>M_PART
        jmp ERRMSG
M_PART: .byte "THE TEXT IS FULL - ONLY PART OF THE FILE WAS READ",0

RDTEXT: jsr FGETB
        bcs @r
        cmp #$0A
        beq RDTEXT
        cmp #0
        beq RDTEXT
        jsr PUTIN
        bra RDTEXT
@r:     rts

RDASM:
@line:  jsr FGETB           ; THE LINE NUMBER (DROPPED)
        bcs @r
        jsr FGETB
        bcs @r
        lda #' '
        sta LAST
@ch:    jsr FGETB
        bcs @r
        cmp #CR
        beq @eol
        cmp #$80
        bcs @rep
        cmp #' '
        bcc @ch
        sta LAST
        jsr PUTIN
        bra @ch
@eol:   jsr PUTIN
        bra @line
@rep:   eor #$FF            ; 256-N MORE
        inc a
        sta RCNT
@rl:    lda LAST
        jsr PUTIN
        dec RCNT
        bne @rl
        bra @ch
@r:     rts

RDBAS:
@line:  jsr FGETB           ; LINK: 0 ENDS THE PROGRAM
        bcc :+
        jmp @r
:
        sta TMP
        jsr FGETB
        bcc :+
        jmp @r
:
        ora TMP
        beq @r
        jsr FGETB           ; LINE NUMBER
        bcs @r
        sta TMP2
        jsr FGETB
        bcs @r
        sta TMP+1
        lda TMP2
        sta TMP
        jsr NUMSTR
        ldx #0
@n:     lda NUMB,x
        beq @n2
        phx
        jsr PUTIN
        plx
        inx
        bra @n
@n2:    lda #' '
        jsr PUTIN
@ch:    jsr FGETB
        bcs @r
        cmp #0
        beq @eol
        cmp #$80
        bcs @kw
        jsr PUTIN
        bra @ch
@eol:   lda #CR
        jsr PUTIN
        bra @line
@kw:    and #$7F            ; KEYWORD NUMBER -> ITS TEXT
        tax
        lda #<KWTAB
        sta GP
        lda #>KWTAB
        sta GP+1
@sk:    cpx #0
        beq @out
@s2:    lda (GP)
        beq @unk
        jsr GPINC
        cmp #$80
        bcc @s2
        dex
        bra @sk
@out:   lda (GP)
        beq @unk
        pha
        and #$7F
        jsr PUTIN
        jsr GPINC
        pla
        bpl @out
        bra @ch
@unk:   lda #'?'
        jsr PUTIN
        bra @ch
@r:     rts
GPINC:  inc GP
        bne @r
        inc GP+1
@r:     rts

;=====================================================================
; SAVING.  ASK FOR THE NAME, COUNT THE BYTES, MAKE THE FILE WITH MS,
; THEN WRITE IT A TRACK AT A TIME.
;=====================================================================
SAVEDOC: ldx #0             ; THE NAME SO FAR AS THE SUGGESTION
@c:     lda FNAME,x
        sta LBUF,x
        beq @e
        inx
        bra @c
@e:     stx LLEN
        jsr ASK
        .byte "Save as:",0
        bcc @1
@x:     jmp MAIN
@1:     jsr SETNAME
        bcs @x
        lda FTYPE
        cmp #2
        bne @2
        jsr KWCHECK
        jsr KWTOKS
@2:     stz WMODE           ; PASS 1: HOW BIG?
        jsr ENCODE
        lda WOFF            ; END = $XX79 + SIZE
        clc
        adc #$79
        sta WEND
        lda WOFF+1
        adc FBASE
        sta WEND+1
        lda WOFF            ; TRACKS = (SIZE-1)/2048 + 1
        sec
        sbc #1
        lda WOFF+1
        sbc #0
        lsr a
        lsr a
        lsr a
        inc a
        sta WT
        lda #<MSCMD         ; "MS 0000 xxFF NAME", xx = 8*TRACKS-2
        sta MP
        lda #>MSCMD
        sta MP+1
        jsr CMDSTART
        lda WT
        asl a
        asl a
        asl a
        sec
        sbc #2
        jsr CMDHEX
        lda #<MSFF
        sta MP
        lda #>MSFF
        sta MP+1
        jsr CMDSTR
        jsr CMDNAME
        jsr DOSCALL
        jsr FINDFILE
        bcc @3
        lda #<M_DISK
        ldy #>M_DISK
        jmp ERRMSG
@3:     lda #1              ; PASS 2: WRITE IT
        sta WMODE
        jsr ENCODE
        lda WOFF+1
        and #$07
        ora WOFF
        beq @4
        jsr FLUSHTRK
@4:     stz MODF
        rts
MSCMD:  .byte "MS 0000 ",0
MSFF:   .byte "FF ",0

; ONE BYTE TO THE FILE
PUTB:   phx
        phy
        ldx WMODE
        beq @inc
        pha
        lda WOFF
        sta GP2
        lda WOFF+1
        and #$07
        clc
        adc #>TRKBUF
        sta GP2+1
        pla
        sta (GP2)
@inc:   inc WOFF
        bne @1
        inc WOFF+1
@1:     lda WMODE
        beq @r
        lda WOFF
        bne @r
        lda WOFF+1
        and #$07
        bne @r
        jsr FLUSHTRK
@r:     ply
        plx
        rts
; WRITE TRKBUF AS THE NEXT TRACK ("SA TT,1=6000/8")
FLUSHTRK: lda WIDX
        jsr TRKNUM
        pha
        lda #<SACMD
        sta MP
        lda #>SACMD
        sta MP+1
        jsr CMDSTART
        pla
        jsr CMDHEX
        lda #<SEC1
        sta MP
        lda #>SEC1
        sta MP+1
        jsr CMDSTR
        lda #'='
        jsr CMDCH
        lda #>TRKBUF
        jsr CMDHEX
        lda #<TRKBUF
        jsr CMDHEX
        lda #<SATAIL
        sta MP
        lda #>SATAIL
        sta MP+1
        jsr CMDSTR
        jsr CMDEND
        jsr DOSCALL
        inc WIDX
        rts
SACMD:  .byte "SA ",0
SATAIL: .byte "/8",0

; THE WHOLE FILE, THROUGH PUTB
ENCODE: stz WOFF
        stz WOFF+1
        stz WIDX
        lda FTYPE           ; HEADER
        clc
        adc #$7D
        jsr PUTB
        lda FBASE
        jsr PUTB
        lda WEND
        jsr PUTB
        lda WEND+1
        jsr PUTB
        lda WT
        jsr PUTB
        stz OFF
        stz OFF+1
        jsr ITSET
        stz DOFF
        stz DOFF+1
        lda FTYPE
        beq ENTEXT
        cmp #1
        bne :+
        jmp ENASM
:
        jmp ENBAS
ENTEXT: jsr ITGET
        bcs @r
        jsr PUTB
        bra ENTEXT
@r:     rts

; NEXT HARD LINE OF THE TEXT INTO LB2/LBL.  RLEND = 1 IF THE TEXT ENDED
RDLINE: lda DOFF
        sta DOFFL
        lda DOFF+1
        sta DOFFL+1
        stz LBL
        stz RLEND
@l:     jsr ITGET
        bcs @end
        inc DOFF
        bne @1
        inc DOFF+1
@1:     cmp #CR
        beq @r
        ldx LBL
        cpx #250
        bcs @long
        sta LB2,x
        inc LBL
        bra @l
@end:   lda #1
        sta RLEND
@r:     rts
@long:  lda #<M_LONG
        ldy #>M_LONG
LINEERR: pha                ; CURSOR TO THE LINE, THEN THE MESSAGE
        phy
        lda DOFFL
        sta OFF
        lda DOFFL+1
        sta OFF+1
        jsr MOVETO
        ply
        pla
        jmp ERRMSG
M_LONG: .byte "THIS LINE IS TOO LONG FOR THE FILE (250 CHARACTERS AT MOST)",0

ENASM:  lda #10
        sta LNUM
        stz LNUM+1
@line:  jsr RDLINE
        lda RLEND           ; NOTHING AFTER THE LAST CR
        beq @go
        lda LBL
        bne :+
        jmp @r
:
@go:    lda LNUM
        jsr PUTB
        lda LNUM+1
        jsr PUTB
        ldx #0
@ch:    cpx LBL
        beq @eol
        lda LB2,x
        cmp #' '
        bne @put
        stx TI              ; A RUN OF SPACES?
@run:   inx
        cpx LBL
        beq @re
        lda LB2,x
        cmp #' '
        beq @run
@re:    txa                 ; K = X - TI
        sec
        sbc TI
        cmp #3
        bcs @pack
        ldx TI              ; SHORT: AS IT IS
        lda #' '
@put:   jsr PUTB
        inx
        bra @ch
@pack:  dec a               ; ONE SPACE, THEN K-1 REPEATS (128 A BYTE)
        sta RCNT
        lda #' '
        jsr PUTB
@pk:    lda RCNT
        cmp #129
        bcc @p1
        lda #128
@p1:    pha
        eor #$FF            ; 256-C
        inc a
        jsr PUTB
        pla
        eor #$FF            ; RCNT -= C
        sec
        adc RCNT
        sta RCNT
        bne @pk
        bra @ch
@eol:   lda #CR
        jsr PUTB
        clc
        lda LNUM
        adc #10
        sta LNUM
        bcc @nx
        inc LNUM+1
@nx:    lda RLEND
        bne :+
        jmp @line
:
@r:     rts

; ---- BASIC --------------------------------------------------------------
; THE TOKENS FOR REM, DATA AND PRINT (FOR ?)
KWTOKS: ldx #<S_REM
        ldy #>S_REM
        jsr KWFIND
        sta TOKREM
        ldx #<S_DATA
        ldy #>S_DATA
        jsr KWFIND
        sta TOKDAT
        ldx #<S_PRINT
        ldy #>S_PRINT
        jsr KWFIND
        sta TOKPRT
        rts
S_REM:  .byte "REM",0
S_DATA: .byte "DATA",0
S_PRINT: .byte "PRINT",0
KWFIND: stx MP              ; WORD AT X/Y -> ITS TOKEN (0 IF NONE)
        sty MP+1
        ldy #0
@c:     lda (MP),y
        sta LB2,y
        beq @e
        iny
        bra @c
@e:     sty LBL
        stz TI
        jsr KWMATCH
        bcc @r
        lda #0
@r:     rts

; IS A KEYWORD AT LB2,TI?  C=0: A = TOKEN, TI MOVED PAST IT
KWMATCH: lda #<KWTAB
        sta GP
        lda #>KWTAB
        sta GP+1
        lda #$80
        sta KTOK
@kw:    lda (GP)
        beq @no
        ldy #0
        ldx TI
@c:     cpx LBL
        beq @miss
        lda LB2,x
        jsr UPPER
        sta KCH
        lda (GP),y
        and #$7F
        cmp KCH
        bne @miss
        lda (GP),y
        bmi @hit
        iny
        inx
        bra @c
@hit:   inx
        stx TI
        lda KTOK
        clc
        rts
@miss:  lda (GP),y          ; TO THE END OF THIS KEYWORD
        bmi @m2
        iny
        bra @miss
@m2:    tya
        sec
        adc GP
        sta GP
        bcc @m3
        inc GP+1
@m3:    inc KTOK
        bra @kw
@no:    sec
        rts
        .bss
KTOK:   .res 1
KCH:    .res 1
        .code

ENBAS:  lda #0              ; $XX7E
        jsr PUTB
        stz PRVSET
@line:  jsr RDLINE
        ldx #0              ; SKIP SPACES; A BLANK LINE IS DROPPED
@sp:    cpx LBL
        beq @blank
        lda LB2,x
        cmp #' '
        bne @num
        inx
        bra @sp
@blank: jmp @next
@num:   stz LNUM
        stz LNUM+1
        lda LB2,x
        jsr ISDIG
        bcs @nonum
@dg:    cpx LBL
        beq @dn
        lda LB2,x
        jsr ISDIG
        bcs @dn
        pha                 ; LNUM = LNUM*10 + DIGIT
        lda LNUM
        sta TMP
        lda LNUM+1
        sta TMP+1
        asl LNUM
        rol LNUM+1
        asl LNUM
        rol LNUM+1
        clc
        lda LNUM
        adc TMP
        sta LNUM
        lda LNUM+1
        adc TMP+1
        sta LNUM+1
        asl LNUM
        rol LNUM+1
        pla
        and #$0F
        clc
        adc LNUM
        sta LNUM
        bcc @d2
        inc LNUM+1
@d2:    lda LNUM+1
        cmp #$FA            ; 64000 AND UP: TOO BIG
        bcs @big
        inx
        bra @dg
@nonum: lda #<M_NONUM
        ldy #>M_NONUM
        jmp LINEERR
@big:   lda #<M_BIG
        ldy #>M_BIG
        jmp LINEERR
@order: lda #<M_ORDER
        ldy #>M_ORDER
        jmp LINEERR
@dn:    lda PRVSET          ; IN ORDER?
        beq @o1
        lda PRVNUM+1
        cmp LNUM+1
        bne @o0
        lda PRVNUM
        cmp LNUM
@o0:    bcs @order
@o1:    lda #1
        sta PRVSET
        lda LNUM
        sta PRVNUM
        lda LNUM+1
        sta PRVNUM+1
        cpx LBL             ; ONE SPACE AFTER THE NUMBER IS DROPPED
        beq @tk
        lda LB2,x
        cmp #' '
        bne @tk
        inx
@tk:    stx TI
        jsr TOKEN
        clc                 ; LINK = $XX79 + WOFF + 4 + TLN + 1
        lda WOFF
        adc #$79+5
        sta TMP
        lda WOFF+1
        adc FBASE
        sta TMP+1
        clc
        lda TMP
        adc TLN
        sta TMP
        bcc @l1
        inc TMP+1
@l1:    lda TMP
        jsr PUTB
        lda TMP+1
        jsr PUTB
        lda LNUM
        jsr PUTB
        lda LNUM+1
        jsr PUTB
        ldx #0
@out:   cpx TLN
        beq @o2
        lda TOKB,x
        jsr PUTB
        inx
        bra @out
@o2:    lda #0
        jsr PUTB
@next:  lda RLEND
        bne @end
        jmp @line
@end:   lda #0              ; THE END: A LINK OF 0
        jsr PUTB
        lda #0
        jmp PUTB
M_NONUM: .byte "THIS BASIC LINE HAS NO LINE NUMBER",0
M_BIG:  .byte "LINE NUMBERS MUST BE LESS THAN 64000",0
M_ORDER: .byte "BASIC LINE NUMBERS MUST GO UP - THIS ONE IS OUT OF ORDER",0
ISDIG:  cmp #'0'            ; C=0 FOR A DIGIT
        bcc @no
        cmp #'9'+1
        bcs @no
        clc
        rts
@no:    sec
        rts

; LB2 FROM TI -> TOKENS IN TOKB/TLN, AS BASIC DOES IT
TOKEN:  stz TLN
        stz TQ
        stz TD
@l:     ldx TI
        cpx LBL
        beq @r
        lda LB2,x
        ldy TQ              ; IN QUOTES: AS IT IS
        beq @1
        cmp #'"'
        bne @cp
        stz TQ
        bra @cp
@1:     cmp #'"'
        bne @2
        inc TQ
        bra @cp
@2:     ldy TD              ; DATA: AS IT IS TO A :
        beq @3
        cmp #':'
        bne @cp
        stz TD
        bra @cp
@3:     cmp #'?'
        bne @4
        lda TOKPRT
        bne @cp
        lda #'?'
        bra @cp
@4:     cmp #' '
        beq @cp
        cmp #'0'            ; DIGITS, : AND ;
        bcc @kw
        cmp #'<'
        bcc @cp
@kw:    jsr KWMATCH
        bcs @lit
        jsr TPUT
        cmp TOKDAT
        bne @k2
        lda #1
        sta TD
        bra @l
@k2:    cmp TOKREM
        bne @l
@rem:   ldx TI              ; REM: THE REST AS IT IS
        cpx LBL
        beq @r
        lda LB2,x
        jsr TPUT
        inc TI
        bra @rem
@lit:   ldx TI
        lda LB2,x
@cp:    jsr TPUT
        inc TI
        jmp @l
@r:     rts
TPUT:   ldy TLN
        cpy #250
        bcs @long
        sta TOKB,y
        inc TLN
        rts
@long:  lda #<M_LONG
        ldy #>M_LONG
        jmp LINEERR
