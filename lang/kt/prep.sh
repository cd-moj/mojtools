#!/bin/bash

# JVM (mesmos binds do java) + o compilador Kotlin (zip da JetBrains em /opt/kotlin).
# Binds do host valem SÓ em modo HOST — no rootfs a jaula já traz JDK e /opt/kotlin
# próprios, e bindar mountpoint inexistente quebra o bwrap (/etc read-only).
if [[ -z "${CAGE_ROOT:-}" || "$CAGE_ROOT" == host ]]; then
  [[ -e /etc/java-21-openjdk/ ]] && EXTRABINDINGS+="-b /etc/java-21-openjdk/"
  [[ -e /etc/java ]] && EXTRABINDINGS+=" -b /etc/java"
  [[ -e /opt/kotlin ]] && EXTRABINDINGS+=" -b /opt/kotlin"
fi
