#!/bin/bash
# Eclipse JDT Language Server launcher

# Find the launcher jar
LAUNCHER_JAR=$(find /opt/jdtls/plugins -name 'org.eclipse.equinox.launcher_*.jar' | head -n 1)

# Determine the workspace data directory from arguments or use default
WORKSPACE_DATA=""
for i in "$@"; do
    if [[ "$i" == --workspace=* ]]; then
        WORKSPACE_DATA="${i#*=}"
        break
    fi
done

# Use default if not specified
if [ -z "$WORKSPACE_DATA" ]; then
    WORKSPACE_DATA="${HOME}/.jdtls-workspace"
fi

# Ensure workspace directory exists
mkdir -p "$WORKSPACE_DATA"

# Launch JDT LS
exec java \
    -Declipse.application=org.eclipse.jdt.ls.core.id1 \
    -Dosgi.bundles.defaultStartLevel=4 \
    -Declipse.product=org.eclipse.jdt.ls.core.product \
    -Dlog.level=ALL \
    -Dlog.protocol=true \
    -Xmx1G \
    --add-modules=ALL-SYSTEM \
    --add-opens java.base/java.util=ALL-UNNAMED \
    --add-opens java.base/java.lang=ALL-UNNAMED \
    -jar "$LAUNCHER_JAR" \
    -configuration /opt/jdtls/config_linux \
    -data "$WORKSPACE_DATA" \
    "$@"