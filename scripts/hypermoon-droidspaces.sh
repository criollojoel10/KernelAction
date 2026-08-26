#!/bin/bash
set -euo pipefail

# hypermoon-droidspaces.sh - agrega soporte Droidspaces al kernel HyperMoon
# (linux 4.19 no-GKI, xiaomi ruby / mt6877) sin tocar KSU/SuSFS:
#
#   1. Fija la fuente al release EXACTO que usa el dispositivo.
#   2. Integra RKSU v3.0.0-30-legacy (mismo lineamiento que el manager).
#   3. Backports A+B (fixes hypermoon main seguros + RubyxLabs reciente).
#   4. Aplica parches non-GKI oficiales de Droidspaces-OSS.
#   5. Genera ruby_droidspaces_defconfig (ruby_defconfig queda intacto).
#
# Se ejecuta desde el workflow con cwd = raiz del arbol del kernel,
# ANTES del paso "Make defconfig".
#
# Doc: https://github.com/ravindu644/Droidspaces-OSS/blob/main/Documentation/Kernel-Configuration.md
# (seccion "Configuring Non-GKI Kernels (Legacy Kernels)")

BASE="https://raw.githubusercontent.com/ravindu644/Droidspaces-OSS/main/Documentation/resources/kernel-patches/non-GKI"

echo "[droidspaces] directorio del kernel: $(pwd)"

# ------------------------------------------------- fijar fuente al release
# El kernel del dispositivo (artefacto upstream "beba7f1") se construyo
# desde beba7f1c, NO desde el tag 1.0.2 (= b76f3eea) ni desde main
# (regresiones de susfs 2.1.0 en task_mmu.c/cgroup de abril 2026).
#
# GitHub rechaza fetch por SHA ancestro ("not our ref"), asi que:
#   1. checkout del tag 1.0.2 (ref tip, si se puede fetchear), y
#   2. sobrescribir los UNICOS 3 archivos que difieren entre el tag y
#      beba7f1c (verificado via API compare), usando el raw oficial.
DS_TAG="1.0.2"
DS_PIN="beba7f1c08d6631d53a92ed1f202c4318c4fae02"
# raw.githubusercontent solo resuelve este commit con SHA corto
DS_PIN_SHORT="${DS_PIN:0:7}"
RAW_BASE="https://raw.githubusercontent.com/DXRN-MoonWake/hypermoon_kernel_xiaomi_ruby/$DS_PIN_SHORT"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  CURRENT_SHA="$(git rev-parse HEAD 2>/dev/null || echo none)"
  if [ "$CURRENT_SHA" != "$DS_TAG" ]; then
    echo "[droidspaces] fijando fuente: tag $DS_TAG + delta del release ${DS_PIN_SHORT} (antes: ${CURRENT_SHA:0:9})"
    git remote get-url origin >/dev/null 2>&1 || \
      git remote add origin https://github.com/DXRN-MoonWake/hypermoon_kernel_xiaomi_ruby
    git fetch --depth=1 origin "refs/tags/$DS_TAG:refs/tags/$DS_TAG"
    # checkout forzado: descarta cualquier estado previo del arbol
    git checkout --force "refs/tags/$DS_TAG"
    for f in \
      include/linux/susfs.h \
      include/linux/susfs_def.h \
      arch/arm64/configs/vendor/susfs.config
    do
      echo "[droidspaces] sincronizando con release: $f"
      curl -fsSL "$RAW_BASE/$f" -o "$f"
    done
    echo "[droidspaces] fuente fijada (base $(git rev-parse --short=7 HEAD) + delta ${DS_PIN_SHORT})"
  else
    echo "[droidspaces] fuente ya esta en $DS_TAG"
  fi
fi

# Si esta variante integra KernelSU: integracion AUTO-GESTIONADA.
# El setup.sh del workflow clona la rama default de forma superficial y
# su checkout de un sha/tag antiguo FALLA EN SILENCIO (queda en master),
# y master reciente perdio compatibilidad con kernels 4.19 no-GKI
# (refactors de hooks/kprobes/sucompat de marzo). Aqui clonamos
# DIRECTAMENTE el tag legacy que corresponde al manager RKSU 3.0 legacy
# instalado en el dispositivo.
DS_RKSU_TAG="v3.0.0-30-legacy"
if [ -n "${kernelSUsetupLink:-}" ] && [ "${kernelSUsetupLink}" != "disabled" ]; then
  echo "[droidspaces] integrando RKSU ${DS_RKSU_TAG} (autogestionado)"
  rm -rf KernelSU
  git clone --depth=1 --branch "$DS_RKSU_TAG" \
    https://github.com/DPR-MoonWake/RKSU KernelSU
  ln -sf ../KernelSU/kernel drivers/kernelsu
  grep -q "kernelsu" drivers/Makefile || \
    printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> drivers/Makefile
  grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig || \
    sed -i "/endmenu/i\source \"drivers/kernelsu/Kconfig\"" drivers/Kconfig
  echo "[droidspaces] RKSU integrado: $(git -C KernelSU describe --tags 2>/dev/null || git -C KernelSU rev-parse --short HEAD)"
