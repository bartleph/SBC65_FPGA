;************************************************************************
;* SD.S - SD CARD "DISK" DRIVER FOR OS-65D V3.3 ROM DOS     $C100-$CFFF *
;*                                                                      *
;* Replaces the floppy routines. Each old entry point in the DOS now    *
;* starts with a JMP to the matching routine here, so the jump table    *
;* at $E024-$E04E, DOSX and the Forth disk words all work unchanged.    *
;*                                                                      *
;* HARDWARE - 6522 VIA at $9000, port B (bit-banged SPI, mode 0):       *
;*   PB0 CLK   PB1 DI (card MOSI)   PB2 CS    (outputs)                 *
;*   PB7 DO (card MISO)                       (input)                   *
;*   The driver keeps its state in DDRB bits 3-5 (PB3-PB5 are unused   *
;*   pins): bit 3 = card started, bit 4 = SDHC/SDXC (block addresses),  *
;*   bit 5 = v2 card (only during start-up). A reset clears DDRB, so   *
;*   the card is started again on the next disk access. No RAM is used. *
;*                                                                      *
;* CARD LAYOUT (no file system - the card is dedicated to the SBC):     *
;*   block = 2048 + image*3200 + track*80 + (sector-1)*5 + k            *
;*   image = the disk image mounted on the drive (MO command, 0-255;    *
;*   after power-up A-D are images 0-3).                                *
;*   k=0   info block: $A5, track (BCD), sector, pages, rest zero       *
;*   k=1-4 data, two pages per block (an odd last page is padded)       *
;*   Sectors 1-15 per track, 1-8 pages each. A sector exists when its   *
;*   info block is valid. IN (format) clears the 15 info blocks.        *
;*                                                                      *
;* ERRORS: #1 read failed, #2 write failed, #3 track 0 is protected,    *
;*         #6 no card / card start-up failed, #8 bad track number,      *
;*         #A sector not found, #B bad page count.                      *
;*                                                                      *
;* RAM: $35F0-$35F5 mount table (signature $5A,$A5 + image for A-D),   *
;*   in unused DOS RAM above DOSX's variables (TY uses up to $35ED).    *
;*                                                                      *
;* ZERO PAGE (all DOS disk scratch bytes, as the floppy code used):     *
;*   $F0-$F3 card address / command argument                           *
;*   $F6 SPI shift, $F7 $F8 $FD low-level counters                      *
;*   $FA $FB high-level counters (RDSEC/WRSEC/IN), and as before the    *
;*   NXTSEC results SECNO $FB, SECPGS $FA, SECCNT $F9.                  *
;************************************************************************

.if FPGA48
VORB    = $C090             ; VIA port B (FPGA: in the $C0 I/O page)
VDDRB   = $C092
.else
VORB    = $9000             ; VIA port B (SBC)
VDDRB   = $9002
.endif
DDRBASE = $07               ; PB0-PB2 outputs
F_INIT  = $08               ; DDRB: card started
F_HC    = $10               ; DDRB: SDHC/SDXC (block addresses)
F_V2    = $20               ; DDRB: v2 card (during start-up)

ARG     = $F0               ; 4 bytes, big endian
SPT     = $F6
T1      = $F7
T2      = $F8
T3      = $FD
HK      = $FB               ; = SECNO  (high level: data block number)
HP      = $FA               ; = SECPGS (high level: pages still to go)

SEL0    = $00               ; port B: CS low, DI 0, CLK 0
SEL1    = $02               ;         CS low, DI 1, CLK 0
SEL1C   = $03               ;         CS low, DI 1, CLK 1
IDLE    = $06               ;         CS high, DI 1, CLK 0
IDLEC   = $07               ;         CS high, DI 1, CLK 1

INFOMAG = $A5
MSIG    = $35F0             ; 2 bytes: $5A $A5 when MNT is valid
MNT     = $35F2             ; 4 bytes: image number for drives A-D

; ======================================================================
; Entry points (reached through the JMPs patched into the DOS)
; ======================================================================

; HLOAD / HUNLD / STEPIN / STEPOUT: nothing to do. Like the ROM code
; they replace, return X=0, Y=0 and keep A and the carry.
SD_HEAD:
SD_STEP:
        ldx #0
        ldy #0
        rts

