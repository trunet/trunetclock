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

void floatToBytes(float number, byte *bytes) {
  float *numberPointer;
  byte i;
  unsigned char *byte = (unsigned char *) &number;
  
  for (i=0; i<sizeof(float); i++) {
    bytes[i] = *byte;
    byte++;
  }
}

float bytesToFloat(char *bytes) {
  float *aPointFloat;
  aPointFloat = (float *)bytes;
  return *aPointFloat;
}

void longToBytes(unsigned long number, byte *bytes) {
  long *numberPointer;
  byte i;
  unsigned char *byte = (unsigned char *) &number;
  
  for (i=0; i<sizeof(long); i++) {
    bytes[i] = *byte;
    byte++;
  }
}

long bytesToLong(byte *bytes) {
  long *aPointLong;
  aPointLong = (long *)bytes;
  return *aPointLong;
}

void intToBytes(int number, char *bytes) {
  int *numberPointer;
  byte i;
  unsigned char *byte = (unsigned char *) &number;
  
  for (i=0; i<sizeof(int); i++) {
    bytes[i] = *byte;
    byte++;
  }
}

int bytesToInt(char *bytes) {
  int *aPointInt;
  aPointInt = (int *)bytes;
  return *aPointInt;
}

char *ftoa(char *a, double f, int precision)
{
  long p[] = {0,10,100,1000,10000,100000,1000000,10000000,100000000};
  
  char *ret = a;
  long heiltal = (long)f;
  itoa(heiltal, a, 10);
  while (*a != '\0') a++;
  *a++ = '.';
  long desimal = abs((long)((f - heiltal) * p[precision]));
  itoa(desimal, a, 10);
  return ret;
}