fi

# ------------------------------------------------------------- updates A+B
# Backports selectos SIN tocar KSU/SuSFS:
#  A) hypermoon main: fixes FROMGIT seguros (panel/proc/ln8000)
#  B) RubyxLabs lineage-23.2 reciente: seguridad BPF, proc map_files,
#     charger/thermal/gpu/ion/soc logging, mm compaction.
# Excluidos: reverts de politica de LineageOS (16-jul), commits de
# susfs/KSU-hook de main, y config zram writeback (usamos defconfig propio).
# Un parche que no aplique se OMITE con aviso (no rompe la build).
DS_UPDATES="
DXRN-MoonWake/hypermoon_kernel_xiaomi_ruby|0590b031|HM panel: disable 30hz
DXRN-MoonWake/hypermoon_kernel_xiaomi_ruby|435c514e|HM fs/proc: fix crashing issue
RubyxLabs/kernel_xiaomi_mt6877|e296574a|RL gpu: synchronous event wakeups
RubyxLabs/kernel_xiaomi_mt6877|0045b1d1|RL ion: demote DMA cache sync logs
RubyxLabs/kernel_xiaomi_mt6877|853fe3fd|RL soc: demote DFD timeout logs
RubyxLabs/kernel_xiaomi_mt6877|c3aa4c17|RL mm: refine compaction retry handling
RubyxLabs/kernel_xiaomi_mt6877|a5de0118|RL gpu: reuse cached state DVFS logging
RubyxLabs/kernel_xiaomi_mt6877|d43609da|RL thermal: defer USB psy notifications
RubyxLabs/kernel_xiaomi_mt6877|8449b98b|RL charger: demote monitor status logs
RubyxLabs/kernel_xiaomi_mt6877|aa6aca24|RL charger: drop periodic register dumps
DXRN-MoonWake/hypermoon_kernel_xiaomi_ruby|742b01bf|HM ln8000: respect regmap_read api
RubyxLabs/kernel_xiaomi_mt6877|a16a4b2f|RL skbuff: skb_network_header_was_set helper
RubyxLabs/kernel_xiaomi_mt6877|ad765016|RL bpf: null prog array check
RubyxLabs/kernel_xiaomi_mt6877|62a18ae5|RL bpf: validate effective prog array
RubyxLabs/kernel_xiaomi_mt6877|cac04e5a|RL proc/map_files: kvmalloc_array
"

echo "$DS_UPDATES" | while IFS= read -r line; do
  [ -z "$line" ] && continue
  repo="$(echo "$line" | cut -d'|' -f1)"
  sha="$(echo "$line" | cut -d'|' -f2)"
  title="$(echo "$line" | cut -d'|' -f3)"
  case "$sha" in *unused*|"") continue;; esac
  url="https://github.com/$repo/commit/$sha.patch"
  if ! curl -fsSL "$url" -o /tmp/ds_upd.patch 2>/dev/null; then
    echo "[updates] OMITIDO (descarga): $title ($sha)"
    continue
  fi
  # dry-run primero: aplicacion atomica, sin hunks parciales
  if patch -p1 --forward --fuzz=3 --dry-run < /tmp/ds_upd.patch >/dev/null 2>&1; then
    patch -p1 --forward --fuzz=3 < /tmp/ds_upd.patch >/dev/null 2>&1
    echo "[updates] OK      : $title ($sha)"
  elif patch -p1 --forward --fuzz=3 -R --dry-run < /tmp/ds_upd.patch >/dev/null 2>&1; then
    echo "[updates] YA ESTABA: $title ($sha)"
  else
    echo "[updates] OMITIDO (conflicto): $title ($sha)"
  fi
done

