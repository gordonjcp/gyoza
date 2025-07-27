// Simple Arduino Sample Looper
// Copyright 2010 Gordon JC Pearce
// GPL V3 applies, please see http://www.gnu.org/licenses/gpl.html

// PWM playback code based on Martin Nawrath's
// Arduino DDS Sinewave Generator

// Portions of the code based on nekobee
// This will require changes to run directly as a MIDI synth,
// or something like ALSABridge to interface to the serial port

#include "avr/pgmspace.h"
#include "wave.h"
// handy macros for clearing or setting bits
#define cbi(sfr, bit) (_SFR_BYTE(sfr) &= ~_BV(bit))
#define sbi(sfr, bit) (_SFR_BYTE(sfr) |= _BV(bit))

PROGMEM float pitchtable[] = {
  8.18, 8.66, 9.18, 9.72, 10.30, 10.91, 11.56, 12.25, 12.98, 13.75, 14.57, 15.43, 16.35, 17.32, 18.35, 19.45, 20.60, 21.83, 23.12, 24.50, 25.96, 27.50, 29.14, 30.87, 32.70, 34.65, 36.71,
  38.89, 41.20, 43.65, 46.25, 49.00, 51.91, 55.00, 58.27, 61.74, 65.41, 69.30, 73.42, 77.78, 82.41, 87.31, 92.50, 98.00, 103.83, 110.00, 116.54, 123.47, 130.81, 138.59, 146.83, 155.56,
  164.81, 174.61, 185.00, 196.00, 207.65, 220.00, 233.08, 246.94, 261.63, 277.18, 293.66, 311.13, 329.63, 349.23, 369.99, 392.00, 415.30, 440.00, 466.16, 493.88, 523.25, 554.37, 587.33,
  622.25, 659.26, 698.46, 739.99, 783.99, 830.61, 880.00, 932.33, 987.77, 1046.50, 1108.73, 1174.66, 1244.51, 1318.51, 1396.91, 1479.98, 1567.98, 1661.22, 1760.00, 1864.66, 1975.53,
  2093.00, 2217.46, 2349.32, 2489.02, 2637.02, 2793.83, 2959.96, 3135.96, 3322.44, 3520.00, 3729.31, 3951.07, 4186.01, 4434.92, 4698.64, 4978.03, 5274.04, 5587.65, 5919.91, 6271.93,
  6644.88, 7040.00, 7458.62, 7902.13, 8372.02, 8869.84, 9397.27, 9956.06, 10548.08, 11175.30, 11839.82, 12543.85
};
  
// Martin's code has both, not sure how it was measured
// the difference in tuning is tiny
// const double refclk=31372.549;  // =16MHz / 510
const double refclk=31376.6;      // measured

// variables used inside interrupt service declared as voilatile
volatile byte icnt;               // var inside interrupt
volatile byte icnt1;              // var inside interrupt
volatile byte do_update;               // count interrupts
volatile byte gain;               // output level
volatile unsigned long s_ptr;
volatile int s_tword;
volatile int sample;
volatile int out;

int bitmask=0x4fff;
byte bitshift=0;
byte bitamt = 0;
byte mix;

// stuff outside the interrupt handler needn't be volatile
double freq;    // note frequency

byte st, p1, p2;  // MIDI bytes

void setup() {
  Serial.begin(57600);
  Serial.println("looper");
  // set up I/O
  pinMode(13, OUTPUT);    // gate LED
  pinMode(11, OUTPUT);    // PWM output
  digitalWrite(13, LOW);  // LED off

  Setup_timer2();
  cbi(TIMSK0, TOIE0);    // timer0 int off
  sbi(TIMSK2, TOIE2);    // timer2 int on
}

void loop() {
  while(1) {
    // are we ready to do an update?
    if (do_update) {
      do_update = 0;
      // got a message?
      st = Serial.read();
      if (st != 0xff) {
        // if it's note on or note off
        // do this rather crappy thing to get note and velocity
        if (st == 0x80 || st == 0x90 || st == 0xb0) {
          do {
            p1 = Serial.read();
          } while (p1 == 0xff);
          do {
            p2 = Serial.read();
          } while (p2 == 0xff);
        }
        if (st == 0xb0) {
           switch(p1) {
              case 41: bitshift = p2 & 7;bitmask = 0x4fff ^ (bitamt<< bitshift);
                  break;
              case 23: { 
                  int i;
                  bitamt = 0;
               for (i=0; i<7; i++) {   
                  bitamt <<= 1;
                   bitamt |= (p2 & 1);

                  p2 >>=1;
               }
               Serial.println(bitamt, HEX);
              bitmask = 0x4fff ^ (bitamt << bitshift);
                  break;
              }
              case 29:
                  mix = p2; break;
           }
              
        }
        if ((st == 0x90 && p2 == 0) || st == 0x80) {
          // note off
          digitalWrite(13, LOW);  // LED off
        }
        
        if (st==0x90 && p2 > 0 && p1 >=60) {
          digitalWrite(13, HIGH); // LED on
          sample = (p1-60)*3072;
          s_ptr = 0;
          s_tword=126;
        }
        
      }  // end of serial processing
      
      // process updates
      
      // calculate DDS phase offset
      //tword_m = pow(2,32)*freq/refclk; 
     
     
      //Serial.println((float)s_ptr);
 
    }  // end of control update
  }
}

void Setup_timer2() {
  // Timer2 Clock Prescaler to : 1
  sbi (TCCR2B, CS20);
  cbi (TCCR2B, CS21);
  cbi (TCCR2B, CS22);

  // Timer2 PWM Mode set to Phase Correct PWM
  cbi (TCCR2A, COM2A0);  // clear Compare Match
  sbi (TCCR2A, COM2A1);

  sbi (TCCR2A, WGM20);  // Mode 1  / Phase Correct PWM
  cbi (TCCR2A, WGM21);
  cbi (TCCR2B, WGM22);
}

ISR(TIMER2_OVF_vect) {
	// internal timer
	if(icnt1++ > 31) { // slightly faster than 1ms
		do_update=1;
		icnt1=0;
	}   
	
  out = 0;
	// calculate the sample output
	// bitmask contains the "bend"
	// mix sets the proportion of "bent" to clean output
	out += (mix*pgm_read_byte_near(wave+sample+(((s_ptr>>8) & bitmask))))>>7;
	out += ((127-mix)*pgm_read_byte_near(wave+sample+(s_ptr>>8)))>>7;

//out = pgm_read_byte_near(wave+sample+(s_ptr>>8));

/*
	// DC restore and clip output
	out += 127;
	out >>=1;
*/
	if (out<0) { out=0; digitalWrite(13, LOW); }
	if (out>0xff) { out=0xff; digitalWrite(13, LOW); }

	OCR2A = out;

	s_ptr += s_tword;
	if (s_ptr>786175) s_tword=0; 
}

/* vim: set noexpandtab ai ts=4 sw=4 tw=4: */
