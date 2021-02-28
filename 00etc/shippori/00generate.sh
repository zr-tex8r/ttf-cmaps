#!/bin/bash
set -eu

VERSION=3.000
#perl gen-override.pl

glymatch -v -r override-shippori.txt --cmapver=$VERSION ShipporiMincho-Bold.ttf
glymatch -v -r override-shippori.txt --cmapver=$VERSION ShipporiMincho-ExtraBold.ttf
glymatch -v -r override-shippori.txt --cmapver=$VERSION ShipporiMincho-Medium.ttf
glymatch -v -r override-shippori.txt --cmapver=$VERSION ShipporiMincho-Regular.ttf
glymatch -v -r override-shippori.txt --cmapver=$VERSION ShipporiMincho-SemiBold.ttf

mv Adobe-Japan1-* ../../01develop/shippori-v$VERSION
