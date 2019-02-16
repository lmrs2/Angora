# Angora

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Build Status](https://api.cirrus-ci.com/github/AngoraFuzzer/Angora.svg)](https://cirrus-ci.com/github/AngoraFuzzer/Angora)

Angora is a mutation-based coverage guided fuzzer. The main goal of Angora is 
to increase branch coverage by solving path constraints without symbolic 
execution. 

Original repo is at [https://github.com/AngoraFuzzer/Angora](https://github.com/AngoraFuzzer/Angora)

## Published Work

Arxiv: [Angora: Efficient Fuzzing by Principled Search](https://arxiv.org/abs/1803.01307), S&P '2018.

## Building Angora


### Installation

- Linux-amd64 (Tested on Ubuntu 14.04/16.04/18.04 and Debian Buster)
- [Clang/LLVM 4.0.0](http://llvm.org/docs/index.html). Do *not* install it from your distribution, it will be problematic
if you need to compilte C++ programs because we need to compile libcxx with DFSan.
	```shell
	cd Angora
	export CLANG_INSTALLATION=$PWD/Angora/clangllvm
	git clone https://github.com/llvm/llvm-project.git -b release/4.x
	cd llvm-project && mkdir build && cd build
	cmake -DCMAKE_INSTALL_PREFIX=$CLANG_INSTALLATION -DLLVM_TARGETS_TO_BUILD="X86" -DLLVM_ENABLE_PROJECTS=libcxxabi -DLLVM_ENABLE_PROJECTS=libcxx -DLLVM_ENABLE_PROJECTS=clang -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release ../llvm
	make install
	```
- [gclang](https://github.com/SRI-CSL/gllvm). Installed automatically by installation script -- see below.
- [rustup](https://rustup.rs). Installed automatically by installation script -- see below.

### Fuzzer Compilation

The build script will resolve most dependencies and setup the 
runtime environment.

```shell
export LLVM_CONFIG=$CLANG_INSTALLATION/bin/llvm-config
./build/build.sh make
```

To clean:

```shell
./build/build.sh clean
```

### System Configuration

As with AFL, system core dumps must be disabled.

```shell
echo core | sudo tee /proc/sys/kernel/core_pattern
```
Also make sure ulimit -s is *not* set to unlimited, as this crashes the binary.track:
```shell
ulimit -s 8912
```

## Running Angora

### Build Target Program

Angora compiles the program into two separate binaries, each with their respective
instrumentation. Using `autoconf` programs as an example, here are the steps required.


```shell
export ANGORA_DIR=/path/to/angora/bin
export LLVM_CONFIG=$CLANG_INSTALLATION/bin/llvm-config
```

With angora-clang:

```shell
# Use the angora compilers
CC=$ANGORA_DIR/angora-clang CXX=$ANGORA_DIR/angora-clang++ LD=$ANGORA_DIR/angora-clang ./configure --disable-shared

USE_TRACK=1  make -j`nproc`
mv output_binary output_binary.track

# if you get errors about libc++abi missing, install it:
sudo apt-get install libc++abi-dev

make clean
USE_FAST=1  make -j`nproc`
mv output_binary output_binary.fast
```


If this does not work, use gllvm:

```shell
# Use the gclang compilers
CC=$ANGORA_DIR/angora-gclang CXX=$ANGORA_DIR/angora-gclang++ ./configure --disable-shared
make -j`nproc`

# extract the .bc. This will create binary.bc
$ANGORA_DIR/angora-get-bc binary

# Build with taint tracking support 
USE_TRACK=1 $ANGORA_DIR/angora-clang binary.bc -o binary.track

# Build with light instrumentation support
USE_FAST=1 $ANGORA_DIR/angora-clang binary.bc -o binary.fast
```

### Fuzzing

Angora alone:

```shell
$ANGORA_DIR/fuzzer -i input -o output -t /path/to/binary.track -- /path/to/binary.fast [argv] @@
```

Angora with AFL:
```shell
$ANGORA_DIR/fuzzer -A --sync_afl -i input -o output -t /path/to/binary.track -- /path/to/binary.fast [argv] @@
/path/to/afl-fuzz -i input -o output -S/M afl_name /path/to/binary.afl [argv] @@
```

-----------

For more information, please refer to the documentation under the 
`docs/` directory.

- [Angora Overview](./docs/overview.md)
- [Build a target program](./docs/build_target.md)
- [Running Angora](./docs/running.md)
- [Example - Fuzz program file by Angora](./docs/example.md)
- [Run Angora on LAVA](./docs/lava.md)
- [Exploit attack points](./docs/exploitation.md)
- [Usage](./docs/usage.md)
- [Configuration Files](./docs/configuration.md)
- [Environment variables in compiling](./docs/environment_variables.md)
- [UI Terminology](./docs/ui.md)
- [Troubleshoot](./docs/troubleshoot.md)

--------
Angora is maintained by [ByteDance AI Lab](https://ailab.bytedance.com/) now.
