#!/bin/zsh
export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin"
export CC="clang -arch x86_64"
export CXX="clang++ -arch x86_64"
export CROSSCC="x86_64-w64-mingw32-gcc"
export LDFLAGS="-L/Users/xnz/Projects/tea-base-build/mvk-lib"
cd "$HOME/Projects/tea-base-build/build-cx26-min"
make -j8 > "$HOME/Projects/tea-base-build/make-cx26.log" 2>&1
echo "MAKE_RC=$?" >> "$HOME/Projects/tea-base-build/make-cx26.log"
