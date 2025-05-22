#!/bin/bash

exec &>/tmp/stderrlog

#ulimit -a

cd /tmp/dir
source binfile.sh

exec dyalog APLTRANS=/opt/mdyalog/19.0/64/unicode/apltrans APLKEYS=/opt/mdyalog/19.0/64/unicode/aplkeys -s -script ./$BIN < /tmp/in > /tmp/out
