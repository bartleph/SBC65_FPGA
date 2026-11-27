;=====================================================================
; DB65 - A dBASE II STYLE DATABASE FOR THE SBC65 (FPGA, 48K)
;        UNDER THE OS-65D V3.3 ROM DOS
;
; BUILD:  ca65 --cpu 65C02 DB.S -o DB.o
;         ld65 -C db.cfg DB.o -o DB.BIN
; LOAD AND RUN: HL (DB65.HEX), THEN GO 3B00.  SAVE THE PROGRAM WITH
;         MS 3B00 81FF DB65  AND AFTER THAT RUN IT WITH  MR DB65
;
; MEMORY: $3B00-$8FFF PROGRAM, $9000-$9FFF TWO TRACK BUFFERS,
;   $A000 FILE HEADER, $A200 RECORD, $A600 DIRECTORY, $A800 FORM /
;   TEXT WORK AREA, $A800-$BFFF SORT.  ZERO PAGE $30-$AF.
;=====================================================================
        .setcpu "65C02"

ACIAS   = $C080             ; FPGA CONSOLE ACIA
ACIAD   = $C081

DOCMD   = $E801             ; ROM DOS: RUN THE COMMAND LINE AT (INBUF)
SETERR  = $E7FA             ; DOS ERROR VECTOR = A (LO), Y (HI)
INBUF   = $E1
CMDPOS  = $2CE5
CMDLEN  = $2CED
CMDBUF  = $2E1E

ZPBASE  = $30
ZPSIZE  = $80
LBMAX   = 120

K_UP    = $80
K_DN    = $81
K_RT    = $82
K_LF    = $83

        .zeropage
MP:     .res 2              ; MESSAGES
GP:     .res 2              ; GENERAL POINTERS
GP2:    .res 2
FP:     .res 2              ; A FIELD DEFINITION
KP:     .res 2              ; SORT KEYS

        .code
        jmp START
NLDEF:  .byte 24            ; $3B03: SCREEN LINES (SET LINES CHANGES IT)

        .include "BCD.S"
        .include "DBIO.S"
        .include "DBFILE.S"
        .include "DBEXPR.S"

        .bss
ZPSAVE: .res ZPSIZE
SAVESP: .res 1
CMDSP:  .res 1
PBK:    .res 1
LCOUNT: .res 1
NLINES: .res 1
LBUF:   .res LBMAX+2
LLEN:   .res 1
OLDLINE: .res LBMAX+2
CPOS:   .res 1
FNAME:  .res 16
EMSG:   .res 2
EMSG2:  .res 2
RECNO:  .res 2              ; CURRENT RECORD (1-BASED, 0 = NONE)
EOFF:   .res 1
        .code

;=====================================================================
; START, QUIT, ERRORS
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
        sta NLINES
        stz PBK
        stz OPENF
        stz RECNO
        stz RECNO+1
        stz OLDLINE
        lda #$FF
        sta CXCUR
        sta CXCUR+1
        lda #>(NUMERR-1)    ; A NUMBER ERROR (BCD.S FERR) RETURNS HERE
        pha
        lda #<(NUMERR-1)
        pha
        tsx
        stx CMDSP
        stx ERRSP
        jsr CLS
        jsr PRS
        .byte "DB65  -  dBASE II STYLE DATABASE",13,10
        .byte "Type HELP for the commands.",13,10,0
        jmp LOOP

QUIT:   jsr FLUSHALL
        jsr CRLF
        ldx #ZPSIZE-1
@z:     lda ZPSAVE,x
        sta ZPBASE,x
        dex
        bpl @z
        ldx SAVESP
        txs
        rts

NUMERR: ldx CMDSP
        txs
        lda #<M_NUM
        sta EMSG
        lda #>M_NUM
        sta EMSG+1
        stz EMSG2+1
        bra SHOWERR
M_NUM:  .byte "NUMBER TOO BIG, OR DIVIDE BY 0",0

; A MESSAGE (A/Y) AND BACK TO THE DOT PROMPT
ERRMSG: sta EMSG
        sty EMSG+1
        stz EMSG2+1
ERRJMP2: ldx CMDSP
        txs
SHOWERR: cld
        jsr REVOFF
        lda #$0D
        jsr OUTC
        jsr CLEOL
        jsr PRS
        .byte "*** ",0
        lda EMSG
        sta MP
        lda EMSG+1
        sta MP+1
        jsr PRMP
        lda EMSG2+1
        beq @1
        sta MP+1
        lda EMSG2
        sta MP
        jsr PRMP
