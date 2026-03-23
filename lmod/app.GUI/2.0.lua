-- -*- lua -*-
-- Modulefile for app.GUI
-- Unified TurboVNC-based GUI launcher for ARCH compute nodes.

local doclink = "https://www.turbovnc.org"
local root = "/data/apps/extern/app.GUI/2.0"

whatis([[Name : app.GUI]])
whatis([[Description : Launch GUI applications on ARCH compute nodes through TurboVNC]])
whatis("URL: " .. doclink)

help([[
app.GUI provides a unified launcher for GUI applications on ARCH compute nodes using TurboVNC.

CPU is the default backend. Add --gpu when you want the GPU-enabled path.

Common commands:
  app --help
  app --start-session
  app --run <application> [args...]
  app --gpu --start-session
  app --gpu --run <application> [args...]
]])

if (mode() == "load") then
   if string.match(capture("hostname"), "login") then
      LmodError([[
ARCH Warning: app.GUI only works on a compute node.
Start an interactive session or submit a SLURM job first.
]])
   end
end

if (mode() == "load") then
  LmodMessage([[
============================================================
app.GUI quick start
============================================================

1. On a compute node, load the module:
   $ module load app.GUI/2.0

2. Start a GUI session:
   CPU default:
   $ app --start-session &

   GPU:
   $ app --gpu --start-session &

3. If you want to choose a resolution interactively, run the command in the foreground.
   For background mode, pass it explicitly, for example:
   $ app --geometry 1920x1080 --start-session &
   $ app --gpu --geometry 2560x1440 --start-session &

4. Follow the printed tunnel instructions, then connect your local TurboVNC client.
   The connection details are also written to:
   $HOME/connection.yml

5. Launch applications from the same shell:
   $ app --run xterm
   $ app --run matlab -desktop

   GPU examples:
   $ app --gpu --run matlab -desktop

6. If needed, inspect the saved GUI environment:
   $ app --print-env

7. Futher details:
   $ app --help

Supported resolutions:
  1024x768
  1280x1024
  1920x1080
  2560x1440
============================================================
]])
end

load("qt/5.14.2")
prepend_path("PATH", pathJoin(root, "bin"))
setenv("QNVSM", root)
