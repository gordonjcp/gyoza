// Simple Arduino Bass Synth
// Copyright 2010 Gordon JC Pearce
// GPL V3 applies, please see http://www.gnu.org/licenses/gpl.html

// PWM playback code based on Martin Nawrath's
// Arduino DDS Sinewave Generator

// Portions of the code based on nekobee
// This will require changes to run directly as a MIDI synth,
// or something like ALSABridge to interface to the serial port

#include "avr/pgmspace.h"
#include "avr/interrupt.h"
// handy macros for clearing or setting bits
#define cbi(sfr, bit) (_SFR_BYTE(sfr) &= ~_BV(bit))
#define sbi(sfr, bit) (_SFR_BYTE(sfr) |= _BV(bit))

#define CLAMP(x, l, h) (((x) > (h)) ? (h) : (((x) < (l)) ? (l) : (x)))
#define CLIP(x) (((x) > 255) ? 255 : (((x) < -255) ? -255 : (x)))
#define CLIP0(x) (((x) > 255) ? 255 : (((x) < 0) ? 0 : (x)))

// analogue controls
// wire four pots across 0V and 5V with the wiper going to the respective analogue input
#define CUTOFF 0
#define RESONANCE 1
#define ENVMOD 2
#define DECAY 3

// 49/61 note C-C pitchtable
// 
PROGMEM float pitchtable[] = {
//16.35, 17.32, 18.35, 19.45, 20.60, 21.83, 23.12, 24.50, 25.96, 27.50, 29.14, 30.87, // C0
32.70, 34.65, 36.71, 38.89, 41.20, 43.65, 46.25, 49.00, 51.91, 55.00, 58.27, 61.74, // C1
65.41, 69.30, 73.42, 77.78, 82.41, 87.31, 92.50, 98.00, 103.83, 110.00, 116.54, 123.47, // C2
130.81, 138.59, 146.83, 155.56, 164.81, 174.61, 185.00, 196.00, 207.65, 220.00, 233.08, 246.94, // C3
261.63, 277.18, 293.66, 311.13, 329.63, 349.23, 369.99, 392.00, 415.30, 440.00, 466.16, 493.88, // C4
523.25 // C5
};

// variables used inside interrupt service declared as voilatile
volatile byte icnt;               // var inside interrupt
volatile byte icnt1;              // var inside interrupt
volatile byte do_update;               // count interrupts
volatile int out=0, d1=0, d2=0, hp=0;   // osc/filter values

volatile unsigned long phaccu;   // phase accumulator
volatile unsigned long tword_m;   // dds tuning word

// sequencer state
int tempo_ct=0;
int step=0;
int run = 0;

// sequence data
char s_notes[] = {12, 14, 16, 17, 19, 21, 23, 24, 36, 38, 40, 41, 43, 45, 47, 48};
unsigned int s_slide, s_accent, s_gate;

double freq, t_freq;    // note frequency

uint8_t pots[4] = { 0, 0, 0, 0 };
const uint8_t nextpot[4] = { _BV(ADLAR) | 0b0001, _BV(ADLAR) | 0b0010, _BV(ADLAR) | 0b0011, _BV(ADLAR) | 0b0000 };
int cutoff, res, envmod, decay, gain;
int i_gate;

long vca_decay, vcf_decay;


int i_cutoff, i_res, i_gain;

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

int jjj[]={ 9, 21, 33, 45 };
//int jjj[]={ 0, 12, 24, 36 };

void newpattern() {
	int i;
	for (i=0; i<16; i++) {
		s_notes[i] = random(0, 12);
	//	s_notes[i]=(i*4);
	//	s_notes[i] = jjj[i>>2];
	}
	//s_slide = random(0, 65536);
	//s_accent = random(0, 65536);
	//s_gate = random(0, 65536);
	
	//s_gate = 0xffff;
}

