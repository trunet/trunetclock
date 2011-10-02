/*
Copyright (C) 2011 Wagner Sartori Junior <wsartori@gmail.com>
http://www.wsartori.com

This file is part of TrunetClock.

TrunetClock program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <EEPROM.h>
#include <XBee.h>
#include <Wire.h>
#include <Time.h>
#include <DS3231RTC.h>
#include <ht1632c.h>

#include "conversions.h"

#define MAX_MSG_LEN 100
char msgLine[8][MAX_MSG_LEN];
byte scrolling[2];
char timezone;
byte brightness;
byte datetimetemp;

bool isOn = true; // Blinky : for seconds passing
unsigned long lastBlinky = 0;
unsigned long lastTempDateswap = 0;
bool printTemp = true;

int line1Pos = 0;
int line2Pos = 0;
int line1X = 63;
int line2X = 63;
bool line1ScrolledOnce = false;
bool line2ScrolledOnce = false;

#define MAX_PAYLOAD_LEN 4
byte payload[MAX_PAYLOAD_LEN];
//RX
XBee xbee = XBee();
XBeeResponse response = XBeeResponse();
ZBRxResponse rx = ZBRxResponse();
//TX
ZBTxStatusResponse txStatus = ZBTxStatusResponse();

ht1632c ledMatrix = ht1632c(PORTB, 2, 3, 5, 4, GEOM_32x16, 2);

// EEPROM address mapping
//    0-799: msgLine
//     1000: scrolling packet row 1
//     1001: scrolling packet row 2
//     1002: timezone
//     1003: date/time/temp packet
//     1004: display brightness

void setup() {
  byte i;
  
  xbee.begin(38400);
  
  // Set initial EEPROM values
  /*
  EEPROM.write(0, '\0');
  EEPROM.write(100, '\0');
  EEPROM.write(200, '\0');
  EEPROM.write(300, '\0');
  EEPROM.write(400, '\0');
  EEPROM.write(500, '\0');
  EEPROM.write(600, '\0');
  EEPROM.write(700, '\0');
  EEPROM.write(1000, 0);
  EEPROM.write(1001, 1);
  EEPROM.write(1002, 0xfd);
  EEPROM.write(1003, 0xbd);
  EEPROM.write(1004, 15);
  */
  
  for (byte line=0; line<8; line++)
    for (i=0; i<MAX_MSG_LEN; i++)
      msgLine[line][i] = EEPROM.read(i+(line*100));
  scrolling[0] = EEPROM.read(1000);
  scrolling[1] = EEPROM.read(1001);
  timezone = EEPROM.read(1002);
  datetimetemp = EEPROM.read(1003);
  brightness = EEPROM.read(1004);
  
  Wire.begin();
  setSyncProvider(RTC.get);
  
  ledMatrix.clear();
  ledMatrix.pwm(brightness);
}

