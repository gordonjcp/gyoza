// Simple Arduino Sample Looper
// Copyright 2010 Gordon JC Pearce
// GPL V3 applies, please see http://www.gnu.org/licenses/gpl.html

// PWM playback code based on Martin Nawrath's
// Arduino DDS Sinewave Generator

// Portions of the code based on nekobee

// Wire a pair 2.2k resistors between pin 3 and pin 11, and the audio input of your amp.


#include "avr/pgmspace.h"
#include "drums.h"
// handy macros for clearing or setting bits
#define cbi(sfr, bit) (_SFR_BYTE(sfr) &= ~_BV(bit))
#define sbi(sfr, bit) (_SFR_BYTE(sfr) |= _BV(bit))

PROGMEM  prog_uchar sine256[]  = {
  127,130,133,136,139,143,146,149,152,155,158,161,164,167,170,173,176,178,181,184,187,190,192,195,198,200,203,205,208,210,212,215,217,219,221,223,225,227,229,231,233,234,236,238,239,240,
  242,243,244,245,247,248,249,249,250,251,252,252,253,253,253,254,254,254,254,254,254,254,253,253,253,252,252,251,250,249,249,248,247,245,244,243,242,240,239,238,236,234,233,231,229,227,225,223,
  221,219,217,215,212,210,208,205,203,200,198,195,192,190,187,184,181,178,176,173,170,167,164,161,158,155,152,149,146,143,139,136,133,130,127,124,121,118,115,111,108,105,102,99,96,93,90,87,84,81,78,
  76,73,70,67,64,62,59,56,54,51,49,46,44,42,39,37,35,33,31,29,27,25,23,21,20,18,
16,15,14,12,11,10,9,7,6,5,5,4,3,2,2,1,1,1,0,0,0,0,0,0,0,1,1,1,2,2,3,4,5,5,6,7,9,
10,11,12,14,15,16,18,20,21,23,25,27,29,31,
  33,35,37,39,42,44,46,49,51,54,56,59,62,64,67,70,73,76,78,81,84,87,90,93,96,99,
102,105,108,111,115,118,121,124
};

PROGMEM float pitchtable[] = {
  8.18, 8.66, 9.18, 9.72, 10.30, 10.91, 11.56, 12.25, 12.98, 13.75, 14.57, 15.43, 16.35, 17.32, 18.35, 19.45, 20.60, 21.83, 23.12, 24.50, 25.96, 27.50, 29.14, 30.87, 32.70, 34.65, 36.71,
  38.89, 41.20, 43.65, 46.25, 49.00, 51.91, 55.00, 58.27, 61.74, 65.41, 69.30, 73.42, 77.78, 82.41, 87.31, 92.50, 98.00, 103.83, 110.00, 116.54, 123.47, 130.81, 138.59, 146.83, 155.56,
  164.81, 174.61, 185.00, 196.00, 207.65, 220.00, 233.08, 246.94, 261.63, 277.18, 293.66, 311.13, 329.63, 349.23, 369.99, 392.00, 415.30, 440.00, 466.16, 493.88, 523.25, 554.37, 587.33,
  622.25, 659.26, 698.46, 739.99, 783.99, 830.61, 880.00, 932.33, 987.77, 1046.50, 1108.73, 1174.66, 1244.51, 1318.51, 1396.91, 1479.98, 1567.98, 1661.22, 1760.00, 1864.66, 1975.53
};
  
// Martin's code has both, not sure how it was measured
// the difference in tuning is tiny
// const double refclk=31372.549;  // =16MHz / 510
const double refclk=31376.6;      // measured

// variables used inside interrupt service declared as voilatile
volatile byte icnt;               // var inside interrupt
volatile byte icnt1;              // var inside interrupt
volatile byte do_update;               // count interrupts
volatile unsigned long s_ptr1, s_ptr2, s_ptr3;
volatile int out;

byte s_tword1, s_tword2, s_tword3;
unsigned int sample;

volatile unsigned long phaccu;   // phase accumulator
volatile unsigned long tword_m;   // dds tuning word

int d1, d2, hp, hp2;

int i_cutoff, i_res, gain;


int tempo_ct=0;
int step=0;

//char drums[] = {1,0,8,0, 3,0,8,0, 1,0,8,0, 3,0,8,0};
//char drums[] = {1,0,8,8, 4,0,8,8, 9,0,8,8, 4,0,8,8};
char drums[] = {1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0};
int run = 0;

