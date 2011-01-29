// resampler.c
// Copyright 2011 Gordon JC Pearce <gordon@gjcp.net>
// Part of nekosynth gyoza
// GPLv3 applies

#include <sndfile.h>
#include <string.h>

#define TABLE_SIZE 24576

int main(int argc, char *argv[]) {
	SNDFILE *input;
	SF_INFO sf_info;
	int samplerate, frames;
	
	
	if (argc != 2) {
		printf("./resampler <filename>\n");
		return 1;
	}

	memset (&sf_info, 0, sizeof(sf_info)) ;

	input = sf_open(argv[1], SFM_READ, &sf_info);
	if (!input) {
		printf("Cannot open %s\n", argv[1]);
		return 1;
	}

	samplerate = sf_info.samplerate;
	frames = (int)sf_info.frames;
		
	printf("Sample is %d samples long and %d Hz sample rate\n", frames, samplerate);
	printf("For %d samples, resample to %dHz\n", TABLE_SIZE, (TABLE_SIZE/frames)*samplerate);
	
	sf_close(input);
}

/* vim: set noexpandtab ai ts=4 sw=4 tw=4: */
