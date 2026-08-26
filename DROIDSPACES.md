# HyperMoon-DroidSpaces — Documentación completa

Kernel personalizado para **Xiaomi Redmi Note 12 Pro / Pro+ 5G (ruby, MediaTek mt6877)**:
base **HyperMoon 1.0.2** exacta (la que corre el dispositivo) + **KernelSU/SuSFS intactos**
+ **soporte Droidspaces** para contenedores Linux en Android.

Mantenido en el fork `criollojoel10/KernelAction`. Todo el trabajo se hizo vía GitHub API,
sin clonar ningún repositorio localmente.

---

## 1. Base sobre la que se construye

| Componente | Valor |
|---|---|
| Árbol fuente | [DXRN-MoonWake/hypermoon_kernel_xiaomi_ruby](https://github.com/DXRN-MoonWake/hypermoon_kernel_xiaomi_ruby) |
| Commit base | `beba7f1c08d6631d53a92ed1f202c4318c4fae02` ("Modify SuSFS configuration options", 22-ene-2026) |
| Versión Linux real | **4.19.325 (no-GKI legacy)** — sublevel final de la LTS 4.19 (EOL kernel.org dic-2024) |
| Versión reportada | `5.10.246` — spoof cosmético del propio árbol (commit `dc674dd0`) |
| Defconfig | `ruby_defconfig` → se genera `ruby_droidspaces_defconfig` (el original queda intacto) |
| Root | **KernelSU-Next `v3.1.0-legacy-susfs`** (`ba4422f0`, rifsxd) — alineado al manager `com.rifsxd.ksunext` 3.x del dispositivo. Configs KSU fijados de forma determinista en el defconfig generado (MANUAL_HOOK=y + SuSFS completo); los fragments extraConfig quedan como respaldo redundante |

### Por qué `beba7f1c` y ni el tag ni main

* El **tag `1.0.2`** apunta a `b76f3eea`, un commit ANTES del artefacto que upstream publicó
  (sus builds se llaman literalmente `beba7f1`). En el tag falta la definición de
  `struct st_susfs_hide_sus_mnts_for_non_su_procs` en `include/linux/susfs.h`
  → la pata KSU no compila (tipo incompleto).
* **`main` está roto desde abril-2026**: la reimplantación susfs 2.1.0 (`90a9396b`)
  introdujo `mmap_read_unlock()` (API 5.x) en `fs/proc/task_mmu.c` de un árbol 4.19
  → falla con `-Werror` en CUALQUIER build de main.
* GitHub rechaza `git fetch <sha>` de commits ancestro (`upload-pack: not our ref`),
  por eso el script hace checkout del **tag** (ref tip, fetchable) y sobrescribe los
  únicos **3 archivos** que difieren hasta `beba7f1c` usando raw.githubusercontent:

```
include/linux/susfs.h
include/linux/susfs_def.h
arch/arm64/configs/vendor/susfs.config
```

> Nota: raw.githubusercontent resuelve este commit solo con **SHA corto**
> (`beba7f1c`); con SHA completo devuelve 404.

---

## 2. Soporte Droidspaces agregado

Según la guía oficial
[Droidspaces-OSS · Kernel-Configuration.md](https://github.com/ravindu644/Droidspaces-OSS/blob/main/Documentation/Kernel-Configuration.md),
sección *Non-GKI Kernels (Legacy Kernels)* — aplica porque el árbol real es 4.19.

### Configs (`ruby_droidspaces_defconfig` = copia de `ruby_defconfig` + bloque)

* IPC: `SYSVIPC`, `POSIX_MQUEUE`
* Namespaces: `NAMESPACES`, `PID_NS`, `UTS_NS`, `IPC_NS`, `USER_NS`, `NET_NS`
* Seccomp: `SECCOMP`, `SECCOMP_FILTER`
* Cgroups: `CGROUPS`, `CGROUP_DEVICE`, `CGROUP_PIDS`, `MEMCG`, `CGROUP_SCHED`,
  `FAIR_GROUP_SCHED`, `CGROUP_FREEZER`, `CGROUP_NET_PRIO`
* FS: `DEVTMPFS`, `OVERLAY_FS`, `TMPFS_POSIX_ACL`, `TMPFS_XATTR`
* Firmware: `FW_LOADER`, `FW_LOADER_USER_HELPER` (se omite `FW_LOADER_COMPRESS`: no existe en 4.19)
* Red/NAT: `VETH`, `BRIDGE`, `BRIDGE_NETFILTER`, `NF_CONNTRACK(+NETLINK)`,
  `IP_NF_IPTABLES/FILTER/NAT`, `NF_NAT(+REDIRECT,+IPV4)`, `NF_TABLES`,
  `MASQUERADE`(x2), `TCPMSS`, `ADDRTYPE`, `IP_ADVANCED_ROUTER`, `IP_MULTIPLE_TABLES`
* `# CONFIG_ANDROID_PARANOID_NETWORK is not set` (internet dentro de contenedores)

### Parches non-GKI oficiales

| Parche | Estado | Motivo |
|---|---|---|
| `01.fix_kernel_panic_in_xt_qtaguid.patch` | omitido automático | este árbol MTK no tiene `net/netfilter/xt_qtaguid.c` |
| `02.fix_restore cgroup file prefix handling .patch` | **aplicado** | requerido por LXC/Droidspaces (kernfs links en raíces NOPREFIX) |

El script omite automáticamente parches cuyo archivo destino no exista y detecta
parches ya aplicados (dry-run antes de aplicar: nunca deja hunks parciales).

---

## 3. Actualizaciones backport (A+B), sin tocar KSU/SuSFS

Fase `[updates]` del script: descarga `https://github.com/<repo>/commit/<sha>.patch`
(funciona incluso para commits que no son punta de rama) y aplica en orden cronológico.
Un parche que falle dry-run se **omite con aviso**, jamás rompe la build.

### A — hypermoon main (solo fixes seguros)

| Commit | Contenido | Resultado build #7 |
|---|---|---|
| `0590b031` | panel: disable 30hz | ✅ aplicado |
| `435c514e` | fs/proc: fix crashing issue | ⏭️ omitido (conflicto: hecho sobre el código roto de main; la base beba7f1 no lo necesita) |
| `742b01bf` | ln8000: respect regmap_read api (cargador) | ✅ aplicado |

### B — RubyxLabs lineage-23.2 (upstream del dispositivo)

| Commit | Contenido | Resultado build #7 |
|---|---|---|
| `a16a4b2f` | skbuff: helper skb_network_header_was_set | ✅ aplicado |
| `ad765016` | bpf: null prog array check (seguridad) | ✅ aplicado |
| `62a18ae5` | bpf: validate effective prog array | ⏭️ omitido (depende de contexto lineage más nuevo) |
| `cac04e5a` | proc/map_files: kvmalloc_array | ⏭️ omitido (conflicto) |
| `c3aa4c17` | mm: refine compaction retry handling | ✅ aplicado |
| `aa6aca24` / `8449b98b` | charger: dumps/logs | ✅ aplicados ×2 |
| `d43609da` | thermal: defer USB psy notifications | ✅ aplicado |
| `a5de0118` / `e296574a` | gpu mtk: DVFS logging / wakeups | ✅ aplicados ×2 |
| `853fe3fd` / `0045b1d1` | soc DFD / ion DMA logs | ✅ aplicados ×2 |

**Excluidos a propósito** (política, riesgo o irrelevancia):
revert-batch de LineageOS del 16-jul (mm/gpu/binder/selinux tweaks),
`6f34ef84` zram writeback config (usamos defconfig propio), y TODO commit de
susfs/KSU-hook de hypermoon main (`4abaf4d2`…`2cfcefd3`).

---

## 4. Cómo funciona el pipeline

```
configs/{nightly,release}/hypermoon-droidspaces.json   ← matrices Vanilla + KSU
scripts/hypermoon-droidspaces.sh                        ← toda la integración
```

Flujo por variante (workflow `build.yml` upstream, sin modificar):

1. Clone de hypermoon (branch main) + toolchain clang r383902
2. *(solo KSU)* Integración RKSU del workflow
3. **Nuestro script** (`additional_script_link`):
   checkout tag `1.0.2` + delta 3 archivos → re-setup KSU (el checkout revierte
   drivers/Makefile+Kconfig editados por RKSU) → updates A+B → parches
   Droidspaces → genera `ruby_droidspaces_defconfig` → localversion
4. `make ruby_droidspaces_defconfig && make Image.gz` (LLVM/clang, LTO+CFI del tree)
5. AnyKernel3 zip (release: rama `hyper`; nightly: `hyper_dev`)

### Versionado embebido

```
5.10.246-HyperMoon-DroidSpaces-CI-beba7f1-<run_number>
```

## 5. Construir

Actions → *Build MoonWake Kernel* → Run workflow:

| Input | Valor recomendado |
|---|---|
| `config_type` | `release` |
| `config_file` | `hypermoon-droidspaces.json` |
| `full_dump` | `true` |
| `send_to_telegram` | `false` (no hay secrets en el fork) |

Artefacto correcto para flashear: **`HyperMoon-KSU-DroidSpaces-*`** (AnyKernel3 zip).
La variante Vanilla es respaldo sin root.

---

## 6. Historial de fallos resueltos (referencia rápida)

| Síntoma | Causa raíz | Solución |
|---|---|---|
| `curl: (3) URL rejected` post-build | regresión upstream: workflow actual lee key JSON `additional_script_post_link`, los configs usaban nombre viejo | renombrar key en configs propios |
| `implicit declaration 'mmap_read_unlock'` | main roto por susfs 2.1.0 (abril) | construir desde release, no main |
| `incomplete type st_susfs_hide_sus_mnts_for_non_su_procs` | tag 1.0.2 = commit anterior al artefacto publicado | delta de 3 archivos hasta `beba7f1c` |
| `upload-pack: not our ref <sha>` | GitHub no permite fetch de SHA ancestro | checkout de tag + overwrite vía raw |
| raw 404 con SHA completo | quirk de raw.githubusercontent | usar SHA corto |
| `out/arch/arm64/boot: No such file or directory` | síntomas previos; el paso de empaquetado no encontró Image porque el build falló antes | diagnosticar el error real arriba |

## 7. Mantenimiento futuro

* **Nuevo parche**: añadir línea `repo|sha|titulo` a `DS_UPDATES` en el script.
* **Nueva base hypermoon**: actualizar `DS_TAG`/delta tras verificar con
  `compare` qué cambió entre tag y artefacto.
* **RKSU**: cambiar `DS_RKSU_TAG` en el script (integración autogestionada).
  ⚠️ NO usar `setupArg` del workflow para fijar versiones: `setup.sh` clona
  de forma superficial y el checkout de un SHA/tag antiguo **falla en silencio**
  (queda en master). Los builds #6/#7 perdieron root por esto: master de marzo
  rompió compatibilidad 4.19 no-GKI (refactors hooks/kprobes/sucompat).
  Síntoma en dispositivo: boot OK pero `su` con ENOENT aunque el manager
  diga Working; además SUS_PATH oculta `su` a UIDs no autorizados.
* **Verificar Droidspaces tras flashear**: app → Settings → Requirements →
  Check Requirements, o `su -c droidspaces check`.

---
*Generado el 2026-08-26 · builds verificados: run [#32902400008](https://github.com/criollojoel10/KernelAction/actions/runs/32902400008) (base) y [#32912554146](https://github.com/criollojoel10/KernelAction/actions/runs/32912554146) (updates A+B).*
