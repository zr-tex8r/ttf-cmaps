#!/bin/bash
set -eu

glymatch -v msmincho.ttc -i 0
glymatch -v msgothic.ttc -i 0

mv Adobe-Japan1-* ../../ms
