# bazzite-mt7927-docker-vbox

Signed `x86_64` bootc image based on the standard KDE `bazzite-nvidia-open:stable` desktop. It adds the MT7927 driver build from [`samutoljamo/bazzite-mt7927`](https://github.com/samutoljamo/bazzite-mt7927), Docker Engine from Docker's official Fedora repository, and VirtualBox Host from RPM Fusion Free.

Published image:

```text
ghcr.io/x-vlad-x/bazzite-mt7927-docker-vbox:stable
```

## Architecture

The image is built in two stages from the same digest-pinned Bazzite base:

1. The MT7927 stage compiles the pinned `jetm/mediatek-mt7927-dkms` source against the kernel shipped in the selected Bazzite image.
2. The final stage installs the compiled MT7927 modules, Docker CE packages, VirtualBox Host packages, and the exact matching kernel development package.
3. `akmods` is forced to build `vboxdrv`, `vboxnetflt`, and `vboxnetadp` during the image build.
4. The build fails unless all three VirtualBox modules exist and their `vermagic` begins with the exact target kernel version.
5. CI runs independent image checks before pushing `stable`. A failed module build cannot publish a new stable image.

RPM Fusion's current ostree post-install helper calls `akmodsbuild` as root, which `akmods 0.6.2` rejects. The build therefore signature-checks the downloaded `akmod-VirtualBox` RPM, installs that one package without its scripts, resolves and validates all package dependencies, runs `akmodsbuild` as the dedicated `akmods` account through `setpriv`, and installs the resulting kernel-specific kmod RPM. Avoiding a PAM session also makes the build work in restricted rootless CI containers.

The image remains the normal KDE desktop with NVIDIA open kernel modules. It does not use a Deck or DX base and does not add a developer-tool bundle.

Oracle Extension Pack is not included. Install it manually only after reviewing and accepting Oracle's license. Guest Additions belong inside each guest operating system; Bazzite's existing `virtualbox-guest-additions` package is separate from the VirtualBox Host packages installed here.

## Secure Boot

Cosign signs the OCI image digest; it does not make out-of-tree kernel modules trusted by Secure Boot. The MT7927 and VirtualBox modules are built without access to a private module-signing key. If kernel lockdown is active, the modules will not load until they are signed with a key enrolled by the machine owner, or Secure Boot is disabled. The build never embeds a private module-signing key.

## Image signing

The workflow signs every published digest with Cosign. Without repository secrets it uses GitHub Actions OIDC keyless signing tied to this repository and its `main` workflow identity.

To use a persistent Cosign key instead, generate a key pair on a trusted machine:

```bash
cosign generate-key-pair
```

In GitHub, open **Settings → Secrets and variables → Actions → New repository secret**, name the secret `SIGNING_SECRET`, and paste the complete contents of `cosign.key`. Add the key password as a second secret named `COSIGN_PASSWORD`. Keep `cosign.key` private and retain `cosign.pub` for verification. The workflow automatically prefers `SIGNING_SECRET` when it is present.

Keyless signatures can be verified with:

```bash
cosign verify \
  --certificate-identity "https://github.com/x-vlad-x/bazzite-mt7927-docker-vbox/.github/workflows/build.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/x-vlad-x/bazzite-mt7927-docker-vbox:stable
```

## Switch with bootc

Review the repository and the latest successful workflow before switching:

```bash
sudo bootc switch ghcr.io/x-vlad-x/bazzite-mt7927-docker-vbox:stable
```

Reboot only when you are ready to activate the staged deployment:

```bash
sudo systemctl reboot
```

## Checks after the first boot

```bash
bootc status
docker --version
docker compose version
docker buildx version
systemctl status docker.socket
id
kernel="$(uname -r)"
modinfo -F filename vboxdrv
modinfo -F vermagic vboxdrv
modinfo -F vermagic vboxnetflt
modinfo -F vermagic vboxnetadp
test "$(modinfo -F vermagic vboxdrv | cut -d" " -f1)" = "${kernel}"
VirtualBox
```

The first-boot service idempotently adds the first regular local user to `docker` and `vboxusers`. Log out and back in if the new supplementary groups are not visible in an existing session.

> [!WARNING]
> Membership in the `docker` group grants root-equivalent access to the machine. Add only trusted users.

## Rollback

To discard a staged deployment before rebooting:

```bash
sudo bootc rollback
```

After booting the new deployment, use the previous entry in the bootloader menu or run:

```bash
sudo bootc rollback
sudo systemctl reboot
```

## Local validation

```bash
git submodule update --init --recursive
just check
just build
just test
```

The same validation runs in GitHub Actions on pushes, pull requests, manual dispatches, and the weekly scheduled rebuild.
