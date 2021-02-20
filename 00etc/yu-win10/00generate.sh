#!/bin/bash
set -eu

for f in *.json; do
  cmjconv -O $f
  mv ${f%.json} ../../yu-win10
done
