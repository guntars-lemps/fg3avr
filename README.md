Fg3avr is 3 channels frequency generator for arduino with ATMEGA328P mcu. It can be used for various purposes, for example, it can drive 3 phase motors or can be used for 3 phase AC generation

### Features ###

* Frequency outputs are digital, the pins used for output are D2, D3, D4
* Generator is driven by UART commads. UART pins used are default D0 and D1
* Each frequency has startup delay, 'on' period and 'off' period adjustable parameters. Also generation can be turned off independently for each channel
* Frequency parameters can be stored in eeprom and loaded from eeprom.
* At board power-up it checks if there are frequencies stored in eeprom. They are loaded from eeprom and generation starts automatically, no need to connect and setup by UART

### Capabilities ###

This board has capabilities below

* Min timing units 1
* Max timing units 65535
* CPU ticks per one time unit 21
* CPU ticks per one second 16000000

So this device has 1.3125 micro seconds resolution per one unit. Max frequency it is able to generate is 378 kHz

### UART commands

Each command contains additional CRC bytes at the end. The checksum algorithm used is CRC16/MODBUS.  
UART protocol now is upgraded to support 32 bit timing ranges, but this generator has limited timing resolution up to 16 bits. 
The UART speed is 19200 bps. All values use big endian byte ordering (highest byte comes first)

* Command 00 - PING PONG  
  Used to check if board is connected and alive
  
  |0x00|0x40|0xBF|  
  |---|---|---|
  
* Command 01 - SET FREQUENCIES  
  if ON period equals to 0 then frequency is muted (off)  
  Command contains 39 bytes. F1, F2, F3 - three frequencies  

  <table>
    <tr>
      <td>Command</td>
      <td>0x01</td>        
    </tr>
    <tr>
      <td>DELAY for F1</td>
      <td>32 bit value</td>
    </tr>
    <tr>
      <td>ON period for F1</td>
      <td>32 bit value</td>
    </tr>
    <tr>
      <td>OFF period for F1</td>
      <td>32 bit value</td>
    </tr>
    <tr>
      <td>DELAY for F2</td>
      <td>32 bit value</td>
    </tr>
    <tr>
      <td>ON period for F2</td>
      <td>32 bit value</td>
    </tr>
    <tr>
      <td>OFF period for F2</td>
      <td>32 bit value</td>
    </tr>
    <tr>
      <td>DELAY for F3</td>
      <td>32 bit value</td>
    </tr>
    <tr>
      <td>ON period for F3</td>
      <td>32 bit value</td>
    </tr>
    <tr>
      <td>OFF period for F3</td>
      <td>32 bit value</td>
    </tr>
    <tr>
      <td>CRC16 Checksum</td>
      <td>16 bits</td>
    </tr>
  </table>
   
* Command 02 - STORE TO EEPROM  
  Stores current frequencies to eeprom
  |0x02|0x81|0x3E|
  |---|---|---|

* Command 03 - LOAD FROM EEPROM  
  Loads frequencies from eeprom, this is done also at the reset (startup)
  |0x03|0x41|0xFF|
  |---|---|---|

* Command 04 - CHECK CAPABILITIES  
  Request device capabilities (timing range, ticks per one unit, cpu ticks per second)
  |0x04|0x83|0xBE|
  |---|---|---|

* Possible arduino responses:  
  
  OK, COMMAND EXECUTED
  <table>
<tr>
  <td>0x00</td><td>CRC checksum 16 bits</td>
</tr>
</table>

  BAD COMMAND (CRC ERROR)
  <table>
<tr>
  <td>0x01</td><td>CRC checksum 16 bits</td>
</tr>
</table>

  BAD DATA IN EEPROM (CRC ERROR)
  <table>
<tr>
  <td>0x02</td><td>CRC checksum 16 bits</td>
</tr>
</table>

  CAPABILITIES (Response to command 04)
  <table>
    <tr>
      <td>Command</td><td>0x04</td>
    </tr>
    <tr>
      <td>Min units 1</td><td>0x00</td><td>0x00</td><td>0x00</td><td>0x01</td>
    </tr>  
    <tr>
      <td>Max units 65536</td><td>0x00</td><td>0x00</td><td>0xff</td><td>0xff</td>
    </tr>  
    <tr>
      <td>Ticks per one unit 21</td><td>0x00</td><td>0x00</td><td>0x00</td><td>0x15</td>
    </tr>  
    <tr>
      <td>CPU ticks per one second 16000000</td><td>0x00</td><td>0xf4</td><td>0x24</td><td>0x00</td>
    </tr>  
    <tr>
      <td>CRC 16 bits</td><td>0x06</td><td>0x17</td>
    </tr>  
  </table>
