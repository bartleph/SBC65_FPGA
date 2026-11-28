;*****************************************************************
;* SPACE INVADERS for the SBC65 FPGA (OSI mode, 64 x 32 screen)  *
;*                                                               *
;* Load with HL (Intel HEX), start with GO 4000 at the DOS       *
;* prompt. Uses OSI mode: screen $D000 (64 bytes a row),         *
;* keyboard matrix $DF00 (C1P polarity), OSI character set.      *
;*                                                               *
;* KEYS:  Z = LEFT   X = RIGHT   SPACE = FIRE   ESC = QUIT       *
;*                                                               *
;* Returns to the DOS prompt (RTS) with OSI mode off. Zero page  *
;* $50-$5F is saved and restored.                                *
;*****************************************************************
        .setcpu "65C02"

SCR     = $D000         ; OSI screen, 64 bytes per row
KBD     = $DF00         ; OSI keyboard matrix
BANK    = $C0A0         ; bank latch: bit 1 = OSI mode
ACIAS   = $C080
ACIAD   = $C081
OUTCH   = $E0C7         ; DOS: print A
TYPAHD  = $2325         ; DOS: key caught by the output routine

; ---- screen layout (rows 0-26, so it also fits a 28-row NTSC screen)
ROW_HUD    = 0
ROW_UFO    = 2
ROW_SHIELD = 21
ROW_BASE   = 24
ROW_GROUND = 25
FORMW      = 42         ; 11 invaders, 4 columns apart, 2 wide

; ---- characters
CH_SP   = $20
CH_BASE = $EC
CH_SHOT = $8B
CH_BOMB = $D6
CH_BOOM = $BC
CH_SH0  = $A0           ; shield: full, damaged, nearly gone
CH_SH1  = $BB
CH_SH2  = $B9
CH_UFOL = $E3
CH_UFOR = $E4
CH_GND  = $83

; ---- zero page (saved and restored)
ZPBASE  = $50
ptr     = $50           ; screen pointer
tmp     = $52
tmp2    = $53
tmp3    = $54
rnd     = $55           ; 2 bytes
sptr    = $57           ; string pointer, 2 bytes
ZPSIZE  = 16

        .segment "CODE"
;=================================================================
START:  tsx
        stx savesp
        ldx #ZPSIZE-1           ; save the zero page we use
@zs:    lda ZPBASE,x
        sta zpsave,x
        dex
        bpl @zs
        lda #$02                ; OSI mode on, C1P keyboard polarity
        sta BANK
        lda #$A5
        sta rnd
        lda #$5A
        sta rnd+1
        stz hiscore
        stz hiscore+1

;----------------------------------------------------------------- title
TITLE:  lda #3                  ; show 3 bases on the title screen
        sta lives
        jsr CLS
        jsr DRAWHUD
        jsr PRINTI
        .byte 5, 18, "S P A C E   I N V A D E R S", 0
        jsr PRINTI
        .byte 9, 24, "= ? MYSTERY", 0
        jsr PRINTI
        .byte 11, 24, "= 30 POINTS", 0
        jsr PRINTI
        .byte 13, 24, "= 20 POINTS", 0
        jsr PRINTI
        .byte 15, 24, "= 10 POINTS", 0
        jsr PRINTI
        .byte 19, 8, "Z = LEFT   X = RIGHT   SPACE = FIRE   ESC = QUIT", 0
        jsr PRINTI
        .byte 22, 22, "PRESS SPACE TO PLAY", 0
        lda #9                  ; the score table pictures
        ldx #20
        jsr SETPTR
        lda #CH_UFOL
        sta (ptr)
        ldy #1
        lda #CH_UFOR
        sta (ptr),y
        lda #11
        ldx #20
        jsr SETPTR
        lda #$ED
        sta (ptr)
        lda #$EF
        sta (ptr),y
        lda #13
        ldx #20
        jsr SETPTR
        lda #$11
        sta (ptr)
        lda #$17
        sta (ptr),y
        lda #15
        ldx #20
        jsr SETPTR
        lda #$12
        sta (ptr)
        lda #$16
        sta (ptr),y
