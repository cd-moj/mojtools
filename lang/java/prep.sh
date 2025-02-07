#!/bin/bash

[[ -e /etc/java-21-openjdk/ ]] && EXTRABINDINGS+="-b /etc/java-21-openjdk/"
[[ -e /etc/java ]] && EXTRABINDINGS+=" -b /etc/java"

