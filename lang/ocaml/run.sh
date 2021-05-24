#!/bin/bash

exec &>/tmp/stderrlog

cd /tmp/dir
source binfile.sh

exec ./$BIN < /tmp/in > /tmp/out
