;=====================================================================
; CALC65 - A SUPERCALC-STYLE SPREADSHEET FOR THE SBC65 (FPGA, 48K)
;          UNDER THE OS-65D V3.3 ROM DOS
;
; BUILD:  ca65 --cpu 65C02 CALC.S -o CALC.o
;         ld65 -C calc.cfg CALC.o -o CALC.BIN
; LOAD AND RUN: HL (CALC65.HEX), THEN GO 4000.  SAVE IT WITH
;         MS 4000 6CFF CALC65   AND START IT AFTER THAT WITH  MR CALC65
;
; MEMORY: $4000-$6FFF PROGRAM, $7700 SHEET HEADER, $7800-$91FF CELL
;         TABLE, $9200-$BFFF CELL TEXT AND VALUES.
;         ZERO PAGE $30-$AF (SAVED AND PUT BACK ON EXIT).
; SCREEN: A VT100 TERMINAL ON THE CONSOLE ACIA, 80 COLUMNS.
;=====================================================================
        .setcpu "65C02"

ACIAS   = $C080             ; FPGA CONSOLE ACIA
ACIAD   = $C081

; ---- ROM DOS ENTRY POINTS (SBC65_FPGA ROM) ----
DRIVE   = $265C             ; THE DOS'S CURRENT DRIVE (1-4 = A-D)
DOCMD   = $E801             ; RUN THE COMMAND LINE AT (INBUF)
SETERR  = $E7FA             ; ERROR VECTOR = A (LO), Y (HI)
SEEK    = $E435
FINDNM  = $F0D2             ; FIND THE FILE NAMED ON THE COMMAND LINE
RDSEC1  = $FEFE             ; READ SECTOR A OF THE CURRENT TRACK TO (MEMLO)
INBUF   = $E1
CMDPOS  = $2CE5
CMDLEN  = $2CED
CMDBUF  = $2E1E
ENTPL   = $10
MEMLO   = $FE
DOSHDR  = $3300             ; ML READS A FILE'S FIRST SECTOR HERE

ZPBASE  = $30
ZPSIZE  = $80

K_UP    = $80
K_DN    = $81
K_RT    = $82
K_LF    = $83

        .code
        jmp START
NLDEF:  .byte 24            ; $4003: SCREEN LINES AT START (/G L SETS IT)

        .include "BCD.S"
        .include "CELLS.S"
        .include "EVAL.S"

        .zeropage
CCOL:   .res 1              ; CURSOR
CROW:   .res 1
LCOL:   .res 1              ; WINDOW: LEFT COLUMN, TOP ROW
TROW:   .res 1
U1:     .res 1
U2:     .res 1
U3:     .res 1
U4:     .res 1
CRP:    .res 2              ; RECORD BEING RECALCULATED
SPP:    .res 2              ; TEXT SPILLING INTO THE NEXT CELLS
MP:     .res 2              ; MESSAGE POINTER
RCP:    .res 2              ; RECALC: TABLE POSITION

        .bss
