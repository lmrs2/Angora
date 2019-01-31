#!/bin/sh

if [ "$#" -ne 1 ]; then
    echo "Illegal number of parameters"
    echo "Usage: $0 make/clean"
    exit 255
fi

action="$1"
if [ $action != "make" ] && [ $action != "clean" ]; then
	echo "Invalid command. Allowed: 'make' and 'clean'"
	exit 255
fi

if [ -z "$LLVM_CONFIG" ]; then
	echo "Error: LLVM_CONFIG variable not set."
	echo "Install clang-4.0 and lldb-4.0"
	exit 255
fi

# sudo apt-add-repository "deb http://apt.llvm.org/trusty/ llvm-toolchain-trusty-4.0 main"
# sudo apt-get update || exit 255
# sudo apt-get install clang-4.0 lldb-4.0 || exit 255

# pre-requesites: make sure clang/lldb is installed
BINDIR=$($LLVM_CONFIG --bindir) || exit 255
CLANG=$BINDIR/clang
LLDB=$BINDIR/lldb

if [ ! -f $CLANG ]; then
	echo "'$CLANG' not found"
	exit 255
fi

if [ ! -f $LLDB ]; then
	echo "'$LLDB' not found"
	exit 255
fi



VERSION_ALL=$($CLANG --version)
VERSION_4=$(echo $VERSION_ALL | grep '(branches/release_40)')
if [ -z "$VERSION_4" ]; then
	echo "LLVM_VERSIOn points to wrong version:"
	echo $VERSION_ALL
	echo
	echo "We need version 4.0"
	exit 255
fi


# install rustc, etc if needed
if [ -f "$HOME/.cargo/env" ]; then
. $HOME/.cargo/env || exit 255
fi

if [ ! -x "$(command -v cargo)" ]; then
curl https://sh.rustup.rs -sSf | sh  || exit 255
. $HOME/.cargo/env || exit 255
fi


# install angora:
PREFIX=./bin

if [ $action = "clean" ]; then
	cargo clean || exit 255
	cd llvm_mode || exit 255
	make clean || exit 255
	rm -rf $PREFIX 2>/dev/null || exit 255
	exit 0
fi


# install angora for make command:
cargo build || exit 255
cargo build --release || exit 255
mkdir -p ${PREFIX} || exit 255
cp target/release/*.a ${PREFIX} || exit 255
cp target/release/fuzzer ${PREFIX} || exit 255
cd llvm_mode || exit 255
LLVM_CONFIG=$LLVM_CONFIG make || exit 255

echo "Installed in Angora/bin"

