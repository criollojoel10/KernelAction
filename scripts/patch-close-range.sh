#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Patch: arregla close_range(2) O(n) en el backport del kernel 4.19 (Aeron).
#
# Sintoma: en OpenSSH >= 9.x, el cliente ssh/scp tarda ~32 s en arrancar.
# Causa: __range_close() recorre fd++ hasta max_fd; con
#   close_range(3, ~0U, 0)  =>  ~2^31 iteraciones (~32 s de CPU kernel).
# Fix: acotar max_fd a la fdtable, igual que ya hace __range_cloexec().
#
# Se ejecuta DESDE la raiz del arbol del kernel (cwd = KERNEL_NAME).
# Idempotente y seguro: si no encuentra el patron, aborta sin tocar nada.
# ---------------------------------------------------------------------------
set -euo pipefail

F="fs/file.c"
[ -f "$F" ] || { echo "[close-range] ERROR: no encuentro $F (cwd correcto?)"; exit 1; }

if grep -q "min(max_fd, last_fd(files_fdtable(cur_fds)))" "$F"; then
    echo "[close-range] ya aplicado"
    exit 0
fi

if ! grep -q "while (fd <= max_fd) {" "$F"; then
    echo "[close-range] ERROR: patron __range_close no encontrado; aborto sin modificar"
    exit 1
fi

sed -i 's/while (fd <= max_fd) {/while (fd <= min(max_fd, last_fd(files_fdtable(cur_fds)))) {/' "$F"

grep -n "min(max_fd, last_fd(files_fdtable(cur_fds)))" "$F"
echo "[close-range] parche aplicado a $F"
