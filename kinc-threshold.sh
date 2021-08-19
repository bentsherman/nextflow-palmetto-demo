#!/bin/bash
#PBS -N kinc-threshold
#PBS -l select=1:ncpus=2:mem=8gb:interconnect=fdr,walltime=24:00:00

# initialize environment
module purge
module load anaconda3/5.1.0-gcc

# change to working directory
cd ${PBS_O_WORKDIR}

# compute similarity threshold
CMX_FILE="example.cmx.txt"
RMT_FILE="example.rmt.txt"
NUM_GENES=$(expr $(cat ${EMX_FILE} | wc -l) - 1)
METHOD="rmt"
TSTART=0.99
TSTEP=0.001
TSTOP=0.50

python3 bin/kinc-threshold.py \
	--input ${CMX_FILE} \
	--n-genes ${NUM_GENES} \
	--method ${METHOD} \
	--tstart ${TSTART} \
	--tstep ${TSTEP} \
	--tstop ${TSTOP} \
	&> ${RMT_FILE}
