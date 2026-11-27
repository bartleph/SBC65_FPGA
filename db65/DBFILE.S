;=====================================================================
; DBFILE.S - DATABASE FILES FOR DB65
;
; A DATABASE IS AN ORDINARY DOS FILE (MADE BY MS, SO DI LISTS IT AND
; DE DELETES IT).  EACH OF ITS TRACKS HOLDS ONE 8-PAGE SECTOR (2K),
; READ AND WRITTEN WITH THE DOS CA AND SA COMMANDS.
;
; TRACK 0 OF THE FILE: BYTES 0-511 THE HEADER, THEN RECORDS.
;   +0  "DB65"   +4 RECORD COUNT   +6 RECORD LENGTH   +8 FIELD COUNT
;   +16 FIELDS, 16 BYTES EACH: NAME (11, 0-PADDED), TYPE (C N D L),
;       WIDTH, DECIMALS, OFFSET IN THE RECORD (2)
; A RECORD IS A DELETE FLAG ("*" OR SPACE) AND THEN THE FIELDS AS TEXT.
; RECORDS NEVER CROSS A TRACK.
;
; TWO "CONTEXTS" (X = 0 OR 1) EACH HAVE A 2K TRACK BUFFER, SO PACK AND
; SORT CAN READ ONE FILE (OR PLACE) WHILE WRITING ANOTHER.
;=====================================================================

TRKBUF0 = $9000
TRKBUF1 = $9800
HDR     = $A000
RECBUF  = $A200
DIRB    = $A600             ; DIRECTORY SECTORS, $A600-$A7FF
RECBUF2 = $A800             ; FORM TEXT / PACK, $A800-$ABFF
SBUF    = $AC00             ; STRING WORK AREA, $AC00-$AFFF
SBUFEND = $B000
SORTMEM = $A800             ; SORT (OVER THE TWO ABOVE), $A800-$BFFF
SORTEND = $C000

NREC    = HDR+4
RECLEN  = HDR+6
NFLD    = HDR+8
FLDS    = HDR+16
F_NAME  = 0
F_TYPE  = 11
F_WID   = 12
F_DEC   = 13
F_OFS   = 14
MAXFLD  = 20


        .bss
CXSTART: .res 2             ; FIRST TRACK (BCD)
CXNT:   .res 2              ; TRACKS IN THE FILE
CXCUR:  .res 2              ; TRACK IN THE BUFFER ($FF = NONE)
CXDIRTY: .res 2
CXX:    .res 1
HDIRTY: .res 1              ; HEADER (RECORD COUNT) NEEDS WRITING
OPENF:  .res 1              ; A FILE IS IN USE
R0:     .res 2              ; RECORDS IN TRACK 0
RPT:    .res 2              ; RECORDS IN EACH OTHER TRACK
MAXREC: .res 2
RN:     .res 2              ; RECORD (0-BASED) TO LOCATE
TIDX:   .res 1
TOFS:   .res 2
FTRK0:  .res 1
FTRKN:  .res 1
DBNAME: .res 16             ; NAME OF THE FILE IN USE
M1:     .res 2              ; MULTIPLY / DIVIDE
M2:     .res 2
M3:     .res 2
M4:     .res 2
        .code

CXBUFH: .byte >TRKBUF0, >TRKBUF1

; ---- 16-BIT ARITHMETIC ----------------------------------------------
; M3 = M1 * M2 (LOW 16 BITS)
MUL16:  stz M3
        stz M3+1
        ldx #16
@l:     asl M3
        rol M3+1
        asl M1
        rol M1+1
        bcc @n
        clc
        lda M3
        adc M2
        sta M3
        lda M3+1
        adc M2+1
        sta M3+1
@n:     dex
        bne @l
        rts
; M1 = M1 / M2, M4 = REMAINDER
DIV16:  stz M4
        stz M4+1
        ldx #16
@l:     asl M1
        rol M1+1
        rol M4
        rol M4+1
        sec
        lda M4
        sbc M2
        tay
        lda M4+1
        sbc M2+1
        bcc @n
        sta M4+1
        sty M4
        inc M1
@n:     dex
        bne @l
        rts

; ---- TRACKS ---------------------------------------------------------
; A = BCD TRACK NUMBER OF TRACK INDEX A IN CONTEXT X
TRKBCD: tay
        lda CXSTART,x
        sed
@l:     cpy #0
        beq @r
        clc
        adc #1
        dey
        bra @l
@r:     cld
        rts

; MAKE CONTEXT X HOLD TRACK INDEX A
CXLOAD: cmp CXCUR,x
        bne @1
        rts
@1:     cmp CXNT,x
        bcc @2
        lda #<M_PAST
        ldy #>M_PAST
        jmp ERRMSG
