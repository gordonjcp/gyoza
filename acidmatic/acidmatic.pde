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

#define CLAMP(x, l, h) (((x) > (h)) ? (h) : (((x) < (l)) ? (l) : (x)))
#define CLIP(x) (((x) > 255) ? 255 : (((x) < -255) ? 255 : (x)))


// analogue controls
#define CUTOFF 0
#define RESONANCE 1
#define ENVMOD 2
#define DECAY 3

// wire four pots across 0V and 5V with the wiper going to the respective analogue input

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
int trig, newpatt = 0, bar_ct=0;

int d1=255, d2=255, hp=255;

int i_cutoff, i_res, i_gain;

int tempo_ct=0;
int step=0;
int run = 0;

char notes[16];
unsigned int slide, accent, gate;

double freq, t_freq;    // note frequency
float vcf_decay, vcf_rate;
float vca_decay, vca_rate;


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

void newpattern() {
	int i;
	for (i=0; i<16; i++) {
		notes[i] = random(20, 60);
	}
	slide = random(0, 65536);
	accent = random(0, 65536);
	gate = random(0, 65536);
#if 1
	for (i=0; i<16; i++) {
		notes[i] = 45; // A
	}
	accent = 65535;
	slide = 0x8888;
#endif

#if 1
	accent = 65535;
	slide = 0xffff;
	slide = 0xefef;
	gate = 0xfafa;
	gate = 0xffff;
#endif
}

void setup() {

	randomSeed(analogRead(5));
	
	// set up I/O
	DDRB = 0x3f; // all high except 6 and 7
	DDRD = 0x72; // all high except RXD, 2, 3 and PCINT23

	PORTB = 0x00;   // blank out port
	PORTD = 0x88;   // pull up button
	
	pinMode(3, INPUT);
	digitalWrite(3, HIGH);
	
	sbi(PCICR, PCIE2);	  // pin change interrupt
	sbi(PCMSK2, PCINT23);
	
	run = PIND & 0x80;

	Setup_timer2();
	attachInterrupt(0, pulseinterrupt, RISING);
	cbi(TIMSK0, TOIE0);    // timer0 int off
	sbi(TIMSK2, TOIE2);    // timer2 int on

	newpattern();

	d1=d2=hp=127;
	tempo_ct = 65534;   // ensure we're always going to start without waiting
	
	newpatt = 0;
	digitalWrite(13, LOW);
	run=1;
}

int cutoff, res, envmod, decay, gain;
int i_gate;

void voice_update() {
	// read the pots
	cutoff = analogRead(CUTOFF)/4;
	res = analogRead(RESONANCE)/4;
	envmod = analogRead(ENVMOD)/4;
	decay = analogRead(DECAY)/4;

	vca_rate = i_gate ? 0.9997:0.95;
	
	// run the envelopes
	vcf_decay *= vcf_rate;
	vca_decay *= vca_rate;
		
	// calculate the values for the sample engine
	
	// envelope is biased a little negative
	cutoff += (envmod*(vcf_decay-0.15));
	i_cutoff = CLAMP(cutoff, 2, 211);   // stable within these values
	
	i_res = 270-res;	// we may want to fiddle with the resonance

	i_gain = vca_decay * 255;

	// slide to target frequency, calculate timing word
	t_freq = (0.05*freq)+(0.95*t_freq);
	tword_m = pow(2,32)*t_freq/refclk; 
	
}

void loop() {
    // are we ready to do an update?
	if (do_update) {
		do_update = 0;
		
		if (digitalRead(3)) {
			newpatt=1;

		}

		voice_update();

		// blink LED on beat
		if (!(step & 0x03)) {
			//if (tempo_ct < (step?2:15))  PORTB = PORTB | 0x20; else PORTB = PORTB & 0xdf;
		}
		// update the tempo counter
		if (run) tempo_ct++;
			
			// play one beat
		if (tempo_ct > 120) {
		//if (trig) {
			trig = 0;
			PORTD = 0x84;
			tempo_ct=0; // reset timer
			
			// fetch note, get pitch
			freq = pgm_read_float_near(pitchtable+notes[step]);

			// slide?
			if (slide & 1<<step) {
				// no (bit high), just set the target frequency and reset the envelope
				t_freq=freq;
				vcf_decay = 1.0;

			}

			// set accent?
			if (accent & 1<<step) {
				vcf_rate = 0.97+(0.000113*decay);
				//gain = 98;
			} else {
				vcf_rate = 0.97;
				//gain = 127;
			}

			// if gate is 0, no output
			if (gate & 1<<step) {
				i_gate=1;
				vca_decay = 1.0;
			} else {
				i_gate = 0;
			}
			
			step++;
			step &= 0x0f;
		}
		if ((slide & 1<<step) && tempo_ct>100) {
			i_gate=0;
		}
	PORTD = 0x80;
    }  // end of control update
}

void pulseinterrupt() {
	trig = 1;
	
}
ISR(PCINT2_vect) {
	if (PIND & 0x80) {
		run = 1;
		step = 0;
		tempo_ct = 0;
	} else {
		run = 0;
		gain=0;
	}
}

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
	out = icnt>127?183:72;

	// simple sawtooth
	//out = (icnt>>1)+68;

	d2 = CLAMP(d2 + ((i_cutoff*d1)>>8), 0, 255);
	hp = CLIP(out - d2 - ((d1*i_res)>>8));
	d1 = CLIP(d1 + ((i_cutoff*hp)>>8));


 
	out= (d2*i_gain)>>8;

	OCR2A = out;
}

/* vim: set noexpandtab ai ts=4 sw=4 tw=4: */
