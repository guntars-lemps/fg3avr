.DEVICE ATMEGA328P
.NOLIST                                            ;Turn off to decrease size of list
.INCLUDEPATH "/usr/share/avra"
.INCLUDE "m328Pdef.inc"                            ;Include device file
.LIST                                              ;Turn on

.dseg
inbuf:  .byte 30   ;input buffer
outbuf: .byte 256  ;output buffer
workbuf: .byte 21  ;copy of input buffer for command 0x01 (Set frequencies)
loadbuf: .byte 21  ;temporary buffer to load eeprom

.cseg
.org 0
    rjmp reset

.org URXCaddr
    rjmp usart_rxc        ;USART RX Complete handler

reset:
    cli                   ;disable global interrupts

    ldi r16, HIGH(RAMEND) ;set stack pointer to RAM end
    out SPH, r16
    ldi r16, LOW(RAMEND)
    out SPL, r16

    ldi r16, 51           ;baud rate 19200 at 16MHz
    sts UBRR0L, r16
    clr r16
    sts UBRR0H, r16

    sts UCSR0A, r16       ;clear USART control and status register


    ldi r16, (1 << RXCIE0) | (1 << RXEN0) | (1 << TXEN0) ;enable RX interrupt, receiver and transmitter
    sts UCSR0B, r16


    ldi r16, (1 << USBS0) | (0b011 << UCSZ00) ;Set frame format: 8data, 1 stop bit
    sts UCSR0C, r16

    clr r16
    out GPIOR0, r16       ;GPIOR0 register used as pointer in UART input buffer
    out GPIOR1, r16       ;GPIOR1 and GPIOR2 register used as pointer in UART output ring buffer
    out GPIOR2, r16


    ;setup timer1 for input buffer pointer resetting

    ;set prescaler to 64 and mode to normal
    clr r16
    sts TCCR1A, r16
    ldi r16, 0b00000011
    sts TCCR1B, r16

    ;reset timer1 value
    clr r16
    sts TCNT1H, r16
    sts TCNT1L, r16

    ldi r16, (1 << DDD4) | (1 << DDD3) | (1 << DDD2) ; set D2,D3,D4 pins for frequencies output
    out DDRD, r16

    ;clear workbuf (all frequencies off by default)
    clr r17
    ldi XH, HIGH(workbuf)
    ldi XL, LOW(workbuf)
    ldi r16, 21
reset0:
    st X, r17
    adiw XH:XL, 0x01
    dec r16
    brne reset0

    sei                     ;enable interrupts

    call load_from_eeprom   ;if there is correct data in eeprom then copy it into workbuf

    rjmp main_freq_gen


main0:

    ;returns there after USART RXC interrupt

    ;check if any command is received
    ldi YH, HIGH(inbuf)
    ldi YL, LOW(inbuf)
    in r16, GPIOR0          ;input buffer lenght
    cpi r16, 3              ;lenght for commands 0x00, 0x02, 0x03
    brne main0_1

    ld r18, Y               ;check if command is 0x01, then do nothing yet, still receiving
    cpi r18, 0x01
    brne main0_2
    rjmp main_tx_out

main0_2:
    ;calculate and compare CRC16
    ldi r16, 1
    call calc_crc16
    ldd r18, Y + 1
    cp r18, r17
    brne main_send_bad
    ldd r18, Y + 2
    cp r18, r16
    brne main_send_bad

    ;data is ok, now check what command is received
    ld r18, Y
    cpi r18, 0x00
    breq main_send_ok       ;if command is 0x00 (ping-pong) then just send OK response
    cpi r18, 0x02
    brne main0_0

    ;do "STORE TO EEPROM"

    call store_to_eeprom

    rjmp main_send_ok

main0_0:
    cpi r18, 0x03
    brne main_send_bad      ;if not equal to 0x03 then unknown command, send bad response

    ;do "LOAD FROM EEPROM"

    call load_from_eeprom
    tst r16
    brne main_send_bad_data ;if bad eeprom data then send "bad data" response
    rjmp main_send_ok

