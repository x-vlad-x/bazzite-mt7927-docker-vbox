image_name := env("IMAGE_NAME", "bazzite-mt7927-docker-vbox")
default_tag := env("DEFAULT_TAG", "stable")
base_image := env("BASE_IMAGE", "ghcr.io/ublue-os/bazzite-nvidia-open:stable")

default:
    @just --list

check:
    bash -n build_files/build.sh
    bash -n build_files/customize.sh
    bash -n build_files/verify-image.sh
    bash -n system_files/usr/libexec/bazzite-configure-primary-user-groups

build:
    podman build --pull=newer --build-arg "BASE_IMAGE={{ base_image }}" --tag "{{ image_name }}:{{ default_tag }}" .

test:
    build_files/verify-image.sh "{{ image_name }}:{{ default_tag }}"
