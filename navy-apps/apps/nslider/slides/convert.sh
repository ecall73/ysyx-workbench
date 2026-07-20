#!/bin/bash

rm -f slides-*.bmp slides-page-*.bmp

if command -v convert >/dev/null; then
  convert slides.pdf \
    -sharpen "0x1.0" \
    -type truecolor -resize 400x300\! slides.bmp
else
  gs -q -dSAFER -dBATCH -dNOPAUSE \
    -sDEVICE=bmp16m -dPDFFitPage -g400x300 -r72 \
    -sOutputFile=slides-page-%d.bmp slides.pdf
  for f in slides-page-*.bmp; do
    n=${f#slides-page-}
    n=${n%.bmp}
    mv "$f" "slides-$((n - 1)).bmp"
  done
fi

mkdir -p $NAVY_HOME/fsimg/share/slides/
rm -f $NAVY_HOME/fsimg/share/slides/*
mv slides-*.bmp $NAVY_HOME/fsimg/share/slides/