@rel:   jsr FRAME               ; wait for SPACE to be let go
        lda kfire
        bne @rel
@wait:  jsr FRAME
        jsr RAND                ; stir the random numbers while waiting
        lda kesc
        beq @nq
        jmp EXIT
@nq:    lda kfire
        beq @wait

;----------------------------------------------------------------- new game
        stz score
        stz score+1
        lda #3
        sta lives
        stz wave
        stz bonus
NEWWAVE:
        inc wave
        jsr CLS
        jsr DRAWHUD
        jsr DRAWSHIELDS
        jsr DRAWGROUND
        ldx #54                 ; all 55 invaders alive
        lda #1
@al:    sta alive,x
        dex
        bpl @al
        lda #55
        sta nalive
        lda #11
        sta fx
        lda wave                ; each wave starts a row lower (to row 9)
        clc
        adc #3
        cmp #10
        bcc @fy
        lda #9
@fy:    sta fy
        lda #1
        sta fdir
        stz anim
        stz invaded
        lda #2
        sta stepcnt
        jsr SETSTEP
        stz sact
        stz bact
        stz bact+1
        stz bact+2
        stz eact
        stz uact
        lda #250
        sta utimer
        lda #40
        sta bombcnt
        stz pdead
        lda #31
        sta px
        jsr DRAWBASE
        jsr DRAWFORM

;----------------------------------------------------------------- main loop
MAIN:   jsr FRAME
        lda kesc
        beq @run
        jmp EXIT
@run:
        jsr PLAYER
        jsr SHOT
        lda pdead               ; everything else waits while the base explodes
        bne @chk
        lda frame
        lsr a
        bcc @nb
        jsr BOMBS               ; bombs move every other frame
@nb:    jsr FORMSTEP
        jsr DROPBOMB
        jsr SAUCER
@chk:   jsr EXPLODE
        lda invaded
        bne GAMEOVER
        lda pdead
        bne MAIN
        lda lives
        beq GAMEOVER
        lda nalive
        bne MAIN
        ldx #50                 ; wave cleared: short pause, next wave
@pw:    jsr FRAME
        dex
        bne @pw
        jmp NEWWAVE

;----------------------------------------------------------------- game over
GAMEOVER:
        lda #10                 ; clear a band for the message
@cb:    pha
        ldx #0
        jsr SETPTR
        ldy #63
        lda #CH_SP
@cc:    sta (ptr),y
        dey
        bpl @cc
        pla
        inc a
        cmp #13
        bne @cb
        jsr PRINTI
        .byte 11, 23, "G A M E   O V E R", 0
        lda score+1             ; new high score?
        cmp hiscore+1
        bcc @nh
        bne @hs
        lda score
        cmp hiscore
        bcc @nh
@hs:    lda score
        sta hiscore
        lda score+1
        sta hiscore+1
        jsr DRAWSCORE
@nh:    ldx #150                ; 3 seconds
@gw:    jsr FRAME
        lda kesc
        bne EXIT
        dex
        bne @gw
        jmp TITLE

;----------------------------------------------------------------- quit
EXIT:   stz BANK                ; OSI mode off
        jsr DRAIN
        stz TYPAHD
        ldx #ZPSIZE-1           ; restore the zero page
@zr:    lda zpsave,x
        sta ZPBASE,x
        dex
        bpl @zr
        lda #$0C                ; clear the terminal screen
        jsr OUTCH
        ldx savesp
        txs
        rts

;=================================================================
; FRAME - wait about 1/50 s, drop typed keys, read the keyboard
;=================================================================
FRAME:  phx
        phy
        ldx #11
        ldy #0
@d:     dey
        bne @d
        dex
        bne @d
        inc frame
        jsr DRAIN
        jsr KEYS
        ply
        plx
        rts

; keys also reach the serial input: throw them away
DRAIN:  lda ACIAS
        lsr a
        bcc @x
        lda ACIAD
        bra DRAIN
@x:     rts