ZPSAVE: .res ZPSIZE
SAVESP: .res 1
DSKSP:  .res 1
NLINES: .res 1              ; SCREEN LINES
VROWS:  .res 1              ; SHEET ROWS ON SCREEN
VCN:    .res 1              ; COLUMNS ON SCREEN
VX:     .res NCOL+1         ; THEIR SCREEN COLUMNS (1-BASED)
DIRTY:  .res NROW           ; ROWS TO REDRAW
FULL:   .res 1              ; 1 = REDRAW EVERYTHING
PEND:   .res 1              ; SPACES WAITING TO BE PRINTED
SPILL:  .res 1              ; 1 = SPP HAS TEXT LEFT TO SHOW
INREV:  .res 1
PBK:    .res 1              ; A KEY PUT BACK
LASTK:  .res 1              ; KEY THAT ENDED THE LAST EDIT
EBUF:   .res 82             ; THE ENTRY LINE
ELEN:   .res 1
EDX:    .res 1              ; SCREEN COLUMN WHERE THE EDIT STARTS
DBUF:   .res 82             ; ONE CELL AS SHOWN
FNAME:  .res 16             ; LAST FILE NAME
FDRV:   .res 1              ; ITS DRIVE (1-4 = A-D)
ODRV:   .res 1              ; THE DOS'S DRIVE WHEN CALC65 STARTED
DEFDRV: .res 1              ; THE DRIVE FOR NAMES WITHOUT ONE (/N)
MSGON:  .res 1
RDI:    .res 1
TBUF:   .res 82             ; SCRATCH TEXT (REFERENCE ADJUSTING)
; RANGES FOR THE COMMANDS
SC1:    .res 1
SR1:    .res 1
SC2:    .res 1
SR2:    .res 1
TC1:    .res 1
TR1:    .res 1
TC2:    .res 1
TR2:    .res 1
ADJM:   .res 1              ; REFERENCE ADJUST MODE
ADJK:   .res 1              ; ROW/COLUMN FOR INSERT/DELETE
ADJDC:  .res 1
ADJDR:  .res 1
DC:     .res 1
DR:     .res 1
QC:     .res 1
QR:     .res 1
SPOS:   .res 1
        .code

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
        lda #<DSKERR        ; DOS ERRORS COME BACK TO US
        ldy #>DSKERR
        jsr SETERR
        lda NLDEF
        sta NLINES
        stz PBK
        stz FNAME
        lda DRIVE
        sta ODRV
        sta FDRV
        sta DEFDRV
        stz CCOL
        stz CROW
        stz LCOL
        stz TROW
        jsr CHKSHEET        ; A SHEET STILL IN MEMORY?
        bcc @kept
        jsr NEWSHEET
        bra @go
@kept:  jsr CALCGARB
        jsr MSG
        .byte "SHEET IN MEMORY KEPT (/Z CLEARS IT)",0
@go:    jsr SETVIEW
        lda #1
        sta FULL
        jmp MAIN

QUIT:   lda ODRV            ; THE DOS GETS ITS OWN DRIVE BACK
        jsr SETDRV
        jsr CLS
        ldx #ZPSIZE-1
@z:     lda ZPSAVE,x
        sta ZPBASE,x
        dex
        bpl @z
        ldx SAVESP
        txs
        rts                 ; BACK TO THE DOS

; IS THERE A GOOD SHEET IN MEMORY?  C=0 YES
CHKSHEET:
        ldx #3
@m:     lda H_MAGIC,x
        cmp MAGIC,x
        bne @no
        dex
        bpl @m
        lda H_TOP+1         ; HEAP TOP WITHIN THE HEAP?
        cmp #>HEAPBEG
        bcc @no
        cmp #>HEAPEND
        bcs @no
        ldx #NCOL-1
@w:     lda COLW,x
        beq @no
        cmp #73
        bcs @no
        dex
        bpl @w
        clc
        rts
@no:    sec
        rts
MAGIC:  .byte "C65S"

NEWSHEET:
        jsr CLEARALL
        ldx #3
@m:     lda MAGIC,x
        sta H_MAGIC,x
        dex
        bpl @m
        ldx #NCOL-1
@w:     lda #9
        sta COLW,x
        stz COLF,x
        dex
        bpl @w
        stz GFMT
        lda #1
        sta GAUTO
        rts

;=====================================================================
; CONSOLE
;=====================================================================
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

