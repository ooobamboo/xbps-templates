#!/bin/bash
# install.sh - install the local *-git packages with xbps-install.
#
# Packages are installed straight from the void-packages local repository
# (hostdir/binpkgs). The repository index is regenerated on the fly if it is
# missing, but the packages themselves must be built first
# (e.g. `./xbps-src pkg <pkg>` inside void-packages).
#
# usage: ./install.sh [pkgname ...]
#   with no arguments, installs every *-git package that has a template.
#
# Set XBPS_INSTALL_REPOSITORY to override the local repository path.

set -euo pipefail

cd "$(dirname "$0")"
REPO="${XBPS_INSTALL_REPOSITORY:-$(dirname "$(pwd)")/void-packages/hostdir/binpkgs}"

case "${1:-}" in
	-h|--help|help)
		cat <<EOF
usage: $(basename "$0") [pkgname ...]

Install the local *-git packages from the void-packages repository
via xbps-install.

With no package names, every *-git package that has a template is installed.
The repository index is regenerated if missing; packages must be built first
(e.g. ./xbps-src pkg <pkg> inside void-packages).

Environment:
  XBPS_INSTALL_REPOSITORY    local package repository
                             (default: ../void-packages/hostdir/binpkgs)
EOF
		exit 0
		;;
esac

args=()
if [ $# -eq 0 ]; then
	for d in *-git; do
		[ -d "$d" ] && [ -f "$d/template" ] && args+=("$d")
	done
else
	args=("$@")
fi

if [ ${#args[@]} -eq 0 ]; then
	echo "error: no packages to install" >&2
	exit 1
fi

if ! compgen -G "$REPO"/*.xbps >/dev/null 2>&1; then
	echo "error: no built packages in $REPO (build them first, e.g. ./xbps-src pkg <pkg>)" >&2
	exit 1
fi

if ! compgen -G "$REPO"/*-repodata >/dev/null 2>&1; then
	echo "=> $REPO: regenerating repository index..."
	xbps-rindex -a "$REPO"/*.xbps
fi

echo "=> installing: ${args[*]}"
sudo xbps-install -S --repository="$REPO" "${args[@]}"