; KEYS - Z, X, SPACE, ESC from the matrix (a 0 selects a row, down = 0)
KEYS:   lda #$FD                ; row 1: bit 5 Z, bit 4 SPACE
        sta KBD
        lda KBD
        eor #$FF
        tax
        and #$20
        sta kleft
        txa
        and #$10
        sta kfire
        lda #$FB                ; row 2: bit 7 X
        sta KBD
        lda KBD
        eor #$FF
        and #$80
        sta kright
        lda #$FE                ; row 0: bit 5 ESC
        sta KBD
        lda KBD
        eor #$FF
        and #$20
        sta kesc
        rts

;=================================================================
; PLAYER - move, fire, or the explosion after being hit
;=================================================================
PLAYER: lda pdead
        beq @alive
        dec pdead
        beq @back
        lda pdead               ; flash
        and #$04
        beq @b1
        lda #CH_BOOM
        bra @b2
@b1:    lda #CH_BASE
@b2:    pha
        lda #ROW_BASE
        ldx px
        jsr SETPTR
        pla
        sta (ptr)
        rts
@back:  lda lives               ; finished: carry on if lives are left
        beq @x
        lda #31
        pha
        jsr ERASEBASE
        pla
        sta px
        jsr DRAWBASE
@x:     rts

@alive: lda frame               ; move every other frame
        lsr a
        bcc @fire
        lda kleft
        beq @nl
        lda px
        cmp #2
        bcc @fire
        dec px
        jsr DRAWBASE
        bra @fire
@nl:    lda kright
        beq @fire
        lda px
        cmp #61
        bcs @fire
        inc px
        jsr DRAWBASE
@fire:  lda kfire
        beq @x2
        lda sact
        bne @x2
        lda #ROW_BASE-1
        sta sy
        lda px
        sta sx
        lda #1
        sta sact
        lda sy
        ldx sx
        jsr SETPTR
        lda (ptr)
        cmp #CH_SP
        bne @x2
        lda #CH_SHOT
        sta (ptr)
@x2:    rts

DRAWBASE:                       ; " ^ " centred on px
        lda #ROW_BASE
        ldx px
        dex
        jsr SETPTR
        lda #CH_SP
        sta (ptr)
        ldy #2
        sta (ptr),y
        dey
        lda #CH_BASE
        sta (ptr),y
        rts

ERASEBASE:
        lda #ROW_BASE
        ldx px
        dex
        jsr SETPTR
        lda #CH_SP
        ldy #2
@e:     sta (ptr),y
        dey
        bpl @e
        rts

;=================================================================
; SHOT - the base's shot moves up one row a frame
;=================================================================
SHOT:   lda sact
        bne @go
        rts
@go:    lda sy                  ; what is at the shot now?
        ldx sx
        jsr SETPTR
        lda (ptr)
        cmp #CH_SHOT
        bne @notme
        lda #CH_SP              ; still our shot: rub it out
        sta (ptr)
        bra @up
@notme: jsr ISINV               ; an invader moved onto it
        bne @up
        jmp HITINV
@up:    dec sy
        lda sy
        cmp #ROW_HUD+2
        bcc ENDSHOT
        ldx sx
        jsr SETPTR
        lda (ptr)
        cmp #CH_SP
        bne @hit
        lda #CH_SHOT
        sta (ptr)
        rts
@hit:   jsr ISINV
        bne @nhi
        jmp HITINV
@nhi:   jsr ISSHIELD
        bne @nsh
        jsr DAMAGE
        bra ENDSHOT
@nsh:   cmp #CH_UFOL
        beq @ufo
        cmp #CH_UFOR
        beq @ufo
        cmp #CH_BOMB            ; shot meets bomb: both go
        bne ENDSHOT
        lda #CH_SP
        sta (ptr)
        ldx #2
@fb:    lda bact,x
        beq @nb
        lda bx,x
        cmp sx
        bne @nb
        lda by,x
        cmp sy
        bne @nb
        stz bact,x
@nb:    dex
        bpl @fb
        bra ENDSHOT
@ufo:   jsr UFOHIT
ENDSHOT:
        stz sact
        rts