; HOME: track 0
SD_HOME:
        ldx #0
        ldy #0
        stx CURTRK
        rts

; SELDRV: remember the drive (1-4). C=0.
SD_SELDRV:
        sta DRIVE
        clc
        rts

; RDYCHK: C=0 if the card is ready (starting it if needed)
SD_RDYCHK:
        jmp SDREADY

; SEEK: track A (BCD). ERR #8 if not 00-39, ERR #6 if no card. Y=0.
SD_SEEK:
        sta SECPGS
        and #$0F
        cmp #$0A
        bcs @bad
        lda SECPGS
        cmp #$40
        bcs @bad
        jsr SDREADY
        bcs @nrdy
        lda SECPGS
        sta CURTRK
        ldy #0
        rts
@bad:   lda #$08
        jmp SDERR
@nrdy:  lda #$06
        jmp SDERR

; FINDHDR: card ready, and for DSECT > 1 sector DSECT-1 must exist.
; (Callers then step through the sectors with NXTSEC and SECCNT.)
SD_FINDHDR:
        jsr NEEDCARD
        lda DSECT
        cmp #2
        bcc @ok
        sbc #1
        jsr RDINFO
        bcc @ok
        lda #$0A
        jmp SDERR
@ok:    rts

; NXTSEC: the sector after SECCNT. C=1 found: SECNO, SECPGS, SECCNT+1.
;         C=0 no more sectors on this track. Keeps Y.
SD_NXTSEC:
        lda SECCNT
        cmp #15
        bcs @none
        adc #1
        jsr RDINFO
        bcs @none
        lda ARG+2
        sta SECNO
        lda ARG+3
        sta SECPGS
        inc SECCNT
        sec
        rts
@none:  clc
        rts

; RDSEC: read sector DSECT to (MEMLO). DPAGE = its page count,
; MEMHI ends DPAGE pages higher, X=0, Y=0, C=1.
; The cold start reads a sector into page 0 itself, so while data is
; arriving nothing here may live in zero page: the pages-to-go count and
; the block number are kept on the stack.
SD_RDSEC:
        jsr NEEDCARD
        lda DSECT
        jsr RDINFO
        bcc @found
        lda #$0A
        jmp SDERR
@found: lda ARG+3
        sta DPAGE
        pha                 ; $0102,x after TSX: pages still to read
        lda #1
        pha                 ; $0101,x: data block number
        ldy #0
@blk:   tsx
        lda $0101,x
        tax
        lda DSECT
        jsr SDLBA
        tsx
        lda $0102,x
        cmp #2
        bcc @one
        lda #2
@one:   jsr SDRDX
        bcs @err
        tsx
        inc $0101,x
        lda $0102,x
        sec
        sbc #2
        bcs @left
        lda #0
@left:  sta $0102,x
        bne @blk
        pla
        pla
        ldx #0
        ldy #0
        sec
        rts
@err:   pla
        pla
        lda #$01
        jmp SDERR

; WRSEC: write DPAGE pages from (MEMLO) as sector DSECT.
; ERR #B if DPAGE is 0 or more than 8. Track 0 is left alone (as the
; floppy code did). MEMHI ends DPAGE pages higher, X=0, Y=0, C=1.
SD_WRSEC:
        lda DPAGE
        beq @badp
        cmp #9
        bcs @badp
        lda CURTRK
        bne @go
        rts
@badp:  lda #$0B
        jmp SDERR
@go:    jsr NEEDCARD
        lda DSECT           ; sectors 1-15 only
        beq @nosec
        cmp #16
        bcs @nosec
        cmp #2              ; sector N needs sector N-1 to exist
        bcc @info
        sbc #1
        jsr RDINFO
        bcc @info
@nosec: lda #$0A
        jmp SDERR
@info:  lda DSECT
        ldx #0
        jsr SDLBA
        lda #3              ; write the info block
        jsr SDWRX
        bcs @err
        lda DPAGE
        sta HP
        lda #1
        sta HK
        ldy #0
@blk:   lda DSECT
        ldx HK
        jsr SDLBA
        jsr TWOMAX
        pha
        jsr SDWRX
        pla
        bcs @err
        inc HK
        jsr HPSUB
        bne @blk
        ldx #0
        ldy #0
        sec
        rts
@err:   lda #$02
        jmp SDERR

