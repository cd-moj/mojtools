#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

chmod a+x *py3
echo BIN=$(ls *py3)