; HITINV - the shot (sx, sy) is on an invader character
HITINV: lda sy
        sec
        sbc fy
        bcc ENDSHOT
        cmp #9
        bcs ENDSHOT
        lsr a
        bcs ENDSHOT             ; between the invader rows
        sta tmp3                ; row 0-4
        lda sx
        sec
        sbc fx
        tax
        and #$03
        cmp #2
        bcs ENDSHOT             ; in the gap
        txa
        lsr a
        lsr a
        cmp #11
        bcs ENDSHOT
        sta tmp2                ; column 0-10
        lda tmp3                ; index = row*11 + column
        asl a
        asl a
        asl a
        clc
        adc tmp3
        adc tmp3
        adc tmp3
        adc tmp2
        tax
        lda alive,x
        beq ENDSHOT
        stz alive,x
        dec nalive
        ldx tmp3                ; score for this row
        lda ROWPTS,x
        jsr ADDSCORE
        jsr EXPLODEEND          ; finish any earlier explosion
        lda tmp2                ; explosion where the invader was
        asl a
        asl a
        clc
        adc fx
        sta ex
        lda sy
        sta ey
        ldx ex
        jsr SETPTR
        lda #CH_BOOM
        sta (ptr)
        ldy #1
        sta (ptr),y
        lda #8
        sta etimer
        lda #1
        sta eact
        jsr SETSTEP
        bra ENDSHOT

ROWPTS: .byte $30, $20, $20, $10, $10

; ISINV - Z=1 if A is an invader character
ISINV:  ldx #5
@l:     cmp INVCH,x
        beq @x
        dex
        bpl @l
        ldx #$FF                ; Z=0
@x:     rts
INVCH:  .byte $ED, $EF, $11, $17, $12, $16

; ISSHIELD - Z=1 if A is a shield character
ISSHIELD:
        cmp #CH_SH0
        beq @x
        cmp #CH_SH1
        beq @x
        cmp #CH_SH2
@x:     rts

; DAMAGE - wear away the shield character at (ptr)
DAMAGE: lda (ptr)
        cmp #CH_SH0
        bne @a
        lda #CH_SH1
        bra @w
@a:     cmp #CH_SH1
        bne @b
        lda #CH_SH2
        bra @w
@b:     lda #CH_SP
@w:     sta (ptr)
        rts

;=================================================================
; EXPLODE - clear an invader explosion after a few frames
;=================================================================
EXPLODE:
        lda eact
        beq EXPX
        dec etimer
        bne EXPX
EXPLODEEND:
        lda eact
        beq EXPX
        stz eact
        lda ey
        ldx ex
        jsr SETPTR
        ldy #1
@c:     lda (ptr),y
        cmp #CH_BOOM
        bne @n
        lda #CH_SP
        sta (ptr),y
@n:     dey
        bpl @c
EXPX:   rts

;=================================================================
; FORMSTEP - move the invaders one column, or down a row at an edge
;=================================================================
FORMSTEP:
        dec stepcnt
        beq @go
        rts
@go:    lda stepint
        sta stepcnt
        jsr COLRANGE            ; lc, rc
        lda fdir
        bmi @left
        lda rc                  ; trailing space after the move
        asl a
        asl a
        clc
        adc fx
        adc #3
        cmp #63
        bcs @down
        inc fx
        bra @draw
@left:  lda lc                  ; leading space after the move
        asl a
        asl a
        clc
        adc fx
        cmp #3
        bcc @down
        dec fx
        bra @draw
@down:  inc fy
        lda fdir
        eor #$FE                ; +1 <-> -1
        sta fdir
        jsr CLEARGAPS
        lda rb                  ; landed?
        asl a
        clc
        adc fy
        cmp #ROW_BASE
        bcc @draw
        lda #1
        sta invaded
@draw:  lda anim
        eor #1
        sta anim
        jmp DRAWFORM

; SETSTEP - fewer invaders, faster steps: (alive+3)/4 frames, 8 at most
SETSTEP:
        lda nalive
        clc
        adc #3
        lsr a
        lsr a
        bne @a
        lda #1
@a:     cmp #9
        bcc @b
        lda #8
@b:     sta stepint
        rts

; COLRANGE - lc / rc: first and last columns with an invader,
;            rb: lowest row with an invader
COLRANGE:
        lda #10
        sta lc
        stz rc
        stz rb
        ldx #54
