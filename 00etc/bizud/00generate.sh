#!/bin/bash
set -eu

glymatch -v BIZ-UDMinchoM.ttc -i 0
glymatch -v BIZ-UDGothicR.ttc -i 0
glymatch -v BIZ-UDGothicB.ttc -i 0

mv Adobe-Japan1-* ../../bizud
