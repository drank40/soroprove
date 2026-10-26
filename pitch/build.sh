#!/bin/sh
# static font instances live in ./fonts (typst can't do variable weights)
cd "$(dirname "$0")" && typst compile --ignore-system-fonts --font-path fonts main.typ soroprove.pdf
