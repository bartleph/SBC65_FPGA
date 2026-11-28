   10         * = $4000
   20 PTR   = $50
   30 TMP   = $52
   40 TMP2  = $53
   50 TMP3  = $54
   60 RND   = $55
   70 SPTR  = $57
   80 SCR   = $D000
   90 KBD   = $DF00
  100 BANK  = $C0A0
  110 ACIAS = $C080
  120 ACIAD = $C081
  130 OUTCH = $E0C7
  140 TYPAHD = $2325
  150 START   TSX
  160         STX SAVESP
  170         LDX #15
  180 STA001  LDA $50,X
  190         STA ZPSAVE,X
  200         DEX
  210         BPL STA001
  220         LDA #$02
  230         STA BANK
  240         LDA #$A5
  250         STA RND
  260         LDA #$5A
  270         STA RND+1
  280         STZ HISCOR
  290         STZ HISCOR+1
  300 TITLE   LDA #3
  310         STA LIVES
  320         JSR CLS
  330         JSR DRWHUD
  340         JSR PRINTI
  350         .BYTE $05,$12,$53,$20,$50,$20,$41,$20
  360         .BYTE $43,$20,$45,$20,$20,$20,$49,$20
  370         .BYTE $4E,$20,$56,$20,$41,$20,$44,$20
  380         .BYTE $45,$20,$52,$20,$53,$00
  390         JSR PRINTI
  400         .BYTE $09,$18,$3D,$20,$3F,$20,$4D,$59
  410         .BYTE $53,$54,$45,$52,$59,$00
  420         JSR PRINTI
  430         .BYTE $0B,$18,$3D,$20,$33,$30,$20,$50
  440         .BYTE $4F,$49,$4E,$54,$53,$00
  450         JSR PRINTI
  460         .BYTE $0D,$18,$3D,$20,$32,$30,$20,$50
  470         .BYTE $4F,$49,$4E,$54,$53,$00
  480         JSR PRINTI
  490         .BYTE $0F,$18,$3D,$20,$31,$30,$20,$50
  500         .BYTE $4F,$49,$4E,$54,$53,$00
  510         JSR PRINTI
  520         .BYTE $13,$08,$5A,$20,$3D,$20,$4C,$45
  530         .BYTE $46,$54,$20,$20,$20,$58,$20,$3D
  540         .BYTE $20,$52,$49,$47,$48,$54,$20,$20
  550         .BYTE $20,$53,$50,$41,$43,$45,$20,$3D
  560         .BYTE $20,$46,$49,$52,$45,$20,$20,$20
  570         .BYTE $45,$53,$43,$20,$3D,$20,$51,$55
  580         .BYTE $49,$54,$00
  590         JSR PRINTI
  600         .BYTE $16,$16,$50,$52,$45,$53,$53,$20
  610         .BYTE $53,$50,$41,$43,$45,$20,$54,$4F
  620         .BYTE $20,$50,$4C,$41,$59,$00
  630         LDA #9
  640         LDX #20
  650         JSR SETPTR
  660         LDA #227
  670         STA (PTR)
  680         LDY #1
  690         LDA #228
  700         STA (PTR),Y
  710         LDA #11
  720         LDX #20
  730         JSR SETPTR
  740         LDA #$ED
  750         STA (PTR)
  760         LDA #$EF
  770         STA (PTR),Y
  780         LDA #13
  790         LDX #20
  800         JSR SETPTR
  810         LDA #$11
  820         STA (PTR)
  830         LDA #$17
  840         STA (PTR),Y
  850         LDA #15
  860         LDX #20
  870         JSR SETPTR
  880         LDA #$12
  890         STA (PTR)
  900         LDA #$16
  910         STA (PTR),Y
  920 TIT002  JSR FRAME
  930         LDA KFIRE
  940         BNE TIT002
  950 TIT003  JSR FRAME
  960         JSR RAND
  970         LDA KESC
  980         BEQ TIT004
  990         JMP EXIT
 1000 TIT004  LDA KFIRE
 1010         BEQ TIT003
 1020         STZ SCORE
 1030         STZ SCORE+1
 1040         LDA #3
 1050         STA LIVES
 1060         STZ WAVE
 1070         STZ BONUS
 1080 NEWWAV  INC WAVE
 1090         JSR CLS
 1100         JSR DRWHUD
 1110         JSR DRWSHD
 1120         JSR DRWGND
 1130         LDX #54
 1140         LDA #1
 1150 NEW005  STA ALIVE,X
 1160         DEX
 1170         BPL NEW005
 1180         LDA #55
 1190         STA NALIVE
 1200         LDA #11
 1210         STA FX
 1220         LDA WAVE
 1230         CLC
 1240         ADC #3
 1250         CMP #10
 1260         BCC NEW006
 1270         LDA #9
 1280 NEW006  STA FY
 1290         LDA #1
 1300         STA FDIR
 1310         STZ ANIM
 1320         STZ INVADD
 1330         LDA #2
 1340         STA STPCNT
 1350         JSR SETSTP
 1360         STZ SACT
 1370         STZ BACT
 1380         STZ BACT+1
 1390         STZ BACT+2
 1400         STZ EACT
 1410         STZ UACT
 1420         LDA #250
 1430         STA UTIMER
 1440         LDA #40
 1450         STA BOMCNT
 1460         STZ PDEAD
 1470         LDA #31
 1480         STA PX
 1490         JSR DRWBAS
 1500         JSR DRWFRM
 1510 MAIN    JSR FRAME
 1520         LDA KESC
 1530         BEQ MAI007
 1540         JMP EXIT
 1550 MAI007  JSR PLAYER
 1560         JSR SHOT
 1570         LDA PDEAD
 1580         BNE MAI009
 1590         LDA FRAMEC
 1600         LSR A
 1610         BCC MAI008
 1620         JSR BOMBS
 1630 MAI008  JSR FRMSTP
 1640         JSR DRPBMB
 1650         JSR SAUCER
 1660 MAI009  JSR EXPLOD
 1670         LDA INVADD
 1680         BNE GAMOVR
 1690         LDA PDEAD
 1700         BNE MAIN
 1710         LDA LIVES
 1720         BEQ GAMOVR
 1730         LDA NALIVE
 1740         BNE MAIN
 1750         LDX #50
 1760 MAI010  JSR FRAME
 1770         DEX
 1780         BNE MAI010
 1790         JMP NEWWAV
 1800 GAMOVR  LDA #10
 1810 GAM011  PHA
 1820         LDX #0
 1830         JSR SETPTR
 1840         LDY #63
 1850         LDA #32
 1860 GAM012  STA (PTR),Y
 1870         DEY
 1880         BPL GAM012
 1890         PLA
 1900         CLC
 1910         ADC #1
 1920         CMP #13
 1930         BNE GAM011
 1940         JSR PRINTI
 1950         .BYTE $0B,$17,$47,$20,$41,$20,$4D,$20
 1960         .BYTE $45,$20,$20,$20,$4F,$20,$56,$20
 1970         .BYTE $45,$20,$52,$00
 1980         LDA SCORE+1
 1990         CMP HISCOR+1
 2000         BCC GAM014
 2010         BNE GAM013
 2020         LDA SCORE
 2030         CMP HISCOR
 2040         BCC GAM014
 2050 GAM013  LDA SCORE
 2060         STA HISCOR
 2070         LDA SCORE+1
 2080         STA HISCOR+1
 2090         JSR DRWSCR
 2100 GAM014  LDX #150
 2110 GAM015  JSR FRAME
 2120         LDA KESC
 2130         BNE EXIT
 2140         DEX
 2150         BNE GAM015
 2160         JMP TITLE
 2170 EXIT    STZ BANK
 2180         JSR DRAIN
 2190         STZ TYPAHD
 2200         LDX #15
 2210 EXI016  LDA ZPSAVE,X
 2220         STA $50,X
 2230         DEX
 2240         BPL EXI016
 2250         LDA #$0C
 2260         JSR OUTCH
 2270         LDX SAVESP
 2280         TXS
 2290         RTS
 2300 FRAME   PHX
 2310         PHY
 2320         LDX #11
 2330         LDY #0
 2340 FRA017  DEY
 2350         BNE FRA017
 2360         DEX
 2370         BNE FRA017
 2380         INC FRAMEC
 2390         JSR DRAIN
 2400         JSR KEYS
 2410         PLY
 2420         PLX
 2430         RTS
 2440 DRAIN   LDA ACIAS
 2450         LSR A
 2460         BCC DRA018
 2470         LDA ACIAD
 2480         BRA DRAIN
 2490 DRA018  RTS
 2500 KEYS    LDA #$FD
 2510         STA KBD
 2520         LDA KBD
 2530         EOR #$FF
 2540         TAX
 2550         AND #$20
 2560         STA KLEFT
 2570         TXA
 2580         AND #$10
 2590         STA KFIRE
 2600         LDA #$FB
 2610         STA KBD
 2620         LDA KBD
 2630         EOR #$FF
 2640         AND #$80
 2650         STA KRIGHT
 2660         LDA #$FE
 2670         STA KBD
 2680         LDA KBD
 2690         EOR #$FF
 2700         AND #$20
 2710         STA KESC
 2720         RTS
 2730 PLAYER  LDA PDEAD
 2740         BEQ PLA023
 2750         DEC PDEAD
 2760         BEQ PLA021
 2770         LDA PDEAD
 2780         AND #$04
 2790         BEQ PLA019
 2800         LDA #188
 2810         BRA PLA020
 2820 PLA019  LDA #236
 2830 PLA020  PHA
 2840         LDA #24
 2850         LDX PX
 2860         JSR SETPTR
 2870         PLA
 2880         STA (PTR)
 2890         RTS
 2900 PLA021  LDA LIVES
 2910         BEQ PLA022
 2920         LDA #31
 2930         PHA
 2940         JSR ERSBAS
 2950         PLA
 2960         STA PX
 2970         JSR DRWBAS
 2980 PLA022  RTS
 2990 PLA023  LDA FRAMEC
 3000         LSR A
 3010         BCC PLA025
 3020         LDA KLEFT
 3030         BEQ PLA024
 3040         LDA PX
 3050         CMP #2
 3060         BCC PLA025
 3070         DEC PX
 3080         JSR DRWBAS
 3090         BRA PLA025
 3100 PLA024  LDA KRIGHT
 3110         BEQ PLA025
 3120         LDA PX
 3130         CMP #61
 3140         BCS PLA025
 3150         INC PX
 3160         JSR DRWBAS
 3170 PLA025  LDA KFIRE
 3180         BEQ PLA026
 3190         LDA SACT
 3200         BNE PLA026
 3210         LDA #23
 3220         STA SY
 3230         LDA PX
 3240         STA SX
 3250         LDA #1
 3260         STA SACT
 3270         LDA SY
 3280         LDX SX
 3290         JSR SETPTR
 3300         LDA (PTR)
 3310         CMP #32
 3320         BNE PLA026
 3330         LDA #139
 3340         STA (PTR)
 3350 PLA026  RTS
 3360 DRWBAS  LDA #24
 3370         LDX PX
 3380         DEX
 3390         JSR SETPTR
 3400         LDA #32
 3410         STA (PTR)
 3420         LDY #2
 3430         STA (PTR),Y
 3440         DEY
 3450         LDA #236
 3460         STA (PTR),Y
 3470         RTS
 3480 ERSBAS  LDA #24
 3490         LDX PX
 3500         DEX
 3510         JSR SETPTR
 3520         LDA #32
 3530         LDY #2
 3540 ERS027  STA (PTR),Y
 3550         DEY
 3560         BPL ERS027
 3570         RTS
 3580 SHOT    LDA SACT
 3590         BNE SHO028
 3600         RTS
 3610 SHO028  LDA SY
 3620         LDX SX
 3630         JSR SETPTR
 3640         LDA (PTR)
 3650         CMP #139
 3660         BNE SHO029
 3670         LDA #32
 3680         STA (PTR)
 3690         BRA SHO030
 3700 SHO029  JSR ISINV
 3710         BNE SHO030
 3720         JMP HITINV
 3730 SHO030  DEC SY
 3740         LDA SY
 3750         CMP #2
 3760         BCC ENDSHT
 3770         LDX SX
 3780         JSR SETPTR
 3790         LDA (PTR)
 3800         CMP #32
 3810         BNE SHO031
 3820         LDA #139
 3830         STA (PTR)
 3840         RTS
 3850 SHO031  JSR ISINV
 3860         BNE SHO032
 3870         JMP HITINV
 3880 SHO032  JSR ISSHLD
 3890         BNE SHO033
 3900         JSR DAMAGE
 3910         BRA ENDSHT
 3920 SHO033  CMP #227
 3930         BEQ SHO036
 3940         CMP #228
 3950         BEQ SHO036
 3960         CMP #214
 3970         BNE ENDSHT
 3980         LDA #32
 3990         STA (PTR)
 4000         LDX #2
 4010 SHO034  LDA BACT,X
 4020         BEQ SHO035
 4030         LDA BX,X
 4040         CMP SX
 4050         BNE SHO035
 4060         LDA BY,X
 4070         CMP SY
 4080         BNE SHO035
 4090         STZ BACT,X
 4100 SHO035  DEX
 4110         BPL SHO034
 4120         BRA ENDSHT
 4130 SHO036  JSR UFOHIT
 4140 ENDSHT  STZ SACT
 4150         RTS
 4160 HITINV  LDA SY
 4170         SEC
 4180         SBC FY
 4190         BCC ENDSHT
 4200         CMP #9
 4210         BCS ENDSHT
 4220         LSR A
 4230         BCS ENDSHT
 4240         STA TMP3
 4250         LDA SX
 4260         SEC
 4270         SBC FX
 4280         TAX
 4290         AND #$03
 4300         CMP #2
 4310         BCS ENDSHT
 4320         TXA
 4330         LSR A
 4340         LSR A
 4350         CMP #11
 4360         BCS ENDSHT
 4370         STA TMP2
 4380         LDA TMP3
 4390         ASL A
 4400         ASL A
 4410         ASL A
 4420         CLC
 4430         ADC TMP3
 4440         ADC TMP3
 4450         ADC TMP3
 4460         ADC TMP2
 4470         TAX
 4480         LDA ALIVE,X
 4490         BEQ ENDSHT
 4500         STZ ALIVE,X
 4510         DEC NALIVE
 4520         LDX TMP3
 4530         LDA ROWPTS,X
 4540         JSR ADDSCR
 4550         JSR EXPEND
 4560         LDA TMP2
 4570         ASL A
 4580         ASL A
 4590         CLC
 4600         ADC FX
 4610         STA EX
 4620         LDA SY
 4630         STA EY
 4640         LDX EX
 4650         JSR SETPTR
 4660         LDA #188
 4670         STA (PTR)
 4680         LDY #1
 4690         STA (PTR),Y
 4700         LDA #8
 4710         STA ETIMER
 4720         LDA #1
 4730         STA EACT
 4740         JSR SETSTP
 4750         BRA ENDSHT
 4760 ROWPTS  .BYTE $30,$20,$20,$10,$10
 4770 ISINV   LDX #5
 4780 ISI037  CMP INVCH,X
 4790         BEQ ISI038
 4800         DEX
 4810         BPL ISI037
 4820         LDX #$FF
 4830 ISI038  RTS
 4840 INVCH   .BYTE $ED,$EF,$11,$17,$12,$16
 4850 ISSHLD  CMP #160
 4860         BEQ ISS039
 4870         CMP #187
 4880         BEQ ISS039
 4890         CMP #185
 4900 ISS039  RTS
 4910 DAMAGE  LDA (PTR)
 4920         CMP #160
 4930         BNE DAM040
 4940         LDA #187
 4950         BRA DAM042
 4960 DAM040  CMP #187
 4970         BNE DAM041
 4980         LDA #185
 4990         BRA DAM042
 5000 DAM041  LDA #32
 5010 DAM042  STA (PTR)
 5020         RTS
 5030 EXPLOD  LDA EACT
 5040         BEQ EXPX
 5050         DEC ETIMER
 5060         BNE EXPX
 5070 EXPEND  LDA EACT
 5080         BEQ EXPX
 5090         STZ EACT
 5100         LDA EY
 5110         LDX EX
 5120         JSR SETPTR
 5130         LDY #1
 5140 EXP043  LDA (PTR),Y
 5150         CMP #188
 5160         BNE EXP044
 5170         LDA #32
 5180         STA (PTR),Y
 5190 EXP044  DEY
 5200         BPL EXP043
 5210 EXPX    RTS
 5220 FRMSTP  DEC STPCNT
 5230         BEQ FRM045
 5240         RTS
 5250 FRM045  LDA STPINT
 5260         STA STPCNT
 5270         JSR COLRNG
 5280         LDA FDIR
 5290         BMI FRM046
 5300         LDA RC
 5310         ASL A
 5320         ASL A
 5330         CLC
 5340         ADC FX
 5350         ADC #3
 5360         CMP #63
 5370         BCS FRM047
 5380         INC FX
 5390         BRA FRM048
 5400 FRM046  LDA LC
 5410         ASL A
 5420         ASL A
 5430         CLC
 5440         ADC FX
 5450         CMP #3
 5460         BCC FRM047
 5470         DEC FX
 5480         BRA FRM048
 5490 FRM047  INC FY
 5500         LDA FDIR
 5510         EOR #$FE
 5520         STA FDIR
 5530         JSR CLRGAP
 5540         LDA RB
 5550         ASL A
 5560         CLC
 5570         ADC FY
 5580         CMP #24
 5590         BCC FRM048
 5600         LDA #1
 5610         STA INVADD
 5620 FRM048  LDA ANIM
 5630         EOR #1
 5640         STA ANIM
 5650         JMP DRWFRM
 5660 SETSTP  LDA NALIVE
 5670         CLC
 5680         ADC #3
 5690         LSR A
 5700         LSR A
 5710         BNE SET049
 5720         LDA #1
 5730 SET049  CMP #9
 5740         BCC SET050
 5750         LDA #8
 5760 SET050  STA STPINT
 5770         RTS
 5780 COLRNG  LDA #10
 5790         STA LC
 5800         STZ RC
 5810         STZ RB
 5820         LDX #54
 5830 COL051  LDA ALIVE,X
 5840         BEQ COL056
 5850         TXA
 5860         LDY #0
 5870 COL052  CMP #11
 5880         BCC COL053
 5890         SBC #11
 5900         INY
 5910         BRA COL052
 5920 COL053  CMP LC
 5930         BCS COL054
 5940         STA LC
 5950 COL054  CMP RC
 5960         BCC COL055
 5970         STA RC
 5980 COL055  CPY RB
 5990         BCC COL056
 6000         STY RB
 6010 COL056  DEX
 6020         BPL COL051
 6030         RTS
 6040 CLRGAP  LDX #0
 6050 CLR057  PHX
 6060         TXA
 6070         ASL A
 6080         CLC
 6090         ADC FY
 6100         SEC
 6110         SBC #1
 6120         CMP #25
 6130         BCS CLR059
 6140         LDX #0
 6150         JSR SETPTR
 6160         LDY #63
 6170         LDA #32
 6180 CLR058  STA (PTR),Y
 6190         DEY
 6200         BPL CLR058
 6210 CLR059  PLX
 6220         INX
 6230         CPX #5
 6240         BNE CLR057
 6250         RTS
 6260 DRWFRM  STZ TMP3
 6270         LDX #0
 6280 DRW060  LDY TMP3
 6290         LDA ROWTYP,Y
 6300         ASL A
 6310         ORA ANIM
 6320         TAY
 6330         LDA TINVL,Y
 6340         STA INVL
 6350         LDA TINVR,Y
 6360         STA INVR
 6370         STZ TMP2
 6380 DRW061  LDA ALIVE,X
 6390         BEQ DRW062
 6400         PHX
 6410         LDA TMP2
 6420         ASL A
 6430         ASL A
 6440         CLC
 6450         ADC FX
 6460         TAX
 6470         DEX
 6480         LDA TMP3
 6490         ASL A
 6500         CLC
 6510         ADC FY
 6520         JSR SETPTR
 6530         LDA #32
 6540         STA (PTR)
 6550         LDY #3
 6560         STA (PTR),Y
 6570         DEY
 6580         LDA INVR
 6590         STA (PTR),Y
 6600         DEY
 6610         LDA INVL
 6620         STA (PTR),Y
 6630         PLX
 6640 DRW062  INX
 6650         INC TMP2
 6660         LDA TMP2
 6670         CMP #11
 6680         BNE DRW061
 6690         INC TMP3
 6700         LDA TMP3
 6710         CMP #5
 6720         BNE DRW060
 6730         RTS
 6740 ROWTYP  .BYTE $00,$01,$01,$02,$02
 6750 TINVL   .BYTE $ED,$EF,$11,$17,$12,$16
 6760 TINVR   .BYTE $EF,$ED,$17,$11,$16,$12
 6770 DRPBMB  DEC BOMCNT
 6780         BEQ DRP063
 6790         RTS
 6800 DRP063  LDA WAVE
 6810         ASL A
 6820         STA TMP
 6830         LDA #26
 6840         SEC
 6850         SBC TMP
 6860         CMP #8
 6870         BCS DRP064
 6880         LDA #8
 6890 DRP064  STA BOMCNT
 6900         LDX #2
 6910 DRP065  LDA BACT,X
 6920         BEQ DRP066
 6930         DEX
 6940         BPL DRP065
 6950         RTS
 6960 DRP066  STX TMP2
 6970         LDY #8
 6980 DRP067  JSR RAND
 6990         AND #$0F
 7000         CMP #11
 7010         BCS DRP069
 7020         STA TMP3
 7030         CLC
 7040         ADC #44
 7050         TAX
 7060 DRP068  LDA ALIVE,X
 7070         BNE DRP070
 7080         TXA
 7090         SEC
 7100         SBC #11
 7110         TAX
 7120         BCS DRP068
 7130 DRP069  DEY
 7140         BNE DRP067
 7150         RTS
 7160 DRP070  TXA
 7170         SEC
 7180         SBC TMP3
 7190         LDY #0
 7200 DRP071  BEQ DRP072
 7210         SEC
 7220         SBC #11
 7230         INY
 7240         BRA DRP071
 7250 DRP072  TYA
 7260         ASL A
 7270         CLC
 7280         ADC FY
 7290         CLC
 7300         ADC #1
 7310         LDX TMP2
 7320         STA BY,X
 7330         LDA TMP3
 7340         ASL A
 7350         ASL A
 7360         CLC
 7370         ADC FX
 7380         STA BX,X
 7390         JSR RAND
 7400         AND #1
 7410         LDX TMP2
 7420         CLC
 7430         ADC BX,X
 7440         STA BX,X
 7450         LDA #1
 7460         STA BACT,X
 7470         RTS
 7480 BOMBS   LDX #2
 7490 BOM073  LDA BACT,X
 7500         BEQ BOM074
 7510         PHX
 7520         JSR BOMB1
 7530         PLX
 7540 BOM074  DEX
 7550         BPL BOM073
 7560         RTS
 7570 BOMB1   STX TMP2
 7580         LDA BY,X
 7590         PHA
 7600         LDA BX,X
 7610         TAX
 7620         PLA
 7630         JSR SETPTR
 7640         LDA (PTR)
 7650         CMP #214
 7660         BNE BOM075
 7670         LDA #32
 7680         STA (PTR)
 7690 BOM075  LDX TMP2
 7700         INC BY,X
 7710         LDA BY,X
 7720         CMP #25
 7730         BCS BOM079
 7740         PHA
 7750         LDA BX,X
 7760         TAX
 7770         PLA
 7780         JSR SETPTR
 7790         LDA (PTR)
 7800         CMP #32
 7810         BNE BOM076
 7820         LDA #214
 7830         STA (PTR)
 7840         RTS
 7850 BOM076  JSR ISINV
 7860         BEQ BOM080
 7870         JSR ISSHLD
 7880         BNE BOM077
 7890         JSR DAMAGE
 7900         BRA BOM079
 7910 BOM077  CMP #236
 7920         BNE BOM078
 7930         JSR BASEHT
 7940         BRA BOM079
 7950 BOM078  CMP #139
 7960         BNE BOM079
 7970         LDA #32
 7980         STA (PTR)
 7990         STZ SACT
 8000 BOM079  LDX TMP2
 8010         STZ BACT,X
 8020 BOM080  RTS
 8030 BASEHT  LDA PDEAD
 8040         BNE BAS084
 8050         DEC LIVES
 8060         JSR DRWLIV
 8070         LDA #60
 8080         STA PDEAD
 8090         LDX #2
 8100 BAS081  LDA BACT,X
 8110         BEQ BAS083
 8120         STZ BACT,X
 8130         PHX
 8140         LDA BY,X
 8150         PHA
 8160         LDA BX,X
 8170         TAX
 8180         PLA
 8190         JSR SETPTR
 8200         LDA (PTR)
 8210         CMP #214
 8220         BNE BAS082
 8230         LDA #32
 8240         STA (PTR)
 8250 BAS082  PLX
 8260 BAS083  DEX
 8270         BPL BAS081
 8280 BAS084  RTS
 8290 SAUCER  LDA UACT
 8300         BNE SAU086
 8310         DEC UTIMER
 8320         BNE SAU088
 8330         LDA #1
 8340         STA UACT
 8350         JSR RAND
 8360         AND #1
 8370         BEQ SAU085
 8380         LDA #1
 8390         STA UX
 8400         STA UDIR
 8410         BRA SAU087
 8420 SAU085  LDA #61
 8430         STA UX
 8440         LDA #$FF
 8450         STA UDIR
 8460         BRA SAU087
 8470 SAU086  LDA FRAMEC
 8480         AND #3
 8490         BNE SAU088
 8500         LDA UX
 8510         CLC
 8520         ADC UDIR
 8530         STA UX
 8540         BEQ SAU089
 8550         CMP #62
 8560         BCS SAU089
 8570 SAU087  LDA #2
 8580         LDX UX
 8590         DEX
 8600         JSR SETPTR
 8610         LDA #32
 8620         STA (PTR)
 8630         LDY #3
 8640         STA (PTR),Y
 8650         DEY
 8660         LDA #228
 8670         STA (PTR),Y
 8680         DEY
 8690         LDA #227
 8700         STA (PTR),Y
 8710 SAU088  RTS
 8720 SAU089  JSR UFOCLR
 8730         RTS
 8740 UFOCLR  STZ UACT
 8750         JSR RAND
 8760         ORA #$80
 8770         LSR A
 8780         CLC
 8790         ADC #120
 8800         STA UTIMER
 8810         LDA #2
 8820         LDX #0
 8830         JSR SETPTR
 8840         LDY #63
 8850         LDA #32
 8860 UFO090  STA (PTR),Y
 8870         DEY
 8880         BPL UFO090
 8890         RTS
 8900 UFOHIT  LDA UACT
 8910         BEQ UFO091
 8920         JSR UFOCLR
 8930         JSR RAND
 8940         AND #3
 8950         TAX
 8960         LDA UFOPTS,X
 8970         JSR ADDSCR
 8980         LDA UFOHI,X
 8990         BEQ UFO091
 9000         SED
 9010         CLC
 9020         ADC SCORE+1
 9030         STA SCORE+1
 9040         CLD
 9050         JSR DRWSCR
 9060 UFO091  RTS
 9070 UFOPTS  .BYTE $50,$00,$50,$00
 9080 UFOHI   .BYTE $00,$01,$01,$01
 9090 ADDSCR  SED
 9100         CLC
 9110         ADC SCORE
 9120         STA SCORE
 9130         LDA SCORE+1
 9140         ADC #0
 9150         STA SCORE+1
 9160         CLD
 9170         LDA BONUS
 9180         BNE ADD092
 9190         LDA SCORE+1
 9200         CMP #$15
 9210         BCC ADD092
 9220         INC BONUS
 9230         INC LIVES
 9240         JSR DRWLIV
 9250 ADD092  JMP DRWSCR
 9260 DRWHUD  JSR PRINTI
 9270         .BYTE $00,$04,$53,$43,$4F,$52,$45,$00
 9280         JSR PRINTI
 9290         .BYTE $00,$18,$48,$49,$2D,$53,$43,$4F
 9300         .BYTE $52,$45,$00
 9310         JSR PRINTI
 9320         .BYTE $00,$2F,$42,$41,$53,$45,$53,$00
 9330         JSR DRWSCR
 9340         JMP DRWLIV
 9350 DRWSCR  LDA #0
 9360         LDX #10
 9370         JSR SETPTR
 9380         LDY #0
 9390         LDA SCORE+1
 9400         JSR PRBCD
 9410         LDA SCORE
 9420         JSR PRBCD
 9430         LDA #0
 9440         LDX #33
 9450         JSR SETPTR
 9460         LDY #0
 9470         LDA HISCOR+1
 9480         JSR PRBCD
 9490         LDA HISCOR
 9500         JMP PRBCD
 9510 DRWLIV  LDA #0
 9520         LDX #53
 9530         JSR SETPTR
 9540         LDA LIVES
 9550         ORA #$30
 9560         STA (PTR)
 9570         RTS
 9580 PRBCD   PHA
 9590         LSR A
 9600         LSR A
 9610         LSR A
 9620         LSR A
 9630         ORA #$30
 9640         STA (PTR),Y
 9650         INY
 9660         PLA
 9670         AND #$0F
 9680         ORA #$30
 9690         STA (PTR),Y
 9700         INY
 9710         RTS
 9720 DRWSHD  LDX #0
 9730 DRW093  PHX
 9740         LDA SHX,X
 9750         TAX
 9760         LDA #21
 9770         JSR SETPTR
 9780         LDA #160
 9790         LDY #4
 9800 DRW094  STA (PTR),Y
 9810         DEY
 9820         BPL DRW094
 9830         LDY #64
 9840         STA (PTR),Y
 9850         INY
 9860         STA (PTR),Y
 9870         INY
 9880         INY
 9890         STA (PTR),Y
 9900         INY
 9910         STA (PTR),Y
 9920         PLX
 9930         INX
 9940         CPX #4
 9950         BNE DRW093
 9960         RTS
 9970 SHX     .BYTE $0A,$17,$24,$31
 9980 DRWGND  LDA #25
 9990         LDX #0
