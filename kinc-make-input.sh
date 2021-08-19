#!/bin/bash
#PBS -N kinc-make-input
#PBS -l select=1:ncpus=2:mem=8gb:interconnect=fdr,walltime=01:00:00

# initialize environment
module purge
module load anaconda3/5.1.0-gcc

# change to working directory
cd ${PBS_O_WORKDIR}

# generate example input dataset
N_SAMPLES=1000
N_GENES=100
N_CLASSES=2
EMX_FILE="example.emx.txt"

python3 bin/make-input.py \
	--n-samples ${N_SAMPLES} \
	--n-genes ${N_GENES} \
	--n-classes ${N_CLASSES} \
	--dataset ${EMX_FILE} \
	--transpose
