#!/bin/sh
#
# build-deb.sh - build the melted Debian (.deb) packages locally.
#
# Produces:
#   melted_<version>_<arch>.deb       (server, clients, libs, MLT modules)
#   melted-dev_<version>_<arch>.deb   (headers, .pc files, .so symlinks)
#
# The resulting .deb files are collected in ./dist/.
#
# Usage:
#   ./build-deb.sh                 build using the version in debian/changelog
#   ./build-deb.sh --auto-version  derive the version from git tags (see below)
#   ./build-deb.sh --version=X.Y.Z use an explicit version
#   ./build-deb.sh --install-deps  apt-get install the build dependencies first
#   ./build-deb.sh --source        also build the source package
#
# Versioning (--auto-version), derived from `git describe --tags`:
#   exact tag  v0.3.12            -> 0.3.12              (clean release)
#   after tag  v0.3.11-5-gabc123  -> 0.3.11+5.gabc123   (snapshot)
#   no tags                       -> 0.0.0+g<shorthash>
# Note: the package is a "native" Debian package, so the version must not
# contain '-'; the snapshot form uses '+'/'.' which also sorts correctly
# (0.3.11 < 0.3.11+5.gabc123 < 0.3.12). --auto-version rewrites the top
# entry of debian/changelog (fine in CI; in a working tree it adds an entry).
#
# This script must be run on a Debian/Ubuntu system (or in a container such
# as `docker run -v "$PWD":/src -w /src debian:stable`). It is CI-friendly:
# any pipeline can simply call it.

set -e

cd "$(dirname "$0")"

INSTALL_DEPS=0
AUTO_VERSION=0
VERSION=""
BUILD_TYPE="-b"   # binary only by default (no orig tarball needed)

for arg in "$@"; do
	case "$arg" in
		--install-deps) INSTALL_DEPS=1 ;;
		--auto-version) AUTO_VERSION=1 ;;
		--version=*)    VERSION="${arg#--version=}" ;;
		--source)       BUILD_TYPE="-F" ;;   # full source + binary
		-h|--help)
			sed -n '2,38p' "$0"
			exit 0
			;;
		*)
			echo "Unknown option: $arg" >&2
			exit 1
			;;
	esac
done

# --- optionally install build dependencies --------------------------------
# Done before the sanity check below so that --install-deps also works on a
# fresh machine that does not yet have dpkg-buildpackage installed.

if [ "$INSTALL_DEPS" = "1" ]; then
	echo ">> Installing build dependencies (requires sudo/root)..."
	if command -v mk-build-deps >/dev/null 2>&1; then
		sudo apt-get update
		sudo apt-get install -y dpkg-dev
		sudo mk-build-deps --install --remove \
			--tool 'apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends -y' \
			debian/control
	else
		sudo apt-get update
		sudo apt-get install -y \
			dpkg-dev build-essential debhelper devscripts pkg-config \
			libmlt-dev libmlt++-dev
	fi
fi

# --- sanity checks --------------------------------------------------------

if ! command -v dpkg-buildpackage >/dev/null 2>&1; then
	echo "error: dpkg-buildpackage not found." >&2
	echo "       Install it with: sudo apt-get install dpkg-dev debhelper" >&2
	echo "       (or re-run this script with --install-deps)" >&2
	exit 1
fi

# --- derive / set the package version -------------------------------------

if [ "$AUTO_VERSION" = "1" ] && [ -z "$VERSION" ]; then
	if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
		echo "error: --auto-version requires git and a git repository." >&2
		exit 1
	fi
	if git describe --tags >/dev/null 2>&1; then
		describe=$(git describe --tags)
		# v0.3.12 -> 0.3.12 ; v0.3.11-5-gabc123 -> 0.3.11+5.gabc123
		VERSION=$(printf '%s' "$describe" | sed -e 's/^v//' -e 's/-/+/' -e 's/-/./g')
	else
		describe="$(git rev-parse --short HEAD)"
		VERSION="0.0.0+g${describe}"
	fi
fi

if [ -n "$VERSION" ]; then
	echo ">> Setting package version to: $VERSION"
	: "${DEBFULLNAME:=premultiply}"
	: "${DEBEMAIL:=4681172+premultiply@users.noreply.github.com}"
	tmp=$(mktemp)
	{
		printf 'melted (%s) unstable; urgency=medium\n\n' "$VERSION"
		printf '  * Automated build (%s).\n\n' "${describe:-version $VERSION}"
		printf ' -- %s <%s>  %s\n\n' "$DEBFULLNAME" "$DEBEMAIL" "$(date -R)"
		cat debian/changelog
	} > "$tmp"
	mv "$tmp" debian/changelog
fi

# --- build ----------------------------------------------------------------

echo ">> Building melted Debian packages..."
dpkg-buildpackage "$BUILD_TYPE" -us -uc

# --- collect artifacts ----------------------------------------------------

mkdir -p dist
# dpkg-buildpackage writes the build products into the parent directory.
mv -f ../melted_*.deb ../melted-dev_*.deb dist/ 2>/dev/null || true
mv -f ../melted_*.changes ../melted_*.buildinfo dist/ 2>/dev/null || true
# Source artifacts (only produced with --source): .dsc and the source tarball.
mv -f ../melted_*.dsc ../melted_*.tar.* dist/ 2>/dev/null || true

echo ""
echo ">> Done. Packages in ./dist/:"
ls -1 dist/*.deb 2>/dev/null || echo "   (no .deb produced - check the build output above)"
