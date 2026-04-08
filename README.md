# app.GUI

Unified TurboVNC-based GUI launcher for ARCH compute nodes.

This repository snapshot contains:

- `lmod/app.GUI/2.0.lua`: Lmod modulefile for `app.GUI/2.0`
- `extern/app.GUI/2.0/bin/`: launchers and wrappers
- `extern/app.GUI/2.0/fluxbox/`: Fluxbox, Xresources, and window-manager config

## Main interface

CPU is the default backend:

```bash
app --start-session &
app --run <application> [args...]
```

GPU-enabled launch:

```bash
app --gpu --start-session &
app --gpu --run <application> [args...]
```

## Common examples

Start a CPU session in the background and launch MATLAB:

```bash
app --start-session &
ml matlab/R2021a
app --run matlab -desktop &
```

Start a GPU session in the background and launch MATLAB:

```bash
app --gpu --start-session &
ml matlab/R2021a
app --gpu --run matlab -desktop &
```

Choose a resolution explicitly:

```bash
app --geometry 1920x1080 --start-session &
app --gpu --geometry 2560x1440 --start-session &
```

Supported resolutions:

- `1024x768`
- `1280x1024`
- `1920x1080`
- `2560x1440`

## Known issue: missing `/run/user/$UID` on compute nodes

When users land on a compute node, they don't have a `/run/user/$UID` folder, which causes several OOD applications to crash.

This requires a system-level fix (root access). The solution below uses the SLURM prolog/epilog to ensure `/run/user/$UID` exists for the job duration on every compute node, without requiring changes per-user or per-application.

**SLURM Prolog script** (`/etc/slurm/prolog.d/create-xdg-runtime.sh`):

```bash
#!/bin/bash
install -d -o "${SLURM_JOB_USER}" -m 0700 "/run/user/$(id -u ${SLURM_JOB_USER})"
```

**SLURM Epilog script** (`/etc/slurm/epilog.d/clean-xdg-runtime.sh`):

```bash
#!/bin/bash
rm -rf "/run/user/$(id -u ${SLURM_JOB_USER})"
```

## Notes

- `cpu.app` and `gpu.app` are internal launchers.
- `app` is the intended public interface.
- The modulefile expects the install root to be `/apps/software/extern/app.GUI/2.0`.
- The current modulefile path in production is `/apps/lmod/extern/app.GUI/2.0.lua`.