; INITTRK: format the current track = clear its 15 info blocks.
SD_INITTRK:
        lda CURTRK
        bne @go
        lda #$03
        jmp SDERR
@go:    jsr NEEDCARD
        lda #1
        sta HK
@l:     lda HK
        ldx #0
        jsr SDLBA
        lda #0              ; write a block of zeros
        jsr SDWRX
        bcs @err
        inc HK
        lda HK
        cmp #16
        bcc @l
        ldx #0
        ldy #0
        rts
@err:   lda #$02
        jmp SDERR

; RDTRK (EX command): rebuild the track as the floppy stored it, at
; (MEMLO): "CW" track "X", then per sector $76 sector pages data "GS".
SD_RDTRK:
        jsr NEEDCARD
        ldy #0
        lda #$43
        jsr PUTM
        lda #$57
        jsr PUTM
        lda CURTRK
        jsr PUTM
        lda #$58
        jsr PUTM
        lda #0
        sta SECCNT
@sec:   jsr SD_NXTSEC       ; SECNO = sector, SECPGS (=HP) = pages
        bcc @end
        lda #$76
        jsr PUTM
        lda SECNO
        jsr PUTM
        lda SECPGS
        jsr PUTM
        lda #1
        sta DPAGE           ; DPAGE = data block number here
@blk:   lda SECNO
        ldx DPAGE
        jsr SDLBA
        jsr TWOMAX
        pha
        jsr SDRDX
        pla
        bcs @rerr
        jsr HPSUB
        php
        inc DPAGE
        plp
        bne @blk
        lda #$47
        jsr PUTM
        lda #$53
        jsr PUTM
        jmp @sec
@end:   rts
@rerr:  lda #$01
        jmp SDERR

; SDDISP: commands the ROM table doesn't know arrive here (BADCMD).
; MO is handled here, DA in DIS.S; anything else carries on to CHKSY (SY, then DOSX)
; with X and Y as they were.
SDDISP: phx
        phy
        ldy #0
        lda (INBUF),y
        jsr UCASE
        cmp #'M'
        bne @no
        iny
        lda (INBUF),y
        jsr UCASE
        cmp #'O'
        bne @no
        ply
        plx
        lda #>(MOCMD-1)
        pha
        lda #<(MOCMD-1)
        pha
        jmp SKIPAR          ; its RTS enters MOCMD
@no:    ply
        plx
        jmp DADISP          ; DA (DIS.S), ELSE ON TO CHKSY

; MO [d n] - mount disk image n (0-255) on drive d (A-D).
;            MO on its own lists the mounts.  e.g.  MO B 12
MOCMD:  jsr MNTINIT
        jsr MOSKIP
        cmp #$0D
        beq @list
        jsr UCASE
        sec
        sbc #'A'
        cmp #4
        bcs @syn
        pha                 ; drive 0-3
        inc CMDPOS
        jsr MOSKIP
        lda #0
        sta T1              ; value
        ldx #0              ; digit count
@dig:   ldy CMDPOS
        lda (INBUF),y
        cmp #'0'
        bcc @end
        cmp #'9'+1
        bcs @end
        and #$0F
        sta T2
        lda T1
        cmp #26
        bcs @syn2           ; would pass 255
        asl a
        sta T3
        asl a
        asl a
        adc T3              ; * 10
        adc T2
        bcs @syn2
        sta T1
        inc CMDPOS
        inx
        bne @dig
@end:   cpx #0
        beq @syn2
        pla
        tax
        lda T1
        sta MNT,x
@list:  jsr CRLF
        ldx #0
@l:     txa
        clc
        adc #'A'
        jsr OUTCH
        lda #'='
        jsr OUTCH
        lda MNT,x
        jsr PRDEC3
        lda #' '
        jsr OUTCH
        inx
        cpx #4
        bne @l
        rts
@syn2:  pla
@syn:   lda #$07
        jmp ERROR

; skip spaces on the command line; A = next char (not consumed)
MOSKIP: ldy CMDPOS
        lda (INBUF),y
        cmp #' '
        bne @r
        inc CMDPOS
        bne MOSKIP
@r:     rts

; print A as 3 decimal digits (keeps X)
PRDEC3: ldy #'0'-1
        sec
@h:     iny
        sbc #100
        bcs @h
        adc #100
        pha
        tya
        jsr OUTCH
        pla
        ldy #'0'-1
        sec
