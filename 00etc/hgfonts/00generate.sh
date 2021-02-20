#!/bin/bash
set -eu

glymatch -v HGRGE.TTC -i 0
glymatch -v HGRGM.TTC -i 0
glymatch -v HGRGY.TTC -i 0
glymatch -v HGRKK.TTC -i 0
glymatch -v HGRMB.TTC -i 0
glymatch -v HGRME.TTC -i 0
glymatch -v HGRPP1.TTC -i 0
glymatch -v HGRPRE.TTC -i 0
glymatch -v HGRSGU.TTC -i 0
glymatch -v HGRSKP.TTF
glymatch -v HGRSMP.TTF

mv Adobe-Japan1-* ../../hgfonts
