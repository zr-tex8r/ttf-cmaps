#!/bin/bash
set -eu

set -eu

for f in *.json; do
  cmjconv -O $f
  mv ${f%.json} ../../meiryo
done
