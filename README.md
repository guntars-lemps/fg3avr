Fg3avr is a 3 independent frequencies generator for arduino which can be used for multiple purposes. 

*Features*

* Frequencies outputs are digital, the pins used for output are D2,D3,D4
* generator is driven by UART commads. The UART pins are default D0 and D1
* The frequencies are adjustable by startup delay, 'off' period and 'on' period
* The generation can be turned on and off independently for each channel
* Current frequencies can be stored in eeprom and loaded from eeprom.
* At board power-up it checks if there are frequencies stored in eeprom. They are loaded from eeprom and generation starts automaticly, no need to connect and use UART

*UART commands*
