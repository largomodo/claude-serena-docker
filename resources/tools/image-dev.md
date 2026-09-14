# claude-env container toolchain: image-dev

## Tools (image-dev)

| Tool | What | Use when |
| --- | --- | --- |
| `docker` `dockerd-rootless.sh` | Engine CLI with `docker compose` plugin; rootless daemon started by the entrypoint | Building or running container workloads |

## Environment (image-dev)

| Variable | What |
| --- | --- |
| `VARIANT` | Container variant name (`image-dev`) |
| `DOCKER_HOST` | Rootless Docker daemon socket |
| `XDG_RUNTIME_DIR` | Runtime dir the rootless daemon uses for its socket |

## Notes (image-dev)

- Inner images are discarded on container exit; no persisted data-root.
- Storage driver is `fuse-overlayfs` with `vfs` fallback when /dev/fuse is missing.
- This variant exists for building and testing claude-env images and other container workloads.
- Presence on PATH is what the build verifies; it does not guarantee a listed tool succeeds for every invocation.