main0_1:
    cpi r16, 21             ;test for command 0x01
    brne main_tx_out

    ld r18, Y
    cpi r18, 0x01
    brne main_send_bad      ;unknown command, send bad response

    ;calculate and compare CRC16
    ldi r16, 19             ;lenght is 19 bytes without CRC checksumm
    call calc_crc16

    ldd r18, Y + 19
    cp r18, r17
    brne main_send_bad
    ldd r18, Y + 20
    cp r18, r16
    brne main_send_bad

    ;do "SETUP FREQUENCIES"
    ;copy inbuf to workbuf
    ;Y is at inbuf already

    ldi XH, HIGH(workbuf)
    ldi XL, LOW(workbuf)
    ldi r16, 21
main0_3:
    ld r17, Y
    st X, r17
    adiw XH:XL, 0x01
    adiw YH:YL, 0x01
    dec r16
    brne main0_3

    rjmp main_send_ok

main_send_ok:
    ldi r16, 0x00
    call send_r16
    ldi r16, 0x40
    call send_r16
    ldi r16, 0xbf
    call send_r16

    clr r16                ;reset input buffer
    out GPIOR0, r16

    rjmp main_tx_out

main_send_bad:
    ldi r16, 0x01
    call send_r16
    ldi r16, 0x80
    call send_r16
    ldi r16, 0x7e
    call send_r16

    clr r16                ;reset input buffer
    out GPIOR0, r16

    rjmp main_tx_out

main_send_bad_data:
    ldi r16, 0x02
    call send_r16
    ldi r16, 0x81
    call send_r16
    ldi r16, 0x3e
    call send_r16

    clr r16                ;reset input buffer
    out GPIOR0, r16

    rjmp main_tx_out

main_tx_out:
    ;check if something is in output buffer
    in r18, GPIOR1
    in r19, GPIOR2
    cp r18, r19
    breq main_freq_gen     ;if nothing in output buffer then jump to main loop

    ;Calculate actual output buffer address in Y register
    ldi YH, HIGH(outbuf)
    ldi YL, LOW(outbuf)
    in  r18, GPIOR1
    add YL, r18
    clr r18
    adc YH, r18

main_tx_out_0:
    ;wait until previous byte is sent
    lds  r18, UCSR0A
    sbrs r18, UDRE0
    rjmp main_tx_out_0

    ;read and send next byte
    ld r18, Y
    sts UDR0, r18

    ;increment GPIOR1
    in r18, GPIOR1
    inc r18
    out GPIOR1, r18

    rjmp main_tx_out

;--------------------------------
;---  Frequencies generation  ---
;--------------------------------

main_freq_gen:

    ;Frequencies on pins D2 / D3 / D4

    ldi YH, HIGH(workbuf)
    ldi YL, LOW(workbuf)

    ;copy all 9 counters to registers for faster generation
    ldd r1, Y + 1
    ldd r0, Y + 2
    ldd r3, Y + 3
    ldd r2, Y + 4
    ldd r5, Y + 5
    ldd r4, Y + 6

    ldd r7, Y + 7
    ldd r6, Y + 8
    ldd r9, Y + 9
    ldd r8, Y + 10
    ldd r11, Y + 11
    ldd r10, Y + 12

    ldd r13, Y + 13
    ldd r12, Y + 14
    ldd r15, Y + 15
    ldd r14, Y + 16
    ldd r17, Y + 17
    ldd r16, Y + 18

    ;copy delay counters into X,Y,Z
    movw XH:XL, r1:r0
    movw YH:YL, r7:r6
    movw ZH:ZL, r13:r12

    ;all combinations for portD output
    ldi r18, (0b000 << 2)
    ldi r19, (0b001 << 2)
    ldi r20, (0b010 << 2)
    ldi r21, (0b011 << 2)
    ldi r22, (0b100 << 2)
    ldi r23, (0b101 << 2)
    ldi r24, (0b110 << 2)
    ldi r25, (0b111 << 2)

    ;if any channel is off then clear related bits

    tst r2
    brne f1
    tst r3
    brne f1

    cbr r19, (0b001 << 2)
    cbr r21, (0b001 << 2)
    cbr r23, (0b001 << 2)
    cbr r25, (0b001 << 2)