@2:     pha
        jsr CXFLUSH
        pla
        stx CXX
        pha
        lda #<CACMD
        sta MP
        lda #>CACMD
        sta MP+1
        jsr CMDSTART
        ldx CXX
        lda CXBUFH,x        ; "CA hh00=tt,1"
        jsr CMDHEX
        lda #0
        jsr CMDHEX
        lda #'='
        jsr CMDCH
        pla
        pha
        ldx CXX
        jsr TRKBCD
        jsr CMDHEX
        lda #<SEC1
        sta MP
        lda #>SEC1
        sta MP+1
        jsr CMDSTR
        jsr DOSCALL
        ldx CXX
        pla
        sta CXCUR,x
        rts
CACMD:  .byte "CA ",0
SEC1:   .byte ",1",13,0
M_PAST: .byte "PAST THE END OF THE FILE",0

; WRITE CONTEXT X'S TRACK BACK IF IT HAS CHANGED
CXFLUSH: lda CXDIRTY,x
        bne @1
        rts
@1:     stx CXX
        lda #<SACMD         ; "SA tt,1=hh00/8"
        sta MP
        lda #>SACMD
        sta MP+1
        jsr CMDSTART
        ldx CXX
        lda CXCUR,x
        jsr TRKBCD
        jsr CMDHEX
        lda #<SAMID
        sta MP
        lda #>SAMID
        sta MP+1
        jsr CMDSTR
        ldx CXX
        lda CXBUFH,x
        jsr CMDHEX
        lda #0
        jsr CMDHEX
        lda #<SAEND
        sta MP
        lda #>SAEND
        sta MP+1
        jsr CMDSTR
        jsr DOSCALL
        ldx CXX
        stz CXDIRTY,x
        rts
SACMD:  .byte "SA ",0
SAMID:  .byte ",1=",0
SAEND:  .byte "/8",13,0

; EVERYTHING ON DISK: BOTH BUFFERS, AND THE HEADER IF IT CHANGED
FLUSHALL:
        lda OPENF
        beq @r
        ldx #1
        jsr CXFLUSH
        ldx #0
        jsr CXFLUSH
        lda HDIRTY
        beq @r
        ldx #0
        lda #0
        jsr CXLOAD
        ldy #0              ; HEADER INTO TRACK 0
@c:     lda HDR,y
        sta TRKBUF0,y
        lda HDR+256,y
        sta TRKBUF0+256,y
        iny
        bne @c
        ldx #0
        lda #1
        sta CXDIRTY
        jsr CXFLUSH
        stz HDIRTY
@r:     rts

; ---- RECORDS --------------------------------------------------------
; RN (0-BASED) -> TIDX, TOFS
RLOC:   lda RN+1
        cmp R0+1
        bne @c
        lda RN
        cmp R0
@c:     bcs @later
        lda RN              ; TRACK 0: 512 + RN*LEN
        sta M1
        lda RN+1
        sta M1+1
        lda RECLEN
        sta M2
        lda RECLEN+1
        sta M2+1
        jsr MUL16
        clc
        lda M3
        sta TOFS
        lda M3+1
        adc #2
        sta TOFS+1
        stz TIDX
        rts
@later: sec                 ; (RN-R0)/RPT -> TRACK-1, REMAINDER*LEN
        lda RN
        sbc R0
        sta M1
        lda RN+1
        sbc R0+1
        sta M1+1
        lda RPT
        sta M2
        lda RPT+1
        sta M2+1
        jsr DIV16
        lda M1
        inc a
        sta TIDX
        lda M4
        sta M1
        lda M4+1
        sta M1+1
        lda RECLEN
        sta M2
        lda RECLEN+1
        sta M2+1
        jsr MUL16
        lda M3
        sta TOFS
        lda M3+1
        sta TOFS+1
        rts

; GP = ADDRESS OF RECORD RN IN CONTEXT X (LOADING ITS TRACK)
RECADDR: phx
        jsr RLOC
        plx
        lda TIDX
        jsr CXLOAD
        clc
        lda TOFS
        sta GP
        lda TOFS+1
        adc CXBUFH,x
        sta GP+1
        rts

; RECBUF = RECORD N (1-BASED, IN A/Y = LO/HI) OF THE FILE IN USE
GETREC: jsr SETRN
        ldx #0
        jsr RECADDR
        lda #<RECBUF
        sta GP2
        lda #>RECBUF
        sta GP2+1
        jmp CPYREC          ; (GP) -> (GP2)
; RECORD N (A/Y) = RECBUF
PUTREC: jsr SETRN
        ldx #0
        jsr RECADDR
        lda #1
        sta CXDIRTY
        lda GP              ; RECBUF -> (GP)
        sta GP2
        lda GP+1
        sta GP2+1
        lda #<RECBUF
        sta GP
        lda #>RECBUF
        sta GP+1
        jmp CPYREC
SETRN:  sec                 ; RN = N - 1
        sbc #1
        sta RN
        tya
        sbc #0
        sta RN+1
        rts

; COPY RECLEN BYTES (GP) -> (GP2)
CPYREC: lda RECLEN
        sta M4
        lda RECLEN+1
        sta M4+1
        ldy #0