@t:     iny
        sbc #10
        bcs @t
        adc #10
        pha
        tya
        jsr OUTCH
        pla
        ora #'0'
        jmp OUTCH

; ======================================================================
; Helpers
; ======================================================================

; A = min(HP, 2): pages for the next block
TWOMAX: lda HP
        cmp #2
        bcc @r
        lda #2
@r:     rts

; HP -= A (A = pages just done). Z=1 when none are left.
HPSUB:  eor #$FF
        sec
        adc HP
        sta HP
        rts

; store A at (MEMLO),Y and move on (next page after 256 bytes)
PUTM:   sta (MEMLO),y
        iny
        bne @r
        inc MEMHI
@r:     rts

; error exit: deselect the card, then the DOS error handler
SDERR:  pha
        lda #IDLE
        sta VORB
        pla
        jmp ERROR

; NEEDCARD: SDREADY, ERR #6 if there is no usable card
NEEDCARD:
        jsr SDREADY
        bcs @no
        rts
@no:    lda #$06
        jmp SDERR

; SDREADY: C=0 if the card is started (start it now if not)
SDREADY:
        lda VDDRB
        and #F_INIT
        bne @ok
        jmp SDINIT
@ok:    clc
        rts

; RDINFO: read the info block of sector A (1-15) on the current track.
; C=0 and ARG = $A5, track, sector, pages if it is a valid sector.
; Keeps Y.
RDINFO: cmp #1              ; sectors 1-15 only
        bcc @bad
        cmp #16
        bcc @go
@bad:   sec
        rts
@go:    pha
        ldx #0
        jsr SDLBA
        lda #0              ; first 4 bytes to ARG
        jsr SDRDX
        pla
        bcs @no
        cmp ARG+2
        bne @no
        lda ARG
        cmp #INFOMAG
        bne @no
        lda ARG+1
        cmp CURTRK
        bne @no
        lda ARG+3
        beq @no
        cmp #9
        bcs @no
        clc
        rts
@no:    sec
        rts

; SDLBA: ARG+1..ARG+3 = block number (24 bit) for sector A, part X
; (0 info, 1-4 data) of the current track and drive, ARG = 0:
;   2048 + image*3200 + track*80 + (A-1)*5 + X
SDLBA:  pha                 ; sector
        txa
        pha                 ; part
        lda #0              ; ARG = 2048 = $00000800
        sta ARG
        sta ARG+1
        sta ARG+3
        lda #$08
        sta ARG+2
        lda #$80            ; T3:T2:T1 = 3200 = $000C80
        sta T1
        lda #$0C
        sta T2
        lda #0
        sta T3
        jsr MNTINIT
        lda DRIVE
        sec
        sbc #1
        and #$03
        tax
        lda MNT,x           ; image number
        sta SPT
@mul:   lsr SPT             ; ARG += image * 3200
        bcc @nob
        clc
        lda ARG+3
        adc T1
        sta ARG+3
        lda ARG+2
        adc T2
        sta ARG+2
        lda ARG+1
        adc T3
        sta ARG+1
@nob:   asl T1
        rol T2
        rol T3
        lda SPT
        bne @mul
        lda CURTRK          ; track BCD -> binary
        lsr a
        lsr a
        lsr a
        lsr a
        sta T1
        asl a
        asl a
        adc T1
        asl a               ; tens * 10
        sta T1
        lda CURTRK
        and #$0F
        adc T1              ; track 0-39
        sta T1
        asl a
        asl a
        adc T1              ; track * 5 (<= 195)
        sta T2
        lda #0
        sta T1
        asl T2              ; * 16 -> T1:T2 = track * 80
        rol T1
        asl T2
        rol T1
        asl T2
        rol T1
        asl T2
        rol T1
        clc
        lda ARG+3
        adc T2
        sta ARG+3
        lda ARG+2
        adc T1
        sta ARG+2
        bcc @t0
        inc ARG+1
@t0:    pla                 ; part
        sta T1
        pla                 ; sector
        sec
        sbc #1
        sta T2
        asl a
        asl a
        adc T2              ; (sector-1)*5
        adc T1              ; + part
        clc
        adc ARG+3
        sta ARG+3
        bcc @r
        inc ARG+2
        bne @r
        inc ARG+1
