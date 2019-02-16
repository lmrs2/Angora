#!/bin/bash

LIB_DIR="$( cd "$(dirname "$0")" ; pwd -P )"
. $LIB_DIR/library.sh


# afl-fuzz
ANGORAFUZZ=$LIB_DIR/bin/fuzzer
RUN_BENCHMARK=$LIB_DIR/run_benchmark.sh
N_RUNS=10 		# number of runs to get some statistical confidence :)
N_INSTANCE=1	# how many instances of the same afl do we run together
TIME=24			# time to run for, in hrs
USE_MASTER=0	# run one master. 0 means all instances run as slaves

run_one() 
{
	AFLFUZZ=$1
	EXE_TRACK=$2
	EXE_FAST=$3
	EXE_AFL=$4
	ARGS=$5

	shift 
	shift 
	shift 
	shift
	shift
	info sh $RUN_BENCHMARK $AFLFUZZ $ANGORAFUZZ $EXE_TRACK $EXE_FAST $EXE_AFL \"$ARGS\" "$@"
	sh $RUN_BENCHMARK $AFLFUZZ $ANGORAFUZZ $EXE_TRACK $EXE_FAST $EXE_AFL "$ARGS" "$@"
	
}

# run_test()
# {
# 	run_one afl-fuzz "$@" in out 
# }

err_exit()
{
	err "$@"
	exit 1
}

run_program()
{
	EXE=$1
	IN=$2
	ARGS=$3
	AFLFUZZ=$4

	#echo $EXE
	#echo $IN
	#echo $ARGS
	#echo $AFLFUZZ
	

	run_one $AFLFUZZ $EXE.track $EXE.fast $EXE.afl "$ARGS" $N_RUNS $N_INSTANCE $IN angora $TIME $USE_MASTER || err_exit "1"
}


if [ "$#" -ne 4 ]; then
	err "Illegal number of parameters"
	err "$0 </path/to/exe-base> <args> <in> afl-fuzz-binary>"
	err "Example: $0 /path/to/readelf" \"-a\" ./in/ /path/to/afl-fuzz
	err "The .taint, .fast and .afl will be automatically appended to the base executable name"
	exit 1
fi

EXE=$1
ARGS=$2
IN=$3
AFLFUZZ=$4

OLDPWD=$PWD

if [ -z $LLVM_CONFIG ]; then
	err_exit "\$LLVM_CONFIG not defined"
fi

VERSION=$($LLVM_CONFIG --version)
VERSION_4=$(echo $VERSION | grep '4.')
if [ -z "$VERSION_4" ]; then
	fatal "LLVM_VERSION points to wrong version:\n${VERSION}\n\nWe need version 4.x"
fi


# setup env for AFL
echo core | sudo tee /proc/sys/kernel/core_pattern 1>/dev/null
value=`cat /proc/sys/kernel/core_pattern`
if [ $value != "core" ];
then
	err_exit "Cannot setup /proc/sys/kernel/core_pattern"
fi

cd /sys/devices/system/cpu 1>/dev/null || err_exit "cd /sys/devices/system/cpu"
echo performance | sudo tee cpu*/cpufreq/scaling_governor 1>/dev/null || err_exit "Echo performance"

# don't do this, it makes .track crash
value=$(ulimit -s)
if [ $value = "unlimited" ]; then
	err_exit "ulimit -s cannot be unlimited. Please change, eg to 8192"
fi
#ulimit -s unlimited || err_exit "ulimit"

cd $OLDPWD || err_exit "cd $OLDPWD"

run_program $EXE $IN "$ARGS" "$AFLFUZZ"
