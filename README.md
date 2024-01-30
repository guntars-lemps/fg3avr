Fg3avr is 3 channels frequency generator for arduino (or any other board with ATMEGA328P) which can be used for multiple purposes. 

### Features

* Frequencies outputs are digital, the pins used for output are D2, D3, D4
* Generator is driven by UART commads. The UART pins are default D0 and D1
* The frequencies are adjustable by startup delay, 'off' period and 'on' period
* The generation can be turned on and off independently for each channel
* Current frequencies can be stored in eeprom and loaded from eeprom.
* At board power-up it checks if there are frequencies stored in eeprom. They are loaded from eeprom and generation starts automaticly, no need to connect and use UART

### UART commands

Each command contains additional CRC bytes at the end. The checksum algorithm used is CRC16/MODBUS.  
All timings are 16 bit values (2 bytes). These timing values are measured in time units of 21/16000000 seconds, that is 1.3125 micro seconds per one unit.   
The UART speed is 19200 bps.   

* Command 00 - PING PONG  
  Used to check if board is connected and alive
  
  |0x00|0x40|0xBF|  
  |---|---|---|
  
* Command 01 - SET FREQUENCIES  
  if ON period equals to 0 then frequency is muted (off)  
  Command contains 21 bytes. F1, F2, F3 - three frequencies  

<table>
<tr>
     <td>   </td>
    <td>
        
|0x01|
|---|
        
</tr>
<tr>
    <td>DELAY for F1</td>
    <td>
        
|H byte |L byte|
|---|---|

</tr>
<tr>
    <td>ON period for F1</td>
    <td>
        
|H byte |L byte|
|---|---|

</tr>
<tr>
    <td>OFF period for F1</td>
    <td>
        
|H byte |L byte|
|---|---|

</tr>
<tr>
    <td>DELAY for F2</td>
    <td>
        
|H byte |L byte|
|---|---|

</tr>
<tr>
    <td>ON period for F2</td>
    <td>
        
|H byte |L byte|
|---|---|

</tr>
<tr>
    <td>OFF period for F2</td>
    <td>
        
|H byte |L byte|
|---|---|

</tr>
<tr>
    <td>DELAY for F3</td>
    <td>
        
|H byte |L byte|
|---|---|

</tr>
<tr>
    <td>ON period for F3</td>
    <td>
        
|H byte |L byte|
|---|---|

</tr>
<tr>
    <td>OFF period for F3</td>
    <td>
        
|H byte |L byte|
|---|---|

</tr>

<tr>
    <td>CRC16 Checksum</td>
    <td>
        
|H byte of CRC|L byte of CRC|
|---|---|

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

* Possible responses from arduino:  
  All respones are 3 byte long
  
  OK, COMMAND EXECUTED
  |0x00|CRC16 H byte|CRC16 L byte|
  |---|---|---|

  BAD COMMAND (CRC ERROR)
  |0x01|CRC16 H byte|CRC16 L byte|
  |---|---|---|

  BAD DATA IN EEPROM (CRC ERROR)
  |0x01|CRC16 H byte|CRC16 L byte|
  |---|---|---|
