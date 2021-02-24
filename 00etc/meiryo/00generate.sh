#!/bin/bash
set -eu

glymatch -v meiryo.ttc -i 0
glymatch -v meiryob.ttc -i 0

mv Adobe-Japan1-* ../../meiryo
