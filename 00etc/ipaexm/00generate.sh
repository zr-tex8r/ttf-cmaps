#!/bin/bash
set -eu

perl gen-override.pl

glymatch -v -r override-ipaex.txt ipaexm.ttf
glymatch -v -r override-ipaex.txt ipaexg.ttf

mv Adobe-Japan1-* ../../ipaex
