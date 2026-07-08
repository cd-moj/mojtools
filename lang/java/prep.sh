#!/bin/bash
# Sem binds: o cage-run monta o /etc INTEIRO da raiz escolhida (host ou rootfs) com máscaras —
# java.security & cia. (/etc/java*) já vêm de lá. (Os binds pontuais de /etc quebravam quando
# o mountpoint não existia na outra raiz: "Can't mkdir /etc/java" => CE.)