f1:
    tst r8
    brne f2
    tst r9
    brne f2

    brne f2
    cbr r20, (0b010 << 2)
    cbr r21, (0b010 << 2)
    cbr r24, (0b010 << 2)
    cbr r25, (0b010 << 2)

f2:
    tst r14
    brne f3
    tst r15
    brne f3

    cbr r22, (0b100 << 2)
    cbr r23, (0b100 << 2)
    cbr r24, (0b100 << 2)
    cbr r25, (0b100 << 2)

; copy ON counters for frequencies without delay
f3:
    tst r0
    brne f4
    tst r1
    brne f4
    ;F1 without delay
    movw XH:XL, r3:r2 ;copy ON counter for F1
f4:
    tst r6
    brne f5
    tst r7
    brne f5
    ;F2 without delay
    movw YH:YL, r9:r8 ;copy ON counter for F2
f5:
    tst r12
    brne f4
    tst r13
    brne f4
    ;F3 without delay
    movw ZH:ZL, r15:r14 ;copy ON counter for F3

; now jump to correct loop

    tst r0
    brne f_X_X_OFF
    tst r1
    brne f_X_X_OFF

    tst r6
    brne f_X_OFF_ON
    tst r7
    brne f_X_OFF_ON

    tst r12
    brne f_OFF_ON_ON
    tst r13
    brne f_OFF_ON_ON

    rjmp f111_0

f_OFF_ON_ON:

    rjmp f011_0

f_X_OFF_ON:

    tst r12
    brne f_OFF_OFF_ON
    tst r13
    brne f_OFF_OFF_ON

    rjmp f101_0

f_OFF_OFF_ON:

    rjmp f001_0

f_X_X_OFF:

    tst r6
    brne f_X_OFF_OFF
    tst r7
    brne f_X_OFF_OFF

    tst r12
    brne f_OFF_ON_OFF
    tst r13
    brne f_OFF_ON_OFF

    rjmp f110_0

f_OFF_ON_OFF:

    rjmp f010_0

f_X_OFF_OFF:

    tst r12
    brne f_OFF_OFF_OFF
    tst r13
    brne f_OFF_OFF_OFF

    rjmp f100_0

f_OFF_OFF_OFF:

f000_0:
    sbiw XH:XL, 0x01     ; 2 clocks
    brne f000_1          ; 2 clocks if jump, 1 clock if dont jump
    movw XH:XL, r3:r2    ; 1 clock
    rjmp f001_2          ; 2 clocks
f000_1:
    nop                  ; 1 clock
    nop                  ; 1 clock
f000_2:
    sbiw YH:YL, 0x01     ; 2 clocks
    brne f000_3          ; 2 clocks if jump, 1 clock if dont jump
    movw YH:YL, r9:r8    ; 1 clock
    rjmp f010_4          ; 2 clocks
f000_3:
    nop                  ; 1 clock
    nop                  ; 1 clock
f000_4:
    sbiw ZH:ZL, 0x01     ; 2 clocks
    brne f000_5          ; 2 clocks if jump, 1 clock if dont jump
    movw ZH:ZL, r15:r14  ; 1 clock
    rjmp f100_6          ; 2 clocks
f000_5:
    nop                  ; 1 clock
    nop                  ; 1 clock
f000_6:
    out PORTD, r18       ; 1 clock
    rjmp f000_0          ; 2 clocks
;----------------------------------------------------------------
;OFF / OFF / ON
f001_0:
    sbiw XH:XL, 0x01     ; 2 clocks
    brne f001_1          ; 2 clocks if jump, 1 clock if dont jump
    movw XH:XL, r5:r4    ; 1 clock
    rjmp f000_2          ; 2 clocks
f001_1:
    nop                  ; 1 clock
    nop                  ; 1 clock
