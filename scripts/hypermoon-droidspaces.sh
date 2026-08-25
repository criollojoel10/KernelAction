#!/bin/bash
set -euo pipefail

# hypermoon-droidspaces.sh - agrega soporte Droidspaces al kernel HyperMoon
# (linux 4.19 no-GKI, xiaomi ruby / mt6877) sin tocar nada mas del kernel:
#
#   1. Aplica los parches non-GKI oficiales de Droidspaces-OSS que apliquen
#      al arbol (los que apunten a archivos inexistentes se omiten).
#   2. Genera arch/arm64/configs/ruby_droidspaces_defconfig a partir de
#      ruby_defconfig (que queda intacto) agregando el bloque obligatorio
#      de la documentacion oficial, adaptado a 4.19.
#
# Se ejecuta desde el workflow con cwd = raiz del arbol del kernel,
# ANTES del paso "Make defconfig".
#
# Doc: https://github.com/ravindu644/Droidspaces-OSS/blob/main/Documentation/Kernel-Configuration.md
# (seccion "Configuring Non-GKI Kernels (Legacy Kernels)")

BASE="https://raw.githubusercontent.com/ravindu644/Droidspaces-OSS/main/Documentation/resources/kernel-patches/non-GKI"

echo "[droidspaces] directorio del kernel: $(pwd)"

# ------------------------------------------------- fijar fuente al release
# El kernel que corre en el dispositivo (artefacto upstream "beba7f1") se
# construyo desde beba7f1c, NO desde el tag 1.0.2 (= b76f3eea) ni desde
# main (regresiones de susfs 2.1.0 en task_mmu.c/cgroup de abril 2026).
#
# GitHub rechaza fetch por SHA ancestro ("not our ref"), asi que:
#   1. checkout del tag 1.0.2 (ref tip, si se puede fetchear), y
#   2. sobrescribir los UNICOS 3 archivos que difieren entre el tag y
#      beba7f1c (verificado via API compare), usando el raw oficial.
DS_TAG="1.0.2"
DS_PIN="beba7f1c08d6631d53a92ed1f202c4318c4fae02"
RAW_BASE="https://raw.githubusercontent.com/DXRN-MoonWake/hypermoon_kernel_xiaomi_ruby/$DS_PIN"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  CURRENT_SHA="$(git rev-parse HEAD 2>/dev/null || echo none)"
  if [ "$CURRENT_SHA" != "$DS_TAG" ]; then
    echo "[droidspaces] fijando fuente: tag $DS_TAG + delta del release ${DS_PIN:0:9} (antes: ${CURRENT_SHA:0:9})"
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
    echo "[droidspaces] fuente fijada (base $(git rev-parse --short=7 HEAD) + delta ${DS_PIN:0:7})"
  else
    echo "[droidspaces] fuente ya esta en $DS_TAG"
  fi
fi

# Si esta variante integra KernelSU, re-ejecutar su setup: el checkout
# anterior revierte las ediciones de drivers/Makefile y drivers/Kconfig
# que hizo el paso "Integrate Kernel Root implementation" del workflow.
# (setup.sh es idempotente: grep antes de editar y ln -sf.)
if [ -n "${kernelSUsetupLink:-}" ] && [ "${kernelSUsetupLink}" != "disabled" ]; then
  echo "[droidspaces] re-integrando KernelSU (${kernelSUsetupName:-KSU})"
  curl -LSs "${kernelSUsetupLink}" | bash -s "${kernelSUsetupArg:-}"
fi

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
echo "-${DS_PIN:0:7}" > localversion-01-experimental
echo "-${RUN_NUMBER:-0}" > localversion-02-experimental

echo "[droidspaces] listo"
