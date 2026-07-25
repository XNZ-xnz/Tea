#!/bin/zsh
export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin"
export CC="clang -arch x86_64"
export CXX="clang++ -arch x86_64"
export CROSSCC="x86_64-w64-mingw32-gcc"
export LDFLAGS="-L/Users/xnz/Projects/tea-base-build/mvk-lib"
cd "/Users/xnz/Projects/tea-base-build/build-cx25-min"
../cx25/sources/wine/configure --enable-win64 --disable-tests --without-x --without-freetype --without-gnutls --without-gstreamer --without-sdl > configure.log 2>&1 || { echo CONFIGURE_FAIL; exit 1; }
make -j8 > make.log 2>&1
echo "MAKE_RC=$?"
