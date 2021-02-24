#!/bin/bash
set -eu

for x in \
  GenShinGothic-ExtraLight.ttf \
  GenShinGothic-Light.ttf \
  GenShinGothic-Regular.ttf \
  GenShinGothic-Normal.ttf \
  GenShinGothic-Medium.ttf \
  GenShinGothic-Bold.ttf \
  GenShinGothic-Heavy.ttf \
  GenShinGothic-Monospace-ExtraLight.ttf \
  GenShinGothic-Monospace-Light.ttf \
  GenShinGothic-Monospace-Regular.ttf \
  GenShinGothic-Monospace-Normal.ttf \
  GenShinGothic-Monospace-Medium.ttf \
  GenShinGothic-Monospace-Bold.ttf \
  GenShinGothic-Monospace-Heavy.ttf \
  GenJyuuGothic-ExtraLight.ttf \
  GenJyuuGothic-Light.ttf \
  GenJyuuGothic-Regular.ttf \
  GenJyuuGothic-Normal.ttf \
  GenJyuuGothic-Medium.ttf \
  GenJyuuGothic-Bold.ttf \
  GenJyuuGothic-Heavy.ttf \
  GenJyuuGothic-Monospace-ExtraLight.ttf \
  GenJyuuGothic-Monospace-Light.ttf \
  GenJyuuGothic-Monospace-Regular.ttf \
  GenJyuuGothic-Monospace-Normal.ttf \
  GenJyuuGothic-Monospace-Medium.ttf \
  GenJyuuGothic-Monospace-Bold.ttf \
  GenJyuuGothic-Monospace-Heavy.ttf
do
  perl gen-override.pl $x
  glymatch -v -r override-${x%.ttf}.txt $x
  rm override-${x%.ttf}.txt
done

mv Adobe-Japan1-GenShin* ../../genshingothic
mv Adobe-Japan1-GenJyuu* ../../genjyuugothic
