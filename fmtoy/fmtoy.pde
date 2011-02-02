
#include "avr/pgmspace.h"

#define SERIAL

// table of 256 sine values / one sine period / stored in flash memory
PROGMEM  prog_uchar sine256[]  = {
  127,130,133,136,139,143,146,149,152,155,158,161,164,167,170,173,176,178,181,184,187,190,192,195,198,200,203,205,208,210,212,215,217,219,221,223,225,227,229,231,233,234,236,238,239,240,
  242,243,244,245,247,248,249,249,250,251,252,252,253,253,253,254,254,254,254,254,254,254,253,253,253,252,252,251,250,249,249,248,247,245,244,243,242,240,239,238,236,234,233,231,229,227,225,223,
  221,219,217,215,212,210,208,205,203,200,198,195,192,190,187,184,181,178,176,173,170,167,164,161,158,155,152,149,146,143,139,136,133,130,127,124,121,118,115,111,108,105,102,99,96,93,90,87,84,81,78,
  76,73,70,67,64,62,59,56,54,51,49,46,44,42,39,37,35,33,31,29,27,25,23,21,20,18,16,15,14,12,11,10,9,7,6,5,5,4,3,2,2,1,1,1,0,0,0,0,0,0,0,1,1,1,2,2,3,4,5,5,6,7,9,10,11,12,14,15,16,18,20,21,23,25,27,29,31,
  33,35,37,39,42,44,46,49,51,54,56,59,62,64,67,70,73,76,78,81,84,87,90,93,96,99,102,105,108,111,115,118,121,124
};

// MIDI note pitches in Hz
PROGMEM float pitchtable[] = {
8.18,  8.66,  9.18,  9.72,  10.30,  10.91,  11.56,  12.25,  12.98,  13.75,  14.57,  15.43,  16.35,  17.32,  18.35,  19.45,  20.60,  21.83,  23.12,  24.50,  25.96,  27.50,  29.14,  30.87,  32.70,  34.65,  36.71,  38.89,  41.20,  43.65,  46.25,  49.00,  51.91,  55.00,  58.27,  61.74,  65.41,  69.30,  73.42,  77.78,  82.41,  87.31,  92.50,  98.00,  103.83,  110.00,  116.54,  123.47,  130.81,  138.59,  146.83,  155.56,  164.81,  174.61,  185.00,  196.00,  207.65,  220.00,  233.08,  246.94,  261.63,  277.18,  293.66,  311.13,  329.63,  349.23,  369.99,  392.00,  415.30,  440.00,  466.16,  493.88,  523.25,  554.37,  587.33,  622.25,  659.26,  698.46,  739.99,  783.99,  830.61,  880.00,  932.33,  987.77,  1046.50,  1108.73,  1174.66,  1244.51,  1318.51,  1396.91,  1479.98,  1567.98,  1661.22,  1760.00,  1864.66,  1975.53,  2093.00,  2217.46,  2349.32,  2489.02,  2637.02,  2793.83,  2959.96,  3135.96,  3322.44,  3520.00,  3729.31,  3951.07,  4186.01,  4434.92,  4698.64,  4978.03,  5274.04,  5587.65,  5919.91,  6271.93,  6644.88,  7040.00,  7458.62,  7902.13,  8372.02,  8869.84,  9397.27,  9956.06,  10548.08,  11175.30,  11839.82,  12543.85, 
};

typedef struct {
    // Patch structure
    // parameters stored as bytes, containing values from 0-127
    // exactly as received over MIDI

    // Operator 1
    byte op1_ratio;   // 0-127, only 0-7 useful
    byte op1_detune;  // -64 to 63, u64 = 0
    byte op1_lfo;     // 0-127, scaled
    byte op1_gain;    // 0-127, scaled
    byte op1_env;     // -64 to 63, u64 = 0
    byte op1_a, op1_d, op1_s, op1_r;

    // Operator 2
    byte op2_ratio;
    byte op2_detune;
    byte op2_lfo;
    byte op2_gain;
    byte op2_env;
    byte op2_a, op2_d, op2_s, op2_r;
    
    // lfo
    byte lfo_rate;
    byte lfo_shape;
    byte lfo_delay;
   
    // instrument
    byte portamento;
    byte fb; 
} patch;