f001_2:
    sbiw YH:YL, 0x01     ; 2 clocks
    brne f001_3          ; 2 clocks if jump, 1 clock if dont jump
    movw YH:YL, r9:r8    ; 1 clock
    rjmp f011_4          ; 2 clocks
f001_3:
    nop                  ; 1 clock
    nop                  ; 1 clock
f001_4:
    sbiw ZH:ZL, 0x01     ; 2 clocks
    brne f001_5          ; 2 clocks if jump, 1 clock if dont jump
    movw ZH:ZL, r15:r14  ; 1 clock
    rjmp f101_6          ; 2 clocks
f001_5:
    nop                  ; 1 clock
    nop                  ; 1 clock
f001_6:
    out PORTD, r19       ; 1 clock
    rjmp f001_0          ; 2 clocks
;----------------------------------------------------------------
;OFF / ON / OFF
f010_0:
    sbiw XH:XL, 0x01     ; 2 clocks
    brne f010_1          ; 2 clocks if jump, 1 clock if dont jump
    movw XH:XL, r3:r2    ; 1 clock
    rjmp f011_2          ; 2 clocks
f010_1:
    nop                  ; 1 clock
    nop                  ; 1 clock
f010_2:
    sbiw YH:YL, 0x01     ; 2 clocks
    brne f010_3          ; 2 clocks if jump, 1 clock if dont jump
    movw YH:YL, r11:r10  ; 1 clock
    rjmp f000_4          ; 2 clocks
f010_3:
    nop                  ; 1 clock
    nop                  ; 1 clock
f010_4:
    sbiw ZH:ZL, 0x01     ; 2 clocks
    brne f010_5          ; 2 clocks if jump, 1 clock if dont jump
    movw ZH:ZL, r15:r14  ; 1 clock
    rjmp f110_6          ; 2 clocks
f010_5:
    nop                  ; 1 clock
    nop                  ; 1 clock
f010_6:
    out PORTD, r20       ; 1 clock
    rjmp f010_0          ; 2 clocks
;----------------------------------------------------------------
;OFF / ON / ON
f011_0:
    sbiw XH:XL, 0x01     ; 2 clocks
    brne f011_1          ; 2 clocks if jump, 1 clock if dont jump
    movw XH:XL, r5:r4    ; 1 clock
    rjmp f010_2          ; 2 clocks
f011_1:
    nop                  ; 1 clock
    nop                  ; 1 clock
f011_2:
    sbiw YH:YL, 0x01     ; 2 clocks
    brne f011_3          ; 2 clocks if jump, 1 clock if dont jump
    movw YH:YL, r11:r10  ; 1 clock
    rjmp f001_4          ; 2 clocks
f011_3:
    nop                  ; 1 clock
    nop                  ; 1 clock
f011_4:
    sbiw ZH:ZL, 0x01     ; 2 clocks
    brne f011_5          ; 2 clocks if jump, 1 clock if dont jump
    movw ZH:ZL, r15:r14  ; 1 clock
    rjmp f111_6          ; 2 clocks
f011_5:
    nop                  ; 1 clock
    nop                  ; 1 clock
f011_6:
    out PORTD, r21       ; 1 clock
    rjmp f011_0          ; 2 clocks
;----------------------------------------------------------------
;ON / OFF / OFF
f100_0:
    sbiw XH:XL, 0x01     ; 2 clocks
    brne f100_1          ; 2 clocks if jump, 1 clock if dont jump
    movw XH:XL, r3:r2    ; 1 clock
    rjmp f101_2          ; 2 clocks
f100_1:
    nop                  ; 1 clock
    nop                  ; 1 clock
f100_2:
    sbiw YH:YL, 0x01     ; 2 clocks
    brne f100_3          ; 2 clocks if jump, 1 clock if dont jump
    movw YH:YL, r9:r8    ; 1 clock
    rjmp f110_4          ; 2 clocks
f100_3:
    nop                  ; 1 clock
    nop                  ; 1 clock
