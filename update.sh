#!/bin/bash
# update.sh - bump *-git package templates to the latest upstream commit.
#
# For each package it:
#   1. resolves the upstream default-branch HEAD via `git ls-remote`,
#   2. pins the template `version` to that full commit hash,
#   3. recomputes the distfile SHA256 checksum from the tarball directly.
#
# The plain update path only rewrites templates; building/installing is done
# through the `build` / `install` / `upgrade` subcommands.
#
# usage: ./update.sh [pkgname ...]           update templates + sync to void-packages
#        ./update.sh build [pkgname ...]     sync + recompile via xbps-src
#        ./update.sh install [pkgname ...]   install from the local repo via xbps-install
#        ./update.sh upgrade [pkgname ...]   update + build + install (all of the above)
#
# With no package names, every *-git package that has a template is used.
#
# Each updated template is copied to ../void-packages/srcpkgs/<pkg>/template,
# because xbps-src builds out of a chroot where only void-packages (and its
# hostdir) is reachable -- symlinks pointing back here do not resolve there.
# Override the destination with XBPS_TEMPLATES_SYNC_DIR.

set -euo pipefail

cd "$(dirname "$0")"
SCRIPT_DIR="$(pwd)"
SYNC_DIR="${XBPS_TEMPLATES_SYNC_DIR:-$(dirname "$(pwd)")/void-packages/srcpkgs}"
VP="$(dirname "$(pwd)")/void-packages"

usage() {
	cat <<EOF
usage: $(basename "$0") [pkgname ...]
       $(basename "$0") build|install|upgrade [pkgname ...]

Update, build and install the local *-git packages.

Commands:
  (default)    update templates from upstream (pin version to the latest
               commit, recompute checksums) and sync them to void-packages
  build        sync templates, then recompile via xbps-src
  install      install from the local void-packages repo via xbps-install
  upgrade      update + build + install
  -h, --help   show this help

With no package names, every *-git package that has a template is used.

Environment:
  XBPS_TEMPLATES_SYNC_DIR    void-packages/srcpkgs destination
                             (default: ../void-packages/srcpkgs)
  XBPS_INSTALL_REPOSITORY    local package repository
                             (default: ../void-packages/hostdir/binpkgs)
EOF
}

collect_pkgs() {
	local d
	if [ $# -eq 0 ]; then
		for d in *-git; do
			[ -d "$d" ] && [ -f "$d/template" ] && args+=("$d")
		done
	else
		args=("$@")
	fi
}

build_pkgs() {
	local pkg d
	args=()
	collect_pkgs "$@"
	if [ ${#args[@]} -eq 0 ]; then
		echo "error: no packages to build" >&2
		return 1
	fi

	# make sure void-packages has the latest templates
	for pkg in "${args[@]}"; do
		sync_pkg "$pkg" "$pkg/template"
	done

	echo "=> building: ${args[*]}"
	cd "$VP"
	./xbps-src -b pkg "${args[@]}"
}

upgrade_pkgs() {
	local pkg
	args=()
	collect_pkgs "$@"
	if [ ${#args[@]} -eq 0 ]; then
		echo "error: no packages to upgrade" >&2
		return 1
	fi

	for pkg in "${args[@]}"; do
		update_pkg "$pkg"
	done
	build_pkgs "${args[@]}" || return $?
	"$SCRIPT_DIR/install.sh" "${args[@]}"
}

get_var() {
	awk -v name="$2" 'index($0, name"=") == 1 { sub(/^[^=]*=/, ""); gsub(/^"|"$/, ""); print; exit }' "$1"
}

sync_pkg() {
	local pkg="$1" template="$2"
	local sync="${SYNC_DIR}/$pkg"
	mkdir -p "$sync"
	cp "$template" "$sync/template"
	echo "=> $pkg: synced to $sync/template"
}

update_pkg() {
	local pkg="$1"
	local template="$pkg/template"
	if [ ! -f "$template" ]; then
		echo "error: no template for '$pkg'" >&2
		return 1
	fi

	local homepage version latest distfile checksum
	homepage=$(get_var "$template" homepage)
	version=$(get_var "$template" version)
	[ -n "$homepage" ] || { echo "error: $pkg: homepage not set" >&2; return 1; }

	latest=$(git ls-remote "$homepage" HEAD | awk '{print $1; exit}')
	[ -n "$latest" ] || { echo "error: $pkg: cannot resolve HEAD of $homepage" >&2; return 1; }

	if [ "$latest" = "$version" ]; then
		echo "=> $pkg: already at latest commit ($version)"
		sync_pkg "$pkg" "$template"
		return 0
	fi

	echo "=> $pkg: $version -> $latest"
	sed -i "$template" -e "s|^version=${version}$|version=${latest}|"

	# derive the first distfile URL from the template and substitute the new
	# version, so any host archive layout (github, gitlab, codeberg, sr.ht) works
	distfile=$(get_var "$template" distfiles)
	distfile="${distfile%%$'\n'*}"
	distfile="${distfile%% *}"
    distfile="${distfile//\$\{homepage\}/$homepage}"
	distfile="${distfile//\$homepage/$homepage}"
    distfile="${distfile//\$\{version\}/$latest}"
	[ -n "$version" ] && distfile="${distfile//$version/$latest}"
	checksum=$(curl -fsSL "$distfile" | sha256sum | awk '{print $1}')
	# replace only the first checksum so multi-distfile templates keep the rest
	sed -i "$template" -e "s|^checksum=[0-9a-f]*|checksum=${checksum}|"

	echo "=> $pkg: checksum updated ($checksum)"
	sync_pkg "$pkg" "$template"
}

case "${1:-}" in
	-h|--help|help)
		usage
		exit 0
		;;
	install)
		shift
		exec "$SCRIPT_DIR/install.sh" "$@"
		;;
	build)
		shift
		build_pkgs "$@"
		exit $?
		;;
	upgrade)
		shift
		upgrade_pkgs "$@"
		exit $?
		;;
esac

args=()
collect_pkgs "$@"
if [ ${#args[@]} -eq 0 ]; then
	echo "usage: $0 [pkgname ...]" >&2
	exit 1
fi

for pkg in "${args[@]}"; do
	update_pkg "$pkg"
done