@l:     lda alive,x
        beq @n
        txa                     ; column = x mod 11, row = x / 11
        ldy #0
@m:     cmp #11
        bcc @g
        sbc #11
        iny
        bra @m
@g:     cmp lc
        bcs @g1
        sta lc
@g1:    cmp rc
        bcc @g2
        sta rc
@g2:    cpy rb
        bcc @n
        sty rb
@n:     dex
        bpl @l
        rts

; CLEARGAPS - after a step down, blank the rows the invaders left
CLEARGAPS:
        ldx #0
@r:     phx
        txa
        asl a
        clc
        adc fy
        sec
        sbc #1                  ; row fy-1+2r
        cmp #ROW_GROUND
        bcs @s
        ldx #0
        jsr SETPTR
        ldy #63
        lda #CH_SP
@c:     sta (ptr),y
        dey
        bpl @c
@s:     plx
        inx
        cpx #5
        bne @r
        rts

; DRAWFORM - draw every live invader as "space L R space"
DRAWFORM:
        stz tmp3                ; row 0-4
        ldx #0                  ; invader index
@row:   ldy tmp3                ; characters for this row and frame
        lda ROWTYPE,y
        asl a
        ora anim
        tay
        lda INVL,y
        sta invl
        lda INVR,y
        sta invr
        stz tmp2                ; column 0-10
@col:   lda alive,x
        beq @next
        phx
        lda tmp2
        asl a
        asl a
        clc
        adc fx
        tax
        dex                     ; leading space
        lda tmp3
        asl a
        clc
        adc fy
        jsr SETPTR
        lda #CH_SP
        sta (ptr)
        ldy #3
        sta (ptr),y
        dey
        lda invr
        sta (ptr),y
        dey
        lda invl
        sta (ptr),y
        plx
@next:  inx
        inc tmp2
        lda tmp2
        cmp #11
        bne @col
        inc tmp3
        lda tmp3
        cmp #5
        bne @row
        rts

ROWTYPE: .byte 0, 1, 1, 2, 2
INVL:   .byte $ED, $EF, $11, $17, $12, $16
INVR:   .byte $EF, $ED, $17, $11, $16, $12

;=================================================================
; DROPBOMB - now and then an invader at the bottom of a column drops one
;=================================================================
DROPBOMB:
        dec bombcnt
        beq @go
        rts
@go:    lda wave                ; next drop: 24 frames less 2 a wave (8 min)
        asl a
        sta tmp
        lda #26
        sec
        sbc tmp
        cmp #8
        bcs @t
        lda #8
@t:     sta bombcnt
        ldx #2                  ; a free bomb?
@f:     lda bact,x
        beq @free
        dex
        bpl @f
        rts
@free:  stx tmp2
        ldy #8                  ; pick a column that has invaders
@pick:  jsr RAND
        and #$0F
        cmp #11
        bcs @again
        sta tmp3
        clc                     ; bottom invader in that column
        adc #44
        tax
@up:    lda alive,x
        bne @found
        txa
        sec
        sbc #11
        tax
        bcs @up
@again: dey
        bne @pick
        rts
@found: txa                     ; row = (x - column) / 11
        sec
        sbc tmp3
        ldy #0
@dv:    beq @dd
        sec
        sbc #11
        iny
        bra @dv
@dd:    tya
        asl a
        clc
        adc fy
        inc a                   ; just under it
        ldx tmp2
        sta by,x
        lda tmp3
        asl a
        asl a
        clc
        adc fx
        sta bx,x
        jsr RAND
        and #1
        ldx tmp2
        clc
        adc bx,x
        sta bx,x
        lda #1
        sta bact,x
        rts

;=================================================================
; BOMBS - move the bombs down a row
;=================================================================
BOMBS:  ldx #2
@b:     lda bact,x
        beq @next
        phx
        jsr BOMB1
        plx
@next:  dex
        bpl @b
        rts

BOMB1:  stx tmp2
        lda by,x                ; rub out the old one (if still there)
        pha
        lda bx,x
        tax
        pla
        jsr SETPTR
        lda (ptr)
        cmp #CH_BOMB
        bne @mv
        lda #CH_SP
        sta (ptr)
