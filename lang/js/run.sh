#!/bin/bash

exec &>/tmp/stderrlog

cd /tmp/dir
source binfile.sh

exec node ./$BIN < /tmp/in > /tmp/out
