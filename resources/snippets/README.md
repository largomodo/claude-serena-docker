# Snippets

Variant-specific resources copied into variant Docker images via COPY instructions. These are not shared across all images — shared infrastructure (apt packages, Serena, cli-tools, codeuser setup) lives in `Dockerfile.base`. This directory holds only resources that belong to one or two variants.

## Directory Layout

- `shared/` scripts (dis16.sh, r216.sh, dump16.sh) are used by both `Dockerfile.snes` and `Dockerfile.x86`, which COPY from this single source to avoid duplication.
- `snes/` resources are specific to the SNES analysis variant only.