@mv:    ldx tmp2
        inc by,x
        lda by,x
        cmp #ROW_GROUND
        bcs @gone
        pha
        lda bx,x
        tax
        pla
        jsr SETPTR
        lda (ptr)
        cmp #CH_SP
        bne @hit
        lda #CH_BOMB
        sta (ptr)
        rts
@hit:   jsr ISINV               ; passing an invader: keep falling unseen
        beq @x
        jsr ISSHIELD
        bne @nsh
        jsr DAMAGE
        bra @gone
@nsh:   cmp #CH_BASE
        bne @nbase
        jsr BASEHIT
        bra @gone
@nbase: cmp #CH_SHOT            ; bomb meets shot: both go
        bne @gone
        lda #CH_SP
        sta (ptr)
        stz sact
@gone:  ldx tmp2
        stz bact,x
@x:     rts

; BASEHIT - lose a life
BASEHIT:
        lda pdead
        bne @x
        dec lives
        jsr DRAWLIVES
        lda #60
        sta pdead
        ldx #2                  ; remove the bombs
@b:     lda bact,x
        beq @n
        stz bact,x
        phx
        lda by,x
        pha
        lda bx,x
        tax
        pla
        jsr SETPTR
        lda (ptr)
        cmp #CH_BOMB
        bne @nb
        lda #CH_SP
        sta (ptr)
@nb:    plx
@n:     dex
        bpl @b
@x:     rts

;=================================================================
; SAUCER - crosses the top now and then
;=================================================================
SAUCER: lda uact
        bne @move
        dec utimer
        bne @x
        lda #1
        sta uact
        jsr RAND
        and #1
        beq @fromr
        lda #1
        sta ux
        sta udir
        bra @draw
@fromr: lda #61
        sta ux
        lda #$FF
        sta udir
        bra @draw
@move:  lda frame
        and #3
        bne @x
        lda ux
        clc
        adc udir
        sta ux
        beq @off
        cmp #62
        bcs @off
@draw:  lda #ROW_UFO
        ldx ux
        dex
        jsr SETPTR
        lda #CH_SP
        sta (ptr)
        ldy #3
        sta (ptr),y
        dey
        lda #CH_UFOR
        sta (ptr),y
        dey
        lda #CH_UFOL
        sta (ptr),y
@x:     rts
@off:   jsr UFOCLR
        rts

UFOCLR: stz uact
        jsr RAND                ; next one in about 4-5 seconds
        ora #$80
        lsr a
        clc
        adc #120
        sta utimer
        lda #ROW_UFO
        ldx #0
        jsr SETPTR
        ldy #63
        lda #CH_SP
@c:     sta (ptr),y
        dey
        bpl @c
        rts

UFOHIT: lda uact
        beq @x
        jsr UFOCLR
        jsr RAND                ; 50, 100 or 150
        and #3
        tax
        lda UFOPTS,x
        jsr ADDSCORE
        lda UFOHI,x
        beq @x
        sed
        clc
        adc score+1
        sta score+1
        cld
        jsr DRAWSCORE
@x:     rts
UFOPTS: .byte $50, $00, $50, $00
UFOHI:  .byte $00, $01, $01, $01

;=================================================================
; score, HUD, screen
;=================================================================
; ADDSCORE - add the BCD number in A; extra base at 1500
ADDSCORE:
        sed
        clc
        adc score
        sta score
        lda score+1
        adc #0
        sta score+1
        cld
        lda bonus
        bne @s
        lda score+1
        cmp #$15
        bcc @s
        inc bonus
        inc lives
        jsr DRAWLIVES
@s:     jmp DRAWSCORE

DRAWHUD:
        jsr PRINTI
        .byte ROW_HUD, 4, "SCORE", 0
        jsr PRINTI
        .byte ROW_HUD, 24, "HI-SCORE", 0
        jsr PRINTI
        .byte ROW_HUD, 47, "BASES", 0
        jsr DRAWSCORE
        jmp DRAWLIVES