10000         JSR SETPTR
10010         LDY #63
10020         LDA #131
10030 DRW095  STA (PTR),Y
10040         DEY
10050         BPL DRW095
10060         RTS
10070 CLS     LDA #$00
10080         STA PTR
10090         LDA #$D0
10100         STA PTR+1
10110         LDX #8
10120         LDY #0
10130         LDA #32
10140 CLS096  STA (PTR),Y
10150         INY
10160         BNE CLS096
10170         INC PTR+1
10180         DEX
10190         BNE CLS096
10200         RTS
10210 PRINTI  PLA
10220         STA SPTR
10230         PLA
10240         STA SPTR+1
10250         LDY #1
10260         LDA (SPTR),Y
10270         PHA
10280         INY
10290         LDA (SPTR),Y
10300         TAX
10310         PLA
10320         JSR SETPTR
10330         LDY #3
10340 PRI097  LDA (SPTR),Y
10350         BEQ PRI098
10360         PHY
10370         DEY
10380         DEY
10390         DEY
10400         STA (PTR),Y
10410         PLY
10420         INY
10430         BRA PRI097
10440 PRI098  TYA
10450         SEC
10460         ADC SPTR
10470         STA SPTR
10480         BCC PRI099
10490         INC SPTR+1
10500 PRI099  JMP (SPTR)
10510 SETPTR  STA TMP
10520         STX PTR
10530         LSR A
10540         LSR A
10550         CLC
10560         ADC #$D0
10570         STA PTR+1
10580         LDA TMP
10590         ASL A
10600         ASL A
10610         ASL A
10620         ASL A
10630         ASL A
10640         ASL A
10650         CLC
10660         ADC PTR
10670         STA PTR
10680         BCC SET100
10690         INC PTR+1
10700 SET100  RTS
10710 RAND    ASL RND
10720         ROL RND+1
10730         BCC RAN101
10740         LDA RND
10750         EOR #$2D
10760         STA RND
10770 RAN101  LDA RND
10780         RTS
10790 SAVESP  .BYTE 0
10800 ZPSAVE  .BYTE 0,0,0,0,0,0,0,0
10810         .BYTE 0,0,0,0,0,0,0,0
10820 HISCOR  .BYTE 0,0
10830 SCORE   .BYTE 0,0
10840 LIVES   .BYTE 0
10850 BONUS   .BYTE 0
10860 WAVE    .BYTE 0
10870 FRAMEC  .BYTE 0
10880 KLEFT   .BYTE 0
10890 KRIGHT  .BYTE 0
10900 KFIRE   .BYTE 0
10910 KESC    .BYTE 0
10920 ALIVE   .BYTE 0,0,0,0,0,0,0,0
10930         .BYTE 0,0,0,0,0,0,0,0
10940         .BYTE 0,0,0,0,0,0,0,0
10950         .BYTE 0,0,0,0,0,0,0,0
10960         .BYTE 0,0,0,0,0,0,0,0
10970         .BYTE 0,0,0,0,0,0,0,0
10980         .BYTE 0,0,0,0,0,0,0
10990 NALIVE  .BYTE 0
11000 FX      .BYTE 0
11010 FY      .BYTE 0
11020 FDIR    .BYTE 0
11030 ANIM    .BYTE 0
11040 STPCNT  .BYTE 0
11050 STPINT  .BYTE 0
11060 INVADD  .BYTE 0
11070 LC      .BYTE 0
11080 RC      .BYTE 0
11090 RB      .BYTE 0
11100 INVL    .BYTE 0
11110 INVR    .BYTE 0
11120 PX      .BYTE 0
11130 PDEAD   .BYTE 0
11140 SACT    .BYTE 0
11150 SX      .BYTE 0
11160 SY      .BYTE 0
11170 BACT    .BYTE 0,0,0
11180 BX      .BYTE 0,0,0
11190 BY      .BYTE 0,0,0
11200 BOMCNT  .BYTE 0
11210 EACT    .BYTE 0
11220 EX      .BYTE 0
11230 EY      .BYTE 0
11240 ETIMER  .BYTE 0
11250 UACT    .BYTE 0
11260 UX      .BYTE 0
11270 UDIR    .BYTE 0
11280 UTIMER  .BYTE 0
11290         .END
