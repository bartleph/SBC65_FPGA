;=====================================================================
; CELLS.S - CELL STORAGE FOR CALC65
;
; TABLE: ONE 2-BYTE POINTER PER CELL, ROW BY ROW (INDEX = ROW*26+COL),
;        0 = EMPTY.  THE RECORDS LIVE IN THE HEAP AFTER THE TABLE:
;  +0 LENGTH OF THE RECORD
;  +1 +2 ITS TABLE INDEX (SO THE HEAP CAN BE PACKED)
;  +3 TYPE: 0 = TEXT, 1 = NUMBER/FORMULA, +$80 = ERROR
;  +4 FORMAT: LOW NIBBLE 0 DEFAULT 1 G 2 $ 3 I,  HIGH NIBBLE 0 DEFAULT
;     1 LEFT 2 RIGHT
;  +5..+12 VALUE (8-BYTE BCD)
;  +13 THE TEXT AS TYPED, ENDING WITH 0
;=====================================================================

NCOL    = 26
NROW    = 128
NCELL   = NCOL*NROW         ; 3328
HDR     = $7700             ; SAVED WITH THE SHEET (PAGE-ALIGNED SO
                            ; ML, WHICH LOADS WHOLE PAGES, STOPS AT THE
                            ; HEAP'S LAST PAGE, NEVER IN THE I/O AT $C000)
TABLE   = $7800
HEAPBEG = TABLE + NCELL*2   ; $9200
HEAPEND = $C000

R_LEN   = 0
R_IDX   = 1
R_TYPE  = 3
R_FMT   = 4
R_VAL   = 5
R_TEXT  = 13

; THE SAVED HEADER
H_MAGIC = HDR               ; "C65S"
H_TOP   = HDR+4             ; END OF THE HEAP
COLW    = HDR+6             ; 26 COLUMN WIDTHS
COLF    = HDR+32            ; 26 COLUMN FORMATS
GFMT    = HDR+58            ; GLOBAL FORMAT
GAUTO   = HDR+59            ; 1 = RECALCULATE AFTER EVERY ENTRY
HDREND  = HDR+64

        .zeropage
RP:     .res 2              ; A RECORD
SLOT:   .res 2              ; A TABLE ENTRY
IDX:    .res 2
SRC:    .res 2
DST:    .res 2
CNT:    .res 2
GP:     .res 2

        .code

; ---- IDX = A(ROW)*26 + X(COL);  SLOT = TABLE + IDX*2 ----------------
CIDX:   stx BT1
        sta IDX
        stz IDX+1
        asl IDX             ; *2
        rol IDX+1
        lda IDX
        ldy IDX+1
        asl IDX             ; *8
        rol IDX+1
        asl IDX
        rol IDX+1
        clc
        adc IDX             ; *10
        sta CNT
        tya
        adc IDX+1
        sta CNT+1
        asl IDX             ; *16
        rol IDX+1
        clc
        lda IDX
        adc CNT
        sta IDX
        lda IDX+1
        adc CNT+1
        sta IDX+1           ; *26
        clc
        lda IDX
        adc BT1
        sta IDX
        bcc IDXSL
        inc IDX+1
IDXSL:  lda IDX             ; SLOT FROM IDX
        asl a
        sta SLOT
        lda IDX+1
        rol a
        adc #>TABLE
        sta SLOT+1
        rts

; ---- RP = THE CELL AT ROW A, COLUMN X.  Z=1 (AND C=1) IF EMPTY ------
GETCELL: jsr CIDX
GETSL:  ldy #0
        lda (SLOT),y
        sta RP
        iny
        lda (SLOT),y
        sta RP+1
        ora RP
        bne @f
        sec
        rts
@f:     clc
        rts

; ---- EMPTY THE WHOLE SHEET ------------------------------------------
CLEARALL:
        lda #<TABLE
        sta DST
        lda #>TABLE
        sta DST+1
        ldx #>(NCELL*2)     ; WHOLE PAGES
        ldy #0
        tya
@p:     sta (DST),y
        iny
        bne @p
        inc DST+1
        dex
        bne @p
        ldy #<(NCELL*2)     ; THE REST
        beq @h
@r:     dey
        sta (DST),y
        cpy #0
        bne @r
@h:     lda #<HEAPBEG
        sta H_TOP
        lda #>HEAPBEG
        sta H_TOP+1
        stz GARB
        stz GARB+1
        rts

; ---- FREE HEAP BYTES -> CNT -----------------------------------------
HFREE:  sec
        lda #<HEAPEND
        sbc H_TOP
        sta CNT
        lda #>HEAPEND
        sbc H_TOP+1
        sta CNT+1
        rts
; FREE INCLUDING GARBAGE (WHAT A PACK WOULD GIVE) -> CNT
HFREEG: jsr HFREE
        clc
        lda CNT
        adc GARB
        sta CNT
        lda CNT+1
        adc GARB+1
        sta CNT+1
        rts

; ---- ALLOCATE A BYTES -> RP.  C=1 IF THERE IS NO ROOM --------------
ALLOC:  sta BT2
        jsr @try
        bcc @r
        jsr COMPACT
@try:   jsr HFREE
        lda CNT+1
        bne @ok
        lda CNT
        cmp BT2
        bcs @ok
        sec                 ; C=1: NO ROOM
        rts
@ok:    lda H_TOP
        sta RP
        clc
        adc BT2
        sta H_TOP
        lda H_TOP+1
        sta RP+1
        adc #0
        sta H_TOP+1
        clc
@r:     rts

; ---- PACK THE HEAP: SLIDE EVERY LIVE RECORD DOWN --------------------
COMPACT:
        lda #<HEAPBEG
        sta SRC
        sta DST
        lda #>HEAPBEG
        sta SRC+1
        sta DST+1
@rec:   lda SRC             ; SRC < H_TOP?
        cmp H_TOP
        lda SRC+1
        sbc H_TOP+1
        bcs @end
        ldy #R_IDX
        lda (SRC),y
        sta IDX
        iny
        lda (SRC),y
        sta IDX+1
        jsr IDXSL
        ldy #0
        lda (SLOT),y        ; IS THE TABLE STILL POINTING HERE?
        cmp SRC
        bne @next
        iny
        lda (SLOT),y
        cmp SRC+1
        bne @next
        lda DST             ; YES: TABLE -> NEW PLACE
        ldy #0
        sta (SLOT),y
        lda DST+1
        iny
        sta (SLOT),y
        lda (SRC)           ; LENGTH
        tax
        ldy #0
@cp:    lda (SRC),y
        sta (DST),y
        iny
        dex
        bne @cp
        clc                 ; DST += LENGTH (Y)
        tya
        adc DST
        sta DST
        bcc @next
        inc DST+1
@next:  clc
        lda (SRC)
        adc SRC
        sta SRC
        bcc @rec
        inc SRC+1
        bra @rec
@end:   lda DST
        sta H_TOP
        lda DST+1
        sta H_TOP+1
        stz GARB
        stz GARB+1
        rts

; THE RECORD IN (SLOT), IF ANY, IS ABOUT TO BE DROPPED: COUNT ITS BYTES
ADDGARB: phy
        ldy #1
        lda (SLOT),y
        beq @n
        sta GP+1
        dey
        lda (SLOT),y
        sta GP
        clc
        lda (GP)
        adc GARB
        sta GARB
        bcc @n
        inc GARB+1
@n:     ply
        rts

; GARB = HEAP IN USE - LIVE RECORDS (AFTER THE TABLE WAS SHUFFLED)
CALCGARB:
        sec
        lda H_TOP
        sbc #<HEAPBEG
        sta GARB
        lda H_TOP+1
        sbc #>HEAPBEG
        sta GARB+1
        lda #<TABLE
        sta SLOT
        lda #>TABLE
        sta SLOT+1
@l:     ldy #1
        lda (SLOT),y
        beq @n
        sta GP+1
        dey
        lda (SLOT),y
        sta GP
        sec
        lda GARB
        sbc (GP)
        sta GARB
        bcs @n
        dec GARB+1
@n:     clc
        lda SLOT
        adc #2
        sta SLOT
        bcc @l
        inc SLOT+1
        lda SLOT+1
        cmp #>HEAPBEG
        bcc @l
        rts

; ---- STORE A CELL ---------------------------------------------------
; IN: CCOL/CROW-STYLE POSITION IN SCOL/SROW, TEXT IN EBUF (0-ENDED),
;     STYPE, SFMT, VALUE IN FA.   C=1 = NO ROOM
PUTCELL:
        ldy #0              ; LENGTH = 14 + TEXT
@ln:    lda EBUF,y
        beq @l1
        iny
        bne @ln
@l1:    tya
        clc
        adc #R_TEXT+1
        bcs @full
        sta BT3
        jsr ALLOC
        bcs @full
        lda BT3
        sta (RP)
        ldx SCOL
        lda SROW
        jsr CIDX            ; (ALLOC MAY HAVE MOVED THINGS: SLOT AGAIN)
        ldy #R_IDX
        lda IDX
        sta (RP),y
        iny
        lda IDX+1
        sta (RP),y
        iny
        lda STYPE
        sta (RP),y
        iny
        lda SFMT
        sta (RP),y
        ldx #0
        ldy #R_VAL
@v:     lda FA,x
        sta (RP),y
        iny
        inx
        cpx #8
        bne @v
        ldx #0
@t:     lda EBUF,x
        sta (RP),y
        beq @s
        iny
        inx
        bra @t
@s:     jsr ADDGARB         ; THE OLD RECORD (IF ANY) IS NOW GARBAGE
        ldy #0              ; TABLE ENTRY -> THE NEW RECORD
        lda RP
        sta (SLOT),y
        iny
        lda RP+1
        sta (SLOT),y
        clc
        rts
@full:  sec
        rts

; ---- EMPTY THE CELL AT ROW A, COLUMN X ------------------------------
DELCELL: jsr CIDX
        jsr ADDGARB
        lda #0
        tay
        sta (SLOT),y
        iny
        sta (SLOT),y
        rts

        .bss
SCOL:   .res 1
SROW:   .res 1
STYPE:  .res 1
SFMT:   .res 1
GARB:   .res 2              ; BYTES OF DEAD RECORDS IN THE HEAP
        .code
