#!/bin/sh

LIB_DIR="$( cd "$(dirname "$0")" ; pwd -P )"
. $LIB_DIR/library.sh

# libraries
is_empty()
{
	if [ -z "$@" ]; then
		true
	else
		false
	fi
}

is_integer()
{
	if is_empty "$@"; then
		false
	elif [ "$@" -eq "$@" ] 2>/dev/null; then
		true
	else
		false
	fi
}

is_positive_integer()
{
	if ! is_integer "$@"; then
		false
	else
		N="$@"
		C1=$(echo $N | head -c1)
		if [ "$C1" = "-" ]; then
			false
		else
			true
		fi
	fi
}

validate_args() 
{
	

	if [ "$#" -lt 10 ]; then
 		err "Illegal number of parameters"
    	err "$0 <afl-fuzz> <n_bins> <bin_1 bin_2 ... bin_n> <args> <n_runs> <n_instances> <infolder> <outfolder> <dict_1 dict_2 ... dict_n> <time_hrs>"
    	exit 1
	fi
}


run_group()
{
	# $GROUPID $AFLFUZZ $BINS $ARGS $INFOLDER $OUTFOLDER $N_PARALLEL_RUNS $N_INSTANCE $DICTFILE $TIME
	GROUPID=$1
	AFLFUZZ=$2
	ANGORAFUZZ=$3
	EXE_TRACK=$4
	EXE_FAST=$5
	EXE_AFL=$6
	ARGS=$7
	INFOLDER=$8
	OUTFOLDER=$9
	N_PARALLEL_RUNS=$10
	N_INSTANCE=$11
	TIME=$12
	USE_MASTER=$13

	trap_pid_list=""
	wait_pid_list=""
		
	N=3

	for r in `seq 1 $N_PARALLEL_RUNS`
	do
		
		# run a bin
		ind=0
		master_done=0
		for j in `seq 1 $N_INSTANCE`
		do
			for i in `seq 1 $N`
			do
				# create command
				OUT=$OUTFOLDER/$GROUPID-$r

				if [ $i -eq 1 ]; then
					B=`get_fn_from_file $EXE_TRACK`-$j-$i
					B=$(echo $B | sed 's/\.track//g')
					# -N = no UI, -E = no exploitation, -A = no AFL mutations but seems to not work properly
					cmd="timeout ${TIME}h $ANGORAFUZZ -A -N -E --sync_afl -i $INFOLDER -o $OUT -t $EXE_TRACK -- $EXE_FAST $ARGS @@"

				elif [ $USE_MASTER -eq 1 ] && [ $i -eq 2 ]; then
					B=`get_fn_from_file $EXE_TRACK`-$j-$i
					B=$(echo $B | sed 's/\.track//g')
					cmd="timeout ${TIME}h $AFLFUZZ -m none -i $INFOLDER -o $OUT -M M-$B $b $ARGS @@"

				else
					B=`get_fn_from_file $EXE_TRACK`-$j-$i
					B=$(echo $B | sed 's/\.track//g')
					cmd="timeout ${TIME}h $AFLFUZZ -m none -i $INFOLDER -o $OUT -S S-$B $b $ARGS @@"
					
				fi

				ind=$((ind+1))
				info "$cmd"
				eval "$cmd &" || { err "$cmd"; exit 1; }
				trap_pid_list="$trap_pid_list -$!"
				wait_pid_list="$wait_pid_list $!"

				#sleep 3s
			done
		done
		
	done

	# https://unix.stackexchange.com/questions/57667/why-cant-i-kill-a-timeout-called-from-a-bash-script-with-a-keystroke
	cmd="trap 'kill -INT $trap_pid_list' INT"
	info "$cmd"
	eval "$cmd" || { err "$cmd"; exit 1; }
	cmd="wait $wait_pid_list"
	info "$cmd"
	eval "$cmd"
}

# start of code
validate_args "$@"

nproc=`nproc`
N_PROC=$((nproc))

NBINS=3
AFLFUZZ=$1
ANGORAFUZZ=$2
EXE_TRACK=$3
EXE_FAST=$4
EXE_AFL=$5
ARGS=$6
N_RUNS=$7
N_INSTANCE=$8
INFOLDER=$9
OUTFOLDER=$10
TIME=$11
USE_MASTER=$12
BINS="$EXE_TRACK $EXE_FAST $EXE_AFL"

# validate binaries
if ! regular_file_exists $EXE_TRACK; then
	err "'$EXE_TRACK' does not exist"
	exit 1
fi

if ! regular_file_exists $EXE_FAST; then
	err "'$EXE_FAST' does not exist"
	exit 1
fi

if ! regular_file_exists $EXE_AFL; then
	err "'$EXE_AFL' does not exist"
	exit 1
fi

# validate positive integer
if ! is_positive_integer $N_INSTANCE; then
	err "Invalid n_instance '$N_INSTANCE'"
	exit 1
fi

T_INSTANCES=$((N_INSTANCE*NBINS))

if ! is_positive_integer $N_RUNS; then
	err "Invalid n_instance '$N_RUNS'"
	exit 1
fi

if ! is_positive_integer $TIME; then
	err "Invalid time '$TIME'"
	exit 1
fi

# infolder must exist
if ! folder_exists $INFOLDER; then
	err "'$INFOLDER' does not exist"
	exit 1
fi

# outfolder must not exist
if folder_exists $OUTFOLDER; then
	err "'$OUTFOLDER' already exists"
	exit 1
fi

mkdir $OUTFOLDER


# let's use maximum of 2/3 of cores
USED_CPUS=$((N_PROC*4/5))
if [ $USED_CPUS -lt $T_INSTANCES ]; then
	err "Not enough cores ($USED_CPUS) for $T_INSTANCES instances"
	exit 1
fi


# Note: the check should always pass because of the chack above
N_PARALLEL_RUNS=$((USED_CPUS/T_INSTANCES))
if [ $N_PARALLEL_RUNS -le 0 ]; then
	err "Not enough CPUs to run ($USED_CPUS/$T_INSTANCES)"
	exit 1
fi

ind=0
for b in $BINS
do
	info "BIN$ind = $b"
	ind=$((ind+1))
done


info "ARGS = '$ARGS'"
info "TIME = $TIME"
info "N_PARALLEL_RUNS = $N_PARALLEL_RUNS"
info "N_RUNS = $N_RUNS"
info "USED_CPUS = $USED_CPUS"
info "T_INSTANCES = $T_INSTANCES"
info "N_INSTANCE = $N_INSTANCE"
info "N_PROC = $N_PROC"
info "USE_MASTER = $USE_MASTER"


# ceil
LOOP_N=$(((N_RUNS/N_PARALLEL_RUNS)))
if [ $((LOOP_N*N_PARALLEL_RUNS)) -lt $N_RUNS ]; then
	LOOP_N=$((LOOP_N+1))
fi

TIME_LEFT=$((LOOP_N*TIME))
warn "Time remaining: ${TIME_LEFT}h"

if [ $N_INSTANCE -gt 1 ]; then
	err "Angora only supports 1 instance of itself"
	exit 1
fi

# disable UI
export AFL_NO_UI=1

for l in `seq 1 $LOOP_N`
do
	now=`date +"%T"`
	info "Start ($l): $now, duration: ${TIME}h"
	run_group $((l-1)) $AFLFUZZ $ANGORAFUZZ $EXE_TRACK $EXE_FAST $EXE_AFL "$ARGS" $INFOLDER $OUTFOLDER $N_PARALLEL_RUNS $N_INSTANCE $TIME $USE_MASTER
done

exit 0
