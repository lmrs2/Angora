#!/bin/sh

LIB_DIR="$( cd "$(dirname "$0")" ; pwd -P )"
. $LIB_DIR/../library.sh || exit 255


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
VERSION=$($LLVM_CONFIG --version)
VERSION_4=$(echo $VERSION | grep '4.')
if [ -z "$VERSION_4" ]; then
	fatal "LLVM_VERSION points to wrong version:\n${VERSION}\n\nWe need version 4.0"
fi

BINDIR=$($LLVM_CONFIG --bindir) || fatal "LLVM_CONFIG"
CLANG=$BINDIR/clang
LLDB=$BINDIR/lldb

if [ ! -f $CLANG ]; then
	fatal "'$CLANG' not found"
fi

# if [ ! -f $LLDB ]; then
#         fatal "'$LLDB' not found"
# fi


PREFIX=./bin

# install rustc, etc if needed
if [ -f "$HOME/.cargo/env" ]; then
	. $HOME/.cargo/env || fatal "cargo"
fi

if [ ! -x "$(command -v cargo)" ]; then
	curl https://sh.rustup.rs -sSf | sh  || fatal "rust"	
	. $HOME/.cargo/env || fatal "source"
fi

if [ $action = "clean" ]; then
	cargo clean || fatal "cargo clean"
	rm -rf $PREFIX 2>/dev/null || fatal "rm -rf"
	cd llvm_mode || fatal "cd"
	make clean || fatal "make clean"
	exit 0
fi

# create common dir for binaries
mkdir -p ${PREFIX} || fatal "mkdir $PREFIX"

# install angora
cargo build --release || fatal "cargo build"
cp target/release/*.a ${PREFIX} || fatal "cp"
cp target/release/fuzzer ${PREFIX} || fatal "cp 2"
cd llvm_mode || fatal "cd"
LLVM_CONFIG=$LLVM_CONFIG make || fatal "make"

# install gllvm
cd ..
if [ ! -f $PREFIX/gclang ]; then
        sh $LIB_DIR/setup-gclang.sh || fatal "gllvm"
        mv gsanity-check $PREFIX || fatal "gsanity-check"
        mv get-bc $PREFIX || fatal "get-bc"
        mv gclang $PREFIX || fatal "gclang"
        mv gclang++ $PREFIX || fatal "gclang++"
fi

cp $LIB_DIR/angora-gclang $PREFIX || fatal "copy angora-gclang"
chmod a+x $PREFIX/angora-gclang || fatal "chmod"
FPA=$(get_full_path_of_file $PREFIX/angora-gclang)
FPAP=$(get_full_path_of_file $PREFIX/angora-gclang++)
rm -rf $FPAP && ln -s $FPA $FPAP || fatal "ln -s"
cp $LIB_DIR/angora-get-bc $PREFIX/ || fatal "cp angora-get-bc"

info "Installed in Angora/bin"