f100_4:
    sbiw ZH:ZL, 0x01     ; 2 clocks
    brne f100_5          ; 2 clocks if jump, 1 clock if dont jump
    movw ZH:ZL, r17:r16  ; 1 clock
    rjmp f000_6          ; 2 clocks
f100_5:
    nop                  ; 1 clock
    nop                  ; 1 clock
f100_6:
    out PORTD, r22       ; 1 clock
    rjmp f100_0          ; 2 clocks
;----------------------------------------------------------------
;ON / OFF / ON
f101_0:
    sbiw XH:XL, 0x01     ; 2 clocks
    brne f101_1          ; 2 clocks if jump, 1 clock if dont jump
    movw XH:XL, r5:r4    ; 1 clock
    rjmp f100_2          ; 2 clocks
f101_1:
    nop                  ; 1 clock
    nop                  ; 1 clock
f101_2:
    sbiw YH:YL, 0x01     ; 2 clocks
    brne f101_3          ; 2 clocks if jump, 1 clock if dont jump
    movw YH:YL, r9:r8    ; 1 clock
    rjmp f111_4          ; 2 clocks
f101_3:
    nop                  ; 1 clock
    nop                  ; 1 clock
f101_4:
    sbiw ZH:ZL, 0x01     ; 2 clocks
    brne f101_5          ; 2 clocks if jump, 1 clock if dont jump
    movw ZH:ZL, r17:r16  ; 1 clock
    rjmp f001_6          ; 2 clocks
f101_5:
    nop                  ; 1 clock
    nop                  ; 1 clock
f101_6:
    out PORTD, r23       ; 1 clock
    rjmp f101_0          ; 2 clocks
;----------------------------------------------------------------
;ON / ON / OFF
f110_0:
    sbiw XH:XL, 0x01     ; 2 clocks
    brne f110_1          ; 2 clocks if jump, 1 clock if dont jump
    movw XH:XL, r3:r2    ; 1 clock
    rjmp f111_2          ; 2 clocks
f110_1:
    nop                  ; 1 clock
    nop                  ; 1 clock
f110_2:
    sbiw YH:YL, 0x01     ; 2 clocks
    brne f110_3          ; 2 clocks if jump, 1 clock if dont jump
    movw YH:YL, r11:r10  ; 1 clock
    rjmp f100_4          ; 2 clocks
f110_3:
    nop                  ; 1 clock
    nop                  ; 1 clock
f110_4:
    sbiw ZH:ZL, 0x01     ; 2 clocks
    brne f110_5          ; 2 clocks if jump, 1 clock if dont jump
    movw ZH:ZL, r17:r16  ; 1 clock
    rjmp f010_6          ; 2 clocks
f110_5:
    nop                  ; 1 clock
    nop                  ; 1 clock
f110_6:
    out PORTD, r24       ; 1 clock
    rjmp f110_0          ; 2 clocks
;----------------------------------------------------------------
;ON / ON / ON
f111_0:
    sbiw XH:XL, 0x01     ; 2 clocks
    brne f111_1          ; 2 clocks if jump, 1 clock if dont jump
    movw XH:XL, r5:r4    ; 1 clock
    rjmp f110_2          ; 2 clocks
f111_1:
    nop                  ; 1 clock
    nop                  ; 1 clock
f111_2:
    sbiw YH:YL, 0x01     ; 2 clocks
    brne f111_3          ; 2 clocks if jump, 1 clock if dont jump
    movw YH:YL, r11:r10  ; 1 clock
    rjmp f101_4          ; 2 clocks
f111_3:
    nop                  ; 1 clock
    nop                  ; 1 clock
f111_4:
    sbiw ZH:ZL, 0x01     ; 2 clocks
    brne f111_5          ; 2 clocks if jump, 1 clock if dont jump
    movw ZH:ZL, r17:r16  ; 1 clock
    rjmp f011_6          ; 2 clocks
f111_5:
    nop                  ; 1 clock
    nop                  ; 1 clock
f111_6:
    out PORTD, r25       ; 1 clock
    rjmp f111_0          ; 2 clocks
