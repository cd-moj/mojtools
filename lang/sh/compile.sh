#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

chmod a+x *sh
echo BIN=$(ls *sh)