void setup() {
	int i;
	randomSeed(analogRead(5));
	//Serial.begin(57600);
	//Serial.println("looper");
	// set up I/O
	DDRB = 0x3f; // all high except 6 and 7
	DDRD = 0x7f; // all high except RXD and PCINT18

	PORTB = 0x00;   // blank out port
	PORTD = 0x80;   // pull up button

	Setup_timer2();
	cbi(TIMSK0, TOIE0);   // timer0 int off
	sbi(TIMSK2, TOIE2);   // timer2 int on
	
	sbi(PCICR, PCIE2);	  // pin change interrupt
	sbi(PCMSK2, PCINT23);
	
	run = PIND & 0x80;
	
}

void loop() {
    // are we ready to do an update?
	if (do_update) {	// every 1ms the timer goes off
		do_update = 0;
		i_res=100;
		i_cutoff = analogRead(0)/4;
		// blink LED on beat
		if (!(step & 0x03)) {
			//if (tempo_ct < (step?2:15))  digitalWrite(13, HIGH); else digitalWrite(13, LOW);
			if (tempo_ct < (step?2:15))  PORTB = PORTB | 0x20; else PORTB = PORTB & 0xdf;

		}
		if (tempo_ct == 0)  PORTD = PORTD | 0x04; else PORTD = PORTD & 0xfb;
		if (run) tempo_ct++;

		// play one beat
		// tempo is 7500/bpm for straight semiquavers
		if (tempo_ct > (3750/127) ) {
			tempo_ct=0;
			PORTD = PORTD | 0x0c;
			
			// trigger drum sounds
			if (drums[step] & 1) {
				s_tword1=16;
				s_ptr1 = 0;
			}
			if (drums[step] & 2) {
				s_tword2=15;
				s_ptr2 = 0;
				sample = 5461;
			}
			if (drums[step] & 4) {
				s_tword2=15;
				s_ptr2 = 0;
				sample = 10922;
			}
			if (drums[step] & 8) {
				s_tword2=15;
				s_ptr2 = 0;
				sample = 16383;
			}
			step++;
			if (step>15) step=0;
		}
    }  // end of control update
}

void Setup_timer2() {
  // Timer2 Clock Prescaler to : 1
  sbi (TCCR2B, CS20);
  cbi (TCCR2B, CS21);
  cbi (TCCR2B, CS22);

  // Timer 2 PWM A on pin 11
  cbi (TCCR2A, COM2A0);  // clear Compare Match
  sbi (TCCR2A, COM2A1);

  // Timer 2 PWM B on pin 3
  cbi (TCCR2A, COM2B0);  // clear Compare Match
  sbi (TCCR2A, COM2B1);

  sbi (TCCR2A, WGM20);  // Mode 1  / Phase Correct PWM
  cbi (TCCR2A, WGM21);
  cbi (TCCR2B, WGM22);
}

ISR(PCINT2_vect) {
	run = (PIND & 0x80);
	step = 0;
	tempo_ct = 0;
}

#define CLAMP(x, l, h) (((x) > (h)) ? (h) : (((x) < (l)) ? (l) : (x)))
#define CLIP(x) (((x) > 255) ? 255 : (((x) < -255) ? 255 : (x)))


ISR(TIMER2_OVF_vect) {
	// internal timer
	if(icnt1++ > 127) { // slightly faster than 1ms
		do_update=1;
		icnt1=0;
	}   

	// play sample
	out = pgm_read_byte_near(wave+(s_ptr1>>4));   // bass
	out += pgm_read_byte_near(wave+sample+(s_ptr2>>4)); // snare
	//out = ((s_gain*out)>>8)-(s_gain>>1)+127;
	// clip
	out = out >> 1;

	
	// filter
	d2 = CLIP(d2 + ((i_cutoff*d1)>>8));
	hp = CLIP(out - d2 - ((d1*i_res)>>8));
	d1 = CLIP(((i_cutoff*hp)>>8) + d1);
	out=CLAMP(d2,0,255);
	
	OCR2A = out;

	s_ptr1 += s_tword1;// s_tword;
	if (s_ptr1>87376) s_tword1=0; // stop the voice
	s_ptr2 += s_tword2;// s_tword;
	if (s_ptr2>87376) s_tword2=0; // stop the voice


}

/* vim: set noexpandtab ai ts=4 sw=4 tw=4: */