void loop() {
  byte i;
  
  xbee.readPacket();
  if (xbee.getResponse().isAvailable()) {
    if (xbee.getResponse().getApiId() == ZB_RX_RESPONSE) {
      xbee.getResponse().getZBRxResponse(rx);
      ZBTxRequest zbTx = ZBTxRequest(rx.getRemoteAddress64(), payload, sizeof(payload));
      switch (rx.getData(0)) {
        // 0x01: Timestamp from DS3231 RTC
        case 0x01:
          longToBytes(now(), payload);
          xbee.send(zbTx);
          break;
        // 0x02: Temperature from DS3231 RTC
        case 0x02:
          floatToBytes(RTC.getTemp(), payload);
          xbee.send(zbTx);
          break;
        // 0x50: Set DS3231 using timestamp
        case 0x50:
          byte tmpByteTimestamp[4];
          time_t tmpTimestamp;
          for (i=0; i<4; i++)
            tmpByteTimestamp[i] = rx.getData(i+1);
          tmpTimestamp = bytesToLong(tmpByteTimestamp);
          RTC.set(tmpTimestamp);
          setTime(tmpTimestamp);
          break;
        // 0x51: Save message X on memory
        case 0x51:
          byte msgNumber;
          msgNumber = (bitRead(rx.getData(1), 2) * 4) + (bitRead(rx.getData(1), 1) * 2) + (bitRead(rx.getData(1), 0));
          for (i=0; i<=rx.getDataLength(); i++) {
            if (!(i+2 > MAX_MSG_LEN)) {
              msgLine[msgNumber][i] = rx.getData(i+2);
              if (bitRead(rx.getData(1), 3) == 1)
                EEPROM.write(i + (msgNumber*100), msgLine[msgNumber][i]);
            }
          }
          msgLine[msgNumber][i+1] = '\0';
          if (bitRead(rx.getData(1), 3) == 1)
            EEPROM.write(i + 1 + (msgNumber*100), msgLine[msgNumber][i+1]);
          break;
        // 0x52: Scrool control
        case 0x52:
          scrolling[bitRead(rx.getData(1), 0)] = rx.getData(1);
          EEPROM.write(1000 + bitRead(rx.getData(1), 0), rx.getData(1));
          if (bitRead(rx.getData(1), 0) == 0) {
            line1X = 63;
            line1Pos = 0;
            line1ScrolledOnce = false;
          } else {
            line2X = 63;
            line2Pos = 0;
            line2ScrolledOnce = false;
          }
          break;
        // 0x53: Show Date/Time 
        case 0x53:
          datetimetemp = rx.getData(1);
          EEPROM.write(1003, datetimetemp);
          break;
        // 0x54: Set display brightness 0-15
        case 0x54:
          brightness = rx.getData(1);
          if (!((brightness >= 0) && (brightness <= 15)))
            brightness = 15;  
          ledMatrix.pwm(brightness);
          EEPROM.write(1004, brightness);
          break;
        // 0x55: Set timezone (-12 to 12)
        case 0x55:
          timezone = rx.getData(1);
          EEPROM.write(1002, timezone);
          break;
      }
    }
  }

  
  printDateTime();
  scroll();
}

void scroll() {
  byte color_line1 = BLACK;
  byte color_line2 = BLACK;
  
  if (brightness != 0) {
  
    // Set line 1 color
    if (bitRead(scrolling[0], 4) == 1 && bitRead(scrolling[0], 5) == 1) {
      color_line1 = ORANGE;
    } else if (bitRead(scrolling[0], 4) == 1) {
      color_line1 = RED;
    } else if (bitRead(scrolling[0], 5) == 1) {
      color_line1 = GREEN;
    }
  
    // Set line 2 color  
    if (bitRead(scrolling[1], 4) == 1 && bitRead(scrolling[1], 5) == 1) {
      color_line2 = ORANGE;
    } else if (bitRead(scrolling[1], 4) == 1) {
      color_line2 = RED;
    } else if (bitRead(scrolling[1], 5) == 1) {
      color_line2 = GREEN;
    }
    
    if (bitRead(scrolling[0], 6) == 1) {
      if ((bitRead(scrolling[0], 7) == 0) || (bitRead(scrolling[0], 7) == 1 && !line1ScrolledOnce)) {
        byte msgNumber;
        msgNumber = (bitRead(scrolling[0], 3) * 4) + (bitRead(scrolling[0], 2) * 2) + (bitRead(scrolling[0], 1));
        int len1 = strlen(msgLine[msgNumber]) + 1;      
        if (line1X > - (len1 * 6)) {
          if (line1Pos < len1) {
            ledMatrix.putchar(line1X + 6 * line1Pos, 0, msgLine[msgNumber][line1Pos], color_line1);
            line1Pos++;
          } else {
            delay(10);
            line1Pos = 0;
            line1X--;
          }
        } else {
          line1ScrolledOnce = true;
          line1X = 63;
        }
      }
    }
    
    if (bitRead(scrolling[1], 6) == 1) {
      if ((bitRead(scrolling[1], 7) == 0) || (bitRead(scrolling[1], 7) == 1 && !line2ScrolledOnce)) {
        byte msgNumber;
        msgNumber = (bitRead(scrolling[1], 3) * 4) + (bitRead(scrolling[1], 2) * 2) + (bitRead(scrolling[1], 1));
        int len2 = strlen(msgLine[msgNumber]) + 1;      
        if (line2X > - (len2 * 6)) {
          if (line2Pos < len2) {
            ledMatrix.putchar(line2X + 6 * line2Pos, 0, msgLine[msgNumber][line2Pos], color_line2);
            line2Pos++;
          } else {
            delay(10);
            line2Pos = 0;
            line2X--;
          }
        } else {
          line2ScrolledOnce = true;
          line2X = 63;
        }
      }
    }
    
  } else {
    ledMatrix.clear();
  }
}

