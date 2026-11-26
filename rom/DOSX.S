;*****************************************************************
;* DOSX - OS-65D V3.3 ROM EXTENSION AT $D000-$DFFF  (ca65 source) *
;*                                                               *
;* HL                 LOAD INTEL HEX OR MOS (;) FROM THE CONSOLE *
;* CO S D [TT[-TT]]   COPY TRACKS FROM DRIVE S TO DRIVE D        *
;* RN OLD NEW         RENAME A FILE                              *
;* DI                 DIRECTORY SORTED BY TRACK + FREE TRACKS    *
;*                    (DI TT STILL GIVES THE TRACK'S SECTOR MAP) *
;* TY NAME            TYPE A TEXT FILE                           *
;* VE [TT[-TT]]       VERIFY: READ EVERY SECTOR                  *
;* MD SSSS [EEEE]     DUMP MEMORY                                *
;* MF SSSS EEEE BB    FILL MEMORY                                *
;* MM SSSS EEEE DDDD  MOVE MEMORY (OVERLAP SAFE)                 *
;* DT [G|R|HH SS]     DISK TIMING: GOTEK / REAL DRIVES / CUSTOM   *
;*                                                               *
;* ROM PATCHES (DONE BY BUILD.PY):                               *
;*  $FD94: JMP $D000  (WAS LDA #$07 / JMP $E7C8 = UNKNOWN CMD)   *
;*  $EB93: DIX-1      (DI COMMAND TABLE ENTRY, WAS $F111)        *
;*  $E4D5: JMP DXHEAD (WAS LDX #$28 / JMP $E3F3 - 40 MS HEAD DELAY) *
;*  $E41B: JMP DXSTEP (WAS LDX #$08 / BNE $E3F3 - 8 MS STEP DELAY)  *
;*  D9 REMOVED FROM THE COMMAND TABLE                             *
;*  FORTH $AAF2: JMP DIRCHK (DIR! CHECKS DIRBUF BEFORE WRITING)   *
;*                                                               *
;* CO, TY AND VE USE $7000-$77FF AS A SECTOR BUFFER.             *
;* VARIABLES LIVE IN $3560-$35DF (UNUSED DOS RAM).               *
;*****************************************************************
        .setcpu "65C02"

; ---- ROM DOS ROUTINES ----
GETCH   = $EA45     ; NEXT COMMAND CHAR (UPPER CASE)
UCASE   = $F00F     ; FOLD A TO UPPER CASE
ERROR   = $E7C8     ; PRINT ERR #A, ABORT VIA ($2A4E)
SKIPAR  = $E821     ; SKIP COMMAND WORD + SPACES
SEEK    = $E435     ; SEEK TO TRACK A (BCD)
HLOAD   = $E4CD     ; LOAD HEAD
HUNLD   = $E4DA     ; UNLOAD HEAD
HOME    = $E3DC     ; STEP TO TRACK 0
SELECT  = $E743     ; SELECT DRIVE A (1-4)
INITTRK = $E4F6     ; FORMAT CURRENT TRACK
FINDHDR = $E641     ; FIND TRACK HEADER (+SECTOR DSECT-1)
NXTSEC  = $E715     ; SKIP NEXT SECTOR: C=1 FOUND ($FB,$FA)
RDRAW   = $E6E4     ; READ SECTOR DSECT TO (MEMLO) - NO PATCHING
WRSEC   = $E55A     ; WRITE SECTOR FROM (MEMLO)
LDDIR   = $F185     ; READ DIRECTORY TO $3300/$3400
GETNM   = $F3D3     ; REST OF LINE -> NAMBUF
FNDNM   = $F3F9     ; FIND NAMBUF IN DIRECTORY
MAPTRK  = $F41E     ; BUILD USED-TRACK MAP AT $3500
DIOLD   = $F112     ; ORIGINAL DI
PRINT   = $EAD6     ; PRINT INLINE STRING
GETKEY  = $E0C4     ; GET A KEY (ECHOED)
CRLF    = $EACD
OUTCH   = $E0C7     ; PRINT A (PRESERVES X,Y)
PRHEX   = $EAF5     ; PRINT A AS 2 HEX DIGITS

; ---- ROM DOS VARIABLES ----
INBUF   = $E1       ; COMMAND LINE POINTER
MEMLO   = $FE
MEMHI   = $FF
ENTPL   = $10       ; DIRECTORY ENTRY POINTER
ENTPH   = $11
P1      = $12       ; WORK POINTERS (PU TEMPS)
P2      = $14
SECCNT  = $F9       ; NXTSEC: SECTORS SEEN
SECPGS  = $FA       ; NXTSEC: PAGES
SECNO   = $FB       ; NXTSEC: SECTOR NUMBER
CMDPOS  = $2CE5
DRIVE   = $265C     ; CURRENT DRIVE 1-4
CURTRK  = $265D     ; CURRENT TRACK (BCD)
DSECT   = $265E
DPAGE   = $265F
NAMBUF  = $3528
FOUND   = $3538
ENTL    = $3539
ENTH    = $353A
PUMAP   = $3500     ; TRACK MAP FROM MAPTRK ($FF = USED)
ERRVEC  = $2A4F     ; OPERAND OF JMP AT $2A4E
TYPAHD  = $2325     ; KEY CAUGHT BY THE OUTPUT ROUTINE
ACIAS   = ::ACIAS   ; CONSOLE ACIA (set in ROM.S: $8000 SBC, $C080 FPGA)
ACIAD   = ::ACIAD
DIRTK   = $12
BUF     = $7000     ; SECTOR BUFFER (8 PAGES)
MAXTRK  = $39

; ---- OUR VARIABLES ----
SAVPG   = $3560
SAVSP   = $3561
RESL    = $3562
RESH    = $3563
OVECL   = $3564
OVECH   = $3565
D0      = $3566
SRC     = $3567
DST     = $3568
T1      = $3569
T2      = $356A
CT      = $356B
NS      = $356C
SI      = $356D
ERRS    = $356E
TMP     = $356F
TRKT    = $3570     ; 5 BYTES, INDEX 1-4
TMP2    = $3575
NEWDR   = $3576
TERR    = $3577
LOWL    = $3578
LOWH    = $3579
HIGL    = $357A
HIGH    = $357B
CK      = $357C
LL      = $357D
TT      = $357E
BAD     = $357F
SECN    = $3580     ; 16 SECTOR NUMBERS
SECP    = $3590     ; 16 SECTOR LENGTHS
LIST    = $35A0     ; 32 SORTED ENTRY NUMBERS
OFFL    = $35C0
OFFH    = $35C1
SKL     = $35C2
SKH     = $35C3
LIML    = $35C4
LIMH    = $35C5
HDRF    = $35C6
OLDL    = $35C7
OLDH    = $35C8
CNTL    = $35C9
CNTH    = $35CA
ENDL    = $35CB
ENDH    = $35CC
NUM     = $35CD
VAL     = $35CE
KS      = $35CF
KE      = $35D0
NFREE   = $35D1
TEML    = $35D2
TEMH    = $35D3
LNST    = $35D4     ; TY: 2/1 = EXPECTING LINE NUMBER LO/HI
LNL     = $35D5
ASMF    = $35D6     ; TY: 1 = ASSEMBLER FILE
TSIG    = $35D8     ; 2 BYTES $5A,$A5 WHEN THE TIMINGS BELOW ARE SET
HDDLY   = $35DA     ; HEAD LOAD/UNLOAD DELAY, MS (0 = NONE)
STPDLY  = $35DB     ; DELAY AFTER EACH TRACK STEP, MS
BLKF    = $35DC     ; TY: 1 = NO HEADER, TREAT AS FORTH SCREENS
COL     = $35DD     ; TY: COLUMN IN THE 64-CHARACTER LINE
PSP     = $35DE     ; TY: SPACES WAITING TO BE PRINTED
BLNK    = $35DF     ; TY: LAST LINE PRINTED WAS BLANK
LHAS    = $35E0     ; TY: THIS LINE HAS SOMETHING ON IT
LASTCH  = $35E1     ; TY: LAST CHARACTER TYPED (FOR REPEATS)
LLEN    = $35E2     ; TY: CHARACTERS IN LBUF
OCOL    = $35E3     ; TY: OUTPUT COLUMN
LNH     = $35E4     ; TY: LINE NUMBER HIGH BYTE
FPOS    = $35E5     ; TY: POSITION IN LBUF
FQ      = $35E6     ; TY: INSIDE QUOTES
FPEND   = $35E7     ; TY: SPACES WAITING IN THE OPERAND
FT      = $35E8     ; TY: TEMP
SLINE   = $35E9     ; TY: LINE IN THE SCREEN (0-15)
SCRN    = $35EA     ; TY: SCREEN NUMBER
HDRD    = $35EB     ; TY: SCREEN NUMBER ALREADY PRINTED
BASF    = $35EC     ; TY: 1 = BASIC PROGRAM
BST     = $35ED     ; TY: BASIC LINE STATE (4..1 = LINK/NUMBER BYTES)
LBUF    = $7800     ; TY: ONE ASSEMBLER LINE (UP TO 250 CHARS)
DLYMS   = $E3F3     ; ROM: WAIT X MILLISECONDS (X=0 -> 256)

        .org $D000
        jmp DISP
        jmp DIX             ; $D003 - NEW DI (FOR OTHER PROGRAMS)
        jmp DXHEAD          ; $D006 - HEAD LOAD/UNLOAD DELAY (FROM $E4D5)
        jmp DXSTEP          ; $D009 - STEP DELAY (FROM $E41B)
        jmp DIRCHK          ; $D00C - FORTH DIR! SAFETY CHECK (FROM $AAF2)

;================================================================
; DISPATCH (ENTERED FOR ANY COMMAND THE ROM DOESN'T KNOW)
;================================================================
DISP:   ldy #0
        lda (INBUF),y
        cmp #$0D            ; EMPTY LINE: JUST GIVE A NEW PROMPT
        beq PEEKRT
        jsr UCASE
        sta TMP
        iny
        lda (INBUF),y
        jsr UCASE
        sta TMP2
        ldx #0
@lp:    lda CMDTAB,x
        beq SYNERR
        cmp TMP
        bne @nx
        lda CMDTAB+1,x
        cmp TMP2
        bne @nx
        lda CMDTAB+3,x
        pha
        lda CMDTAB+2,x
        pha
        jmp SKIPAR          ; ITS RTS ENTERS THE COMMAND
@nx:    inx
        inx
        inx
        inx
        bne @lp
SYNERR: lda #$07
        jmp ERROR

CMDTAB: .byte "HL"
        .word HLCMD-1
        .byte "CO"
        .word COCMD-1
        .byte "RN"
        .word RNCMD-1
        .byte "TY"
        .word TYCMD-1
        .byte "VE"
        .word VECMD-1
        .byte "MD"
        .word MDCMD-1
        .byte "MF"
        .word MFCMD-1
        .byte "MM"
        .word MMCMD-1
        .byte "DT"
        .word DTCMD-1
        .byte 0

;================================================================
; COMMAND LINE HELPERS
;================================================================
PEEKC:  ldy CMDPOS          ; CHAR AT CMDPOS, NOT CONSUMED
        lda (INBUF),y
PEEKRT: rts

SKIPSP: jsr PEEKC
        cmp #' '
        bne @r
        inc CMDPOS
        bne SKIPSP
@r:     rts

ATEND:  jsr SKIPSP          ; Z=1 IF NOTHING MORE ON THE LINE
        cmp #$0D
        rts

NEXTC:  jsr PEEKC           ; NEXT CHAR, UPPER CASE, CONSUMED
        jsr UCASE
        cmp #$0D
        beq @r
        inc CMDPOS
@r:     rts

HEXVAL: jsr UCASE           ; A=ASCII -> 0-15, C=1 IF NOT HEX
        cmp #'0'
        bcc @bad
        cmp #'9'+1
        bcc @dig
        cmp #'A'
        bcc @bad
        cmp #'F'+1
        bcs @bad
        sbc #54             ; C=0: A-55
        clc
        rts
@dig:   sbc #'0'-1          ; C=0: A-'0'
        clc
        rts
@bad:   sec
        rts

HEXDIG: jsr NEXTC
        jsr HEXVAL
        bcs SYNERR
        rts

GETHB:  jsr HEXDIG          ; 2 HEX DIGITS -> A
        asl a
        asl a
        asl a
        asl a
        sta TMP
        jsr HEXDIG
        ora TMP
        rts

GETW:   jsr SKIPSP          ; 4 HEX DIGITS -> A=LO, Y=HI
        jsr GETHB
        pha
        jsr GETHB
        tax
        ply
        txa
        rts

DECDIG: jsr NEXTC
        sec
        sbc #'0'
        cmp #10
        bcs SYN2
        rts

GETTRK: jsr SKIPSP          ; 2 DECIMAL DIGITS -> BCD TRACK 01-39
        jsr DECDIG
        asl a
        asl a
        asl a
        asl a
        sta TMP
        jsr DECDIG
        ora TMP
        beq SYN2
        cmp #MAXTRK+1
        bcs SYN2
        rts
SYN2:   jmp SYNERR

RANGE:  jsr ATEND           ; [TT[-TT]] -> T1,T2 (DEFAULT 01-39)
        bne @r1
        lda #$01
        sta T1
        lda #MAXTRK
        sta T2
        rts
@r1:    jsr GETTRK
        sta T1
        sta T2
        jsr PEEKC
        cmp #'-'
        bne @r2
        inc CMDPOS
        jsr GETTRK
        sta T2
@r2:    lda T2
        cmp T1
        bcc SYN2
        rts

GETDRV: jsr SKIPSP          ; A-D -> 1-4
        jsr NEXTC
        cmp #'A'
        bcc SYN2
        cmp #'E'
        bcs SYN2
        sbc #$3F            ; C=0 HERE: A-$40
        rts

GETNAM: jsr SKIPSP          ; NAME (NO SPACES) -> NAMBUF
        ldx #0
@lp:    jsr PEEKC
        cmp #$21
        bcc @end
        cmp #'#'
        beq SYN2
        cpx #14
        beq SYN2
        sta NAMBUF,x
        inx
        inc CMDPOS
        bra @lp
@end:   txa
        beq SYN2
        lda #' '
@pad:   cpx #14
        beq @r
        sta NAMBUF,x
        inx
        bra @pad
@r:     rts

;================================================================
; OUTPUT / MISC HELPERS
;================================================================
PRSP:   lda #' '
        jmp OUTCH

PRBCD:  jsr BIN2BCD         ; PRINT BINARY 0-99 AS 2 DIGITS
        jmp PRHEX

BIN2BCD: phx                ; A (0-99) -> BCD
        ldx #0
@l:     cmp #10
        bcc @d
        sbc #10
        inx
        bra @l
@d:     sta TMP
        txa
        asl a
        asl a
        asl a
        asl a
        ora TMP
        plx
        rts

BCDINC: sed                 ; A = A+1 (BCD)
        clc
        adc #1
        cld
        rts

SETBUF: lda #<BUF
        sta MEMLO
        lda #>BUF
        sta MEMHI
        rts

; KEYCHK: ESC OR CTRL-C -> C=1 (STOP). SPACE PAUSES UNTIL NEXT KEY.
; THE ROM'S ACIA OUTPUT ROUTINE GRABS ANY KEY THAT ARRIVES WHILE IT
; PRINTS AND LEAVES IT IN $2325, SO LOOK THERE AS WELL AS THE ACIA.
KEYCHK: jsr KEYGET
        bcc @no
        cmp #' '
        bne @tst
@w:     jsr KEYGET
        bcc @w
@tst:   cmp #$1B
        beq @ab
        cmp #$03
        beq @ab
@no:    clc
        rts
@ab:    sec
        rts
KEYGET: lda TYPAHD          ; C=1 AND A=KEY IF ONE IS WAITING
        beq @acia
        stz TYPAHD
        sec
        rts
@acia:  lda ACIAS
        lsr a
        bcc @none
        jsr KEYIN
        sec
        rts
@none:  clc
        rts
KEYIN:  lda ACIAD
        and #$7F
        rts

SERIN:  jsr KEYGET          ; WAIT FOR A CONSOLE CHAR
        bcc SERIN
        rts

; ERROR TRAP: DOS ERRORS GO TO (RESL) WITH SP = SAVSP
SETTRAP: lda ERRVEC
        sta OVECL
        lda ERRVEC+1
        sta OVECH
        lda #<TRAP
        sta ERRVEC
        lda #>TRAP
        sta ERRVEC+1
        rts
CLRTRAP: lda OVECL
        sta ERRVEC
        lda OVECH
        sta ERRVEC+1
        rts
TRAP:   ldx SAVSP
        txs
        jmp (RESL)

; SCANTRK: CURRENT TRACK -> SECN/SECP TABLE, NS = COUNT
SCANTRK: jsr HLOAD
        lda #1
        sta DSECT
        jsr FINDHDR
        lda #0
        sta SECCNT
        sta NS
@l:     jsr NXTSEC
        bcc @d
        ldx NS
        cpx #16
        bcs @l
        lda SECNO
        sta SECN,x
        lda SECPGS
        sta SECP,x
        inc NS
        bra @l
@d:     jmp HUNLD

; READ SECTOR SECN[SI] OF CURRENT TRACK INTO BUF
RDSI:   ldx SI
        lda SECN,x
        sta DSECT
        jsr SETBUF
        jsr HLOAD
        jsr RDRAW
        jmp HUNLD

;================================================================
; MD SSSS [EEEE]  - DUMP MEMORY (ESC STOPS, SPACE PAUSES)
;================================================================
MDCMD:  jsr GETW
        sta P1
        sty P1+1
        jsr ATEND
        bne @e
        clc                 ; DEFAULT: 128 BYTES
        lda P1
        adc #$7F
        sta ENDL
        lda P1+1
        adc #0
        sta ENDH
        bcc MDLINE
        lda #$FF
        sta ENDL
        sta ENDH
        bra MDLINE
@e:     jsr GETW
        sta ENDL
        sty ENDH
MDLINE: jsr CRLF
        lda P1+1
        jsr PRHEX
        lda P1
        jsr PRHEX
        lda #':'
        jsr OUTCH
        ldy #0
@hx:    jsr PRSP
        lda (P1),y
        jsr PRHEX
        iny
        cpy #16
        bne @hx
        jsr PRSP
        jsr PRSP
        ldy #0
@as:    lda (P1),y
        cmp #$20
        bcc @dot
        cmp #$7F
        bcc @pr
@dot:   lda #'.'
@pr:    jsr OUTCH
        iny
        cpy #16
        bne @as
        clc
        lda P1
        adc #16
        sta P1
        lda P1+1
        adc #0
        sta P1+1
        bcs @done           ; WRAPPED PAST $FFFF
        lda ENDL            ; DONE WHEN P1 > END
        cmp P1
        lda ENDH
        sbc P1+1
        bcc @done
        jsr KEYCHK
        bcc MDLINE
@done:  jmp CRLF

;================================================================
; MF SSSS EEEE BB  - FILL MEMORY
;================================================================
MFCMD:  jsr GETW
        sta P1
        sty P1+1
        jsr GETW
        sta ENDL
        sty ENDH
        jsr SKIPSP
        jsr GETHB
        sta TMP2
        lda ENDL
        cmp P1
        lda ENDH
        sbc P1+1
        bcc SYN3
@lp:    lda TMP2
        sta (P1)
        lda P1
        cmp ENDL
        bne @nx
        lda P1+1
        cmp ENDH
        beq @dn
@nx:    inc P1
        bne @lp
        inc P1+1
        bra @lp
@dn:    rts
SYN3:   jmp SYNERR

;================================================================
; MM SSSS EEEE DDDD  - MOVE MEMORY
;================================================================
MMCMD:  jsr GETW
        sta P1
        sty P1+1
        jsr GETW
        sta ENDL
        sty ENDH
        jsr GETW
        sta P2
        sty P2+1
        sec                 ; CNT = END-START+1
        lda ENDL
        sbc P1
        sta CNTL
        lda ENDH
        sbc P1+1
        sta CNTH
        bcc SYN3
        inc CNTL
        bne @c1
        inc CNTH
@c1:    lda P2              ; DEST > SOURCE -> COPY BACKWARDS
        cmp P1
        lda P2+1
        sbc P1+1
        bcc MMFWD
        lda ENDL            ; P1 = END
        sta P1
        lda ENDH
        sta P1+1
        clc                 ; P2 = DEST+CNT-1
        lda P2
        adc CNTL
        sta P2
        lda P2+1
        adc CNTH
        sta P2+1
        jsr DECP2
@bl:    lda (P1)
        sta (P2)
        lda P1
        bne @b1
        dec P1+1
@b1:    dec P1
        jsr DECP2
        jsr DECCNT
        bne @bl
        rts
MMFWD:
@fl:    lda (P1)
        sta (P2)
        inc P1
        bne @f1
        inc P1+1
@f1:    inc P2
        bne @f2
        inc P2+1
@f2:    jsr DECCNT
        bne @fl
        rts
DECP2:  lda P2
        bne @d
        dec P2+1
@d:     dec P2
        rts
DECCNT: lda CNTL            ; CNT-1, Z=1 WHEN ZERO
        bne @d
        dec CNTH
@d:     dec CNTL
        lda CNTL
        ora CNTH
        rts

;================================================================
; HL  - LOAD INTEL HEX FROM THE CONSOLE
;================================================================
HLCMD:  jsr PRINT
        .byte "SEND HEX FILE (ESC ENDS)",$0D,$0A,0
        lda #$FF
        sta LOWL
        sta LOWH
        stz HIGL
        stz HIGH
        stz ERRS
        bra HLREC
HLESC:  jmp HLEND
HLREC:  jsr HLGET           ; ROM.S: TAKES MOS ';' RECORDS ITSELF
        cmp #$1B
        beq HLESC
        cmp #$03
        beq HLESC
        cmp #':'
        bne HLREC
        stz CK
        stz BAD
        jsr SERHB
        sta LL
        jsr SERHB
        sta P1+1
        jsr SERHB
        sta P1
        jsr SERHB
        sta TT
        ldy #0
@dl:    cpy LL
        beq @ck
        jsr SERHB
        ldx TT
        bne @sk
        sta (P1),y          ; TYPE 00 = DATA
@sk:    iny
        bra @dl
@ck:    jsr SERHB           ; CHECKSUM
        lda TT
        bne @nr
        jsr HLRNG           ; DATA RECORD: NOTE LOWEST/HIGHEST ADDRESS
@nr:    lda CK
        ora BAD
        beq @good
        inc ERRS
        lda TT
        cmp #$01
        beq HLEOF
        lda #'X'
        bra @mk
@good:  lda TT
        beq @dot
        cmp #$01
        beq HLEOF           ; END OF FILE RECORD
        lda #'?'            ; OTHER TYPES IGNORED
        bra @mk
@dot:   lda #'.'
@mk:    jsr OUTCH
        jmp HLREC
HLEOF:  jmp HLEND

; LOW = MIN(LOW,ADDR), HIGH = MAX(HIGH,ADDR+LL-1)
HLRNG:  lda LL
        beq @x
        lda P1
        cmp LOWL
        lda P1+1
        sbc LOWH
        bcs @nl
        lda P1
        sta LOWL
        lda P1+1
        sta LOWH
@nl:    clc
        lda P1
        adc LL
        sta TEML
        lda P1+1
        adc #0
        sta TEMH
        lda TEML
        bne @t1
        dec TEMH
@t1:    dec TEML
        lda HIGL
        cmp TEML
        lda HIGH
        sbc TEMH
        bcs @x
        lda TEML
        sta HIGL
        lda TEMH
        sta HIGH
@x:     rts

HLEND:  jsr DRAIN
        jsr CRLF
        lda HIGL            ; ANYTHING LOADED?
        cmp LOWL
        lda HIGH
        sbc LOWH
        bcs @ld
        jsr PRINT
        .byte "NONE LOADED",0
        bra @er
@ld:    jsr PRINT
        .byte "LOADED ",0
        lda LOWH
        jsr PRHEX
        lda LOWL
        jsr PRHEX
        lda #'-'
        jsr OUTCH
        lda HIGH
        jsr PRHEX
        lda HIGL
        jsr PRHEX
@er:    lda ERRS
        beq @x
        jsr PRINT
        .byte "  BAD: ",0
        lda ERRS
        jsr PRHEX
@x:     jmp CRLF

; TWO HEX CHARS FROM THE CONSOLE -> A, ADDED TO CK. KEEPS X,Y.
SERHB:  jsr SERIN
        jsr HEXVAL
        bcc @1
        inc BAD
        lda #0
@1:     asl a
        asl a
        asl a
        asl a
        sta TMP
        jsr SERIN
        jsr HEXVAL
        bcc @2
        inc BAD
        lda #0
@2:     ora TMP
        pha
        clc
        adc CK
        sta CK
        pla
        rts

; SWALLOW WHATEVER IS STILL ARRIVING (TRAILING CR/LF), ~0.3 S QUIET
DRAIN:  ldx #0
        ldy #0
@l:     lda ACIAS
        lsr a
        bcc @n
        lda ACIAD
        ldx #0
        ldy #0
@n:     dex
        bne @l
        dey
        bne @l
        rts

;================================================================
; RN OLD NEW  - RENAME
;================================================================
RNCMD:  lda DPAGE
        sta SAVPG
        jsr GETNAM
        jsr LDDIR
        stz FOUND
        jsr FNDNM
        lda FOUND
        bne @f
        lda #$0C            ; FILE NOT FOUND
        jmp ERROR
@f:     lda ENTL
        sta OLDL
        lda ENTH
        sta OLDH
        jsr GETNAM
        stz FOUND
        jsr FNDNM
        lda FOUND
        beq @ok
        jsr PRINT
        .byte "NAME IN USE",$0D,$0A,0
        bra RNEND
@ok:    lda OLDL
        sta ENTPL
        lda OLDH
        sta ENTPH
        ldy #13
@cp:    lda NAMBUF,y
        sta (ENTPL),y
        dey
        bpl @cp
        jsr WRDIRS
RNEND:  lda SAVPG
        sta DPAGE
        rts

; WRITE DIRECTORY PAGE ENTPH ($33/$34) BACK AS SECTOR 1/2
WRDIRS: lda #DIRTK
        jsr SEEK
        stz MEMLO
        lda ENTPH
        sta MEMHI
        sec
        sbc #$32
        sta DSECT
        lda #1
        sta DPAGE
        jsr HLOAD
        jsr WRSEC
        jmp HUNLD

;================================================================
; DI  - SORTED DIRECTORY + FREE TRACKS ("DI TT" -> OLD DI)
;================================================================
DIX:    ldy CMDPOS
@sk:    lda (INBUF),y
        cmp #' '
        bne @c
        iny
        bne @sk
@c:     cmp #$21
        bcc DISORT
        cmp #'#'
        beq DISORT
        cmp #'"'
        beq DISORT
        jmp DIOLD
DISORT: lda DPAGE
        sta SAVPG
        jsr PRINT
        .byte $0A,"   DIRECTORY",$0D,$0A,$0A,0
        jsr LDDIR
        ldx #0              ; LIST THE USED ENTRIES
        ldy #0
@b:     tya
        jsr EPTR
        jsr ISEMPTY
        beq @nx
        tya
        sta LIST,x
        inx
@nx:    iny
        cpy #32
        bne @b
        stx NUM
        jsr SORT
        ldx #0
@p:     cpx NUM
        beq @fr
        stx SI
        lda LIST,x
        jsr EPTR
        ldy #0
@n:     lda (ENTPL),y
        jsr OUTCH
        iny
        cpy #14
        bne @n
        jsr PRINT
        .byte "  ",0
        ldy #14
        lda (ENTPL),y
        jsr PRHEX
        jsr PRINT
        .byte " - ",0
        ldy #15
        lda (ENTPL),y
        jsr PRHEX
        jsr CRLF
        jsr KEYCHK
        bcs @fr
        ldx SI
        inx
        bra @p
@fr:    jsr FREELIST
        lda SAVPG
        sta DPAGE
        rts

EPTR:   pha                 ; ENTRY A (0-31) -> ENTPL/H. KEEPS X,Y,A
        pha
        and #$0F
        asl a
        asl a
        asl a
        asl a
        sta ENTPL
        pla
        lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc #$33
        sta ENTPH
        pla
        rts

ISEMPTY: phy                ; Z=1 IF NAME IS 14 X '#'
        ldy #13
@l:     lda (ENTPL),y
        cmp #'#'
        bne @no
        dey
        bpl @l
        ply
        lda #0
        rts
@no:    ply
        lda #1
        rts

SORT:   ldx #1              ; INSERTION SORT LIST BY START, END
@o:     cpx NUM
        bcs @done
        stx SI
        lda LIST,x
        sta VAL
        jsr EPTR
        ldy #14
        lda (ENTPL),y
        sta KS
        iny
        lda (ENTPL),y
        sta KE
@in:    cpx #0
        beq @put
        lda LIST-1,x
        jsr EPTR
        ldy #14
        lda (ENTPL),y
        cmp KS
        bcc @put
        bne @sh
        iny
        lda (ENTPL),y
        cmp KE
        bcc @put
        beq @put
@sh:    lda LIST-1,x
        sta LIST,x
        dex
        bra @in
@put:   lda VAL
        sta LIST,x
        ldx SI
        inx
        bra @o
@done:  rts

FREELIST: stz FOUND
        jsr MAPTRK
        jsr PRINT
        .byte $0D,$0A,"FREE TRACKS:",0
        stz NFREE
        ldx #1
@t:     cpx #40
        bcs @end
        lda PUMAP,x
        bne @u
        stx T1              ; FREE RUN STARTS AT X
@r:     inx
        cpx #40
        bcs @ce
        lda PUMAP,x
        beq @r
@ce:    stx T2              ; RUN IS T1 .. T2-1
        jsr PRSP
        lda T1
        jsr PRBCD
        txa
        sec
        sbc T1
        clc
        adc NFREE
        sta NFREE
        dex
        cpx T1
        beq @one
        lda #'-'
        jsr OUTCH
        txa
        jsr PRBCD
@one:   ldx T2
        bra @t
@u:     inx
        bra @t
@end:   lda NFREE
        bne @c
        jsr PRINT
        .byte " NONE",0
@c:     jsr PRINT
        .byte "  (",0
        lda NFREE
        jsr PRBCD
        jsr PRINT
        .byte " FREE)",$0D,$0A,0
        rts

;================================================================
; TY NAME  - TYPE A TEXT FILE (ESC STOPS, SPACE PAUSES)
;================================================================
TYCMD:  lda DPAGE
        sta SAVPG
        jsr GETNM
        ldx #13             ; NEED A NAME
@nm:    lda NAMBUF,x
        cmp #' '
        bne @hn
        dex
        bpl @nm
        jmp SYNERR
@hn:    jsr LDDIR
        stz FOUND
        jsr FNDNM
        lda FOUND
        bne @f
        lda #$0C
        jmp ERROR
@f:     lda ENTL
        sta ENTPL
        lda ENTH
        sta ENTPH
        ldy #14
        lda (ENTPL),y
        sta CT
        iny
        lda (ENTPL),y
        sta T2
        stz OFFL
        stz OFFH
        lda #1
        sta HDRF
        jsr CRLF
TYTRK:  lda CT
        jsr SEEK
        jsr SCANTRK
        stz SI
TYSEC:  ldx SI
        cpx NS
        beq TYNXT
        jsr RDSI
        lda #<BUF
        sta P1
        lda #>BUF
        sta P1+1
        stz CNTL
        lda DPAGE
        sta CNTH
        lda HDRF
        beq @b
        stz HDRF
        jsr TYHDR
@b:     lda OFFL            ; PAST THE END?
        cmp LIML
        lda OFFH
        sbc LIMH
        bcs TYDONE
        lda OFFL            ; BEFORE THE START?
        cmp SKL
        lda OFFH
        sbc SKH
        bcc @np
        lda (P1)
        jsr TYCH
        bcs TYDONE
@np:    inc OFFL
        bne @o1
        inc OFFH
@o1:    inc P1
        bne @o2
        inc P1+1
@o2:    jsr DECCNT
        bne @b
        inc SI
        bra TYSEC
TYNXT:  lda CT
        cmp T2
        beq TYDONE
        jsr BCDINC
        sta CT
        bra TYTRK
TYDONE: jsr CRLF
        lda SAVPG
        sta DPAGE
        rts

;
; TYCH: TYPE ONE BYTE. IN ASSEMBLER FILES EACH LINE STARTS WITH A
; 2-BYTE LINE NUMBER (LO,HI), PRINTED IN DECIMAL; A BYTE $80-$FF
; REPEATS THE CHARACTER BEFORE IT 256-N MORE TIMES. C=1 IF ESC PRESSED.
TYCH:   ldx BLKF
        beq @bas
        jmp TYBLK
@bas:   ldx BASF
        beq @asm
        jmp TYBAS
@asm:   ldx LNST
        beq @txt
        cpx #2
        bne @hi
        sta LNL             ; LINE NUMBER LOW BYTE
        dec LNST
        clc
        rts
@hi:    sta LNH             ; HIGH BYTE; START COLLECTING THE LINE
        stz LNST
        stz LLEN
        clc
        rts
@txt:   cmp #$0D            ; CR -> NEW LINE, CHECK KEYS
        bne @1
        lda ASMF
        beq @nl
        jsr FMTLIN          ; ASSEMBLER: PRINT THE LINE IN COLUMNS
        lda #2
        sta LNST
@nl:    jsr CRLF
        lda #' '
        sta LASTCH
        jmp KEYCHK
@1:     cmp #$80            ; $80-$FF: REPEAT THE LAST CHARACTER
        bcc @2              ; 256-N MORE TIMES ($FF = ONCE MORE,
        eor #$FF            ; $FE = TWICE ...)
        tay
        iny
@rp:    lda LASTCH
        jsr TYPUT
        dey
        bne @rp
        clc
        rts
@2:     cmp #$20
        bcc @no
        cmp #$7F
        bcs @no
        sta LASTCH
        jsr TYPUT
@no:    clc
        rts

TYPUT:  ldx ASMF            ; ASSEMBLER LINES GO TO THE LINE BUFFER
        bne @b
        jmp OUTCH
@b:     ldx LLEN
        cpx #250
        bcs @x
        sta LBUF,x
        inc LLEN
@x:     rts

;----------------------------------------------------------------
; FMTLIN: PRINT AN ASSEMBLER LINE FROM LBUF IN COLUMNS
;   LINE NUMBER RIGHT-ALIGNED IN 5, LABEL AT 7, MNEMONIC AT 15,
;   OPERAND AT 21, COMMENT AT 33. A LINE STARTING WITH ; IS
;   PRINTED FROM COLUMN 7 AS IT IS.
;----------------------------------------------------------------
FMTLIN: stz OCOL
        stz FPOS
        lda LNL             ; DIGITS IN THE LINE NUMBER -> X
        ldy LNH
        jsr DIGCNT
        stx FT
        lda #5
        sec
        sbc FT
        tax
        beq @n
@pad:   jsr OSP
        dex
        bne @pad
@n:     lda LNL
        ldy LNH
        jsr PRDEC
        lda #5
        sta OCOL
        lda #7
        jsr PADTO
        jsr FPEEK           ; WHOLE-LINE COMMENT?
        beq @x
        cmp #';'
        beq @rest
        cmp #' '
        beq @mn
        jsr FWORD           ; LABEL
@mn:    jsr FSKIP
        beq @x
        cmp #';'
        beq @cm
        lda #15
        jsr PADTO
        jsr FWORD           ; MNEMONIC
        jsr FSKIP
        beq @x
        cmp #';'
        beq @cm
        lda #21
        jsr PADTO
        jsr FOPER           ; OPERAND (STOPS AT AN UNQUOTED ;)
        jsr FPEEK
        beq @x
@cm:    lda #33
        jsr PADTO
@rest:  jsr FPEEK           ; REST OF THE LINE AS IT IS
        beq @x
        jsr OPUT
        inc FPOS
        bra @rest
@x:     rts

FPEEK:  ldx FPOS            ; A = NEXT LINE CHAR, Z=1 AT THE END
        cpx LLEN
        bcs @e
        lda LBUF,x
        rts
@e:     lda #0
        rts

FSKIP:  jsr FPEEK           ; SKIP SPACES; A = NEXT, Z=1 AT THE END
        beq @r
        cmp #' '
        bne @r
        inc FPOS
        bra FSKIP
@r:     rts

FWORD:  jsr FPEEK           ; PRINT UP TO THE NEXT SPACE
        beq @r
        cmp #' '
        beq @r
        jsr OPUT
        inc FPOS
        bra FWORD
@r:     rts

FOPER:  stz FQ              ; OPERAND: QUOTES KEEP ; AND SPACES,
        stz FPEND           ; TRAILING SPACES DROPPED
@l:     jsr FPEEK
        beq @r
        ldx FQ
        bne @in
        cmp #';'
        beq @r
        cmp #' '
        bne @in
        inc FPEND
        inc FPOS
        bra @l
@in:    pha
@sp:    lda FPEND
        beq @c
        jsr OSP
        dec FPEND
        bra @sp
@c:     pla
        cmp #$27            ; ' OR " TOGGLES QUOTING
        beq @q
        cmp #$22
        bne @o
@q:     pha
        lda FQ
        eor #1
        sta FQ
        pla
@o:     jsr OPUT
        inc FPOS
        bra @l
@r:     rts

OSP:    lda #' '
OPUT:   inc OCOL
        jmp OUTCH

PADTO:  sta FT              ; SPACES TO COLUMN A (AT LEAST ONE)
        jsr OSP
@l:     lda OCOL
        cmp FT
        bcs @r
        jsr OSP
        bra @l
@r:     rts

DIGCNT: sta TEML            ; X = DIGITS IN Y:A (1-5)
        sty TEMH
        ldx #1
@l:     cpx #5
        beq @r
        lda TEML            ; VALUE >= 10^X ?
        cmp DTL-1,x
        lda TEMH
        sbc DTH-1,x
        bcc @r
        inx
        bra @l
@r:     rts
DTL:    .byte <10,<100,<1000,<10000
DTH:    .byte >10,>100,>1000,>10000

; BASIC PROGRAM: EACH LINE IS LINK (2), LINE NUMBER (2), TEXT, $00.
; A LINK OF 0 ENDS THE PROGRAM. KEYWORD TOKENS ($80-$FF) ARE LOOKED
; UP IN BASIC'S OWN TABLE AT $0284 IF BASIC IS IN MEMORY, OTHERWISE
; SHOWN AS {XX}.
KWTAB   = $0284
TYBAS:  ldx BST
        beq @txt
        cpx #4
        bne @3
        sta TMP2            ; LINK LOW
        bra @dn
@3:     cpx #3
        bne @2
        ora TMP2            ; LINK = 0: END OF PROGRAM
        bne @dn
        sec
        rts
@2:     cpx #2
        bne @1
        sta LNL
        bra @dn
@1:     tay                 ; LINE NUMBER HIGH: PRINT IT
        lda LNL
        jsr PRDEC
        jsr PRSP
@dn:    dec BST
        clc
        rts
@txt:   cmp #0
        bne @t1
        jsr CRLF            ; END OF LINE
        lda #4
        sta BST
        jmp KEYCHK
@t1:    cmp #$80
        bcs PRKW
        cmp #$20
        bcc @no
        jsr OUTCH
@no:    clc
        rts
PRKW:   sta TMP             ; PRINT KEYWORD FOR TOKEN A
        lda KWTAB
        cmp #'E'
        bne @hex
        lda KWTAB+2
        cmp #$C4            ; "END" WITH BIT 7 ON THE D
        bne @hex
        lda TMP
        sec
        sbc #$80
        tax
        ldy #0
@sk:    cpx #0
        beq @pr
@w:     cpy #$E0            ; RAN OFF THE TABLE
        bcs @hex
        lda KWTAB,y
        iny
        asl a
        bcc @w
        dex
        bra @sk
@pr:    lda KWTAB,y
        pha
        and #$7F
        jsr OUTCH
        iny
        pla
        bpl @pr
        clc
        rts
@hex:   lda #'{'
        jsr OUTCH
        lda TMP
        jsr PRHEX
        lda #'}'
        jsr OUTCH
        clc
        rts

; FORTH SCREENS: 16 LINES OF 64 CHARACTERS, NO CR. BREAK EVERY 64,
; DROP TRAILING SPACES, AND PRINT RUNS OF BLANK LINES AS ONE.
TYBLK:  cmp #$21
        bcc @sp
        cmp #$7F
        bcc @ch
@sp:    inc PSP             ; SPACE (OR CONTROL/$00): HOLD IT
        bra @col
@ch:    pha
        lda HDRD            ; FIRST TEXT IN THIS SCREEN: NUMBER IT
        bne @ps
        jsr SCRHDR
@ps:    lda PSP             ; FLUSH HELD SPACES
        beq @pc
        jsr PRSP
        dec PSP
        bra @ps
@pc:    pla
        jsr OUTCH
        lda #1
        sta LHAS
@col:   inc COL
        lda COL
        cmp #64
        bcc @no
        stz COL             ; END OF A 64-CHARACTER LINE
        stz PSP
        inc SLINE           ; 16 LINES = NEXT SCREEN
        lda SLINE
        cmp #16
        bcc @eol
        stz SLINE
        inc SCRN
        stz HDRD
@eol:   lda LHAS
        beq @bl
        stz LHAS
        stz BLNK
        bra @nl
@bl:    lda BLNK            ; BLANK LINE: ONLY ONE IN A ROW
        bne @no
        inc BLNK
@nl:    jsr CRLF
        jmp KEYCHK
@no:    clc
        rts

; "SCR # N" BEFORE THE FIRST LINE OF TEXT IN EACH SCREEN. NUMBERS
; COUNT FROM 0 AT THE START OF THE FILE, AS FORTH NUMBERS THEM
; AFTER USE NAME. EMPTY SCREENS ARE NOT SHOWN.
SCRHDR: lda #1
        sta HDRD
        jsr PRINT
        .byte "SCR # ",0
        lda SCRN
        ldy #0
        jsr PRDEC
        jmp CRLF

; PRDEC: PRINT Y:A (0-65535) IN DECIMAL, NO LEADING ZEROS
PRDEC:  sta TEML
        sty TEMH
        ldx #0              ; X = POWER OF TEN INDEX
        stz TMP2            ; 1 = A DIGIT HAS BEEN PRINTED
@pw:    ldy #'0'
@sub:   lda TEML
        sec
        sbc P10L,x
        pha
        lda TEMH
        sbc P10H,x
        bcc @dn
        sta TEMH
        pla
        sta TEML
        iny
        bra @sub
@dn:    pla
        tya
        cpx #4              ; ALWAYS PRINT THE UNITS
        beq @pr
        cmp #'0'
        bne @pr
        lda TMP2
        beq @nx
        lda #'0'
@pr:    jsr OUTCH
        lda #1
        sta TMP2
@nx:    inx
        cpx #5
        bne @pw
        rts
P10L:   .byte <10000,<1000,<100,<10,<1
P10H:   .byte >10000,>1000,>100,>10,>1

; WORKSPACE HEADER: BUF+0/1 = START, BUF+2/3 = END, BUF+4 = TRACKS.
; THE FILE IS AN IMAGE OF MEMORY FROM $XX79 (XX = START'S PAGE):
; BASIC STARTS AT $3A7F, THE ASSEMBLER AT $327E. IF THE HEADER LOOKS
; RIGHT, TYPE ONLY START..END-1. AN ASSEMBLER FILE ($XX7E) ALSO GETS
; ITS LINE NUMBERS DECODED.
TYHDR:  stz ASMF
        stz BLKF
        stz BASF
        stz SLINE
        stz SCRN
        stz HDRD
        stz COL
        stz PSP
        stz LHAS
        lda #1
        sta BLNK
        stz LNST
        lda BUF             ; START LOW BYTE MUST BE $7D-$7F
        cmp #$7D
        bcc @inv
        cmp #$80
        bcs @inv
        lda BUF+2           ; END >= START
        cmp BUF
        lda BUF+3
        sbc BUF+1
        bcc @inv
        sec                 ; SKIP = START - $XX79
        lda BUF
        sbc #$79
        sta SKL
        stz SKH
        sec                 ; LIMIT = END - $XX79
        lda BUF+2
        sbc #$79
        sta LIML
        lda BUF+3
        sbc BUF+1
        sta LIMH
        lda BUF
        cmp #$7F
        bne @nb
        inc BASF            ; BASIC PROGRAM ($xx7F)
        lda #4
        sta BST
        rts
@nb:    cmp #$7E
        bne @r
        inc ASMF            ; ASSEMBLER SOURCE
        lda #2
        sta LNST
@r:     rts
@inv:   lda #1              ; NO HEADER: FORTH SCREENS
        sta BLKF
        stz SKL
        stz SKH
        lda #$FF
        sta LIML
        sta LIMH
        rts

;================================================================
; VE [TT[-TT]]  - VERIFY TRACKS (READ EVERY SECTOR)
;================================================================
VECMD:  jsr RANGE
        lda DPAGE
        sta SAVPG
        stz ERRS
        jsr SETTRAP
        lda T1
        sta CT
VETRK:  jsr CRLF
        lda CT
        jsr PRHEX
        lda #':'
        jsr OUTCH
        stz TERR
        tsx
        stx SAVSP
        lda #<VEBADT
        sta RESL
        lda #>VEBADT
        sta RESH
        lda CT
        jsr SEEK
        jsr SCANTRK
        lda NS
        bne @s
        jsr PRINT
        .byte " EMPTY",0
        bra VENXT
@s:     stz SI
VESEC:  ldx SI
        cpx NS
        beq VEOK
        jsr PRSP
        lda SECN,x
        jsr PRHEX
        lda #<VEBADS
        sta RESL
        lda #>VEBADS
        sta RESH
        jsr RDSI
VESNX:  inc SI
        bra VESEC
VEOK:   lda TERR
        bne VENXT
        jsr PRINT
        .byte "  OK",0
VENXT:  jsr KEYCHK
        bcs VEEND
        lda CT
        cmp T2
        beq VEEND
        jsr BCDINC
        sta CT
        jmp VETRK
VEEND:  jsr CLRTRAP
        jsr CRLF
        lda ERRS
        bne @e
        jsr PRINT
        .byte "NO ERRORS",$0D,$0A,0
        bra @x
@e:     jsr PRBCD
        jsr PRINT
        .byte " ERRORS",$0D,$0A,0
@x:     lda SAVPG
        sta DPAGE
        rts
VEBADT: inc ERRS            ; TRACK UNREADABLE
        bra VENXT
VEBADS: inc ERRS            ; SECTOR UNREADABLE
        lda #1
        sta TERR
        bra VESNX

;================================================================
; CO S D [TT[-TT]]  - COPY TRACKS BETWEEN DRIVES
;================================================================
COCMD:  jsr GETDRV
        sta SRC
        jsr GETDRV
        sta DST
        cmp SRC
        bne @ok
        jmp SYNERR
@ok:    jsr RANGE
        jsr PRINT
        .byte "COPY ",0
        lda SRC
        jsr PRDRV
        jsr PRINT
        .byte " TO ",0
        lda DST
        jsr PRDRV
        jsr PRINT
        .byte ", TRACKS ",0
        lda T1
        jsr PRHEX
        lda #'-'
        jsr OUTCH
        lda T2
        jsr PRHEX
        jsr PRINT
        .byte "  SURE? ",0
        jsr GETKEY
        jsr UCASE
        pha
        jsr CRLF
        pla
        cmp #'Y'
        beq @go
        rts
@go:    lda DPAGE
        sta SAVPG
        lda #$FF            ; HEAD POSITIONS NOT KNOWN YET
        ldx #4
@tk:    sta TRKT,x
        dex
        bne @tk
        lda DRIVE
        sta D0
        tax
        lda CURTRK
        sta TRKT,x
        jsr SETTRAP
        lda #<COABRT
        sta RESL
        lda #>COABRT
        sta RESH
        tsx
        stx SAVSP
        lda T1
        sta CT
COTRK:  lda CT
        jsr PRHEX
        lda #':'
        jsr OUTCH
        lda SRC
        jsr SELDRV
        lda CT
        jsr SEEK
        jsr SCANTRK
        lda DST
        jsr SELDRV
        lda CT
        jsr SEEK
        jsr INITTRK
        stz SI
COSEC:  ldx SI
        cpx NS
        beq CONXT
        lda SRC
        jsr SELDRV
        lda CT
        jsr SEEK
        jsr RDSI
        lda DST
        jsr SELDRV
        lda CT
        jsr SEEK
        ldx SI
        lda SECN,x
        sta DSECT
        lda SECP,x
        sta DPAGE
        jsr SETBUF
        jsr HLOAD
        jsr WRSEC
        jsr HUNLD
        lda #'.'
        jsr OUTCH
        inc SI
        bra COSEC
CONXT:  jsr CRLF
        jsr KEYCHK
        bcs CODONE
        lda CT
        cmp T2
        beq CODONE
        jsr BCDINC
        sta CT
        jmp COTRK
CODONE: jsr CORST
        jsr CLRTRAP
        jsr PRINT
        .byte "COPY DONE",$0D,$0A,0
        rts
COABRT: jsr CORST           ; ERROR: PUT DRIVE BACK, THEN NORMAL ABORT
        jsr CLRTRAP
        jmp (OVECL)
CORST:  lda D0
        jsr SELDRV
        lda SAVPG
        sta DPAGE
        rts

PRDRV:  clc
        adc #$40
        jmp OUTCH

; SELECT DRIVE A (1-4), KEEPING EACH DRIVE'S HEAD POSITION
SELDRV: pha
        ldx DRIVE
        lda CURTRK
        sta TRKT,x
        pla
        sta NEWDR
        jsr SELECT
        ldx NEWDR
        lda TRKT,x
        cmp #$FF
        bne @k
        jsr HOME            ; FIRST USE: FIND TRACK 0
        ldx NEWDR
        lda CURTRK
        sta TRKT,x
        rts
@k:     sta CURTRK
        rts

;================================================================
; DISK TIMING. THE ROM'S FIXED DELAYS (40 MS AFTER EVERY HEAD LOAD
; AND UNLOAD, 8 MS AFTER EVERY STEP) ARE NOW READ FROM RAM.
; DEFAULT AFTER POWER-UP IS GOTEK TIMING (HEAD 0 MS, STEP 3 MS).
; BOTH ROUTINES RETURN X=0, Y=0 AND KEEP A AND THE CARRY, LIKE THE
; ROM CODE THEY REPLACE (SEEK AND D9 RELY ON THAT).
;================================================================
DXHEAD: php
        jsr CHKSIG
        plp
        ldx HDDLY
        bne DXWAIT
        ldy #0
        rts
DXSTEP: php
        jsr CHKSIG
        plp
        ldx STPDLY
        bne DXWAIT
        ldy #0
        rts
DXWAIT: jmp DLYMS

CHKSIG: pha                 ; FIRST USE AFTER POWER-UP: SET DEFAULTS
        lda TSIG
        cmp #$5A
        bne @set
        lda TSIG+1
        cmp #$A5
        beq @ok
@set:   jsr TGOTEK
@ok:    pla
        rts

TGOTEK: lda #0              ; GOTEK / SD-CARD EMULATOR
        ldx #3
        bra TSET
TREAL:  lda #40             ; REAL 5.25" DRIVES (THE ORIGINAL VALUES)
        ldx #8
TSET:   sta HDDLY
        stx STPDLY
        lda #$5A
        sta TSIG
        lda #$A5
        sta TSIG+1
        rts

; DT          SHOW THE TIMING
; DT G        GOTEK TIMING (HEAD 0, STEP 3 MS)
; DT R        REAL-DRIVE TIMING (HEAD 40, STEP 8 MS)
; DT HH SS    HEAD AND STEP DELAYS IN MS (DECIMAL 0-255)
DTCMD:  jsr CHKSIG
        jsr ATEND
        beq DTSHOW
        jsr PEEKC
        jsr UCASE
        cmp #'G'
        bne @r
        jsr TGOTEK
        bra DTSHOW
@r:     cmp #'R'
        bne @n
        jsr TREAL
        bra DTSHOW
@n:     jsr GETDEC
        pha
        jsr GETDEC
        tax
        pla
        jsr TSET
DTSHOW: jsr PRINT
        .byte "HEAD ",0
        lda HDDLY
        ldy #0
        jsr PRDEC
        jsr PRINT
        .byte " STEP ",0
        lda STPDLY
        ldy #0
        jsr PRDEC
        jsr PRINT
        .byte " MS",$0D,$0A,0
        rts

GETDEC: jsr SKIPSP          ; 1-3 DECIMAL DIGITS -> A (0-255)
        stz TMP2
        ldx #0
@d:     jsr PEEKC
        sec
        sbc #'0'
        cmp #10
        bcs @e
        inc CMDPOS
        pha
        lda TMP2            ; TMP2 = TMP2*10 + DIGIT
        asl a
        bcs @bad
        sta TMP
        asl a
        bcs @bad
        asl a
        bcs @bad
        adc TMP
        bcs @bad
        sta TMP
        pla
        adc TMP
        bcs @bad2
        sta TMP2
        inx
        bra @d
@e:     txa
        beq @bad2
        lda TMP2
        rts
@bad:   pla
@bad2:  jmp SYNERR

;================================================================
; FORTH DIR! SAFETY CHECK. DIR! WRITES DIRBUF ($7900-$7AFF) TO
; TRACK 12. REFUSE IF IT DOESN'T LOOK LIKE A DIRECTORY (E.G. NO
; DIR@ SINCE POWER-UP): EVERY ENTRY MUST BE 14 X '#', OR A NAME OF
; PRINTABLE CHARACTERS WITH BCD TRACKS 00-39, START <= END.
;================================================================
FEMIT   = $A4DA             ; FORTH: PRINT A
FABORT  = $AC3C             ; FORTH: ABORT
FDIRW   = $AAF6             ; FORTH: REST OF DIR! (A=1)
DIRCHK: stx $2D             ; AS DIR! DOES
        stz MEMLO
        lda #$79
        sta MEMHI
@ent:   ldy #13
@h:     lda (MEMLO),y
        cmp #'#'
        bne @used
        dey
        bpl @h
        bra @nx             ; UNUSED ENTRY
@used:  ldy #13
@n:     lda (MEMLO),y
        cmp #$20
        bcc @bad
        cmp #$7F
        bcs @bad
        dey
        bpl @n
        ldy #14
        jsr TRKOK
        bcs @bad
        sta TMP
        iny
        jsr TRKOK
        bcs @bad
        cmp TMP
        bcc @bad
@nx:    clc
        lda MEMLO
        adc #16
        sta MEMLO
        bcc @ent
        inc MEMHI
        lda MEMHI
        cmp #$7B
        bne @ent
        lda #1
        jmp FDIRW
@bad:   ldy #0
@m:     lda DIRMSG,y
        beq @ab
        jsr FEMIT
        iny
        bra @m
@ab:    jmp FABORT
TRKOK:  lda (MEMLO),y       ; C=1 IF NOT A BCD TRACK 00-39
        cmp #$40
        bcs @r
        pha
        and #$0F
        cmp #$0A
        pla
@r:     rts
DIRMSG: .byte " DIR NOT LOADED",0

        .res $E000-*, $FF
