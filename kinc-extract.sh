#!/bin/bash
#PBS -N kinc-extract
#PBS -l select=1:ncpus=2:mem=8gb:interconnect=fdr,walltime01:00:00

# initialize environment
module purge
module load anaconda3/5.1.0-gcc

# change to working directory
cd ${PBS_O_WORKDIR}

# extract co-expression network
EMX_FILE="example.emx.txt"
CMX_FILE="example.cmx.txt"
RMT_FILE="example.rmt.txt"
THRESHOLD=`tail -n 1 ${RMT_FILE}`
NET_FILE="example.net.txt"

python3 bin/kinc-extract.py \
	--emx ${EMX_FILE} \
	--cmx ${CMX_FILE} \
	--output ${NET_FILE} \
	--mincorr ${THRESHOLD}
