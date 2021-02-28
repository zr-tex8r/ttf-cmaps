#!/bin/bash
set -eu

#perl gen-override.pl

glymatch -v -r override-shippori.txt ShipporiMincho-Bold.ttf
glymatch -v -r override-shippori.txt ShipporiMincho-ExtraBold.ttf
glymatch -v -r override-shippori.txt ShipporiMincho-Medium.ttf
glymatch -v -r override-shippori.txt ShipporiMincho-Regular.ttf
glymatch -v -r override-shippori.txt ShipporiMincho-SemiBold.ttf

mv Adobe-Japan1-* ../../shippori

glymatch -v -j -r override-shippori.txt ShipporiMincho-Bold.ttf
glymatch -v -j -r override-shippori.txt ShipporiMincho-Regular.ttf