;----------------------------------------------------------------

usart_rxc:          ;USART RX Complete Handler

    push r17
    clr r17
    out PORTD, r17  ;turn all channels OFF asap
    push r16
    push YH
    push YL
    in r16, SREG
    push r16

    in r16, TIFR1   ;copy TIFR into r16
    sbrs r16, TOV1  ;is timer1 overflow flag set?
    rjmp label0     ;if it isn't then don't reset pointer

    clr r16
    out GPIOR0, r16 ;reset input buffer pointer

label0:

    ;clear timer1 value
    clr r16
    sts TCNT1H, r16
    sts TCNT1L, r16

    ;clear overflow flag
    ldi r16, (1 << TOV1)
    out TIFR1, r16

    ;Calculate actual SRAM address in Y register
    ldi YH, HIGH(inbuf)
    ldi YL, LOW(inbuf)
    in  r16, GPIOR0
    add YL, r16
    clr r16
    adc YH, r16

    ;Store received byte
    lds r16, UDR0
    st Y, r16

    ;increment and check GPIOR0
    in r16, GPIOR0
    inc r16
    cpi r16, 30
    in r17, SREG
    sbrs r17, SREG_C    ;skip clearing if flag C is set
    clr r16             ;clear GPIOR0 if >= 30
    out GPIOR0, r16     ;store incremented (or just cleared) value

    ;replace return address to main0
    in YH, SPH
    in YL, SPL

    ldi r16, HIGH(main0) ;set stack pointer to RAM end
    std Y + 6, r16
    ldi r16, LOW(main0)
    std Y + 7, r16

    pop r16
    out SREG, r16
    pop YL
    pop YH
    pop r16
    pop r17

    reti

;----------------------------------------------------------
;--- function to TX byte by pushing it to output buffer ---

send_r16:
    push YL
    push YH
    push r16
    push r17

    ;calculate actual address in output buffer
    ldi YH, HIGH(outbuf)
    ldi YL, LOW(outbuf)
    in  r17, GPIOR2
    add YL, r17
    clr r17
    adc YH, r17

    st Y, r16

    ;increment output buffer pointer GPIOR2
    in r17, GPIOR2
    inc r17
    out GPIOR2, r17

    pop r17
    pop r16
    pop YH
    pop YL
    ret

;--- function to calculate CRC-16/MODBUS checksum ---

calc_crc16:

;Poly  : 0x8005   x^16 + x^15 + x^2 + 1
;input YL:YH - pointer to buffer in the SRAM
;input R16 - buffer length
;output R16,R17 - L,H of CRC16 checksum

    push r18
    push r21
    push r22
    push r23
    push ZL
    push ZH
    push YL
    push YH

    tst r16
    breq crc16_label1
    mov r18, r16
    ldi r16, 0xff
    ldi r17, 0xff

crc16_label0:
    ld R22, Y+                     ;load byte from buffer to R21:R22
    mov R21, R16                   ;xor checksum with this byte
    eor R21, R22

    add R21, R21                   ;load byte from buffer to R21:R22 and multiply by 2 to get lookup table offset
    clr R22
    adc R22, R22

    ldi ZL, LOW(crc16table * 2)
    ldi ZH, HIGH(crc16table * 2)
    add ZL, R21                    ;R21:R22 = crc16table[R21:R22]
    adc ZH, R22
    lpm R22, Z+
    lpm R23, Z+

    mov R16, R17                   ;(R16:R17 >> 8) ^ R21:R22
    eor R16, R22
    mov R17, R23

    subi r18, 1
    brne crc16_label0

crc16_label1:
    pop YH
    pop YL
    pop ZH
    pop ZL
    pop r23
    pop r22
    pop r21
    pop r18
    ret

;---------------

store_to_eeprom:

    ;stores workbuf to eeprom

    push XH
    push XL
    push r16
    push r17

    cli                    ;disable interrupts during eeprom write

    ldi XH, HIGH(workbuf)
    ldi XL, LOW(workbuf)

    clr r16