void setup() {

	randomSeed(analogRead(5));
	
	Serial.begin(57600);
	
	// set up I/O
	DDRB = 0x3f; // all high except 6 and 7
	DDRD = 0x72; // all high except RXD, 2, 3 and PCINT23

	PORTB = 0x00;   // blank out port
	PORTD = 0x88;   // pull up button
	
	pinMode(3, INPUT);
	digitalWrite(3, HIGH);
	
	sbi(PCICR, PCIE2);	  // pin change interrupt
	sbi(PCMSK2, PCINT23);

	Setup_timer2();
	cbi(TIMSK0, TOIE0);    // timer0 int off
	sbi(TIMSK2, TOIE2);    // timer2 int on

	newpattern();

	tempo_ct = 0;   // ensure we're always going to start without waiting

	run=1;
	
	pinMode(13,OUTPUT);
	
	vca_decay = 65535;

	// first ADC read will be from ADC1 and left-adjusted (8bit)
	ADMUX = _BV(ADLAR) | _BV(MUX1) | _BV(MUX0);
	// enable ADC, start conversions, enable automatic trigger, enable conversion interrupt, enable /128 prescaler
	ADCSRA = _BV(ADEN) | _BV(ADSC) | _BV(ADATE) | _BV(ADIE) | _BV(ADPS0)| _BV(ADPS1) | _BV(ADPS2);
	// set to free-running conversion (ACME and ADTS[0,1,2] all 0)
	ADCSRB = 0;
}

void read_pots() {
	cutoff = pots[0];
	res    = pots[1];
	envmod = pots[2];
	decay  = pots[3];
}

unsigned long i_f, i_tf;

void voice_update() {
	// called on every update to calculate voice parameters


	read_pots();
	
	// run the envelopes
	vca_decay += (((0-vca_decay) * 63)>>16);
	vcf_decay += (((0-vcf_decay) * decay)>>16);
	// not the most efficient expression, because I plan to add an attack envelope

		
	// calculate the values for the sample engine
	
	// envelope is biased a little negative
	//cutoff += (envmod*(vcf_decay-0.15));

	cutoff += (envmod*(vcf_decay-8192))>>16;
	i_cutoff = CLAMP(cutoff, 1, 211);// CLAMP(cutoff, 1, 211);   // stable within these values
	
	i_res = 260-res;	// we may want to fiddle with the resonance

	i_gain = vca_decay >> 9;//127;// vca_decay * 127;

	// slide to target frequency, calculate timing word
	i_tf = ((i_f*12)>>8) + ((243*i_tf)>>8);
	tword_m = 580*i_tf;
}


void loop() {
    // are we ready to do an update?
    // this is the ~1ms "heartbeat" of the synth engine
    if (do_update) {
		PORTB = PORTB | 0x20;
		do_update = 0;
		
		//read_pots();

		voice_update(); // always run the voice updates
			
		// play one beat
		if (tempo_ct == 0) {
			tempo_ct=120; // reset timer
			if (step == 0) vca_decay = 65535;
			if ((step & 0x03) == 0) vcf_decay = 65535;
			
			
			// fetch note, get pitch
			i_f = 256*pgm_read_float_near(pitchtable + s_notes[step]);
		
			// slide?
		//	i//f (s_slide & 1<<step) {
				// no (bit high), just set the target frequency and reset the envelope
		//		t_freq=freq;
				//vcf_decay = 1.0;

	//		}

/*
			// set accent?
			if (s_accent & 1<<step) {
				vcf_rate = 0.97+(0.000113*decay);
				//gain = 98;
			} else {
				vcf_rate = 0.97;
				//gain = 127;
			}

			// if gate is 0, no output
			if (s_gate & 1<<step) {
				i_gate=1;
				vca_decay = 1.0;
			} else {
				i_gate = 0;
			}
			*/
			step++;
			step &= 0x0f;
		}
		//if ((s_slide & 1<<step) && tempo_ct>100) {
		//	i_gate=0;
		//}
	
			if (run) tempo_ct--;
	PORTB=PORTB & 0xdf;
    }  // end of control update
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
	out = icnt>127?159:32;

	// simple sawtooth
	//out = (icnt>>1)+68;

	d2 = CLIP(d2 + ((i_cutoff*d1)>>8));
	hp = CLIP(out - d2 - ((d1*i_res)>>8));
	d1 = CLIP(d1 + ((i_cutoff*hp)>>8));
 
	out= (d2*i_gain)>>7;

	OCR2A = CLIP0(out);
}

ISR(ADC_vect) {
        uint8_t reading = ADCH;
        static uint8_t first = 1;
        if (first) {
                first = 0;
                return;
        }
        uint8_t mux;
        mux = ADMUX & 0b00000111;
        ADMUX = nextpot[mux];
        pots[mux] = reading;
}


/* vim: set noexpandtab ai ts=4 sw=4 tw=4: */
