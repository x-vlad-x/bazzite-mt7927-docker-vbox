ARG BASE_IMAGE=ghcr.io/ublue-os/bazzite-nvidia-open:stable

FROM scratch AS mt7927-context
COPY build_files/build.sh /build.sh
COPY build_files/config /config
COPY build_files/mediatek-mt7927-dkms /mediatek-mt7927-dkms

FROM scratch AS customization-context
COPY build_files/customize.sh /customize.sh
COPY build_files/repos /repos
COPY system_files /system_files

FROM ${BASE_IMAGE} AS mt7927-builder

RUN --mount=type=bind,from=mt7927-context,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

FROM ${BASE_IMAGE}

COPY --from=mt7927-builder /output/ /

RUN --mount=type=bind,from=customization-context,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/customize.sh

RUN bootc container lint