@r:     rts

; MNTINIT: after power-up (no signature) drives A-D = images 0-3
MNTINIT:
        lda MSIG
        cmp #$5A
        bne @set
        lda MSIG+1
        cmp #$A5
        beq @r
@set:   lda #$5A
        sta MSIG
        lda #$A5
        sta MSIG+1
        lda #0
        sta MNT
        lda #1
        sta MNT+1
        lda #2
        sta MNT+2
        lda #3
        sta MNT+3
@r:     rts

; SDADDR: SDSC cards take a byte address (block * 512)
SDADDR: lda VDDRB
        and #F_HC
        bne @r
        asl ARG+3
        rol ARG+2
        rol ARG+1
        lda ARG+1
        sta ARG
        lda ARG+2
        sta ARG+1
        lda ARG+3
        sta ARG+2
        lda #0
        sta ARG+3
@r:     rts

; ======================================================================
; Block read / write, retried once after restarting the card
; ======================================================================
; SDRDX: read block ARG (ARG = 0, block number in ARG+1..ARG+3).
;        A = 0: the first 4 bytes go to ARG
;        A = 1 or 2: that many pages go to (MEMLO),Y through PUTM
;        C=1 on failure.
SDRDX:  pha
        lda ARG+1
        pha
        lda ARG+2
        pha
        lda ARG+3
        pha
        tsx
        lda $0104,x
        jsr SDRD
        bcc @done
        jsr RESTART
        bcs @done
        pla
        sta ARG+3
        pla
        sta ARG+2
        pla
        sta ARG+1
        lda #0
        sta ARG
        pla
        jmp SDRD
@done:  pla
        pla
        pla
        pla
        rts

; SDWRX: write block ARG. A = 0 zeros, 1 one page + zeros, 2 two pages
;        (from (MEMLO),Y), 3 info block (DSECT, DPAGE). C=1 on failure.
SDWRX:  pha
        lda ARG+1
        pha
        lda ARG+2
        pha
        lda ARG+3
        pha
        tsx
        lda $0104,x
        jsr SDWR
        bcc @done
        jsr RESTART
        bcs @done
        pla
        sta ARG+3
        pla
        sta ARG+2
        pla
        sta ARG+1
        lda #0
        sta ARG
        pla
        jmp SDWR
@done:  pla
        pla
        pla
        pla
        rts

; RESTART: forget the card and start it again. C=0 ok.
RESTART:
        lda #DDRBASE
        sta VDDRB
        jmp SDINIT

; ----------------------------------------------------------------------
; SDRD: one block read (see SDRDX). The mode stays on the stack, as the
; data may be landing in zero page.
SDRD:   pha                 ; mode: $0101,x after TSX
        jsr SDADDR
        lda #$51            ; CMD17 READ_SINGLE_BLOCK
        ldx #$01
        jsr SDCMD
        bne @fail
        lda #0              ; wait for the data token, 1024 tries
        sta T1
        lda #4
        sta T2
@tok:   jsr SPIR
        cmp #$FE
        beq @data
        dec T1
        bne @tok
        dec T2
        bne @tok
        beq @fail
@data:  tsx
        lda $0101,x
        bne @pages
        jsr SPIR            ; info: 4 bytes to ARG, skip the other 508
        sta ARG
        jsr SPIR
        sta ARG+1
        jsr SPIR
        sta ARG+2
        jsr SPIR
        sta ARG+3
        lda #252
        jsr SKIPN
        lda #0
        jsr SKIPN
        jmp @crc
@pages: jsr RD256
        tsx
        lda $0101,x
        cmp #2
        bne @half
        jsr RD256
        jmp @crc
@half:  lda #0
        jsr SKIPN
@crc:   jsr SPIR
        jsr SPIR
        jsr SDDESEL
        pla
        clc
        rts
@fail:  jsr SDDESEL
        pla
        sec
        rts

; 256 bytes from the card to (MEMLO),Y
; From a page boundary (Y=0, the normal case) the loop ends when Y wraps,
; so it needs no counter in zero page.
RD256:  cpy #0
        bne @cnt
@w:     jsr SPIR
        jsr PUTM
        cpy #0
        bne @w
        rts
@cnt:   lda #0              ; (EX only: not page aligned)
        sta T1