// if you add more patches, don't forget to change the limit in set_patch()
PROGMEM patch patches[] = {
    {2, 64, 3, 5, 82, 0, 83, 0, 75, 2, 64, 3, 64, 127, 68, 80, 75, 64, 25, 0, 0, 0, 73, },
{1, 64, 0, 77, 127, 0, 75, 0, 75, 7, 64, 0, 64, 127, 0, 91, 0, 0, 64, 0, 0, 0, 38, },
    {6, 64, 0, 3, 98, 0, 79, 0, 75, 2, 64, 0, 64, 127, 0, 80, 75, 64, 24, 0, 0, 0, 0, },
    {1, 64, 5, 49, 127, 48, 101, 0, 75, 2, 64, 5, 64, 127, 0, 80, 75, 64, 19, 0, 0, 0, 56, },
    {7, 64, 0, 12, 79, 0, 75, 0, 75, 2, 64, 0, 64, 127, 0, 91, 0, 90, 64, 0, 0, 0, 0, },
    {7, 64, 0, 12, 79, 0, 75, 0, 75, 1, 64, 0, 64, 127, 0, 91, 0, 90, 64, 0, 0, 0, 0, },
    {1, 64, 0, 12, 79, 0, 75, 0, 75, 7, 64, 0, 64, 127, 0, 91, 0, 90, 64, 0, 0, 0, 0, },
    {4, 64, 0, 2, 94, 0, 66, 0, 75, 2, 64, 0, 64, 127, 0, 80, 75, 64, 24, 0, 0, 0, 37, },
};
#define N_PATCH 7

#define cbi(sfr, bit) (_SFR_BYTE(sfr) &= ~_BV(bit))
#define sbi(sfr, bit) (_SFR_BYTE(sfr) |= _BV(bit))

// envelopes
byte eg1_phase, eg2_phase;
float eg1_rate[3], eg1_rate_level[3];
float eg2_rate[3], eg2_rate_level[3];
float eg1_s, eg2_s;
float eg1, eg2;

double dfreq;
double tfreq;


char note;
char velocity;
char modwheel;
char cutoff;

// const double refclk=31372.549;  // =16MHz / 510
const double refclk=31376.6;

// midi functions
#define NOTEQUEUE 8
char notes[NOTEQUEUE];

byte st, p1, p2;

// variables used inside interrupt service declared as voilatile
volatile byte icnt;              // var inside interrupt
volatile byte icnt1;             // var inside interrupt
volatile byte y1, fb1;           // feedback
volatile byte y2;
volatile unsigned int fb2;    // mod depth

volatile unsigned long phaccu1;   // phase accumulator
volatile unsigned long phaccu2;   // phase accumulator
volatile byte fb;

volatile unsigned int gain1;
volatile unsigned int gain2;
volatile unsigned long tword_m1;  // dds tuning word m
volatile unsigned long tword_m2;  // dds tuning word m

volatile byte do_update;

// lfo
unsigned int tword_lfo;
unsigned int phaccu_lfo;
float lfo;
byte lfo_icnt;

float portamento;

// controllers
float bend, mod=1;

int i; // random general purpose counter
patch current;

// Wiring gets in the way of using structs
// so we just do both in one handler
void set_env() {
    float k;
    eg1_s = current.op1_s/127.0;    
    k = exp(-4*(current.op1_a/127.0)*2.3);
    eg1_rate_level[0] = k * 0.99; // attack time
    eg1_rate[0] = 1 - k;
    k = exp(-4*(current.op1_d/127.0)*2.3);
    eg1_rate_level[1] = k * eg1_s * 0.99;
    eg1_rate[1] = 1 - k;
    k = exp(-4*(current.op1_r/127.0)*2.3);
    eg1_rate_level[2] = 0; // final level
    eg1_rate[2] = 1-k;
    
    eg2_s = current.op2_s/127.0;    
    k = exp(-4*(current.op2_a/127.0)*2.3);
    eg2_rate_level[0] = k * 0.99; // attack time
    eg2_rate[0] = 1 - k;
    k = exp(-4*(current.op2_d/127.0)*2.3);
    eg2_rate_level[1] = k * eg2_s * 0.99;
    eg2_rate[1] = 1 - k;
    k = exp(-4*(current.op2_r/127.0)*2.3);
    eg2_rate_level[2] = 0; // final level
    eg2_rate[2] = 1-k;
    
}

