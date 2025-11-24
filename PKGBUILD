# Maintainer: Ola Hulleberg <ola@hulleberg.net>
pkgname=waylight
pkgver=0.1.0
pkgrel=1
pkgdesc="A fast application launcher for Wayland"
arch=('x86_64')
url="https://github.com/OlaHulleberg/waylight"
license=('MIT')
depends=('gtk4' 'gtk4-layer-shell' 'webkitgtk-6.0' 'wl-clipboard' 'libqalculate')
makedepends=('zig')
source=("$pkgname-$pkgver.tar.gz::$url/archive/v$pkgver.tar.gz")
sha256sums=('SKIP')

build() {
    cd "$pkgname-$pkgver"
    zig build -Doptimize=ReleaseFast
}

package() {
    cd "$pkgname-$pkgver"
    install -Dm755 zig-out/bin/waylight "$pkgdir/usr/bin/waylight"
}