# ---------------------------------------------------------------- parches
apply_ds_patch() {
  fname="$1"
  target="$2"
  url="$BASE/$3"
  if [ ! -f "$target" ]; then
    echo "[droidspaces] omitido: $fname (no existe $target en este arbol)"
    return 0
  fi
  echo "[droidspaces] aplicando: $fname"
  curl -fsSL "$url" -o /tmp/ds_patch.diff
  if patch -p1 --forward --fuzz=3 < /tmp/ds_patch.diff; then
    echo "[droidspaces] OK: $fname"
  else
    echo "[droidspaces] FALLO al aplicar: $fname" >&2
    exit 1
  fi
}

apply_ds_patch \
  "01.fix_kernel_panic_in_xt_qtaguid.patch" \
  "net/netfilter/xt_qtaguid.c" \
  "01.fix_kernel_panic_in_xt_qtaguid.patch"

apply_ds_patch \
  "02.fix_restore cgroup file prefix handling .patch" \
  "kernel/cgroup/cgroup.c" \
  "02.fix_restore%20cgroup%20file%20prefix%20handling%20.patch"

# ---------------------------------------------------------------- defconfig
SRC_DEFCONFIG="arch/arm64/configs/ruby_defconfig"
DST_DEFCONFIG="arch/arm64/configs/ruby_droidspaces_defconfig"

[ -f "$SRC_DEFCONFIG" ] || { echo "[droidspaces] FALLO: no existe $SRC_DEFCONFIG" >&2; exit 1; }

cp "$SRC_DEFCONFIG" "$DST_DEFCONFIG"

cat >> "$DST_DEFCONFIG" <<'EOF'

# ------------------------------------------------------------------
# Soporte DroidSpaces (non-GKI legacy 4.19)
# https://github.com/ravindu644/Droidspaces-OSS/blob/main/Documentation/Kernel-Configuration.md
# ------------------------------------------------------------------
# IPC mechanisms
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
# Core namespace support
CONFIG_NAMESPACES=y
CONFIG_PID_NS=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
# Fix docker unsafe procfs
CONFIG_USER_NS=y
# Network namespace (NAT/none modes)
CONFIG_NET_NS=y
# Seccomp support
CONFIG_SECCOMP=y
CONFIG_SECCOMP_FILTER=y
# Control groups support
CONFIG_CGROUPS=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CGROUP_PIDS=y
CONFIG_MEMCG=y
CONFIG_CGROUP_SCHED=y
CONFIG_FAIR_GROUP_SCHED=y
CONFIG_CGROUP_FREEZER=y
CONFIG_CGROUP_NET_PRIO=y
# Device filesystem support
CONFIG_DEVTMPFS=y
# Overlay filesystem (volatile mode)
CONFIG_OVERLAY_FS=y
# tmpfs xattr/acl
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_TMPFS_XATTR=y
# Firmware loading support
CONFIG_FW_LOADER=y
CONFIG_FW_LOADER_USER_HELPER=y
# Network isolation (NAT mode)
CONFIG_VETH=y
CONFIG_BRIDGE=y
CONFIG_NETFILTER=y
CONFIG_BRIDGE_NETFILTER=y
CONFIG_NETFILTER_ADVANCED=y
CONFIG_NF_CONNTRACK=y
CONFIG_IP_NF_IPTABLES=y
CONFIG_IP_NF_FILTER=y
CONFIG_NF_NAT=y
CONFIG_NF_TABLES=y
CONFIG_IP_NF_TARGET_MASQUERADE=y
CONFIG_NETFILTER_XT_TARGET_MASQUERADE=y
CONFIG_NETFILTER_XT_TARGET_TCPMSS=y
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
CONFIG_NF_CONNTRACK_NETLINK=y
CONFIG_NF_NAT_REDIRECT=y
CONFIG_IP_ADVANCED_ROUTER=y
CONFIG_IP_MULTIPLE_TABLES=y
# legacy compat (kernel 4.19)
CONFIG_NF_CONNTRACK_IPV4=y
CONFIG_NF_NAT_IPV4=y
CONFIG_IP_NF_NAT=y
# requerido para que internet funcione en containers en kernels viejos
# CONFIG_ANDROID_PARANOID_NETWORK is not set
EOF

echo "[droidspaces] defconfig generado: $DST_DEFCONFIG"

# ------------------------------------------------------- version string
# Igual que hypermoon-exp-version.sh pero marcando la build como DroidSpaces
# y usando el hash del release real (beba7f1), no el del tag base.
rm -f localversion-hypermoon
echo "-HyperMoon-DroidSpaces-CI" > localversion-00-experimental
echo "-${DS_PIN_SHORT}" > localversion-01-experimental
echo "-${RUN_NUMBER:-0}" > localversion-02-experimental

echo "[droidspaces] listo"