@l:     jsr SPIR
        jsr PUTM
        dec T1
        bne @l
        rts

; skip A bytes (0 = 256)
SKIPN:  pha                 ; count on the stack (0 = 256)
@l:     jsr SPIR
        tsx
        dec $0101,x
        bne @l
        pla
        rts

; ----------------------------------------------------------------------
; SDWR: one block write (see SDWRX).
SDWR:   sta T3
        jsr SDADDR
        lda #$58            ; CMD24 WRITE_BLOCK
        ldx #$01
        jsr SDCMD
        bne @fail
        lda #$FF
        jsr SPIX
        lda #$FE            ; data token
        jsr SPIX
        lda T3
        beq @z512
        cmp #3
        beq @info
        jsr WR256
        lda T3
        cmp #2
        bne @z256
        jsr WR256
        jmp @end
@z512:  lda #0
        jsr WRZ
@z256:  lda #0
        jsr WRZ
        jmp @end
@info:  lda #INFOMAG
        jsr SPIX
        lda CURTRK
        jsr SPIX
        lda DSECT
        jsr SPIX
        lda DPAGE
        jsr SPIX
        lda #252
        jsr WRZ
        lda #0
        jsr WRZ
@end:   lda #$FF            ; CRC (not checked in SPI mode)
        jsr SPIX
        lda #$FF
        jsr SPIX
        jsr SPIR            ; data response: xxx00101 = accepted
        and #$1F
        cmp #$05
        bne @fail
        lda #0              ; wait while the card is busy (DO low)
        sta T1
        sta T2
@busy:  jsr SPIR
        bne @ok
        dec T1
        bne @busy
        dec T2
        bne @busy
        beq @fail
@ok:    jsr SDDESEL
        clc
        rts
@fail:  jsr SDDESEL
        sec
        rts

; 256 bytes from (MEMLO),Y to the card
WR256:  lda #0
        sta T1
@l:     lda (MEMLO),y
        jsr SPIX
        iny
        bne @n
        inc MEMHI
@n:     dec T1
        bne @l
        rts

; A zero bytes (0 = 256)
WRZ:    sta T1
@l:     lda #0
        jsr SPIX
        dec T1
        bne @l
        rts

; ======================================================================
; Card start-up: CMD0, CMD8, ACMD41, CMD58 / CMD16. C=0 ok.
; Uses T1-T3 and ARG. Keeps Y.
; ======================================================================
SDINIT: lda #IDLE
        sta VORB
        lda #DDRBASE
        sta VDDRB
        ldx #80             ; 80 clocks with CS high
@clk:   lda #IDLEC
        sta VORB
        lda #IDLE
        sta VORB
        dex
        bne @clk
        lda #10             ; CMD0 GO_IDLE_STATE until R1 = $01
        sta T3
@c0:    jsr ARG0
        lda #$40
        ldx #$95
        jsr SDCMD
        php
        jsr SDDESEL
        plp
        cmp #$01
        beq @c8
        dec T3
        bne @c0
        jmp @fail
@c8:    jsr ARG0            ; CMD8 SEND_IF_COND $1AA
        lda #$01
        sta ARG+2
        lda #$AA
        sta ARG+3
        lda #$48
        ldx #$87
        jsr SDCMD
        cmp #$01
        bne @v1
        jsr SPIR            ; R7: 4 more bytes, the last echoes $AA
        jsr SPIR
        jsr SPIR
        jsr SPIR
        cmp #$AA
        bne @v1
        lda #DDRBASE|F_V2
        sta VDDRB
@v1:    jsr SDDESEL
        lda #0              ; ACMD41 until ready, 256 tries (~1.5 s)
        sta T3
@a41:   jsr ARG0
        lda #$77            ; CMD55 APP_CMD
        ldx #$01
        jsr SDCMD
        jsr SDDESEL
        jsr ARG0
        lda VDDRB
        and #F_V2
        beq @a1
        lda #$40            ; HCS: we take high-capacity cards
        sta ARG
@a1:    lda #$69            ; ACMD41 SD_SEND_OP_COND
        ldx #$01
        jsr SDCMD
        php
        jsr SDDESEL
        plp
        beq @rdy
        dec T3
        bne @a41
        jmp @fail
