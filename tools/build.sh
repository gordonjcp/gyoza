#!/bin/sh

# crappy build script, to be replaced with waf

# build resampler
gcc resampler.c -o resampler -lsndfile