; A KEY: ARROWS (ESC [ A-D OR ^E ^X ^S ^D) BECOME K_UP..K_LF,
; DEL BECOMES BS
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
        lda #$1B            ; NO: A PLAIN ESC
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

; PRINT THE TEXT THAT FOLLOWS THE JSR (0-ENDED)
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

; PRINT THE 0-ENDED TEXT AT (MP)
PRMP:   ldy #0
@l:     lda (MP),y
        beq @r
        jsr OUTC
        iny
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

; CURSOR TO LINE X, COLUMN Y (BOTH 1-BASED)
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

; A IN DECIMAL, NO LEADING ZEROS
PRDEC:  ldx #0
        stx U4
@h:     cmp #100
        bcc @t
        sbc #100
        inx
        bra @h
@t:     pha
        txa
        beq @t1
        ora #'0'
        jsr OUTC
        inc U4
@t1:    pla
        ldx #0
@t2:    cmp #10
        bcc @u
        sbc #10
        inx
        bra @t2
@u:     pha
        txa
        bne @t3
        ldx U4
        beq @t4
@t3:    ora #'0'
        jsr OUTC
@t4:    pla
        ora #'0'
        jmp OUTC

; 16-BIT CNT IN DECIMAL
PRDEC16: lda CNT
        sta T16
        lda CNT+1
        sta T16+1
        jsr FINT16
        lda #0
        jsr FIXSTR
        ldx #0
@l:     cpx OLEN
        beq @r
        lda OBUF,x
        jsr OUTC
        inx
        bra @l
@r:     rts

; CELL NAME FOR COLUMN X, ROW A (0-BASED) e.g. B12
PRCELL: pha
        txa
        clc
        adc #'A'
        jsr OUTC
        pla
        inc a
        jmp PRDEC

;=====================================================================
; THE SCREEN
;=====================================================================
; WORK OUT WHICH COLUMNS FIT, FROM LCOL
LAYOUT: sec
        lda NLINES
        sbc #4
        sta VROWS
        ldx LCOL
        ldy #0
        lda #5              ; FIRST CELL COLUMN ON THE SCREEN
@l:     sta VX,y
        clc
        adc COLW,x
        cmp #82             ; MUST END BY COLUMN 80
        bcs @e
        iny
        inx
        cpx #NCOL
        bne @l
@e:     cpy #0
        bne @k
        iny                 ; ALWAYS AT LEAST ONE
@k:     sty VCN
        rts

; MAKE SURE THE CURSOR IS ON THE SCREEN (FULL=1 IF THE VIEW MOVES)
SETVIEW:
        jsr LAYOUT
        lda CROW
        cmp TROW
        bcs @1
        sta TROW
        inc FULL
@1:     clc
        lda TROW
        adc VROWS
        sta U1
        lda CROW
        cmp U1
        bcc @2
        sec
        sbc VROWS
        inc a
        sta TROW
        inc FULL
@2:     lda CCOL
        cmp LCOL
        bcs @3
        sta LCOL
        inc FULL
        jsr LAYOUT
@3:     clc
        lda LCOL
        adc VCN
        sta U1
        lda CCOL
        cmp U1
        bcc @r
        inc LCOL
        inc FULL
        jsr LAYOUT
        bra @3
@r:     rts

; PRINT A CHARACTER IN A ROW, HOLDING BACK SPACES
DCHAR:  cmp #' '
        bne @c
        ldx INREV
        bne @c
        inc PEND
        rts
@c:     pha
        jsr FLUSH
        pla
        jmp OUTC
FLUSH:  lda PEND
        beq @r
        lda #' '
        jsr OUTC
        dec PEND
        bra FLUSH
@r:     rts

; ---- REDRAW ---------------------------------------------------------
REDRAW: jsr SETVIEW
        lda FULL
        beq @dirty
        stz FULL
        jsr CLS
        jsr HEADER
        ldx #NROW-1
@a:     stz DIRTY,x
        dex
        bpl @a
        stz RDI              ; EVERY SCREEN ROW
@all:   clc
        lda TROW
        adc RDI
        cmp #NROW
        bcs @blank
        jsr DRAWROW
        bra @nx
@blank: clc                 ; PAST ROW 128
        lda RDI
        adc #2
        tax
        ldy #1
        jsr GOTO
        jsr CLEOL
@nx:    inc RDI
        lda RDI
        cmp VROWS
        bne @all
        bra @st
@dirty: stz RDI              ; ONLY THE CHANGED ROWS
@d:     clc
        lda TROW
        adc RDI
        cmp #NROW
        bcs @dn
        tax
        lda DIRTY,x
        beq @dn
        txa
        jsr DRAWROW
@dn:    inc RDI
        lda RDI
        cmp VROWS
        bne @d
        ldx #NROW-1
@c:     stz DIRTY,x
        dex
        bpl @c
@st:    jmp STATUS

; COLUMN LETTERS
HEADER: ldx #1
        ldy #1
        jsr GOTO
        jsr REVON
        jsr PRS
        .byte "    ",0
        stz U1
@l:     clc
        lda LCOL
        adc U1
        tax
        lda COLW,x
        sta U2
        dec a
        lsr a
        sta U4              ; SPACES BEFORE THE LETTER
        sec
        lda U2
        sbc U4
        sbc #1
        sta U2              ; AND AFTER
@b:     lda U4
        beq @t
        lda #' '
        jsr OUTC
        dec U4
        bra @b
@t:     txa
        clc
        adc #'A'
        jsr OUTC
@a:     lda U2
        beq @n
        lda #' '
        jsr OUTC
        dec U2
        bra @a
@n:     inc U1
        lda U1
        cmp VCN
        bne @l
        jsr REVOFF
        jmp CLEOL

; DRAW SHEET ROW A
DRAWROW:
        sta U2
        sec
        sbc TROW
        clc
        adc #2
        tax
        ldy #1
        jsr GOTO
        stz PEND
        stz SPILL
        stz INREV
        lda U2              ; ROW NUMBER, RIGHT-ALIGNED IN 3
        inc a
        cmp #100
        bcs @n3
        pha
        lda #' '
        jsr OUTC
        pla
        cmp #10
        bcs @n3
        pha
        lda #' '
        jsr OUTC
        pla
@n3:    jsr PRDEC
        lda #' '
        jsr OUTC
        stz U1              ; SCREEN COLUMN INDEX
@col:   clc
        lda LCOL
        adc U1
        sta U4              ; SHEET COLUMN
        jsr CELLTXT         ; -> DBUF, COLW[U4] CHARACTERS
        lda U4
        cmp CCOL
        bne @nc
        lda U2
        cmp CROW
        bne @nc
        jsr FLUSH           ; THE CURSOR CELL
        lda #1
        sta INREV
        jsr REVON
@nc:    ldx U4
        ldy #0
@ch:    phy
        lda DBUF,y
        jsr DCHAR
        ply
        iny
        tya
        ldx U4
        cmp COLW,x
        bne @ch
        lda INREV
        beq @nx
        stz INREV
        jsr REVOFF
@nx:    inc U1
        lda U1
        cmp VCN
        bne @col
        jmp CLEOL

; THE TEXT FOR CELL U4 IN ROW U2, PADDED TO ITS WIDTH, IN DBUF
CELLTXT:
        ldx U4
        lda COLW,x
        sta U3
        tay                 ; FILL WITH SPACES
        lda #' '
@f:     dey
        sta DBUF,y
        bne @f
        ldx U4
        lda U2
        jsr GETCELL
        bcc @have
        lda SPILL           ; EMPTY: SHOW SPILLED TEXT FROM THE LEFT
        beq @r
        ldy #0
@sp:    lda (SPP),y
        beq @send
        sta DBUF,y
        iny
        cpy U3
        bne @sp
        clc                 ; MORE STILL TO COME
        tya
        adc SPP
        sta SPP
        bcc @r
        inc SPP+1
@r:     rts
@send:  stz SPILL
        rts
@have:  stz SPILL
        ldy #R_TYPE
        lda (RP),y
        bmi @err
        bne @num
        jsr CFMT            ; TEXT
        and #$F0
        cmp #$20
        beq @rtxt
        clc                 ; LEFT: SHOW IT, LET THE REST SPILL
        lda RP
        adc #R_TEXT
        sta SPP
        lda RP+1
        adc #0
        sta SPP+1
        lda #1
        sta SPILL
        bra @sp0
@sp0:   ldy #0
        jmp @sp
@rtxt:  jsr TXTLEN          ; RIGHT-ALIGNED TEXT (NO SPILL)
        jmp RIGHTA
@err:   ldx #0
@e:     lda ERRTXT,x
        beq @r2
        cpx U3
        bcs @r2
        sta DBUF,x
        inx
        bra @e
@r2:    rts
@num:   clc                 ; A NUMBER
        lda RP
        adc #R_VAL
        sta PTR
        lda RP+1
        adc #0
        sta PTR+1
        jsr FLDA
        jsr CFMT
        pha
        and #$0F
        cmp #2
        beq @dol
        cmp #3
        beq @int
        lda U3              ; GENERAL: LEAVE ONE SPACE
        dec a
        jsr GENSTR
        bra @fit
@dol:   lda #2
        jsr FIXSTR
        bra @fit
@int:   lda #0
        jsr FIXSTR
@fit:   pla
        sta CFT
        lda OLEN            ; TOO WIDE?  FILL WITH >
        cmp U3
        bcc @ok
        ldy U3
        lda #'>'
@g:     dey
        sta DBUF,y
        bne @g
        rts
@ok:    lda CFT
        and #$F0
        cmp #$10
        beq @left
        lda OLEN            ; RIGHT, ONE SPACE IN FROM THE EDGE
        inc a
        sta CFT
        sec
        lda U3
        sbc CFT
        tay
        ldx #0
@rc:    cpx OLEN
        beq @rr
        lda OBUF,x
        sta DBUF,y
        inx
        iny
        bra @rc
@rr:    rts
@left:  ldx #0
@lc:    cpx OLEN
        beq @rr
        lda OBUF,x
        sta DBUF,x
        inx
        bra @lc
ERRTXT: .byte "ERROR",0

; COPY THE RECORD TEXT TO OBUF (FOR RIGHT-ALIGNED TEXT)
TXTLEN: ldy #R_TEXT
        ldx #0
@l:     lda (RP),y
        beq @e
        cpx #47
        bcs @e
        sta OBUF,x
        iny
        inx
        bra @l
@e:     stx OLEN
        rts
RIGHTA: ldx U3              ; OBUF RIGHT-ALIGNED INTO DBUF, ONE SPACE IN
        dex                 ; FROM THE EDGE LIKE NUMBERS (CUT TO FIT)
        bne @w
        inx
@w:     stx CFT
        lda OLEN
        cmp CFT
        bcc @1
        lda CFT
        sta OLEN
@1:     sec
        lda CFT
        sbc OLEN
        tay
        ldx #0
@c:     cpx OLEN
        beq @r
        lda OBUF,x
        sta DBUF,y
        inx
        iny
        bra @c
@r:     rts

; FORMAT OF RECORD RP IN COLUMN U4 -> A (BOTH NIBBLES FILLED IN)
CFMT:   ldy #R_FMT
        lda (RP),y
        ldx U4
        jmp EFFMT
; COMBINE CELL FORMAT A WITH COLUMN X AND GLOBAL FORMATS
EFFMT:  sta CFT
        and #$0F
        bne @n
        lda COLF,x
        and #$0F
        bne @n
        lda GFMT
        and #$0F
        bne @n
        lda #1
@n:     sta CFT2
        lda CFT
        and #$F0
        bne @a
        lda COLF,x
        and #$F0
        bne @a
        lda GFMT
        and #$F0
@a:     ora CFT2
        rts

        .bss
CFT:    .res 1
CFT2:   .res 1
        .code

; ---- THE THREE LINES AT THE BOTTOM ----------------------------------
STATUS: ldx NLINES          ; CELL AND WHAT IS IN IT
        dex
        dex
        ldy #1
        jsr GOTO
        jsr REVON
        ldx CCOL
        lda CROW
        jsr PRCELL
        jsr REVOFF
        lda #' '
        jsr OUTC
        ldx CCOL
        lda CROW
        jsr GETCELL
        bcs @e
        ldy #R_TYPE
        lda (RP),y
        and #$7F
        bne @f
        lda #'"'
        jsr OUTC
@f:     ldy #R_TEXT
@t:     lda (RP),y
        beq @e
        jsr OUTC
        iny
        cpy #R_TEXT+70
        bne @t
@e:     jsr CLEOL
        lda MSGON           ; A MESSAGE IS SHOWING: KEEP IT ON SCREEN
        beq @inf
        jsr SHOWMSG
        bra @ent
@inf:   jsr INFO
@ent:   jmp ENTRYLN

; WIDTH, FORMAT, FREE MEMORY
INFO:   ldx NLINES
        dex
        ldy #1
        jsr GOTO
        jsr PRS
        .byte "Width:",0
        ldx CCOL
        lda COLW,x
        jsr PRDEC
        jsr PRS
        .byte "  Format:",0
        ldx CCOL
        lda CROW
        jsr GETCELL
        lda #0
        bcs @nf
        ldy #R_FMT
        lda (RP),y
@nf:    ldx CCOL
        jsr EFFMT
        pha
        and #$0F
        tax
        lda FMTCH,x
        jsr OUTC
        pla
        lsr a
        lsr a
        lsr a
        lsr a
        tax
        beq @na
        lda ALCH,x
        jsr OUTC
@na:    jsr PRS
        .byte "  Free:",0
        jsr HFREEG
        jsr PRDEC16
        lda GAUTO
        bne @au
        jsr PRS
        .byte "  Manual (! recalcs)",0
@au:    jsr PRS
        .byte "   / for commands  ? for help",0
        jmp CLEOL
FMTCH:  .byte "?G$I"
ALCH:   .byte " LR"

ENTRYLN: ldx NLINES
        ldy #1
        jsr GOTO
        lda #'>'
        jsr OUTC
        jmp CLEOL

; A MESSAGE ON THE INFO LINE (TEXT FOLLOWS THE JSR)
MSG:    pla
        sta MP
        pla
        sta MP+1
        lda MP
        clc
        adc #1
        sta MSGP
        lda MP+1
        adc #0
        sta MSGP+1
@l:     inc MP              ; FIND THE END
        bne @1
        inc MP+1
@1:     lda (MP)
        bne @l
        lda MP+1
        pha
        lda MP
        pha
SHOWMSG: lda #1
        sta MSGON
        ldx NLINES
        dex
        ldy #1
        jsr GOTO
        jsr REVON
        lda MSGP
        sta MP
        lda MSGP+1
        sta MP+1
        jsr PRMP
        jsr REVOFF
        jmp CLEOL
        .bss
MSGP:   .res 2
        .code

; A PROMPT ON THE ENTRY LINE (TEXT FOLLOWS THE JSR); EDX = ITS LENGTH
PROMPT: pla
        sta MP
        pla
        sta MP+1
        ldx NLINES
        ldy #1
        jsr GOTO            ; (GOTO KEEPS MP)
        stz EDX
@l:     inc MP
        bne @1
        inc MP+1
@1:     lda (MP)
        beq @e
        jsr OUTC
        inc EDX
        bra @l
@e:     jsr CLEOL
        lda MP+1
        pha
        lda MP
        pha
        rts

;=====================================================================
; THE MAIN LOOP
;=====================================================================
MAIN:   jsr REDRAW
        ldx NLINES
        ldy #2
        jsr GOTO
        jsr GETKEY
        pha
        lda MSGON           ; ANY KEY CLEARS A MESSAGE
        beq @k
        stz MSGON
        jsr INFO
@k:     pla
        cmp #K_UP
        beq M_UP
        cmp #K_DN
        beq M_DN
        cmp #K_LF
        beq M_LF
        cmp #K_RT
        beq M_RT
        cmp #'/'
        bne @1
        jmp COMMAND
@1:     cmp #'='
        bne @2
        jmp GOTOCELL
@2:     cmp #'!'
        bne @3
        jsr RECALC
        lda #1
        sta FULL
        bra MAIN
@3:     cmp #'?'
        bne @4
        jmp HELP
@4:     cmp #' '
        bcc MAIN            ; OTHER CONTROL KEYS
        cmp #$80
        bcs MAIN
        sta EBUF            ; START TYPING AN ENTRY
        lda #1
        sta ELEN
        jmp ENTRY

M_UP:   lda CROW
        beq MAIN
        jsr MARKC
        dec CROW
        bra MOVED
M_DN:   lda CROW
        cmp #NROW-1
        beq MAIN
        jsr MARKC
        inc CROW
        bra MOVED
M_LF:   lda CCOL
        beq MAIN
        jsr MARKC
        dec CCOL
        bra MOVED
M_RT:   lda CCOL
        cmp #NCOL-1
        bne :+
        jmp MAIN
:
        jsr MARKC
        inc CCOL
MOVED:  jsr MARKC
        jmp MAIN
MOVEBY: cmp #K_UP           ; MOVE AFTER AN ENTRY ENDED WITH AN ARROW
        beq M_UP
        cmp #K_DN
        beq M_DN
        cmp #K_LF
        beq M_LF
        cmp #K_RT
        beq M_RT
        jmp MAIN
MARKC:  ldx CROW            ; THE CURSOR ROW NEEDS DRAWING
        lda #1
        sta DIRTY,x
        rts

;=====================================================================
; LINE EDITING ON THE BOTTOM LINE.  EBUF/ELEN HOLD THE TEXT.
; RETURN OR AN ARROW: C=0 (LASTK = THE KEY).  ESC: C=1.
;=====================================================================
EDIT:   jsr EDSHOW
@k:     jsr GETKEY
        sta LASTK
        cmp #$0D
        beq @ok
        cmp #$80
        bcs @ok
        cmp #$1B
        beq @esc
        cmp #$03
        beq @esc
        cmp #$08
        beq @bs
        cmp #$15            ; ^U: CLEAR THE LINE
        beq @clr
        cmp #' '
        bcc @k
        ldx ELEN
        cpx #70
        bcs @k
        sta EBUF,x
        inc ELEN
        jsr OUTC
        bra @k
@bs:    lda ELEN
        beq @k
        dec ELEN
        lda #8
        jsr OUTC
        lda #' '
        jsr OUTC
        lda #8
        jsr OUTC
        bra @k
@clr:   stz ELEN
        jsr EDSHOW
        bra @k
@ok:    ldx ELEN
        stz EBUF,x
        clc
        rts
@esc:   ldx ELEN
        stz EBUF,x
        sec
        rts
EDSHOW: ldx NLINES          ; REPRINT THE TEXT AFTER THE PROMPT
        lda EDX
        inc a
        tay
        jsr GOTO
        ldx #0
@l:     cpx ELEN
        beq @e
        lda EBUF,x
        phx
        jsr OUTC
        plx
        inx
        bra @l
@e:     jmp CLEOL

;=====================================================================
; TYPING INTO A CELL
;=====================================================================
ENTRY:  jsr ENTRYLN
        lda #1
        sta EDX
        jsr EDIT
        bcc @go
        jmp MAIN
@go:    lda ELEN
        bne @st
        jmp MAIN
@st:    lda CCOL
        sta SCOL
        lda CROW
        sta SROW
        jsr STOREENTRY
        bcs ENTRY           ; BAD FORMULA: EDIT IT AGAIN
        jsr AFTERCHG
        lda LASTK
        jmp MOVEBY

; AFTER A CHANGE: RECALCULATE (IF AUTO) AND MARK THE CURSOR ROW
AFTERCHG:
        lda GAUTO
        beq @m
        jsr RECALC
@m:     ldx SROW
        lda #1
        sta DIRTY,x
        rts

; STORE EBUF IN CELL SCOL,SROW.  C=1 IF IT WAS NOT STORED.
STOREENTRY:
        stz SFMT            ; KEEP THE CELL'S OLD FORMAT
        ldx SCOL
        lda SROW
        jsr GETCELL
        bcs @nf
        ldy #R_FMT
        lda (RP),y
        sta SFMT
@nf:    lda EBUF
        cmp #'"'
        beq @text
        lda #<EBUF          ; TRY IT AS A FORMULA
        sta TP
        lda #>EBUF
        sta TP+1
        jsr EVALUATE
        bcc @good
        lda PERR
        beq @merr           ; MATHS ERROR: STORE IT, SHOWING ERROR
        lda EBUF            ; NOT A FORMULA: A WORD IS TEXT
        jsr UPPER
        cmp #'A'
        bcc @bad
        cmp #'Z'+1
        bcs @bad
        jsr FZERO
        stz STYPE
        bra @put
@bad:   jsr MSG
        .byte "ERROR IN FORMULA - CORRECT IT OR ESC",0
        sec
        rts
@merr:  jsr FZERO
        lda #$81
        sta STYPE
        bra @put
@good:  lda #1
        sta STYPE
        bra @put
@text:  ldx #0              ; DROP THE QUOTE
@q:     lda EBUF+1,x
        sta EBUF,x
        beq @qz
        inx
        bra @q
@qz:    jsr FZERO
        stz STYPE
@put:   jsr PUTCELL
        bcc @r
        jsr MSG
        .byte "MEMORY FULL",0
        sec
@r:     rts

;=====================================================================
; RECALCULATE EVERY FORMULA, ROW BY ROW.  CHANGED ROWS GET DIRTY.
;=====================================================================
RECALC: stz U1              ; ROW
        stz U2              ; COLUMN
        lda #<TABLE         ; WALK THE TABLE IN ORDER
        sta RCP
        lda #>TABLE
        sta RCP+1
@cell:  ldy #0
        lda (RCP),y
        sta CRP
        iny
        lda (RCP),y
        sta CRP+1
        ora CRP
        beq @next
        ldy #R_TYPE
        lda (CRP),y
        and #$7F
        beq @next           ; TEXT
        clc
        lda CRP
        adc #R_TEXT
        sta TP
        lda CRP+1
        adc #0
        sta TP+1
        jsr EVALUATE
        lda #1              ; NEW TYPE
        bcc @ok
        jsr FZERO
        lda #$81
@ok:    ldy #R_TYPE
        cmp (CRP),y
        beq @same
        sta (CRP),y
        jsr @mark
@same:  ldy #R_VAL          ; NEW VALUE?
        ldx #0
@v:     lda FA,x
        cmp (CRP),y
        beq @vs
        sta (CRP),y
        jsr @mark
@vs:    iny
        inx
        cpx #8
        bne @v
@next:  clc
        lda RCP
        adc #2
        sta RCP
        bcc @n1
        inc RCP+1
@n1:    inc U2
        lda U2
        cmp #NCOL
        bne @cell
        stz U2
        inc U1
        lda U1
        cmp #NROW
        bne @cell
        rts
@mark:  phx
        ldx U1
        lda #1
        sta DIRTY,x
        plx
        rts

;=====================================================================
; = GO TO A CELL
;=====================================================================
GOTOCELL:
        jsr PROMPT
        .byte "Go to: ",0
        stz ELEN
        jsr EDIT
        bcs @x
        jsr PARSERANGE
        bcs @bad
        jsr MARKC
        lda SC1
        sta CCOL
        lda SR1
        sta CROW
        jsr MARKC
@x:     jmp MAIN
@bad:   jsr MSG
        .byte "NOT A CELL",0
        jmp MAIN

; EBUF -> RANGE SC1,SR1 : SC2,SR2 (A SINGLE CELL GIVES BOTH THE SAME,
; NOTHING GIVES THE CURSOR CELL).  C=1 IF IT IS NOT A RANGE.
PARSERANGE:
        lda #<EBUF
        sta TP
        lda #>EBUF
        sta TP+1
        stz TI
        jsr PEEK
        bne @r
        lda CCOL
        sta SC1
        sta SC2
        lda CROW
        sta SR1
        sta SR2
        clc
        rts
@r:     jsr CELLREF
        bcs @no
        lda RCOL
        sta SC1
        sta SC2
        lda RROW
        sta SR1
        sta SR2
        jsr PEEK
        beq @ok
        cmp #':'
        bne @no
        jsr NEXT
        jsr CELLREF
        bcs @no
        jsr PEEK
        bne @no
        lda RCOL            ; IN ORDER
        cmp SC1
        bcs @c
        ldx SC1
        stx SC2
        sta SC1
        bra @rr
@c:     sta SC2
@rr:    lda RROW
        cmp SR1
        bcs @d
        ldx SR1
        stx SR2
        sta SR1
        bra @ok
@d:     sta SR2
@ok:    clc
        rts
@no:    sec
        rts

;=====================================================================
; HELP
;=====================================================================
HELP:   jsr CLS
        lda #<HELPTXT
        sta MP
        lda #>HELPTXT
        sta MP+1
@l:     lda (MP)
        beq @e
        cmp #$0A
        bne @c
        lda #$0D
        jsr OUTC
        lda #$0A
@c:     jsr OUTC
        inc MP
        bne @l
        inc MP+1
        bra @l
@e:     jsr GETKEY
        lda #1
        sta FULL
        jmp MAIN

HELPTXT:
        .byte "CALC65  -  SUPERCALC-STYLE SPREADSHEET",$0A,$0A
        .byte "MOVE      arrow keys (or ^E ^X ^S ^D)    = cell   go to a cell",$0A
        .byte "ENTER     type a number, formula or text, then RETURN or an arrow",$0A
        .byte "          text starts with ",$22," (a plain word is text too)",$0A
        .byte "          BS deletes, ^U clears the line, ESC cancels",$0A
        .byte "FORMULAS  + - * / ^  ( )   = < > <= >= <> give 1 or 0",$0A
        .byte "          A1  $A$1 (fixed when copied)  A1:C9 ranges",$0A
        .byte "          SUM AVERAGE MIN MAX COUNT (lists and ranges)",$0A
        .byte "          ABS(x) INT(x) IF(test,then,else)",$0A
        .byte "!         recalculate",$0A,$0A
        .byte "/B Blank a range        /C Copy        /R Replicate",$0A
        .byte "/D Delete row/column    /I Insert row/column",$0A
        .byte "/E Edit the cell        /F Format (G $ I L R, width)",$0A
        .byte "/G Global (lines, auto/manual recalc)",$0A
        .byte "/S Save   /L Load   /N Names (directory)   /Z Zap   /Q Quit",$0A
        .byte "          a name can start with its drive:  B:BUDGET",$0A,$0A
        .byte "Press any key",0

        .include "CMDS.S"
