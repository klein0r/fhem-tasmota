# Tasmota FHEM Module

**DEPRECATED - PLEASE USE MQTT2_DEVICE INSTEAD**

----

This module extends the default MQTT_Device of FHEM, to make the integration of [Tasmota](https://github.com/arendst/Sonoff-Tasmota/) devices (like Sonoff) much easier.

- All topics will be subscribed automatically
- JSON messages with multiple information are automatically splitted into separate readings
- You can use set ... cmd syntax to configure your Tasmota device without any knowledge about the mqtt topics

## Installation

```
update add https://raw.githubusercontent.com/klein0r/fhem-tasmota/master/controls_tasmota.txt
update check tasmota
update all tasmota
```

## License

MIT License

Copyright (c) 2017 Matthias Kleine

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
