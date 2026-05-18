#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <ffmpeg-kit.aar>" >&2
  exit 64
fi

AAR_PATH="$1"

if [[ ! -f "${AAR_PATH}" ]]; then
  echo "AAR not found: ${AAR_PATH}" >&2
  exit 66
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

ENTRIES_FILE="${TMP_DIR}/entries.txt"
ABIS_FILE="${TMP_DIR}/abis.txt"

unzip -Z1 "${AAR_PATH}" >"${ENTRIES_FILE}"

if grep -q 'libc++_shared\.so$' "${ENTRIES_FILE}"; then
  echo "AAR must not package libc++_shared.so; use the app/runtime copy instead." >&2
  exit 1
fi

awk -F/ '$1 == "jni" && $2 != "" && $3 ~ /\.so$/ { print $2 }' "${ENTRIES_FILE}" |
  sort -u >"${ABIS_FILE}"

for required_abi in arm64-v8a armeabi-v7a; do
  if ! grep -qx "${required_abi}" "${ABIS_FILE}"; then
    echo "Missing required ABI: ${required_abi}" >&2
    printf 'Found ABIs: %s\n' "$(tr '\n' ' ' <"${ABIS_FILE}")" >&2
    exit 1
  fi
done

for unsupported_abi in x86 x86_64; do
  if grep -qx "${unsupported_abi}" "${ABIS_FILE}"; then
    echo "Unexpected unsupported ABI in Photos AAR: ${unsupported_abi}" >&2
    exit 1
  fi
done

unzip -q "${AAR_PATH}" 'jni/*/*.so' -d "${TMP_DIR}"

LIBAVCODEC="${TMP_DIR}/jni/arm64-v8a/libavcodec.so"
if [[ ! -f "${LIBAVCODEC}" ]]; then
  echo "Missing arm64-v8a libavcodec.so" >&2
  exit 1
fi

LIBAVCODEC_STRINGS="${TMP_DIR}/libavcodec.strings"
strings "${LIBAVCODEC}" >"${LIBAVCODEC_STRINGS}"

for option in --enable-libx264 --enable-libzimg --enable-zlib --enable-gpl; do
  if ! grep -q -- "${option}" "${LIBAVCODEC_STRINGS}"; then
    echo "Missing FFmpeg configure option: ${option}" >&2
    exit 1
  fi
done

if ! grep -q '^libx264' "${LIBAVCODEC_STRINGS}"; then
  echo "libx264 symbols were not found in libavcodec.so" >&2
  exit 1
fi

if [[ "${ALLOW_LOCAL_BUILD:-0}" != "1" ]] &&
  grep -q '/Users/' "${LIBAVCODEC_STRINGS}"; then
  echo "AAR appears to come from a local macOS build; refusing local artifact." >&2
  exit 1
fi

if [[ "${REQUIRE_CI_PATH:-0}" == "1" ]] &&
  ! grep -q '/home/runner/' "${LIBAVCODEC_STRINGS}"; then
  echo "AAR does not include GitHub Actions runner paths in FFmpeg config." >&2
  exit 1
fi

READELF="${READELF:-}"
if [[ -z "${READELF}" ]] && command -v llvm-readelf >/dev/null 2>&1; then
  READELF="$(command -v llvm-readelf)"
fi
if [[ -z "${READELF}" && -n "${ANDROID_NDK_ROOT:-}" ]]; then
  READELF="$(find "${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt" -path '*/bin/llvm-readelf' \( -type f -o -type l \) -print -quit)"
fi
if [[ -z "${READELF}" || ! -x "${READELF}" ]]; then
  echo "llvm-readelf not found. Set READELF or ANDROID_NDK_ROOT." >&2
  exit 69
fi

python3 - "${READELF}" "${TMP_DIR}/jni" <<'PY'
import pathlib
import subprocess
import sys

readelf = sys.argv[1]
jni_dir = pathlib.Path(sys.argv[2])
minimum_alignment = 0x4000
failures = []

for so_path in sorted(jni_dir.glob("*/*.so")):
    output = subprocess.check_output(
        [readelf, "-lW", str(so_path)],
        text=True,
        stderr=subprocess.STDOUT,
    )
    for line in output.splitlines():
        fields = line.split()
        if not fields or fields[0] != "LOAD":
            continue
        alignment = int(fields[-1], 0)
        if alignment < minimum_alignment:
            failures.append(f"{so_path.relative_to(jni_dir)} LOAD align {fields[-1]}")

if failures:
    print("Native libraries are not 16 KB page-size aligned:", file=sys.stderr)
    for failure in failures:
        print(f"  {failure}", file=sys.stderr)
    sys.exit(1)
PY

echo "Validated ${AAR_PATH}"
