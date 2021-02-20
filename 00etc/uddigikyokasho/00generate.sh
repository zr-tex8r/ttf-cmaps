#!/bin/bash
set -eu

glymatch -v UDDigiKyokashoN-R.ttc -i 0
glymatch -v UDDigiKyokashoN-B.ttc -i 0

mv Adobe-Japan1-* ../../uddigikyokasho