ew0:
    sbic EECR, EEPE
    rjmp ew0
    ld r17, X
    out EEDR, r17          ;data to write
    clr r17
    out EEARH, r17
    out EEARL, r16         ;address where to write
    sbi EECR, EEMPE
    sbi EECR, EEPE         ;start to write

    adiw XH:XL, 0x01
    inc r16
    ldi r17, 21
    cp r16, r17
    brne ew0

    sei                    ;enable interrupts

    pop r17
    pop r16
    pop XL
    pop XH

    ret

;---------------

load_from_eeprom:
    ;sets r16 to 0 if crc is ok and copy 21 bytes from eeprom into workbuf
    ;sets r16 to 1 if crc is bad

    ;load eeprom into loadbuf

    push XH
    push XL
    push YH
    push YL
    push r17
    push r18

    cli                 ;disable interrupts

    ldi XH, HIGH(loadbuf)
    ldi XL, LOW(loadbuf)
    clr r16

er0:
    sbic EECR, EEPE
    rjmp er0
    clr r17
    out EEARH, r17
    out EEARL, r16      ;address to read from
    sbi EECR, EERE
    in r17, EEDR
    st X, r17
    adiw XH:XL, 0x01
    inc r16
    ldi r17, 21
    cp r16, r17
    brne er0

    ;check crc
    ldi r16, 19
    ldi YH, HIGH(loadbuf)
    ldi YL, LOW(loadbuf)
    call calc_crc16

    ldd r18, Y + 20
    cp r18, r16
    ldi r16, 0x01        ;load 0x01 (bad data result) into r16
    brne er1
    ldd r18, Y + 19
    cp r18, r17
    brne er1

    ;data is good, copy loadbuf to workbuf

er4:
    ldi XH, HIGH(workbuf)
    ldi XL, LOW(workbuf)
    ldi YH, HIGH(loadbuf)
    ldi YL, LOW(loadbuf)
    ldi r16, 21
er2:
    ld r17, Y
    st X, r17
    adiw XH:XL, 0x01
    adiw YH:YL, 0x01
    dec r16
    brne er2

    clr r16              ;load 0x00 (good data result) into r16

er1:
    sei                  ;enable interrupts

    pop r18
    pop r17
    pop YL
    pop YH
    pop XL
    pop XH

    ret

;---------------