@1:     jsr CRLF
        jsr FLUSHALL
        bra LOOP

ABORT:  ldx CMDSP           ; ESC DURING A LISTING
        txs
        jsr CRLF
        jsr FLUSHALL
        ; (FALLS INTO LOOP)

;=====================================================================
; THE DOT PROMPT
;=====================================================================
LOOP:   ldx CMDSP
        txs
        stz LCOUNT
        lda #'.'
        jsr OUTC
        jsr SPACE
        jsr GETLINE
        bcs LOOP
        lda #<LBUF
        sta TP
        lda #>LBUF
        sta TP+1
        stz TI
        jsr PEEK
        beq LOOP
        cmp #'?'
        bne @1
        jsr NEXT
        jsr C_PRINT
        bra LOOP
@1:     cmp #'0'            ; A NUMBER ON ITS OWN = GOTO
        bcc @2
        cmp #'9'+1
        bcs @2
        jsr C_GOTO
        bra LOOP
@2:     jsr GETNAME
        bcc @3
        jmp BADCMD
@3:     ldx #0              ; FIND THE COMMAND
@f:     lda CMDTAB,x
        bne @4
        jmp BADCMD
@4:     stx BT3             ; ENTRY START
        ldy #0
@c:     lda NAMEB,y
        beq @end
        cmp CMDTAB,x
        bne @next
        inx
        iny
        bra @c
@end:   cpy #4              ; TYPED AT LEAST 4 LETTERS, OR THE WHOLE WORD
        bcs @hit
        lda CMDTAB,x
        beq @hit
@next:  ldx BT3             ; SKIP THIS ENTRY
@s:     lda CMDTAB,x
        inx
        cmp #0
        bne @s
        inx
        inx
        bra @f
@hit:   lda CMDTAB,x        ; TO THE END OF THE NAME
        beq @go
        inx
        bra @hit
@go:    lda #>(CMDRET-1)    ; THE HANDLER RETURNS TO CMDRET
        pha
        lda #<(CMDRET-1)
        pha
        lda CMDTAB+2,x
        pha
        lda CMDTAB+1,x
        pha
        rts                 ; (HANDLERS END WITH RTS -> CMDRET)

CMDRET: jmp LOOP

BADCMD: lda #<M_BAD
        ldy #>M_BAD
        jmp ERRMSG
M_BAD:  .byte "UNKNOWN COMMAND - TYPE HELP",0

; NAME, 0, HANDLER-1.  HANDLERS ARE ENTERED WITH CMDRET-1 ON THE
; STACK SO THEY CAN SIMPLY RTS.
CMDTAB: .byte "USE",0
        .word H_USE-1
        .byte "CREATE",0
        .word H_CREATE-1
        .byte "CLOSE",0
        .word H_CLOSE-1
        .byte "APPEND",0
        .word H_APPEND-1
        .byte "EDIT",0
        .word H_EDIT-1
        .byte "BROWSE",0
        .word H_BROWSE-1
        .byte "LIST",0
        .word H_LIST-1
        .byte "DISPLAY",0
        .word H_DISP-1
        .byte "REPORT",0
        .word H_REPORT-1
        .byte "GOTO",0
        .word H_GO-1
        .byte "GO",0
        .word H_GO-1
        .byte "SKIP",0
        .word H_SKIP-1
        .byte "LOCATE",0
        .word H_LOCATE-1
        .byte "CONTINUE",0
        .word H_CONT-1
        .byte "REPLACE",0
        .word H_REPL-1
        .byte "DELETE",0
        .word H_DELETE-1
        .byte "RECALL",0
        .word H_RECALL-1
        .byte "PACK",0
        .word H_PACK-1
        .byte "ZAP",0
        .word H_ZAP-1
        .byte "COUNT",0
        .word H_COUNT-1
        .byte "SUM",0
        .word H_SUM-1
        .byte "AVERAGE",0
        .word H_AVG-1
        .byte "SORT",0
        .word H_SORT-1
        .byte "DIR",0
        .word H_DIR-1
        .byte "SET",0
        .word H_SET-1
        .byte "HELP",0
        .word H_HELP-1
        .byte "QUIT",0
        .word H_QUIT-1
        .byte 0

        .include "DBCMD.S"
        .include "DBSCR.S"
