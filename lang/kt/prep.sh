#!/bin/bash

# JVM (mesmos binds do java) + o compilador Kotlin (zip da JetBrains em /opt/kotlin;
# em modo host /opt não é bindado por padrão — no rootfs ele já vem inteiro).
[[ -e /etc/java-21-openjdk/ ]] && EXTRABINDINGS+="-b /etc/java-21-openjdk/"
[[ -e /etc/java ]] && EXTRABINDINGS+=" -b /etc/java"
[[ -e /opt/kotlin ]] && EXTRABINDINGS+=" -b /opt/kotlin"
