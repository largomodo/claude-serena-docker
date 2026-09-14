# java-docker notes

Condensed from README.md Troubleshooting > java-docker; edit both.

Quarkus dev mode binds `localhost` by default, so the host-published port
8080 will not reach it even though `launch.sh` publishes it -- bind
explicitly: `mvn quarkus:dev -Dquarkus.http.host=0.0.0.0`. The debugger
listens on 5005.

Testcontainers needs no `TESTCONTAINERS_*` overrides: `DOCKER_HOST` already
points at the rootless daemon, and Ryuk works because the daemon that owns
the socket can bind-mount it into the Ryuk container.

The combined memory footprint of JDT-LS (`-Xmx2G`), the rootless `dockerd`
daemon, the Surefire test JVM, and any Dev Services containers (postgres,
kafka, etc.) is roughly 6GB. If the host runs out of memory, Testcontainers
and Dev Services report the symptom (a container that unexpectedly exited)
rather than the cause -- give the host at least 8GB.

Inner daemon storage is bind-mounted to /workspace/.claudeproject/docker so
image pulls survive a relaunch. Those files are owned by subuids
(100000+), not the host user -- reclaim disk space with
`sudo rm -rf .claudeproject/docker`. That data-root is not portable
between storage drivers (`fuse-overlayfs` vs `vfs`); wipe it before
relaunching under a different driver and let the daemon repopulate it.

This file is prose only: check-tools.sh verifies the sheet's `## Tools` and `## Environment` tables, never the content here.
