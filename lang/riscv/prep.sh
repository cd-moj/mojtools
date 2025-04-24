#!/bin/bash

[[ -e /etc/java-21-openjdk/ ]] && EXTRABINDINGS+="-b /etc/java-21-openjdk/"
[[ -e /etc/java ]] && EXTRABINDINGS+=" -b /etc/java"

[[ ! -e /tmp/rars.jar ]] && wget https://github.com/TheThirdOne/rars/releases/download/v1.5/rars1_5.jar -O /tmp/rars.jar
cp /tmp/rars.jar $1/