void set_patch(int p) {
    // Fetch a patch from ROM
    
    if (p > N_PATCH) p=N_PATCH;// only have one patch! update when we add more
    patch *ptr = &patches[p];
    memcpy_P(&current, ptr, sizeof(patch));
    fb = current.fb;
    set_env();
    tword_lfo = pow(2,16)*current.lfo_rate/4000;
}

void setup()
{
  Serial.begin(57600);        // connect to the serial port
  Serial.println("FMToy");
  
  set_patch(0);
  
  pinMode(6, OUTPUT);      // sets the digital pin as output
  pinMode(7, OUTPUT);      // sets the digital pin as output
  pinMode(11, OUTPUT);     // pin11= PWM  output / frequency output
  pinMode(2, INPUT);
  pinMode(13, OUTPUT);
  digitalWrite(2, HIGH);
  digitalWrite(13, LOW);
  digitalWrite(7, LOW);
  pinMode(3, OUTPUT);

  digitalWrite(6, LOW);
  analogWrite(3, 255);

  Setup_timer2();

  // disable interrupts to avoid timing distortion
  cbi (TIMSK0,TOIE0);              // disable Timer0 !!! delay() is now not available
  sbi (TIMSK2,TOIE2);              // enable Timer2 Interrupt
}

void loop()
{
  byte note = 60;
  while(1) {
     if (do_update) {
      do_update=0;
      st=Serial.read();

      if (st != 0xff) {

        // crufty, not all statuses expect two values
        if (st >= 0x80 ) { // note off
          do {
            p1 = Serial.read();  
          } while (p1 == 0xff);
          if (st != 0xc0) do {  // don't wait for a second byte
            p2 = Serial.read();  
          } while (p2 == 0xff);
        }

       
        if ((st == 0x90 && p2 == 0) || st == 0x80) {
          int j, k;
          k = notes[0];  // keep current key
          // remove note from note queue
          for(i=0; i<NOTEQUEUE; i++) {
            if (p1==notes[i]) {
              // nudge rest up
              for(j=i+1; j<NOTEQUEUE; j++) {
                notes[j-1] = notes[j];
              }
              notes[NOTEQUEUE-1]=0;
              break;
            }
          } 
          
          if (notes[0]!=k && notes[0]!=0) {
            // top note released
            note = notes[0];
            tfreq=pgm_read_float_near(pitchtable+note);     
          }
          
          if (notes[0]==0) {
            // no notes left to play
            digitalWrite(13, LOW);  // LED off
            // envelopes to release
            eg1_phase=2;
            eg2_phase=2;
          }

        }
        if (st ==0x90 && p2 > 0) {
          // scan for highest note
          int j, k;
          k = notes[0];
          for(i=0; i<NOTEQUEUE; i++) {
            if (p1>notes[i]) {
              // nudge rest down
              for(j=NOTEQUEUE-1; j>i; j--) {
                notes[j] = notes[j-1];
              }
              notes[i]=p1;
              break;
            }         
          }
            
          if (notes[0]!=k) {
            // top note released
            note = notes[0];
            tfreq=pgm_read_float_near(pitchtable+note);
          }
          
            // note on, set target frequency
            if (k==0) {
                // new note;
                eg1_phase=0;
                eg2_phase=0;
                velocity = p2;
                phaccu1=0;
                phaccu2=0;
            }

            digitalWrite(13, HIGH);  // LED on
        }
       if (st == 0xB0) {
          switch(p1) {
            // based on Novation BassStation parameters
            case 28: current.op1_gain = p2; break;   // Op1 Level
            case 29: {
                current.op1_lfo = p2; // set LFO level for both
                current.op2_lfo = p2;
                break;
            }
            case 30: current.op1_env = p2; break;    // Op1 EG Depth
            case 108: {
                current.op2_a = p2;
                set_env();
                break; 
            }
            case 109: {
                current.op2_d = p2;
                set_env();
                break; 
            }
            case 110: {
                current.op2_s = p2;
                set_env();
                break; 
            }
            case 111: {
                current.op2_r = p2;
                set_env();
                break; 
            }
            case 114: {
                current.op1_a = p2;
                set_env();
                break; 
            }
            case 115: {
                current.op1_d = p2;
                set_env();
                break; 
            }
            case 116: {
                current.op1_s = p2;
                set_env();
                break; 
            }
            case 117: {
                current.op1_r = p2;
                set_env();
                break; 
            }
            
            case 41:    // osc1 ratio
                current.op1_ratio = p2;
                break;
            case 23:    // feedback
                current.fb = p2;
                fb = current.fb;
                break;
            case 16:    // lfo speed
                current.lfo_rate = p2;
                tword_lfo = pow(2,16)*p2/4000;
                break;
            
            
            case 105:    // "real" cutoff
                analogWrite(3, p2*2);
                break;
#ifdef SERIAL
            case 127:
                if (p2 == 127) {
                    int i;
                    char *x;
                    x = (char *)&current;
                    Serial.print("{");
                    for (i=0; i<sizeof(patch); i++) {
                        Serial.print((int)*(x+i), DEC);
                        Serial.print(", ");
                    }
                    Serial.println("},");
                }
                break;
#endif
            default:  break;
          }           
       }
      }
      
      if (st == 0xc0) {
          set_patch(p1);
      }
      
      // update the voice
      phaccu_lfo += tword_lfo;
      lfo_icnt = phaccu_lfo >> 8;
      lfo = (pgm_read_byte_near(sine256+lfo_icnt)-127)/128.0f;
   
      eg1 = eg1_rate_level[eg1_phase] + eg1_rate[eg1_phase] * eg1;
      if (!eg1_phase && eg1 > 0.98) eg1_phase=1;

      eg2 = eg2_rate_level[eg2_phase] + eg2_rate[eg2_phase] * eg2;
      if (!eg2_phase && eg2 > 0.98) eg2_phase=1;
      
      
      gain1 = (current.op1_gain<<1) + (eg1 * ((current.op1_env-64)<<1));// + keyfollow ;
      if (gain1 < 0) gain1 = 0;
      
      gain2 = (current.op2_env<<1)*eg2;
 
      //dfreq = portamento*tfreq+(1-portamento)*dfreq;
      dfreq=tfreq;
      tword_m1 = pow(2,32)*((dfreq* current.op1_ratio)/2 * (1+(lfo*current.op1_lfo)/256.0))/refclk;
      tword_m2 = pow(2,32)*((dfreq* current.op2_ratio)/2 * (1+(lfo*current.op2_lfo)/256.0))/refclk;
    }

   sbi(PORTD,6); // Test / set PORTD,7 high to observe timing with a scope
   cbi(PORTD,6); // Test /reset PORTD,7 high to observe timing with a scope
  }
 }
