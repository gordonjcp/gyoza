// Simple Arduino Sample Looper
// Copyright 2010 Gordon JC Pearce
// GPL V3 applies, please see http://www.gnu.org/licenses/gpl.html

// PWM playback code based on Martin Nawrath's
// Arduino DDS Sinewave Generator

// Portions of the code based on nekobee
// This will require changes to run directly as a MIDI synth,
// or something like ALSABridge to interface to the serial port

#include "avr/pgmspace.h"
// handy macros for clearing or setting bits
#define cbi(sfr, bit) (_SFR_BYTE(sfr) &= ~_BV(bit))
#define sbi(sfr, bit) (_SFR_BYTE(sfr) |= _BV(bit))

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
volatile unsigned long s_ptr;
volatile int s_tword;
volatile int sample;
volatile int out;

volatile unsigned long phaccu;   // phase accumulator
volatile unsigned long tword_m;   // dds tuning word

int d1, d2, hp, hp2;

int i_cutoff, i_res, gain;

int tempo_ct=0;
int step=0;
int run = 0;

char notes[16];
unsigned int slide, accent, gate;

double freq, t_freq;    // note frequency
float decay, decay_rate;


void Setup_timer2() {
  // Timer2 Clock Prescaler to : 1
  sbi (TCCR2B, CS20);
  cbi (TCCR2B, CS21);
  cbi (TCCR2B, CS22);

  // Timer 2 PWM A on pin 11
  cbi (TCCR2A, COM2A0);  // clear Compare Match
  sbi (TCCR2A, COM2A1);

  sbi (TCCR2A, WGM20);  // Mode 1  / Phase Correct PWM
  cbi (TCCR2A, WGM21);
  cbi (TCCR2B, WGM22);
}


void setup() {
	int i;
	randomSeed(analogRead(5));
  Serial.begin(57600);
  Serial.println("acidmatic");
  // set up I/O
	DDRB = 0x3f; // all high except 6 and 7
	DDRD = 0x7f; // all high except RXD and PCINT18

	PORTB = 0x00;   // blank out port
	PORTD = 0x80;   // pull up button
	
	sbi(PCICR, PCIE2);	  // pin change interrupt
	sbi(PCMSK2, PCINT23);
	
	run = PIND & 0x80;

  Setup_timer2();
  cbi(TIMSK0, TOIE0);    // timer0 int off
  sbi(TIMSK2, TOIE2);    // timer2 int on

	for (i=0; i<16; i++) {
		notes[i] = random(20, 60);
	}
	slide = random(0, 65536);
	accent = random(0, 65536);
	gate = random(0, 65536);

	d1=d2=hp=127;
	tempo_ct = 65534;   // ensure we're always going to start without waiting
}

void loop() {

	int cutoff;
	int envmod;
    // are we ready to do an update?
	if (do_update) {
		do_update = 0;
		
		cutoff = analogRead(0)/4;
		envmod = analogRead(1)/4;	
		decay *= decay_rate;
			
		cutoff += (analogRead(1)/4)*decay;

		// clamp cutoff, and set "atomic" cutoff value	
		if (cutoff>211) cutoff=211;
		i_cutoff = cutoff; //analogRead(1) / 4;

		i_res = 40; // fixed (high) resonance

		// slide to target frequency, calculate timing word
		t_freq = (0.05*freq)+(0.95*t_freq);
		tword_m = pow(2,32)*t_freq/refclk; 

		// blink LED on beat
		if (!(step & 0x03)) {
			if (tempo_ct < (step?2:15))  digitalWrite(13, HIGH); else digitalWrite(13, LOW);
		}
		// update the tempo counter
		if (run) tempo_ct++;
			
			// play one beat
		if (tempo_ct > 120) {
			tempo_ct=0; // reset timer
			
			// fetch note, get pitch
			freq = pgm_read_float_near(pitchtable+notes[step]);

			// slide?
			if (slide & 1<<step) {
				// no (bit high), just set the target frequency and reset the envelope
				t_freq=freq;
				decay = 1.0;
			}

			// set accent?
			if (accent & 1<<step) {
				decay_rate = 0.997;//(0.97+(analogRead(1)/34200.0f));
				gain = 98;
			} else {
				decay_rate = 0.97;
				gain = 127;
			}
			
			
			// if gate is 0, no output
			if (gate & 1<<step) {
				// flags are active high
				//gain = 16;
			}
			step++;
			step &= 0x0f;

			
  }
    }  // end of control update
}

ISR(PCINT2_vect) {
	run = (PIND & 0x80);
	step = 0;
	tempo_ct = 0;
	if (!run) gain=0;
}
#define CLAMP(x, l, h) (((x) > (h)) ? (h) : (((x) < (l)) ? (l) : (x)))
#define CLIP(x) (((x) > 255) ? 255 : (((x) < -255) ? 255 : (x)))

ISR(TIMER2_OVF_vect) {
	// internal timer
	
	if(icnt1++ > 31) { // slightly faster than 1ms
		do_update=1;
		icnt1=0;
	}   
	
	// play bassline
	phaccu=phaccu+tword_m;
	icnt=phaccu >> 24;
	
	// simple squarewave
	out = icnt>127?192:64;

	// simple sawtooth
	//out = (icnt>>1)+127;

	d2 = CLIP(d2 + ((i_cutoff*d1)>>8));
	hp = CLIP(out - d2 - ((d1*i_res)>>8));
	d1 = CLIP(((i_cutoff*hp)>>8) + d1);

	out=CLAMP(((gain*d2)>>7)-(gain>>1),0,255);
	OCR2A = out;
}

/* vim: set noexpandtab ai ts=4 sw=4 tw=4: */
