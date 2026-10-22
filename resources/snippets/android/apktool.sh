#!/bin/bash
# Apktool launcher installed as /usr/local/bin/apktool. Replaces upstream's
# scripts/linux/apktool (same java options, no extra pinned download); REA
# finds it through REA_APKTOOL_COMMAND. Leading -J<opt> arguments become JVM
# options, as in the upstream wrapper.
set -eu

extra=()
while [ $# -gt 0 ] && [ "${1#-J}" != "$1" ]; do
    extra+=("${1#-J}")
    shift
done

# The -Djdk.* options relax JDK zip validation for APKs with non-standard
# entries; all options match upstream's wrapper.
exec java -Xmx1024M -Dfile.encoding=utf-8 \
    -Djdk.util.zip.disableZip64ExtraFieldValidation=true \
    -Djdk.nio.zipfs.allowDotZipEntry=true \
    "${extra[@]}" -jar /opt/apktool/apktool.jar "$@"