crc16table:
.dw 0x0000, 0xC0C1, 0xC181, 0x0140, 0xC301, 0x03C0, 0x0280, 0xC241
.dw 0xC601, 0x06C0, 0x0780, 0xC741, 0x0500, 0xC5C1, 0xC481, 0x0440
.dw 0xCC01, 0x0CC0, 0x0D80, 0xCD41, 0x0F00, 0xCFC1, 0xCE81, 0x0E40
.dw 0x0A00, 0xCAC1, 0xCB81, 0x0B40, 0xC901, 0x09C0, 0x0880, 0xC841
.dw 0xD801, 0x18C0, 0x1980, 0xD941, 0x1B00, 0xDBC1, 0xDA81, 0x1A40
.dw 0x1E00, 0xDEC1, 0xDF81, 0x1F40, 0xDD01, 0x1DC0, 0x1C80, 0xDC41
.dw 0x1400, 0xD4C1, 0xD581, 0x1540, 0xD701, 0x17C0, 0x1680, 0xD641
.dw 0xD201, 0x12C0, 0x1380, 0xD341, 0x1100, 0xD1C1, 0xD081, 0x1040
.dw 0xF001, 0x30C0, 0x3180, 0xF141, 0x3300, 0xF3C1, 0xF281, 0x3240
.dw 0x3600, 0xF6C1, 0xF781, 0x3740, 0xF501, 0x35C0, 0x3480, 0xF441
.dw 0x3C00, 0xFCC1, 0xFD81, 0x3D40, 0xFF01, 0x3FC0, 0x3E80, 0xFE41
.dw 0xFA01, 0x3AC0, 0x3B80, 0xFB41, 0x3900, 0xF9C1, 0xF881, 0x3840
.dw 0x2800, 0xE8C1, 0xE981, 0x2940, 0xEB01, 0x2BC0, 0x2A80, 0xEA41
.dw 0xEE01, 0x2EC0, 0x2F80, 0xEF41, 0x2D00, 0xEDC1, 0xEC81, 0x2C40
.dw 0xE401, 0x24C0, 0x2580, 0xE541, 0x2700, 0xE7C1, 0xE681, 0x2640
.dw 0x2200, 0xE2C1, 0xE381, 0x2340, 0xE101, 0x21C0, 0x2080, 0xE041
.dw 0xA001, 0x60C0, 0x6180, 0xA141, 0x6300, 0xA3C1, 0xA281, 0x6240
.dw 0x6600, 0xA6C1, 0xA781, 0x6740, 0xA501, 0x65C0, 0x6480, 0xA441
.dw 0x6C00, 0xACC1, 0xAD81, 0x6D40, 0xAF01, 0x6FC0, 0x6E80, 0xAE41
.dw 0xAA01, 0x6AC0, 0x6B80, 0xAB41, 0x6900, 0xA9C1, 0xA881, 0x6840
.dw 0x7800, 0xB8C1, 0xB981, 0x7940, 0xBB01, 0x7BC0, 0x7A80, 0xBA41
.dw 0xBE01, 0x7EC0, 0x7F80, 0xBF41, 0x7D00, 0xBDC1, 0xBC81, 0x7C40
.dw 0xB401, 0x74C0, 0x7580, 0xB541, 0x7700, 0xB7C1, 0xB681, 0x7640
.dw 0x7200, 0xB2C1, 0xB381, 0x7340, 0xB101, 0x71C0, 0x7080, 0xB041
.dw 0x5000, 0x90C1, 0x9181, 0x5140, 0x9301, 0x53C0, 0x5280, 0x9241
.dw 0x9601, 0x56C0, 0x5780, 0x9741, 0x5500, 0x95C1, 0x9481, 0x5440
.dw 0x9C01, 0x5CC0, 0x5D80, 0x9D41, 0x5F00, 0x9FC1, 0x9E81, 0x5E40
.dw 0x5A00, 0x9AC1, 0x9B81, 0x5B40, 0x9901, 0x59C0, 0x5880, 0x9841
.dw 0x8801, 0x48C0, 0x4980, 0x8941, 0x4B00, 0x8BC1, 0x8A81, 0x4A40
.dw 0x4E00, 0x8EC1, 0x8F81, 0x4F40, 0x8D01, 0x4DC0, 0x4C80, 0x8C41
.dw 0x4400, 0x84C1, 0x8581, 0x4540, 0x8701, 0x47C0, 0x4680, 0x8641
.dw 0x8201, 0x42C0, 0x4380, 0x8341, 0x4100, 0x81C1, 0x8081, 0x4040


;----------------------------------
;
; *** UART commands ***
;
;  CRC algorithm used is CRC16/MODBUS, each TX/RX packet contains additional CRC bytes at end
;
;  Command 00 - PING PONG (00 40 BF)
;
;  Command 01 - SET FREQUENCIES, if ON == 0 then frequency is muted (off)
;  Format: (total 21 bytes)
;  01
;  DELAY F1 H/L
;  ON    F1 H/L
;  OFF   F1 H/L
;  DELAY F2 H/L
;  ON    F2 H/L
;  OFF   F2 H/L
;  DELAY F3 H/L
;  ON    F3 H/L
;  OFF   F3 H/L
;  CRC16
;
;  02 - STORE TO EEPROM (02 81 3E), stores current frequencies to eeprom
;
;  03 - LOAD FROM EEPROM (03 41 FF), loads frequencies from eeprom, this is done also at reset (startup)
;
;  Possible responses:
;  00 + CRC16 = OK, COMMAND EXECUTED
;  01 + CRC16 = BAD COMMAND (CRC ERROR)
;  02 + CRC16 = BAD DATA IN EEPROM (CRC ERROR)
