#!/bin/bash
set -eu

glymatch -v -r override.txt BIZUDMincho-Regular.ttf
glymatch -v -r override.txt BIZUDGothic-Regular.ttf
glymatch -v -r override.txt BIZUDGothic-Bold.ttf

mv Adobe-Japan1-* ../../bizudfree