DRAWSCORE:
        lda #ROW_HUD
        ldx #10
        jsr SETPTR
        ldy #0
        lda score+1
        jsr PRBCD
        lda score
        jsr PRBCD
        lda #ROW_HUD
        ldx #33
        jsr SETPTR
        ldy #0
        lda hiscore+1
        jsr PRBCD
        lda hiscore
        jmp PRBCD

DRAWLIVES:
        lda #ROW_HUD
        ldx #53
        jsr SETPTR
        lda lives
        ora #$30
        sta (ptr)
        rts

; PRBCD - two digits of A at (ptr),y, y += 2
PRBCD:  pha
        lsr a
        lsr a
        lsr a
        lsr a
        ora #$30
        sta (ptr),y
        iny
        pla
        and #$0F
        ora #$30
        sta (ptr),y
        iny
        rts

DRAWSHIELDS:                    ; four shields, 5 wide
        ldx #0
@s:     phx
        lda SHX,x
        tax
        lda #ROW_SHIELD
        jsr SETPTR
        lda #CH_SH0
        ldy #4
@t:     sta (ptr),y
        dey
        bpl @t
        ldy #64                 ; next row: 2 blocks, gap, 2 blocks
        sta (ptr),y
        iny
        sta (ptr),y
        iny
        iny
        sta (ptr),y
        iny
        sta (ptr),y
        plx
        inx
        cpx #4
        bne @s
        rts
SHX:    .byte 10, 23, 36, 49

DRAWGROUND:
        lda #ROW_GROUND
        ldx #0
        jsr SETPTR
        ldy #63
        lda #CH_GND
@g:     sta (ptr),y
        dey
        bpl @g
        rts

CLS:    lda #<SCR
        sta ptr
        lda #>SCR
        sta ptr+1
        ldx #8                  ; 2K
        ldy #0
        lda #CH_SP
@c:     sta (ptr),y
        iny
        bne @c
        inc ptr+1
        dex
        bne @c
        rts

; PRINTI - print the inline text: .byte row, column, "text", 0
PRINTI: pla
        sta sptr
        pla
        sta sptr+1
        ldy #1
        lda (sptr),y            ; row
        pha
        iny
        lda (sptr),y            ; column
        tax
        pla
        jsr SETPTR
        ldy #3
@c:     lda (sptr),y
        beq @end
        phy
        dey
        dey
        dey
        sta (ptr),y
        ply
        iny
        bra @c
@end:   tya                     ; return past the 0
        sec
        adc sptr
        sta sptr
        bcc @r
        inc sptr+1
@r:     jmp (sptr)

; SETPTR - ptr = SCR + A*64 + X   (uses tmp, tmp2 is kept)
SETPTR: sta tmp
        stx ptr
        lsr a
        lsr a
        clc
        adc #>SCR
        sta ptr+1
        lda tmp
        asl a
        asl a
        asl a
        asl a
        asl a
        asl a
        clc
        adc ptr
        sta ptr
        bcc @x
        inc ptr+1
@x:     rts

; RAND - 16-bit random number, A = low byte
RAND:   asl rnd
        rol rnd+1
        bcc @x
        lda rnd
        eor #$2D
        sta rnd
@x:     lda rnd
        rts

;=================================================================
        .segment "BSS"
savesp: .res 1
zpsave: .res ZPSIZE
hiscore: .res 2
score:  .res 2
lives:  .res 1
bonus:  .res 1
wave:   .res 1
frame:  .res 1
kleft:  .res 1
kright: .res 1
kfire:  .res 1
kesc:   .res 1
alive:  .res 55
nalive: .res 1
fx:     .res 1
fy:     .res 1
fdir:   .res 1
anim:   .res 1
stepcnt: .res 1
stepint: .res 1
invaded: .res 1
lc:     .res 1
rc:     .res 1
rb:     .res 1
invl:   .res 1
invr:   .res 1
px:     .res 1
pdead:  .res 1
sact:   .res 1
sx:     .res 1
sy:     .res 1
bact:   .res 3
bx:     .res 3
by:     .res 3
bombcnt: .res 1
eact:   .res 1
ex:     .res 1
ey:     .res 1
etimer: .res 1
uact:   .res 1
ux:     .res 1
udir:   .res 1
utimer: .res 1
