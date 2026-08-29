# MoonWake CI build script (fork criollojoel10)

Fork de [DPR-MoonWake/KernelAction](https://github.com/DPR-MoonWake/KernelAction)
adaptado para construir los kernels de `criollojoel10/kernel_xiaomi_mt6877`
(Redmi Note 12 Pro/Pro+ 5G / Discovery Edition, MT6877, kernel 4.19 no-GKI)
con KernelSU-Next + SuSFS.

Configs disponibles:

- `configs/{nightly,release}/ksu-susfs.json` — kernel `ksu_susfs` con
  KernelSU-Next `legacy-susfs-v2` (release pineado a `v3.2.0-legacy-susfs-v2`,
  nightly a la rama viva) + fragments `vendor/kernelsu.config` y
  `vendor/susfs.config` (incluye `SUS_MOUNT=y`).
- Configs heredados de upstream (`aeron`, `hyper`/`hypermoon`, `moonwake`)
  para los kernels base de DPR-MoonWake.

DroidSpaces fue eliminado de este tenedor (sin soporte).

---

# MoonWake CI build script

This build script inspired from DogDayAndroid  with some optimization and feature like release, patch kp and more.