//******************************************************************
// timer2 setup
// set prscaler to 1, PWM mode to phase correct PWM,  16000000/510 = 31372.55 Hz clock
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

// Serial timer interrupt
//******************************************************************
// Timer2 Interrupt Service at 31372,550 KHz = 32uSec
// this is the timebase REFCLOCK for the DDS generator
// FOUT = (M (REFCLK)) / (2 exp 32)
// runtime : 8 microseconds ( inclusive push and pop)
volatile int out;
ISR(TIMER2_OVF_vect) {
  // internal timer
  if(icnt1++ > 31) { // slightly faster than 1ms
    do_update=1;
    icnt1=0;
   }   
  

    // operator 1
  phaccu1=phaccu1+tword_m1;
  icnt=phaccu1 >> 24;
  y1 = pgm_read_byte_near(sine256 + ((icnt+fb1) % 256));
  fb1 = fb*(y1 + fb1) >> 8;

    // operator 2
  phaccu2=phaccu2+tword_m2;
  icnt=phaccu2 >> 24;  
  //fb2 = gain1*(y1) >> 8-(gain1>>1);
  fb2 = ((gain1*y1)>>6)-(gain1>>1);
  y2 = pgm_read_byte_near(sine256 + ((icnt+fb2)%256));  

    // set the PWM

   out = ((gain2*y2)>>8)-(gain2>>1);

    // DC restore and clip output
    out += 127;
    out >>=1;
    if (out<0) out=0;
    if (out>0xff) out = 0xff;
    
    OCR2A = out;
}
