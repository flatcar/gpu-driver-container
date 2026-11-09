#!/bin/bash
# Import the Flatcar developer container disk image as a container image.
# Usage: import-devcontainer.sh FLATCAR_VERSION

set -euo pipefail

FLATCAR_VERSION=${1:?"Usage: $0 FLATCAR_VERSION"}
: "${BOARD:=amd64-usr}"
: "${IMAGE_NAME:=flatcar-devcontainer}"
: "${HELPER_IMAGE:=ubuntu:24.04}"

# Primary key of the Flatcar Buildbot (Official Builds) signing key.
SIGNING_KEY_FPR=F88CFEDEFF29A5B4D9523864E25D9AED0593B34A
SIGNING_KEY_FILE=$(dirname "$(readlink -f "$0")")/flatcar-image-signing-key.asc

case "${FLATCAR_VERSION}" in
    *.2.*) channel=stable ;;
    *.1.*) channel=beta ;;
    *.0.*) channel=alpha ;;
    *) echo "Unsupported Flatcar version: ${FLATCAR_VERSION}" >&2; exit 1 ;;
esac

case "${BOARD}" in
    amd64-usr) platform=linux/amd64 ;;
    arm64-usr) platform=linux/arm64 ;;
    *) echo "Unsupported board: ${BOARD}" >&2; exit 1 ;;
esac

url="https://${channel}.release.flatcar-linux.net/${BOARD}/${FLATCAR_VERSION}/flatcar_developer_container.bin.bz2"
workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT

echo "Downloading ${url}..."
curl -fsSL --retry 3 -o "${workdir}/dev.bin.bz2" "${url}"
curl -fsSL --retry 3 -o "${workdir}/dev.bin.bz2.sig" "${url}.sig"

echo "Verifying signature..."
export GNUPGHOME="${workdir}/gnupg"
mkdir -m 700 "${GNUPGHOME}"
gpg --batch --quiet --import "${SIGNING_KEY_FILE}"
if ! gpg --batch --status-fd 1 --verify "${workdir}/dev.bin.bz2.sig" "${workdir}/dev.bin.bz2" 2>/dev/null \
        | grep -qE "^\[GNUPG:\] VALIDSIG .* ${SIGNING_KEY_FPR}$"; then
    echo "Signature verification failed for ${url}" >&2
    exit 1
fi
sha256=$(sha256sum "${workdir}/dev.bin.bz2" | cut -d' ' -f1)

# Loop-mounting the disk image needs privileges, so it happens in a helper container.
echo "Importing ${IMAGE_NAME}:${FLATCAR_VERSION}..."
docker run --rm --privileged -v "${workdir}:/work" "${HELPER_IMAGE}" bash -euo pipefail -c '
    apt-get -qq update > /dev/null
    apt-get -qq install -y --no-install-recommends bzip2 fdisk jq > /dev/null
    bzip2 -dc /work/dev.bin.bz2 | cp --sparse=always /dev/stdin /work/dev.bin
    rm /work/dev.bin.bz2
    read -r start size < <(sfdisk -J /work/dev.bin |
        jq -r ".partitiontable.partitions[] | select(.name == \"ROOT\") | \"\(.start) \(.size)\"")
    mkdir /mnt/root
    mount -o ro,loop,offset=$((start * 512)),sizelimit=$((size * 512)) /work/dev.bin /mnt/root
    tar --xattrs --xattrs-include="*" --numeric-owner -C /mnt/root -cf - .
    umount /mnt/root
' | docker import \
        --platform "${platform}" \
        --change 'CMD ["/bin/bash"]' \
        --change "LABEL org.opencontainers.image.title=\"Flatcar developer container\"" \
        --change "LABEL org.opencontainers.image.version=\"${FLATCAR_VERSION}\"" \
        --change "LABEL org.opencontainers.image.source=\"${url}\"" \
        --change "LABEL org.flatcar-linux.devcontainer.sha256=\"${sha256}\"" \
        - "${IMAGE_NAME}:${FLATCAR_VERSION}"

echo "Imported ${IMAGE_NAME}:${FLATCAR_VERSION}"
