#!/bin/sh

LIB_DIR="$( cd "$(dirname "$0")" ; pwd -P )"
. $LIB_DIR/../library.sh

DIR=$LIB_DIR

# # SETUP_DIR="`dirname \"$0\"`"
# # SETUP_DIR="`( cd \"${SETUP_DIR}\" && pwd )`"

#run_command "Installing go" sudo add-apt-repository -y ppa:gophers/archive && sudo apt-get update && sudo apt-get -y --force-yes install golang-1.10-go

run_command "cd $DIR" cd $DIR

#run_command "Cloning repo AFL transformations" git clone git@github.sisa.samsung.com:KnoxSecurity/compiler_transformation_AFL.git && cd compiler_transformation_AFL

# note: we could also use wllvm which is the python version available at https://github.com/SRI-CSL/whole-program-llvm
# i use the go version because it's supposed to be faster... available at https://github.com/SRI-CSL/gllvm.git
# run_command "Cloning repo gclang" git clone https://github.com/SRI-CSL/gllvm.git

# compile the .go files
GO=/usr/lib/go-1.10/bin/go
if [ ! -f $GO ]; then
	fatal "Cannot find go binary."
fi


run_command "Compiling go gclang" $GO build -o gclang $LIB_DIR/../gllvm/cmd/gclang/main.go

run_command "Compiling go gclang++" $GO build -o gclang++ $LIB_DIR/../gllvm/cmd/gclang++/main.go 

run_command "Compiling go get-bc" $GO build -o get-bc $LIB_DIR/../gllvm/cmd/get-bc/main.go 

run_command "Compiling go gsanity-check" $GO build -o gsanity-check $LIB_DIR/../gllvm/cmd/gsanity-check/main.go

exit 0


