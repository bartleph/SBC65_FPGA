;************************************************************************
;* ROM.S - COMPLETE SOURCE FOR THE 32K EEPROM, $8000-$FFFF              *
;*                                                                      *
;*   $8000-$9FFF  I/O (not in the EEPROM, filled with $FF)              *
;*   $A000-$BFFF  FORTH-79                                              *
;*   $C000-$CFFF  disk PIA / ACIA (not in the EEPROM, filled with $FF)  *
;*   $D000-$DFFF  DOSX new commands       (DOSX.S, the original source) *
;*   $E000-$FFFF  OS-65D V3.3 ROM DOS                                   *
;*                                                                      *
;* The Forth and DOS parts are a disassembly of the current ROM images  *
;* (no original source for them was available). The labels and         *
;* comments come from tracing the code and from what we know of the    *
;* routines. Bytes that aren't reached as code are kept as .byte data,  *
;* so the file always rebuilds exactly the same 32K.                    *
;*                                                                      *
;* BUILD (cc65 tools):                                                  *
;*   ca65 ROM.S -o rom.o                                                *
;*   ld65 -C rom.cfg -o EEPROM_8000-FFFF.bin rom.o                      *
;* rom.cfg:                                                             *
;*   MEMORY { ROM: start=$8000, size=$8000, file=%O, fill=yes,          *
;*            fillval=$FF; }                                            *
;*   SEGMENTS { CODE: load=ROM, type=ro; }                              *
;* DOSX.S must be in the same folder.                                   *
;*                                                                      *
;* Notation: "a:$00xx" forces absolute addressing where the original    *
;* used it for a zero-page address. "NAME = LABEL + n" marks code that  *
;* jumps into the middle of an instruction (BIT-skip tricks).           *
;************************************************************************

        .setcpu "65C02"

; ---- RAM and I/O locations used by the DOS ----
ENTPL      = $10
ENTPH      = $11
ZTMP       = $E0
INBUF      = $E1
INBUFH     = $E2
PRPTR      = $E3
PRPTRH     = $E4
MAXTK      = $E5
WRTRY      = $F6
RDTRY      = $F7
RDTRY2     = $F8
SECCNT     = $F9
SECPGS     = $FA
SECNO      = $FB
SPSAV      = $FC
DTMP       = $FD
MEMLO      = $FE
MEMHI      = $FF
INMASK     = $2321
OUTMASK    = $2322
RNDSEED    = $2324
TYPAHD     = $2325
XSAV       = $235F
YSAV       = $2361
CHRSAV     = $2363
DEVOFS     = $2378
PAGEFLG    = $25B6
ESCCNT     = $25C0
DRIVE      = $265C
CURTRK     = $265D
DSECT      = $265E
DPAGE      = $265F
DMEML      = $2660
DMEMH      = $2661
TRKBIN     = $2662
NOERR9     = $28B4
ERRJMP     = $2A4E
ERRVEC     = $2A4F
DEFIO      = $2AC6
CMDPOS     = $2CE5
CMDLEN     = $2CED
SWPRET     = $2D20
SWPRL      = $2D21
SWPRH      = $2D22
CMDBUF     = $2E1E
DIRSEC     = $2E79
ZPSAVE     = $2F79
BASPTRL    = $305A
BASPTRH    = $305B
STKSAVE    = $3079
PAGELEN    = $31A9
PAGEGAP    = $31AA
LINECNT    = $31AB
DIRBUF1    = $3300
DIRBUF2    = $3400
PUMAP      = $3500
NAMBUF     = $3528
DIRWR      = $3536
NAMEND     = $3537
FOUND      = $3538
ENTL       = $3539
ENTH       = $353A
WSHDR      = $3A79
WSTRK      = $3A7D
WSSTART    = $3A7E
; ----------------------------------------------------------------------
; Build for the FPGA (FPGA48 = 1, the default) or for the real SBC
; (ca65 -D FPGA48=0 ROM.S ...).
;   SBC : RAM $0000-$7FFF, ACIA $8000, VIA $9000, Forth ROM $A000-$BFFF
;   FPGA: RAM $0000-$BFFF (48K), ACIA $C080, VIA $C090, bank latch $C0A0.
;         The Forth ROM is switched into $A000-$BFFF by FT (bank latch
;         bit 0 = 1) and out again by BYE, F10 or power-up.
; ----------------------------------------------------------------------
.ifndef FPGA48
FPGA48     = 1
.endif
.if FPGA48
ACIAS      = $C080
ACIAD      = $C081
BANKREG    = $C0A0
RAMTOP     = $BF                ; highest RAM page, found by the RAM test
.else
ACIAS      = $8000
ACIAD      = $8001
RAMTOP     = $7F
.endif
PIAA       = $C000
PIAB       = $C002
DACIAS     = $C010
DACIAD     = $C011
IP = $20
IPH = $21
WP = $22
WPH = $23

; ======================================================================
; $8000-$9FFF  I/O AREA (ACIA $8000, VIA $9000) - NOT IN THE EEPROM
; ======================================================================
        .org $8000
        .res $2000, $FF

        .org $A000

; ======================================================================
; FORTH-79 ROM  $A000-$BFFF  (direct threaded; IP=$20/21, W=$22/23,
; data stack in zero page indexed by X, return stack = 6502 stack)
; ======================================================================
FCOLD:
        jmp L_ACCA                        ; $A000  4C CA AC
        .byte $4C,$C7,$AC,$46,$4F,$52,$54,$48,$2D,$36,$35,$43,$30,$32,$00; $A003
NEXT:
        lda (IP)                          ; $A012  B2 20
        sta WP                            ; $A014  85 22
        inc IP                            ; $A016  E6 20
        bne L_A01C                        ; $A018  D0 02
        inc IPH                           ; $A01A  E6 21
L_A01C:
        lda (IP)                          ; $A01C  B2 20
        sta WPH                           ; $A01E  85 23
        inc IP                            ; $A020  E6 20
        bne L_A026                        ; $A022  D0 02
        inc IPH                           ; $A024  E6 21
L_A026:
        jmp (WP)                          ; $A026  6C 22 00
DOCOL:
        pla                               ; $A029  68
        sta WP                            ; $A02A  85 22
        pla                               ; $A02C  68
        sta WPH                           ; $A02D  85 23
        lda IPH                           ; $A02F  A5 21
        pha                               ; $A031  48
        lda IP                            ; $A032  A5 20
        pha                               ; $A034  48
        clc                               ; $A035  18
        lda WP                            ; $A036  A5 22
        adc #$01                          ; $A038  69 01
        sta IP                            ; $A03A  85 20
        lda WPH                           ; $A03C  A5 23
        adc #$00                          ; $A03E  69 00
        sta IPH                           ; $A040  85 21
        jmp NEXT                          ; $A042  4C 12 A0
DOCON:
        pla                               ; $A045  68
        sta WP                            ; $A046  85 22
        pla                               ; $A048  68
        sta WPH                           ; $A049  85 23
        ldy #$01                          ; $A04B  A0 01
        lda (WP),y                        ; $A04D  B1 22
        sta $24                           ; $A04F  85 24
        iny                               ; $A051  C8
        lda (WP),y                        ; $A052  B1 22
        tay                               ; $A054  A8
        lda $24                           ; $A055  A5 24
        dex                               ; $A057  CA
        dex                               ; $A058  CA
        sta $00,x                         ; $A059  95 00
        sty $01,x                         ; $A05B  94 01
        jmp NEXT                          ; $A05D  4C 12 A0
DOVAR:
        pla                               ; $A060  68
        sta WP                            ; $A061  85 22
        pla                               ; $A063  68
        sta WPH                           ; $A064  85 23
        clc                               ; $A066  18
        lda WP                            ; $A067  A5 22
        adc #$01                          ; $A069  69 01
        pha                               ; $A06B  48
        lda WPH                           ; $A06C  A5 23
        adc #$00                          ; $A06E  69 00
        tay                               ; $A070  A8
        pla                               ; $A071  68
        dex                               ; $A072  CA
        dex                               ; $A073  CA
        sta $00,x                         ; $A074  95 00
        sty $01,x                         ; $A076  94 01
        jmp NEXT                          ; $A078  4C 12 A0
L_A07B:
        lda (IP)                          ; $A07B  B2 20
        sta $24                           ; $A07D  85 24
        inc IP                            ; $A07F  E6 20
        bne L_A085                        ; $A081  D0 02
        inc IPH                           ; $A083  E6 21
L_A085:
        lda (IP)                          ; $A085  B2 20
        sta IPH                           ; $A087  85 21
        lda $24                           ; $A089  A5 24
        sta IP                            ; $A08B  85 20
        jmp NEXT                          ; $A08D  4C 12 A0
L_A090:
        inc IP                            ; $A090  E6 20
        bne L_A096                        ; $A092  D0 02
        inc IPH                           ; $A094  E6 21
L_A096:
        inc IP                            ; $A096  E6 20
        bne L_A09C                        ; $A098  D0 02
        inc IPH                           ; $A09A  E6 21
L_A09C:
        jmp NEXT                          ; $A09C  4C 12 A0
N_EXIT:
        .word $0000                       ; $A09F
        .byte $04
        .byte "EXIT"
W_EXIT:
        pla                               ; $A0A6  68
        sta IP                            ; $A0A7  85 20
        pla                               ; $A0A9  68
        sta IPH                           ; $A0AA  85 21
        jmp NEXT                          ; $A0AC  4C 12 A0
N_EXECUTE:
        .word N_EXIT                      ; $A0AF
        .byte $07
        .byte "EXECUTE"
W_EXECUTE:
        lda $00,x                         ; $A0B9  B5 00
        sta WP                            ; $A0BB  85 22
        lda $01,x                         ; $A0BD  B5 01
        sta WPH                           ; $A0BF  85 23
        inx                               ; $A0C1  E8
        inx                               ; $A0C2  E8
        jmp (WP)                          ; $A0C3  6C 22 00
N_LIT:
        .word N_EXECUTE                   ; $A0C6
        .byte $03
        .byte "LIT"
W_LIT:
        lda (IP)                          ; $A0CC  B2 20
        sta $24                           ; $A0CE  85 24
        inc IP                            ; $A0D0  E6 20
        bne L_A0D6                        ; $A0D2  D0 02
        inc IPH                           ; $A0D4  E6 21
L_A0D6:
        lda (IP)                          ; $A0D6  B2 20
        tay                               ; $A0D8  A8
        inc IP                            ; $A0D9  E6 20
        bne L_A0DF                        ; $A0DB  D0 02
        inc IPH                           ; $A0DD  E6 21
L_A0DF:
        lda $24                           ; $A0DF  A5 24
        dex                               ; $A0E1  CA
        dex                               ; $A0E2  CA
        sta $00,x                         ; $A0E3  95 00
        sty $01,x                         ; $A0E5  94 01
        jmp NEXT                          ; $A0E7  4C 12 A0
N_BRANCH:
        .word N_LIT                       ; $A0EA
        .byte $06
        .byte "BRANCH"
W_BRANCH:
        jmp L_A07B                        ; $A0F3  4C 7B A0
N_0BRANCH:
        .word N_BRANCH                    ; $A0F6
        .byte $07
        .byte "0BRANCH"
W_0BRANCH:
        lda $00,x                         ; $A100  B5 00
        ora $01,x                         ; $A102  15 01
        php                               ; $A104  08
        inx                               ; $A105  E8
        inx                               ; $A106  E8
        plp                               ; $A107  28
        beq L_A10D                        ; $A108  F0 03
        jmp L_A090                        ; $A10A  4C 90 A0
L_A10D:
        jmp L_A07B                        ; $A10D  4C 7B A0
N_LPDORP:
        .word N_0BRANCH                   ; $A110
        .byte $04
        .byte "(DO)"
W_LPDORP:
        lda $03,x                         ; $A117  B5 03
        pha                               ; $A119  48
        lda $02,x                         ; $A11A  B5 02
        pha                               ; $A11C  48
        lda $01,x                         ; $A11D  B5 01
        pha                               ; $A11F  48
        lda $00,x                         ; $A120  B5 00
        pha                               ; $A122  48
        inx                               ; $A123  E8
        inx                               ; $A124  E8
        inx                               ; $A125  E8
        inx                               ; $A126  E8
        jmp NEXT                          ; $A127  4C 12 A0
N_LPLOOPRP:
        .word N_LPDORP                    ; $A12A
        .byte $06
        .byte "(LOOP)"
W_LPLOOPRP:
        lda #$01                          ; $A133  A9 01
        sta $24                           ; $A135  85 24
        stz $25                           ; $A137  64 25
        bra L_A14F                        ; $A139  80 14
N_LPPLUSLOOPRP:
        .word N_LPLOOPRP                  ; $A13B
        .byte $07
        .byte "(+LOOP)"
W_LPPLUSLOOPRP:
        lda $00,x                         ; $A145  B5 00
        sta $24                           ; $A147  85 24
        lda $01,x                         ; $A149  B5 01
        sta $25                           ; $A14B  85 25
        inx                               ; $A14D  E8
        inx                               ; $A14E  E8
L_A14F:
        stx $2D                           ; $A14F  86 2D
        tsx                               ; $A151  BA
        sec                               ; $A152  38
        lda $0101,x                       ; $A153  BD 01 01
        sbc $0103,x                       ; $A156  FD 03 01
        sta $26                           ; $A159  85 26
        lda $0102,x                       ; $A15B  BD 02 01
        sbc $0104,x                       ; $A15E  FD 04 01
        sta $27                           ; $A161  85 27
        clc                               ; $A163  18
        lda $26                           ; $A164  A5 26
        adc $24                           ; $A166  65 24
        sta $28                           ; $A168  85 28
        lda $27                           ; $A16A  A5 27
        adc $25                           ; $A16C  65 25
        sta $29                           ; $A16E  85 29
        clc                               ; $A170  18
        lda $0101,x                       ; $A171  BD 01 01
        adc $24                           ; $A174  65 24
        sta $0101,x                       ; $A176  9D 01 01
        lda $0102,x                       ; $A179  BD 02 01
        adc $25                           ; $A17C  65 25
        sta $0102,x                       ; $A17E  9D 02 01
        ldx $2D                           ; $A181  A6 2D
        lda $27                           ; $A183  A5 27
        eor $29                           ; $A185  45 29
        bmi L_A18C                        ; $A187  30 03
        jmp L_A07B                        ; $A189  4C 7B A0
L_A18C:
        pla                               ; $A18C  68
        pla                               ; $A18D  68
        pla                               ; $A18E  68
        pla                               ; $A18F  68
        jmp L_A090                        ; $A190  4C 90 A0
N_I:
        .word N_LPPLUSLOOPRP              ; $A193
        .byte $01
        .byte "I"
W_I:
        stx $2D                           ; $A197  86 2D
        tsx                               ; $A199  BA
        lda $0101,x                       ; $A19A  BD 01 01
        ldy $0102,x                       ; $A19D  BC 02 01
        ldx $2D                           ; $A1A0  A6 2D
        dex                               ; $A1A2  CA
        dex                               ; $A1A3  CA
        sta $00,x                         ; $A1A4  95 00
        sty $01,x                         ; $A1A6  94 01
        jmp NEXT                          ; $A1A8  4C 12 A0
N_RFETCH:
        .word N_I                         ; $A1AB
        .byte $02
        .byte "R@"
W_RFETCH:
        jmp W_I                           ; $A1B0  4C 97 A1
N_J:
        .word N_RFETCH                    ; $A1B3
        .byte $01
        .byte "J"
W_J:
        stx $2D                           ; $A1B7  86 2D
        tsx                               ; $A1B9  BA
        lda $0105,x                       ; $A1BA  BD 05 01
        ldy $0106,x                       ; $A1BD  BC 06 01
        ldx $2D                           ; $A1C0  A6 2D
        dex                               ; $A1C2  CA
        dex                               ; $A1C3  CA
        sta $00,x                         ; $A1C4  95 00
        sty $01,x                         ; $A1C6  94 01
        jmp NEXT                          ; $A1C8  4C 12 A0
N_LEAVE:
        .word N_J                         ; $A1CB
        .byte $05
        .byte "LEAVE"
W_LEAVE:
        stx $2D                           ; $A1D3  86 2D
        tsx                               ; $A1D5  BA
        clc                               ; $A1D6  18
        lda $0101,x                       ; $A1D7  BD 01 01
        adc #$01                          ; $A1DA  69 01
        sta $0103,x                       ; $A1DC  9D 03 01
        lda $0102,x                       ; $A1DF  BD 02 01
        adc #$00                          ; $A1E2  69 00
        sta $0104,x                       ; $A1E4  9D 04 01
        ldx $2D                           ; $A1E7  A6 2D
        jmp NEXT                          ; $A1E9  4C 12 A0
N_GTR:
        .word N_LEAVE                     ; $A1EC
        .byte $02
        .byte ">R"
W_GTR:
        lda $01,x                         ; $A1F1  B5 01
        pha                               ; $A1F3  48
        lda $00,x                         ; $A1F4  B5 00
        pha                               ; $A1F6  48
        inx                               ; $A1F7  E8
        inx                               ; $A1F8  E8
        jmp NEXT                          ; $A1F9  4C 12 A0
N_RGT:
        .word N_GTR                       ; $A1FC
        .byte $02
        .byte "R>"
W_RGT:
        pla                               ; $A201  68
        sta $24                           ; $A202  85 24
        pla                               ; $A204  68
        tay                               ; $A205  A8
        lda $24                           ; $A206  A5 24
        dex                               ; $A208  CA
        dex                               ; $A209  CA
        sta $00,x                         ; $A20A  95 00
        sty $01,x                         ; $A20C  94 01
        jmp NEXT                          ; $A20E  4C 12 A0
N_DROP:
        .word N_RGT                       ; $A211
        .byte $04
        .byte "DROP"
W_DROP:
        inx                               ; $A218  E8
        inx                               ; $A219  E8
        jmp NEXT                          ; $A21A  4C 12 A0
N_DUP:
        .word N_DROP                      ; $A21D
        .byte $03
        .byte "DUP"
W_DUP:
        lda $00,x                         ; $A223  B5 00
        ldy $01,x                         ; $A225  B4 01
        dex                               ; $A227  CA
        dex                               ; $A228  CA
        sta $00,x                         ; $A229  95 00
        sty $01,x                         ; $A22B  94 01
        jmp NEXT                          ; $A22D  4C 12 A0
N_OVER:
        .word N_DUP                       ; $A230
        .byte $04
        .byte "OVER"
W_OVER:
        lda $02,x                         ; $A237  B5 02
        ldy $03,x                         ; $A239  B4 03
        dex                               ; $A23B  CA
        dex                               ; $A23C  CA
        sta $00,x                         ; $A23D  95 00
        sty $01,x                         ; $A23F  94 01
        jmp NEXT                          ; $A241  4C 12 A0
N_SWAP:
        .word N_OVER                      ; $A244
        .byte $04
        .byte "SWAP"
W_SWAP:
        lda $00,x                         ; $A24B  B5 00
        ldy $02,x                         ; $A24D  B4 02
        sta $02,x                         ; $A24F  95 02
        sty $00,x                         ; $A251  94 00
        lda $01,x                         ; $A253  B5 01
        ldy $03,x                         ; $A255  B4 03
        sta $03,x                         ; $A257  95 03
        sty $01,x                         ; $A259  94 01
        jmp NEXT                          ; $A25B  4C 12 A0
N_ROT:
        .word N_SWAP                      ; $A25E
        .byte $03
        .byte "ROT"
W_ROT:
        lda $04,x                         ; $A264  B5 04
        sta $24                           ; $A266  85 24
        lda $05,x                         ; $A268  B5 05
        sta $25                           ; $A26A  85 25
        lda $02,x                         ; $A26C  B5 02
        sta $04,x                         ; $A26E  95 04
        lda $03,x                         ; $A270  B5 03
        sta $05,x                         ; $A272  95 05
        lda $00,x                         ; $A274  B5 00
        sta $02,x                         ; $A276  95 02
        lda $01,x                         ; $A278  B5 01
        sta $03,x                         ; $A27A  95 03
        lda $24                           ; $A27C  A5 24
        sta $00,x                         ; $A27E  95 00
        lda $25                           ; $A280  A5 25
        sta $01,x                         ; $A282  95 01
        jmp NEXT                          ; $A284  4C 12 A0
N_PLUS:
        .word N_ROT                       ; $A287
        .byte $01
        .byte "+"
W_PLUS:
        clc                               ; $A28B  18
        lda $00,x                         ; $A28C  B5 00
        adc $02,x                         ; $A28E  75 02
        sta $02,x                         ; $A290  95 02
        lda $01,x                         ; $A292  B5 01
        adc $03,x                         ; $A294  75 03
        sta $03,x                         ; $A296  95 03
        inx                               ; $A298  E8
        inx                               ; $A299  E8
        jmp NEXT                          ; $A29A  4C 12 A0
N_MINUS:
        .word N_PLUS                      ; $A29D
        .byte $01
        .byte "-"
W_MINUS:
        sec                               ; $A2A1  38
        lda $02,x                         ; $A2A2  B5 02
        sbc $00,x                         ; $A2A4  F5 00
        sta $02,x                         ; $A2A6  95 02
        lda $03,x                         ; $A2A8  B5 03
        sbc $01,x                         ; $A2AA  F5 01
        sta $03,x                         ; $A2AC  95 03
        inx                               ; $A2AE  E8
        inx                               ; $A2AF  E8
        jmp NEXT                          ; $A2B0  4C 12 A0
N_AND:
        .word N_MINUS                     ; $A2B3
        .byte $03
        .byte "AND"
W_AND:
        lda $00,x                         ; $A2B9  B5 00
        and $02,x                         ; $A2BB  35 02
        sta $02,x                         ; $A2BD  95 02
        lda $01,x                         ; $A2BF  B5 01
        and $03,x                         ; $A2C1  35 03
        sta $03,x                         ; $A2C3  95 03
        inx                               ; $A2C5  E8
        inx                               ; $A2C6  E8
        jmp NEXT                          ; $A2C7  4C 12 A0
N_OR:
        .word N_AND                       ; $A2CA
        .byte $02
        .byte "OR"
W_OR:
        lda $00,x                         ; $A2CF  B5 00
        ora $02,x                         ; $A2D1  15 02
        sta $02,x                         ; $A2D3  95 02
        lda $01,x                         ; $A2D5  B5 01
        ora $03,x                         ; $A2D7  15 03
        sta $03,x                         ; $A2D9  95 03
        inx                               ; $A2DB  E8
        inx                               ; $A2DC  E8
        jmp NEXT                          ; $A2DD  4C 12 A0
N_XOR:
        .word N_OR                        ; $A2E0
        .byte $03
        .byte "XOR"
W_XOR:
        lda $00,x                         ; $A2E6  B5 00
        eor $02,x                         ; $A2E8  55 02
        sta $02,x                         ; $A2EA  95 02
        lda $01,x                         ; $A2EC  B5 01
        eor $03,x                         ; $A2EE  55 03
        sta $03,x                         ; $A2F0  95 03
        inx                               ; $A2F2  E8
        inx                               ; $A2F3  E8
        jmp NEXT                          ; $A2F4  4C 12 A0
N_0EQ:
        .word N_XOR                       ; $A2F7
        .byte $02
        .byte "0="
W_0EQ:
        lda $00,x                         ; $A2FC  B5 00
        ora $01,x                         ; $A2FE  15 01
        beq L_A306                        ; $A300  F0 04
        lda #$00                          ; $A302  A9 00
        bra L_A308                        ; $A304  80 02
L_A306:
        lda #$FF                          ; $A306  A9 FF
L_A308:
        sta $00,x                         ; $A308  95 00
        sta $01,x                         ; $A30A  95 01
        jmp NEXT                          ; $A30C  4C 12 A0
N_0LT:
        .word N_0EQ                       ; $A30F
        .byte $02
        .byte "0<"
W_0LT:
        lda $01,x                         ; $A314  B5 01
        asl a                             ; $A316  0A
        lda #$00                          ; $A317  A9 00
        bcc L_A31D                        ; $A319  90 02
        lda #$FF                          ; $A31B  A9 FF
L_A31D:
        sta $00,x                         ; $A31D  95 00
        sta $01,x                         ; $A31F  95 01
        jmp NEXT                          ; $A321  4C 12 A0
N_LT:
        .word N_0LT                       ; $A324
        .byte $01
        .byte "<"
W_LT:
        sec                               ; $A328  38
        lda $02,x                         ; $A329  B5 02
        sbc $00,x                         ; $A32B  F5 00
        lda $03,x                         ; $A32D  B5 03
        sbc $01,x                         ; $A32F  F5 01
        bvc L_A335                        ; $A331  50 02
        eor #$80                          ; $A333  49 80
L_A335:
        inx                               ; $A335  E8
        inx                               ; $A336  E8
        asl a                             ; $A337  0A
        lda #$00                          ; $A338  A9 00
        bcc L_A33E                        ; $A33A  90 02
        lda #$FF                          ; $A33C  A9 FF
L_A33E:
        sta $00,x                         ; $A33E  95 00
        sta $01,x                         ; $A340  95 01
        jmp NEXT                          ; $A342  4C 12 A0
N_ULT:
        .word N_LT                        ; $A345
        .byte $02
        .byte "U<"
W_ULT:
        sec                               ; $A34A  38
        lda $02,x                         ; $A34B  B5 02
        sbc $00,x                         ; $A34D  F5 00
        lda $03,x                         ; $A34F  B5 03
        sbc $01,x                         ; $A351  F5 01
        inx                               ; $A353  E8
        inx                               ; $A354  E8
        lda #$00                          ; $A355  A9 00
        bcs L_A35B                        ; $A357  B0 02
        lda #$FF                          ; $A359  A9 FF
L_A35B:
        sta $00,x                         ; $A35B  95 00
        sta $01,x                         ; $A35D  95 01
        jmp NEXT                          ; $A35F  4C 12 A0
N_2STAR:
        .word N_ULT                       ; $A362
        .byte $02
        .byte "2*"
W_2STAR:
        asl $00,x                         ; $A367  16 00
        rol $01,x                         ; $A369  36 01
        jmp NEXT                          ; $A36B  4C 12 A0
N_2SLASH:
        .word N_2STAR                     ; $A36E
        .byte $02
        .byte "2/"
W_2SLASH:
        lda $01,x                         ; $A373  B5 01
        cmp #$80                          ; $A375  C9 80
        ror $01,x                         ; $A377  76 01
        ror $00,x                         ; $A379  76 00
        jmp NEXT                          ; $A37B  4C 12 A0
N_1PLUS:
        .word N_2SLASH                    ; $A37E
        .byte $02
        .byte "1+"
W_1PLUS:
        inc $00,x                         ; $A383  F6 00
        bne L_A389                        ; $A385  D0 02
        inc $01,x                         ; $A387  F6 01
L_A389:
        jmp NEXT                          ; $A389  4C 12 A0
N_FETCH:
        .word N_1PLUS                     ; $A38C
        .byte $01
        .byte "@"
W_FETCH:
        lda $00,x                         ; $A390  B5 00
        sta $24                           ; $A392  85 24
        lda $01,x                         ; $A394  B5 01
        sta $25                           ; $A396  85 25
        ldy #$01                          ; $A398  A0 01
        lda ($24),y                       ; $A39A  B1 24
        sta $01,x                         ; $A39C  95 01
        lda ($24)                         ; $A39E  B2 24
        sta $00,x                         ; $A3A0  95 00
        jmp NEXT                          ; $A3A2  4C 12 A0
N_STORE:
        .word N_FETCH                     ; $A3A5
        .byte $01
        .byte "!"
W_STORE:
        lda $00,x                         ; $A3A9  B5 00
        sta $24                           ; $A3AB  85 24
        lda $01,x                         ; $A3AD  B5 01
        sta $25                           ; $A3AF  85 25
        lda $02,x                         ; $A3B1  B5 02
        sta ($24)                         ; $A3B3  92 24
        ldy #$01                          ; $A3B5  A0 01
        lda $03,x                         ; $A3B7  B5 03
        sta ($24),y                       ; $A3B9  91 24
        inx                               ; $A3BB  E8
        inx                               ; $A3BC  E8
        inx                               ; $A3BD  E8
        inx                               ; $A3BE  E8
        jmp NEXT                          ; $A3BF  4C 12 A0
N_CFETCH:
        .word N_STORE                     ; $A3C2
        .byte $02
        .byte "C@"
W_CFETCH:
        lda $00,x                         ; $A3C7  B5 00
        sta $24                           ; $A3C9  85 24
        lda $01,x                         ; $A3CB  B5 01
        sta $25                           ; $A3CD  85 25
        lda ($24)                         ; $A3CF  B2 24
        sta $00,x                         ; $A3D1  95 00
        stz $01,x                         ; $A3D3  74 01
        jmp NEXT                          ; $A3D5  4C 12 A0
N_CSTORE:
        .word N_CFETCH                    ; $A3D8
        .byte $02
        .byte "C!"
W_CSTORE:
        lda $00,x                         ; $A3DD  B5 00
        sta $24                           ; $A3DF  85 24
        lda $01,x                         ; $A3E1  B5 01
        sta $25                           ; $A3E3  85 25
        lda $02,x                         ; $A3E5  B5 02
        sta ($24)                         ; $A3E7  92 24
        inx                               ; $A3E9  E8
        inx                               ; $A3EA  E8
        inx                               ; $A3EB  E8
        inx                               ; $A3EC  E8
        jmp NEXT                          ; $A3ED  4C 12 A0
N_UMSTAR:
        .word N_CSTORE                    ; $A3F0
        .byte $03
        .byte "UM*"
W_UMSTAR:
        stz $26                           ; $A3F6  64 26
        stz $27                           ; $A3F8  64 27
        stz $28                           ; $A3FA  64 28
        stz $29                           ; $A3FC  64 29
        lda $02,x                         ; $A3FE  B5 02
        sta $2A                           ; $A400  85 2A
        lda $03,x                         ; $A402  B5 03
        sta $2B                           ; $A404  85 2B
        ldy #$10                          ; $A406  A0 10
L_A408:
        asl $26                           ; $A408  06 26
        rol $27                           ; $A40A  26 27
        rol $28                           ; $A40C  26 28
        rol $29                           ; $A40E  26 29
        asl $2A                           ; $A410  06 2A
        rol $2B                           ; $A412  26 2B
        bcc L_A42F                        ; $A414  90 19
        clc                               ; $A416  18
        lda $26                           ; $A417  A5 26
        adc $00,x                         ; $A419  75 00
        sta $26                           ; $A41B  85 26
        lda $27                           ; $A41D  A5 27
        adc $01,x                         ; $A41F  75 01
        sta $27                           ; $A421  85 27
        lda $28                           ; $A423  A5 28
        adc #$00                          ; $A425  69 00
        sta $28                           ; $A427  85 28
        lda $29                           ; $A429  A5 29
        adc #$00                          ; $A42B  69 00
        sta $29                           ; $A42D  85 29
L_A42F:
        dey                               ; $A42F  88
        bne L_A408                        ; $A430  D0 D6
        lda $26                           ; $A432  A5 26
        sta $02,x                         ; $A434  95 02
        lda $27                           ; $A436  A5 27
        sta $03,x                         ; $A438  95 03
        lda $28                           ; $A43A  A5 28
        sta $00,x                         ; $A43C  95 00
        lda $29                           ; $A43E  A5 29
        sta $01,x                         ; $A440  95 01
        jmp NEXT                          ; $A442  4C 12 A0
N_UMSLASHMOD:
        .word N_UMSTAR                    ; $A445
        .byte $06
        .byte "UM/MOD"
W_UMSLASHMOD:
        ldy #$10                          ; $A44E  A0 10
L_A450:
        asl $04,x                         ; $A450  16 04
        rol $05,x                         ; $A452  36 05
        rol $02,x                         ; $A454  36 02
        rol $03,x                         ; $A456  36 03
        lda #$00                          ; $A458  A9 00
        rol a                             ; $A45A  2A
        sta $26                           ; $A45B  85 26
        sec                               ; $A45D  38
        lda $02,x                         ; $A45E  B5 02
        sbc $00,x                         ; $A460  F5 00
        sta $24                           ; $A462  85 24
        lda $03,x                         ; $A464  B5 03
        sbc $01,x                         ; $A466  F5 01
        sta $25                           ; $A468  85 25
        bcs L_A470                        ; $A46A  B0 04
        lda $26                           ; $A46C  A5 26
        beq L_A47A                        ; $A46E  F0 0A
L_A470:
        lda $24                           ; $A470  A5 24
        sta $02,x                         ; $A472  95 02
        lda $25                           ; $A474  A5 25
        sta $03,x                         ; $A476  95 03
        inc $04,x                         ; $A478  F6 04
L_A47A:
        dey                               ; $A47A  88
        bne L_A450                        ; $A47B  D0 D3
        inx                               ; $A47D  E8
        inx                               ; $A47E  E8
        lda $00,x                         ; $A47F  B5 00
        ldy $02,x                         ; $A481  B4 02
        sta $02,x                         ; $A483  95 02
        sty $00,x                         ; $A485  94 00
        lda $01,x                         ; $A487  B5 01
        ldy $03,x                         ; $A489  B4 03
        sta $03,x                         ; $A48B  95 03
        sty $01,x                         ; $A48D  94 01
        jmp NEXT                          ; $A48F  4C 12 A0
N_CMOVE:
        .word N_UMSLASHMOD                ; $A492
        .byte $05
        .byte "CMOVE"
W_CMOVE:
        lda $04,x                         ; $A49A  B5 04
        sta $24                           ; $A49C  85 24
        lda $05,x                         ; $A49E  B5 05
        sta $25                           ; $A4A0  85 25
        lda $02,x                         ; $A4A2  B5 02
        sta $26                           ; $A4A4  85 26
        lda $03,x                         ; $A4A6  B5 03
        sta $27                           ; $A4A8  85 27
        lda $00,x                         ; $A4AA  B5 00
        sta $28                           ; $A4AC  85 28
        lda $01,x                         ; $A4AE  B5 01
        sta $29                           ; $A4B0  85 29
        txa                               ; $A4B2  8A
        clc                               ; $A4B3  18
        adc #$06                          ; $A4B4  69 06
        tax                               ; $A4B6  AA
L_A4B7:
        lda $28                           ; $A4B7  A5 28
        ora $29                           ; $A4B9  05 29
        beq L_A4D7                        ; $A4BB  F0 1A
        lda ($24)                         ; $A4BD  B2 24
        sta ($26)                         ; $A4BF  92 26
        inc $24                           ; $A4C1  E6 24
        bne L_A4C7                        ; $A4C3  D0 02
        inc $25                           ; $A4C5  E6 25
L_A4C7:
        inc $26                           ; $A4C7  E6 26
        bne L_A4CD                        ; $A4C9  D0 02
        inc $27                           ; $A4CB  E6 27
L_A4CD:
        lda $28                           ; $A4CD  A5 28
        bne L_A4D3                        ; $A4CF  D0 02
        dec $29                           ; $A4D1  C6 29
L_A4D3:
        dec $28                           ; $A4D3  C6 28
        bra L_A4B7                        ; $A4D5  80 E0
L_A4D7:
        jmp NEXT                          ; $A4D7  4C 12 A0
L_A4DA:
        pha                               ; $A4DA  48
L_A4DB:
        lda ACIAS                         ; $A4DB  AD 00 80
        and #$02                          ; $A4DE  29 02
        beq L_A4DB                        ; $A4E0  F0 F9
        pla                               ; $A4E2  68
        sta ACIAD                         ; $A4E3  8D 01 80
        rts                               ; $A4E6  60
L_A4E7:
        lda ACIAS                         ; $A4E7  AD 00 80
        lsr a                             ; $A4EA  4A
        bcc L_A4E7                        ; $A4EB  90 FA
        lda ACIAD                         ; $A4ED  AD 01 80
        rts                               ; $A4F0  60
N_EMIT:
        .word N_CMOVE                     ; $A4F1
        .byte $04
        .byte "EMIT"
W_EMIT:
        lda $00,x                         ; $A4F8  B5 00
        inx                               ; $A4FA  E8
        inx                               ; $A4FB  E8
        jsr L_A4DA                        ; $A4FC  20 DA A4
        jmp NEXT                          ; $A4FF  4C 12 A0
N_KEY:
        .word N_EMIT                      ; $A502
        .byte $03
        .byte "KEY"
W_KEY:
        jsr L_A4E7                        ; $A508  20 E7 A4
        and #$7F                          ; $A50B  29 7F
        ldy #$00                          ; $A50D  A0 00
        dex                               ; $A50F  CA
        dex                               ; $A510  CA
        sta $00,x                         ; $A511  95 00
        sty $01,x                         ; $A513  94 01
        jmp NEXT                          ; $A515  4C 12 A0
N_CR:
        .word N_KEY                       ; $A518
        .byte $02
        .byte "CR"
W_CR:
        lda #$0D                          ; $A51D  A9 0D
        jsr L_A4DA                        ; $A51F  20 DA A4
        lda #$0A                          ; $A522  A9 0A
        jsr L_A4DA                        ; $A524  20 DA A4
        jmp NEXT                          ; $A527  4C 12 A0
N_TYPE:
        .word N_CR                        ; $A52A
        .byte $04
        .byte "TYPE"
W_TYPE:
        lda $02,x                         ; $A531  B5 02
        sta $24                           ; $A533  85 24
        lda $03,x                         ; $A535  B5 03
        sta $25                           ; $A537  85 25
        lda $00,x                         ; $A539  B5 00
        sta $26                           ; $A53B  85 26
        lda $01,x                         ; $A53D  B5 01
        sta $27                           ; $A53F  85 27
        inx                               ; $A541  E8
        inx                               ; $A542  E8
        inx                               ; $A543  E8
        inx                               ; $A544  E8
L_A545:
        lda $26                           ; $A545  A5 26
        ora $27                           ; $A547  05 27
        beq L_A560                        ; $A549  F0 15
        lda ($24)                         ; $A54B  B2 24
        jsr L_A4DA                        ; $A54D  20 DA A4
        inc $24                           ; $A550  E6 24
        bne L_A556                        ; $A552  D0 02
        inc $25                           ; $A554  E6 25
L_A556:
        lda $26                           ; $A556  A5 26
        bne L_A55C                        ; $A558  D0 02
        dec $27                           ; $A55A  C6 27
L_A55C:
        dec $26                           ; $A55C  C6 26
        bra L_A545                        ; $A55E  80 E5
L_A560:
        jmp NEXT                          ; $A560  4C 12 A0
N_COUNT:
        .word N_TYPE                      ; $A563
        .byte $05
        .byte "COUNT"
W_COUNT:
        lda $00,x                         ; $A56B  B5 00
        sta $24                           ; $A56D  85 24
        lda $01,x                         ; $A56F  B5 01
        sta $25                           ; $A571  85 25
        lda ($24)                         ; $A573  B2 24
        inc $00,x                         ; $A575  F6 00
        bne L_A57B                        ; $A577  D0 02
        inc $01,x                         ; $A579  F6 01
L_A57B:
        ldy #$00                          ; $A57B  A0 00
        dex                               ; $A57D  CA
        dex                               ; $A57E  CA
        sta $00,x                         ; $A57F  95 00
        sty $01,x                         ; $A581  94 01
        jmp NEXT                          ; $A583  4C 12 A0
N_QUERY:
        .word N_COUNT                     ; $A586
        .byte $05
        .byte "QUERY"
W_QUERY:
        ldy #$00                          ; $A58E  A0 00
L_A590:
        jsr L_A4E7                        ; $A590  20 E7 A4
        and #$7F                          ; $A593  29 7F
        cmp #$0D                          ; $A595  C9 0D
        beq L_A5CC                        ; $A597  F0 33
        cmp #$0A                          ; $A599  C9 0A
        beq L_A590                        ; $A59B  F0 F3
        cmp #$08                          ; $A59D  C9 08
        beq L_A5B6                        ; $A59F  F0 15
        cmp #$7F                          ; $A5A1  C9 7F
        beq L_A5B6                        ; $A5A3  F0 11
        cmp #$20                          ; $A5A5  C9 20
        bcc L_A590                        ; $A5A7  90 E7
        cpy #$78                          ; $A5A9  C0 78
        bcs L_A590                        ; $A5AB  B0 E3
        sta $7800,y                       ; $A5AD  99 00 78
        iny                               ; $A5B0  C8
        jsr L_A4DA                        ; $A5B1  20 DA A4
        bra L_A590                        ; $A5B4  80 DA
L_A5B6:
        cpy #$00                          ; $A5B6  C0 00
        beq L_A590                        ; $A5B8  F0 D6
        dey                               ; $A5BA  88
        lda #$08                          ; $A5BB  A9 08
        jsr L_A4DA                        ; $A5BD  20 DA A4
        lda #$20                          ; $A5C0  A9 20
        jsr L_A4DA                        ; $A5C2  20 DA A4
        lda #$08                          ; $A5C5  A9 08
        jsr L_A4DA                        ; $A5C7  20 DA A4
        bra L_A590                        ; $A5CA  80 C4
L_A5CC:
        lda #$0D                          ; $A5CC  A9 0D
        jsr L_A4DA                        ; $A5CE  20 DA A4
        lda #$0A                          ; $A5D1  A9 0A
        jsr L_A4DA                        ; $A5D3  20 DA A4
        sty $7E0C                         ; $A5D6  8C 0C 7E
        stz $7E0D                         ; $A5D9  9C 0D 7E
        lda #$00                          ; $A5DC  A9 00
        sta $7E0A                         ; $A5DE  8D 0A 7E
        lda #$78                          ; $A5E1  A9 78
        sta $7E0B                         ; $A5E3  8D 0B 7E
        stz $7E08                         ; $A5E6  9C 08 7E
        stz $7E09                         ; $A5E9  9C 09 7E
        jmp NEXT                          ; $A5EC  4C 12 A0
L_A5EF:
        lda ($26)                         ; $A5EF  B2 26
        ldy $24                           ; $A5F1  A4 24
        cpy #$20                          ; $A5F3  C0 20
        bne L_A5FD                        ; $A5F5  D0 06
        cmp #$21                          ; $A5F7  C9 21
        bcc L_A603                        ; $A5F9  90 08
L_A5FB:
        clc                               ; $A5FB  18
        rts                               ; $A5FC  60
L_A5FD:
        cmp $24                           ; $A5FD  C5 24
        beq L_A603                        ; $A5FF  F0 02
        bra L_A5FB                        ; $A601  80 F8
L_A603:
        sec                               ; $A603  38
        rts                               ; $A604  60
L_A605:
        inc $26                           ; $A605  E6 26
        bne L_A60B                        ; $A607  D0 02
        inc $27                           ; $A609  E6 27
L_A60B:
        lda $28                           ; $A60B  A5 28
        bne L_A611                        ; $A60D  D0 02
        dec $29                           ; $A60F  C6 29
L_A611:
        dec $28                           ; $A611  C6 28
        inc $7E08                         ; $A613  EE 08 7E
        bne L_A61B                        ; $A616  D0 03
        inc $7E09                         ; $A618  EE 09 7E
L_A61B:
        rts                               ; $A61B  60
N_WORD:
        .word N_QUERY                     ; $A61C
        .byte $04
        .byte "WORD"
W_WORD:
        lda $00,x                         ; $A623  B5 00
        sta $24                           ; $A625  85 24
        clc                               ; $A627  18
        lda $7E0A                         ; $A628  AD 0A 7E
        adc $7E08                         ; $A62B  6D 08 7E
        sta $26                           ; $A62E  85 26
        lda $7E0B                         ; $A630  AD 0B 7E
        adc $7E09                         ; $A633  6D 09 7E
        sta $27                           ; $A636  85 27
        sec                               ; $A638  38
        lda $7E0C                         ; $A639  AD 0C 7E
        sbc $7E08                         ; $A63C  ED 08 7E
        sta $28                           ; $A63F  85 28
        lda $7E0D                         ; $A641  AD 0D 7E
        sbc $7E09                         ; $A644  ED 09 7E
        sta $29                           ; $A647  85 29
        bcs L_A64F                        ; $A649  B0 04
        stz $28                           ; $A64B  64 28
        stz $29                           ; $A64D  64 29
L_A64F:
        lda $7E04                         ; $A64F  AD 04 7E
        sta $2A                           ; $A652  85 2A
        lda $7E05                         ; $A654  AD 05 7E
        sta $2B                           ; $A657  85 2B
        stz $2C                           ; $A659  64 2C
L_A65B:
        lda $28                           ; $A65B  A5 28
        ora $29                           ; $A65D  05 29
        beq L_A6A0                        ; $A65F  F0 3F
        jsr L_A5EF                        ; $A661  20 EF A5
        bcc L_A66B                        ; $A664  90 05
        jsr L_A605                        ; $A666  20 05 A6
        bra L_A65B                        ; $A669  80 F0
L_A66B:
        inc $2A                           ; $A66B  E6 2A
        bne L_A671                        ; $A66D  D0 02
        inc $2B                           ; $A66F  E6 2B
L_A671:
        lda $28                           ; $A671  A5 28
        ora $29                           ; $A673  05 29
        beq L_A6A0                        ; $A675  F0 29
        jsr L_A5EF                        ; $A677  20 EF A5
        bcs L_A69D                        ; $A67A  B0 21
        lda ($26)                         ; $A67C  B2 26
        ldy $24                           ; $A67E  A4 24
        cpy #$20                          ; $A680  C0 20
        bne L_A68E                        ; $A682  D0 0A
        cmp #$61                          ; $A684  C9 61
        bcc L_A68E                        ; $A686  90 06
        cmp #$7B                          ; $A688  C9 7B
        bcs L_A68E                        ; $A68A  B0 02
        and #$DF                          ; $A68C  29 DF
L_A68E:
        sta ($2A)                         ; $A68E  92 2A
        inc $2A                           ; $A690  E6 2A
        bne L_A696                        ; $A692  D0 02
        inc $2B                           ; $A694  E6 2B
L_A696:
        inc $2C                           ; $A696  E6 2C
        jsr L_A605                        ; $A698  20 05 A6
        bra L_A671                        ; $A69B  80 D4
L_A69D:
        jsr L_A605                        ; $A69D  20 05 A6
L_A6A0:
        lda $7E04                         ; $A6A0  AD 04 7E
        sta $2A                           ; $A6A3  85 2A
        lda $7E05                         ; $A6A5  AD 05 7E
        sta $2B                           ; $A6A8  85 2B
        lda $2C                           ; $A6AA  A5 2C
        sta ($2A)                         ; $A6AC  92 2A
        lda $7E04                         ; $A6AE  AD 04 7E
        sta $00,x                         ; $A6B1  95 00
        lda $7E05                         ; $A6B3  AD 05 7E
        sta $01,x                         ; $A6B6  95 01
        jmp NEXT                          ; $A6B8  4C 12 A0
N_FIND:
        .word N_WORD                      ; $A6BB
        .byte $04
        .byte "FIND"
W_FIND:
        lda $00,x                         ; $A6C2  B5 00
        sta $24                           ; $A6C4  85 24
        lda $01,x                         ; $A6C6  B5 01
        sta $25                           ; $A6C8  85 25
        lda $7E06                         ; $A6CA  AD 06 7E
        sta $26                           ; $A6CD  85 26
        lda $7E07                         ; $A6CF  AD 07 7E
        sta $27                           ; $A6D2  85 27
L_A6D4:
        lda $26                           ; $A6D4  A5 26
        ora $27                           ; $A6D6  05 27
        beq L_A742                        ; $A6D8  F0 68
        ldy #$02                          ; $A6DA  A0 02
        lda ($26),y                       ; $A6DC  B1 26
        sta $28                           ; $A6DE  85 28
        and #$20                          ; $A6E0  29 20
        bne L_A732                        ; $A6E2  D0 4E
        lda $28                           ; $A6E4  A5 28
        and #$1F                          ; $A6E6  29 1F
        cmp ($24)                         ; $A6E8  D2 24
        bne L_A732                        ; $A6EA  D0 46
        clc                               ; $A6EC  18
        lda $26                           ; $A6ED  A5 26
        adc #$02                          ; $A6EF  69 02
        sta $2A                           ; $A6F1  85 2A
        lda $27                           ; $A6F3  A5 27
        adc #$00                          ; $A6F5  69 00
        sta $2B                           ; $A6F7  85 2B
        lda $28                           ; $A6F9  A5 28
        and #$1F                          ; $A6FB  29 1F
        tay                               ; $A6FD  A8
L_A6FE:
        lda ($24),y                       ; $A6FE  B1 24
        cmp ($2A),y                       ; $A700  D1 2A
        bne L_A732                        ; $A702  D0 2E
        dey                               ; $A704  88
        bne L_A6FE                        ; $A705  D0 F7
        lda $28                           ; $A707  A5 28
        and #$1F                          ; $A709  29 1F
        clc                               ; $A70B  18
        adc #$03                          ; $A70C  69 03
        adc $26                           ; $A70E  65 26
        sta $00,x                         ; $A710  95 00
        lda $27                           ; $A712  A5 27
        adc #$00                          ; $A714  69 00
        sta $01,x                         ; $A716  95 01
        dex                               ; $A718  CA
        dex                               ; $A719  CA
        lda $28                           ; $A71A  A5 28
        and #$40                          ; $A71C  29 40
        beq L_A729                        ; $A71E  F0 09
        lda #$01                          ; $A720  A9 01
        sta $00,x                         ; $A722  95 00
        stz $01,x                         ; $A724  74 01
        jmp NEXT                          ; $A726  4C 12 A0
L_A729:
        lda #$FF                          ; $A729  A9 FF
        sta $00,x                         ; $A72B  95 00
        sta $01,x                         ; $A72D  95 01
        jmp NEXT                          ; $A72F  4C 12 A0
L_A732:
        lda ($26)                         ; $A732  B2 26
        sta $29                           ; $A734  85 29
        ldy #$01                          ; $A736  A0 01
        lda ($26),y                       ; $A738  B1 26
        sta $27                           ; $A73A  85 27
        lda $29                           ; $A73C  A5 29
        sta $26                           ; $A73E  85 26
        bra L_A6D4                        ; $A740  80 92
L_A742:
        dex                               ; $A742  CA
        dex                               ; $A743  CA
        stz $00,x                         ; $A744  74 00
        stz $01,x                         ; $A746  74 01
        jmp NEXT                          ; $A748  4C 12 A0
N_NUMBER:
        .word N_FIND                      ; $A74B
        .byte $06
        .byte "NUMBER"
W_NUMBER:
        lda $00,x                         ; $A754  B5 00
        sta $24                           ; $A756  85 24
        lda $01,x                         ; $A758  B5 01
        sta $25                           ; $A75A  85 25
        lda ($24)                         ; $A75C  B2 24
        sta $28                           ; $A75E  85 28
        stz $29                           ; $A760  64 29
        stz $26                           ; $A762  64 26
        stz $27                           ; $A764  64 27
        bra L_A76B                        ; $A766  80 03
L_A768:
        jmp L_A7F9                        ; $A768  4C F9 A7
L_A76B:
        inc $24                           ; $A76B  E6 24
        bne L_A771                        ; $A76D  D0 02
        inc $25                           ; $A76F  E6 25
L_A771:
        lda $28                           ; $A771  A5 28
        beq L_A768                        ; $A773  F0 F3
        lda ($24)                         ; $A775  B2 24
        cmp #$2D                          ; $A777  C9 2D
        bne L_A789                        ; $A779  D0 0E
        lda #$01                          ; $A77B  A9 01
        sta $29                           ; $A77D  85 29
        inc $24                           ; $A77F  E6 24
        bne L_A785                        ; $A781  D0 02
        inc $25                           ; $A783  E6 25
L_A785:
        dec $28                           ; $A785  C6 28
        beq L_A768                        ; $A787  F0 DF
L_A789:
        lda ($24)                         ; $A789  B2 24
        sec                               ; $A78B  38
        sbc #$30                          ; $A78C  E9 30
        bcc L_A768                        ; $A78E  90 D8
        cmp #$0A                          ; $A790  C9 0A
        bcc L_A79A                        ; $A792  90 06
        sbc #$07                          ; $A794  E9 07
        cmp #$0A                          ; $A796  C9 0A
        bcc L_A768                        ; $A798  90 CE
L_A79A:
        cmp $7E02                         ; $A79A  CD 02 7E
        bcs L_A768                        ; $A79D  B0 C9
        sta $2A                           ; $A79F  85 2A
        lda $26                           ; $A7A1  A5 26
        sta $2B                           ; $A7A3  85 2B
        lda $27                           ; $A7A5  A5 27
        sta $2C                           ; $A7A7  85 2C
        stz $26                           ; $A7A9  64 26
        stz $27                           ; $A7AB  64 27
        ldy $7E02                         ; $A7AD  AC 02 7E
L_A7B0:
        clc                               ; $A7B0  18
        lda $26                           ; $A7B1  A5 26
        adc $2B                           ; $A7B3  65 2B
        sta $26                           ; $A7B5  85 26
        lda $27                           ; $A7B7  A5 27
        adc $2C                           ; $A7B9  65 2C
        sta $27                           ; $A7BB  85 27
        dey                               ; $A7BD  88
        bne L_A7B0                        ; $A7BE  D0 F0
        clc                               ; $A7C0  18
        lda $26                           ; $A7C1  A5 26
        adc $2A                           ; $A7C3  65 2A
        sta $26                           ; $A7C5  85 26
        bcc L_A7CB                        ; $A7C7  90 02
        inc $27                           ; $A7C9  E6 27
L_A7CB:
        inc $24                           ; $A7CB  E6 24
        bne L_A7D1                        ; $A7CD  D0 02
        inc $25                           ; $A7CF  E6 25
L_A7D1:
        dec $28                           ; $A7D1  C6 28
        bne L_A789                        ; $A7D3  D0 B4
        lda $29                           ; $A7D5  A5 29
        beq L_A7E6                        ; $A7D7  F0 0D
        sec                               ; $A7D9  38
        lda #$00                          ; $A7DA  A9 00
        sbc $26                           ; $A7DC  E5 26
        sta $26                           ; $A7DE  85 26
        lda #$00                          ; $A7E0  A9 00
        sbc $27                           ; $A7E2  E5 27
        sta $27                           ; $A7E4  85 27
L_A7E6:
        lda $26                           ; $A7E6  A5 26
        sta $00,x                         ; $A7E8  95 00
        lda $27                           ; $A7EA  A5 27
        sta $01,x                         ; $A7EC  95 01
        dex                               ; $A7EE  CA
        dex                               ; $A7EF  CA
        lda #$FF                          ; $A7F0  A9 FF
        sta $00,x                         ; $A7F2  95 00
        sta $01,x                         ; $A7F4  95 01
        jmp NEXT                          ; $A7F6  4C 12 A0
L_A7F9:
        stz $00,x                         ; $A7F9  74 00
        stz $01,x                         ; $A7FB  74 01
        dex                               ; $A7FD  CA
        dex                               ; $A7FE  CA
        stz $00,x                         ; $A7FF  74 00
        stz $01,x                         ; $A801  74 01
        jmp NEXT                          ; $A803  4C 12 A0
N_COMMA:
        .word N_NUMBER                    ; $A806
        .byte $01
        .byte ","
W_COMMA:
        lda $7E04                         ; $A80A  AD 04 7E
        sta $24                           ; $A80D  85 24
        lda $7E05                         ; $A80F  AD 05 7E
        sta $25                           ; $A812  85 25
        lda $00,x                         ; $A814  B5 00
        sta ($24)                         ; $A816  92 24
        ldy #$01                          ; $A818  A0 01
        lda $01,x                         ; $A81A  B5 01
        sta ($24),y                       ; $A81C  91 24
        inx                               ; $A81E  E8
        inx                               ; $A81F  E8
        clc                               ; $A820  18
        lda $7E04                         ; $A821  AD 04 7E
        adc #$02                          ; $A824  69 02
        sta $7E04                         ; $A826  8D 04 7E
        bcc L_A82E                        ; $A829  90 03
        inc $7E05                         ; $A82B  EE 05 7E
L_A82E:
        jmp NEXT                          ; $A82E  4C 12 A0
N_CCOMMA:
        .word N_COMMA                     ; $A831
        .byte $02
        .byte "C,"
W_CCOMMA:
        lda $7E04                         ; $A836  AD 04 7E
        sta $24                           ; $A839  85 24
        lda $7E05                         ; $A83B  AD 05 7E
        sta $25                           ; $A83E  85 25
        lda $00,x                         ; $A840  B5 00
        sta ($24)                         ; $A842  92 24
        inx                               ; $A844  E8
        inx                               ; $A845  E8
        inc $7E04                         ; $A846  EE 04 7E
        bne L_A84E                        ; $A849  D0 03
        inc $7E05                         ; $A84B  EE 05 7E
L_A84E:
        jmp NEXT                          ; $A84E  4C 12 A0
N_LPHDRRP:
        .word N_CCOMMA                    ; $A851
        .byte $05
        .byte "(HDR)"
W_LPHDRRP:
        lda $7E04                         ; $A859  AD 04 7E
        sta $24                           ; $A85C  85 24
        lda $7E05                         ; $A85E  AD 05 7E
        sta $25                           ; $A861  85 25
        clc                               ; $A863  18
        lda $24                           ; $A864  A5 24
        adc #$02                          ; $A866  69 02
        sta $26                           ; $A868  85 26
        lda $25                           ; $A86A  A5 25
        adc #$00                          ; $A86C  69 00
        sta $27                           ; $A86E  85 27
        lda ($24)                         ; $A870  B2 24
        and #$1F                          ; $A872  29 1F
        sta $28                           ; $A874  85 28
        tay                               ; $A876  A8
        beq L_A880                        ; $A877  F0 07
L_A879:
        lda ($24),y                       ; $A879  B1 24
        sta ($26),y                       ; $A87B  91 26
        dey                               ; $A87D  88
        bne L_A879                        ; $A87E  D0 F9
L_A880:
        lda $28                           ; $A880  A5 28
        ldy #$02                          ; $A882  A0 02
        sta ($24),y                       ; $A884  91 24
        lda $7E06                         ; $A886  AD 06 7E
        sta ($24)                         ; $A889  92 24
        ldy #$01                          ; $A88B  A0 01
        lda $7E07                         ; $A88D  AD 07 7E
        sta ($24),y                       ; $A890  91 24
        lda $24                           ; $A892  A5 24
        sta $7E06                         ; $A894  8D 06 7E
        lda $25                           ; $A897  A5 25
        sta $7E07                         ; $A899  8D 07 7E
        clc                               ; $A89C  18
        lda $28                           ; $A89D  A5 28
        adc #$03                          ; $A89F  69 03
        adc $24                           ; $A8A1  65 24
        sta $7E04                         ; $A8A3  8D 04 7E
        lda $25                           ; $A8A6  A5 25
        adc #$00                          ; $A8A8  69 00
        sta $7E05                         ; $A8AA  8D 05 7E
        inx                               ; $A8AD  E8
        inx                               ; $A8AE  E8
        jmp NEXT                          ; $A8AF  4C 12 A0
N_SMUDGE:
        .word N_LPHDRRP                   ; $A8B2
        .byte $06
        .byte "SMUDGE"
W_SMUDGE:
        lda $7E06                         ; $A8BB  AD 06 7E
        sta $24                           ; $A8BE  85 24
        lda $7E07                         ; $A8C0  AD 07 7E
        sta $25                           ; $A8C3  85 25
        ldy #$02                          ; $A8C5  A0 02
        lda ($24),y                       ; $A8C7  B1 24
        eor #$20                          ; $A8C9  49 20
        sta ($24),y                       ; $A8CB  91 24
        jmp NEXT                          ; $A8CD  4C 12 A0
N_LBR:
        .word N_SMUDGE                    ; $A8D0
        .byte $41   ; IMMEDIATE
        .byte "["
W_LBR:
        stz $7E00                         ; $A8D4  9C 00 7E
        stz $7E01                         ; $A8D7  9C 01 7E
        jmp NEXT                          ; $A8DA  4C 12 A0
N_RBR:
        .word N_LBR                       ; $A8DD
        .byte $01
        .byte "]"
W_RBR:
        lda #$FF                          ; $A8E1  A9 FF
        sta $7E00                         ; $A8E3  8D 00 7E
        sta $7E01                         ; $A8E6  8D 01 7E
        jmp NEXT                          ; $A8E9  4C 12 A0
N_STATE:
        .word N_RBR                       ; $A8EC
        .byte $05
        .byte "STATE"
W_STATE:
        lda #$00                          ; $A8F4  A9 00
        ldy #$7E                          ; $A8F6  A0 7E
        dex                               ; $A8F8  CA
        dex                               ; $A8F9  CA
        sta $00,x                         ; $A8FA  95 00
        sty $01,x                         ; $A8FC  94 01
        jmp NEXT                          ; $A8FE  4C 12 A0
N_BASE:
        .word N_STATE                     ; $A901
        .byte $04
        .byte "BASE"
W_BASE:
        lda #$02                          ; $A908  A9 02
        ldy #$7E                          ; $A90A  A0 7E
        dex                               ; $A90C  CA
        dex                               ; $A90D  CA
        sta $00,x                         ; $A90E  95 00
        sty $01,x                         ; $A910  94 01
        jmp NEXT                          ; $A912  4C 12 A0
N_DP:
        .word N_BASE                      ; $A915
        .byte $02
        .byte "DP"
W_DP:
        lda #$04                          ; $A91A  A9 04
        ldy #$7E                          ; $A91C  A0 7E
        dex                               ; $A91E  CA
        dex                               ; $A91F  CA
        sta $00,x                         ; $A920  95 00
        sty $01,x                         ; $A922  94 01
        jmp NEXT                          ; $A924  4C 12 A0
N_LATEST:
        .word N_DP                        ; $A927
        .byte $06
        .byte "LATEST"
W_LATEST:
        lda #$06                          ; $A930  A9 06
        ldy #$7E                          ; $A932  A0 7E
        dex                               ; $A934  CA
        dex                               ; $A935  CA
        sta $00,x                         ; $A936  95 00
        sty $01,x                         ; $A938  94 01
        jmp NEXT                          ; $A93A  4C 12 A0
N_GTIN:
        .word N_LATEST                    ; $A93D
        .byte $03
        .byte ">IN"
W_GTIN:
        lda #$08                          ; $A943  A9 08
        ldy #$7E                          ; $A945  A0 7E
        dex                               ; $A947  CA
        dex                               ; $A948  CA
        sta $00,x                         ; $A949  95 00
        sty $01,x                         ; $A94B  94 01
        jmp NEXT                          ; $A94D  4C 12 A0
N_SRC:
        .word N_GTIN                      ; $A950
        .byte $03
        .byte "SRC"
W_SRC:
        lda #$0A                          ; $A956  A9 0A
        ldy #$7E                          ; $A958  A0 7E
        dex                               ; $A95A  CA
        dex                               ; $A95B  CA
        sta $00,x                         ; $A95C  95 00
        sty $01,x                         ; $A95E  94 01
        jmp NEXT                          ; $A960  4C 12 A0
N_SLEN:
        .word N_SRC                       ; $A963
        .byte $04
        .byte "SLEN"
W_SLEN:
        lda #$0C                          ; $A96A  A9 0C
        ldy #$7E                          ; $A96C  A0 7E
        dex                               ; $A96E  CA
        dex                               ; $A96F  CA
        sta $00,x                         ; $A970  95 00
        sty $01,x                         ; $A972  94 01
        jmp NEXT                          ; $A974  4C 12 A0
N_SPFETCH:
        .word N_SLEN                      ; $A977
        .byte $03
        .byte "SP@"
W_SPFETCH:
        txa                               ; $A97D  8A
        ldy #$00                          ; $A97E  A0 00
        dex                               ; $A980  CA
        dex                               ; $A981  CA
        sta $00,x                         ; $A982  95 00
        sty $01,x                         ; $A984  94 01
        jmp NEXT                          ; $A986  4C 12 A0
N_LPDOCOLRP:
        .word N_SPFETCH                   ; $A989
        .byte $07
        .byte "(DOCOL)"
W_LPDOCOLRP:
        lda #$29                          ; $A993  A9 29
        ldy #$A0                          ; $A995  A0 A0
        dex                               ; $A997  CA
        dex                               ; $A998  CA
        sta $00,x                         ; $A999  95 00
        sty $01,x                         ; $A99B  94 01
        jmp NEXT                          ; $A99D  4C 12 A0
N_LPDOCONRP:
        .word N_LPDOCOLRP                 ; $A9A0
        .byte $07
        .byte "(DOCON)"
W_LPDOCONRP:
        lda #$45                          ; $A9AA  A9 45
        ldy #$A0                          ; $A9AC  A0 A0
        dex                               ; $A9AE  CA
        dex                               ; $A9AF  CA
        sta $00,x                         ; $A9B0  95 00
        sty $01,x                         ; $A9B2  94 01
        jmp NEXT                          ; $A9B4  4C 12 A0
N_LPDOVARRP:
        .word N_LPDOCONRP                 ; $A9B7
        .byte $07
        .byte "(DOVAR)"
W_LPDOVARRP:
        lda #$60                          ; $A9C1  A9 60
        ldy #$A0                          ; $A9C3  A0 A0
        dex                               ; $A9C5  CA
        dex                               ; $A9C6  CA
        sta $00,x                         ; $A9C7  95 00
        sty $01,x                         ; $A9C9  94 01
        jmp NEXT                          ; $A9CB  4C 12 A0
N_BYE:
        .word N_LPDOVARRP                 ; $A9CE
        .byte $03
        .byte "BYE"
W_BYE:
        jmp FT_BYE                        ; $A9D4  (FPGA: switch it out again)
        .byte $68,$85,$22,$68,$85,$23,$A5,$21,$48,$A5,$20,$48,$A0,$01,$B1,$22; $A9D7
        .byte $85,$20,$C8,$B1,$22,$85,$21,$18,$A5,$22,$69,$03,$48,$A5,$23,$69; $A9E7
        .byte $00,$A8,$68,$CA,$CA,$95,$00,$94,$01,$4C,$12,$A0,$A6,$A0; $A9F7
N_LPDODOESRP:
        .word N_BYE                       ; $AA05
        .byte $08
        .byte "(DODOES)"
W_LPDODOESRP:
        lda #$D7                          ; $AA10  A9 D7
        ldy #$A9                          ; $AA12  A0 A9
        dex                               ; $AA14  CA
        dex                               ; $AA15  CA
        sta $00,x                         ; $AA16  95 00
        sty $01,x                         ; $AA18  94 01
        jmp NEXT                          ; $AA1A  4C 12 A0
N_LPXTHRP:
        .word N_LPDODOESRP                ; $AA1D
        .byte $05
        .byte "(XTH)"
W_LPXTHRP:
        lda #$03                          ; $AA25  A9 03
        ldy #$AA                          ; $AA27  A0 AA
        dex                               ; $AA29  CA
        dex                               ; $AA2A  CA
        sta $00,x                         ; $AA2B  95 00
        sty $01,x                         ; $AA2D  94 01
        jmp NEXT                          ; $AA2F  4C 12 A0
N_CALL:
        .word N_LPXTHRP                   ; $AA32
        .byte $04
        .byte "CALL"
W_CALL:
        lda $00,x                         ; $AA39  B5 00
        sta WP                            ; $AA3B  85 22
        lda $01,x                         ; $AA3D  B5 01
        sta WPH                           ; $AA3F  85 23
        inx                               ; $AA41  E8
        inx                               ; $AA42  E8
        stx $2D                           ; $AA43  86 2D
        jsr L_AA4D                        ; $AA45  20 4D AA
        ldx $2D                           ; $AA48  A6 2D
        jmp NEXT                          ; $AA4A  4C 12 A0
L_AA4D:
        jmp (WP)                          ; $AA4D  6C 22 00
L_AA50:
        ldy #$00                          ; $AA50  A0 00
L_AA52:
        cmp #$0A                          ; $AA52  C9 0A
        bcc L_AA5B                        ; $AA54  90 05
        sbc #$0A                          ; $AA56  E9 0A
        iny                               ; $AA58  C8
        bra L_AA52                        ; $AA59  80 F7
L_AA5B:
        sta $24                           ; $AA5B  85 24
        tya                               ; $AA5D  98
        asl a                             ; $AA5E  0A
        asl a                             ; $AA5F  0A
        asl a                             ; $AA60  0A
        asl a                             ; $AA61  0A
        ora $24                           ; $AA62  05 24
        rts                               ; $AA64  60
N_TRKFETCH:
        .word N_CALL                      ; $AA65
        .byte $04
        .byte "TRK@"
W_TRKFETCH:
        lda $00,x                         ; $AA6C  B5 00
        inx                               ; $AA6E  E8
        inx                               ; $AA6F  E8
        stx $2D                           ; $AA70  86 2D
        jsr L_AA50                        ; $AA72  20 50 AA
        jsr $E024                         ; $AA75  20 24 E0
        lda #$01                          ; $AA78  A9 01
        sta $265E                         ; $AA7A  8D 5E 26
        stz $FE                           ; $AA7D  64 FE
        lda #$70                          ; $AA7F  A9 70
        sta $FF                           ; $AA81  85 FF
        jsr $E033                         ; $AA83  20 33 E0
        ldx $2D                           ; $AA86  A6 2D
        jmp NEXT                          ; $AA88  4C 12 A0
N_TRKSTORE:
        .word N_TRKFETCH                  ; $AA8B
        .byte $04
        .byte "TRK!"
W_TRKSTORE:
        lda $00,x                         ; $AA92  B5 00
        inx                               ; $AA94  E8
        inx                               ; $AA95  E8
        stx $2D                           ; $AA96  86 2D
        jsr L_AA50                        ; $AA98  20 50 AA
        jsr $E024                         ; $AA9B  20 24 E0
        lda #$01                          ; $AA9E  A9 01
        sta $265E                         ; $AAA0  8D 5E 26
        lda #$08                          ; $AAA3  A9 08
        sta $265F                         ; $AAA5  8D 5F 26
        stz $FE                           ; $AAA8  64 FE
        lda #$70                          ; $AAAA  A9 70
        sta $FF                           ; $AAAC  85 FF
        jsr $E02D                         ; $AAAE  20 2D E0
        jsr $E039                         ; $AAB1  20 39 E0
        jsr $E030                         ; $AAB4  20 30 E0
        ldx $2D                           ; $AAB7  A6 2D
        jmp NEXT                          ; $AAB9  4C 12 A0
N_DIRFETCH:
        .word N_TRKSTORE                  ; $AABC
        .byte $04
        .byte "DIR@"
W_DIRFETCH:
        stx $2D                           ; $AAC3  86 2D
        lda #$12                          ; $AAC5  A9 12
        jsr $E024                         ; $AAC7  20 24 E0
        lda #$01                          ; $AACA  A9 01
        sta $265E                         ; $AACC  8D 5E 26
        stz $FE                           ; $AACF  64 FE
        lda #$79                          ; $AAD1  A9 79
        sta $FF                           ; $AAD3  85 FF
        jsr $E033                         ; $AAD5  20 33 E0
        lda #$02                          ; $AAD8  A9 02
        sta $265E                         ; $AADA  8D 5E 26
        stz $FE                           ; $AADD  64 FE
        lda #$7A                          ; $AADF  A9 7A
        sta $FF                           ; $AAE1  85 FF
        jsr $E033                         ; $AAE3  20 33 E0
        ldx $2D                           ; $AAE6  A6 2D
        jmp NEXT                          ; $AAE8  4C 12 A0
N_DIRSTORE:
        .word N_DIRFETCH                  ; $AAEB
        .byte $04
        .byte "DIR!"
W_DIRSTORE:
        jmp $D00C                         ; $AAF2  4C 0C D0
        .byte $01                         ; $AAF5
        jsr L_AB03                        ; $AAF6  20 03 AB
        lda #$02                          ; $AAF9  A9 02
        jsr L_AB03                        ; $AAFB  20 03 AB
        ldx $2D                           ; $AAFE  A6 2D
        jmp NEXT                          ; $AB00  4C 12 A0
L_AB03:
        sta $265E                         ; $AB03  8D 5E 26
        lda #$12                          ; $AB06  A9 12
        jsr $E024                         ; $AB08  20 24 E0
        lda #$01                          ; $AB0B  A9 01
        sta $265F                         ; $AB0D  8D 5F 26
        stz $FE                           ; $AB10  64 FE
        lda $265E                         ; $AB12  AD 5E 26
        clc                               ; $AB15  18
        adc #$78                          ; $AB16  69 78
        sta $FF                           ; $AB18  85 FF
        jsr $E02D                         ; $AB1A  20 2D E0
        jsr $E039                         ; $AB1D  20 39 E0
        jmp $E030                         ; $AB20  4C 30 E0
N_BL:
        .word N_DIRSTORE                  ; $AB23
        .byte $02
        .byte "BL"
W_BL:
        jsr DOCOL                         ; $AB28
        .word W_LIT                       ; $AB2B
        .word $0020   ; 32                ; $AB2D
        .word W_EXIT                      ; $AB2F
N_LPCREATERP:
        .word N_BL                        ; $AB31
        .byte $08
        .byte "(CREATE)"
W_LPCREATERP:
        jsr DOCOL                         ; $AB3C
        .word W_BL                        ; $AB3F
        .word W_WORD                      ; $AB41
        .word W_LPHDRRP                   ; $AB43
        .word W_EXIT                      ; $AB45
N_COMMACODE:
        .word N_LPCREATERP                ; $AB47
        .byte $05
        .byte ",CODE"
W_COMMACODE:
        jsr DOCOL                         ; $AB4F
        .word W_LIT                       ; $AB52
        .word $0020   ; 32                ; $AB54
        .word W_CCOMMA                    ; $AB56
        .word W_COMMA                     ; $AB58
        .word W_EXIT                      ; $AB5A
N_COLON:
        .word N_COMMACODE                 ; $AB5C
        .byte $01
        .byte ":"
W_COLON:
        jsr DOCOL                         ; $AB60
        .word W_LPCREATERP                ; $AB63
        .word W_LPDOCOLRP                 ; $AB65
        .word W_COMMACODE                 ; $AB67
        .word W_SMUDGE                    ; $AB69
        .word W_RBR                       ; $AB6B
        .word W_EXIT                      ; $AB6D
N_SEMI:
        .word N_COLON                     ; $AB6F
        .byte $41   ; IMMEDIATE
        .byte ";"
W_SEMI:
        jsr DOCOL                         ; $AB73
        .word W_LIT                       ; $AB76
        .word $A0A6   ; -24410            ; $AB78
        .word W_COMMA                     ; $AB7A
        .word W_SMUDGE                    ; $AB7C
        .word W_LBR                       ; $AB7E
        .word W_EXIT                      ; $AB80
N_ERROR:
        .word N_SEMI                      ; $AB82
        .byte $05
        .byte "ERROR"
W_ERROR:
        jsr DOCOL                         ; $AB8A
        .word W_DP                        ; $AB8D
        .word W_FETCH                     ; $AB8F
        .word W_COUNT                     ; $AB91
        .word W_TYPE                      ; $AB93
        .word W_LIT                       ; $AB95
        .word $003F   ; 63                ; $AB97
        .word W_EMIT                      ; $AB99
        .word W_CR                        ; $AB9B
        .word W_ABORT                     ; $AB9D
N_QSTACK:
        .word N_ERROR                     ; $AB9F
        .byte $06
        .byte "?STACK"
W_QSTACK:
        cpx #$81                          ; $ABA8  E0 81
        bcs L_ABAF                        ; $ABAA  B0 03
        jmp NEXT                          ; $ABAC  4C 12 A0
L_ABAF:
        lda #$CA                          ; $ABAF  A9 CA
        ldy #$AB                          ; $ABB1  A0 AB
        sta $2A                           ; $ABB3  85 2A
        sty $2B                           ; $ABB5  84 2B
        ldy #$00                          ; $ABB7  A0 00
L_ABB9:
        lda ($2A),y                       ; $ABB9  B1 2A
        beq L_ABC7                        ; $ABBB  F0 0A
        sty $2C                           ; $ABBD  84 2C
        jsr L_A4DA                        ; $ABBF  20 DA A4
        ldy $2C                           ; $ABC2  A4 2C
        iny                               ; $ABC4  C8
        bra L_ABB9                        ; $ABC5  80 F2
L_ABC7:
        jmp W_ABORT                       ; $ABC7  4C 3C AC
        .byte $53,$54,$41,$43,$4B,$3F,$0D,$0A,$00; $ABCA
N_INTERPRET:
        .word N_QSTACK                    ; $ABD3
        .byte $09
        .byte "INTERPRET"
W_INTERPRET:
        jsr DOCOL                         ; $ABDF
B_ABE2:
        .word W_BL                        ; $ABE2
        .word W_WORD                      ; $ABE4
        .word W_DUP                       ; $ABE6
        .word W_CFETCH                    ; $ABE8
        .word W_0BRANCH                   ; $ABEA
        .word B_AC30                      ; $ABEC
        .word W_FIND                      ; $ABEE
        .word W_DUP                       ; $ABF0
        .word W_0BRANCH                   ; $ABF2
        .word B_AC10                      ; $ABF4
        .word W_0LT                       ; $ABF6
        .word W_STATE                     ; $ABF8
        .word W_FETCH                     ; $ABFA
        .word W_AND                       ; $ABFC
        .word W_0BRANCH                   ; $ABFE
        .word B_AC08                      ; $AC00
        .word W_COMMA                     ; $AC02
        .word W_BRANCH                    ; $AC04
        .word B_ABE2                      ; $AC06
B_AC08:
        .word W_EXECUTE                   ; $AC08
        .word W_QSTACK                    ; $AC0A
        .word W_BRANCH                    ; $AC0C
        .word B_ABE2                      ; $AC0E
B_AC10:
        .word W_DROP                      ; $AC10
        .word W_NUMBER                    ; $AC12
        .word W_0BRANCH                   ; $AC14
        .word B_AC2C                      ; $AC16
        .word W_STATE                     ; $AC18
        .word W_FETCH                     ; $AC1A
        .word W_0BRANCH                   ; $AC1C
        .word B_ABE2                      ; $AC1E
        .word W_LIT                       ; $AC20
        .word $A0CC   ; -24372            ; $AC22
        .word W_COMMA                     ; $AC24
        .word W_COMMA                     ; $AC26
        .word W_BRANCH                    ; $AC28
        .word B_ABE2                      ; $AC2A
B_AC2C:
        .word W_DROP                      ; $AC2C
        .word W_ERROR                     ; $AC2E
B_AC30:
        .word W_DROP                      ; $AC30
        .word W_EXIT                      ; $AC32
N_ABORT:
        .word N_INTERPRET                 ; $AC34
        .byte $05
        .byte "ABORT"
W_ABORT:
        ldx #$FF                          ; $AC3C  A2 FF
        txs                               ; $AC3E  9A
        ldx #$80                          ; $AC3F  A2 80
        stz $7E00                         ; $AC41  9C 00 7E
        stz $7E01                         ; $AC44  9C 01 7E
        stz $7E20                         ; $AC47  9C 20 7E
        stz $7E21                         ; $AC4A  9C 21 7E
        stz $7E22                         ; $AC4D  9C 22 7E
        stz $7E23                         ; $AC50  9C 23 7E
        lda #$89                          ; $AC53  A9 89
        sta IP                            ; $AC55  85 20
        lda #$AC                          ; $AC57  A9 AC
        sta IPH                           ; $AC59  85 21
        jmp NEXT                          ; $AC5B  4C 12 A0
N_LPOKRP:
        .word N_ABORT                     ; $AC5E
        .byte $04
        .byte "(OK)"
W_LPOKRP:
        lda $7E00                         ; $AC65  AD 00 7E
        ora $7E01                         ; $AC68  0D 01 7E
        bne L_AC7C                        ; $AC6B  D0 0F
        lda #$20                          ; $AC6D  A9 20
        jsr L_A4DA                        ; $AC6F  20 DA A4
        lda #$4F                          ; $AC72  A9 4F
        jsr L_A4DA                        ; $AC74  20 DA A4
        lda #$4B                          ; $AC77  A9 4B
        jsr L_A4DA                        ; $AC79  20 DA A4
L_AC7C:
        lda #$0D                          ; $AC7C  A9 0D
        jsr L_A4DA                        ; $AC7E  20 DA A4
        lda #$0A                          ; $AC81  A9 0A
        jsr L_A4DA                        ; $AC83  20 DA A4
        jmp NEXT                          ; $AC86  4C 12 A0
        .byte $8E,$A5,$DF,$AB,$65,$AC,$F3,$A0,$89,$AC; $AC89
N_QUIT:
        .word N_LPOKRP                    ; $AC93
        .byte $04
        .byte "QUIT"
W_QUIT:
        jmp W_ABORT                       ; $AC9A  4C 3C AC
        .byte $0D,$0A,$46,$4F,$52,$54,$48,$2D,$37,$39,$20,$36,$35,$43,$30,$32; $AC9D
        .byte $20,$20,$00,$84,$2C,$85,$2A,$86,$2B,$A0,$00,$B1,$2A,$F0,$0A,$84; $ACAD
        .byte $2C,$20,$DA,$A4,$A4,$2C,$C8,$80,$F2,$60,$4C,$3C,$AC; $ACBD
L_ACCA:
        cld                               ; $ACCA  D8
        ldx #$FF                          ; $ACCB  A2 FF
        txs                               ; $ACCD  9A
        ldx #$80                          ; $ACCE  A2 80
        stz $7E00                         ; $ACD0  9C 00 7E
        stz $7E01                         ; $ACD3  9C 01 7E
        lda #$0A                          ; $ACD6  A9 0A
        sta $7E02                         ; $ACD8  8D 02 7E
        stz $7E03                         ; $ACDB  9C 03 7E
        stz $7E20                         ; $ACDE  9C 20 7E
        stz $7E21                         ; $ACE1  9C 21 7E
        stz $7E22                         ; $ACE4  9C 22 7E
        stz $7E23                         ; $ACE7  9C 23 7E
        lda #$9D                          ; $ACEA  A9 9D
        ldy #$AC                          ; $ACEC  A0 AC
        sta $2A                           ; $ACEE  85 2A
        sty $2B                           ; $ACF0  84 2B
        ldy #$00                          ; $ACF2  A0 00
L_ACF4:
        lda ($2A),y                       ; $ACF4  B1 2A
        beq L_AD02                        ; $ACF6  F0 0A
        sty $2C                           ; $ACF8  84 2C
        jsr L_A4DA                        ; $ACFA  20 DA A4
        ldy $2C                           ; $ACFD  A4 2C
        iny                               ; $ACFF  C8
        bra L_ACF4                        ; $AD00  80 F2
L_AD02:
        lda #$5F                          ; $AD02  A9 5F
        sta $24                           ; $AD04  85 24
        lda #$AD                          ; $AD06  A9 AD
        sta $25                           ; $AD08  85 25
        lda #$00                          ; $AD0A  A9 00
        sta $26                           ; $AD0C  85 26
        lda #$44                          ; $AD0E  A9 44
        sta $27                           ; $AD10  85 27
        lda #$90                          ; $AD12  A9 90
        sta $28                           ; $AD14  85 28
        lda #$12                          ; $AD16  A9 12
        sta $29                           ; $AD18  85 29
L_AD1A:
        lda $28                           ; $AD1A  A5 28
        ora $29                           ; $AD1C  05 29
        beq L_AD3A                        ; $AD1E  F0 1A
        lda ($24)                         ; $AD20  B2 24
        sta ($26)                         ; $AD22  92 26
        inc $24                           ; $AD24  E6 24
        bne L_AD2A                        ; $AD26  D0 02
        inc $25                           ; $AD28  E6 25
L_AD2A:
        inc $26                           ; $AD2A  E6 26
        bne L_AD30                        ; $AD2C  D0 02
        inc $27                           ; $AD2E  E6 27
L_AD30:
        lda $28                           ; $AD30  A5 28
        bne L_AD36                        ; $AD32  D0 02
        dec $29                           ; $AD34  C6 29
L_AD36:
        dec $28                           ; $AD36  C6 28
        bra L_AD1A                        ; $AD38  80 E0
L_AD3A:
        lda #$90                          ; $AD3A  A9 90
        sta $7E04                         ; $AD3C  8D 04 7E
        lda #$56                          ; $AD3F  A9 56
        sta $7E05                         ; $AD41  8D 05 7E
        lda #$48                          ; $AD44  A9 48
        sta $7E06                         ; $AD46  8D 06 7E
        lda #$56                          ; $AD49  A9 56
        sta $7E07                         ; $AD4B  8D 07 7E
        lda #$59                          ; $AD4E  A9 59
        sta IP                            ; $AD50  85 20
        lda #$AD                          ; $AD52  A9 AD
        sta IPH                           ; $AD54  85 21
        jmp NEXT                          ; $AD56  4C 12 A0
        .byte $53,$56,$F3,$A0,$89,$AC     ; $AD59

; ----------------------------------------------------------------------
; RAM DICTIONARY: STORED HERE, COPIED TO $4400-$568F AT COLD START
; ----------------------------------------------------------------------
        .org $4400
N_CONSTANT:
        .word N_QUIT                      ; $4400
        .byte $08
        .byte "CONSTANT"
W_CONSTANT:
        jsr DOCOL                         ; $440B
        .word W_LPCREATERP                ; $440E
        .word W_LPDOCONRP                 ; $4410
        .word W_COMMACODE                 ; $4412
        .word W_COMMA                     ; $4414
        .word W_EXIT                      ; $4416
N_VARIABLE:
        .word N_CONSTANT                  ; $4418
        .byte $08
        .byte "VARIABLE"
W_VARIABLE:
        jsr DOCOL                         ; $4423
        .word W_LPCREATERP                ; $4426
        .word W_LPDOVARRP                 ; $4428
        .word W_COMMACODE                 ; $442A
        .word W_LIT                       ; $442C
        .word $0000   ; 0                 ; $442E
        .word W_COMMA                     ; $4430
        .word W_EXIT                      ; $4432
N_BLK:
        .word N_VARIABLE                  ; $4434
        .byte $03
        .byte "BLK"
W_BLK:
        jsr DOCON                         ; $443A
        .word $7E20                       ; $443D
N_LDD:
        .word N_BLK                       ; $443F
        .byte $03
        .byte "LDD"
W_LDD:
        jsr DOCON                         ; $4445
        .word $7E22                       ; $4448
N_TRKBUF:
        .word N_LDD                       ; $444A
        .byte $06
        .byte "TRKBUF"
W_TRKBUF:
        jsr DOCON                         ; $4453
        .word $7000                       ; $4456
N_DIRBUF:
        .word N_TRKBUF                    ; $4458
        .byte $06
        .byte "DIRBUF"
W_DIRBUF:
        jsr DOCON                         ; $4461
        .word $7900                       ; $4464
N_PLUSSTORE:
        .word N_DIRBUF                    ; $4466
        .byte $02
        .byte "+!"
W_PLUSSTORE:
        jsr DOCOL                         ; $446B
        .word W_DUP                       ; $446E
        .word W_FETCH                     ; $4470
        .word W_ROT                       ; $4472
        .word W_PLUS                      ; $4474
        .word W_SWAP                      ; $4476
        .word W_STORE                     ; $4478
        .word W_EXIT                      ; $447A
N_HERE:
        .word N_PLUSSTORE                 ; $447C
        .byte $04
        .byte "HERE"
W_HERE:
        jsr DOCOL                         ; $4483
        .word W_DP                        ; $4486
        .word W_FETCH                     ; $4488
        .word W_EXIT                      ; $448A
N_2PLUS:
        .word N_HERE                      ; $448C
        .byte $02
        .byte "2+"
W_2PLUS:
        jsr DOCOL                         ; $4491
        .word W_LIT                       ; $4494
        .word $0002   ; 2                 ; $4496
        .word W_PLUS                      ; $4498
        .word W_EXIT                      ; $449A
N_1MINUS:
        .word N_2PLUS                     ; $449C
        .byte $02
        .byte "1-"
W_1MINUS:
        jsr DOCOL                         ; $44A1
        .word W_LIT                       ; $44A4
        .word $0001   ; 1                 ; $44A6
        .word W_MINUS                     ; $44A8
        .word W_EXIT                      ; $44AA
N_IMMEDIATE:
        .word N_1MINUS                    ; $44AC
        .byte $09
        .byte "IMMEDIATE"
W_IMMEDIATE:
        jsr DOCOL                         ; $44B8
        .word W_LATEST                    ; $44BB
        .word W_FETCH                     ; $44BD
        .word W_2PLUS                     ; $44BF
        .word W_DUP                       ; $44C1
        .word W_CFETCH                    ; $44C3
        .word W_LIT                       ; $44C5
        .word $0040   ; 64                ; $44C7
        .word W_OR                        ; $44C9
        .word W_SWAP                      ; $44CB
        .word W_CSTORE                    ; $44CD
        .word W_EXIT                      ; $44CF
N_ALLOT:
        .word N_IMMEDIATE                 ; $44D1
        .byte $05
        .byte "ALLOT"
W_ALLOT:
        jsr DOCOL                         ; $44D9
        .word W_DP                        ; $44DC
        .word W_PLUSSTORE                 ; $44DE
        .word W_EXIT                      ; $44E0
N_LP:
        .word N_ALLOT                     ; $44E2
        .byte $41   ; IMMEDIATE
        .byte "("
W_LP:
        jsr DOCOL                         ; $44E6
        .word W_LIT                       ; $44E9
        .word $0029   ; 41                ; $44EB
        .word W_WORD                      ; $44ED
        .word W_DROP                      ; $44EF
        .word W_EXIT                      ; $44F1
N_COMPILE:
        .word N_LP                        ; $44F3
        .byte $07
        .byte "COMPILE"
W_COMPILE:
        jsr DOCOL                         ; $44FD
        .word W_RGT                       ; $4500
        .word W_DUP                       ; $4502
        .word W_2PLUS                     ; $4504
        .word W_GTR                       ; $4506
        .word W_FETCH                     ; $4508
        .word W_COMMA                     ; $450A
        .word W_EXIT                      ; $450C
N_IF:
        .word N_COMPILE                   ; $450E
        .byte $42   ; IMMEDIATE
        .byte "IF"
W_IF:
        jsr DOCOL                         ; $4513
        .word W_COMPILE                   ; $4516
        .word W_0BRANCH                   ; $4518
        .word W_HERE                      ; $451A
        .word W_LIT                       ; $451C
        .word $0000   ; 0                 ; $451E
        .word W_COMMA                     ; $4520
        .word W_EXIT                      ; $4522
N_THEN:
        .word N_IF                        ; $4524
        .byte $44   ; IMMEDIATE
        .byte "THEN"
W_THEN:
        jsr DOCOL                         ; $452B
        .word W_HERE                      ; $452E
        .word W_SWAP                      ; $4530
        .word W_STORE                     ; $4532
        .word W_EXIT                      ; $4534
N_ELSE:
        .word N_THEN                      ; $4536
        .byte $44   ; IMMEDIATE
        .byte "ELSE"
W_ELSE:
        jsr DOCOL                         ; $453D
        .word W_COMPILE                   ; $4540
        .word W_BRANCH                    ; $4542
        .word W_HERE                      ; $4544
        .word W_LIT                       ; $4546
        .word $0000   ; 0                 ; $4548
        .word W_COMMA                     ; $454A
        .word W_SWAP                      ; $454C
        .word W_HERE                      ; $454E
        .word W_SWAP                      ; $4550
        .word W_STORE                     ; $4552
        .word W_EXIT                      ; $4554
N_BEGIN:
        .word N_ELSE                      ; $4556
        .byte $45   ; IMMEDIATE
        .byte "BEGIN"
W_BEGIN:
        jsr DOCOL                         ; $455E
        .word W_HERE                      ; $4561
        .word W_EXIT                      ; $4563
N_UNTIL:
        .word N_BEGIN                     ; $4565
        .byte $45   ; IMMEDIATE
        .byte "UNTIL"
W_UNTIL:
        jsr DOCOL                         ; $456D
        .word W_COMPILE                   ; $4570
        .word W_0BRANCH                   ; $4572
        .word W_COMMA                     ; $4574
        .word W_EXIT                      ; $4576
N_AGAIN:
        .word N_UNTIL                     ; $4578
        .byte $45   ; IMMEDIATE
        .byte "AGAIN"
W_AGAIN:
        jsr DOCOL                         ; $4580
        .word W_COMPILE                   ; $4583
        .word W_BRANCH                    ; $4585
        .word W_COMMA                     ; $4587
        .word W_EXIT                      ; $4589
N_WHILE:
        .word N_AGAIN                     ; $458B
        .byte $45   ; IMMEDIATE
        .byte "WHILE"
W_WHILE:
        jsr DOCOL                         ; $4593
        .word W_COMPILE                   ; $4596
        .word W_0BRANCH                   ; $4598
        .word W_HERE                      ; $459A
        .word W_LIT                       ; $459C
        .word $0000   ; 0                 ; $459E
        .word W_COMMA                     ; $45A0
        .word W_EXIT                      ; $45A2
N_REPEAT:
        .word N_WHILE                     ; $45A4
        .byte $46   ; IMMEDIATE
        .byte "REPEAT"
W_REPEAT:
        jsr DOCOL                         ; $45AD
        .word W_COMPILE                   ; $45B0
        .word W_BRANCH                    ; $45B2
        .word W_SWAP                      ; $45B4
        .word W_COMMA                     ; $45B6
        .word W_HERE                      ; $45B8
        .word W_SWAP                      ; $45BA
        .word W_STORE                     ; $45BC
        .word W_EXIT                      ; $45BE
N_DO:
        .word N_REPEAT                    ; $45C0
        .byte $42   ; IMMEDIATE
        .byte "DO"
W_DO:
        jsr DOCOL                         ; $45C5
        .word W_COMPILE                   ; $45C8
        .word W_LPDORP                    ; $45CA
        .word W_HERE                      ; $45CC
        .word W_EXIT                      ; $45CE
N_LOOP:
        .word N_DO                        ; $45D0
        .byte $44   ; IMMEDIATE
        .byte "LOOP"
W_LOOP:
        jsr DOCOL                         ; $45D7
        .word W_COMPILE                   ; $45DA
        .word W_LPLOOPRP                  ; $45DC
        .word W_COMMA                     ; $45DE
        .word W_EXIT                      ; $45E0
N_PLUSLOOP:
        .word N_LOOP                      ; $45E2
        .byte $45   ; IMMEDIATE
        .byte "+LOOP"
W_PLUSLOOP:
        jsr DOCOL                         ; $45EA
        .word W_COMPILE                   ; $45ED
        .word W_LPPLUSLOOPRP              ; $45EF
        .word W_COMMA                     ; $45F1
        .word W_EXIT                      ; $45F3
N_BSL:
        .word N_PLUSLOOP                  ; $45F5
        .byte $41   ; IMMEDIATE
        .byte "\"
W_BSL:
        jsr DOCOL                         ; $45F9
        .word W_BLK                       ; $45FC
        .word W_FETCH                     ; $45FE
        .word W_0BRANCH                   ; $4600
        .word B_4618                      ; $4602
        .word W_GTIN                      ; $4604
        .word W_FETCH                     ; $4606
        .word W_LIT                       ; $4608
        .word $003F   ; 63                ; $460A
        .word W_OR                        ; $460C
        .word W_1PLUS                     ; $460E
        .word W_GTIN                      ; $4610
        .word W_STORE                     ; $4612
        .word W_BRANCH                    ; $4614
        .word B_4620                      ; $4616
B_4618:
        .word W_SLEN                      ; $4618
        .word W_FETCH                     ; $461A
        .word W_GTIN                      ; $461C
        .word W_STORE                     ; $461E
B_4620:
        .word W_EXIT                      ; $4620
N_TICK:
        .word N_BSL                       ; $4622
        .byte $01
        .byte "'"
W_TICK:
        jsr DOCOL                         ; $4626
        .word W_BL                        ; $4629
        .word W_WORD                      ; $462B
        .word W_FIND                      ; $462D
        .word W_0EQ                       ; $462F
        .word W_0BRANCH                   ; $4631
        .word B_4637                      ; $4633
        .word W_ERROR                     ; $4635
B_4637:
        .word W_EXIT                      ; $4637
N_LBRCOMPILERBR:
        .word N_TICK                      ; $4639
        .byte $49   ; IMMEDIATE
        .byte "[COMPILE]"
W_LBRCOMPILERBR:
        jsr DOCOL                         ; $4645
        .word W_TICK                      ; $4648
        .word W_COMMA                     ; $464A
        .word W_EXIT                      ; $464C
N_LITERAL:
        .word N_LBRCOMPILERBR             ; $464E
        .byte $47   ; IMMEDIATE
        .byte "LITERAL"
W_LITERAL:
        jsr DOCOL                         ; $4658
        .word W_STATE                     ; $465B
        .word W_FETCH                     ; $465D
        .word W_0BRANCH                   ; $465F
        .word B_4669                      ; $4661
        .word W_COMPILE                   ; $4663
        .word W_LIT                       ; $4665
        .word W_COMMA                     ; $4667
B_4669:
        .word W_EXIT                      ; $4669
N_LBRTICKRBR:
        .word N_LITERAL                   ; $466B
        .byte $43   ; IMMEDIATE
        .byte "[']"
W_LBRTICKRBR:
        jsr DOCOL                         ; $4671
        .word W_TICK                      ; $4674
        .word W_LITERAL                   ; $4676
        .word W_EXIT                      ; $4678
N_CHAR:
        .word N_LBRTICKRBR                ; $467A
        .byte $04
        .byte "CHAR"
W_CHAR:
        jsr DOCOL                         ; $4681
        .word W_BL                        ; $4684
        .word W_WORD                      ; $4686
        .word W_1PLUS                     ; $4688
        .word W_CFETCH                    ; $468A
        .word W_EXIT                      ; $468C
N_LBRCHARRBR:
        .word N_CHAR                      ; $468E
        .byte $46   ; IMMEDIATE
        .byte "[CHAR]"
W_LBRCHARRBR:
        jsr DOCOL                         ; $4697
        .word W_CHAR                      ; $469A
        .word W_LITERAL                   ; $469C
        .word W_EXIT                      ; $469E
N_GTXT:
        .word N_LBRCHARRBR                ; $46A0
        .byte $03
        .byte ">XT"
W_GTXT:
        jsr DOCOL                         ; $46A6
        .word W_2PLUS                     ; $46A9
        .word W_DUP                       ; $46AB
        .word W_CFETCH                    ; $46AD
        .word W_LIT                       ; $46AF
        .word $001F   ; 31                ; $46B1
        .word W_AND                       ; $46B3
        .word W_PLUS                      ; $46B5
        .word W_1PLUS                     ; $46B7
        .word W_EXIT                      ; $46B9
N_RECURSE:
        .word N_GTXT                      ; $46BB
        .byte $47   ; IMMEDIATE
        .byte "RECURSE"
W_RECURSE:
        jsr DOCOL                         ; $46C5
        .word W_LATEST                    ; $46C8
        .word W_FETCH                     ; $46CA
        .word W_GTXT                      ; $46CC
        .word W_COMMA                     ; $46CE
        .word W_EXIT                      ; $46D0
N_DECIMAL:
        .word N_RECURSE                   ; $46D2
        .byte $07
        .byte "DECIMAL"
W_DECIMAL:
        jsr DOCOL                         ; $46DC
        .word W_LIT                       ; $46DF
        .word $000A   ; 10                ; $46E1
        .word W_BASE                      ; $46E3
        .word W_STORE                     ; $46E5
        .word W_EXIT                      ; $46E7
N_HEX:
        .word N_DECIMAL                   ; $46E9
        .byte $03
        .byte "HEX"
W_HEX:
        jsr DOCOL                         ; $46EF
        .word W_LIT                       ; $46F2
        .word $0010   ; 16                ; $46F4
        .word W_BASE                      ; $46F6
        .word W_STORE                     ; $46F8
        .word W_EXIT                      ; $46FA
N_NIP:
        .word N_HEX                       ; $46FC
        .byte $03
        .byte "NIP"
W_NIP:
        jsr DOCOL                         ; $4702
        .word W_SWAP                      ; $4705
        .word W_DROP                      ; $4707
        .word W_EXIT                      ; $4709
N_2DUP:
        .word N_NIP                       ; $470B
        .byte $04
        .byte "2DUP"
W_2DUP:
        jsr DOCOL                         ; $4712
        .word W_OVER                      ; $4715
        .word W_OVER                      ; $4717
        .word W_EXIT                      ; $4719
N_2DROP:
        .word N_2DUP                      ; $471B
        .byte $05
        .byte "2DROP"
W_2DROP:
        jsr DOCOL                         ; $4723
        .word W_DROP                      ; $4726
        .word W_DROP                      ; $4728
        .word W_EXIT                      ; $472A
N_QDUP:
        .word N_2DROP                     ; $472C
        .byte $04
        .byte "?DUP"
W_QDUP:
        jsr DOCOL                         ; $4733
        .word W_DUP                       ; $4736
        .word W_0BRANCH                   ; $4738
        .word B_473E                      ; $473A
        .word W_DUP                       ; $473C
B_473E:
        .word W_EXIT                      ; $473E
N_GT:
        .word N_QDUP                      ; $4740
        .byte $01
        .byte ">"
W_GT:
        jsr DOCOL                         ; $4744
        .word W_SWAP                      ; $4747
        .word W_LT                        ; $4749
        .word W_EXIT                      ; $474B
N_EQ:
        .word N_GT                        ; $474D
        .byte $01
        .byte "="
W_EQ:
        jsr DOCOL                         ; $4751
        .word W_MINUS                     ; $4754
        .word W_0EQ                       ; $4756
        .word W_EXIT                      ; $4758
N_LTGT:
        .word N_EQ                        ; $475A
        .byte $02
        .byte "<>"
W_LTGT:
        jsr DOCOL                         ; $475F
        .word W_EQ                        ; $4762
        .word W_0EQ                       ; $4764
        .word W_EXIT                      ; $4766
N_0GT:
        .word N_LTGT                      ; $4768
        .byte $02
        .byte "0>"
W_0GT:
        jsr DOCOL                         ; $476D
        .word W_LIT                       ; $4770
        .word $0000   ; 0                 ; $4772
        .word W_GT                        ; $4774
        .word W_EXIT                      ; $4776
N_NEGATE:
        .word N_0GT                       ; $4778
        .byte $06
        .byte "NEGATE"
W_NEGATE:
        jsr DOCOL                         ; $4781
        .word W_LIT                       ; $4784
        .word $0000   ; 0                 ; $4786
        .word W_SWAP                      ; $4788
        .word W_MINUS                     ; $478A
        .word W_EXIT                      ; $478C
N_ABS:
        .word N_NEGATE                    ; $478E
        .byte $03
        .byte "ABS"
W_ABS:
        jsr DOCOL                         ; $4794
        .word W_DUP                       ; $4797
        .word W_0LT                       ; $4799
        .word W_0BRANCH                   ; $479B
        .word B_47A1                      ; $479D
        .word W_NEGATE                    ; $479F
B_47A1:
        .word W_EXIT                      ; $47A1
N_MIN:
        .word N_ABS                       ; $47A3
        .byte $03
        .byte "MIN"
W_MIN:
        jsr DOCOL                         ; $47A9
        .word W_2DUP                      ; $47AC
        .word W_LT                        ; $47AE
        .word W_0BRANCH                   ; $47B0
        .word B_47BA                      ; $47B2
        .word W_DROP                      ; $47B4
        .word W_BRANCH                    ; $47B6
        .word B_47BC                      ; $47B8
B_47BA:
        .word W_NIP                       ; $47BA
B_47BC:
        .word W_EXIT                      ; $47BC
N_MAX:
        .word N_MIN                       ; $47BE
        .byte $03
        .byte "MAX"
W_MAX:
        jsr DOCOL                         ; $47C4
        .word W_2DUP                      ; $47C7
        .word W_LT                        ; $47C9
        .word W_0BRANCH                   ; $47CB
        .word B_47D5                      ; $47CD
        .word W_NIP                       ; $47CF
        .word W_BRANCH                    ; $47D1
        .word B_47D7                      ; $47D3
B_47D5:
        .word W_DROP                      ; $47D5
B_47D7:
        .word W_EXIT                      ; $47D7
N_INVERT:
        .word N_MAX                       ; $47D9
        .byte $06
        .byte "INVERT"
W_INVERT:
        jsr DOCOL                         ; $47E2
        .word W_LIT                       ; $47E5
        .word $FFFF   ; -1                ; $47E7
        .word W_XOR                       ; $47E9
        .word W_EXIT                      ; $47EB
N_STAR:
        .word N_INVERT                    ; $47ED
        .byte $01
        .byte "*"
W_STAR:
        jsr DOCOL                         ; $47F1
        .word W_UMSTAR                    ; $47F4
        .word W_DROP                      ; $47F6
        .word W_EXIT                      ; $47F8
N_USLASHMOD:
        .word N_STAR                      ; $47FA
        .byte $05
        .byte "U/MOD"
W_USLASHMOD:
        jsr DOCOL                         ; $4802
        .word W_GTR                       ; $4805
        .word W_LIT                       ; $4807
        .word $0000   ; 0                 ; $4809
        .word W_RGT                       ; $480B
        .word W_UMSLASHMOD                ; $480D
        .word W_EXIT                      ; $480F
N_SLASHMOD:
        .word N_USLASHMOD                 ; $4811
        .byte $04
        .byte "/MOD"
W_SLASHMOD:
        jsr DOCOL                         ; $4818
        .word W_DUP                       ; $481B
        .word W_GTR                       ; $481D
        .word W_2DUP                      ; $481F
        .word W_XOR                       ; $4821
        .word W_0LT                       ; $4823
        .word W_GTR                       ; $4825
        .word W_OVER                      ; $4827
        .word W_0LT                       ; $4829
        .word W_GTR                       ; $482B
        .word W_ABS                       ; $482D
        .word W_SWAP                      ; $482F
        .word W_ABS                       ; $4831
        .word W_SWAP                      ; $4833
        .word W_USLASHMOD                 ; $4835
        .word W_RGT                       ; $4837
        .word W_0BRANCH                   ; $4839
        .word B_4843                      ; $483B
        .word W_SWAP                      ; $483D
        .word W_NEGATE                    ; $483F
        .word W_SWAP                      ; $4841
B_4843:
        .word W_RGT                       ; $4843
        .word W_0BRANCH                   ; $4845
        .word B_485B                      ; $4847
        .word W_NEGATE                    ; $4849
        .word W_OVER                      ; $484B
        .word W_0BRANCH                   ; $484D
        .word B_485B                      ; $484F
        .word W_1MINUS                    ; $4851
        .word W_SWAP                      ; $4853
        .word W_RFETCH                    ; $4855
        .word W_PLUS                      ; $4857
        .word W_SWAP                      ; $4859
B_485B:
        .word W_RGT                       ; $485B
        .word W_DROP                      ; $485D
        .word W_EXIT                      ; $485F
N_SLASH:
        .word N_SLASHMOD                  ; $4861
        .byte $01
        .byte "/"
W_SLASH:
        jsr DOCOL                         ; $4865
        .word W_SLASHMOD                  ; $4868
        .word W_NIP                       ; $486A
        .word W_EXIT                      ; $486C
N_MOD:
        .word N_SLASH                     ; $486E
        .byte $03
        .byte "MOD"
W_MOD:
        jsr DOCOL                         ; $4874
        .word W_SLASHMOD                  ; $4877
        .word W_DROP                      ; $4879
        .word W_EXIT                      ; $487B
N_DEPTH:
        .word N_MOD                       ; $487D
        .byte $05
        .byte "DEPTH"
W_DEPTH:
        jsr DOCOL                         ; $4885
        .word W_SPFETCH                   ; $4888
        .word W_LIT                       ; $488A
        .word $0080   ; 128               ; $488C
        .word W_SWAP                      ; $488E
        .word W_MINUS                     ; $4890
        .word W_2SLASH                    ; $4892
        .word W_EXIT                      ; $4894
N_FILL:
        .word N_DEPTH                     ; $4896
        .byte $04
        .byte "FILL"
W_FILL:
        jsr DOCOL                         ; $489D
        .word W_GTR                       ; $48A0
        .word W_SWAP                      ; $48A2
B_48A4:
        .word W_OVER                      ; $48A4
        .word W_0BRANCH                   ; $48A6
        .word B_48BC                      ; $48A8
        .word W_RFETCH                    ; $48AA
        .word W_OVER                      ; $48AC
        .word W_CSTORE                    ; $48AE
        .word W_1PLUS                     ; $48B0
        .word W_SWAP                      ; $48B2
        .word W_1MINUS                    ; $48B4
        .word W_SWAP                      ; $48B6
        .word W_BRANCH                    ; $48B8
        .word B_48A4                      ; $48BA
B_48BC:
        .word W_2DROP                     ; $48BC
        .word W_RGT                       ; $48BE
        .word W_DROP                      ; $48C0
        .word W_EXIT                      ; $48C2
N_MOVE:
        .word N_FILL                      ; $48C4
        .byte $04
        .byte "MOVE"
W_MOVE:
        jsr DOCOL                         ; $48CB
        .word W_CMOVE                     ; $48CE
        .word W_EXIT                      ; $48D0
N_SPACE:
        .word N_MOVE                      ; $48D2
        .byte $05
        .byte "SPACE"
W_SPACE:
        jsr DOCOL                         ; $48DA
        .word W_BL                        ; $48DD
        .word W_EMIT                      ; $48DF
        .word W_EXIT                      ; $48E1
N_SPACES:
        .word N_SPACE                     ; $48E3
        .byte $06
        .byte "SPACES"
W_SPACES:
        jsr DOCOL                         ; $48EC
        .word W_QDUP                      ; $48EF
        .word W_0BRANCH                   ; $48F1
        .word B_4901                      ; $48F3
        .word W_LIT                       ; $48F5
        .word $0000   ; 0                 ; $48F7
        .word W_LPDORP                    ; $48F9
B_48FB:
        .word W_SPACE                     ; $48FB
        .word W_LPLOOPRP                  ; $48FD
        .word B_48FB                      ; $48FF
B_4901:
        .word W_EXIT                      ; $4901
N_DIGIT:
        .word N_SPACES                    ; $4903
        .byte $05
        .byte "DIGIT"
W_DIGIT:
        jsr DOCOL                         ; $490B
        .word W_DUP                       ; $490E
        .word W_LIT                       ; $4910
        .word $0009   ; 9                 ; $4912
        .word W_GT                        ; $4914
        .word W_0BRANCH                   ; $4916
        .word B_4920                      ; $4918
        .word W_LIT                       ; $491A
        .word $0007   ; 7                 ; $491C
        .word W_PLUS                      ; $491E
B_4920:
        .word W_LIT                       ; $4920
        .word $0030   ; 48                ; $4922
        .word W_PLUS                      ; $4924
        .word W_EXIT                      ; $4926
N_LPUDOTRP:
        .word N_DIGIT                     ; $4928
        .byte $04
        .byte "(U.)"
W_LPUDOTRP:
        jsr DOCOL                         ; $492F
        .word W_BASE                      ; $4932
        .word W_FETCH                     ; $4934
        .word W_USLASHMOD                 ; $4936
        .word W_DUP                       ; $4938
        .word W_0BRANCH                   ; $493A
        .word B_4944                      ; $493C
        .word W_LPUDOTRP                  ; $493E
        .word W_BRANCH                    ; $4940
        .word B_4946                      ; $4942
B_4944:
        .word W_DROP                      ; $4944
B_4946:
        .word W_DIGIT                     ; $4946
        .word W_EMIT                      ; $4948
        .word W_EXIT                      ; $494A
N_UDOT:
        .word N_LPUDOTRP                  ; $494C
        .byte $02
        .byte "U."
W_UDOT:
        jsr DOCOL                         ; $4951
        .word W_LPUDOTRP                  ; $4954
        .word W_SPACE                     ; $4956
        .word W_EXIT                      ; $4958
N_DOT:
        .word N_UDOT                      ; $495A
        .byte $01
        .byte "."
W_DOT:
        jsr DOCOL                         ; $495E
        .word W_DUP                       ; $4961
        .word W_0LT                       ; $4963
        .word W_0BRANCH                   ; $4965
        .word B_4971                      ; $4967
        .word W_LIT                       ; $4969
        .word $002D   ; 45                ; $496B
        .word W_EMIT                      ; $496D
        .word W_NEGATE                    ; $496F
B_4971:
        .word W_UDOT                      ; $4971
        .word W_EXIT                      ; $4973
N_Q:
        .word N_DOT                       ; $4975
        .byte $01
        .byte "?"
W_Q:
        jsr DOCOL                         ; $4979
        .word W_FETCH                     ; $497C
        .word W_DOT                       ; $497E
        .word W_EXIT                      ; $4980
N_DOT2:
        .word N_Q                         ; $4982
        .byte $02
        .byte ".2"
W_DOT2:
        jsr DOCOL                         ; $4987
        .word W_LIT                       ; $498A
        .word $0010   ; 16                ; $498C
        .word W_USLASHMOD                 ; $498E
        .word W_DIGIT                     ; $4990
        .word W_EMIT                      ; $4992
        .word W_DIGIT                     ; $4994
        .word W_EMIT                      ; $4996
        .word W_EXIT                      ; $4998
N_LPDOTQTRP:
        .word N_DOT2                      ; $499A
        .byte $04
        .byte "(.", $22, ")"
W_LPDOTQTRP:
        jsr DOCOL                         ; $49A1
        .word W_RGT                       ; $49A4
        .word W_COUNT                     ; $49A6
        .word W_2DUP                      ; $49A8
        .word W_PLUS                      ; $49AA
        .word W_GTR                       ; $49AC
        .word W_TYPE                      ; $49AE
        .word W_EXIT                      ; $49B0
N_DOTQT:
        .word N_LPDOTQTRP                 ; $49B2
        .byte $42   ; IMMEDIATE
        .byte ".", $22
W_DOTQT:
        jsr DOCOL                         ; $49B7
        .word W_LIT                       ; $49BA
        .word $0022   ; 34                ; $49BC
        .word W_STATE                     ; $49BE
        .word W_FETCH                     ; $49C0
        .word W_0BRANCH                   ; $49C2
        .word B_49D6                      ; $49C4
        .word W_COMPILE                   ; $49C6
        .word W_LPDOTQTRP                 ; $49C8
        .word W_WORD                      ; $49CA
        .word W_CFETCH                    ; $49CC
        .word W_1PLUS                     ; $49CE
        .word W_ALLOT                     ; $49D0
        .word W_BRANCH                    ; $49D2
        .word B_49DC                      ; $49D4
B_49D6:
        .word W_WORD                      ; $49D6
        .word W_COUNT                     ; $49D8
        .word W_TYPE                      ; $49DA
B_49DC:
        .word W_EXIT                      ; $49DC
N_WORDS:
        .word N_DOTQT                     ; $49DE
        .byte $05
        .byte "WORDS"
W_WORDS:
        jsr DOCOL                         ; $49E6
        .word W_LATEST                    ; $49E9
        .word W_FETCH                     ; $49EB
B_49ED:
        .word W_DUP                       ; $49ED
        .word W_0BRANCH                   ; $49EF
        .word B_4A09                      ; $49F1
        .word W_DUP                       ; $49F3
        .word W_2PLUS                     ; $49F5
        .word W_COUNT                     ; $49F7
        .word W_LIT                       ; $49F9
        .word $001F   ; 31                ; $49FB
        .word W_AND                       ; $49FD
        .word W_TYPE                      ; $49FF
        .word W_SPACE                     ; $4A01
        .word W_FETCH                     ; $4A03
        .word W_BRANCH                    ; $4A05
        .word B_49ED                      ; $4A07
B_4A09:
        .word W_DROP                      ; $4A09
        .word W_EXIT                      ; $4A0B
N_FENCE:
        .word N_WORDS                     ; $4A0D
        .byte $05
        .byte "FENCE"
W_FENCE:
        jsr DOVAR                         ; $4A15
        .word $5690                       ; $4A18
N_CREATE:
        .word N_FENCE                     ; $4A1A
        .byte $06
        .byte "CREATE"
W_CREATE:
        jsr DOCOL                         ; $4A23
        .word W_LPCREATERP                ; $4A26
        .word W_LPDODOESRP                ; $4A28
        .word W_COMMACODE                 ; $4A2A
        .word W_LPXTHRP                   ; $4A2C
        .word W_COMMA                     ; $4A2E
        .word W_EXIT                      ; $4A30
N_LPSEMICODERP:
        .word N_CREATE                    ; $4A32
        .byte $07
        .byte "(;CODE)"
W_LPSEMICODERP:
        jsr DOCOL                         ; $4A3C
        .word W_RGT                       ; $4A3F
        .word W_LATEST                    ; $4A41
        .word W_FETCH                     ; $4A43
        .word W_GTXT                      ; $4A45
        .word W_LIT                       ; $4A47
        .word $0003   ; 3                 ; $4A49
        .word W_PLUS                      ; $4A4B
        .word W_STORE                     ; $4A4D
        .word W_EXIT                      ; $4A4F
N_DOESGT:
        .word N_LPSEMICODERP              ; $4A51
        .byte $45   ; IMMEDIATE
        .byte "DOES>"
W_DOESGT:
        jsr DOCOL                         ; $4A59
        .word W_COMPILE                   ; $4A5C
        .word W_LPSEMICODERP              ; $4A5E
        .word W_EXIT                      ; $4A60
N_CELLS:
        .word N_DOESGT                    ; $4A62
        .byte $05
        .byte "CELLS"
W_CELLS:
        jsr DOCOL                         ; $4A6A
        .word W_2STAR                     ; $4A6D
        .word W_EXIT                      ; $4A6F
N_CELLPLUS:
        .word N_CELLS                     ; $4A71
        .byte $05
        .byte "CELL+"
W_CELLPLUS:
        jsr DOCOL                         ; $4A79
        .word W_2PLUS                     ; $4A7C
        .word W_EXIT                      ; $4A7E
N_TRUE:
        .word N_CELLPLUS                  ; $4A80
        .byte $04
        .byte "TRUE"
W_TRUE:
        jsr DOCOL                         ; $4A87
        .word W_LIT                       ; $4A8A
        .word $FFFF   ; -1                ; $4A8C
        .word W_EXIT                      ; $4A8E
N_FALSE:
        .word N_TRUE                      ; $4A90
        .byte $05
        .byte "FALSE"
W_FALSE:
        jsr DOCOL                         ; $4A98
        .word W_LIT                       ; $4A9B
        .word $0000   ; 0                 ; $4A9D
        .word W_EXIT                      ; $4A9F
N_WITHIN:
        .word N_FALSE                     ; $4AA1
        .byte $06
        .byte "WITHIN"
W_WITHIN:
        jsr DOCOL                         ; $4AAA
        .word W_OVER                      ; $4AAD
        .word W_MINUS                     ; $4AAF
        .word W_GTR                       ; $4AB1
        .word W_MINUS                     ; $4AB3
        .word W_RGT                       ; $4AB5
        .word W_ULT                       ; $4AB7
        .word W_EXIT                      ; $4AB9
N_FORGET:
        .word N_WITHIN                    ; $4ABB
        .byte $06
        .byte "FORGET"
W_FORGET:
        jsr DOCOL                         ; $4AC4
        .word W_TICK                      ; $4AC7
        .word W_LATEST                    ; $4AC9
        .word W_FETCH                     ; $4ACB
B_4ACD:
        .word W_2DUP                      ; $4ACD
        .word W_GTXT                      ; $4ACF
        .word W_EQ                        ; $4AD1
        .word W_0EQ                       ; $4AD3
        .word W_0BRANCH                   ; $4AD5
        .word B_4ADF                      ; $4AD7
        .word W_FETCH                     ; $4AD9
        .word W_BRANCH                    ; $4ADB
        .word B_4ACD                      ; $4ADD
B_4ADF:
        .word W_NIP                       ; $4ADF
        .word W_DUP                       ; $4AE1
        .word W_FENCE                     ; $4AE3
        .word W_FETCH                     ; $4AE5
        .word W_ULT                       ; $4AE7
        .word W_OVER                      ; $4AE9
        .word W_LIT                       ; $4AEB
        .word $8000   ; -32768            ; $4AED
        .word W_ULT                       ; $4AEF
        .word W_0EQ                       ; $4AF1
        .word W_OR                        ; $4AF3
        .word W_0BRANCH                   ; $4AF5
        .word B_4B0B                      ; $4AF7
        .word W_DROP                      ; $4AF9
        .word W_LPDOTQTRP                 ; $4AFB
        .byte 9                           ; $4AFD
        .byte "PROTECTED"
        .word W_BRANCH                    ; $4B07
        .word B_4B17                      ; $4B09
B_4B0B:
        .word W_DUP                       ; $4B0B
        .word W_FETCH                     ; $4B0D
        .word W_LATEST                    ; $4B0F
        .word W_STORE                     ; $4B11
        .word W_DP                        ; $4B13
        .word W_STORE                     ; $4B15
B_4B17:
        .word W_EXIT                      ; $4B17
N_BLKBASE:
        .word N_FORGET                    ; $4B19
        .byte $07
        .byte "BLKBASE"
W_BLKBASE:
        jsr DOVAR                         ; $4B23
        .word $0000                       ; $4B26
N_BLKMAX:
        .word N_BLKBASE                   ; $4B28
        .byte $06
        .byte "BLKMAX"
W_BLKMAX:
        jsr DOVAR                         ; $4B31
        .word $0000                       ; $4B34
N_CURTRK:
        .word N_BLKMAX                    ; $4B36
        .byte $06
        .byte "CURTRK"
W_CURTRK:
        jsr DOVAR                         ; $4B3F
        .word $FFFF                       ; $4B42
N_DIRTY:
        .word N_CURTRK                    ; $4B44
        .byte $05
        .byte "DIRTY"
W_DIRTY:
        jsr DOVAR                         ; $4B4C
        .word $0000                       ; $4B4F
N_SCR:
        .word N_DIRTY                     ; $4B51
        .byte $03
        .byte "SCR"
W_SCR:
        jsr DOVAR                         ; $4B57
        .word $0000                       ; $4B5A
N_ENT:
        .word N_SCR                       ; $4B5C
        .byte $03
        .byte "ENT"
W_ENT:
        jsr DOVAR                         ; $4B62
        .word $0000                       ; $4B65
N_NTRK:
        .word N_ENT                       ; $4B67
        .byte $04
        .byte "NTRK"
W_NTRK:
        jsr DOVAR                         ; $4B6E
        .word $0000                       ; $4B71
N_STRK:
        .word N_NTRK                      ; $4B73
        .byte $04
        .byte "STRK"
W_STRK:
        jsr DOVAR                         ; $4B7A
        .word $0000                       ; $4B7D
N_NB:
        .word N_STRK                      ; $4B7F
        .byte $02
        .byte "NB"
W_NB:
        jsr DOVAR                         ; $4B84
        .word $0000                       ; $4B87
        .word $4105                       ; $4B89
        .word $4C4C                       ; $4B8B
        .word $544F                       ; $4B8D
        .word $0000                       ; $4B8F
        .word $0000                       ; $4B91
        .word $0000                       ; $4B93
        .word $0000                       ; $4B95
        .word $0000                       ; $4B97
N_USED:
        .word N_NB                        ; $4B99
        .byte $04
        .byte "USED"
W_USED:
        jsr DOVAR                         ; $4BA0
        .word $0000                       ; $4BA3
        .word $4105                       ; $4BA5
        .word $4C4C                       ; $4BA7
        .word $544F                       ; $4BA9
        .word $0000                       ; $4BAB
        .word $0000                       ; $4BAD
        .word $0000                       ; $4BAF
        .word $0000                       ; $4BB1
        .word $0000                       ; $4BB3
        .word $0000                       ; $4BB5
        .word $0000                       ; $4BB7
        .word $0000                       ; $4BB9
        .word $0000                       ; $4BBB
        .word $0000                       ; $4BBD
        .word $0000                       ; $4BBF
        .word $0000                       ; $4BC1
        .word $0000                       ; $4BC3
        .word $0000                       ; $4BC5
        .word $0000                       ; $4BC7
        .word $0000                       ; $4BC9
        .word $0000                       ; $4BCB
N_FLUSH:
        .word N_USED                      ; $4BCD
        .byte $05
        .byte "FLUSH"
W_FLUSH:
        jsr DOCOL                         ; $4BD5
        .word W_DIRTY                     ; $4BD8
        .word W_FETCH                     ; $4BDA
        .word W_0BRANCH                   ; $4BDC
        .word B_4BF4                      ; $4BDE
        .word W_CURTRK                    ; $4BE0
        .word W_FETCH                     ; $4BE2
        .word W_BLKBASE                   ; $4BE4
        .word W_FETCH                     ; $4BE6
        .word W_PLUS                      ; $4BE8
        .word W_TRKSTORE                  ; $4BEA
        .word W_LIT                       ; $4BEC
        .word $0000   ; 0                 ; $4BEE
        .word W_DIRTY                     ; $4BF0
        .word W_STORE                     ; $4BF2
B_4BF4:
        .word W_EXIT                      ; $4BF4
N_EMPTYMINUSBUFFERS:
        .word N_FLUSH                     ; $4BF6
        .byte $0D
        .byte "EMPTY-BUFFERS"
W_EMPTYMINUSBUFFERS:
        jsr DOCOL                         ; $4C06
        .word W_LIT                       ; $4C09
        .word $0000   ; 0                 ; $4C0B
        .word W_DIRTY                     ; $4C0D
        .word W_STORE                     ; $4C0F
        .word W_LIT                       ; $4C11
        .word $FFFF   ; -1                ; $4C13
        .word W_CURTRK                    ; $4C15
        .word W_STORE                     ; $4C17
        .word W_EXIT                      ; $4C19
N_UPDATE:
        .word N_EMPTYMINUSBUFFERS         ; $4C1B
        .byte $06
        .byte "UPDATE"
W_UPDATE:
        jsr DOCOL                         ; $4C24
        .word W_LIT                       ; $4C27
        .word $0001   ; 1                 ; $4C29
        .word W_DIRTY                     ; $4C2B
        .word W_STORE                     ; $4C2D
        .word W_EXIT                      ; $4C2F
N_BLOCK:
        .word N_UPDATE                    ; $4C31
        .byte $05
        .byte "BLOCK"
W_BLOCK:
        jsr DOCOL                         ; $4C39
        .word W_DUP                       ; $4C3C
        .word W_BLKMAX                    ; $4C3E
        .word W_FETCH                     ; $4C40
        .word W_ULT                       ; $4C42
        .word W_0EQ                       ; $4C44
        .word W_0BRANCH                   ; $4C46
        .word B_4C57                      ; $4C48
        .word W_LPDOTQTRP                 ; $4C4A
        .byte 8                           ; $4C4C
        .byte "NO BLOCK"
        .word W_ABORT                     ; $4C55
B_4C57:
        .word W_DUP                       ; $4C57
        .word W_2SLASH                    ; $4C59
        .word W_DUP                       ; $4C5B
        .word W_CURTRK                    ; $4C5D
        .word W_FETCH                     ; $4C5F
        .word W_EQ                        ; $4C61
        .word W_0BRANCH                   ; $4C63
        .word B_4C6D                      ; $4C65
        .word W_DROP                      ; $4C67
        .word W_BRANCH                    ; $4C69
        .word B_4C7D                      ; $4C6B
B_4C6D:
        .word W_FLUSH                     ; $4C6D
        .word W_DUP                       ; $4C6F
        .word W_BLKBASE                   ; $4C71
        .word W_FETCH                     ; $4C73
        .word W_PLUS                      ; $4C75
        .word W_TRKFETCH                  ; $4C77
        .word W_CURTRK                    ; $4C79
        .word W_STORE                     ; $4C7B
B_4C7D:
        .word W_LIT                       ; $4C7D
        .word $0001   ; 1                 ; $4C7F
        .word W_AND                       ; $4C81
        .word W_0BRANCH                   ; $4C83
        .word B_4C8F                      ; $4C85
        .word W_LIT                       ; $4C87
        .word $0400   ; 1024              ; $4C89
        .word W_BRANCH                    ; $4C8B
        .word B_4C93                      ; $4C8D
B_4C8F:
        .word W_LIT                       ; $4C8F
        .word $0000   ; 0                 ; $4C91
B_4C93:
        .word W_TRKBUF                    ; $4C93
        .word W_PLUS                      ; $4C95
        .word W_EXIT                      ; $4C97
N_BCD:
        .word N_BLOCK                     ; $4C99
        .byte $03
        .byte "BCD"
W_BCD:
        jsr DOCOL                         ; $4C9F
        .word W_LIT                       ; $4CA2
        .word $0010   ; 16                ; $4CA4
        .word W_USLASHMOD                 ; $4CA6
        .word W_LIT                       ; $4CA8
        .word $000A   ; 10                ; $4CAA
        .word W_STAR                      ; $4CAC
        .word W_PLUS                      ; $4CAE
        .word W_EXIT                      ; $4CB0
N_GTBCD:
        .word N_BCD                       ; $4CB2
        .byte $04
        .byte ">BCD"
W_GTBCD:
        jsr DOCOL                         ; $4CB9
        .word W_LIT                       ; $4CBC
        .word $000A   ; 10                ; $4CBE
        .word W_USLASHMOD                 ; $4CC0
        .word W_LIT                       ; $4CC2
        .word $0010   ; 16                ; $4CC4
        .word W_STAR                      ; $4CC6
        .word W_PLUS                      ; $4CC8
        .word W_EXIT                      ; $4CCA
N_PADNAME:
        .word N_GTBCD                     ; $4CCC
        .byte $07
        .byte "PADNAME"
W_PADNAME:
        jsr DOCOL                         ; $4CD6
        .word W_NB                        ; $4CD9
        .word W_LIT                       ; $4CDB
        .word $0010   ; 16                ; $4CDD
        .word W_BL                        ; $4CDF
        .word W_FILL                      ; $4CE1
        .word W_COUNT                     ; $4CE3
        .word W_LIT                       ; $4CE5
        .word $000E   ; 14                ; $4CE7
        .word W_MIN                       ; $4CE9
        .word W_NB                        ; $4CEB
        .word W_SWAP                      ; $4CED
        .word W_CMOVE                     ; $4CEF
        .word W_EXIT                      ; $4CF1
N_SAMEQ:
        .word N_PADNAME                   ; $4CF3
        .byte $05
        .byte "SAME?"
W_SAMEQ:
        jsr DOCOL                         ; $4CFB
B_4CFE:
        .word W_DUP                       ; $4CFE
        .word W_0BRANCH                   ; $4D00
        .word B_4D30                      ; $4D02
        .word W_GTR                       ; $4D04
        .word W_OVER                      ; $4D06
        .word W_CFETCH                    ; $4D08
        .word W_OVER                      ; $4D0A
        .word W_CFETCH                    ; $4D0C
        .word W_MINUS                     ; $4D0E
        .word W_0BRANCH                   ; $4D10
        .word B_4D20                      ; $4D12
        .word W_RGT                       ; $4D14
        .word W_DROP                      ; $4D16
        .word W_2DROP                     ; $4D18
        .word W_LIT                       ; $4D1A
        .word $0000   ; 0                 ; $4D1C
        .word W_EXIT                      ; $4D1E
B_4D20:
        .word W_1PLUS                     ; $4D20
        .word W_SWAP                      ; $4D22
        .word W_1PLUS                     ; $4D24
        .word W_SWAP                      ; $4D26
        .word W_RGT                       ; $4D28
        .word W_1MINUS                    ; $4D2A
        .word W_BRANCH                    ; $4D2C
        .word B_4CFE                      ; $4D2E
B_4D30:
        .word W_DROP                      ; $4D30
        .word W_2DROP                     ; $4D32
        .word W_LIT                       ; $4D34
        .word $0001   ; 1                 ; $4D36
        .word W_EXIT                      ; $4D38
N_FINDNAME:
        .word N_SAMEQ                     ; $4D3A
        .byte $08
        .byte "FINDNAME"
W_FINDNAME:
        jsr DOCOL                         ; $4D45
        .word W_LIT                       ; $4D48
        .word $0000   ; 0                 ; $4D4A
        .word W_ENT                       ; $4D4C
        .word W_STORE                     ; $4D4E
        .word W_LIT                       ; $4D50
        .word $0020   ; 32                ; $4D52
        .word W_LIT                       ; $4D54
        .word $0000   ; 0                 ; $4D56
        .word W_LPDORP                    ; $4D58
B_4D5A:
        .word W_DIRBUF                    ; $4D5A
        .word W_I                         ; $4D5C
        .word W_LIT                       ; $4D5E
        .word $0010   ; 16                ; $4D60
        .word W_STAR                      ; $4D62
        .word W_PLUS                      ; $4D64
        .word W_DUP                       ; $4D66
        .word W_NB                        ; $4D68
        .word W_SWAP                      ; $4D6A
        .word W_LIT                       ; $4D6C
        .word $000E   ; 14                ; $4D6E
        .word W_SAMEQ                     ; $4D70
        .word W_0BRANCH                   ; $4D72
        .word B_4D7E                      ; $4D74
        .word W_ENT                       ; $4D76
        .word W_STORE                     ; $4D78
        .word W_BRANCH                    ; $4D7A
        .word B_4D80                      ; $4D7C
B_4D7E:
        .word W_DROP                      ; $4D7E
B_4D80:
        .word W_LPLOOPRP                  ; $4D80
        .word B_4D5A                      ; $4D82
        .word W_ENT                       ; $4D84
        .word W_FETCH                     ; $4D86
        .word W_EXIT                      ; $4D88
N_USE:
        .word N_FINDNAME                  ; $4D8A
        .byte $03
        .byte "USE"
W_USE:
        jsr DOCOL                         ; $4D90
        .word W_FLUSH                     ; $4D93
        .word W_DIRFETCH                  ; $4D95
        .word W_BL                        ; $4D97
        .word W_WORD                      ; $4D99
        .word W_PADNAME                   ; $4D9B
        .word W_FINDNAME                  ; $4D9D
        .word W_0EQ                       ; $4D9F
        .word W_0BRANCH                   ; $4DA1
        .word B_4DB1                      ; $4DA3
        .word W_LPDOTQTRP                 ; $4DA5
        .byte 7                           ; $4DA7
        .byte "NO FILE"
        .word W_ABORT                     ; $4DAF
B_4DB1:
        .word W_ENT                       ; $4DB1
        .word W_FETCH                     ; $4DB3
        .word W_LIT                       ; $4DB5
        .word $000E   ; 14                ; $4DB7
        .word W_PLUS                      ; $4DB9
        .word W_CFETCH                    ; $4DBB
        .word W_BCD                       ; $4DBD
        .word W_DUP                       ; $4DBF
        .word W_BLKBASE                   ; $4DC1
        .word W_STORE                     ; $4DC3
        .word W_ENT                       ; $4DC5
        .word W_FETCH                     ; $4DC7
        .word W_LIT                       ; $4DC9
        .word $000F   ; 15                ; $4DCB
        .word W_PLUS                      ; $4DCD
        .word W_CFETCH                    ; $4DCF
        .word W_BCD                       ; $4DD1
        .word W_SWAP                      ; $4DD3
        .word W_MINUS                     ; $4DD5
        .word W_1PLUS                     ; $4DD7
        .word W_2STAR                     ; $4DD9
        .word W_BLKMAX                    ; $4DDB
        .word W_STORE                     ; $4DDD
        .word W_EMPTYMINUSBUFFERS         ; $4DDF
        .word W_EXIT                      ; $4DE1
N_DIR:
        .word N_USE                       ; $4DE3
        .byte $03
        .byte "DIR"
W_DIR:
        jsr DOCOL                         ; $4DE9
        .word W_DIRFETCH                  ; $4DEC
        .word W_LIT                       ; $4DEE
        .word $0020   ; 32                ; $4DF0
        .word W_LIT                       ; $4DF2
        .word $0000   ; 0                 ; $4DF4
        .word W_LPDORP                    ; $4DF6
B_4DF8:
        .word W_DIRBUF                    ; $4DF8
        .word W_I                         ; $4DFA
        .word W_LIT                       ; $4DFC
        .word $0010   ; 16                ; $4DFE
        .word W_STAR                      ; $4E00
        .word W_PLUS                      ; $4E02
        .word W_DUP                       ; $4E04
        .word W_CFETCH                    ; $4E06
        .word W_LIT                       ; $4E08
        .word $0023   ; 35                ; $4E0A
        .word W_EQ                        ; $4E0C
        .word W_0EQ                       ; $4E0E
        .word W_0BRANCH                   ; $4E10
        .word B_4E3E                      ; $4E12
        .word W_CR                        ; $4E14
        .word W_DUP                       ; $4E16
        .word W_LIT                       ; $4E18
        .word $000E   ; 14                ; $4E1A
        .word W_TYPE                      ; $4E1C
        .word W_SPACE                     ; $4E1E
        .word W_DUP                       ; $4E20
        .word W_LIT                       ; $4E22
        .word $000E   ; 14                ; $4E24
        .word W_PLUS                      ; $4E26
        .word W_CFETCH                    ; $4E28
        .word W_DOT2                      ; $4E2A
        .word W_LPDOTQTRP                 ; $4E2C
        .byte 1                           ; $4E2E
        .byte "-"
        .word W_LIT                       ; $4E30
        .word $000F   ; 15                ; $4E32
        .word W_PLUS                      ; $4E34
        .word W_CFETCH                    ; $4E36
        .word W_DOT2                      ; $4E38
        .word W_BRANCH                    ; $4E3A
        .word B_4E40                      ; $4E3C
B_4E3E:
        .word W_DROP                      ; $4E3E
B_4E40:
        .word W_LPLOOPRP                  ; $4E40
        .word B_4DF8                      ; $4E42
        .word W_CR                        ; $4E44
        .word W_EXIT                      ; $4E46
N_MARK:
        .word N_DIR                       ; $4E48
        .byte $04
        .byte "MARK"
W_MARK:
        jsr DOCOL                         ; $4E4F
        .word W_LIT                       ; $4E52
        .word $0027   ; 39                ; $4E54
        .word W_MIN                       ; $4E56
        .word W_1PLUS                     ; $4E58
        .word W_SWAP                      ; $4E5A
        .word W_LPDORP                    ; $4E5C
B_4E5E:
        .word W_LIT                       ; $4E5E
        .word $0001   ; 1                 ; $4E60
        .word W_USED                      ; $4E62
        .word W_I                         ; $4E64
        .word W_PLUS                      ; $4E66
        .word W_CSTORE                    ; $4E68
        .word W_LPLOOPRP                  ; $4E6A
        .word B_4E5E                      ; $4E6C
        .word W_EXIT                      ; $4E6E
N_SCANDIR:
        .word N_MARK                      ; $4E70
        .byte $07
        .byte "SCANDIR"
W_SCANDIR:
        jsr DOCOL                         ; $4E7A
        .word W_USED                      ; $4E7D
        .word W_LIT                       ; $4E7F
        .word $0028   ; 40                ; $4E81
        .word W_LIT                       ; $4E83
        .word $0000   ; 0                 ; $4E85
        .word W_FILL                      ; $4E87
        .word W_LIT                       ; $4E89
        .word $0001   ; 1                 ; $4E8B
        .word W_USED                      ; $4E8D
        .word W_CSTORE                    ; $4E8F
        .word W_LIT                       ; $4E91
        .word $0001   ; 1                 ; $4E93
        .word W_USED                      ; $4E95
        .word W_LIT                       ; $4E97
        .word $000C   ; 12                ; $4E99
        .word W_PLUS                      ; $4E9B
        .word W_CSTORE                    ; $4E9D
        .word W_LIT                       ; $4E9F
        .word $0020   ; 32                ; $4EA1
        .word W_LIT                       ; $4EA3
        .word $0000   ; 0                 ; $4EA5
        .word W_LPDORP                    ; $4EA7
B_4EA9:
        .word W_DIRBUF                    ; $4EA9
        .word W_I                         ; $4EAB
        .word W_LIT                       ; $4EAD
        .word $0010   ; 16                ; $4EAF
        .word W_STAR                      ; $4EB1
        .word W_PLUS                      ; $4EB3
        .word W_DUP                       ; $4EB5
        .word W_CFETCH                    ; $4EB7
        .word W_LIT                       ; $4EB9
        .word $0023   ; 35                ; $4EBB
        .word W_EQ                        ; $4EBD
        .word W_0EQ                       ; $4EBF
        .word W_0BRANCH                   ; $4EC1
        .word B_4EE3                      ; $4EC3
        .word W_DUP                       ; $4EC5
        .word W_LIT                       ; $4EC7
        .word $000E   ; 14                ; $4EC9
        .word W_PLUS                      ; $4ECB
        .word W_CFETCH                    ; $4ECD
        .word W_BCD                       ; $4ECF
        .word W_SWAP                      ; $4ED1
        .word W_LIT                       ; $4ED3
        .word $000F   ; 15                ; $4ED5
        .word W_PLUS                      ; $4ED7
        .word W_CFETCH                    ; $4ED9
        .word W_BCD                       ; $4EDB
        .word W_MARK                      ; $4EDD
        .word W_BRANCH                    ; $4EDF
        .word B_4EE5                      ; $4EE1
B_4EE3:
        .word W_DROP                      ; $4EE3
B_4EE5:
        .word W_LPLOOPRP                  ; $4EE5
        .word B_4EA9                      ; $4EE7
        .word W_EXIT                      ; $4EE9
N_FREEQ:
        .word N_SCANDIR                   ; $4EEB
        .byte $05
        .byte "FREE?"
W_FREEQ:
        jsr DOCOL                         ; $4EF3
        .word W_LIT                       ; $4EF6
        .word $0000   ; 0                 ; $4EF8
        .word W_SWAP                      ; $4EFA
        .word W_LIT                       ; $4EFC
        .word $0000   ; 0                 ; $4EFE
        .word W_LPDORP                    ; $4F00
B_4F02:
        .word W_OVER                      ; $4F02
        .word W_I                         ; $4F04
        .word W_PLUS                      ; $4F06
        .word W_USED                      ; $4F08
        .word W_PLUS                      ; $4F0A
        .word W_CFETCH                    ; $4F0C
        .word W_OR                        ; $4F0E
        .word W_LPLOOPRP                  ; $4F10
        .word B_4F02                      ; $4F12
        .word W_SWAP                      ; $4F14
        .word W_DROP                      ; $4F16
        .word W_0EQ                       ; $4F18
        .word W_EXIT                      ; $4F1A
N_FINDRUN:
        .word N_FREEQ                     ; $4F1C
        .byte $07
        .byte "FINDRUN"
W_FINDRUN:
        jsr DOCOL                         ; $4F26
        .word W_LIT                       ; $4F29
        .word $0001   ; 1                 ; $4F2B
B_4F2D:
        .word W_2DUP                      ; $4F2D
        .word W_PLUS                      ; $4F2F
        .word W_LIT                       ; $4F31
        .word $0029   ; 41                ; $4F33
        .word W_ULT                       ; $4F35
        .word W_0EQ                       ; $4F37
        .word W_0BRANCH                   ; $4F39
        .word B_4F45                      ; $4F3B
        .word W_2DROP                     ; $4F3D
        .word W_LIT                       ; $4F3F
        .word $0000   ; 0                 ; $4F41
        .word W_EXIT                      ; $4F43
B_4F45:
        .word W_2DUP                      ; $4F45
        .word W_SWAP                      ; $4F47
        .word W_FREEQ                     ; $4F49
        .word W_0BRANCH                   ; $4F4B
        .word B_4F53                      ; $4F4D
        .word W_NIP                       ; $4F4F
        .word W_EXIT                      ; $4F51
B_4F53:
        .word W_1PLUS                     ; $4F53
        .word W_LIT                       ; $4F55
        .word $0000   ; 0                 ; $4F57
        .word W_0BRANCH                   ; $4F59
        .word B_4F2D                      ; $4F5B
        .word W_EXIT                      ; $4F5D
N_FINDENT:
        .word N_FINDRUN                   ; $4F5F
        .byte $07
        .byte "FINDENT"
W_FINDENT:
        jsr DOCOL                         ; $4F69
        .word W_LIT                       ; $4F6C
        .word $0000   ; 0                 ; $4F6E
        .word W_ENT                       ; $4F70
        .word W_STORE                     ; $4F72
        .word W_LIT                       ; $4F74
        .word $0020   ; 32                ; $4F76
        .word W_LIT                       ; $4F78
        .word $0000   ; 0                 ; $4F7A
        .word W_LPDORP                    ; $4F7C
B_4F7E:
        .word W_DIRBUF                    ; $4F7E
        .word W_I                         ; $4F80
        .word W_LIT                       ; $4F82
        .word $0010   ; 16                ; $4F84
        .word W_STAR                      ; $4F86
        .word W_PLUS                      ; $4F88
        .word W_DUP                       ; $4F8A
        .word W_CFETCH                    ; $4F8C
        .word W_LIT                       ; $4F8E
        .word $0023   ; 35                ; $4F90
        .word W_EQ                        ; $4F92
        .word W_ENT                       ; $4F94
        .word W_FETCH                     ; $4F96
        .word W_0EQ                       ; $4F98
        .word W_AND                       ; $4F9A
        .word W_0BRANCH                   ; $4F9C
        .word B_4FA8                      ; $4F9E
        .word W_ENT                       ; $4FA0
        .word W_STORE                     ; $4FA2
        .word W_BRANCH                    ; $4FA4
        .word B_4FAA                      ; $4FA6
B_4FA8:
        .word W_DROP                      ; $4FA8
B_4FAA:
        .word W_LPLOOPRP                  ; $4FAA
        .word B_4F7E                      ; $4FAC
        .word W_ENT                       ; $4FAE
        .word W_FETCH                     ; $4FB0
        .word W_EXIT                      ; $4FB2
N_MAKE:
        .word N_FINDENT                   ; $4FB4
        .byte $04
        .byte "MAKE"
W_MAKE:
        jsr DOCOL                         ; $4FBB
        .word W_DEPTH                     ; $4FBE
        .word W_0EQ                       ; $4FC0
        .word W_0BRANCH                   ; $4FC2
        .word B_4FDD                      ; $4FC4
        .word W_LPDOTQTRP                 ; $4FC6
        .byte 18                          ; $4FC8
        .byte "USAGE: n MAKE name"
        .word W_ABORT                     ; $4FDB
B_4FDD:
        .word W_DUP                       ; $4FDD
        .word W_0EQ                       ; $4FDF
        .word W_0BRANCH                   ; $4FE1
        .word B_4FEC                      ; $4FE3
        .word W_LPDOTQTRP                 ; $4FE5
        .byte 2                           ; $4FE7
        .byte "N?"
        .word W_ABORT                     ; $4FEA
B_4FEC:
        .word W_FLUSH                     ; $4FEC
        .word W_DIRFETCH                  ; $4FEE
        .word W_BL                        ; $4FF0
        .word W_WORD                      ; $4FF2
        .word W_PADNAME                   ; $4FF4
        .word W_DUP                       ; $4FF6
        .word W_NTRK                      ; $4FF8
        .word W_STORE                     ; $4FFA
        .word W_FINDNAME                  ; $4FFC
        .word W_0BRANCH                   ; $4FFE
        .word B_500D                      ; $5000
        .word W_LPDOTQTRP                 ; $5002
        .byte 6                           ; $5004
        .byte "EXISTS"
        .word W_ABORT                     ; $500B
B_500D:
        .word W_SCANDIR                   ; $500D
        .word W_FINDRUN                   ; $500F
        .word W_QDUP                      ; $5011
        .word W_0EQ                       ; $5013
        .word W_0BRANCH                   ; $5015
        .word B_5025                      ; $5017
        .word W_LPDOTQTRP                 ; $5019
        .byte 7                           ; $501B
        .byte "NO ROOM"
        .word W_ABORT                     ; $5023
B_5025:
        .word W_STRK                      ; $5025
        .word W_STORE                     ; $5027
        .word W_FINDENT                   ; $5029
        .word W_QDUP                      ; $502B
        .word W_0EQ                       ; $502D
        .word W_0BRANCH                   ; $502F
        .word B_5040                      ; $5031
        .word W_LPDOTQTRP                 ; $5033
        .byte 8                           ; $5035
        .byte "DIR FULL"
        .word W_ABORT                     ; $503E
B_5040:
        .word W_GTR                       ; $5040
        .word W_NB                        ; $5042
        .word W_RFETCH                    ; $5044
        .word W_LIT                       ; $5046
        .word $000E   ; 14                ; $5048
        .word W_CMOVE                     ; $504A
        .word W_STRK                      ; $504C
        .word W_FETCH                     ; $504E
        .word W_GTBCD                     ; $5050
        .word W_RFETCH                    ; $5052
        .word W_LIT                       ; $5054
        .word $000E   ; 14                ; $5056
        .word W_PLUS                      ; $5058
        .word W_CSTORE                    ; $505A
        .word W_STRK                      ; $505C
        .word W_FETCH                     ; $505E
        .word W_NTRK                      ; $5060
        .word W_FETCH                     ; $5062
        .word W_PLUS                      ; $5064
        .word W_1MINUS                    ; $5066
        .word W_GTBCD                     ; $5068
        .word W_RFETCH                    ; $506A
        .word W_LIT                       ; $506C
        .word $000F   ; 15                ; $506E
        .word W_PLUS                      ; $5070
        .word W_CSTORE                    ; $5072
        .word W_RGT                       ; $5074
        .word W_DROP                      ; $5076
        .word W_DIRSTORE                  ; $5078
        .word W_TRKBUF                    ; $507A
        .word W_LIT                       ; $507C
        .word $0800   ; 2048              ; $507E
        .word W_BL                        ; $5080
        .word W_FILL                      ; $5082
        .word W_NTRK                      ; $5084
        .word W_FETCH                     ; $5086
        .word W_LIT                       ; $5088
        .word $0000   ; 0                 ; $508A
        .word W_LPDORP                    ; $508C
B_508E:
        .word W_STRK                      ; $508E
        .word W_FETCH                     ; $5090
        .word W_I                         ; $5092
        .word W_PLUS                      ; $5094
        .word W_TRKSTORE                  ; $5096
        .word W_LPLOOPRP                  ; $5098
        .word B_508E                      ; $509A
        .word W_EMPTYMINUSBUFFERS         ; $509C
        .word W_EXIT                      ; $509E
N_LIST:
        .word N_MAKE                      ; $50A0
        .byte $04
        .byte "LIST"
W_LIST:
        jsr DOCOL                         ; $50A7
        .word W_DUP                       ; $50AA
        .word W_SCR                       ; $50AC
        .word W_STORE                     ; $50AE
        .word W_BLOCK                     ; $50B0
        .word W_CR                        ; $50B2
        .word W_LIT                       ; $50B4
        .word $0010   ; 16                ; $50B6
        .word W_LIT                       ; $50B8
        .word $0000   ; 0                 ; $50BA
        .word W_LPDORP                    ; $50BC
B_50BE:
        .word W_I                         ; $50BE
        .word W_DUP                       ; $50C0
        .word W_LIT                       ; $50C2
        .word $000A   ; 10                ; $50C4
        .word W_LT                        ; $50C6
        .word W_0BRANCH                   ; $50C8
        .word B_50CE                      ; $50CA
        .word W_SPACE                     ; $50CC
B_50CE:
        .word W_DOT                       ; $50CE
        .word W_DUP                       ; $50D0
        .word W_I                         ; $50D2
        .word W_LIT                       ; $50D4
        .word $0040   ; 64                ; $50D6
        .word W_STAR                      ; $50D8
        .word W_PLUS                      ; $50DA
        .word W_LIT                       ; $50DC
        .word $0040   ; 64                ; $50DE
        .word W_TYPET                     ; $50E0  (SD.S) was W_TYPE: no trailing spaces
        .word W_CR                        ; $50E2
        .word W_LPLOOPRP                  ; $50E4
        .word B_50BE                      ; $50E6
        .word W_DROP                      ; $50E8
        .word W_EXIT                      ; $50EA
N_LDADDR:
        .word N_LIST                      ; $50EC
        .byte $06
        .byte "LDADDR"
W_LDADDR:
        jsr DOCOL                         ; $50F5
        .word W_LDD                       ; $50F8
        .word W_FETCH                     ; $50FA
        .word W_LIT                       ; $50FC
        .word $0400   ; 1024              ; $50FE
        .word W_STAR                      ; $5100
        .word W_LIT                       ; $5102
        .word $6400   ; 25600             ; $5104
        .word W_PLUS                      ; $5106
        .word W_EXIT                      ; $5108
N_LOAD:
        .word N_LDADDR                    ; $510A
        .byte $04
        .byte "LOAD"
W_LOAD:
        jsr DOCOL                         ; $5111
        .word W_LDD                       ; $5114
        .word W_FETCH                     ; $5116
        .word W_LIT                       ; $5118
        .word $0003   ; 3                 ; $511A
        .word W_LT                        ; $511C
        .word W_0EQ                       ; $511E
        .word W_0BRANCH                   ; $5120
        .word B_512D                      ; $5122
        .word W_LPDOTQTRP                 ; $5124
        .byte 4                           ; $5126
        .byte "DEEP"
        .word W_ABORT                     ; $512B
B_512D:
        .word W_SRC                       ; $512D
        .word W_FETCH                     ; $512F
        .word W_GTR                       ; $5131
        .word W_SLEN                      ; $5133
        .word W_FETCH                     ; $5135
        .word W_GTR                       ; $5137
        .word W_GTIN                      ; $5139
        .word W_FETCH                     ; $513B
        .word W_GTR                       ; $513D
        .word W_BLK                       ; $513F
        .word W_FETCH                     ; $5141
        .word W_GTR                       ; $5143
        .word W_DUP                       ; $5145
        .word W_BLK                       ; $5147
        .word W_STORE                     ; $5149
        .word W_BLOCK                     ; $514B
        .word W_LDADDR                    ; $514D
        .word W_LIT                       ; $514F
        .word $0400   ; 1024              ; $5151
        .word W_CMOVE                     ; $5153
        .word W_LDADDR                    ; $5155
        .word W_SRC                       ; $5157
        .word W_STORE                     ; $5159
        .word W_LIT                       ; $515B
        .word $0400   ; 1024              ; $515D
        .word W_SLEN                      ; $515F
        .word W_STORE                     ; $5161
        .word W_LIT                       ; $5163
        .word $0000   ; 0                 ; $5165
        .word W_GTIN                      ; $5167
        .word W_STORE                     ; $5169
        .word W_LIT                       ; $516B
        .word $0001   ; 1                 ; $516D
        .word W_LDD                       ; $516F
        .word W_PLUSSTORE                 ; $5171
        .word W_INTERPRET                 ; $5173
        .word W_LIT                       ; $5175
        .word $FFFF   ; -1                ; $5177
        .word W_LDD                       ; $5179
        .word W_PLUSSTORE                 ; $517B
        .word W_RGT                       ; $517D
        .word W_BLK                       ; $517F
        .word W_STORE                     ; $5181
        .word W_RGT                       ; $5183
        .word W_GTIN                      ; $5185
        .word W_STORE                     ; $5187
        .word W_RGT                       ; $5189
        .word W_SLEN                      ; $518B
        .word W_STORE                     ; $518D
        .word W_RGT                       ; $518F
        .word W_SRC                       ; $5191
        .word W_STORE                     ; $5193
        .word W_EXIT                      ; $5195
N_CUR:
        .word N_LOAD                      ; $5197
        .byte $03
        .byte "CUR"
W_CUR:
        jsr DOVAR                         ; $519D
        .word $0000                       ; $51A0
N_CMASK:
        .word N_CUR                       ; $51A2
        .byte $05
        .byte "CMASK"
W_CMASK:
        jsr DOVAR                         ; $51AA
        .word $0080                       ; $51AD
N_INS:
        .word N_CMASK                     ; $51AF
        .byte $03
        .byte "INS"
W_INS:
        jsr DOVAR                         ; $51B5
        .word $0000                       ; $51B8
N_VDUF:
        .word N_INS                       ; $51BA
        .byte $04
        .byte "VDUF"
W_VDUF:
        jsr DOVAR                         ; $51C1
        .word $0000                       ; $51C4
N_RD:
        .word N_VDUF                      ; $51C6
        .byte $02
        .byte "RD"
W_RD:
        jsr DOVAR                         ; $51CB
        .word $0000                       ; $51CE
N_B:
        .word N_RD                        ; $51D0
        .byte $01
        .byte "B"
W_B:
        jsr DOCOL                         ; $51D4
        .word W_SCR                       ; $51D7
        .word W_FETCH                     ; $51D9
        .word W_LIT                       ; $51DB
        .word $FFFE   ; -2                ; $51DD
        .word W_AND                       ; $51DF
        .word W_BLOCK                     ; $51E1
        .word W_EXIT                      ; $51E3
N_CURPLUS:
        .word N_B                         ; $51E5
        .byte $04
        .byte "CUR+"
W_CURPLUS:
        jsr DOCOL                         ; $51EC
        .word W_CUR                       ; $51EF
        .word W_FETCH                     ; $51F1
        .word W_PLUS                      ; $51F3
        .word W_LIT                       ; $51F5
        .word $07FF   ; 2047              ; $51F7
        .word W_AND                       ; $51F9
        .word W_CUR                       ; $51FB
        .word W_STORE                     ; $51FD
        .word W_EXIT                      ; $51FF
N_LE:
        .word N_CURPLUS                   ; $5201
        .byte $02
        .byte "LE"
W_LE:
        jsr DOCOL                         ; $5206
        .word W_CUR                       ; $5209
        .word W_FETCH                     ; $520B
        .word W_LIT                       ; $520D
        .word $003F   ; 63                ; $520F
        .word W_OR                        ; $5211
        .word W_EXIT                      ; $5213
N_DOTN:
        .word N_LE                        ; $5215
        .byte $02
        .byte ".N"
W_DOTN:
        jsr DOCOL                         ; $521A
        .word W_LIT                       ; $521D
        .word $000A   ; 10                ; $521F
        .word W_SLASHMOD                  ; $5221
        .word W_QDUP                      ; $5223
        .word W_0BRANCH                   ; $5225
        .word B_5231                      ; $5227
        .word W_LIT                       ; $5229
        .word $0030   ; 48                ; $522B
        .word W_PLUS                      ; $522D
        .word W_EMIT                      ; $522F
B_5231:
        .word W_LIT                       ; $5231
        .word $0030   ; 48                ; $5233
        .word W_PLUS                      ; $5235
        .word W_EMIT                      ; $5237
        .word W_EXIT                      ; $5239
N_POS:
        .word N_DOTN                      ; $523B
        .byte $03
        .byte "POS"
W_POS:
        jsr DOCOL                         ; $5241
        .word W_LIT                       ; $5244
        .word $001B   ; 27                ; $5246
        .word W_EMIT                      ; $5248
        .word W_LIT                       ; $524A
        .word $005B   ; 91                ; $524C
        .word W_EMIT                      ; $524E
        .word W_SWAP                      ; $5250
        .word W_1PLUS                     ; $5252
        .word W_DOTN                      ; $5254
        .word W_LIT                       ; $5256
        .word $003B   ; 59                ; $5258
        .word W_EMIT                      ; $525A
        .word W_1PLUS                     ; $525C
        .word W_DOTN                      ; $525E
        .word W_LIT                       ; $5260
        .word $0048   ; 72                ; $5262
        .word W_EMIT                      ; $5264
        .word W_EXIT                      ; $5266
N_DRAW:
        .word N_POS                       ; $5268
        .byte $04
        .byte "DRAW"
W_DRAW:
        jsr DOCOL                         ; $526F
        .word W_VDUF                      ; $5272
        .word W_FETCH                     ; $5274
        .word W_0BRANCH                   ; $5276
        .word B_52A2                      ; $5278
        .word W_B                         ; $527A
        .word W_LIT                       ; $527C
        .word $D000   ; -12288            ; $527E
        .word W_LIT                       ; $5280
        .word $0800   ; 2048              ; $5282
        .word W_CMOVE                     ; $5284
        .word W_LIT                       ; $5286
        .word $D000   ; -12288            ; $5288
        .word W_CUR                       ; $528A
        .word W_FETCH                     ; $528C
        .word W_PLUS                      ; $528E
        .word W_DUP                       ; $5290
        .word W_CFETCH                    ; $5292
        .word W_CMASK                     ; $5294
        .word W_FETCH                     ; $5296
        .word W_XOR                       ; $5298
        .word W_SWAP                      ; $529A
        .word W_CSTORE                    ; $529C
        .word W_BRANCH                    ; $529E
        .word B_535B                      ; $52A0
B_52A2:
        .word W_RD                        ; $52A2
        .word W_FETCH                     ; $52A4
        .word W_LIT                       ; $52A6
        .word $0002   ; 2                 ; $52A8
        .word W_EQ                        ; $52AA
        .word W_0BRANCH                   ; $52AC
        .word B_530B                      ; $52AE
        .word W_LIT                       ; $52B0
        .word $0000   ; 0                 ; $52B2
        .word W_LIT                       ; $52B4
        .word $0000   ; 0                 ; $52B6
        .word W_POS                       ; $52B8
        .word W_B                         ; $52BA
        .word W_LIT                       ; $52BC
        .word $0020   ; 32                ; $52BE
        .word W_LIT                       ; $52C0
        .word $0000   ; 0                 ; $52C2
        .word W_LPDORP                    ; $52C4
B_52C6:
        .word W_DUP                       ; $52C6
        .word W_LIT                       ; $52C8
        .word $0040   ; 64                ; $52CA
        .word W_TYPE                      ; $52CC
        .word W_CR                        ; $52CE
        .word W_LIT                       ; $52D0
        .word $0040   ; 64                ; $52D2
        .word W_PLUS                      ; $52D4
        .word W_LPLOOPRP                  ; $52D6
        .word B_52C6                      ; $52D8
        .word W_DROP                      ; $52DA
        .word W_LIT                       ; $52DC
        .word $0021   ; 33                ; $52DE
        .word W_LIT                       ; $52E0
        .word $0000   ; 0                 ; $52E2
        .word W_POS                       ; $52E4
        .word W_LPDOTQTRP                 ; $52E6
        .byte 4                           ; $52E8
        .byte "BLK "
        .word W_SCR                       ; $52ED
        .word W_FETCH                     ; $52EF
        .word W_DOT                       ; $52F1
        .word W_INS                       ; $52F3
        .word W_FETCH                     ; $52F5
        .word W_0BRANCH                   ; $52F7
        .word B_5305                      ; $52F9
        .word W_LPDOTQTRP                 ; $52FB
        .byte 3                           ; $52FD
        .byte "INS"
        .word W_BRANCH                    ; $5301
        .word B_530B                      ; $5303
B_5305:
        .word W_LPDOTQTRP                 ; $5305
        .byte 3                           ; $5307
        .byte "OVR"
B_530B:
        .word W_RD                        ; $530B
        .word W_FETCH                     ; $530D
        .word W_LIT                       ; $530F
        .word $0001   ; 1                 ; $5311
        .word W_EQ                        ; $5313
        .word W_0BRANCH                   ; $5315
        .word B_533D                      ; $5317
        .word W_CUR                       ; $5319
        .word W_FETCH                     ; $531B
        .word W_LIT                       ; $531D
        .word $0040   ; 64                ; $531F
        .word W_SLASH                     ; $5321
        .word W_LIT                       ; $5323
        .word $0000   ; 0                 ; $5325
        .word W_POS                       ; $5327
        .word W_B                         ; $5329
        .word W_CUR                       ; $532B
        .word W_FETCH                     ; $532D
        .word W_LIT                       ; $532F
        .word $07C0   ; 1984              ; $5331
        .word W_AND                       ; $5333
        .word W_PLUS                      ; $5335
        .word W_LIT                       ; $5337
        .word $0040   ; 64                ; $5339
        .word W_TYPE                      ; $533B
B_533D:
        .word W_LIT                       ; $533D
        .word $0000   ; 0                 ; $533F
        .word W_RD                        ; $5341
        .word W_STORE                     ; $5343
        .word W_CUR                       ; $5345
        .word W_FETCH                     ; $5347
        .word W_LIT                       ; $5349
        .word $0040   ; 64                ; $534B
        .word W_SLASH                     ; $534D
        .word W_CUR                       ; $534F
        .word W_FETCH                     ; $5351
        .word W_LIT                       ; $5353
        .word $003F   ; 63                ; $5355
        .word W_AND                       ; $5357
        .word W_POS                       ; $5359
B_535B:
        .word W_EXIT                      ; $535B
N_KEYTICK:
        .word N_DRAW                      ; $535D
        .byte $04
        .byte "KEY'"
W_KEYTICK:
        jsr DOCOL                         ; $5364
        .word W_KEY                       ; $5367
        .word W_DUP                       ; $5369
        .word W_LIT                       ; $536B
        .word $001B   ; 27                ; $536D
        .word W_EQ                        ; $536F
        .word W_0EQ                       ; $5371
        .word W_0BRANCH                   ; $5373
        .word B_5379                      ; $5375
        .word W_EXIT                      ; $5377
B_5379:
        .word W_DROP                      ; $5379
        .word W_KEY                       ; $537B
        .word W_LIT                       ; $537D
        .word $005B   ; 91                ; $537F
        .word W_EQ                        ; $5381
        .word W_0EQ                       ; $5383
        .word W_0BRANCH                   ; $5385
        .word B_538F                      ; $5387
        .word W_LIT                       ; $5389
        .word $0000   ; 0                 ; $538B
        .word W_EXIT                      ; $538D
B_538F:
        .word W_KEY                       ; $538F
        .word W_DUP                       ; $5391
        .word W_LIT                       ; $5393
        .word $0041   ; 65                ; $5395
        .word W_MINUS                     ; $5397
        .word W_LIT                       ; $5399
        .word $0004   ; 4                 ; $539B
        .word W_ULT                       ; $539D
        .word W_0BRANCH                   ; $539F
        .word B_53AB                      ; $53A1
        .word W_LIT                       ; $53A3
        .word $0040   ; 64                ; $53A5
        .word W_PLUS                      ; $53A7
        .word W_EXIT                      ; $53A9
B_53AB:
        .word W_KEY                       ; $53AB
        .word W_DROP                      ; $53AD
        .word W_LIT                       ; $53AF
        .word $0054   ; 84                ; $53B1
        .word W_PLUS                      ; $53B3
        .word W_EXIT                      ; $53B5
N_SHL:
        .word N_KEYTICK                   ; $53B7
        .byte $03
        .byte "SHL"
W_SHL:
        jsr DOCOL                         ; $53BD
        .word W_B                         ; $53C0
        .word W_CUR                       ; $53C2
        .word W_FETCH                     ; $53C4
        .word W_PLUS                      ; $53C6
        .word W_DUP                       ; $53C8
        .word W_1PLUS                     ; $53CA
        .word W_SWAP                      ; $53CC
        .word W_LE                        ; $53CE
        .word W_CUR                       ; $53D0
        .word W_FETCH                     ; $53D2
        .word W_MINUS                     ; $53D4
        .word W_CMOVE                     ; $53D6
        .word W_BL                        ; $53D8
        .word W_B                         ; $53DA
        .word W_LE                        ; $53DC
        .word W_PLUS                      ; $53DE
        .word W_CSTORE                    ; $53E0
        .word W_UPDATE                    ; $53E2
        .word W_LIT                       ; $53E4
        .word $0001   ; 1                 ; $53E6
        .word W_RD                        ; $53E8
        .word W_STORE                     ; $53EA
        .word W_EXIT                      ; $53EC
N_SHR:
        .word N_SHL                       ; $53EE
        .byte $03
        .byte "SHR"
W_SHR:
        jsr DOCOL                         ; $53F4
        .word W_LE                        ; $53F7
        .word W_CUR                       ; $53F9
        .word W_FETCH                     ; $53FB
        .word W_MINUS                     ; $53FD
        .word W_DUP                       ; $53FF
        .word W_0BRANCH                   ; $5401
        .word B_5427                      ; $5403
        .word W_LIT                       ; $5405
        .word $0000   ; 0                 ; $5407
        .word W_LPDORP                    ; $5409
B_540B:
        .word W_B                         ; $540B
        .word W_LE                        ; $540D
        .word W_PLUS                      ; $540F
        .word W_I                         ; $5411
        .word W_MINUS                     ; $5413
        .word W_DUP                       ; $5415
        .word W_1MINUS                    ; $5417
        .word W_CFETCH                    ; $5419
        .word W_SWAP                      ; $541B
        .word W_CSTORE                    ; $541D
        .word W_LPLOOPRP                  ; $541F
        .word B_540B                      ; $5421
        .word W_BRANCH                    ; $5423
        .word B_5429                      ; $5425
B_5427:
        .word W_DROP                      ; $5427
B_5429:
        .word W_EXIT                      ; $5429
N_PUT:
        .word N_SHR                       ; $542B
        .byte $03
        .byte "PUT"
W_PUT:
        jsr DOCOL                         ; $5431
        .word W_INS                       ; $5434
        .word W_FETCH                     ; $5436
        .word W_0BRANCH                   ; $5438
        .word B_543E                      ; $543A
        .word W_SHR                       ; $543C
B_543E:
        .word W_B                         ; $543E
        .word W_CUR                       ; $5440
        .word W_FETCH                     ; $5442
        .word W_PLUS                      ; $5444
        .word W_CSTORE                    ; $5446
        .word W_UPDATE                    ; $5448
        .word W_LIT                       ; $544A
        .word $0001   ; 1                 ; $544C
        .word W_RD                        ; $544E
        .word W_STORE                     ; $5450
        .word W_LIT                       ; $5452
        .word $0001   ; 1                 ; $5454
        .word W_CURPLUS                   ; $5456
        .word W_EXIT                      ; $5458
N_NXT:
        .word N_PUT                       ; $545A
        .byte $03
        .byte "NXT"
W_NXT:
        jsr DOCOL                         ; $5460
        .word W_SCR                       ; $5463
        .word W_FETCH                     ; $5465
        .word W_PLUS                      ; $5467
        .word W_DUP                       ; $5469
        .word W_BLKMAX                    ; $546B
        .word W_FETCH                     ; $546D
        .word W_ULT                       ; $546F
        .word W_0BRANCH                   ; $5471
        .word B_548F                      ; $5473
        .word W_FLUSH                     ; $5475
        .word W_SCR                       ; $5477
        .word W_STORE                     ; $5479
        .word W_LIT                       ; $547B
        .word $0000   ; 0                 ; $547D
        .word W_CUR                       ; $547F
        .word W_STORE                     ; $5481
        .word W_LIT                       ; $5483
        .word $0002   ; 2                 ; $5485
        .word W_RD                        ; $5487
        .word W_STORE                     ; $5489
        .word W_BRANCH                    ; $548B
        .word B_5491                      ; $548D
B_548F:
        .word W_DROP                      ; $548F
B_5491:
        .word W_EXIT                      ; $5491
N_ED1:
        .word N_NXT                       ; $5493
        .byte $03
        .byte "ED1"
W_ED1:
        jsr DOCOL                         ; $5499
        .word W_DUP                       ; $549C
        .word W_LIT                       ; $549E
        .word $0020   ; 32                ; $54A0
        .word W_LIT                       ; $54A2
        .word $007F   ; 127               ; $54A4
        .word W_WITHIN                    ; $54A6
        .word W_0BRANCH                   ; $54A8
        .word B_54B4                      ; $54AA
        .word W_PUT                       ; $54AC
        .word W_LIT                       ; $54AE
        .word $0000   ; 0                 ; $54B0
        .word W_EXIT                      ; $54B2
B_54B4:
        .word W_DUP                       ; $54B4
        .word W_LIT                       ; $54B6
        .word $0081   ; 129               ; $54B8
        .word W_LIT                       ; $54BA
        .word $0085   ; 133               ; $54BC
        .word W_WITHIN                    ; $54BE
        .word W_0BRANCH                   ; $54C0
        .word B_54F8                      ; $54C2
        .word W_LIT                       ; $54C4
        .word $0081   ; 129               ; $54C6
        .word W_MINUS                     ; $54C8
        .word W_DUP                       ; $54CA
        .word W_LIT                       ; $54CC
        .word $0001   ; 1                 ; $54CE
        .word W_AND                       ; $54D0
        .word W_2STAR                     ; $54D2
        .word W_1MINUS                    ; $54D4
        .word W_SWAP                      ; $54D6
        .word W_LIT                       ; $54D8
        .word $0002   ; 2                 ; $54DA
        .word W_LT                        ; $54DC
        .word W_0BRANCH                   ; $54DE
        .word B_54EA                      ; $54E0
        .word W_LIT                       ; $54E2
        .word $0040   ; 64                ; $54E4
        .word W_BRANCH                    ; $54E6
        .word B_54EE                      ; $54E8
B_54EA:
        .word W_LIT                       ; $54EA
        .word $FFFF   ; -1                ; $54EC
B_54EE:
        .word W_STAR                      ; $54EE
        .word W_CURPLUS                   ; $54F0
        .word W_LIT                       ; $54F2
        .word $0000   ; 0                 ; $54F4
        .word W_EXIT                      ; $54F6
B_54F8:
        .word W_DUP                       ; $54F8
        .word W_LIT                       ; $54FA
        .word $0086   ; 134               ; $54FC
        .word W_EQ                        ; $54FE
        .word W_0BRANCH                   ; $5500
        .word B_5538                      ; $5502
        .word W_DROP                      ; $5504
        .word W_INS                       ; $5506
        .word W_FETCH                     ; $5508
        .word W_0EQ                       ; $550A
        .word W_INS                       ; $550C
        .word W_STORE                     ; $550E
        .word W_LIT                       ; $5510
        .word $0002   ; 2                 ; $5512
        .word W_RD                        ; $5514
        .word W_STORE                     ; $5516
        .word W_INS                       ; $5518
        .word W_FETCH                     ; $551A
        .word W_0BRANCH                   ; $551C
        .word B_552B                      ; $551E
        .word W_LPDOTQTRP                 ; $5520
        .byte 4                           ; $5522
        .byte "INS "
        .word W_BRANCH                    ; $5527
        .word B_5532                      ; $5529
B_552B:
        .word W_LPDOTQTRP                 ; $552B
        .byte 4                           ; $552D
        .byte "OVR "
B_5532:
        .word W_LIT                       ; $5532
        .word $0000   ; 0                 ; $5534
        .word W_EXIT                      ; $5536
B_5538:
        .word W_DUP                       ; $5538
        .word W_LIT                       ; $553A
        .word $0087   ; 135               ; $553C
        .word W_EQ                        ; $553E
        .word W_0BRANCH                   ; $5540
        .word B_554E                      ; $5542
        .word W_DROP                      ; $5544
        .word W_SHL                       ; $5546
        .word W_LIT                       ; $5548
        .word $0000   ; 0                 ; $554A
        .word W_EXIT                      ; $554C
B_554E:
        .word W_DUP                       ; $554E
        .word W_LIT                       ; $5550
        .word $007F   ; 127               ; $5552
        .word W_EQ                        ; $5554
        .word W_0BRANCH                   ; $5556
        .word B_5578                      ; $5558
        .word W_DROP                      ; $555A
        .word W_CUR                       ; $555C
        .word W_FETCH                     ; $555E
        .word W_LIT                       ; $5560
        .word $003F   ; 63                ; $5562
        .word W_AND                       ; $5564
        .word W_0BRANCH                   ; $5566
        .word B_5572                      ; $5568
        .word W_LIT                       ; $556A
        .word $FFFF   ; -1                ; $556C
        .word W_CURPLUS                   ; $556E
        .word W_SHL                       ; $5570
B_5572:
        .word W_LIT                       ; $5572
        .word $0000   ; 0                 ; $5574
        .word W_EXIT                      ; $5576
B_5578:
        .word W_DUP                       ; $5578
        .word W_LIT                       ; $557A
        .word $000D   ; 13                ; $557C
        .word W_EQ                        ; $557E
        .word W_0BRANCH                   ; $5580
        .word B_55A0                      ; $5582
        .word W_DROP                      ; $5584
        .word W_CUR                       ; $5586
        .word W_FETCH                     ; $5588
        .word W_LIT                       ; $558A
        .word $0040   ; 64                ; $558C
        .word W_PLUS                      ; $558E
        .word W_LIT                       ; $5590
        .word $07C0   ; 1984              ; $5592
        .word W_AND                       ; $5594
        .word W_CUR                       ; $5596
        .word W_STORE                     ; $5598
        .word W_LIT                       ; $559A
        .word $0000   ; 0                 ; $559C
        .word W_EXIT                      ; $559E
B_55A0:
        .word W_DUP                       ; $55A0
        .word W_LIT                       ; $55A2
        .word $008A   ; 138               ; $55A4
        .word W_EQ                        ; $55A6
        .word W_0BRANCH                   ; $55A8
        .word B_55BA                      ; $55AA
        .word W_DROP                      ; $55AC
        .word W_LIT                       ; $55AE
        .word $0002   ; 2                 ; $55B0
        .word W_NXT                       ; $55B2
        .word W_LIT                       ; $55B4
        .word $0000   ; 0                 ; $55B6
        .word W_EXIT                      ; $55B8
B_55BA:
        .word W_DUP                       ; $55BA
        .word W_LIT                       ; $55BC
        .word $0089   ; 137               ; $55BE
        .word W_EQ                        ; $55C0
        .word W_0BRANCH                   ; $55C2
        .word B_55D4                      ; $55C4
        .word W_DROP                      ; $55C6
        .word W_LIT                       ; $55C8
        .word $FFFE   ; -2                ; $55CA
        .word W_NXT                       ; $55CC
        .word W_LIT                       ; $55CE
        .word $0000   ; 0                 ; $55D0
        .word W_EXIT                      ; $55D2
B_55D4:
        .word W_LIT                       ; $55D4
        .word $0011   ; 17                ; $55D6
        .word W_EQ                        ; $55D8
        .word W_EXIT                      ; $55DA
N_EDIT:
        .word N_ED1                       ; $55DC
        .byte $04
        .byte "EDIT"
W_EDIT:
        jsr DOCOL                         ; $55E3
        .word W_SCR                       ; $55E6
        .word W_STORE                     ; $55E8
        .word W_LIT                       ; $55EA
        .word $0000   ; 0                 ; $55EC
        .word W_CUR                       ; $55EE
        .word W_STORE                     ; $55F0
        .word W_LIT                       ; $55F2
        .word $0000   ; 0                 ; $55F4
        .word W_INS                       ; $55F6
        .word W_STORE                     ; $55F8
        .word W_LIT                       ; $55FA
        .word $0002   ; 2                 ; $55FC
        .word W_RD                        ; $55FE
        .word W_STORE                     ; $5600
        .word W_VDUF                      ; $5602
        .word W_FETCH                     ; $5604
        .word W_0EQ                       ; $5606
        .word W_0BRANCH                   ; $5608
        .word B_5618                      ; $560A
        .word W_LIT                       ; $560C
        .word $001B   ; 27                ; $560E
        .word W_EMIT                      ; $5610
        .word W_LPDOTQTRP                 ; $5612
        .byte 3                           ; $5614
        .byte "[2J"
B_5618:
        .word W_DRAW                      ; $5618
        .word W_KEYTICK                   ; $561A
        .word W_ED1                       ; $561C
        .word W_0BRANCH                   ; $561E
        .word B_5618                      ; $5620
        .word W_FLUSH                     ; $5622
        .word W_VDUF                      ; $5624
        .word W_FETCH                     ; $5626
        .word W_0BRANCH                   ; $5628
        .word B_563C                      ; $562A
        .word W_LIT                       ; $562C
        .word $D000   ; -12288            ; $562E
        .word W_LIT                       ; $5630
        .word $0800   ; 2048              ; $5632
        .word W_BL                        ; $5634
        .word W_FILL                      ; $5636
        .word W_BRANCH                    ; $5638
        .word B_5646                      ; $563A
B_563C:
        .word W_LIT                       ; $563C
        .word $0022   ; 34                ; $563E
        .word W_LIT                       ; $5640
        .word $0000   ; 0                 ; $5642
        .word W_POS                       ; $5644
B_5646:
        .word W_EXIT                      ; $5646
N_COLDINIT:
        .word N_EDIT                      ; $5648
        .byte $08
        .byte "COLDINIT"
W_COLDINIT:
        jsr DOCOL                         ; $5653
        .word W_LIT                       ; $5656
        .word $D000   ; -12288            ; $5658
        .word W_LIT                       ; $565A
        .word $0800   ; 2048              ; $565C
        .word W_BL                        ; $565E
        .word W_FILL                      ; $5660
        .word W_CR                        ; $5662
        .word W_LPDOTQTRP                 ; $5664
        .byte 37                          ; $5666
        .byte "WORDS DIR USE MAKE EDIT LIST LOAD BYE"
        .word W_CR                        ; $568C
        .word W_EXIT                      ; $568E

        .org $BFEF
        .res 16, $FF                      ; $BFEF
        .byte $FF                         ; $BFFF

; ======================================================================
; $C000-$CFFF  DISK PIA ($C000) / DISK ACIA ($C010) - NOT IN THE EEPROM
; ======================================================================
        .org $C000
        .res $100, $FF                    ; $C000-$C0FF I/O (disk PIA/ACIA, not used now)
        .include "SD.S"                   ; $C100 SD card driver
.scope DIS
        .include "DIS.S"                  ; DA disassembler (after the SD driver)
.endscope
DADISP  = DIS::DADISP

; ----------------------------------------------------------------------
; HLGET - CHARACTER INPUT FOR HL (DOSX HLREC). PASSES EVERYTHING BACK
; EXCEPT A MOS TECHNOLOGY CHECKSUM RECORD, WHICH IT LOADS ITSELF:
;   ;LLHHLL<DATA>CCCC   LL BYTES AT $HHLL, CCCC = 16-BIT SUM OF ALL BYTES
;   ;00...              END OF FILE: RETURNS ESC SO HL FINISHES
; ONCE SOMETHING HAS LOADED, A QUIET LINE ALSO ENDS THE LOAD (INTEL TOO).
; (THE FORMAT OF THE OSI ASSEMBLER'S CHECKSUM/OBJECT OUTPUT)
; ----------------------------------------------------------------------
M_P1    = $12               ; DOSX P1
M_CKH   = $35E8             ; HIGH BYTE OF THE 16-BIT SUM (TY TEMP FT)

HLGET:  lda DX_HIGL          ; NOTHING LOADED YET: WAIT AS LONG AS IT TAKES
        ora DX_HIGH
        bne @tw
        jsr DX_SERIN
        bra @c
@tw:    ldx #0              ; AFTER A RECORD: ABOUT 2.5 S OF SILENCE AT 1 MHZ
        ldy #0              ; ENDS THE LOAD (THE OSI ASSEMBLER WRITES NO ;00)
@w:     jsr DX_KEYGET
        bcs @c
        dex
        bne @w
        dey
        bne @w
        lda #$1B
        rts
@c:     cmp #';'
        beq @m
        rts
@m:     stz DX_CK
        stz M_CKH
        stz DX_BAD
        jsr MSHB            ; BYTE COUNT
        sta DX_LL
        beq @eof
        jsr MSHB
        sta M_P1+1
        jsr MSHB
        sta M_P1
        ldy #0
@dl:    jsr MSHB
        sta (M_P1),y
        iny
        cpy DX_LL
        bne @dl
        jsr MSCK
        bcs @bad
        jsr DX_HLRNG        ; NOTE LOWEST/HIGHEST ADDRESS
        lda #'.'
        bra @mk
@bad:   inc DX_ERRS
        lda #'X'
@mk:    jsr DX_OUTCH
        bra HLGET
@eof:   lda #$1B            ; HL DRAINS THE REST AND REPORTS
        rts

MSHB:   jsr DX_SERHB        ; HEX BYTE, 16-BIT SUM IN CK/M_CKH
        bcc @r
        inc M_CKH
@r:     rts

MSCK:   lda DX_CK           ; C=1 IF THE CHECKSUM OR A HEX DIGIT WAS BAD
        sta DX_TEML
        lda M_CKH
        sta DX_TEMH
        jsr DX_SERHB
        cmp DX_TEMH
        bne @b
        jsr DX_SERHB
        cmp DX_TEML
        bne @b
        lda DX_BAD
        bne @b
        clc
        rts
@b:     sec
        rts
        .res $D000 - *, $FF

; ======================================================================
; $D000-$DFFF  DOSX - NEW COMMANDS (ORIGINAL SOURCE, OWN SYMBOL SCOPE)
; ======================================================================
.scope DOSX
        .include "DOSX.S"
.endscope
; DOSX helpers used by DIS.S (it comes earlier in the ROM)
DX_GETW   = DOSX::GETW
DX_ATEND  = DOSX::ATEND
DX_KEYCHK = DOSX::KEYCHK
DX_SERIN  = DOSX::SERIN
DX_SERHB  = DOSX::SERHB
DX_KEYGET = DOSX::KEYGET
DX_HIGL   = DOSX::HIGL
DX_HIGH   = DOSX::HIGH
DX_HLRNG  = DOSX::HLRNG
DX_OUTCH  = DOSX::OUTCH
DX_CK     = DOSX::CK
DX_BAD    = DOSX::BAD
DX_LL     = DOSX::LL
DX_ERRS   = DOSX::ERRS
DX_TEML   = DOSX::TEML
DX_TEMH   = DOSX::TEMH

        .org $E000

; ======================================================================
; OS-65D V3.3 ROM DOS  $E000-$FFFF  (disassembled; names are this
; disassembly's, comments mark what is known)
; ======================================================================
        jmp RESET                         ; $E000  4C A5 F4
        jmp INLINE                        ; $E003  4C BA E0
        jmp INCHR                         ; $E006  4C BD E0
        jmp GETKEY                        ; $E009  4C C4 E0
        jmp OUTCH                         ; $E00C  4C C7 E0
        jmp PRINT                         ; $E00F  4C D6 EA
        jmp CRLF                          ; $E012  4C CD EA
        jmp PRHEX                         ; $E015  4C F5 EA
        jmp PRNIB                         ; $E018  4C FE EA
        jmp GETHX                         ; $E01B  4C 91 EA
        jmp GETADR                        ; $E01E  4C 86 EA
        jmp GETCH                         ; $E021  4C 45 EA
        jmp SEEK                          ; $E024  4C 35 E4
        jmp BIN2TRK                       ; $E027  4C 1F E4
        jmp HOME                          ; $E02A  4C DC E3
        jmp HLOAD                         ; $E02D  4C CD E4
        jmp HUNLD                         ; $E030  4C DA E4
        jmp RDHEAD                        ; $E033  4C 98 E8
        jmp RDSECP                        ; $E036  4C 24 F0
        jmp WRSEC                         ; $E039  4C 5A E5
        jmp NXTTRK                        ; $E03C  4C E4 E9
        jmp SELDRV                        ; $E03F  4C 43 E7
        jmp ERROR                         ; $E042  4C C8 E7
        jmp PROMPT                        ; $E045  4C CE E7
        jmp STEPOUT                       ; $E048  4C 03 E4
        jmp STEPIN                        ; $E04B  4C FC E3
        jmp SECMAP                        ; $E04E  4C 70 E7

; FT - start the Forth ROM at $A000
CMD_FT:
        jmp FT_GO                         ; $E051  (FPGA: switch the Forth ROM in)

; PX - print the disk PIA values for each drive
CMD_PX:
        lda #$01                          ; $E054  A9 01
L_E056:
        pha                               ; $E056  48
        jsr SELDRV                        ; $E057  20 43 E7
        jsr DELAY                         ; $E05A  20 F1 E3
        jsr DELAY                         ; $E05D  20 F1 E3
        pla                               ; $E060  68
        pha                               ; $E061  48
        clc                               ; $E062  18
        adc #$40                          ; $E063  69 40
        jsr OUTCH                         ; $E065  20 C7 E0
        jsr PRINT                         ; $E068  20 D6 EA
        .byte " PA=", $00                 ; $E06B
        lda PIAA                          ; $E070  AD 00 C0
        jsr PRHEX                         ; $E073  20 F5 EA
        jsr PRINT                         ; $E076  20 D6 EA
        .byte " PB=", $00                 ; $E079
        lda PIAB                          ; $E07E  AD 02 C0
        jsr PRHEX                         ; $E081  20 F5 EA
        jsr PRINT                         ; $E084  20 D6 EA
        .byte " CRA=", $00                ; $E087
        lda $C001                         ; $E08D  AD 01 C0
        jsr PRHEX                         ; $E090  20 F5 EA
        jsr CRLF                          ; $E093  20 CD EA
        pla                               ; $E096  68
        clc                               ; $E097  18
        adc #$01                          ; $E098  69 01
        cmp #$05                          ; $E09A  C9 05
        bne L_E056                        ; $E09C  D0 B8
        lda #$01                          ; $E09E  A9 01
        jsr SELDRV                        ; $E0A0  20 43 E7
        jmp PROMPT                        ; $E0A3  4C CE E7
L_E0A6:
        jmp PROMPT                        ; $E0A6  4C CE E7
        .byte $0D,$0A,$4F,$53,$2D,$36,$35,$44,$20,$56,$33,$2E,$30,$00,$4C,$CE; $E0A9
        .byte $E7                         ; $E0B9
INLINE:
        jmp GETCHR                        ; $E0BA  4C 37 EA

; INCHR - read a character from the input devices in INMASK
INCHR:
        ldy #$00                          ; $E0BD  A0 00
        lda INMASK                        ; $E0BF  AD 21 23
        bne L_E0CF                        ; $E0C2  D0 0B

; GETKEY - read a key and echo it
GETKEY:
        jsr INLINE                        ; $E0C4  20 BA E0

; OUTCH - print A on the output devices in OUTMASK (keeps X,Y)
OUTCH:
        jsr SAVREG                        ; $E0C7  20 EE E0
L_E0CA:
        jsr OUTPOST                       ; $E0CA  20 2E E3
        ldy #$10                          ; $E0CD  A0 10
L_E0CF:
        ldx #$FF                          ; $E0CF  A2 FF
        bne L_E0F8                        ; $E0D1  D0 25
L_E0D3:
        inx                               ; $E0D3  E8
        lsr a                             ; $E0D4  4A
        bcc L_E0E0                        ; $E0D5  90 09
        pha                               ; $E0D7  48
        txa                               ; $E0D8  8A
        pha                               ; $E0D9  48
        jsr DEVJMP                        ; $E0DA  20 FD E0
        pla                               ; $E0DD  68
        tax                               ; $E0DE  AA
        pla                               ; $E0DF  68
L_E0E0:
        bne L_E0D3                        ; $E0E0  D0 F1
RESREG:
        ldx XSAV                          ; $E0E2  AE 5F 23
        ldy YSAV                          ; $E0E5  AC 61 23
        lda CHRSAV                        ; $E0E8  AD 63 23
        and #$7F                          ; $E0EB  29 7F
        rts                               ; $E0ED  60
SAVREG:
        sta CHRSAV                        ; $E0EE  8D 63 23
        sty YSAV                          ; $E0F1  8C 61 23
        stx XSAV                          ; $E0F4  8E 5F 23
        rts                               ; $E0F7  60
L_E0F8:
        sty DEVOFS                        ; $E0F8  8C 78 23
        bne L_E0D3                        ; $E0FB  D0 D6
DEVJMP:
        asl a                             ; $E0FD  0A
        adc DEVOFS                        ; $E0FE  6D 78 23
        tax                               ; $E101  AA
        lda $2302,x                       ; $E102  BD 02 23
        pha                               ; $E105  48
        lda $2301,x                       ; $E106  BD 01 23
        pha                               ; $E109  48
        lda CHRSAV                        ; $E10A  AD 63 23
        rts                               ; $E10D  60
        lda #$00                          ; $E10E  A9 00
        rts                               ; $E110  60
        jsr $2389                         ; $E111  20 89 23
        ldx #$00                          ; $E114  A2 00
        beq L_E11D                        ; $E116  F0 05
        jsr $2390                         ; $E118  20 90 23
        ldx #$07                          ; $E11B  A2 07
L_E11D:
        sta CHRSAV                        ; $E11D  8D 63 23
        inc $238A,x                       ; $E120  FE 8A 23
L_E123:
        bne L_E128                        ; $E123  D0 03
        inc $238B,x                       ; $E125  FE 8B 23
L_E128:
        rts                               ; $E128  60
        ldy #$00                          ; $E129  A0 00
        jsr L_E1EE                        ; $E12B  20 EE E1
        bne L_E133                        ; $E12E  D0 03
        jsr L_E154                        ; $E130  20 54 E1
L_E133:
        jsr $23AB                         ; $E133  20 AB 23
        ldx #$22                          ; $E136  A2 22
        bne L_E11D                        ; $E138  D0 E3
        cmp #$0A                          ; $E13A  C9 0A
        beq L_E128                        ; $E13C  F0 EA
        pha                               ; $E13E  48
        ldy #$17                          ; $E13F  A0 17
        jsr L_E1EE                        ; $E141  20 EE E1
        bne L_E149                        ; $E144  D0 03
        jsr L_E154                        ; $E146  20 54 E1
L_E149:
        pla                               ; $E149  68
        jsr $23C2                         ; $E14A  20 C2 23
        ldx #$39                          ; $E14D  A2 39
        stx $232D                         ; $E14F  8E 2D 23
        bne L_E11D                        ; $E152  D0 C9
L_E154:
        lda $232D                         ; $E154  AD 2D 23
        beq L_E15E                        ; $E157  F0 05
        ldx #$00                          ; $E159  A2 00
        jsr L_E1FF                        ; $E15B  20 FF E1
L_E15E:
        lda $2326                         ; $E15E  AD 26 23
        sta $23AC                         ; $E161  8D AC 23
        sta $23C3                         ; $E164  8D C3 23
        sta MEMLO                         ; $E167  85 FE
        lda $2327                         ; $E169  AD 27 23
        sta $23AD                         ; $E16C  8D AD 23
        sta $23C4                         ; $E16F  8D C4 23
        sta MEMHI                         ; $E172  85 FF
        ldx #$00                          ; $E174  A2 00
        beq L_E1CA                        ; $E176  F0 52
        ldx #$08                          ; $E178  A2 08
        ldy #$51                          ; $E17A  A0 51
        jsr L_E1F0                        ; $E17C  20 F0 E1
        bne L_E184                        ; $E17F  D0 03
        jsr L_E1A8                        ; $E181  20 A8 E1
L_E184:
        jsr $23FC                         ; $E184  20 FC 23
        ldx #$73                          ; $E187  A2 73
        bne L_E11D                        ; $E189  D0 92
        cmp #$0A                          ; $E18B  C9 0A
        beq L_E1FE                        ; $E18D  F0 6F
        pha                               ; $E18F  48
        ldx #$08                          ; $E190  A2 08
        ldy #$6A                          ; $E192  A0 6A
        jsr L_E1F0                        ; $E194  20 F0 E1
        bne L_E19C                        ; $E197  D0 03
        jsr L_E1A8                        ; $E199  20 A8 E1
L_E19C:
        pla                               ; $E19C  68
        jsr $2415                         ; $E19D  20 15 24
        ldx #$8C                          ; $E1A0  A2 8C
        stx $2335                         ; $E1A2  8E 35 23
        jmp L_E11D                        ; $E1A5  4C 1D E1
L_E1A8:
        lda $2335                         ; $E1A8  AD 35 23
        beq L_E1B2                        ; $E1AB  F0 05
        ldx #$08                          ; $E1AD  A2 08
        jsr L_E1FF                        ; $E1AF  20 FF E1
L_E1B2:
        lda $232E                         ; $E1B2  AD 2E 23
        sta $23FD                         ; $E1B5  8D FD 23
        sta $2416                         ; $E1B8  8D 16 24
        sta MEMLO                         ; $E1BB  85 FE
        lda $232F                         ; $E1BD  AD 2F 23
        sta $23FE                         ; $E1C0  8D FE 23
        sta $2417                         ; $E1C3  8D 17 24
        sta MEMHI                         ; $E1C6  85 FF
        ldx #$08                          ; $E1C8  A2 08
L_E1CA:
        lda $232C,x                       ; $E1CA  BD 2C 23
        clc                               ; $E1CD  18
        sed                               ; $E1CE  F8
        adc #$01                          ; $E1CF  69 01
        cld                               ; $E1D1  D8
        sta $232C,x                       ; $E1D2  9D 2C 23
        jsr L_E1DB                        ; $E1D5  20 DB E1
        jmp L_E89B                        ; $E1D8  4C 9B E8
L_E1DB:
        lda #$00                          ; $E1DB  A9 00
        sta $232D,x                       ; $E1DD  9D 2D 23
        lda $232C,x                       ; $E1E0  BD 2C 23
        cmp $232B,x                       ; $E1E3  DD 2B 23
        jsr L_E9EE                        ; $E1E6  20 EE E9
        iny                               ; $E1E9  C8
        bne L_E219                        ; $E1EA  D0 2D
        brk                               ; $E1EC  00
        .byte $00                         ; $E1ED
L_E1EE:
        ldx #$00                          ; $E1EE  A2 00
L_E1F0:
        lda $23AC,y                       ; $E1F0  B9 AC 23
        cmp $2328,x                       ; $E1F3  DD 28 23
        bne L_E1FE                        ; $E1F6  D0 06
        lda $23AD,y                       ; $E1F8  B9 AD 23
        cmp $2329,x                       ; $E1FB  DD 29 23
L_E1FE:
        rts                               ; $E1FE  60
L_E1FF:
        lda $2329,x                       ; $E1FF  BD 29 23
        sec                               ; $E202  38
        sbc $2327,x                       ; $E203  FD 27 23
        sta DPAGE                         ; $E206  8D 5F 26
        lda $2326,x                       ; $E209  BD 26 23
        sta MEMLO                         ; $E20C  85 FE
        lda $2327,x                       ; $E20E  BD 27 23
        sta MEMHI                         ; $E211  85 FF
        jsr L_E1DB                        ; $E213  20 DB E1
        jmp WRSEC                         ; $E216  4C 5A E5
L_E219:
        sty DSECT                         ; $E219  8C 5E 26
        jmp HLOAD                         ; $E21C  4C CD E4
L_E21F:
        lda #$80                          ; $E21F  A9 80
        sta $238B                         ; $E221  8D 8B 23
        lda #$00                          ; $E224  A9 00
        rts                               ; $E226  60

; (not reached when tracing from the known entry points)
L_E227:
        pha                               ; $E227  48
L_E228:
        lda $F400                         ; $E228  AD 00 F4
        lsr a                             ; $E22B  4A
        bcs L_E228                        ; $E22C  B0 FA
        pla                               ; $E22E  68
        and #$7F                          ; $E22F  29 7F
        sta $F402                         ; $E231  8D 02 F4
        lda $F420                         ; $E234  AD 20 F4
        rts                               ; $E237  60
        .byte $AE,$23,$23,$BD,$00,$CF,$4A,$90,$F7,$B0,$4D,$00,$00,$48,$AE,$23; $E238
        .byte $23,$BD,$00,$CF,$4A,$4A,$90,$F6,$68,$9D,$01,$CF,$60; $E248

; ACOUT - console ACIA output; a key arriving meanwhile goes to TYPAHD, Ctrl-S waits for Ctrl-Q
ACOUT:
        pha                               ; $E255  48
L_E256:
        lda ACIAS                         ; $E256  AD 00 80
        lsr a                             ; $E259  4A
        lsr a                             ; $E25A  4A
        bcc L_E256                        ; $E25B  90 F9
        pla                               ; $E25D  68
        sta ACIAD                         ; $E25E  8D 01 80
        pha                               ; $E261  48
        lda ACIAS                         ; $E262  AD 00 80
        lsr a                             ; $E265  4A
        bcc L_E279                        ; $E266  90 11
        jsr ACIN                          ; $E268  20 7E E2
        sta TYPAHD                        ; $E26B  8D 25 23
        cmp #$13                          ; $E26E  C9 13
        bne L_E279                        ; $E270  D0 07
L_E272:
        jsr ACIN                          ; $E272  20 7E E2
        cmp #$11                          ; $E275  C9 11
        bne L_E272                        ; $E277  D0 F9
L_E279:
        pla                               ; $E279  68
        sta CHRSAV                        ; $E27A  8D 63 23
        rts                               ; $E27D  60

; ACIN - wait for a console ACIA character
ACIN:
        lda ACIAS                         ; $E27E  AD 00 80
        inc RNDSEED                       ; $E281  EE 24 23
        lsr a                             ; $E284  4A
        bcc ACIN                          ; $E285  90 F7
        lda ACIAD                         ; $E287  AD 01 80
        and #$7F                          ; $E28A  29 7F
L_E28C:
        sta CHRSAV                        ; $E28C  8D 63 23
        rts                               ; $E28F  60

; (not reached when tracing from the known entry points)
L_E290:
        lda $CF01,x                       ; $E290  BD 01 CF
        bcs L_E28C                        ; $E293  B0 F7
        pha                               ; $E295  48
L_E296:
        lda L_FB05                        ; $E296  AD 05 FB
        bpl L_E296                        ; $E299  10 FB
        pla                               ; $E29B  68
        sta $FB04                         ; $E29C  8D 04 FB
        rts                               ; $E29F  60

; (not reached when tracing from the known entry points)
L_E2A0:
        lda L_FB05                        ; $E2A0  AD 05 FB
        lsr a                             ; $E2A3  4A
        bcc L_E2A0                        ; $E2A4  90 FA
        lda $FB03                         ; $E2A6  AD 03 FB
        sta $FB07                         ; $E2A9  8D 07 FB
        sta CHRSAV                        ; $E2AC  8D 63 23
        rts                               ; $E2AF  60

; (not reached when tracing from the known entry points)
L_E2B0:
        jsr L_E2CC                        ; $E2B0  20 CC E2
        jsr SWAP213                       ; $E2B3  20 C9 E3
L_E2B6:
        inc RNDSEED                       ; $E2B6  EE 24 23
        jsr L_EC68                        ; $E2B9  20 68 EC
        beq L_E2B6                        ; $E2BC  F0 F8
        sta CHRSAV                        ; $E2BE  8D 63 23
        jsr SWAP213                       ; $E2C1  20 C9 E3
        lda CHRSAV                        ; $E2C4  AD 63 23
        rts                               ; $E2C7  60
        .byte $8D, "%#h"                  ; $E2C8
L_E2CC:
        jmp L_E28C                        ; $E2CC  4C 8C E2

; (not reached when tracing from the known entry points)
L_E2CF:
        jsr SWAP213                       ; $E2CF  20 C9 E3
        jmp PROMPT                        ; $E2D2  4C CE E7

; SPECKEY - [ ] and Ctrl-X keyboard functions
SPECKEY:
        cmp #$5B                          ; $E2D5  C9 5B
        bne L_E2EA                        ; $E2D7  D0 11
        lda #$80                          ; $E2D9  A9 80
        sta $2392                         ; $E2DB  8D 92 23
        lda #$00                          ; $E2DE  A9 00
        sta $2391                         ; $E2E0  8D 91 23
        lda OUTMASK                       ; $E2E3  AD 22 23
        ora #$10                          ; $E2E6  09 10
        bne L_E31B                        ; $E2E8  D0 31
L_E2EA:
        cmp #$5D                          ; $E2EA  C9 5D
        bne L_E301                        ; $E2EC  D0 13
        jsr L_E0CA                        ; $E2EE  20 CA E0
        lda DEFIO                         ; $E2F1  AD C6 2A
        sta INMASK                        ; $E2F4  8D 21 23
        lda OUTMASK                       ; $E2F7  AD 22 23
        and #$EF                          ; $E2FA  29 EF
        sta OUTMASK                       ; $E2FC  8D 22 23
        lda #$5D                          ; $E2FF  A9 5D
L_E301:
        cmp #$18                          ; $E301  C9 18
        bne L_E312                        ; $E303  D0 0D
        lda #$10                          ; $E305  A9 10
        sta INMASK                        ; $E307  8D 21 23
        jsr L_E21F                        ; $E30A  20 1F E2
        sta $238A                         ; $E30D  8D 8A 23
        bcs L_E31E                        ; $E310  B0 0C
L_E312:
        nop                               ; $E312  EA
        nop                               ; $E313  EA
        bne L_E320                        ; $E314  D0 0A
        lda OUTMASK                       ; $E316  AD 22 23
        eor #$08                          ; $E319  49 08
L_E31B:
        sta OUTMASK                       ; $E31B  8D 22 23
L_E31E:
        lda #$00                          ; $E31E  A9 00
L_E320:
        rts                               ; $E320  60

; (not reached when tracing from the known entry points)
L_E321:
        lda CHRSAV                        ; $E321  AD 63 23
        jmp L_EC6B                        ; $E324  4C 6B EC
        .byte $00,$00                     ; $E327
        and #$7F                          ; $E329  29 7F
        jmp OUTCH                         ; $E32B  4C C7 E0
OUTPOST:
        jsr L_ED8A                        ; $E32E  20 8A ED
        pha                               ; $E331  48
        and #$8D                          ; $E332  29 8D
        beq L_E33B                        ; $E334  F0 05
        cmp DEFIO                         ; $E336  CD C6 2A
        bne L_E33D                        ; $E339  D0 02
L_E33B:
        pla                               ; $E33B  68
        rts                               ; $E33C  60
L_E33D:
        lda PAGEFLG                       ; $E33D  AD B6 25
        bne L_E33B                        ; $E340  D0 F9
        ldy CHRSAV                        ; $E342  AC 63 23
        ldx PAGELEN                       ; $E345  AE A9 31
        lda ESCCNT                        ; $E348  AD C0 25
        bne L_E3B3                        ; $E34B  D0 66
        cpy #$0C                          ; $E34D  C0 0C
        beq L_E388                        ; $E34F  F0 37
        cpy #$0A                          ; $E351  C0 0A
        bne L_E37F                        ; $E353  D0 2A
        inc LINECNT                       ; $E355  EE AB 31
        cpx LINECNT                       ; $E358  EC AB 31
        bcs L_E33B                        ; $E35B  B0 DE
        bcc L_E38B                        ; $E35D  90 2C
        brk                               ; $E35F  00
        .byte $00,$EA,$EA,$A9,$01,$20,$C7,$E3,$50,$5E,$A9,$08,$20,$C7,$E3,$10; $E360
        .byte $57,$AD,$63,$23,$48,$20,$B3,$E2,$C9,$13,$F0,$F9,$4C,$C8,$E2; $E370
L_E37F:
        cpy #$1B                          ; $E37F  C0 1B
        bne L_E33B                        ; $E381  D0 B8
        dec ESCCNT                        ; $E383  CE C0 25
        bne L_E33B                        ; $E386  D0 B3
L_E388:
        inc LINECNT                       ; $E388  EE AB 31
L_E38B:
        txa                               ; $E38B  8A
        sec                               ; $E38C  38
        sbc LINECNT                       ; $E38D  ED AB 31
        sec                               ; $E390  38
        adc PAGEGAP                       ; $E391  6D AA 31
        sta PAGEFLG                       ; $E394  8D B6 25
        tax                               ; $E397  AA
        lda XSAV                          ; $E398  AD 5F 23
        ldy YSAV                          ; $E39B  AC 61 23
        pha                               ; $E39E  48
        lda #$0A                          ; $E39F  A9 0A
L_E3A1:
        jsr OUTCH                         ; $E3A1  20 C7 E0
        dex                               ; $E3A4  CA
        bne L_E3A1                        ; $E3A5  D0 FA
        txa                               ; $E3A7  8A
        sta PAGEFLG                       ; $E3A8  8D B6 25
        sta LINECNT                       ; $E3AB  8D AB 31
        pla                               ; $E3AE  68
        tax                               ; $E3AF  AA
        jmp L_EBFA                        ; $E3B0  4C FA EB
L_E3B3:
        bmi L_E3C2                        ; $E3B3  30 0D
        tya                               ; $E3B5  98
        pha                               ; $E3B6  48
        ldy #$00                          ; $E3B7  A0 00
        sec                               ; $E3B9  38
L_E3BA:
        sbc #$0A                          ; $E3BA  E9 0A
        iny                               ; $E3BC  C8
        bcs L_E3BA                        ; $E3BD  B0 FB
        jmp L_EBD9                        ; $E3BF  4C D9 EB
L_E3C2:
        jmp L_EBEC                        ; $E3C2  4C EC EB
        .byte $00,$00                     ; $E3C5
        clv                               ; $E3C7  B8
        rts                               ; $E3C8  60
SWAP213:
        ldx #$03                          ; $E3C9  A2 03
L_E3CB:
        lda $0213,x                       ; $E3CB  BD 13 02
        ldy $2657,x                       ; $E3CE  BC 57 26
        sta $2657,x                       ; $E3D1  9D 57 26
        tya                               ; $E3D4  98
        sta $0213,x                       ; $E3D5  9D 13 02
        dex                               ; $E3D8  CA
        bpl L_E3CB                        ; $E3D9  10 F0
        rts                               ; $E3DB  60

; HO / HOME - step the head out to track 0
HOME:
        jmp SD_HOME                       ; $E3DC  (SD) was JSR STEPOUT
        jsr DELAY                         ; $E3DF  20 F1 E3
        sty CURTRK                        ; $E3E2  8C 5D 26
L_E3E5:
        lda #$02                          ; $E3E5  A9 02
        bit PIAA                          ; $E3E7  2C 00 C0
        beq DELAY                         ; $E3EA  F0 05
        jsr STEP1                         ; $E3EC  20 B5 E9
        bne L_E3E5                        ; $E3EF  D0 F4
DELAY:
        ldx #$0C                          ; $E3F1  A2 0C
L_E3F3:
        ldy #$31                          ; $E3F3  A0 31
        jsr DLYY                          ; $E3F5  20 80 E4
        dex                               ; $E3F8  CA
        bne L_E3F3                        ; $E3F9  D0 F8
L_E3FB:
        rts                               ; $E3FB  60
STEPIN:
        jmp SD_STEP                       ; $E3FC  (SD) was LDA PIAB
        ora #$04                          ; $E3FF  09 04
        bne L_E408                        ; $E401  D0 05

; STEPOUT / STEPIN - one step (delay now set by DT, via $D009)
STEPOUT:
        jmp SD_STEP                       ; $E403  (SD) was LDA #$FB
        .byte $EA,$EA                     ; $E406  (SD) was AND PIAB
L_E408:
        sta PIAB                          ; $E408  8D 02 C0
        jsr L_E3FB                        ; $E40B  20 FB E3
        and #$F7                          ; $E40E  29 F7
        jsr L_E492                        ; $E410  20 92 E4
        jsr L_E486                        ; $E413  20 86 E4
        ora #$08                          ; $E416  09 08
        jsr L_E492                        ; $E418  20 92 E4
        jmp $D009                         ; $E41B  4C 09 D0
        .byte $EA                         ; $E41E
BIN2TRK:
        lda TRKBIN                        ; $E41F  AD 62 26
        sec                               ; $E422  38
        ldx #$FF                          ; $E423  A2 FF
L_E425:
        inx                               ; $E425  E8
        sbc #$0A                          ; $E426  E9 0A
        bcs L_E425                        ; $E428  B0 FB
        adc #$0A                          ; $E42A  69 0A
        sta SECPGS                        ; $E42C  85 FA
        txa                               ; $E42E  8A
        asl a                             ; $E42F  0A
        asl a                             ; $E430  0A
        asl a                             ; $E431  0A
        asl a                             ; $E432  0A
        ora SECPGS                        ; $E433  05 FA

; SEEK - step to track A (BCD). ERR #8 if not 00-39, ERR #6 drive not ready
SEEK:
        jmp SD_SEEK                       ; $E435  (SD) was STA SECPGS / PHA
        bit $E417                         ; $E438  2C 17 E4
        beq L_E441                        ; $E43B  F0 04
        and #$06                          ; $E43D  29 06
        bne L_E446                        ; $E43F  D0 05
L_E441:
        pla                               ; $E441  68
        cmp #$40                          ; $E442  C9 40
        bcc L_E44A                        ; $E444  90 04
L_E446:
        lda #$08                          ; $E446  A9 08
        bne L_E457                        ; $E448  D0 0D
L_E44A:
        lda DRIVE                         ; $E44A  AD 5C 26
        and #$01                          ; $E44D  29 01
        tay                               ; $E44F  A8
        jsr RDYCHK                        ; $E450  20 57 E7
        bcc L_E45A                        ; $E453  90 05
        lda #$06                          ; $E455  A9 06
L_E457:
        jmp ERROR                         ; $E457  4C C8 E7
L_E45A:
        lda SECPGS                        ; $E45A  A5 FA
        cmp CURTRK                        ; $E45C  CD 5D 26
        beq L_E488                        ; $E45F  F0 27
        bcs L_E46A                        ; $E461  B0 07
        jsr STEPIN                        ; $E463  20 FC E3
        lda #$99                          ; $E466  A9 99
        bcc L_E46E                        ; $E468  90 04
L_E46A:
        jsr STEPOUT                       ; $E46A  20 03 E4
        txa                               ; $E46D  8A
L_E46E:
        sed                               ; $E46E  F8
        adc CURTRK                        ; $E46F  6D 5D 26
        sta CURTRK                        ; $E472  8D 5D 26
        cld                               ; $E475  D8
        jmp L_E45A                        ; $E476  4C 5A E4
L_E479:
        lda SECPGS                        ; $E479  A5 FA
        asl a                             ; $E47B  0A
        asl a                             ; $E47C  0A
        asl a                             ; $E47D  0A
        tax                               ; $E47E  AA
        rts                               ; $E47F  60
DLYY:
        jsr L_E123                        ; $E480  20 23 E1
        dey                               ; $E483  88
        bne DLYY                          ; $E484  D0 FA
L_E486:
        nop                               ; $E486  EA
        rts                               ; $E487  60
L_E488:
        ldy #$00                          ; $E488  A0 00
        rts                               ; $E48A  60
        .byte $B0,$05,$A9,$40             ; $E48B
L_E48F:
        ora PIAB                          ; $E48F  0D 02 C0
L_E492:
        sta PIAB                          ; $E492  8D 02 C0
        rts                               ; $E495  60
WAITIDX:
        lda PIAA                          ; $E496  AD 00 C0
        bmi WAITIDX                       ; $E499  30 FB
L_E49B:
        lda PIAA                          ; $E49B  AD 00 C0
        bpl L_E49B                        ; $E49E  10 FB
        rts                               ; $E4A0  60
HLDIDX:
        jsr HLOAD                         ; $E4A1  20 CD E4
IDXRST:
        jsr WAITIDX                       ; $E4A4  20 96 E4
        lda #$03                          ; $E4A7  A9 03
        sta DACIAS                        ; $E4A9  8D 10 C0
        lda #$58                          ; $E4AC  A9 58
        sta DACIAS                        ; $E4AE  8D 10 C0
        rts                               ; $E4B1  60

; RDTRK - read a whole track raw into (MEMLO) (used by EX)
RDTRK:
        jmp SD_RDTRK                      ; $E4B2  (SD) was JSR HLDIDX
L_E4B5:
        lda PIAA                          ; $E4B5  AD 00 C0
        bpl HUNLD                         ; $E4B8  10 20
        lda DACIAS                        ; $E4BA  AD 10 C0
        lsr a                             ; $E4BD  4A
        bcc L_E4B5                        ; $E4BE  90 F5
        lda DACIAD                        ; $E4C0  AD 11 C0
        sta (MEMLO),y                     ; $E4C3  91 FE
        iny                               ; $E4C5  C8
        bne L_E4B5                        ; $E4C6  D0 ED
        inc MEMHI                         ; $E4C8  E6 FF
        jmp L_E4B5                        ; $E4CA  4C B5 E4

; HLOAD - load the head (delay now set by DT, via $D006)
HLOAD:
        jmp SD_HEAD                       ; $E4CD  (SD) was LDA #$7F
        .byte $EA,$EA                     ; $E4D0  (SD) was AND PIAB
L_E4D2:
        sta PIAB                          ; $E4D2  8D 02 C0
        jmp $D006                         ; $E4D5  4C 06 D0
        .byte $EA,$EA                     ; $E4D8

; HUNLD - unload the head
HUNLD:
        jmp SD_HEAD                       ; $E4DA  (SD) was LDA #$80 / ORA PIAB
L_E4DC = HUNLD + 2                        ; (old label, now unused code)
        .byte $EA,$EA                     ; $E4DD
        bne L_E4D2                        ; $E4DF  D0 F1

; INITALL - format tracks 00-39
INITALL:
        lda #$39                          ; $E4E1  A9 39
        sta MAXTK                         ; $E4E3  85 E5
        jsr HOME                          ; $E4E5  20 DC E3
L_E4E8:
        jsr NXTTRK                        ; $E4E8  20 E4 E9
        jsr INITTRK                       ; $E4EB  20 F6 E4
        lda CURTRK                        ; $E4EE  AD 5D 26
        cmp #$39                          ; $E4F1  C9 39
        bne L_E4E8                        ; $E4F3  D0 F3
        rts                               ; $E4F5  60

; INITTRK - format the current track (write the track header)
INITTRK:
        jmp SD_INITTRK                    ; $E4F6  (SD) was LDA #$02
        .byte $EA,$EA                     ; $E4F9  (SD) was BIT PIAA
        bne L_E501                        ; $E4FB  D0 04
        lda #$03                          ; $E4FD  A9 03
        bne L_E50A                        ; $E4FF  D0 09
L_E501:
        lda #$20                          ; $E501  A9 20
        bit PIAA                          ; $E503  2C 00 C0
        bne L_E50D                        ; $E506  D0 05
        lda #$04                          ; $E508  A9 04
L_E50A:
        jmp ERROR                         ; $E50A  4C C8 E7
L_E50D:
        jsr HLDIDX                        ; $E50D  20 A1 E4
        lda #$FC                          ; $E510  A9 FC
        and PIAB                          ; $E512  2D 02 C0
        sta PIAB                          ; $E515  8D 02 C0
        ldx #$0A                          ; $E518  A2 0A
        jsr L_E3F3                        ; $E51A  20 F3 E3
        ldx #$43                          ; $E51D  A2 43
        jsr DWRBYT                        ; $E51F  20 3B E5
        ldx #$57                          ; $E522  A2 57
        jsr DWRBYT                        ; $E524  20 3B E5
        ldx CURTRK                        ; $E527  AE 5D 26
        jsr DWRBYT                        ; $E52A  20 3B E5
        ldx #$58                          ; $E52D  A2 58
        jsr DWRBYT                        ; $E52F  20 3B E5
L_E532:
        lda PIAA                          ; $E532  AD 00 C0
        bmi L_E532                        ; $E535  30 FB
        lda #$83                          ; $E537  A9 83
        bne L_E4DC                        ; $E539  D0 A1

; DWRBYT - write X to the disk ACIA
DWRBYT:
        lda DACIAS                        ; $E53B  AD 10 C0
        lsr a                             ; $E53E  4A
        lsr a                             ; $E53F  4A
        bcc DWRBYT                        ; $E540  90 F9
        stx DACIAD                        ; $E542  8E 11 C0
        rts                               ; $E545  60

; DRDBYT - read a byte from the disk ACIA
DRDBYT:
        lda DACIAS                        ; $E546  AD 10 C0
        lsr a                             ; $E549  4A
        bcc DRDBYT                        ; $E54A  90 FA
        lda DACIAD                        ; $E54C  AD 11 C0
L_E54F:
        rts                               ; $E54F  60
        lda DMEML                         ; $E550  AD 60 26
        sta MEMLO                         ; $E553  85 FE
        lda DMEMH                         ; $E555  AD 61 26
        sta MEMHI                         ; $E558  85 FF

; WRSEC - write sector DSECT, DPAGE pages from (MEMLO), then verify
WRSEC:
        jmp SD_WRSEC                      ; $E55A  (SD) was LDA DPAGE
        beq L_E561                        ; $E55D  F0 02
        bpl L_E565                        ; $E55F  10 04
L_E561:
        lda #$0B                          ; $E561  A9 0B
L_E563:
        bne L_E50A                        ; $E563  D0 A5
L_E565:
        cmp #$09                          ; $E565  C9 09
        bpl L_E561                        ; $E567  10 F8
        lda #$02                          ; $E569  A9 02
        bit PIAA                          ; $E56B  2C 00 C0
        beq L_E54F                        ; $E56E  F0 DF
        lsr a                             ; $E570  4A
        sta SECPGS                        ; $E571  85 FA
        lda #$20                          ; $E573  A9 20
        bit PIAA                          ; $E575  2C 00 C0
        bne L_E57E                        ; $E578  D0 04
        lda #$04                          ; $E57A  A9 04
        bne L_E563                        ; $E57C  D0 E5
L_E57E:
        lda #$01                          ; $E57E  A9 01
        sta WRTRY                         ; $E580  85 F6
L_E582:
        lda #$03                          ; $E582  A9 03
        sta RDTRY2                        ; $E584  85 F8
        jsr FINDHDR                       ; $E586  20 41 E6
        jsr L_E618                        ; $E589  20 18 E6
        lda #$FE                          ; $E58C  A9 FE
        and PIAB                          ; $E58E  2D 02 C0
        sta PIAB                          ; $E591  8D 02 C0
        ldx #$02                          ; $E594  A2 02
        jsr L_E61B                        ; $E596  20 1B E6
        lda #$FF                          ; $E599  A9 FF
        and PIAB                          ; $E59B  2D 02 C0
        sta PIAB                          ; $E59E  8D 02 C0
        jsr L_E618                        ; $E5A1  20 18 E6
        ldx #$76                          ; $E5A4  A2 76
        jsr DWRBYT                        ; $E5A6  20 3B E5
        ldx DSECT                         ; $E5A9  AE 5E 26
        jsr DWRBYT                        ; $E5AC  20 3B E5
        ldx DPAGE                         ; $E5AF  AE 5F 26
        stx DTMP                          ; $E5B2  86 FD
        jsr DWRBYT                        ; $E5B4  20 3B E5
        ldy #$00                          ; $E5B7  A0 00
L_E5B9:
        lda (MEMLO),y                     ; $E5B9  B1 FE
        tax                               ; $E5BB  AA
        jsr DWRBYT                        ; $E5BC  20 3B E5
        iny                               ; $E5BF  C8
        bne L_E5B9                        ; $E5C0  D0 F7
        inc MEMHI                         ; $E5C2  E6 FF
        dec DTMP                          ; $E5C4  C6 FD
        bne L_E5B9                        ; $E5C6  D0 F1
        ldx #$47                          ; $E5C8  A2 47
        jsr DWRBYT                        ; $E5CA  20 3B E5
        ldx #$53                          ; $E5CD  A2 53
        jsr DWRBYT                        ; $E5CF  20 3B E5
        lda DPAGE                         ; $E5D2  AD 5F 26
        asl a                             ; $E5D5  0A
        sta DTMP                          ; $E5D6  85 FD
        asl a                             ; $E5D8  0A
        adc DTMP                          ; $E5D9  65 FD
        tax                               ; $E5DB  AA
        jsr L_E61B                        ; $E5DC  20 1B E6
        lda PIAB                          ; $E5DF  AD 02 C0
        ora #$01                          ; $E5E2  09 01
        sta PIAB                          ; $E5E4  8D 02 C0
        ldx #$05                          ; $E5E7  A2 05
        jsr L_E61B                        ; $E5E9  20 1B E6
        lda #$02                          ; $E5EC  A9 02
        jsr L_E48F                        ; $E5EE  20 8F E4
L_E5F1:
        clc                               ; $E5F1  18
        txa                               ; $E5F2  8A
        adc MEMHI                         ; $E5F3  65 FF
        sec                               ; $E5F5  38
        sbc DPAGE                         ; $E5F6  ED 5F 26
        sta MEMHI                         ; $E5F9  85 FF
        jsr RDCMP                         ; $E5FB  20 82 E6
        bcs L_E627                        ; $E5FE  B0 27
        dec RDTRY2                        ; $E600  C6 F8
        bne L_E5F1                        ; $E602  D0 ED
        dec WRTRY                         ; $E604  C6 F6
        bmi L_E614                        ; $E606  30 0C
        txa                               ; $E608  8A
        adc MEMHI                         ; $E609  65 FF
        sec                               ; $E60B  38
        sbc DPAGE                         ; $E60C  ED 5F 26
        sta MEMHI                         ; $E60F  85 FF
        jmp L_E582                        ; $E611  4C 82 E5
L_E614:
        lda #$02                          ; $E614  A9 02
        bne L_E63E                        ; $E616  D0 26
L_E618:
        jsr L_E479                        ; $E618  20 79 E4
L_E61B:
        lda #$31                          ; $E61B  A9 31
L_E61D:
        bit $00                           ; $E61D  24 00
        sec                               ; $E61F  38
        sbc #$05                          ; $E620  E9 05
        bcs L_E61D                        ; $E622  B0 F9
        dex                               ; $E624  CA
        bne L_E61B                        ; $E625  D0 F4
L_E627:
        rts                               ; $E627  60
DRDIDX:
        lda PIAA                          ; $E628  AD 00 C0
        bmi L_E632                        ; $E62B  30 05
        lda NOERR9                        ; $E62D  AD B4 28
        beq L_E63C                        ; $E630  F0 0A
L_E632:
        lda DACIAS                        ; $E632  AD 10 C0
        lsr a                             ; $E635  4A
        bcc DRDIDX                        ; $E636  90 F0
        lda DACIAD                        ; $E638  AD 11 C0
        rts                               ; $E63B  60
L_E63C:
        lda #$09                          ; $E63C  A9 09
L_E63E:
        jmp ERROR                         ; $E63E  4C C8 E7

; FINDHDR - find the track header, then skip to the end of sector DSECT-1
FINDHDR:
        jmp SD_FINDHDR                    ; $E641  (SD) was JSR IDXRST
L_E644:
        jsr DRDIDX                        ; $E644  20 28 E6
L_E647:
        cmp #$43                          ; $E647  C9 43
        bne L_E644                        ; $E649  D0 F9
        jsr DRDIDX                        ; $E64B  20 28 E6
        cmp #$57                          ; $E64E  C9 57
        bne L_E647                        ; $E650  D0 F5
        jsr DRDBYT                        ; $E652  20 46 E5
        cmp CURTRK                        ; $E655  CD 5D 26
        beq L_E65E                        ; $E658  F0 04
        lda #$05                          ; $E65A  A9 05
        bne L_E63E                        ; $E65C  D0 E0
L_E65E:
        jsr DRDBYT                        ; $E65E  20 46 E5
        dec DSECT                         ; $E661  CE 5E 26
        beq L_E67A                        ; $E664  F0 14
        lda #$00                          ; $E666  A9 00
        sta SECCNT                        ; $E668  85 F9
L_E66A:
        jsr NXTSEC                        ; $E66A  20 15 E7
        bcc L_E67E                        ; $E66D  90 0F
        lda DSECT                         ; $E66F  AD 5E 26
        cmp SECCNT                        ; $E672  C5 F9
        bne L_E66A                        ; $E674  D0 F4
        cmp SECNO                         ; $E676  C5 FB
        bne L_E67E                        ; $E678  D0 04
L_E67A:
        inc DSECT                         ; $E67A  EE 5E 26
        rts                               ; $E67D  60
L_E67E:
        lda #$0A                          ; $E67E  A9 0A
        bne L_E63E                        ; $E680  D0 BC

; RDCMP - read (A=0) or compare (A<>0) sector DSECT at (MEMLO). C=1 ok
RDCMP:
        pha                               ; $E682  48
        jsr FINDHDR                       ; $E683  20 41 E6
L_E686:
        jsr DRDIDX                        ; $E686  20 28 E6
        cmp #$76                          ; $E689  C9 76
        bne L_E686                        ; $E68B  D0 F9
        jsr DRDBYT                        ; $E68D  20 46 E5
        cmp DSECT                         ; $E690  CD 5E 26
        beq L_E698                        ; $E693  F0 03
        pla                               ; $E695  68
L_E696:
        clc                               ; $E696  18
        rts                               ; $E697  60
L_E698:
        jsr DRDBYT                        ; $E698  20 46 E5
        tax                               ; $E69B  AA
        sta DPAGE                         ; $E69C  8D 5F 26
        ldy #$00                          ; $E69F  A0 00
        pla                               ; $E6A1  68
        beq L_E6C0                        ; $E6A2  F0 1C
L_E6A4:
        lda DACIAS                        ; $E6A4  AD 10 C0
        lsr a                             ; $E6A7  4A
        bcc L_E6A4                        ; $E6A8  90 FA
        lda DACIAD                        ; $E6AA  AD 11 C0
        bit DACIAS                        ; $E6AD  2C 10 C0
        bvs L_E696                        ; $E6B0  70 E4
        cmp (MEMLO),y                     ; $E6B2  D1 FE
        bne L_E696                        ; $E6B4  D0 E0
        iny                               ; $E6B6  C8
        bne L_E6A4                        ; $E6B7  D0 EB
        inc MEMHI                         ; $E6B9  E6 FF
        dex                               ; $E6BB  CA
        bne L_E6A4                        ; $E6BC  D0 E6
        sec                               ; $E6BE  38
        rts                               ; $E6BF  60
L_E6C0:
        lda DACIAS                        ; $E6C0  AD 10 C0
        lsr a                             ; $E6C3  4A
        bcc L_E6C0                        ; $E6C4  90 FA
        lda DACIAD                        ; $E6C6  AD 11 C0
        bit DACIAS                        ; $E6C9  2C 10 C0
        bvs L_E696                        ; $E6CC  70 C8
        sta (MEMLO),y                     ; $E6CE  91 FE
        iny                               ; $E6D0  C8
        bne L_E6C0                        ; $E6D1  D0 ED
        inc MEMHI                         ; $E6D3  E6 FF
        dex                               ; $E6D5  CA
        bne L_E6C0                        ; $E6D6  D0 E8
        sec                               ; $E6D8  38
        rts                               ; $E6D9  60
        lda DMEML                         ; $E6DA  AD 60 26
        sta MEMLO                         ; $E6DD  85 FE
        lda DMEMH                         ; $E6DF  AD 61 26
        sta MEMHI                         ; $E6E2  85 FF

; RDSEC - read sector DSECT to (MEMLO) with retries, ERR #1 on failure
RDSEC:
        jmp SD_RDSEC                      ; $E6E4  (SD) was LDA #$03 / STA RDTRY
        .byte $EA                         ; $E6E7
L_E6E8:
        lda #$07                          ; $E6E8  A9 07
        sta RDTRY2                        ; $E6EA  85 F8
L_E6EC:
        lda #$00                          ; $E6EC  A9 00
        jsr RDCMP                         ; $E6EE  20 82 E6
        bcc L_E6F7                        ; $E6F1  90 04
        rts                               ; $E6F3  60
L_E6F4:
        dec MEMHI                         ; $E6F4  C6 FF
        inx                               ; $E6F6  E8
L_E6F7:
        cpx DPAGE                         ; $E6F7  EC 5F 26
        bne L_E6F4                        ; $E6FA  D0 F8
        dec RDTRY2                        ; $E6FC  C6 F8
        bne L_E6EC                        ; $E6FE  D0 EC
        jsr STEPIN                        ; $E700  20 FC E3
        jsr DELAY                         ; $E703  20 F1 E3
        jsr STEPOUT                       ; $E706  20 03 E4
        jsr DELAY                         ; $E709  20 F1 E3
        dec RDTRY                         ; $E70C  C6 F7
        bpl L_E6E8                        ; $E70E  10 D8
        lda #$01                          ; $E710  A9 01
        jmp ERROR                         ; $E712  4C C8 E7

; NXTSEC - skip the next sector: C=1 found (SECNO, SECPGS), C=0 index hole
NXTSEC:
        jmp SD_NXTSEC                     ; $E715  (SD) was LDA PIAA
        bpl L_E741                        ; $E718  10 27
        lda DACIAS                        ; $E71A  AD 10 C0
        lsr a                             ; $E71D  4A
        bcc NXTSEC                        ; $E71E  90 F5
        lda DACIAD                        ; $E720  AD 11 C0
        cmp #$76                          ; $E723  C9 76
        bne NXTSEC                        ; $E725  D0 EE
        jsr DRDBYT                        ; $E727  20 46 E5
        sta SECNO                         ; $E72A  85 FB
        jsr DRDBYT                        ; $E72C  20 46 E5
        sta SECPGS                        ; $E72F  85 FA
        inc SECCNT                        ; $E731  E6 F9
        tay                               ; $E733  A8
        ldx #$00                          ; $E734  A2 00
L_E736:
        jsr DRDBYT                        ; $E736  20 46 E5
        dex                               ; $E739  CA
        bne L_E736                        ; $E73A  D0 FA
        dey                               ; $E73C  88
        bne L_E736                        ; $E73D  D0 F7
        sec                               ; $E73F  38
        rts                               ; $E740  60
L_E741:
        clc                               ; $E741  18
        rts                               ; $E742  60

; SELDRV - select drive A (1-4)
SELDRV:
        jmp SD_SELDRV                     ; $E743  (SD) was STA DRIVE
        asl a                             ; $E746  0A
        tax                               ; $E747  AA
        and #$02                          ; $E748  29 02
        tay                               ; $E74A  A8
        lda L_E766,x                      ; $E74B  BD 66 E7
        sta PIAA                          ; $E74E  8D 00 C0
        lda $E767,x                       ; $E751  BD 67 E7
        sta PIAB                          ; $E754  8D 02 C0
RDYCHK:
        jmp SD_RDYCHK                     ; $E757  (SD) was LDA PIAA
        lsr a                             ; $E75A  4A
        php                               ; $E75B  08
        cpy #$00                          ; $E75C  C0 00
        bne L_E766                        ; $E75E  D0 06
        plp                               ; $E760  28
        lsr a                             ; $E761  4A
        lsr a                             ; $E762  4A
        lsr a                             ; $E763  4A
        lsr a                             ; $E764  4A
        rts                               ; $E765  60
L_E766:
        plp                               ; $E766  28
        rts                               ; $E767  60
        .byte $40,$FF,$00,$FF,$40,$DF,$00,$DF; $E768

; SECMAP - list the sectors of a track (DI tt)
SECMAP:
        tax                               ; $E770  AA
        beq L_E741                        ; $E771  F0 CE
        pha                               ; $E773  48
        jsr SEEK                          ; $E774  20 35 E4
        jsr PRINT                         ; $E777  20 D6 EA
        .byte $0D, $0A, "TRACK ", $00     ; $E77A
        pla                               ; $E783  68
        jsr PRHEX                         ; $E784  20 F5 EA
        tsx                               ; $E787  BA
        stx SPSAV                         ; $E788  86 FC
        jsr HLOAD                         ; $E78A  20 CD E4
        inx                               ; $E78D  E8
        stx DSECT                         ; $E78E  8E 5E 26
        jsr FINDHDR                       ; $E791  20 41 E6
        lda #$00                          ; $E794  A9 00
        sta SECCNT                        ; $E796  85 F9
L_E798:
        jsr NXTSEC                        ; $E798  20 15 E7
        lda SECNO                         ; $E79B  A5 FB
        pha                               ; $E79D  48
        lda SECPGS                        ; $E79E  A5 FA
        pha                               ; $E7A0  48
        bcs L_E798                        ; $E7A1  B0 F5
        ldx SPSAV                         ; $E7A3  A6 FC
        bcc L_E7B4                        ; $E7A5  90 0D
L_E7A7:
        jsr CRLF                          ; $E7A7  20 CD EA
        lda #$20                          ; $E7AA  A9 20
        jsr L_E7BE                        ; $E7AC  20 BE E7
        lda #$2D                          ; $E7AF  A9 2D
        jsr L_E7BE                        ; $E7B1  20 BE E7
L_E7B4:
        dec SECCNT                        ; $E7B4  C6 F9
        bpl L_E7A7                        ; $E7B6  10 EF
        ldx SPSAV                         ; $E7B8  A6 FC
        txs                               ; $E7BA  9A
        jmp HUNLD                         ; $E7BB  4C DA E4
L_E7BE:
        jsr OUTCH                         ; $E7BE  20 C7 E0
        lda $0100,x                       ; $E7C1  BD 00 01
        dex                               ; $E7C4  CA
        jmp PRHEX                         ; $E7C5  4C F5 EA

; ERROR - print ERR #A and leave through ERRJMP ($2A4E)
ERROR:
        jsr PRERR                         ; $E7C8  20 41 E8
        jmp ERRJMP                        ; $E7CB  4C 4E 2A

; PROMPT - command loop: drive letter, *, read and run a line
PROMPT:
        ldx #$28                          ; $E7CE  A2 28
        txs                               ; $E7D0  9A
        lda #$CE                          ; $E7D1  A9 CE
        ldy #$E7                          ; $E7D3  A0 E7
        jsr SETERR                        ; $E7D5  20 FA E7
        jsr CRLF                          ; $E7D8  20 CD EA
        lda DRIVE                         ; $E7DB  AD 5C 26
        clc                               ; $E7DE  18
        adc #$40                          ; $E7DF  69 40
        jsr OUTCH                         ; $E7E1  20 C7 E0
        lda #$2A                          ; $E7E4  A9 2A
        jsr OUTCH                         ; $E7E6  20 C7 E0
        jsr L_E9FC                        ; $E7E9  20 FC E9
        lda #$2E                          ; $E7EC  A9 2E
        sta INBUFH                        ; $E7EE  85 E2
        lda #$1E                          ; $E7F0  A9 1E
        sta INBUF                         ; $E7F2  85 E1
        jsr DOCMD                         ; $E7F4  20 01 E8
        jmp PROMPT                        ; $E7F7  4C CE E7
SETERR:
        sta ERRVEC                        ; $E7FA  8D 4F 2A
        sty $2A50                         ; $E7FD  8C 50 2A
        rts                               ; $E800  60

; DOCMD - look up the command line in CMDTAB and run it
DOCMD:
        ldx #$00                          ; $E801  A2 00
        stx CMDPOS                        ; $E803  8E E5 2C
L_E806:
        ldy #$00                          ; $E806  A0 00
        lda CMDTAB,x                      ; $E808  BD 81 EB
        beq BADCMD                        ; $E80B  F0 30
        jsr L_ED02                        ; $E80D  20 02 ED
        nop                               ; $E810  EA
        iny                               ; $E811  C8
        lda D_EB82,x                      ; $E812  BD 82 EB
        jsr L_ED02                        ; $E815  20 02 ED
        nop                               ; $E818  EA
        lda D_EB84,x                      ; $E819  BD 84 EB
        pha                               ; $E81C  48
        lda D_EB83,x                      ; $E81D  BD 83 EB
        pha                               ; $E820  48

; SKIPAR - skip the command word and following spaces
SKIPAR:
        jsr GETCH                         ; $E821  20 45 EA
        cmp #$0D                          ; $E824  C9 0D
        beq L_E836                        ; $E826  F0 0E
        cmp #$20                          ; $E828  C9 20
        bne SKIPAR                        ; $E82A  D0 F5
L_E82C:
        jsr GETCH                         ; $E82C  20 45 EA
        cmp #$20                          ; $E82F  C9 20
        beq L_E82C                        ; $E831  F0 F9
        dec CMDPOS                        ; $E833  CE E5 2C
L_E836:
        rts                               ; $E836  60
L_E837:
        inx                               ; $E837  E8
        inx                               ; $E838  E8
        inx                               ; $E839  E8
        inx                               ; $E83A  E8
        bne L_E806                        ; $E83B  D0 C9

; BADCMD - command not in the table: SY, then the extensions
BADCMD:
        jmp SDDISP                        ; $E83D  (SD) was JMP CHKSY - adds MO
        .byte $EA                         ; $E840

; PRERR - print " ERR #n"
PRERR:
        pha                               ; $E841  48
        lda DEFIO                         ; $E842  AD C6 2A
        sta INMASK                        ; $E845  8D 21 23
        sta OUTMASK                       ; $E848  8D 22 23
        jsr PRINT                         ; $E84B  20 D6 EA
        .byte " ERR #", $00               ; $E84E
        pla                               ; $E855  68
        jsr PRNIB                         ; $E856  20 FE EA
        jmp HUNLD                         ; $E859  4C DA E4

; (not reached when tracing from the known entry points)
L_E85C:
        lda #$07                          ; $E85C  A9 07
        jsr LOADSYS                       ; $E85E  20 6C E8
        jmp $1300                         ; $E861  4C 00 13

; (not reached when tracing from the known entry points)
L_E864:
        lda #$02                          ; $E864  A9 02
        jsr LOADSYS                       ; $E866  20 6C E8
        jmp $20E4                         ; $E869  4C E4 20

; LOADSYS - load a system track (BASIC, assembler, EM)
LOADSYS:
        jsr SEEK                          ; $E86C  20 35 E4
        ldx #$02                          ; $E86F  A2 02
        stx ZTMP                          ; $E871  86 E0
        stx MEMHI                         ; $E873  86 FF
        dex                               ; $E875  CA
        stx DSECT                         ; $E876  8E 5E 26
        dex                               ; $E879  CA
        stx MEMLO                         ; $E87A  86 FE
        dex                               ; $E87C  CA
        stx MAXTK                         ; $E87D  86 E5
        jsr L_EBD2                        ; $E87F  20 D2 EB
L_E882:
        jsr RDSECP                        ; $E882  20 24 F0
        dec ZTMP                          ; $E885  C6 E0
        bmi L_E89E                        ; $E887  30 15
        jsr NXTTRK                        ; $E889  20 E4 E9
        jmp L_E882                        ; $E88C  4C 82 E8

; CA mmmm=tt,s - load a sector into memory
CMD_CA:
        jsr GETADR                        ; $E88F  20 86 EA
        jsr EXPEQ                         ; $E892  20 BB EA
        jsr GETTS                         ; $E895  20 C1 E9
RDHEAD:
        jsr HLOAD                         ; $E898  20 CD E4
L_E89B:
        jsr RDSECP                        ; $E89B  20 24 F0
L_E89E:
        jmp HUNLD                         ; $E89E  4C DA E4

; (not reached when tracing from the known entry points)
L_E8A1:
        lda #$01                          ; $E8A1  A9 01
        sta NOERR9                        ; $E8A3  8D B4 28
        rts                               ; $E8A6  60

; (not reached when tracing from the known entry points)
L_E8A7:
        jsr GETHX                         ; $E8A7  20 91 EA
        jmp SECMAP                        ; $E8AA  4C 70 E7

; (not reached when tracing from the known entry points)
L_E8AD:
        lda #$07                          ; $E8AD  A9 07
        jsr LOADSYS                       ; $E8AF  20 6C E8
        jmp $1700                         ; $E8B2  4C 00 17

; EX mmmm=tt - read a whole track (raw) into memory
CMD_EX:
        jsr GETADR                        ; $E8B5  20 86 EA
        jsr EXPEQ                         ; $E8B8  20 BB EA
        jsr GETHX                         ; $E8BB  20 91 EA
        jsr SEEK                          ; $E8BE  20 35 E4
        jmp RDTRK                         ; $E8C1  4C B2 E4

; GO mmmm - jump to an address
CMD_GO:
        jsr GETHX                         ; $E8C4  20 91 EA
        sta $2B54                         ; $E8C7  8D 54 2B
        jsr GETHX                         ; $E8CA  20 91 EA
        sta $2B53                         ; $E8CD  8D 53 2B
        jmp $2B52                         ; $E8D0  4C 52 2B

; IN [tt] - format one track, or (after ARE YOU SURE?) the whole disk
CMD_IN:
        jsr GETCH                         ; $E8D3  20 45 EA
        cmp #$0D                          ; $E8D6  C9 0D
        beq L_E8E6                        ; $E8D8  F0 0C
        dec CMDPOS                        ; $E8DA  CE E5 2C
        jsr GETHX                         ; $E8DD  20 91 EA
        jsr SEEK                          ; $E8E0  20 35 E4
        jmp INITTRK                       ; $E8E3  4C F6 E4
L_E8E6:
        jsr PRINT                         ; $E8E6  20 D6 EA
        .byte "ARE YOU SURE?", $00        ; $E8E9
        jsr GETKEY                        ; $E8F7  20 C4 E0
        cmp #$59                          ; $E8FA  C9 59
        bne L_E924                        ; $E8FC  D0 26
        jmp INITALL                       ; $E8FE  4C E1 E4

; IO ii,oo - set input/output device masks
CMD_IO:
        jsr GETCH                         ; $E901  20 45 EA
        cmp #$2C                          ; $E904  C9 2C
        beq L_E91E                        ; $E906  F0 16
        dec CMDPOS                        ; $E908  CE E5 2C
        jsr GETHX                         ; $E90B  20 91 EA
        sta INMASK                        ; $E90E  8D 21 23
        jsr GETCH                         ; $E911  20 45 EA
        cmp #$0D                          ; $E914  C9 0D
        beq L_E924                        ; $E916  F0 0C
        dec CMDPOS                        ; $E918  CE E5 2C
        jsr L_EABE                        ; $E91B  20 BE EA
L_E91E:
        jsr GETHX                         ; $E91E  20 91 EA
        sta OUTMASK                       ; $E921  8D 22 23
L_E924:
        rts                               ; $E924  60

; LO name|tt - load a file into the workspace ($3A79)
CMD_LO:
        jsr FINDFILE                      ; $E925  20 09 EB
        jsr WSSEEK                        ; $E928  20 D1 E9
        stx ZTMP                          ; $E92B  86 E0
        beq L_E932                        ; $E92D  F0 03
L_E92F:
        jsr NXTTRK                        ; $E92F  20 E4 E9
L_E932:
        jsr RDSECP                        ; $E932  20 24 F0
        inc ZTMP                          ; $E935  E6 E0
        dec WSTRK                         ; $E937  CE 7D 3A
        bne L_E92F                        ; $E93A  D0 F3
        lda ZTMP                          ; $E93C  A5 E0
        sta WSTRK                         ; $E93E  8D 7D 3A
        jmp L_EC11                        ; $E941  4C 11 EC

; ME iiii,oooo - memory device input/output pointers
CMD_ME:
        ldx #$00                          ; $E944  A2 00
        jsr L_E94E                        ; $E946  20 4E E9
        jsr L_EABE                        ; $E949  20 BE EA
        ldx #$07                          ; $E94C  A2 07
L_E94E:
        jsr GETHX                         ; $E94E  20 91 EA
        sta $238B,x                       ; $E951  9D 8B 23
        jsr GETHX                         ; $E954  20 91 EA
        sta $238A,x                       ; $E957  9D 8A 23
        rts                               ; $E95A  60

; PU name|tt - save the workspace
CMD_PU:
        jmp PUENT                         ; $E95B  4C 52 FE

; RE A|B|E|M - re-enter assembler, BASIC, EM or monitor
CMD_RE:
        jsr GETCH                         ; $E95E  20 45 EA
        cmp #$41                          ; $E961  C9 41
        bne L_E968                        ; $E963  D0 03
        jmp $2C04                         ; $E965  4C 04 2C
L_E968:
        cmp #$42                          ; $E968  C9 42
        bne L_E96F                        ; $E96A  D0 03
        jmp $2C0B                         ; $E96C  4C 0B 2C
L_E96F:
        cmp #$45                          ; $E96F  C9 45
        bne L_E976                        ; $E971  D0 03
        jmp $2C12                         ; $E973  4C 12 2C
L_E976:
        cmp #$4D                          ; $E976  C9 4D
        bne L_E980                        ; $E978  D0 06
        jsr SWAP213                       ; $E97A  20 C9 E3
        jmp ($FEFC)                       ; $E97D  6C FC FE
L_E980:
        jmp BADCMD                        ; $E980  4C 3D E8

; XQ name - load a file and run it at $3A7E
CMD_XQ:
        jsr CMD_LO                        ; $E983  20 25 E9
        jmp WSSTART                       ; $E986  4C 7E 3A

; SA tt,s=mmmm/p - save p pages of memory as a sector
CMD_SA:
        jsr GETTS                         ; $E989  20 C1 E9
        jsr EXPEQ                         ; $E98C  20 BB EA
        jsr GETADR                        ; $E98F  20 86 EA
        jsr L_EAC1                        ; $E992  20 C1 EA
        jsr GETNIB                        ; $E995  20 A0 EA
        sta DPAGE                         ; $E998  8D 5F 26
        jsr HLOAD                         ; $E99B  20 CD E4
        jsr WRSEC                         ; $E99E  20 5A E5
        jmp HUNLD                         ; $E9A1  4C DA E4

; SE A-D - select a drive
CMD_SE:
        jsr GETCH                         ; $E9A4  20 45 EA
        sbc #$3F                          ; $E9A7  E9 3F
        cmp #$05                          ; $E9A9  C9 05
        bcs L_E9BC                        ; $E9AB  B0 0F
        sta DTMP                          ; $E9AD  85 FD
        jsr SELDRV                        ; $E9AF  20 43 E7
        jmp HOME                          ; $E9B2  4C DC E3
STEP1:
        jsr STEPIN                        ; $E9B5  20 FC E3
        inc DTMP                          ; $E9B8  E6 FD
        bne L_E9D0                        ; $E9BA  D0 14
L_E9BC:
        lda #$06                          ; $E9BC  A9 06
L_E9BE:
        jmp ERROR                         ; $E9BE  4C C8 E7

; GETTS - parse tt,s
GETTS:
        jsr GETHX                         ; $E9C1  20 91 EA
        jsr SEEK                          ; $E9C4  20 35 E4
        jsr L_EABE                        ; $E9C7  20 BE EA
        jsr GETNIB                        ; $E9CA  20 A0 EA
        sta DSECT                         ; $E9CD  8D 5E 26
L_E9D0:
        rts                               ; $E9D0  60
WSSEEK:
        jsr SEEK                          ; $E9D1  20 35 E4
        lda #$3A                          ; $E9D4  A9 3A
        sta MEMHI                         ; $E9D6  85 FF
        lda #$79                          ; $E9D8  A9 79
        sta MEMLO                         ; $E9DA  85 FE
        lda #$01                          ; $E9DC  A9 01
        sta DSECT                         ; $E9DE  8D 5E 26
        jmp HLOAD                         ; $E9E1  4C CD E4
NXTTRK:
        lda CURTRK                        ; $E9E4  AD 5D 26
        clc                               ; $E9E7  18
        sed                               ; $E9E8  F8
        adc #$01                          ; $E9E9  69 01
        cld                               ; $E9EB  D8
        cmp MAXTK                         ; $E9EC  C5 E5
L_E9EE:
        beq L_E9F2                        ; $E9EE  F0 02
        bcs L_E9F5                        ; $E9F0  B0 03
L_E9F2:
        jmp SEEK                          ; $E9F2  4C 35 E4
L_E9F5:
        lda #$0D                          ; $E9F5  A9 0D
        bne L_E9BE                        ; $E9F7  D0 C5

; GETLIN - read a command line into CMDBUF
GETLIN:
        jsr CRLF                          ; $E9F9  20 CD EA
L_E9FC:
        lda #$28                          ; $E9FC  A9 28
        sta CMDLEN                        ; $E9FE  8D ED 2C
        ldx #$00                          ; $EA01  A2 00
L_EA03:
        jsr GETKEY                        ; $EA03  20 C4 E0
        cmp #$5F                          ; $EA06  C9 5F
        bne L_EA1D                        ; $EA08  D0 13
        dex                               ; $EA0A  CA
        bmi GETLIN                        ; $EA0B  30 EC
        sta CMDBUF,x                      ; $EA0D  9D 1E 2E
        jsr PRINT                         ; $EA10  20 D6 EA
        .byte $08, $08, "  ", $08, $08, $00; $EA13
        jmp L_EA03                        ; $EA1A  4C 03 EA
L_EA1D:
        cmp #$15                          ; $EA1D  C9 15
        beq GETLIN                        ; $EA1F  F0 D8
L_EA21:
        sta CMDBUF,x                      ; $EA21  9D 1E 2E
        cmp #$0D                          ; $EA24  C9 0D
        beq L_EA31                        ; $EA26  F0 09
        inx                               ; $EA28  E8
        cpx #$28                          ; $EA29  E0 28
        bne L_EA03                        ; $EA2B  D0 D6
        lda #$0D                          ; $EA2D  A9 0D
        bne L_EA21                        ; $EA2F  D0 F0
L_EA31:
        jmp CRLF                          ; $EA31  4C CD EA
        .byte $00,$00,$00                 ; $EA34
GETCHR:
        jsr SAVREG                        ; $EA37  20 EE E0
L_EA3A:
        jsr INCHR                         ; $EA3A  20 BD E0
        jsr SPECKEY                       ; $EA3D  20 D5 E2
        beq L_EA3A                        ; $EA40  F0 F8
        jmp RESREG                        ; $EA42  4C E2 E0

; GETCH - next command line character (upper case), CR at the end
GETCH:
        ldy CMDPOS                        ; $EA45  AC E5 2C
        lda (INBUF),y                     ; $EA48  B1 E1
        jmp GETCHU                        ; $EA4A  4C 1A F0
        .byte $EA                         ; $EA4D
L_EA4E:
        cpy CMDLEN                        ; $EA4E  CC ED 2C
        beq L_EA57                        ; $EA51  F0 04
        inc CMDPOS                        ; $EA53  EE E5 2C
        rts                               ; $EA56  60
L_EA57:
        lda #$0D                          ; $EA57  A9 0D
        rts                               ; $EA59  60

; SWAPZP - swap zero page and stack with the DOS copies (DISK! from BASIC)
SWAPZP:
        pla                               ; $EA5A  68
        clc                               ; $EA5B  18
        adc #$01                          ; $EA5C  69 01
        sta SWPRL                         ; $EA5E  8D 21 2D
        pla                               ; $EA61  68
        adc #$00                          ; $EA62  69 00
        sta SWPRH                         ; $EA64  8D 22 2D
        ldx #$00                          ; $EA67  A2 00
L_EA69:
        lda $0100,x                       ; $EA69  BD 00 01
        ldy STKSAVE,x                     ; $EA6C  BC 79 30
        sta STKSAVE,x                     ; $EA6F  9D 79 30
        tya                               ; $EA72  98
        sta $0100,x                       ; $EA73  9D 00 01
        lda $00,x                         ; $EA76  B5 00
        ldy ZPSAVE,x                      ; $EA78  BC 79 2F
        sta ZPSAVE,x                      ; $EA7B  9D 79 2F
        sty $00,x                         ; $EA7E  94 00
        inx                               ; $EA80  E8
        bne L_EA69                        ; $EA81  D0 E6
        jmp SWPRET                        ; $EA83  4C 20 2D

; GETADR - 4 hex digits to MEMLO/MEMHI
GETADR:
        jsr GETHX                         ; $EA86  20 91 EA
        sta MEMHI                         ; $EA89  85 FF
        jsr GETHX                         ; $EA8B  20 91 EA
        sta MEMLO                         ; $EA8E  85 FE
        rts                               ; $EA90  60

; GETHX - 2 hex digits to A
GETHX:
        jsr GETNIB                        ; $EA91  20 A0 EA
        asl a                             ; $EA94  0A
        asl a                             ; $EA95  0A
        asl a                             ; $EA96  0A
        asl a                             ; $EA97  0A
        sta ZTMP                          ; $EA98  85 E0
        jsr GETNIB                        ; $EA9A  20 A0 EA
        ora ZTMP                          ; $EA9D  05 E0
        rts                               ; $EA9F  60
GETNIB:
        jsr GETCH                         ; $EAA0  20 45 EA
        sec                               ; $EAA3  38
        sbc #$30                          ; $EAA4  E9 30
        cmp #$0A                          ; $EAA6  C9 0A
        bcc L_EAB2                        ; $EAA8  90 08
        sbc #$11                          ; $EAAA  E9 11
        cmp #$06                          ; $EAAC  C9 06
        bcs SYNERR                        ; $EAAE  B0 08
        adc #$0A                          ; $EAB0  69 0A
L_EAB2:
        rts                               ; $EAB2  60
        lda $00                           ; $EAB3  A5 00
        beq SWAPZP                        ; $EAB5  F0 A3
        rts                               ; $EAB7  60
SYNERR:
        jmp BADCMD                        ; $EAB8  4C 3D E8
EXPEQ:
        lda #$3D                          ; $EABB  A9 3D
D_EABD:
        bit $2CA9                         ; $EABD  2C A9 2C
L_EABE = D_EABD + 1   ; entry into the middle of the instruction above
        .byte $2C                         ; $EAC0
L_EAC1:
        lda #$2F                          ; $EAC1  A9 2F
        sta ZTMP                          ; $EAC3  85 E0
        jsr GETCH                         ; $EAC5  20 45 EA
        cmp ZTMP                          ; $EAC8  C5 E0
        bne SYNERR                        ; $EACA  D0 EC
        rts                               ; $EACC  60

; CRLF
CRLF:
        lda #$0D                          ; $EACD  A9 0D
        jsr OUTCH                         ; $EACF  20 C7 E0
        lda #$0A                          ; $EAD2  A9 0A
        bne L_EB06                        ; $EAD4  D0 30

; PRINT - print the 0-terminated string that follows the JSR
PRINT:
        pla                               ; $EAD6  68
        sta PRPTR                         ; $EAD7  85 E3
        pla                               ; $EAD9  68
        sta PRPTRH                        ; $EADA  85 E4
        ldy #$01                          ; $EADC  A0 01
L_EADE:
        lda (PRPTR),y                     ; $EADE  B1 E3
        beq L_EAE8                        ; $EAE0  F0 06
        jsr OUTCH                         ; $EAE2  20 C7 E0
        iny                               ; $EAE5  C8
        bne L_EADE                        ; $EAE6  D0 F6
L_EAE8:
        tya                               ; $EAE8  98
        sec                               ; $EAE9  38
        adc PRPTR                         ; $EAEA  65 E3
        sta PRPTR                         ; $EAEC  85 E3
        bcc L_EAF2                        ; $EAEE  90 02
        inc PRPTRH                        ; $EAF0  E6 E4
L_EAF2:
        jmp (PRPTR)                       ; $EAF2  6C E3 00

; PRHEX - print A as 2 hex digits
PRHEX:
        pha                               ; $EAF5  48
        lsr a                             ; $EAF6  4A
        lsr a                             ; $EAF7  4A
        lsr a                             ; $EAF8  4A
        lsr a                             ; $EAF9  4A
        jsr PRNIB                         ; $EAFA  20 FE EA
        pla                               ; $EAFD  68
PRNIB:
        and #$0F                          ; $EAFE  29 0F
        cmp #$0A                          ; $EB00  C9 0A
        sed                               ; $EB02  F8
        adc #$30                          ; $EB03  69 30
        cld                               ; $EB05  D8
L_EB06:
        jmp OUTCH                         ; $EB06  4C C7 E0

; FINDFILE - file name or track number to start track
FINDFILE:
        lda #$39                          ; $EB09  A9 39
        sta MAXTK                         ; $EB0B  85 E5
        jsr GETCH                         ; $EB0D  20 45 EA
        dec CMDPOS                        ; $EB10  CE E5 2C
        cmp #$41                          ; $EB13  C9 41
        bpl L_EB21                        ; $EB15  10 0A
        ldx #$00                          ; $EB17  A2 00
        lda #$39                          ; $EB19  A9 39
        sta $2E7A,x                       ; $EB1B  9D 7A 2E
        jmp GETHX                         ; $EB1E  4C 91 EA
L_EB21:
        jmp L_F1B3                        ; $EB21  4C B3 F1

; (not reached when tracing from the known entry points)
L_EB24:
        sta ZTMP                          ; $EB24  85 E0
        lda #$12                          ; $EB26  A9 12
        jsr SEEK                          ; $EB28  20 35 E4
        sty DSECT                         ; $EB2B  8C 5E 26
        jmp L_EB63                        ; $EB2E  4C 63 EB
        .byte $A2,$00                     ; $EB31
L_EB33:
        jsr GETCH                         ; $EB33  20 45 EA
        cmp #$0D                          ; $EB36  C9 0D
        bne L_EB3C                        ; $EB38  D0 02
        lda #$20                          ; $EB3A  A9 20
L_EB3C:
        jsr L_ED0C                        ; $EB3C  20 0C ED
        bne L_EB52                        ; $EB3F  D0 11
        inx                               ; $EB41  E8
        txa                               ; $EB42  8A
        and #$07                          ; $EB43  29 07
        cmp #$06                          ; $EB45  C9 06
        bne L_EB33                        ; $EB47  D0 EA
        lda $2E7A,x                       ; $EB49  BD 7A 2E
        sta MAXTK                         ; $EB4C  85 E5
        lda DIRSEC,x                      ; $EB4E  BD 79 2E
        rts                               ; $EB51  60
L_EB52:
        txa                               ; $EB52  8A
        and #$F8                          ; $EB53  29 F8
        clc                               ; $EB55  18
        adc #$08                          ; $EB56  69 08
        tax                               ; $EB58  AA
        beq L_EB63                        ; $EB59  F0 08
L_EB5B:
        lda ZTMP                          ; $EB5B  A5 E0
        sta CMDPOS                        ; $EB5D  8D E5 2C
        jmp L_EB33                        ; $EB60  4C 33 EB
L_EB63:
        inc DSECT                         ; $EB63  EE 5E 26
        lda DSECT                         ; $EB66  AD 5E 26
        cmp #$03                          ; $EB69  C9 03
        bmi L_EB72                        ; $EB6B  30 05
        lda #$0C                          ; $EB6D  A9 0C
        jmp ERROR                         ; $EB6F  4C C8 E7
L_EB72:
        lda #$79                          ; $EB72  A9 79
        sta MEMLO                         ; $EB74  85 FE
        lda #$2E                          ; $EB76  A9 2E
        sta MEMHI                         ; $EB78  85 FF
        jsr RDHEAD                        ; $EB7A  20 98 E8
        ldx #$00                          ; $EB7D  A2 00
        beq L_EB5B                        ; $EB7F  F0 DA

; DOS COMMAND TABLE: 2 letters + (handler address - 1); ends with 0
CMDTAB:
        .byte "AS"                        ; $EB81
        .word CMD_AS-1
D_EB82 = CMDTAB + 1
D_EB84 = CMDTAB + 3
D_EB83 = CMDTAB + 2
        .byte "BA"                        ; $EB85
        .word CMD_BA-1
        .byte "CA"                        ; $EB89
        .word CMD_CA-1
        .byte "DI"                        ; $EB8D
        .word $D003-1
        .byte "EM"                        ; $EB91
        .word CMD_EM-1
        .byte "EX"                        ; $EB95
        .word CMD_EX-1
        .byte "GO"                        ; $EB99
        .word CMD_GO-1
        .byte "HO"                        ; $EB9D
        .word HOME-1
        .byte "IN"                        ; $EBA1
        .word CMD_IN-1
        .byte "IO"                        ; $EBA5
        .word CMD_IO-1
        .byte "LO"                        ; $EBA9
        .word CMD_LO-1
        .byte "ME"                        ; $EBAD
        .word CMD_ME-1
        .byte "PU"                        ; $EBB1
        .word CMD_PU-1
        .byte "RE"                        ; $EBB5
        .word CMD_RE-1
        .byte "XQ"                        ; $EBB9
        .word CMD_XQ-1
        .byte "SA"                        ; $EBBD
        .word CMD_SA-1
        .byte "SE"                        ; $EBC1
        .word CMD_SE-1
        .byte "FT"                        ; $EBC5
        .word CMD_FT-1
        .byte "PX"                        ; $EBC9
        .word CMD_PX-1
        .byte 0                   ; end of table; $EBCD
        .byte $00,$00,$00,$00             ; $EBCE
L_EBD2:
        lda #$04                          ; $EBD2  A9 04
        sta ZTMP                          ; $EBD4  85 E0
        jmp HLOAD                         ; $EBD6  4C CD E4
L_EBD9:
        sty PAGEGAP                       ; $EBD9  8C AA 31
        pla                               ; $EBDC  68
        sec                               ; $EBDD  38
        sbc PAGEGAP                       ; $EBDE  ED AA 31
        sta PAGELEN                       ; $EBE1  8D A9 31
        sta LINECNT                       ; $EBE4  8D AB 31
        dec ESCCNT                        ; $EBE7  CE C0 25
        bpl L_EBFA                        ; $EBEA  10 0E
L_EBEC:
        inc ESCCNT                        ; $EBEC  EE C0 25
        cpy #$50                          ; $EBEF  C0 50
        beq L_EC02                        ; $EBF1  F0 0F
        cpy #$43                          ; $EBF3  C0 43
        bne L_EBFF                        ; $EBF5  D0 08
        inc ESCCNT                        ; $EBF7  EE C0 25
L_EBFA:
        lda #$00                          ; $EBFA  A9 00
        sta CHRSAV                        ; $EBFC  8D 63 23
L_EBFF:
        jmp L_E33B                        ; $EBFF  4C 3B E3
L_EC02:
        jmp L_EBFA                        ; $EC02  4C FA EB
L_EC05:
        jsr a:$00AC                       ; $EC05  20 AC 00
        lda #$01                          ; $EC08  A9 01
        sta DIRWR                         ; $EC0A  8D 36 35
        ldx #$F8                          ; $EC0D  A2 F8
        bne L_EC1B                        ; $EC0F  D0 0A
L_EC11:
        jsr HUNLD                         ; $EC11  20 DA E4
        lda #$00                          ; $EC14  A9 00
        sta DIRWR                         ; $EC16  8D 36 35
        ldx #$08                          ; $EC19  A2 08
L_EC1B:
        lda MEMLO                         ; $EC1B  A5 FE
        pha                               ; $EC1D  48
        lda MEMHI                         ; $EC1E  A5 FF
        pha                               ; $EC20  48
        lda #$79                          ; $EC21  A9 79
        sta MEMLO                         ; $EC23  85 FE
        lda #$3A                          ; $EC25  A9 3A
        sta MEMHI                         ; $EC27  85 FF
        stx $32C8                         ; $EC29  8E C8 32
        ldy #$03                          ; $EC2C  A0 03
        jsr L_EC5D                        ; $EC2E  20 5D EC
        ldy #$01                          ; $EC31  A0 01
        jsr L_EC5D                        ; $EC33  20 5D EC
        lda $0200                         ; $EC36  AD 00 02
        cmp #$29                          ; $EC39  C9 29
        bne L_EC56                        ; $EC3B  D0 19
L_EC3D:
        ldy #$00                          ; $EC3D  A0 00
        lda (MEMLO),y                     ; $EC3F  B1 FE
        iny                               ; $EC41  C8
        tax                               ; $EC42  AA
        lda (MEMLO),y                     ; $EC43  B1 FE
        stx MEMLO                         ; $EC45  86 FE
        ldx DIRWR                         ; $EC47  AE 36 35
        beq L_EC4F                        ; $EC4A  F0 03
        sec                               ; $EC4C  38
        sbc #$F8                          ; $EC4D  E9 F8
L_EC4F:
        sta MEMHI                         ; $EC4F  85 FF
        jsr L_EC5D                        ; $EC51  20 5D EC
        bne L_EC3D                        ; $EC54  D0 E7
L_EC56:
        pla                               ; $EC56  68
        sta MEMHI                         ; $EC57  85 FF
        pla                               ; $EC59  68
        sta MEMLO                         ; $EC5A  85 FE
        rts                               ; $EC5C  60
L_EC5D:
        lda (MEMLO),y                     ; $EC5D  B1 FE
        beq L_EC67                        ; $EC5F  F0 06
        clc                               ; $EC61  18
        adc $32C8                         ; $EC62  6D C8 32
        sta (MEMLO),y                     ; $EC65  91 FE
L_EC67:
        rts                               ; $EC67  60

; (not reached when tracing from the known entry points)
L_EC68:
        lda #$00                          ; $EC68  A9 00
        rts                               ; $EC6A  60
L_EC6B:
        jmp ACOUT                         ; $EC6B  4C 55 E2
        jsr OUTCH                         ; $EC6E  20 C7 E0
        pla                               ; $EC71  68
        ror a                             ; $EC72  6A
        bcs L_EC7A                        ; $EC73  B0 05
        lda #$11                          ; $EC75  A9 11
        jsr OUTCH                         ; $EC77  20 C7 E0
L_EC7A:
        jsr a:$00C0                       ; $EC7A  20 C0 00
        jsr $0E10                         ; $EC7D  20 10 0E
L_EC80:
        jsr $1618                         ; $EC80  20 18 16
        pha                               ; $EC83  48
        txa                               ; $EC84  8A
        jsr OUTCH                         ; $EC85  20 C7 E0
        pla                               ; $EC88  68
        cmp #$2C                          ; $EC89  C9 2C
        bne L_EC92                        ; $EC8B  D0 05
        jsr a:$00C0                       ; $EC8D  20 C0 00
        bne L_EC80                        ; $EC90  D0 EE
L_EC92:
        jsr $0E0D                         ; $EC92  20 0D 0E
        pla                               ; $EC95  68
        pla                               ; $EC96  68
        jmp $0A32                         ; $EC97  4C 32 0A
        .byte $00,$00                     ; $EC9A
        lda $36D0                         ; $EC9C  AD D0 36
        bne L_ECA4                        ; $EC9F  D0 03
        jmp $1CD1                         ; $ECA1  4C D1 1C
L_ECA4:
        jsr $0A73                         ; $ECA4  20 73 0A
        lda $36DA                         ; $ECA7  AD DA 36
        sta $19                           ; $ECAA  85 19
        lda $36DE                         ; $ECAC  AD DE 36
        sta $1A                           ; $ECAF  85 1A
        pla                               ; $ECB1  68
        pla                               ; $ECB2  68
        lda #$FF                          ; $ECB3  A9 FF
        sta $87                           ; $ECB5  85 87
        jsr $08AC                         ; $ECB7  20 AC 08
        jmp $07B4                         ; $ECBA  4C B4 07
        cmp $232C                         ; $ECBD  CD 2C 23
        bne L_ECC9                        ; $ECC0  D0 07
        pla                               ; $ECC2  68
        pla                               ; $ECC3  68
        pla                               ; $ECC4  68
        pla                               ; $ECC5  68
        jmp $2291                         ; $ECC6  4C 91 22
L_ECC9:
        pha                               ; $ECC9  48
        lda $232D                         ; $ECCA  AD 2D 23
        beq L_ECD7                        ; $ECCD  F0 08
        ldx #$00                          ; $ECCF  A2 00
        jsr L_E1FF                        ; $ECD1  20 FF E1
        jsr HUNLD                         ; $ECD4  20 DA E4
L_ECD7:
        pla                               ; $ECD7  68
        jsr $17D8                         ; $ECD8  20 D8 17
L_ECDB:
        rts                               ; $ECDB  60
        cmp #$46                          ; $ECDC  C9 46
        beq L_ECE3                        ; $ECDE  F0 03
L_ECE0:
        jmp $0E1E                         ; $ECE0  4C 1E 0E
L_ECE3:
        jsr a:$00C0                       ; $ECE3  20 C0 00
        beq L_ECE0                        ; $ECE6  F0 F8
        cmp #$2C                          ; $ECE8  C9 2C
        bne L_ECE3                        ; $ECEA  D0 F7
        jsr a:$00C0                       ; $ECEC  20 C0 00
        jsr $0CCD                         ; $ECEF  20 CD 0C
        jsr $0CBE                         ; $ECF2  20 BE 0C
        jsr $1520                         ; $ECF5  20 20 15
        sta CMDLEN                        ; $ECF8  8D ED 2C
        stx INBUF                         ; $ECFB  86 E1
        sty INBUFH                        ; $ECFD  84 E2
        jmp $1953                         ; $ECFF  4C 53 19
L_ED02:
        jsr L_ED14                        ; $ED02  20 14 ED
        beq L_ECDB                        ; $ED05  F0 D4
        pla                               ; $ED07  68
        pla                               ; $ED08  68
        jmp L_E837                        ; $ED09  4C 37 E8
L_ED0C:
        sta $374D                         ; $ED0C  8D 4D 37
        lda DIRSEC,x                      ; $ED0F  BD 79 2E
        bne L_ED19                        ; $ED12  D0 05
L_ED14:
        sta $374D                         ; $ED14  8D 4D 37
        lda (INBUF),y                     ; $ED17  B1 E1
L_ED19:
        jsr UCASE                         ; $ED19  20 0F F0
        cmp $374D                         ; $ED1C  CD 4D 37
        rts                               ; $ED1F  60

; (not reached when tracing from the known entry points)
L_ED20:
        ldy $87                           ; $ED20  A4 87
        iny                               ; $ED22  C8
        beq L_ED28                        ; $ED23  F0 03
        jmp $10D0                         ; $ED25  4C D0 10
L_ED28:
        jsr a:$00C6                       ; $ED28  20 C6 00
        beq L_ED47                        ; $ED2B  F0 1A
        cmp #$21                          ; $ED2D  C9 21
        bne L_ED38                        ; $ED2F  D0 07
        jsr a:$00C0                       ; $ED31  20 C0 00
        beq L_ED54                        ; $ED34  F0 1E
        bne L_ED44                        ; $ED36  D0 0C
L_ED38:
        jsr a:$00C6                       ; $ED38  20 C6 00
        bcc L_ED3F                        ; $ED3B  90 02
        bcs L_ED44                        ; $ED3D  B0 05
L_ED3F:
        jsr $096C                         ; $ED3F  20 6C 09
        beq L_ED54                        ; $ED42  F0 10
L_ED44:
        jmp $0E1E                         ; $ED44  4C 1E 0E
L_ED47:
        inc $19                           ; $ED47  E6 19
        bne L_ED4D                        ; $ED49  D0 02
        inc $1A                           ; $ED4B  E6 1A
L_ED4D:
        ldy #$01                          ; $ED4D  A0 01
        lda ($AC),y                       ; $ED4F  B1 AC
        bne L_ED54                        ; $ED51  D0 01
        rts                               ; $ED53  60
L_ED54:
        jsr $0633                         ; $ED54  20 33 06
        bcs L_ED67                        ; $ED57  B0 0E
        ldy #$03                          ; $ED59  A0 03
        lda ($AC),y                       ; $ED5B  B1 AC
        sta $1A                           ; $ED5D  85 1A
        dey                               ; $ED5F  88
        lda ($AC),y                       ; $ED60  B1 AC
        sta $19                           ; $ED62  85 19
        dey                               ; $ED64  88
        bne L_ED4D                        ; $ED65  D0 E6
L_ED67:
        ldy #$FF                          ; $ED67  A0 FF
        sty $376F                         ; $ED69  8C 6F 37
        iny                               ; $ED6C  C8
        sty $16                           ; $ED6D  84 16
        jsr $06D8                         ; $ED6F  20 D8 06
        ldy #$FF                          ; $ED72  A0 FF
        sty $376D                         ; $ED74  8C 6D 37
        iny                               ; $ED77  C8
        sty $376E                         ; $ED78  8C 6E 37
        sty $376F                         ; $ED7B  8C 6F 37
        sty $16                           ; $ED7E  84 16
        lda $3767                         ; $ED80  AD 67 37
        sta ($EE),y                       ; $ED83  91 EE
        pla                               ; $ED85  68
        pla                               ; $ED86  68
        jmp $047D                         ; $ED87  4C 7D 04
L_ED8A:
        ldy $376F                         ; $ED8A  AC 6F 37
        bne L_ED93                        ; $ED8D  D0 04
        lda OUTMASK                       ; $ED8F  AD 22 23
        rts                               ; $ED92  60
L_ED93:
        ldy $EE                           ; $ED93  A4 EE
        cpy $3756                         ; $ED95  CC 56 37
        bcs L_EDAE                        ; $ED98  B0 14
        cmp $3765                         ; $ED9A  CD 65 37
        bcc L_EDAE                        ; $ED9D  90 0F
        cmp #$20                          ; $ED9F  C9 20
        bne L_EDA8                        ; $EDA1  D0 05
        cpy $3753                         ; $EDA3  CC 53 37
        beq L_EDAE                        ; $EDA6  F0 06
L_EDA8:
        ldy #$00                          ; $EDA8  A0 00
        sta ($EE),y                       ; $EDAA  91 EE
        inc $EE                           ; $EDAC  E6 EE
L_EDAE:
        lda #$00                          ; $EDAE  A9 00
        rts                               ; $EDB0  60
        cmp #$3F                          ; $EDB1  C9 3F
        bne L_EDB8                        ; $EDB3  D0 03
        jmp $05C1                         ; $EDB5  4C C1 05
L_EDB8:
        cmp #$21                          ; $EDB8  C9 21
        bne L_EDC6                        ; $EDBA  D0 0A
        cpx $3753                         ; $EDBC  EC 53 37
        bne L_EDC6                        ; $EDBF  D0 05
        lda #$91                          ; $EDC1  A9 91
        jmp $05C3                         ; $EDC3  4C C3 05
L_EDC6:
        jmp $05C5                         ; $EDC6  4C C5 05
        lda $3753                         ; $EDC9  AD 53 37
        sta $EE                           ; $EDCC  85 EE
        lda $3754                         ; $EDCE  AD 54 37
        sta $EF                           ; $EDD1  85 EF
        lda $376E                         ; $EDD3  AD 6E 37
        beq L_EDDF                        ; $EDD6  F0 07
        ldy #$00                          ; $EDD8  A0 00
        lda $3767                         ; $EDDA  AD 67 37
        sta ($EE),y                       ; $EDDD  91 EE
L_EDDF:
        ldy #$FF                          ; $EDDF  A0 FF
L_EDE1:
        iny                               ; $EDE1  C8
        lda ($EE),y                       ; $EDE2  B1 EE
        cmp $3767                         ; $EDE4  CD 67 37
        beq L_EDF3                        ; $EDE7  F0 0A
        ldx $376D                         ; $EDE9  AE 6D 37
        beq L_EDE1                        ; $EDEC  F0 F3
        jsr $0AEE                         ; $EDEE  20 EE 0A
        bne L_EDE1                        ; $EDF1  D0 EE
L_EDF3:
        ldx #$00                          ; $EDF3  A2 00
        stx $376D                         ; $EDF5  8E 6D 37
        sty $3768                         ; $EDF8  8C 68 37
        lda $16                           ; $EDFB  A5 16
        sta $3769                         ; $EDFD  8D 69 37
        lda $376C                         ; $EE00  AD 6C 37
        beq L_EE32                        ; $EE03  F0 2D
        stx $376C                         ; $EE05  8E 6C 37
        ldx $3768                         ; $EE08  AE 68 37
        lda $3767                         ; $EE0B  AD 67 37
        rts                               ; $EE0E  60
L_EE0F:
        lda #$FF                          ; $EE0F  A9 FF
        sta $376C                         ; $EE11  8D 6C 37
        sta $376E                         ; $EE14  8D 6E 37
        bne L_EDDF                        ; $EE17  D0 C6
L_EE19:
        ldy #$00                          ; $EE19  A0 00
        lda ($EE),y                       ; $EE1B  B1 EE
        ldy $3768                         ; $EE1D  AC 68 37
        cmp $3767                         ; $EE20  CD 67 37
        beq L_EE32                        ; $EE23  F0 0D
        jsr $0A73                         ; $EE25  20 73 0A
        ldx #$00                          ; $EE28  A2 00
        stx $16                           ; $EE2A  86 16
        dex                               ; $EE2C  CA
        stx $376D                         ; $EE2D  8E 6D 37
        bne L_EDDF                        ; $EE30  D0 AD
L_EE32:
        jmp L_EE7E                        ; $EE32  4C 7E EE
L_EE35:
        ldx $375C                         ; $EE35  AE 5C 37
        beq L_EE6A                        ; $EE38  F0 30
        ldx $375A                         ; $EE3A  AE 5A 37
        beq L_EE6A                        ; $EE3D  F0 2B
L_EE3F:
        lda ($EE),y                       ; $EE3F  B1 EE
        cmp $3767                         ; $EE41  CD 67 37
        beq L_EE4F                        ; $EE44  F0 09
        lda $375A                         ; $EE46  AD 5A 37
        iny                               ; $EE49  C8
        jsr $0AEE                         ; $EE4A  20 EE 0A
        bne L_EE3F                        ; $EE4D  D0 F0
L_EE4F:
        tya                               ; $EE4F  98
        beq L_EE74                        ; $EE50  F0 22
        dec $16                           ; $EE52  C6 16
        ldx #$02                          ; $EE54  A2 02
L_EE56:
        lda $375C                         ; $EE56  AD 5C 37
L_EE59:
        jsr $0AEE                         ; $EE59  20 EE 0A
        dex                               ; $EE5C  CA
        beq L_EE56                        ; $EE5D  F0 F7
        bmi L_EE65                        ; $EE5F  30 04
        lda #$20                          ; $EE61  A9 20
        bne L_EE59                        ; $EE63  D0 F4
L_EE65:
        dec $16                           ; $EE65  C6 16
        dey                               ; $EE67  88
        bpl L_EE4F                        ; $EE68  10 E5
L_EE6A:
        jsr $0AEE                         ; $EE6A  20 EE 0A
        jsr $0A73                         ; $EE6D  20 73 0A
        lda #$00                          ; $EE70  A9 00
        sta $16                           ; $EE72  85 16
L_EE74:
        ldy #$01                          ; $EE74  A0 01
L_EE76:
        dey                               ; $EE76  88
        bmi L_EE74                        ; $EE77  30 FB
        lda $3767                         ; $EE79  AD 67 37
        sta ($EE),y                       ; $EE7C  91 EE
L_EE7E:
        sty $3768                         ; $EE7E  8C 68 37
        jsr $0587                         ; $EE81  20 87 05
        cmp $375B                         ; $EE84  CD 5B 37
        bne L_EE8C                        ; $EE87  D0 03
        jmp L_EF33                        ; $EE89  4C 33 EF
L_EE8C:
        cmp $3758                         ; $EE8C  CD 58 37
        beq L_EE96                        ; $EE8F  F0 05
        cmp $3759                         ; $EE91  CD 59 37
        bne L_EE99                        ; $EE94  D0 03
L_EE96:
        jmp L_EF86                        ; $EE96  4C 86 EF
L_EE99:
        cmp $375F                         ; $EE99  CD 5F 37
        bne L_EEA1                        ; $EE9C  D0 03
        jmp L_EE19                        ; $EE9E  4C 19 EE
L_EEA1:
        cmp $3760                         ; $EEA1  CD 60 37
        bne L_EEA9                        ; $EEA4  D0 03
        jmp L_EF27                        ; $EEA6  4C 27 EF
L_EEA9:
        cmp $3761                         ; $EEA9  CD 61 37
        bne L_EEB1                        ; $EEAC  D0 03
        jmp L_EF67                        ; $EEAE  4C 67 EF
L_EEB1:
        cmp $3762                         ; $EEB1  CD 62 37
        bne L_EEB9                        ; $EEB4  D0 03
        jmp L_EF59                        ; $EEB6  4C 59 EF
L_EEB9:
        cmp $3763                         ; $EEB9  CD 63 37
        bne L_EEC1                        ; $EEBC  D0 03
        jmp L_EE35                        ; $EEBE  4C 35 EE
L_EEC1:
        cmp $375D                         ; $EEC1  CD 5D 37
        beq L_EECB                        ; $EEC4  F0 05
        cmp $375E                         ; $EEC6  CD 5E 37
        bne L_EECE                        ; $EEC9  D0 03
L_EECB:
        jmp L_EFB0                        ; $EECB  4C B0 EF
L_EECE:
        cmp $3767                         ; $EECE  CD 67 37
        bne L_EED6                        ; $EED1  D0 03
        jmp L_EE0F                        ; $EED3  4C 0F EE
L_EED6:
        cmp $3765                         ; $EED6  CD 65 37
        bcc L_EE7E                        ; $EED9  90 A3
        cmp $3766                         ; $EEDB  CD 66 37
        bcc L_EEE3                        ; $EEDE  90 03
L_EEE0:
        jmp L_EE7E                        ; $EEE0  4C 7E EE
L_EEE3:
        cpy $3755                         ; $EEE3  CC 55 37
        bcs L_EEE0                        ; $EEE6  B0 F8
        ldx $16                           ; $EEE8  A6 16
        cpx $376A                         ; $EEEA  EC 6A 37
        bcs L_EEE0                        ; $EEED  B0 F1
        pha                               ; $EEEF  48
        txa                               ; $EEF0  8A
        clc                               ; $EEF1  18
        adc #$03                          ; $EEF2  69 03
        cmp $376A                         ; $EEF4  CD 6A 37
        bcc L_EEFF                        ; $EEF7  90 06
        lda $3764                         ; $EEF9  AD 64 37
        jsr $0AEE                         ; $EEFC  20 EE 0A
L_EEFF:
        pla                               ; $EEFF  68
        inc $16                           ; $EF00  E6 16
L_EF02:
        pha                               ; $EF02  48
        dec $16                           ; $EF03  C6 16
        jsr $0AEE                         ; $EF05  20 EE 0A
        cpy $3757                         ; $EF08  CC 57 37
        bcc L_EF13                        ; $EF0B  90 06
        lda $3764                         ; $EF0D  AD 64 37
        jsr $0AEE                         ; $EF10  20 EE 0A
L_EF13:
        lda ($EE),y                       ; $EF13  B1 EE
        tax                               ; $EF15  AA
        pla                               ; $EF16  68
        sta ($EE),y                       ; $EF17  91 EE
        iny                               ; $EF19  C8
        txa                               ; $EF1A  8A
        cmp $3767                         ; $EF1B  CD 67 37
        beq L_EF46                        ; $EF1E  F0 26
        cpy $3755                         ; $EF20  CC 55 37
        bcs L_EF41                        ; $EF23  B0 1C
        bcc L_EF02                        ; $EF25  90 DB
L_EF27:
        ldx $375C                         ; $EF27  AE 5C 37
        beq L_EF83                        ; $EF2A  F0 57
        lda #$00                          ; $EF2C  A9 00
        sta $3768                         ; $EF2E  8D 68 37
        beq L_EF4B                        ; $EF31  F0 18
L_EF33:
        sta $375C                         ; $EF33  8D 5C 37
        tya                               ; $EF36  98
        beq L_EF83                        ; $EF37  F0 4A
        tax                               ; $EF39  AA
        dex                               ; $EF3A  CA
        stx $3768                         ; $EF3B  8E 68 37
        clc                               ; $EF3E  18
        bcc L_EF4B                        ; $EF3F  90 0A
L_EF41:
        lda $3767                         ; $EF41  AD 67 37
        dec $16                           ; $EF44  C6 16
L_EF46:
        inc $3768                         ; $EF46  EE 68 37
        sta ($EE),y                       ; $EF49  91 EE
L_EF4B:
        cpy $3768                         ; $EF4B  CC 68 37
        beq L_EF83                        ; $EF4E  F0 33
        dey                               ; $EF50  88
        lda $375C                         ; $EF51  AD 5C 37
        jsr $0AEE                         ; $EF54  20 EE 0A
        bne L_EF4B                        ; $EF57  D0 F2
L_EF59:
        ldx $375A                         ; $EF59  AE 5A 37
        beq L_EF83                        ; $EF5C  F0 25
        ldx $3755                         ; $EF5E  AE 55 37
        inx                               ; $EF61  E8
        stx $3768                         ; $EF62  8E 68 37
        bne L_EF9B                        ; $EF65  D0 34
L_EF67:
        ldx $375A                         ; $EF67  AE 5A 37
        beq L_EF83                        ; $EF6A  F0 17
        lda #$00                          ; $EF6C  A9 00
        sta $3768                         ; $EF6E  8D 68 37
L_EF71:
        clc                               ; $EF71  18
        lda $376B                         ; $EF72  AD 6B 37
        adc $3768                         ; $EF75  6D 68 37
        sta $3768                         ; $EF78  8D 68 37
        tya                               ; $EF7B  98
        cmp $3768                         ; $EF7C  CD 68 37
        bcs L_EF71                        ; $EF7F  B0 F0
        bcc L_EF9B                        ; $EF81  90 18
L_EF83:
        jmp L_EE7E                        ; $EF83  4C 7E EE
L_EF86:
        ldx $375A                         ; $EF86  AE 5A 37
        bne L_EF90                        ; $EF89  D0 05
        sta $375A                         ; $EF8B  8D 5A 37
        bne L_EF95                        ; $EF8E  D0 05
L_EF90:
        cmp $375A                         ; $EF90  CD 5A 37
        bne L_EF83                        ; $EF93  D0 EE
L_EF95:
        sty $3768                         ; $EF95  8C 68 37
        inc $3768                         ; $EF98  EE 68 37
L_EF9B:
        lda ($EE),y                       ; $EF9B  B1 EE
        cmp $3767                         ; $EF9D  CD 67 37
        beq L_EF83                        ; $EFA0  F0 E1
        cpy $3768                         ; $EFA2  CC 68 37
        bcs L_EF83                        ; $EFA5  B0 DC
        iny                               ; $EFA7  C8
        lda $375A                         ; $EFA8  AD 5A 37
        jsr $0AEE                         ; $EFAB  20 EE 0A
        bne L_EF9B                        ; $EFAE  D0 EB
L_EFB0:
        ldy #$00                          ; $EFB0  A0 00
        lda ($EE),y                       ; $EFB2  B1 EE
        ldy $3768                         ; $EFB4  AC 68 37
        cmp $3767                         ; $EFB7  CD 67 37
        beq L_EF83                        ; $EFBA  F0 C7
        lda $375C                         ; $EFBC  AD 5C 37
        bne L_EFD3                        ; $EFBF  D0 12
        lda $3764                         ; $EFC1  AD 64 37
        ldx $16                           ; $EFC4  A6 16
        cpx $376A                         ; $EFC6  EC 6A 37
        bcs L_EFCE                        ; $EFC9  B0 03
        lda $375E                         ; $EFCB  AD 5E 37
L_EFCE:
        jsr $0AEE                         ; $EFCE  20 EE 0A
        bne L_EFEF                        ; $EFD1  D0 1C
L_EFD3:
        dec $16                           ; $EFD3  C6 16
        lda ($EE),y                       ; $EFD5  B1 EE
        cmp $3767                         ; $EFD7  CD 67 37
        bne L_EFF2                        ; $EFDA  D0 16
        ldx #$02                          ; $EFDC  A2 02
L_EFDE:
        lda $375C                         ; $EFDE  AD 5C 37
L_EFE1:
        jsr $0AEE                         ; $EFE1  20 EE 0A
        dex                               ; $EFE4  CA
        beq L_EFDE                        ; $EFE5  F0 F7
        bmi L_EFED                        ; $EFE7  30 04
        lda #$20                          ; $EFE9  A9 20
        bne L_EFE1                        ; $EFEB  D0 F4
L_EFED:
        dec $16                           ; $EFED  C6 16
L_EFEF:
        jmp L_EE76                        ; $EFEF  4C 76 EE
L_EFF2:
        iny                               ; $EFF2  C8
        lda ($EE),y                       ; $EFF3  B1 EE
        dey                               ; $EFF5  88
        sta ($EE),y                       ; $EFF6  91 EE
        pha                               ; $EFF8  48
        cmp $3767                         ; $EFF9  CD 67 37
        bne L_F000                        ; $EFFC  D0 02
        lda #$20                          ; $EFFE  A9 20
L_F000:
        jsr $0AEE                         ; $F000  20 EE 0A
        dec $16                           ; $F003  C6 16
        iny                               ; $F005  C8
        pla                               ; $F006  68
        cmp $3767                         ; $F007  CD 67 37
        bne L_EFF2                        ; $F00A  D0 E6
        jmp L_EF4B                        ; $F00C  4C 4B EF

; UCASE - fold A to upper case
UCASE:
        cmp #$61                          ; $F00F  C9 61
        bcc L_F019                        ; $F011  90 06
        cmp #$7B                          ; $F013  C9 7B
        bcs L_F019                        ; $F015  B0 02
        eor #$20                          ; $F017  49 20
L_F019:
        rts                               ; $F019  60
GETCHU:
        jsr UCASE                         ; $F01A  20 0F F0
        cmp #$0D                          ; $F01D  C9 0D
        beq L_F019                        ; $F01F  F0 F8
        jmp L_EA4E                        ; $F021  4C 4E EA

; RDSECP - RDSEC, then apply SECPAT patches for this track/sector
RDSECP:
        jsr RDSEC                         ; $F024  20 E4 E6
        php                               ; $F027  08
        pha                               ; $F028  48
        txa                               ; $F029  8A
        pha                               ; $F02A  48
        tya                               ; $F02B  98
        pha                               ; $F02C  48
        ldx #$00                          ; $F02D  A2 00
L_F02F:
        lda SECPAT,x                      ; $F02F  BD 13 F9
        cmp #$FF                          ; $F032  C9 FF
        beq L_F056                        ; $F034  F0 20
        cmp CURTRK                        ; $F036  CD 5D 26
        bne L_F050                        ; $F039  D0 15
        lda D_F914,x                      ; $F03B  BD 14 F9
        cmp DSECT                         ; $F03E  CD 5E 26
        bne L_F050                        ; $F041  D0 0D
        txa                               ; $F043  8A
        pha                               ; $F044  48
        lda D_F915,x                      ; $F045  BD 15 F9
        ldy D_F916,x                      ; $F048  BC 16 F9
        jsr PATCH                         ; $F04B  20 5D F0
        pla                               ; $F04E  68
        tax                               ; $F04F  AA
L_F050:
        inx                               ; $F050  E8
        inx                               ; $F051  E8
        inx                               ; $F052  E8
        inx                               ; $F053  E8
        bne L_F02F                        ; $F054  D0 D9
L_F056:
        pla                               ; $F056  68
        tay                               ; $F057  A8
        pla                               ; $F058  68
        tax                               ; $F059  AA
        pla                               ; $F05A  68
        plp                               ; $F05B  28
        rts                               ; $F05C  60

; PATCH - apply a patch list (A,Y = address)
PATCH:
        sta $F0                           ; $F05D  85 F0
        sty $F1                           ; $F05F  84 F1
L_F061:
        ldy #$01                          ; $F061  A0 01
        lda ($F0),y                       ; $F063  B1 F0
        cmp #$FF                          ; $F065  C9 FF
        beq L_F0A3                        ; $F067  F0 3A
        ldx #$05                          ; $F069  A2 05
        asl a                             ; $F06B  0A
        bcc L_F070                        ; $F06C  90 02
        ldx #$04                          ; $F06E  A2 04
L_F070:
        lsr a                             ; $F070  4A
        sta $F3                           ; $F071  85 F3
        dey                               ; $F073  88
        lda ($F0),y                       ; $F074  B1 F0
        sta $F2                           ; $F076  85 F2
        ldy #$02                          ; $F078  A0 02
        lda ($F0),y                       ; $F07A  B1 F0
        ldy #$00                          ; $F07C  A0 00
        cmp ($F2),y                       ; $F07E  D1 F2
        bne L_F096                        ; $F080  D0 14
        ldy #$03                          ; $F082  A0 03
        lda ($F0),y                       ; $F084  B1 F0
        ldy #$00                          ; $F086  A0 00
        sta ($F2),y                       ; $F088  91 F2
        cpx #$05                          ; $F08A  E0 05
        bne L_F096                        ; $F08C  D0 08
        ldy #$04                          ; $F08E  A0 04
        lda ($F0),y                       ; $F090  B1 F0
        ldy #$01                          ; $F092  A0 01
        sta ($F2),y                       ; $F094  91 F2
L_F096:
        txa                               ; $F096  8A
        clc                               ; $F097  18
        adc $F0                           ; $F098  65 F0
        sta $F0                           ; $F09A  85 F0
        bcc L_F061                        ; $F09C  90 C3
        inc $F1                           ; $F09E  E6 F1
        jmp L_F061                        ; $F0A0  4C 61 F0
L_F0A3:
        rts                               ; $F0A3  60

; BA - load and start BASIC (patched by BASPAT)
CMD_BA:
        lda #$02                          ; $F0A4  A9 02
        jsr LOADSYS                       ; $F0A6  20 6C E8
        lda #$78                          ; $F0A9  A9 78
        ldy #$F7                          ; $F0AB  A0 F7
        jsr PATCH                         ; $F0AD  20 5D F0
        jmp $20E4                         ; $F0B0  4C E4 20

; AS - load and start the assembler
CMD_AS:
        lda #$07                          ; $F0B3  A9 07
        jsr LOADSYS                       ; $F0B5  20 6C E8
        lda #$8F                          ; $F0B8  A9 8F
        ldy #$F6                          ; $F0BA  A0 F6
        jsr PATCH                         ; $F0BC  20 5D F0
        jmp $1300                         ; $F0BF  4C 00 13

; EM - load the extended monitor
CMD_EM:
        lda #$07                          ; $F0C2  A9 07
        jsr LOADSYS                       ; $F0C4  20 6C E8
        lda #$8F                          ; $F0C7  A9 8F
        ldy #$F6                          ; $F0C9  A0 F6
        jsr PATCH                         ; $F0CB  20 5D F0
        jmp $1700                         ; $F0CE  4C 00 17
        .byte $80                         ; $F0D1
L_F0D2:
        jsr SKIPAR                        ; $F0D2  20 21 E8
        lda DPAGE                         ; $F0D5  AD 5F 26
        sta $19                           ; $F0D8  85 19
        jsr LDDIR                         ; $F0DA  20 85 F1
        lda #$00                          ; $F0DD  A9 00
        sta FOUND                         ; $F0DF  8D 38 35
        jsr GETNM                         ; $F0E2  20 D3 F3
        jsr FNDNM                         ; $F0E5  20 F9 F3
        lda FOUND                         ; $F0E8  AD 38 35
        bne L_F0F2                        ; $F0EB  D0 05
        lda #$0C                          ; $F0ED  A9 0C
        jmp ERROR                         ; $F0EF  4C C8 E7
L_F0F2:
        lda ENTL                          ; $F0F2  AD 39 35
        sta ENTPL                         ; $F0F5  85 10
        ldx ENTH                          ; $F0F7  AE 3A 35
        stx ENTPH                         ; $F0FA  86 11
        rts                               ; $F0FC  60

; DSKFIX - copy a DISK! string to CMDBUF with a CR (fixes ERR #7 from BASIC)
        ldy CMDLEN                        ; $F0FD  AC ED 2C
        lda #$0D                          ; $F100  A9 0D
L_F102:
        sta CMDBUF,y                      ; $F102  99 1E 2E
        dey                               ; $F105  88
        lda ($6F),y                       ; $F106  B1 6F
        cpy #$FF                          ; $F108  C0 FF
        bne L_F102                        ; $F10A  D0 F6
        lda #$1E                          ; $F10C  A9 1E
        jmp DSKFIX2                       ; $F10E  4C F1 FE
        .byte $E7                         ; $F111

; original DI (now reached from DOSX only for DI tt; its directory listing, $F133-$F184, was replaced by the routines below)
        ldy CMDPOS                        ; $F112  AC E5 2C
L_F115:
        lda (INBUF),y                     ; $F115  B1 E1
        cmp #$20                          ; $F117  C9 20
        bne L_F121                        ; $F119  D0 06
        iny                               ; $F11B  C8
        sty CMDPOS                        ; $F11C  8C E5 2C
        bne L_F115                        ; $F11F  D0 F4
L_F121:
        cmp #$20                          ; $F121  C9 20
        bmi FNGET                         ; $F123  30 0E
        cmp #$23                          ; $F125  C9 23
        beq FNGET                         ; $F127  F0 0A
        cmp #$22                          ; $F129  C9 22
        beq FNGET                         ; $F12B  F0 06
        jsr GETHX                         ; $F12D  20 91 EA
        jmp SECMAP                        ; $F130  4C 70 E7

; FNGET - FINDFILE: name character at Y, or CR once CMDLEN is reached (BASIC RUN"name" strings have no CR)
FNGET:
        tay                               ; $F133  A8
        cpy CMDLEN                        ; $F134  CC ED 2C
        bcs L_F13C                        ; $F137  B0 03
        lda (INBUF),y                     ; $F139  B1 E1
        rts                               ; $F13B  60
L_F13C:
        lda #$0D                          ; $F13C  A9 0D
        rts                               ; $F13E  60

; FNCMP - FINDFILE: compare name characters ignoring case (Z set = match)
FNCMP:
        jsr UCASE                         ; $F13F  20 0F F0
        sta $35EF                         ; $F142  8D EF 35
        txa                               ; $F145  8A
        tay                               ; $F146  A8
        lda (ENTPL),y                     ; $F147  B1 10
        jsr UCASE                         ; $F149  20 0F F0
        cmp $35EF                         ; $F14C  CD EF 35
        rts                               ; $F14F  60

; FNUC - GETNM/PU: next name character in upper case, CMP #$20
FNUC:
        lda (INBUF),y                     ; $F150  B1 E1
        jsr UCASE                         ; $F152  20 0F F0
        cmp #$20                          ; $F155  C9 20
        rts                               ; $F157  60

; FNDCMP - FNDNM: compare directory character with NAMBUF ignoring case
FNDCMP:
        lda (ENTPL),y                     ; $F158  B1 10
        jsr UCASE                         ; $F15A  20 0F F0
        cmp NAMBUF,y                      ; $F15D  D9 28 35
        rts                               ; $F160  60
        .res 16, $FF                      ; $F161
        .res 16, $FF                      ; $F171
        .byte $FF,$FF,$FF,$FF             ; $F181

; LDDIR - read the directory (track 12, sectors 1 and 2) to $3300/$3400
LDDIR:
        lda #$00                          ; $F185  A9 00
        sta MEMLO                         ; $F187  85 FE
        lda #$33                          ; $F189  A9 33
        sta MEMHI                         ; $F18B  85 FF
        lda #$12                          ; $F18D  A9 12
        jsr SEEK                          ; $F18F  20 35 E4
        lda #$01                          ; $F192  A9 01
        sta DSECT                         ; $F194  8D 5E 26
        jsr RDHEAD                        ; $F197  20 98 E8
        lda #$00                          ; $F19A  A9 00
        sta MEMLO                         ; $F19C  85 FE
        lda #$34                          ; $F19E  A9 34
        sta MEMHI                         ; $F1A0  85 FF
        lda #$02                          ; $F1A2  A9 02
        sta DSECT                         ; $F1A4  8D 5E 26
        jmp RDHEAD                        ; $F1A7  4C 98 E8
DIRPTR:
        lda #$00                          ; $F1AA  A9 00
        sta ENTPL                         ; $F1AC  85 10
        lda #$33                          ; $F1AE  A9 33
        sta ENTPH                         ; $F1B0  85 11
        rts                               ; $F1B2  60
L_F1B3:
        lda CMDPOS                        ; $F1B3  AD E5 2C
        sta ZTMP                          ; $F1B6  85 E0
        jsr LDDIR                         ; $F1B8  20 85 F1
        jsr DIRPTR                        ; $F1BB  20 AA F1
L_F1BE:
        ldx #$00                          ; $F1BE  A2 00
        stx NAMEND                        ; $F1C0  8E 37 35
L_F1C3:
        lda NAMEND                        ; $F1C3  AD 37 35
        bne L_F1E2                        ; $F1C6  D0 1A
        txa                               ; $F1C8  8A
        clc                               ; $F1C9  18
        adc ZTMP                          ; $F1CA  65 E0
        jsr FNGET                         ; $F1CC  20 33 F1
        beq L_F1DD                        ; $F1CF  F0 0C
        cmp #$0D                          ; $F1D1  C9 0D
        beq L_F1DD                        ; $F1D3  F0 08
        cmp #$22                          ; $F1D5  C9 22
        beq L_F1DD                        ; $F1D7  F0 04
        cmp #$20                          ; $F1D9  C9 20
        bne L_F1E4                        ; $F1DB  D0 07
L_F1DD:
        lda #$01                          ; $F1DD  A9 01
        sta NAMEND                        ; $F1DF  8D 37 35
L_F1E2:
        lda #$20                          ; $F1E2  A9 20
L_F1E4:
        jsr FNCMP                         ; $F1E4  20 3F F1
        nop                               ; $F1E7  EA
        nop                               ; $F1E8  EA
        nop                               ; $F1E9  EA
        bne L_F23C                        ; $F1EA  D0 50
        inx                               ; $F1EC  E8
        cpx #$0E                          ; $F1ED  E0 0E
        bne L_F1C3                        ; $F1EF  D0 D2
        lda NAMEND                        ; $F1F1  AD 37 35
        bne L_F20F                        ; $F1F4  D0 19
        txa                               ; $F1F6  8A
        clc                               ; $F1F7  18
        adc ZTMP                          ; $F1F8  65 E0
        jsr FNGET                         ; $F1FA  20 33 F1
        beq L_F20F                        ; $F1FD  F0 10
        cmp #$0D                          ; $F1FF  C9 0D
        beq L_F20F                        ; $F201  F0 0C
        cmp #$22                          ; $F203  C9 22
        beq L_F20F                        ; $F205  F0 08
        cmp #$20                          ; $F207  C9 20
        beq L_F20F                        ; $F209  F0 04
        cmp #$2C                          ; $F20B  C9 2C
        bne L_F23C                        ; $F20D  D0 2D
L_F20F:
        ldy #$0F                          ; $F20F  A0 0F
        lda (ENTPL),y                     ; $F211  B1 10
        sta MAXTK                         ; $F213  85 E5
        ldy #$00                          ; $F215  A0 00
        lda ENTPH                         ; $F217  A5 11
        cmp #$33                          ; $F219  C9 33
        bne L_F228                        ; $F21B  D0 0B
L_F21D:
        lda DIRBUF1,y                     ; $F21D  B9 00 33
        sta DIRSEC,y                      ; $F220  99 79 2E
        iny                               ; $F223  C8
        bne L_F21D                        ; $F224  D0 F7
        beq L_F231                        ; $F226  F0 09
L_F228:
        lda DIRBUF2,y                     ; $F228  B9 00 34
        sta DIRSEC,y                      ; $F22B  99 79 2E
        iny                               ; $F22E  C8
        bne L_F228                        ; $F22F  D0 F7
L_F231:
        lda ENTPL                         ; $F231  A5 10
        clc                               ; $F233  18
        adc #$0E                          ; $F234  69 0E
        tax                               ; $F236  AA
        ldy #$0E                          ; $F237  A0 0E
        lda (ENTPL),y                     ; $F239  B1 10
        rts                               ; $F23B  60
L_F23C:
        jsr NXTENT                        ; $F23C  20 56 F2
        beq L_F244                        ; $F23F  F0 03
        jmp L_F1BE                        ; $F241  4C BE F1
L_F244:
        lda #$0C                          ; $F244  A9 0C
        jmp ERROR                         ; $F246  4C C8 E7

; ISEMPTY - Z=1 if the entry at (ENTPL) is unused (14 x #)
ISEMPTY:
        ldy #$0D                          ; $F249  A0 0D
L_F24B:
        lda (ENTPL),y                     ; $F24B  B1 10
        cmp #$23                          ; $F24D  C9 23
        bne L_F255                        ; $F24F  D0 04
        dey                               ; $F251  88
        bpl L_F24B                        ; $F252  10 F7
        iny                               ; $F254  C8
L_F255:
        rts                               ; $F255  60

; NXTENT - next directory entry, Z=1 at the end
NXTENT:
        clc                               ; $F256  18
        lda ENTPL                         ; $F257  A5 10
        adc #$10                          ; $F259  69 10
        sta ENTPL                         ; $F25B  85 10
        lda ENTPH                         ; $F25D  A5 11
        adc #$00                          ; $F25F  69 00
        sta ENTPH                         ; $F261  85 11
        cmp #$35                          ; $F263  C9 35
        bne L_F26F                        ; $F265  D0 08
        lda ENTPL                         ; $F267  A5 10
        cmp #$00                          ; $F269  C9 00
        bne L_F26F                        ; $F26B  D0 02
        lda #$00                          ; $F26D  A9 00
L_F26F:
        rts                               ; $F26F  60
PUGO:
        lda #$39                          ; $F270  A9 39
        sta MAXTK                         ; $F272  85 E5
        lda DPAGE                         ; $F274  AD 5F 26
        sta $19                           ; $F277  85 19
        ldy CMDPOS                        ; $F279  AC E5 2C
        lda (INBUF),y                     ; $F27C  B1 E1
        cmp #$41                          ; $F27E  C9 41
        bcs PUCONT                        ; $F280  B0 10
        jsr GETHX                         ; $F282  20 91 EA
        jmp PUWRT                         ; $F285  4C B6 F3
L_F288:
        lda #$0B                          ; $F288  A9 0B
        jmp ERROR                         ; $F28A  4C C8 E7
L_F28D:
        lda #$0E                          ; $F28D  A9 0E
        jmp ERROR                         ; $F28F  4C C8 E7
PUCONT:
        jsr L_FE45                        ; $F292  20 45 FE
        beq L_F288                        ; $F295  F0 F1
        cmp #$28                          ; $F297  C9 28
        bcs L_F288                        ; $F299  B0 ED
        sta $12                           ; $F29B  85 12
        jsr LDDIR                         ; $F29D  20 85 F1
        lda #$00                          ; $F2A0  A9 00
        sta FOUND                         ; $F2A2  8D 38 35
        jsr GETNM                         ; $F2A5  20 D3 F3
        jsr FNDNM                         ; $F2A8  20 F9 F3
        jsr MAPTRK                        ; $F2AB  20 1E F4
        lda FOUND                         ; $F2AE  AD 38 35
        beq L_F2E2                        ; $F2B1  F0 2F
        lda ENTL                          ; $F2B3  AD 39 35
        sta ENTPL                         ; $F2B6  85 10
        lda ENTH                          ; $F2B8  AD 3A 35
        sta ENTPH                         ; $F2BB  85 11
        ldy #$0E                          ; $F2BD  A0 0E
        lda (ENTPL),y                     ; $F2BF  B1 10
        jsr BCD2BIN                       ; $F2C1  20 7A F4
        tax                               ; $F2C4  AA
        clc                               ; $F2C5  18
        adc $12                           ; $F2C6  65 12
        sta $15                           ; $F2C8  85 15
        cmp #$29                          ; $F2CA  C9 29
        bcs L_F2E2                        ; $F2CC  B0 14
        stx $14                           ; $F2CE  86 14
L_F2D0:
        ldy $14                           ; $F2D0  A4 14
        lda PUMAP,y                       ; $F2D2  B9 00 35
        bne L_F2E2                        ; $F2D5  D0 0B
        inc $14                           ; $F2D7  E6 14
        lda $14                           ; $F2D9  A5 14
        cmp $15                           ; $F2DB  C5 15
        bcc L_F2D0                        ; $F2DD  90 F1
        jmp L_F304                        ; $F2DF  4C 04 F3
L_F2E2:
        ldx #$01                          ; $F2E2  A2 01
L_F2E4:
        txa                               ; $F2E4  8A
        clc                               ; $F2E5  18
        adc $12                           ; $F2E6  65 12
        sta $15                           ; $F2E8  85 15
        cmp #$29                          ; $F2EA  C9 29
        bcs L_F28D                        ; $F2EC  B0 9F
        stx $14                           ; $F2EE  86 14
L_F2F0:
        ldy $14                           ; $F2F0  A4 14
        lda PUMAP,y                       ; $F2F2  B9 00 35
        bne L_F301                        ; $F2F5  D0 0A
        inc $14                           ; $F2F7  E6 14
        lda $14                           ; $F2F9  A5 14
        cmp $15                           ; $F2FB  C5 15
        bcc L_F2F0                        ; $F2FD  90 F1
        bcs L_F304                        ; $F2FF  B0 03
L_F301:
        inx                               ; $F301  E8
        bne L_F2E4                        ; $F302  D0 E0
L_F304:
        stx $13                           ; $F304  86 13
        txa                               ; $F306  8A
        jsr L_F490                        ; $F307  20 90 F4
        sta $17                           ; $F30A  85 17
        lda $15                           ; $F30C  A5 15
        sec                               ; $F30E  38
        sbc #$01                          ; $F30F  E9 01
        jsr L_F490                        ; $F311  20 90 F4
        sta $18                           ; $F314  85 18
        lda FOUND                         ; $F316  AD 38 35
        beq L_F328                        ; $F319  F0 0D
        lda ENTL                          ; $F31B  AD 39 35
        sta ENTPL                         ; $F31E  85 10
        lda ENTH                          ; $F320  AD 3A 35
        sta ENTPH                         ; $F323  85 11
        jmp L_F33A                        ; $F325  4C 3A F3
L_F328:
        jsr DIRPTR                        ; $F328  20 AA F1
L_F32B:
        jsr ISEMPTY                       ; $F32B  20 49 F2
        beq L_F33A                        ; $F32E  F0 0A
        jsr NXTENT                        ; $F330  20 56 F2
        bne L_F32B                        ; $F333  D0 F6
        lda #$0F                          ; $F335  A9 0F
        jmp ERROR                         ; $F337  4C C8 E7
L_F33A:
        lda #$01                          ; $F33A  A9 01
        ldy ENTPH                         ; $F33C  A4 11
        cpy #$34                          ; $F33E  C0 34
        bcc L_F344                        ; $F340  90 02
        lda #$02                          ; $F342  A9 02
L_F344:
        sta $16                           ; $F344  85 16
        ldy CMDPOS                        ; $F346  AC E5 2C
        ldx #$00                          ; $F349  A2 00
L_F34B:
        jsr FNUC                          ; $F34B  20 50 F1
        nop                               ; $F34E  EA
        bcc L_F365                        ; $F34F  90 14
        cmp #$23                          ; $F351  C9 23
        bne L_F357                        ; $F353  D0 02
        lda #$20                          ; $F355  A9 20
L_F357:
        sta NAMBUF,x                      ; $F357  9D 28 35
        iny                               ; $F35A  C8
        inx                               ; $F35B  E8
        cpx #$0E                          ; $F35C  E0 0E
        bne L_F34B                        ; $F35E  D0 EB
        sty CMDPOS                        ; $F360  8C E5 2C
        beq L_F36F                        ; $F363  F0 0A
L_F365:
        lda #$20                          ; $F365  A9 20
L_F367:
        sta NAMBUF,x                      ; $F367  9D 28 35
        inx                               ; $F36A  E8
        cpx #$0E                          ; $F36B  E0 0E
        bne L_F367                        ; $F36D  D0 F8
L_F36F:
        ldy #$0D                          ; $F36F  A0 0D
L_F371:
        lda NAMBUF,y                      ; $F371  B9 28 35
        sta (ENTPL),y                     ; $F374  91 10
        dey                               ; $F376  88
        bpl L_F371                        ; $F377  10 F8
        ldy #$0E                          ; $F379  A0 0E
        lda $17                           ; $F37B  A5 17
        sta (ENTPL),y                     ; $F37D  91 10
        iny                               ; $F37F  C8
        lda $18                           ; $F380  A5 18
        sta (ENTPL),y                     ; $F382  91 10
        lda #$12                          ; $F384  A9 12
        jsr SEEK                          ; $F386  20 35 E4
        lda $16                           ; $F389  A5 16
        sta DSECT                         ; $F38B  8D 5E 26
        lda #$01                          ; $F38E  A9 01
        sta DPAGE                         ; $F390  8D 5F 26
        lda #$00                          ; $F393  A9 00
        ldx #$33                          ; $F395  A2 33
        ldy $16                           ; $F397  A4 16
        cpy #$02                          ; $F399  C0 02
        bne L_F39F                        ; $F39B  D0 02
        ldx #$34                          ; $F39D  A2 34
L_F39F:
        sta MEMLO                         ; $F39F  85 FE
        stx MEMHI                         ; $F3A1  86 FF
        jsr HLOAD                         ; $F3A3  20 CD E4
        jsr WRSEC                         ; $F3A6  20 5A E5
        jsr HUNLD                         ; $F3A9  20 DA E4
        lda $19                           ; $F3AC  A5 19
        sta DPAGE                         ; $F3AE  8D 5F 26
        lda $17                           ; $F3B1  A5 17
        jmp L_FE5A                        ; $F3B3  4C 5A FE
PUWRT:
        jsr WSSEEK                        ; $F3B6  20 D1 E9
        lda WSTRK                         ; $F3B9  AD 7D 3A
        sta ZTMP                          ; $F3BC  85 E0
        lda #$08                          ; $F3BE  A9 08
        jsr L_EC05                        ; $F3C0  20 05 EC
L_F3C3:
        jsr WRSEC                         ; $F3C3  20 5A E5
        dec ZTMP                          ; $F3C6  C6 E0
        beq L_F3D0                        ; $F3C8  F0 06
        jsr NXTTRK                        ; $F3CA  20 E4 E9
        jmp L_F3C3                        ; $F3CD  4C C3 F3
L_F3D0:
        jmp a:$009C                       ; $F3D0  4C 9C 00

; GETNM - rest of the command line to NAMBUF (14 chars)
GETNM:
        ldy CMDPOS                        ; $F3D3  AC E5 2C
        ldx #$00                          ; $F3D6  A2 00
L_F3D8:
        jsr FNUC                          ; $F3D8  20 50 F1
        nop                               ; $F3DB  EA
        bcc L_F3EE                        ; $F3DC  90 10
        cmp #$23                          ; $F3DE  C9 23
        bne L_F3E4                        ; $F3E0  D0 02
        lda #$20                          ; $F3E2  A9 20
L_F3E4:
        sta NAMBUF,x                      ; $F3E4  9D 28 35
        iny                               ; $F3E7  C8
        inx                               ; $F3E8  E8
        cpx #$0E                          ; $F3E9  E0 0E
        bne L_F3D8                        ; $F3EB  D0 EB
        rts                               ; $F3ED  60
L_F3EE:
        lda #$20                          ; $F3EE  A9 20
L_F3F0:
        sta NAMBUF,x                      ; $F3F0  9D 28 35
        inx                               ; $F3F3  E8
        cpx #$0E                          ; $F3F4  E0 0E
        bne L_F3F0                        ; $F3F6  D0 F8
        rts                               ; $F3F8  60

; FNDNM - find NAMBUF in the directory: FOUND, ENTL/ENTH
FNDNM:
        jsr DIRPTR                        ; $F3F9  20 AA F1
L_F3FC:
        ldy #$0D                          ; $F3FC  A0 0D
L_F3FE:
        jsr FNDCMP                        ; $F3FE  20 58 F1
        nop                               ; $F401  EA
        nop                               ; $F402  EA
        bne L_F418                        ; $F403  D0 13
        dey                               ; $F405  88
        bpl L_F3FE                        ; $F406  10 F6
        lda #$01                          ; $F408  A9 01
        sta FOUND                         ; $F40A  8D 38 35
        lda ENTPL                         ; $F40D  A5 10
        sta ENTL                          ; $F40F  8D 39 35
        lda ENTPH                         ; $F412  A5 11
        sta ENTH                          ; $F414  8D 3A 35
        rts                               ; $F417  60
L_F418:
        jsr NXTENT                        ; $F418  20 56 F2
        bne L_F3FC                        ; $F41B  D0 DF
        rts                               ; $F41D  60

; MAPTRK - mark used tracks in PUMAP ($3500, $FF = used)
MAPTRK:
        ldx #$27                          ; $F41E  A2 27
        lda #$00                          ; $F420  A9 00
L_F422:
        sta PUMAP,x                       ; $F422  9D 00 35
        dex                               ; $F425  CA
        bpl L_F422                        ; $F426  10 FA
        lda #$FF                          ; $F428  A9 FF
        sta PUMAP                         ; $F42A  8D 00 35
        sta $350C                         ; $F42D  8D 0C 35
        jsr DIRPTR                        ; $F430  20 AA F1
L_F433:
        jsr ISEMPTY                       ; $F433  20 49 F2
        beq L_F474                        ; $F436  F0 3C
        lda FOUND                         ; $F438  AD 38 35
        beq L_F44B                        ; $F43B  F0 0E
        lda ENTPL                         ; $F43D  A5 10
        cmp ENTL                          ; $F43F  CD 39 35
        bne L_F44B                        ; $F442  D0 07
        lda ENTPH                         ; $F444  A5 11
        cmp ENTH                          ; $F446  CD 3A 35
        beq L_F474                        ; $F449  F0 29
L_F44B:
        ldy #$0E                          ; $F44B  A0 0E
        lda (ENTPL),y                     ; $F44D  B1 10
        jsr BCD2BIN                       ; $F44F  20 7A F4
        sta $13                           ; $F452  85 13
        iny                               ; $F454  C8
        lda (ENTPL),y                     ; $F455  B1 10
        jsr BCD2BIN                       ; $F457  20 7A F4
        cmp #$28                          ; $F45A  C9 28
        bcc L_F460                        ; $F45C  90 02
        lda #$27                          ; $F45E  A9 27
L_F460:
        sta $15                           ; $F460  85 15
        ldx $13                           ; $F462  A6 13
L_F464:
        cpx #$28                          ; $F464  E0 28
        bcs L_F474                        ; $F466  B0 0C
        lda #$FF                          ; $F468  A9 FF
        sta PUMAP,x                       ; $F46A  9D 00 35
        cpx $15                           ; $F46D  E4 15
        bcs L_F474                        ; $F46F  B0 03
        inx                               ; $F471  E8
        bne L_F464                        ; $F472  D0 F0
L_F474:
        jsr NXTENT                        ; $F474  20 56 F2
        bne L_F433                        ; $F477  D0 BA
        rts                               ; $F479  60
BCD2BIN:
        pha                               ; $F47A  48
        lsr a                             ; $F47B  4A
        lsr a                             ; $F47C  4A
        lsr a                             ; $F47D  4A
        lsr a                             ; $F47E  4A
        sta $14                           ; $F47F  85 14
        asl a                             ; $F481  0A
        asl a                             ; $F482  0A
        clc                               ; $F483  18
        adc $14                           ; $F484  65 14
        asl a                             ; $F486  0A
        sta $14                           ; $F487  85 14
        pla                               ; $F489  68
        and #$0F                          ; $F48A  29 0F
        clc                               ; $F48C  18
        adc $14                           ; $F48D  65 14
        rts                               ; $F48F  60
L_F490:
        ldx #$00                          ; $F490  A2 00
L_F492:
        cmp #$0A                          ; $F492  C9 0A
        bcc L_F49B                        ; $F494  90 05
        sbc #$0A                          ; $F496  E9 0A
        inx                               ; $F498  E8
        bne L_F492                        ; $F499  D0 F7
L_F49B:
        sta $14                           ; $F49B  85 14
        txa                               ; $F49D  8A
        asl a                             ; $F49E  0A
        asl a                             ; $F49F  0A
        asl a                             ; $F4A0  0A
        asl a                             ; $F4A1  0A
        ora $14                           ; $F4A2  05 14
        rts                               ; $F4A4  60

; RESET - cold start
; RESET ENTRY
RESET:
        sei                               ; $F4A5  78
        cld                               ; $F4A6  D8
        ldx #$FF                          ; $F4A7  A2 FF
        txs                               ; $F4A9  9A
        lda #$03                          ; $F4AA  A9 03
        sta ACIAS                         ; $F4AC  8D 00 80
        lda #$11                          ; $F4AF  A9 11
        sta ACIAS                         ; $F4B1  8D 00 80
        ldx #$00                          ; $F4B4  A2 00
L_F4B6:
        lda D_F589,x                      ; $F4B6  BD 89 F5
        beq L_F4C1                        ; $F4B9  F0 06
        jsr L_F57C                        ; $F4BB  20 7C F5
        inx                               ; $F4BE  E8
        bne L_F4B6                        ; $F4BF  D0 F5
L_F4C1:
        lda #$04                          ; $F4C1  A9 04
        sta $C001                         ; $F4C3  8D 01 C0
        lda #$40                          ; $F4C6  A9 40
        sta PIAA                          ; $F4C8  8D 00 C0
        lda #$00                          ; $F4CB  A9 00
        sta $C001                         ; $F4CD  8D 01 C0
        lda #$40                          ; $F4D0  A9 40
        sta PIAA                          ; $F4D2  8D 00 C0
        lda #$04                          ; $F4D5  A9 04
        sta $C001                         ; $F4D7  8D 01 C0
        lda #$04                          ; $F4DA  A9 04
        sta $C003                         ; $F4DC  8D 03 C0
        lda #$FF                          ; $F4DF  A9 FF
        sta PIAB                          ; $F4E1  8D 02 C0
        lda #$00                          ; $F4E4  A9 00
        sta $C003                         ; $F4E6  8D 03 C0
        lda #$FF                          ; $F4E9  A9 FF
        sta PIAB                          ; $F4EB  8D 02 C0
        lda #$04                          ; $F4EE  A9 04
        sta $C003                         ; $F4F0  8D 03 C0
        lda #$20                          ; $F4F3  A9 20
        sta $F4                           ; $F4F5  85 F4
        lda #$F9                          ; $F4F7  A9 F9
        sta $F5                           ; $F4F9  85 F5
L_F4FB:
        ldy #$00                          ; $F4FB  A0 00
        lda ($F4),y                       ; $F4FD  B1 F4
        sta $F0                           ; $F4FF  85 F0
        iny                               ; $F501  C8
        lda ($F4),y                       ; $F502  B1 F4
        sta $F1                           ; $F504  85 F1
        iny                               ; $F506  C8
        lda ($F4),y                       ; $F507  B1 F4
        sta $F2                           ; $F509  85 F2
        iny                               ; $F50B  C8
        lda ($F4),y                       ; $F50C  B1 F4
        sta $F3                           ; $F50E  85 F3
        iny                               ; $F510  C8
        lda ($F4),y                       ; $F511  B1 F4
        tax                               ; $F513  AA
        ora $F0                           ; $F514  05 F0
        ora $F1                           ; $F516  05 F1
        beq L_F531                        ; $F518  F0 17
        ldy #$00                          ; $F51A  A0 00
L_F51C:
        lda ($F0),y                       ; $F51C  B1 F0
        sta ($F2),y                       ; $F51E  91 F2
        iny                               ; $F520  C8
        dex                               ; $F521  CA
        bne L_F51C                        ; $F522  D0 F8
        lda $F4                           ; $F524  A5 F4
        clc                               ; $F526  18
        adc #$06                          ; $F527  69 06
        sta $F4                           ; $F529  85 F4
        bcc L_F4FB                        ; $F52B  90 CE
        inc $F5                           ; $F52D  E6 F5
        bne L_F4FB                        ; $F52F  D0 CA
L_F531:
        ldy #RAMTOP                       ; $F531  A0 7F  (FPGA: $BF)
L_F533:
        ldx #$00                          ; $F533  A2 00
        stx MEMLO                         ; $F535  86 FE
        sty MEMHI                         ; $F537  84 FF
        lda #$A5                          ; $F539  A9 A5
        sta (MEMLO,x)                     ; $F53B  81 FE
        cmp (MEMLO,x)                     ; $F53D  C1 FE
        bne L_F549                        ; $F53F  D0 08
        lda #$5A                          ; $F541  A9 5A
        sta (MEMLO,x)                     ; $F543  81 FE
        cmp (MEMLO,x)                     ; $F545  C1 FE
        beq L_F54C                        ; $F547  F0 03
L_F549:
        dey                               ; $F549  88
        bne L_F533                        ; $F54A  D0 E7
L_F54C:
        sty $2300                         ; $F54C  8C 00 23
        lda #$01                          ; $F54F  A9 01
        sta DTMP                          ; $F551  85 FD
        jsr SELDRV                        ; $F553  20 43 E7
        jsr HOME                          ; $F556  20 DC E3
        lda #$06                          ; $F559  A9 06
        jsr SEEK                          ; $F55B  20 35 E4
        lda #$03                          ; $F55E  A9 03
        sta DSECT                         ; $F560  8D 5E 26
        lda #$00                          ; $F563  A9 00
        sta MEMLO                         ; $F565  85 FE
        sta MEMHI                         ; $F567  85 FF
        jsr HLOAD                         ; $F569  20 CD E4
        jsr RDSECP                        ; $F56C  20 24 F0
        jsr HUNLD                         ; $F56F  20 DA E4
        ldx #$00                          ; $F572  A2 00
        stx $00                           ; $F574  86 00
        ldx #$28                          ; $F576  A2 28
        txs                               ; $F578  9A
        jmp L_E0A6                        ; $F579  4C A6 E0
L_F57C:
        pha                               ; $F57C  48
L_F57D:
        lda ACIAS                         ; $F57D  AD 00 80
        and #$02                          ; $F580  29 02
        beq L_F57D                        ; $F582  F0 F9
        pla                               ; $F584  68
        sta ACIAD                         ; $F585  8D 01 80
        rts                               ; $F588  60
D_F589:
        .byte $0D,$0A,$4F,$53,$2D,$36,$35,$44,$20,$56,$33,$2E,$33,$20,$52,$4F; $F589
        .byte $4D,$0D,$0A,$00             ; $F599

; NMI/IRQ - just return
        rti                               ; $F59D  40
        .byte $00,$7D,$E2,$7D,$E2,$7D,$E2,$0D,$E1,$10,$E1,$28,$E1,$77,$E1,$7D; $F59E
        .byte $E2,$54,$E2,$54,$E2,$54,$E2,$27,$E1,$17,$E1,$39,$E1,$8A,$E1,$54; $F5AE
        .byte $E2,$01,$01,$00,$00,$00,$7E,$3A,$7E,$42,$50,$51,$50,$00,$7E,$42; $F5BE
        .byte $7E,$4A,$50,$51,$50,$00,$4C,$BA,$E0,$4C,$BD,$E0,$4C,$C4,$E0,$4C; $F5CE
        .byte $C7,$E0,$00,$00,$00,$00,$AD,$25,$2E,$60,$8D,$00,$80,$60,$AD,$7E; $F5DE
        .byte $42,$60,$8D,$7E,$42,$60,$AD,$7E,$4A,$60,$8D,$7E,$4A,$60,$00,$00; $F5EE
        .byte $00,$4C,$CB,$25,$01,$00,$00,$00,$00,$00,$00,$4C,$DC,$E3,$4C,$35; $F5FE
        .byte $E4,$4C,$CD,$E4,$4C,$DA,$E4,$4C,$E1,$E4,$4C,$F6,$E4,$4C,$5A,$E5; $F60E
        .byte $00,$4C,$24,$F0,$4C,$43,$E7,$4C,$C8,$E7,$4C,$CE,$E7,$4C,$CE,$E7; $F61E
        .byte $01,$4C,$98,$E8,$4C,$FF,$FF,$4C,$03,$13,$4C,$3D,$E8,$4C,$00,$17; $F62E
        .byte $4C,$E4,$E9,$0E,$11,$4C,$24,$13,$4C,$86,$EA,$4C,$91,$EA,$4C,$CD; $F63E
        .byte $EA,$4C,$D6,$EA,$4C,$F5,$EA,$4C,$FE,$EA,$0D,$00,$00,$00,$00,$00; $F64E
        .byte $00,$52,$55,$4E,$22,$42,$45,$58,$45,$43,$2A,$0D,$41,$01,$00,$09; $F65E
        .byte $00,$00,$00,$00,$1B,$00,$47,$62,$44,$10,$0C,$00,$08,$00,$7F,$5F; $F66E
        .byte $14,$06,$09,$12,$40,$07,$20,$7B,$0D,$00,$00,$4F,$07,$00,$00,$FF; $F67E
        .byte $00,$BA,$0B,$9B,$FE,$EA,$C0,$0B,$9B,$FE,$EA,$FA,$0B,$43,$C7,$E0; $F68E
        .byte $04,$13,$F7,$5A,$EA,$22,$13,$F7,$5A,$EA,$28,$13,$6A,$CD,$EA,$2C; $F69E
        .byte $13,$92,$F5,$EA,$2F,$13,$73,$D6,$EA,$3C,$13,$51,$CE,$E7,$68,$13; $F6AE
        .byte $73,$D6,$EA,$AE,$93,$2A,$E8,$B3,$93,$C0,$3D,$DE,$13,$43,$C7,$E0; $F6BE
        .byte $E1,$13,$40,$C4,$E0,$EB,$13,$43,$C7,$E0,$EE,$13,$43,$C7,$E0,$F3; $F6CE
        .byte $13,$43,$C7,$E0,$F6,$13,$43,$C7,$E0,$FB,$13,$43,$C7,$E0,$FE,$13; $F6DE
        .byte $43,$C7,$E0,$C5,$14,$F7,$5A,$EA,$DA,$14,$43,$C7,$E0,$DD,$14,$84; $F6EE
        .byte $01,$E8,$2D,$15,$7D,$FA,$E7,$33,$15,$F7,$5A,$EA,$36,$15,$6A,$CD; $F6FE
        .byte $EA,$48,$15,$00,$00,$80,$4E,$15,$FF,$87,$E2,$63,$15,$9F,$28,$E1; $F70E
        .byte $71,$15,$00,$D1,$F0,$04,$17,$73,$D6,$EA,$26,$97,$2A,$E8,$2B,$97; $F71E
        .byte $C0,$3D,$5F,$17,$9B,$FC,$E9,$7C,$17,$84,$01,$E8,$9E,$17,$E4,$45; $F72E
        .byte $EA,$A1,$17,$43,$C7,$E0,$15,$1A,$40,$C4,$E0,$B6,$1A,$40,$C4,$E0; $F73E
        .byte $B6,$1B,$E4,$45,$EA,$D7,$1B,$51,$CE,$E7,$97,$1C,$40,$C4,$E0,$9D; $F74E
        .byte $1E,$0D,$55,$E2,$0E,$1F,$18,$7E,$E2,$19,$1F,$01,$D1,$F0,$1E,$1F; $F75E
        .byte $00,$00,$80,$36,$1F,$7D,$FA,$E7,$FF,$FF; $F76E

; PATCH LISTS: applied to BASIC after BA (F778) and to sectors read by RDSECP
; record: address (bit 15 set = 1-byte patch), expected old byte, new byte(s)
PATCH_F778:
        .word $0222                       ; $F778
        .byte $6F     ; was $6F
        .word $ED1F
        .word $0460                       ; $F77D
        .byte $A1     ; was $A1
        .word $E329
        .word $0472                       ; $F782
        .byte $CF     ; was $CF
        .word $EC9C
        .word $055B                       ; $F787
        .byte $19     ; was $19
        .word $EDC9
        .word $0588                       ; $F78C
        .byte $36     ; was $36
        .word INLINE
        .word $0592                       ; $F791
        .byte $43     ; was $43
        .word OUTCH
        .word $0597                       ; $F796
        .byte $43     ; was $43
        .word OUTCH
        .word $059C                       ; $F79B
        .byte $43     ; was $43
        .word OUTCH
        .word $05BE                       ; $F7A0
        .byte $01     ; was $01
        .word $EDB1
        .word $0B08                       ; $F7A5
        .byte $43     ; was $43
        .word OUTCH
        .word $16A9                       ; $F7AA
        .byte $D0     ; was $D0
        .word $EC9F
        .word $17B9                       ; $F7AF
        .byte $5F     ; was $5F
        .word UCASE
        .word $17BF                       ; $F7B4
        .byte $5F     ; was $5F
        .word UCASE
        .word $17CB                       ; $F7B9
        .byte $5F     ; was $5F
        .word UCASE
        .word $17D3                       ; $F7BE
        .byte $5F     ; was $5F
        .word UCASE
        .word $17DC                       ; $F7C3
        .byte $BC     ; was $BC
        .word SEEK
        .word $1959                       ; $F7C8
        .byte $E4     ; was $E4
        .word GETCH
        .word $1961                       ; $F7CD
        .byte $A1     ; was $A1
        .word $E129
        .word $1964                       ; $F7D2
        .byte $5F     ; was $5F
        .word UCASE
        .word $1976                       ; $F7D7
        .byte $A1     ; was $A1
        .word $E129
        .word $2061                       ; $F7DC
        .byte $5F     ; was $5F
        .word UCASE
        .word $2079                       ; $F7E1
        .byte $E4     ; was $E4
        .word GETCH
        .word $2089                       ; $F7E6
        .byte $F7     ; was $F7
        .word SWAPZP
        .word $2093                       ; $F7EB
        .byte $E4     ; was $E4
        .word GETCH
        .word $20AA                       ; $F7F0
        .byte $F7     ; was $F7
        .word SWAPZP
        .word $20C1                       ; $F7F5
        .byte $A1     ; was $A1
        .word $EC6E
        .word $20C5                       ; $F7FA
        .byte $67     ; was $67
        .word RDSECP
        .word $20E5                       ; $F7FF
        .byte $73     ; was $73
        .word PRINT
        .word $2125 | $8000, $E82A   ; $2125: $2A -> $E8; $F804
        .word $212D | $8000, $3DC0   ; $212D: $C0 -> $3D; $F808
        .word $2135                       ; $F80C
        .byte $F7     ; was $F7
        .word SWAPZP
        .word $218E                       ; $F811
        .byte $F7     ; was $F7
        .word SWAPZP
        .word $2191                       ; $F816
        .byte $73     ; was $73
        .word PRINT
        .word $21A5                       ; $F81B
        .byte $BC     ; was $BC
        .word SEEK
        .word $21B5                       ; $F820
        .byte $54     ; was $54
        .word HLOAD
        .word $2232                       ; $F825
        .byte $A7     ; was $A7
        .word CMD_LO
        .word $2235                       ; $F82A
        .byte $F7     ; was $F7
        .word SWAPZP
        .word $2241                       ; $F82F
        .byte $92     ; was $92
        .word PRHEX
        .word $2244                       ; $F834
        .byte $F7     ; was $F7
        .word SWAPZP
        .word $2247                       ; $F839
        .byte $73     ; was $73
        .word PRINT
        .word $2251                       ; $F83E
        .byte $51     ; was $51
        .word PROMPT
        .word $2266                       ; $F843
        .byte $F7     ; was $F7
        .word $F0FD
        .word $2269                       ; $F848
        .byte $84     ; was $84
        .word DOCMD
        .word $226C                       ; $F84D
        .byte $F7     ; was $F7
        .word SWAPZP
        .word $2287                       ; $F852
        .byte $F7     ; was $F7
        .word SWAPZP
        .word $228C                       ; $F857
        .byte $77     ; was $77
        .word L_E1FF
        .word $228F                       ; $F85C
        .byte $61     ; was $61
        .word HUNLD
        .word $2292                       ; $F861
        .byte $F7     ; was $F7
        .word SWAPZP
        .word $22A3                       ; $F866
        .byte $A6     ; was $A6
        .word FINDFILE
        .word $22BA                       ; $F86B
        .byte $BC     ; was $BC
        .word SEEK
        .word $22BD                       ; $F870
        .byte $1A     ; was $1A
        .word RDHEAD
        .word $22C9                       ; $F875
        .byte $D7     ; was $D7
        .word $E550
        .word $22CC                       ; $F87A
        .byte $5D     ; was $5D
        .word $E6DA
        .word $22CF                       ; $F87F
        .byte $D7     ; was $D7
        .word $E550
        .word $22D2                       ; $F884
        .byte $5D     ; was $5D
        .word $E6DA
        .word $22E6                       ; $F889
        .byte $C6     ; was $C6
        .word SELDRV
        .word $22E9                       ; $F88E
        .byte $63     ; was $63
        .word HOME
        .word $22EC                       ; $F893
        .byte $A6     ; was $A6
        .word BIN2TRK
        .word $22EF                       ; $F898
        .byte $54     ; was $54
        .word HLOAD
        .word $22F2                       ; $F89D
        .byte $5D     ; was $5D
        .word $E6DA
        .word $22F5                       ; $F8A2
        .byte $61     ; was $61
        .word HUNLD
        .word $22F8                       ; $F8A7
        .byte $F7     ; was $F7
        .word SWAPZP
        .word $FFFF               ; end of list; $F8AC
PATCH_F8AE:
        .word $00A1                       ; $F8AE
        .byte $7D     ; was $7D
        .word SETERR
        .word $00A4                       ; $F8B3
        .byte $7B     ; was $7B
        .word L_EC11
        .word $00AA                       ; $F8B8
        .byte $4E     ; was $4E
        .word $E7CB
        .word $00BE                       ; $F8BD
        .byte $7D     ; was $7D
        .word SETERR
        .word $FFFF               ; end of list; $F8C2
PATCH_F8C4:
        .word $20C8                       ; $F8C4
        .byte $61     ; was $61
        .word HUNLD
        .word $20CB                       ; $F8C9
        .byte $F7     ; was $F7
        .word SWAPZP
        .word $20D2                       ; $F8CE
        .byte $7D     ; was $7D
        .word SETERR
        .word $20D8                       ; $F8D3
        .byte $50     ; was $50
        .word $EAB3
        .word $20E0                       ; $F8D8
        .byte $3D     ; was $3D
        .word $E3C7
        .word $2149                       ; $F8DD
        .byte $F7     ; was $F7
        .word SWAPZP
        .word $FFFF               ; end of list; $F8E2
PATCH_F8E4:
        .word $2E9D                       ; $F8E4
        .byte $CC     ; was $CC
        .word L_E154
        .word $2EA2                       ; $F8E9
        .byte $20     ; was $20
        .word L_E1A8
        .word $2EB3                       ; $F8EE
        .byte $F7     ; was $F7
        .word SWAPZP
        .word $2EC2                       ; $F8F3
        .byte $67     ; was $67
        .word RDSECP
        .word $2EC8                       ; $F8F8
        .byte $0C     ; was $0C
        .word $ECDC
        .word $2EE7                       ; $F8FD
        .byte $F7     ; was $F7
        .word SWAPZP
        .word $2F4D                       ; $F902
        .byte $ED     ; was $ED
        .word $ECBD
        .word $2F5F                       ; $F907
        .byte $54     ; was $54
        .word HLOAD
        .word $2F62                       ; $F90C
        .byte $F7     ; was $F7
        .word SWAPZP
        .word $FFFF               ; end of list; $F911

; SECTOR PATCH TABLE: track, sector, patch list to apply after reading it
SECPAT:
        .byte $06, 3             ; track, sector; $F913
        .word PATCH_F8AE
D_F914 = SECPAT + 1
D_F915 = SECPAT + 2
D_F916 = SECPAT + 3
        .byte $12, 3             ; track, sector; $F917
        .word PATCH_F8C4
        .byte $12, 4             ; track, sector; $F91B
        .word PATCH_F8E4
        .byte $FF                 ; end   ; $F91F

; RESET RAM INITIALISATION TABLE: source, destination, length
INITTAB:
        .word $F59E, $2300, 1             ; $F920
        .word $F59F, $2301, 32            ; $F926
        .word $F5BF, INMASK, 21           ; $F92C
        .word $F5D4, $2336, 3             ; $F932
        .word $F5D7, $2339, 3             ; $F938
        .word $F5DA, $2340, 3             ; $F93E
        .word $F5DD, $2343, 3             ; $F944
        .word $F5E0, XSAV, 1              ; $F94A
        .word $F5E1, YSAV, 1              ; $F950
        .word $F5E2, CHRSAV, 1            ; $F956
        .word $F5E3, DEVOFS, 1            ; $F95C
        .word $F5E4, $2389, 4             ; $F962
        .word $F5E8, $2390, 4             ; $F968
        .word $F5EC, $23AB, 4             ; $F96E
        .word $F5F0, $23C2, 4             ; $F974
        .word $F5F4, $23FC, 4             ; $F97A
        .word $F5F8, $2415, 4             ; $F980
        .word $F5FC, PAGEFLG, 1           ; $F986
        .word $F5FD, ESCCNT, 1            ; $F98C
        .word $F5FE, $2657, 4             ; $F992
        .word $F602, DRIVE, 7             ; $F998
        .word $F609, $2663, 3             ; $F99E
        .word $F60C, $26BC, 3             ; $F9A4
        .word $F60F, $2754, 3             ; $F9AA
        .word $F612, $2761, 3             ; $F9B0
        .word $F615, $2768, 3             ; $F9B6
        .word $F618, $277D, 3             ; $F9BC
        .word $F61B, $27E1, 3             ; $F9C2
        .word $F61E, NOERR9, 1            ; $F9C8
        .word $F61F, $2967, 3             ; $F9CE
        .word $F622, $29C6, 3             ; $F9D4
        .word $F625, $2A4B, 3             ; $F9DA
        .word $F628, ERRJMP, 3            ; $F9E0
        .word $F62B, $2A51, 3             ; $F9E6
        .word $F62E, DEFIO, 1             ; $F9EC
        .word $F62F, $2B1A, 3             ; $F9F2
        .word $F632, $2B52, 3             ; $F9F8
        .word $F635, $2C04, 3             ; $F9FE
        .word $F638, $2C0B, 3             ; $FA04
        .word $F63B, $2C12, 3             ; $FA0A
        .word $F63E, $2C83, 3             ; $FA10
        .word $F641, CMDPOS, 1            ; $FA16
        .word $F642, CMDLEN, 1            ; $FA1C
        .word $F643, SWPRET, 3            ; $FA22
        .word $F646, $2D23, 3             ; $FA28
        .word $F649, $2D2E, 3             ; $FA2E
        .word $F64C, $2D6A, 3             ; $FA34
        .word $F64F, $2D73, 3             ; $FA3A
        .word $F652, $2D92, 3             ; $FA40
        .word $F655, $2D9B, 3             ; $FA46
        .word $F658, CMDBUF, 18           ; $FA4C
        .word $F66A, PAGELEN, 3           ; $FA52
        .word $F66D, $32C8, 1             ; $FA58
        .word $F66E, $36D0, 1             ; $FA5E
        .word $F66F, $36DA, 1             ; $FA64
        .word $F670, $36DE, 1             ; $FA6A
        .word $F671, $374D, 1             ; $FA70
        .word $F672, $3753, 29            ; $FA76
        .byte $00,$00,$00,$00,$00,$00,$FF ; $FA7C

; CHKSY - SY command, else on to the extensions
CHKSY:
        cpx #$4C                          ; $FA83  E0 4C
        bne EXTCMD0                       ; $FA85  D0 20
        cpy #$00                          ; $FA87  C0 00
        bne EXTCMD0                       ; $FA89  D0 1C
        lda (INBUF),y                     ; $FA8B  B1 E1
        jsr UCASE                         ; $FA8D  20 0F F0
        cmp #$53                          ; $FA90  C9 53
        bne EXTCMD0                       ; $FA92  D0 13
        iny                               ; $FA94  C8
        lda (INBUF),y                     ; $FA95  B1 E1
        jsr UCASE                         ; $FA97  20 0F F0
        cmp #$59                          ; $FA9A  C9 59
        bne EXTCMD0                       ; $FA9C  D0 09
        lda #$FA                          ; $FA9E  A9 FA
        pha                               ; $FAA0  48
        lda #$AB                          ; $FAA1  A9 AB
        pha                               ; $FAA3  48
        jmp SKIPAR                        ; $FAA4  4C 21 E8
EXTCMD0:
        jmp EXTCMD                        ; $FAA7  4C 60 FD
        .byte $EA,$EA                     ; $FAAA

; SY N|V - list the assembler symbol table by name or value
        jsr GETCH                         ; $FAAC  20 45 EA
        ldx #$00                          ; $FAAF  A2 00
        cmp #$4E                          ; $FAB1  C9 4E
        beq L_FABD                        ; $FAB3  F0 08
        inx                               ; $FAB5  E8
        cmp #$56                          ; $FAB6  C9 56
        beq L_FABD                        ; $FAB8  F0 03
        jmp L_FBD8                        ; $FABA  4C D8 FB
L_FABD:
        stx $EC                           ; $FABD  86 EC
        jsr L_FACB                        ; $FABF  20 CB FA
        bcs L_FACA                        ; $FAC2  B0 06
        jsr L_FB42                        ; $FAC4  20 42 FB
        jmp L_FBD8                        ; $FAC7  4C D8 FB
L_FACA:
        rts                               ; $FACA  60
L_FACB:
        lda $2F83                         ; $FACB  AD 83 2F
        sta $EA                           ; $FACE  85 EA
        lda $2F84                         ; $FAD0  AD 84 2F
        sta $EB                           ; $FAD3  85 EB
        jsr L_FAF2                        ; $FAD5  20 F2 FA
        bcs L_FAE4                        ; $FAD8  B0 0A
        lda $EA                           ; $FADA  A5 EA
        sta $DE                           ; $FADC  85 DE
        lda $EB                           ; $FADE  A5 EB
        sta $DF                           ; $FAE0  85 DF
        clc                               ; $FAE2  18
        rts                               ; $FAE3  60
L_FAE4:
        lda $DE                           ; $FAE4  A5 DE
        sta $EA                           ; $FAE6  85 EA
        lda $DF                           ; $FAE8  A5 DF
        sta $EB                           ; $FAEA  85 EB
        jsr L_FAF2                        ; $FAEC  20 F2 FA
        bcs L_FB1C                        ; $FAEF  B0 2B
        rts                               ; $FAF1  60
L_FAF2:
        lda $EB                           ; $FAF2  A5 EB
        cmp #$30                          ; $FAF4  C9 30
        bcc L_FB1A                        ; $FAF6  90 22
        lda $EA                           ; $FAF8  A5 EA
        bne L_FB02                        ; $FAFA  D0 06
        lda $EB                           ; $FAFC  A5 EB
        cmp #RAMTOP+1                     ; $FAFE  C9 80  (end of RAM + 1)
        beq L_FB2B                        ; $FB00  F0 29
L_FB02:
        jsr L_FB2D                        ; $FB02  20 2D FB
L_FB05:
        lda $E6                           ; $FB05  A5 E6
        cmp $EA                           ; $FB07  C5 EA
        bne L_FB11                        ; $FB09  D0 06
        lda $E7                           ; $FB0B  A5 E7
        cmp $EB                           ; $FB0D  C5 EB
        beq L_FB2B                        ; $FB0F  F0 1A
L_FB11:
        jsr L_FB36                        ; $FB11  20 36 FB
        lda $E7                           ; $FB14  A5 E7
        cmp #$30                          ; $FB16  C9 30
        bcs L_FB05                        ; $FB18  B0 EB
L_FB1A:
        sec                               ; $FB1A  38
        rts                               ; $FB1B  60
L_FB1C:
        ldx #$00                          ; $FB1C  A2 00
L_FB1E:
        lda D_FCD4,x                      ; $FB1E  BD D4 FC
        beq L_FB29                        ; $FB21  F0 06
        jsr L_FCCA                        ; $FB23  20 CA FC
        inx                               ; $FB26  E8
        bne L_FB1E                        ; $FB27  D0 F5
L_FB29:
        sec                               ; $FB29  38
        rts                               ; $FB2A  60
L_FB2B:
        clc                               ; $FB2B  18
        rts                               ; $FB2C  60
L_FB2D:
        lda #$FA                          ; $FB2D  A9 FA
        sta $E6                           ; $FB2F  85 E6
        lda #RAMTOP                       ; $FB31  A9 7F  (table from top page + $FA down)
        sta $E7                           ; $FB33  85 E7
        rts                               ; $FB35  60
L_FB36:
        sec                               ; $FB36  38
        lda $E6                           ; $FB37  A5 E6
        sbc #$06                          ; $FB39  E9 06
        sta $E6                           ; $FB3B  85 E6
        bcs L_FB41                        ; $FB3D  B0 02
        dec $E7                           ; $FB3F  C6 E7
L_FB41:
        rts                               ; $FB41  60
L_FB42:
        ldx #$00                          ; $FB42  A2 00
L_FB44:
        lda D_FB91,x                      ; $FB44  BD 91 FB
        sta $EA                           ; $FB47  85 EA
        lda D_FB92,x                      ; $FB49  BD 92 FB
        sta $EB                           ; $FB4C  85 EB
        ora $EA                           ; $FB4E  05 EA
        beq L_FB90                        ; $FB50  F0 3E
L_FB52:
        lda #$00                          ; $FB52  A9 00
        sta $ED                           ; $FB54  85 ED
        jsr L_FB2D                        ; $FB56  20 2D FB
L_FB59:
        sec                               ; $FB59  38
        lda $E6                           ; $FB5A  A5 E6
        sbc $EA                           ; $FB5C  E5 EA
        sta $E8                           ; $FB5E  85 E8
        lda $E7                           ; $FB60  A5 E7
        sbc $EB                           ; $FB62  E5 EB
        sta $E9                           ; $FB64  85 E9
        bcc L_FB88                        ; $FB66  90 20
        cmp $DF                           ; $FB68  C5 DF
        bcc L_FB88                        ; $FB6A  90 1C
        bne L_FB74                        ; $FB6C  D0 06
        lda $E8                           ; $FB6E  A5 E8
        cmp $DE                           ; $FB70  C5 DE
        bcc L_FB88                        ; $FB72  90 14
L_FB74:
        jsr L_FBA3                        ; $FB74  20 A3 FB
        beq L_FB82                        ; $FB77  F0 09
        bcc L_FB82                        ; $FB79  90 07
        jsr L_FBC8                        ; $FB7B  20 C8 FB
        lda #$01                          ; $FB7E  A9 01
        sta $ED                           ; $FB80  85 ED
L_FB82:
        jsr L_FB36                        ; $FB82  20 36 FB
        jmp L_FB59                        ; $FB85  4C 59 FB
L_FB88:
        lda $ED                           ; $FB88  A5 ED
        bne L_FB52                        ; $FB8A  D0 C6
        inx                               ; $FB8C  E8
        inx                               ; $FB8D  E8
        bne L_FB44                        ; $FB8E  D0 B4
L_FB90:
        rts                               ; $FB90  60
D_FB91:
        .byte $6E                         ; $FB91
D_FB92:
        .byte $10,$0E,$07,$18,$03,$56,$01,$8A,$00,$3C,$00,$18,$00,$06,$00,$00; $FB92
        .byte $00                         ; $FBA2
L_FBA3:
        lda $EC                           ; $FBA3  A5 EC
        beq L_FBAE                        ; $FBA5  F0 07
        ldy #$04                          ; $FBA7  A0 04
        jsr L_FBBB                        ; $FBA9  20 BB FB
        bne L_FBBA                        ; $FBAC  D0 0C
L_FBAE:
        ldy #$00                          ; $FBAE  A0 00
        jsr L_FBBB                        ; $FBB0  20 BB FB
        bne L_FBBA                        ; $FBB3  D0 05
        ldy #$02                          ; $FBB5  A0 02
        jsr L_FBBB                        ; $FBB7  20 BB FB
L_FBBA:
        rts                               ; $FBBA  60
L_FBBB:
        iny                               ; $FBBB  C8
        lda ($E6),y                       ; $FBBC  B1 E6
        cmp ($E8),y                       ; $FBBE  D1 E8
        bne L_FBC7                        ; $FBC0  D0 05
        dey                               ; $FBC2  88
        lda ($E6),y                       ; $FBC3  B1 E6
        cmp ($E8),y                       ; $FBC5  D1 E8
L_FBC7:
        rts                               ; $FBC7  60
L_FBC8:
        ldy #$05                          ; $FBC8  A0 05
L_FBCA:
        lda ($E6),y                       ; $FBCA  B1 E6
        pha                               ; $FBCC  48
        lda ($E8),y                       ; $FBCD  B1 E8
        sta ($E6),y                       ; $FBCF  91 E6
        pla                               ; $FBD1  68
        sta ($E8),y                       ; $FBD2  91 E8
        dey                               ; $FBD4  88
        bpl L_FBCA                        ; $FBD5  10 F3
        rts                               ; $FBD7  60
L_FBD8:
        jsr L_FACB                        ; $FBD8  20 CB FA
        bcs L_FC50                        ; $FBDB  B0 73
        lda $DF                           ; $FBDD  A5 DF
        cmp #RAMTOP+1                     ; $FBDF  C9 80
        beq L_FC50                        ; $FBE1  F0 6D
        ldx #$00                          ; $FBE3  A2 00
L_FBE5:
        lda D_FCE6,x                      ; $FBE5  BD E6 FC
        beq L_FBF0                        ; $FBE8  F0 06
        jsr L_FCCA                        ; $FBEA  20 CA FC
        inx                               ; $FBED  E8
        bne L_FBE5                        ; $FBEE  D0 F5
L_FBF0:
        jsr L_FB2D                        ; $FBF0  20 2D FB
        lda #$00                          ; $FBF3  A9 00
        sta $ED                           ; $FBF5  85 ED
L_FBF7:
        lda $E7                           ; $FBF7  A5 E7
        cmp $DF                           ; $FBF9  C5 DF
        bcc L_FC49                        ; $FBFB  90 4C
        bne L_FC05                        ; $FBFD  D0 06
        lda $E6                           ; $FBFF  A5 E6
        cmp $DE                           ; $FC01  C5 DE
        bcc L_FC49                        ; $FC03  90 44
L_FC05:
        ldy #$00                          ; $FC05  A0 00
        jsr L_FC51                        ; $FC07  20 51 FC
        ldy #$02                          ; $FC0A  A0 02
        jsr L_FC51                        ; $FC0C  20 51 FC
        lda #$20                          ; $FC0F  A9 20
        jsr L_FCCA                        ; $FC11  20 CA FC
        lda #$24                          ; $FC14  A9 24
        jsr L_FCCA                        ; $FC16  20 CA FC
        ldy #$05                          ; $FC19  A0 05
        lda ($E6),y                       ; $FC1B  B1 E6
        jsr L_FCAE                        ; $FC1D  20 AE FC
        ldy #$04                          ; $FC20  A0 04
        lda ($E6),y                       ; $FC22  B1 E6
        jsr L_FCAE                        ; $FC24  20 AE FC
        inc $ED                           ; $FC27  E6 ED
        lda $ED                           ; $FC29  A5 ED
        cmp #$04                          ; $FC2B  C9 04
        bne L_FC38                        ; $FC2D  D0 09
        jsr L_FCC3                        ; $FC2F  20 C3 FC
        lda #$00                          ; $FC32  A9 00
        sta $ED                           ; $FC34  85 ED
        beq L_FC43                        ; $FC36  F0 0B
L_FC38:
        lda #$20                          ; $FC38  A9 20
        jsr L_FCCA                        ; $FC3A  20 CA FC
        jsr L_FCCA                        ; $FC3D  20 CA FC
        jsr L_FCCA                        ; $FC40  20 CA FC
L_FC43:
        jsr L_FB36                        ; $FC43  20 36 FB
        jmp L_FBF7                        ; $FC46  4C F7 FB
L_FC49:
        lda $ED                           ; $FC49  A5 ED
        beq L_FC50                        ; $FC4B  F0 03
        jsr L_FCC3                        ; $FC4D  20 C3 FC
L_FC50:
        rts                               ; $FC50  60
L_FC51:
        lda ($E6),y                       ; $FC51  B1 E6
        sta $EA                           ; $FC53  85 EA
        iny                               ; $FC55  C8
        lda ($E6),y                       ; $FC56  B1 E6
        sta $EB                           ; $FC58  85 EB
        ldx #$00                          ; $FC5A  A2 00
L_FC5C:
        lda $EA                           ; $FC5C  A5 EA
        sec                               ; $FC5E  38
        sbc #$40                          ; $FC5F  E9 40
        pha                               ; $FC61  48
        lda $EB                           ; $FC62  A5 EB
        sbc #$06                          ; $FC64  E9 06
        bcc L_FC70                        ; $FC66  90 08
        sta $EB                           ; $FC68  85 EB
        pla                               ; $FC6A  68
        sta $EA                           ; $FC6B  85 EA
        inx                               ; $FC6D  E8
        bne L_FC5C                        ; $FC6E  D0 EC
L_FC70:
        pla                               ; $FC70  68
        txa                               ; $FC71  8A
        jsr L_FC92                        ; $FC72  20 92 FC
        ldx #$00                          ; $FC75  A2 00
L_FC77:
        lda $EA                           ; $FC77  A5 EA
        sec                               ; $FC79  38
        sbc #$28                          ; $FC7A  E9 28
        pha                               ; $FC7C  48
        lda $EB                           ; $FC7D  A5 EB
        sbc #$00                          ; $FC7F  E9 00
        bcc L_FC8B                        ; $FC81  90 08
        sta $EB                           ; $FC83  85 EB
        pla                               ; $FC85  68
        sta $EA                           ; $FC86  85 EA
        inx                               ; $FC88  E8
        bne L_FC77                        ; $FC89  D0 EC
L_FC8B:
        pla                               ; $FC8B  68
        txa                               ; $FC8C  8A
        jsr L_FC92                        ; $FC8D  20 92 FC
        lda $EA                           ; $FC90  A5 EA
L_FC92:
        beq L_FCAA                        ; $FC92  F0 16
        cmp #$1B                          ; $FC94  C9 1B
        bcc L_FCA1                        ; $FC96  90 09
        cmp #$25                          ; $FC98  C9 25
        bcs L_FCA6                        ; $FC9A  B0 0A
        clc                               ; $FC9C  18
        adc #$15                          ; $FC9D  69 15
        bne L_FCCA                        ; $FC9F  D0 29
L_FCA1:
        clc                               ; $FCA1  18
        adc #$40                          ; $FCA2  69 40
        bne L_FCCA                        ; $FCA4  D0 24
L_FCA6:
        lda #$3F                          ; $FCA6  A9 3F
        bne L_FCCA                        ; $FCA8  D0 20
L_FCAA:
        lda #$20                          ; $FCAA  A9 20
        bne L_FCCA                        ; $FCAC  D0 1C
L_FCAE:
        pha                               ; $FCAE  48
        lsr a                             ; $FCAF  4A
        lsr a                             ; $FCB0  4A
        lsr a                             ; $FCB1  4A
        lsr a                             ; $FCB2  4A
        jsr L_FCB9                        ; $FCB3  20 B9 FC
        pla                               ; $FCB6  68
        and #$0F                          ; $FCB7  29 0F
L_FCB9:
        cmp #$0A                          ; $FCB9  C9 0A
        bcc L_FCBF                        ; $FCBB  90 02
        adc #$06                          ; $FCBD  69 06
L_FCBF:
        adc #$30                          ; $FCBF  69 30
        bne L_FCCA                        ; $FCC1  D0 07
L_FCC3:
        lda #$0D                          ; $FCC3  A9 0D
        jsr L_FCCA                        ; $FCC5  20 CA FC
        lda #$0A                          ; $FCC8  A9 0A
L_FCCA:
        phx                               ; $FCCA  DA
        phy                               ; $FCCB  5A
        pha                               ; $FCCC  48
        jsr OUTCH                         ; $FCCD  20 C7 E0
        pla                               ; $FCD0  68
        ply                               ; $FCD1  7A
        plx                               ; $FCD2  FA
        rts                               ; $FCD3  60
D_FCD4:
        .byte "NO SYMBOL TABLE", $0D      ; $FCD4
        .byte $0A,$00                     ; $FCE4
D_FCE6:
        .byte "SYMBOL VALUE   S"          ; $FCE6
        .byte "YMBOL VALUE   SY"          ; $FCF6
        .byte "MBOL VALUE   SYM"          ; $FD06
        .byte $42,$4F,$4C,$20,$56,$41,$4C,$55,$45,$0D,$0A,$2D,$2D,$2D,$2D,$2D; $FD16
        .byte "- -----   ------"          ; $FD26
        .byte " -----   ------ "          ; $FD36
        .byte "-----   ------ -"          ; $FD46
        .byte $2D,$2D,$2D,$2D,$0D,$0A,$00,$FF,$FF,$FF; $FD56

; EXTCMD - MS, ML, MR, DE; anything else goes to DOSX at $D000
EXTCMD:
        ldy #$00                          ; $FD60  A0 00
        lda (INBUF),y                     ; $FD62  B1 E1
        jsr UCASE                         ; $FD64  20 0F F0
        cmp #$44                          ; $FD67  C9 44
        bne L_FD78                        ; $FD69  D0 0D
        iny                               ; $FD6B  C8
        lda (INBUF),y                     ; $FD6C  B1 E1
        jsr UCASE                         ; $FD6E  20 0F F0
        cmp #$45                          ; $FD71  C9 45
        bne L_FD94                        ; $FD73  D0 1F
        jmp CMD_DE                        ; $FD75  4C B9 FF
L_FD78:
        cmp #$4D                          ; $FD78  C9 4D
        bne L_FD94                        ; $FD7A  D0 18
        iny                               ; $FD7C  C8
        lda (INBUF),y                     ; $FD7D  B1 E1
        jsr UCASE                         ; $FD7F  20 0F F0
        cmp #$53                          ; $FD82  C9 53
        beq CMD_MS                        ; $FD84  F0 13
        ldx #$00                          ; $FD86  A2 00
        cmp #$4C                          ; $FD88  C9 4C
        beq L_FD91                        ; $FD8A  F0 05
        inx                               ; $FD8C  E8
        cmp #$52                          ; $FD8D  C9 52
        bne L_FD94                        ; $FD8F  D0 03
L_FD91:
        jmp CMD_ML                        ; $FD91  4C 31 FF
L_FD94:
        jmp $D000                         ; $FD94  4C 00 D0
        .byte $EA,$EA                     ; $FD97

; MS ssss eeee name[@xxxx] - save machine code
CMD_MS:
        jsr SKIPAR                        ; $FD99  20 21 E8
        jsr GETHX                         ; $FD9C  20 91 EA
        sta $3543                         ; $FD9F  8D 43 35
        jsr GETHX                         ; $FDA2  20 91 EA
        sta $3542                         ; $FDA5  8D 42 35
        jsr L_FE31                        ; $FDA8  20 31 FE
        jsr GETHX                         ; $FDAB  20 91 EA
        sta $3545                         ; $FDAE  8D 45 35
        jsr GETHX                         ; $FDB1  20 91 EA
        sta $3544                         ; $FDB4  8D 44 35
        jsr L_FE31                        ; $FDB7  20 31 FE
        lda CMDPOS                        ; $FDBA  AD E5 2C
        sta $354F                         ; $FDBD  8D 4F 35
        lda $3542                         ; $FDC0  AD 42 35
        sta $3546                         ; $FDC3  8D 46 35
        lda $3543                         ; $FDC6  AD 43 35
        sta $3547                         ; $FDC9  8D 47 35
        ldy CMDPOS                        ; $FDCC  AC E5 2C
L_FDCF:
        lda (INBUF),y                     ; $FDCF  B1 E1
        cmp #$20                          ; $FDD1  C9 20
        bcc L_FDF6                        ; $FDD3  90 21
        cmp #$40                          ; $FDD5  C9 40
        beq L_FDDC                        ; $FDD7  F0 03
        iny                               ; $FDD9  C8
        bne L_FDCF                        ; $FDDA  D0 F3
L_FDDC:
        lda #$0D                          ; $FDDC  A9 0D
        sta (INBUF),y                     ; $FDDE  91 E1
        iny                               ; $FDE0  C8
        sty CMDPOS                        ; $FDE1  8C E5 2C
        jsr GETHX                         ; $FDE4  20 91 EA
        sta $3547                         ; $FDE7  8D 47 35
        jsr GETHX                         ; $FDEA  20 91 EA
        sta $3546                         ; $FDED  8D 46 35
        lda $354F                         ; $FDF0  AD 4F 35
        sta CMDPOS                        ; $FDF3  8D E5 2C
L_FDF6:
        ldy CMDPOS                        ; $FDF6  AC E5 2C
        lda (INBUF),y                     ; $FDF9  B1 E1
        cmp #$21                          ; $FDFB  C9 21
        bcc L_FD94                        ; $FDFD  90 95
        sec                               ; $FDFF  38
        lda $3544                         ; $FE00  AD 44 35
        sbc $3542                         ; $FE03  ED 42 35
        lda $3545                         ; $FE06  AD 45 35
        sbc $3543                         ; $FE09  ED 43 35
        bcs L_FE11                        ; $FE0C  B0 03
        jmp L_FD94                        ; $FE0E  4C 94 FD
L_FE11:
        clc                               ; $FE11  18
        adc #$01                          ; $FE12  69 01
        sta $3548                         ; $FE14  8D 48 35
        clc                               ; $FE17  18
        adc #$08                          ; $FE18  69 08
        ror a                             ; $FE1A  6A
        lsr a                             ; $FE1B  4A
        lsr a                             ; $FE1C  4A
        sta $3541                         ; $FE1D  8D 41 35
        lda #$01                          ; $FE20  A9 01
        sta $3540                         ; $FE22  8D 40 35
        lda #$39                          ; $FE25  A9 39
        sta MAXTK                         ; $FE27  85 E5
        lda DPAGE                         ; $FE29  AD 5F 26
        sta $19                           ; $FE2C  85 19
        jmp PUCONT                        ; $FE2E  4C 92 F2
L_FE31:
        ldy CMDPOS                        ; $FE31  AC E5 2C
        cpy CMDLEN                        ; $FE34  CC ED 2C
        beq L_FE44                        ; $FE37  F0 0B
        lda (INBUF),y                     ; $FE39  B1 E1
        cmp #$20                          ; $FE3B  C9 20
        bne L_FE44                        ; $FE3D  D0 05
        inc CMDPOS                        ; $FE3F  EE E5 2C
        bne L_FE31                        ; $FE42  D0 ED
L_FE44:
        rts                               ; $FE44  60
L_FE45:
        lda $3540                         ; $FE45  AD 40 35
        beq L_FE4E                        ; $FE48  F0 04
        lda $3541                         ; $FE4A  AD 41 35
        rts                               ; $FE4D  60
L_FE4E:
        lda WSTRK                         ; $FE4E  AD 7D 3A
        rts                               ; $FE51  60

; PUENT - PU entry (clears the MS flag)
PUENT:
        lda #$00                          ; $FE52  A9 00
        sta $3540                         ; $FE54  8D 40 35
        jmp PUGO                          ; $FE57  4C 70 F2
L_FE5A:
        ldx $3540                         ; $FE5A  AE 40 35
        bne L_FE62                        ; $FE5D  D0 03
        jmp PUWRT                         ; $FE5F  4C B6 F3
L_FE62:
        ldx #$00                          ; $FE62  A2 00
        stx $3540                         ; $FE64  8E 40 35
        sta $354A                         ; $FE67  8D 4A 35
        jsr SEEK                          ; $FE6A  20 35 E4
        lda #$4D                          ; $FE6D  A9 4D
        sta DIRBUF1                       ; $FE6F  8D 00 33
        lda #$43                          ; $FE72  A9 43
        sta $3301                         ; $FE74  8D 01 33
        ldx #$00                          ; $FE77  A2 00
L_FE79:
        lda $3542,x                       ; $FE79  BD 42 35
        sta $3302,x                       ; $FE7C  9D 02 33
        inx                               ; $FE7F  E8
        cpx #$07                          ; $FE80  E0 07
        bne L_FE79                        ; $FE82  D0 F5
        lda #$00                          ; $FE84  A9 00
        sta MEMLO                         ; $FE86  85 FE
        lda #$33                          ; $FE88  A9 33
        sta MEMHI                         ; $FE8A  85 FF
        lda #$01                          ; $FE8C  A9 01
        sta $354D                         ; $FE8E  8D 4D 35
        jsr L_FEDF                        ; $FE91  20 DF FE
        lda $3548                         ; $FE94  AD 48 35
        sta $3549                         ; $FE97  8D 49 35
        lda $3542                         ; $FE9A  AD 42 35
        sta $354B                         ; $FE9D  8D 4B 35
        lda $3543                         ; $FEA0  AD 43 35
        sta $354C                         ; $FEA3  8D 4C 35
        lda #$02                          ; $FEA6  A9 02
        sta $354D                         ; $FEA8  8D 4D 35
        lda #$07                          ; $FEAB  A9 07
        sta $354E                         ; $FEAD  8D 4E 35
L_FEB0:
        lda $354B                         ; $FEB0  AD 4B 35
        sta MEMLO                         ; $FEB3  85 FE
        lda $354C                         ; $FEB5  AD 4C 35
        sta MEMHI                         ; $FEB8  85 FF
        lda $3549                         ; $FEBA  AD 49 35
        cmp $354E                         ; $FEBD  CD 4E 35
        bcc L_FEC5                        ; $FEC0  90 03
        lda $354E                         ; $FEC2  AD 4E 35
L_FEC5:
        pha                               ; $FEC5  48
        jsr L_FEDF                        ; $FEC6  20 DF FE
        pla                               ; $FEC9  68
        jsr L_FF0A                        ; $FECA  20 0A FF
        beq L_FED9                        ; $FECD  F0 0A
        jsr L_FF1D                        ; $FECF  20 1D FF
        lda #$08                          ; $FED2  A9 08
        sta $354E                         ; $FED4  8D 4E 35
        bne L_FEB0                        ; $FED7  D0 D7
L_FED9:
        lda $19                           ; $FED9  A5 19
        sta DPAGE                         ; $FEDB  8D 5F 26
        rts                               ; $FEDE  60
L_FEDF:
        sta DPAGE                         ; $FEDF  8D 5F 26
        lda $354D                         ; $FEE2  AD 4D 35
        sta DSECT                         ; $FEE5  8D 5E 26
        jsr HLOAD                         ; $FEE8  20 CD E4
        jsr WRSEC                         ; $FEEB  20 5A E5
        jmp HUNLD                         ; $FEEE  4C DA E4
DSKFIX2:
        sta BASPTRL                       ; $FEF1  8D 5A 30
        lda #$2E                          ; $FEF4  A9 2E
        sta BASPTRH                       ; $FEF6  8D 5B 30
        jmp SWAPZP                        ; $FEF9  4C 5A EA
        .byte $A5,$F4                     ; $FEFC
L_FEFE:
        sta DSECT                         ; $FEFE  8D 5E 26
        jsr HLOAD                         ; $FF01  20 CD E4
        jsr RDSECP                        ; $FF04  20 24 F0
        jmp HUNLD                         ; $FF07  4C DA E4
L_FF0A:
        pha                               ; $FF0A  48
        clc                               ; $FF0B  18
        adc $354C                         ; $FF0C  6D 4C 35
        sta $354C                         ; $FF0F  8D 4C 35
        pla                               ; $FF12  68
        eor #$FF                          ; $FF13  49 FF
        sec                               ; $FF15  38
        adc $3549                         ; $FF16  6D 49 35
        sta $3549                         ; $FF19  8D 49 35
        rts                               ; $FF1C  60
L_FF1D:
        sed                               ; $FF1D  F8
        lda $354A                         ; $FF1E  AD 4A 35
        clc                               ; $FF21  18
        adc #$01                          ; $FF22  69 01
        cld                               ; $FF24  D8
        sta $354A                         ; $FF25  8D 4A 35
        jsr SEEK                          ; $FF28  20 35 E4
        lda #$01                          ; $FF2B  A9 01
        sta $354D                         ; $FF2D  8D 4D 35
        rts                               ; $FF30  60

; ML name / MR name - load (and run) machine code
CMD_ML:
        stx $354F                         ; $FF31  8E 4F 35
        jsr L_F0D2                        ; $FF34  20 D2 F0
        ldy #$0E                          ; $FF37  A0 0E
        lda (ENTPL),y                     ; $FF39  B1 10
        sta $354A                         ; $FF3B  8D 4A 35
        jsr SEEK                          ; $FF3E  20 35 E4
        lda #$00                          ; $FF41  A9 00
        sta MEMLO                         ; $FF43  85 FE
        lda #$33                          ; $FF45  A9 33
        sta MEMHI                         ; $FF47  85 FF
        lda #$01                          ; $FF49  A9 01
        jsr L_FEFE                        ; $FF4B  20 FE FE
        lda DIRBUF1                       ; $FF4E  AD 00 33
        cmp #$4D                          ; $FF51  C9 4D
        bne L_FFB4                        ; $FF53  D0 5F
        lda $3301                         ; $FF55  AD 01 33
        cmp #$43                          ; $FF58  C9 43
        bne L_FFB4                        ; $FF5A  D0 58
        ldx #$00                          ; $FF5C  A2 00
L_FF5E:
        lda $3302,x                       ; $FF5E  BD 02 33
        sta $3542,x                       ; $FF61  9D 42 35
        inx                               ; $FF64  E8
        cpx #$07                          ; $FF65  E0 07
        bne L_FF5E                        ; $FF67  D0 F5
        lda $3548                         ; $FF69  AD 48 35
        sta $3549                         ; $FF6C  8D 49 35
        lda $3542                         ; $FF6F  AD 42 35
        sta $354B                         ; $FF72  8D 4B 35
        lda $3543                         ; $FF75  AD 43 35
        sta $354C                         ; $FF78  8D 4C 35
        lda #$02                          ; $FF7B  A9 02
        sta $354D                         ; $FF7D  8D 4D 35
L_FF80:
        lda $354B                         ; $FF80  AD 4B 35
        sta MEMLO                         ; $FF83  85 FE
        lda $354C                         ; $FF85  AD 4C 35
        sta MEMHI                         ; $FF88  85 FF
        lda $354D                         ; $FF8A  AD 4D 35
        jsr L_FEFE                        ; $FF8D  20 FE FE
        lda $3549                         ; $FF90  AD 49 35
        cmp DPAGE                         ; $FF93  CD 5F 26
        bcc L_FFA6                        ; $FF96  90 0E
        lda DPAGE                         ; $FF98  AD 5F 26
        jsr L_FF0A                        ; $FF9B  20 0A FF
        beq L_FFA6                        ; $FF9E  F0 06
        jsr L_FF1D                        ; $FFA0  20 1D FF
        jmp L_FF80                        ; $FFA3  4C 80 FF
L_FFA6:
        lda $19                           ; $FFA6  A5 19
        sta DPAGE                         ; $FFA8  8D 5F 26
        lda $354F                         ; $FFAB  AD 4F 35
        beq L_FFB3                        ; $FFAE  F0 03
        jmp ($3546)                       ; $FFB0  6C 46 35
L_FFB3:
        rts                               ; $FFB3  60
L_FFB4:
        lda #$0D                          ; $FFB4  A9 0D
        jmp ERROR                         ; $FFB6  4C C8 E7

; DE name - delete a file (asks SURE?)
CMD_DE:
        jsr L_F0D2                        ; $FFB9  20 D2 F0
        jsr PRINT                         ; $FFBC  20 D6 EA
        .byte "SURE? ", $00               ; $FFBF
        jsr GETKEY                        ; $FFC6  20 C4 E0
        jsr UCASE                         ; $FFC9  20 0F F0
        pha                               ; $FFCC  48
        jsr CRLF                          ; $FFCD  20 CD EA
        pla                               ; $FFD0  68
        cmp #$59                          ; $FFD1  C9 59
        bne L_FFF7                        ; $FFD3  D0 22
        jsr L_F0F2                        ; $FFD5  20 F2 F0
        stx MEMHI                         ; $FFD8  86 FF
        ldy #$0D                          ; $FFDA  A0 0D
        lda #$23                          ; $FFDC  A9 23
L_FFDE:
        sta (ENTPL),y                     ; $FFDE  91 10
        dey                               ; $FFE0  88
        bpl L_FFDE                        ; $FFE1  10 FB
        iny                               ; $FFE3  C8
        sty MEMLO                         ; $FFE4  84 FE
        txa                               ; $FFE6  8A
        sec                               ; $FFE7  38
        sbc #$32                          ; $FFE8  E9 32
        sta $354D                         ; $FFEA  8D 4D 35
        lda #$12                          ; $FFED  A9 12
        jsr SEEK                          ; $FFEF  20 35 E4
        lda #$01                          ; $FFF2  A9 01
        jsr L_FEDF                        ; $FFF4  20 DF FE
L_FFF7:
        jmp L_FED9                        ; $FFF7  4C D9 FE

; 6502 VECTORS
        .word $F59D, RESET, $F59D         ; $FFFA
