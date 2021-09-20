#!/bin/bash
#PBS -N kinc-visualize
#PBS -l select=1:ncpus=2:mem=8gb:interconnect=fdr,walltime=04:00:00

# initialize environment
module purge
module load anaconda3/5.1.0-gcc

# change to working directory
cd ${PBS_O_WORKDIR}

# visualize pairwise scatter plots
EMX_FILE="example.emx.txt"
NET_FILE="example.net.txt"
PLOTS_DIR="plots"

mkdir -p ${PLOTS_DIR}

python3 bin/make-plots.py \
	--emx ${EMX_FILE} \
	--netlist ${NET_FILE} \
	--output-dir ${PLOTS_DIR} \
	--corrdist \
	--pairwise