void printDateTime() {
  char tmp[20];
  byte line = 0;
  byte color_date = BLACK;
  byte color_time = BLACK;
  int temp, temp1;
  
  if (brightness != 0) {
  
    if (bitRead(datetimetemp, 4) == 1)
      line = 8;
    
    // Set date color
    if (bitRead(datetimetemp, 0) == 1 && bitRead(datetimetemp, 1) == 1) {
      color_date = ORANGE;
    } else if (bitRead(datetimetemp, 0) == 1) {
      color_date = RED;
    } else if (bitRead(datetimetemp, 1) == 1) {
      color_date = GREEN;
    }
  
    // Set time color  
    if (bitRead(datetimetemp, 2) == 1 && bitRead(datetimetemp, 3) == 1) {
      color_time = ORANGE;
    } else if (bitRead(datetimetemp, 2) == 1) {
      color_time = RED;
    } else if (bitRead(datetimetemp, 3) == 1) {
      color_time = GREEN;
    }
  
    if (millis() - lastBlinky >= 1000 || lastBlinky == 0) {
      lastBlinky = millis();
      
      if (!((bitRead(datetimetemp, 5) == 0) && (bitRead(datetimetemp, 6) == 0) && (bitRead(datetimetemp, 7) == 0))) {
        byte swapEach = (bitRead(datetimetemp, 7) * 4) + (bitRead(datetimetemp, 6) * 2) + (bitRead(datetimetemp, 5));
        if (millis() - lastTempDateswap >= (swapEach * 1000) || lastTempDateswap == 0) {
          lastTempDateswap = millis();
          printTemp = !printTemp;
        }
      } else {
        printTemp = false;
      }
      
      time_t utc, local;

      utc = now();
      local = utc + timezone *60 * 60;  // Local time 8 hours behind UTC.
        
      if (isOn) {
        isOn = false;
        if (printTemp) {
          temp = RTC.getTemp();
          temp1 = (temp - (int)temp) * 100;
          sprintf(tmp, "%0d.%d\\C %02d:%02d", (int)temp, temp1, hour(local), minute());
        } else {
          sprintf(tmp, "%02d/%02d  %02d:%02d", day(), month(), hour(local), minute());
        }
      } else {
        isOn = true;
        if (printTemp) {
          temp = RTC.getTemp();
          temp1 = (temp - (int)temp) * 100;
          sprintf(tmp, "%0d.%d\\C %02d %02d", (int)temp, temp1, hour(local), minute());
        } else {
          sprintf(tmp, "%02d/%02d  %02d %02d", day(), month(), hour(local), minute());
        }
      }
    
      for (int i = 0; i < strlen(tmp); i++) {
        if (i<7) {
         ledMatrix.putchar(5*i,  line, tmp[i], color_date);
        } else {
         ledMatrix.putchar(5*i,  line, tmp[i], color_time);
        }
      }
    }
  } else {
    ledMatrix.clear();
  }
}