@rdy:   lda VDDRB
        and #F_V2
        beq @sc
        jsr ARG0            ; CMD58 READ_OCR: CCS bit = SDHC
        lda #$7A
        ldx #$01
        jsr SDCMD
        bne @fail2
        jsr SPIR
        sta T1
        jsr SPIR
        jsr SPIR
        jsr SPIR
        jsr SDDESEL
        lda T1
        and #$40
        beq @sc
        lda #DDRBASE|F_INIT|F_HC
        sta VDDRB
        clc
        rts
@sc:    jsr ARG0            ; CMD16 SET_BLOCKLEN 512 (SDSC)
        lda #$02
        sta ARG+2
        lda #$50
        ldx #$01
        jsr SDCMD
        php
        jsr SDDESEL
        plp
        bne @fail
        lda #DDRBASE|F_INIT
        sta VDDRB
        clc
        rts
@fail2: jsr SDDESEL
@fail:  lda #DDRBASE
        sta VDDRB
        sec
        rts

ARG0:   lda #0
        sta ARG
        sta ARG+1
        sta ARG+2
        sta ARG+3
        rts

; ======================================================================
; SPI
; ======================================================================
; SDCMD: send command A ($40+n), argument ARG, CRC X. Card left
; selected. A = R1 response ($FF if none), flags set from A. Keeps Y.
SDCMD:  stx T2
        pha
        lda #$FF
        jsr SPIX
        pla
        jsr SPIX
        lda ARG
        jsr SPIX
        lda ARG+1
        jsr SPIX
        lda ARG+2
        jsr SPIX
        lda ARG+3
        jsr SPIX
        lda T2
        jsr SPIX
        lda #16
        sta T2
@w:     jsr SPIR
        bpl @r
        dec T2
        bne @w
@r:     ora #0              ; flags from A
        rts

; SDDESEL: CS high, then 8 clocks. Keeps A and Y.
SDDESEL:
        pha
        ldx #8
@l:     lda #IDLEC
        sta VORB
        lda #IDLE
        sta VORB
        dex
        bne @l
        pla
        rts

; SPIX: send A, return the byte received in A. Uses X.
SPIX:   sta SPT
        ldx #8
@b:     lda #SEL0
        asl SPT             ; next bit out (MSB first), bit 0 now clear
        bcc @z
        lda #SEL1
@z:     sta VORB            ; data out, CLK low
        ora #$01
        sta VORB            ; CLK high: card samples DI
        lda VORB
        bpl @n              ; DO (PB7) into bit 0
        inc SPT
@n:     dex
        bne @b
        lda #SEL1
        sta VORB            ; CLK low, DI idle high
        lda SPT
        rts

; SPIR: receive a byte (sending $FF). A = byte, flags set. Uses X.
SPIR:   lda #$01            ; byte builds on the stack (no zero page: the
        pha                 ; data may be going to page 0); the 1 is a
@b:     lda #SEL1C          ; marker that drops out after 8 bits
        sta VORB            ; CLK high
        lda VORB
        asl a               ; C = DO
        tsx
        rol $0101,x
        lda #SEL1
        sta VORB            ; CLK low (C unchanged)
        bcc @b
        pla
        rts

; ----------------------------------------------------------------------
; W_TYPET - Forth primitive used by LIST: TYPE without trailing spaces.
; ( addr n -- ), n < 256. A listed line is "nn " + 64 characters, which
; is wider than the 64-column screen: printing the padding made every
; line wrap and left a blank line between them.
W_TYPET:
        lda $00,x           ; n
        sta $26
        lda $02,x           ; addr
        sta $24
        lda $03,x
        sta $25
@t:     ldy $26
        beq @go
        dey
        lda ($24),y
        cmp #$20
        bne @go
        dec $26
        bra @t
@go:    lda $26
        sta $00,x
        jmp W_TYPE

; ----------------------------------------------------------------------
; Forth ROM paging (FPGA). FT and BYE come through here because the switch
; must be made from code outside $A000-$BFFF.
.if FPGA48
FT_GO:  lda #$01
        sta BANKREG         ; Forth ROM in at $A000-$BFFF
        jmp $A000
FT_BYE: stz BANKREG         ; RAM back at $A000-$BFFF
        jmp $E045           ; DOS prompt (as BYE did)
.else
FT_GO   = $A000
FT_BYE  = $E045
.endif