@l:     lda M4
        ora M4+1
        beq @r
        lda (GP),y
        sta (GP2),y
        iny
        bne @d
        inc GP+1
        inc GP2+1
@d:     lda M4
        bne @d1
        dec M4+1
@d1:    dec M4
        bra @l
@r:     rts

; RECBUF = A BLANK RECORD
BLANKREC:
        ldx #0
        ldy #0
        lda RECLEN
        sta M4
        lda RECLEN+1
        sta M4+1
        lda #<RECBUF
        sta GP
        lda #>RECBUF
        sta GP+1
@l:     lda M4
        ora M4+1
        beq @r
        lda #' '
        sta (GP),y
        iny
        bne @d
        inc GP+1
@d:     lda M4
        bne @d1
        dec M4+1
@d1:    dec M4
        bra @l
@r:     rts

; ---- OPENING ----------------------------------------------------------
; R0, RPT, MAXREC FROM RECLEN AND THE TRACK COUNT
SETGEOM:
        lda #<1536
        sta M1
        lda #>1536
        sta M1+1
        lda RECLEN
        sta M2
        lda RECLEN+1
        sta M2+1
        jsr DIV16
        lda M1
        sta R0
        lda M1+1
        sta R0+1
        stz M1
        lda #>2048
        sta M1+1
        jsr DIV16
        lda M1
        sta RPT
        sta M2
        lda M1+1
        sta RPT+1
        sta M2+1
        lda CXNT            ; MAXREC = R0 + (TRACKS-1)*RPT
        dec a
        sta M1
        stz M1+1
        jsr MUL16
        clc
        lda M3
        adc R0
        sta MAXREC
        lda M3+1
        adc R0+1
        sta MAXREC+1
        rts

; USE THE FILE NAMED IN FNAME.  C=1 (MESSAGE SHOWN) IF IT CANNOT
OPENFILE:
        jsr FINDFILE        ; (THE FILE IN USE STAYS OPEN IF NOT FOUND)
        bcc @f
        lda #<M_NOFILE
        ldy #>M_NOFILE
        jmp ERRMSG
@f:     jsr CLOSEFILE
        lda FTRK0
        sta CXSTART
        lda FTRKN
        sta CXNT
        lda #$FF
        sta CXCUR
        sta CXCUR+1
        stz CXDIRTY
        stz CXDIRTY+1
        stz HDIRTY
        ldx #0
        lda #0
        jsr CXLOAD
        ldx #3
@m:     lda TRKBUF0,x
        cmp MAGIC,x
        bne @not
        dex
        bpl @m
        ldy #0
@c:     lda TRKBUF0,y
        sta HDR,y
        lda TRKBUF0+256,y
        sta HDR+256,y
        iny
        bne @c
        jsr SETGEOM
        lda #1
        sta OPENF
        ldx #15
@n:     lda FNAME,x
        sta DBNAME,x
        dex
        bpl @n
        jsr GOTOP
        clc
        rts
@not:   lda #$FF
        sta CXCUR
        lda #<M_NOTDB
        ldy #>M_NOTDB
        jmp ERRMSG
MAGIC:  .byte "DB65"
M_NOFILE: .byte "FILE NOT FOUND",0
M_NOTDB: .byte "NOT A DB65 DATABASE",0

CLOSEFILE:
        jsr FLUSHALL
        stz OPENF
        stz RECNO
        stz RECNO+1
        lda #$FF
        sta CXCUR
        sta CXCUR+1
        rts

; GO TO THE FIRST RECORD (RECNO = 0 IF THERE ARE NONE)
GOTOP:  lda NREC
        ora NREC+1
        beq @e
        lda #1
        ldy #0
        jmp SETREC
@e:     stz RECNO
        stz RECNO+1
        stz EOFF
        rts
; RECNO = A/Y AND READ IT
SETREC: sta RECNO
        sty RECNO+1
        stz EOFF
        jmp GETREC

; ---- FIELDS ---------------------------------------------------------
; FP = FIELD X (0-BASED)
FLDPTR: txa
        asl a
        asl a
        asl a
        asl a
        clc
        adc #<FLDS
        sta FP
        lda #>FLDS
        adc #0
        sta FP+1
        rts

; FIND THE FIELD NAMED IN NAMEB.  C=0: X = IT, FP SET.  C=1: NONE
FINDFLD:
        ldx #0
@f:     cpx NFLD
        bcs @no
        jsr FLDPTR
        ldy #0
@c:     lda (FP),y
        cmp NAMEB,y
        bne @n
        cmp #0
        beq @y
        iny
        cpy #11
        bne @c
@y:     clc
        rts
@n:     inx
        bra @f
@no:    sec
        rts

; GP = ADDRESS OF FIELD FP IN RECBUF, A = ITS WIDTH
FLDADDR:
        ldy #F_OFS
        clc
        lda (FP),y
        adc #<RECBUF
        sta GP
        iny
        lda (FP),y
        adc #>RECBUF
        sta GP+1
        ldy #F_WID
        lda (FP),y
        rts
