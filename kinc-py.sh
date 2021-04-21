#!/bin/bash
#PBS -N kinc-py
#PBS -l select=1:ncpus=2:mem=8gb:interconnect=fdr,walltime=24:00:00

# setup environment
module purge
module load anaconda3/5.1.0-gcc

KINC_PATH="${PBS_O_WORKDIR}/KINC"

# change to working directory
cd ${PBS_O_WORKDIR}

# define input/output files
EMX_FILE="example.emx.txt"
CMX_FILE="example.cmx.txt"
RMT_FILE="example.rmt.txt"
NET_FILE="example.net.txt"

# generate example input dataset
N_SAMPLES=1000
N_GENES=100
N_CLASSES=2

python ${KINC_PATH}/scripts/make-input-data.py \
	--n-samples ${N_SAMPLES} \
	--n-genes ${N_GENES} \
	--n-classes ${N_CLASSES} \
	--dataset ${EMX_FILE} \
	--transpose

# compute similarity matrix
CLUSMETHOD="gmm"
CORRMETHOD="spearman"
MINEXPR="-inf"
MINCLUS=1
MAXCLUS=5
CRITERION="bic"
PREOUT="--preout"
POSTOUT="--postout"
MINCORR=0
MAXCORR=1

python ${KINC_PATH}/scripts/kinc-similarity.py \
	--input ${EMX_FILE} \
	--output ${CMX_FILE} \
	--clusmethod ${CLUSMETHOD} \
	--corrmethod ${CORRMETHOD} \
	--minexpr=${MINEXPR} \
	--minclus ${MINCLUS} \
	--maxclus ${MAXCLUS} \
	--criterion ${CRITERION} \
	${PREOUT} \
	${POSTOUT} \
	--mincorr ${MINCORR} \
	--maxcorr ${MAXCORR}

# compute similarity threshold
NUM_GENES=$(expr $(cat ${EMX_FILE} | wc -l) - 1)
METHOD="rmt"
TSTART=0.99
TSTEP=0.001
TSTOP=0.50

python ${KINC_PATH}/scripts/kinc-threshold.py \
	--input ${CMX_FILE} \
	--n-genes ${NUM_GENES} \
	--method ${METHOD} \
	--tstart ${TSTART} \
	--tstep ${TSTEP} \
	--tstop ${TSTOP} \
	&> ${RMT_FILE}

# extract co-expression network
THRESHOLD=0

python ${KINC_PATH}/scripts/kinc-extract.py \
	--emx ${EMX_FILE} \
	--cmx ${CMX_FILE} \
	--output ${NET_FILE} \
	--mincorr ${THRESHOLD}

# visualize pairwise scatter plots
OUTPUT_DIR="plots"

python ${KINC_PATH}/scripts/visualize.py \
	--emx ${EMX_FILE} \
	--netlist ${NET_FILE} \
	--output-dir ${OUTPUT_DIR} \
	--corrdist \
	--pairwise