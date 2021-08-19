#!/bin/bash
#PBS -N kinc-similarity
#PBS -l select=1:ncpus=2:mem=8gb:interconnect=fdr,walltime=24:00:00

# initialize environment
module purge
module load anaconda3/5.1.0-gcc

# change to working directory
cd ${PBS_O_WORKDIR}

# compute similarity matrix
EMX_FILE="example.emx.txt"
CMX_FILE="example.cmx.txt"
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

python3 bin/kinc-similarity.py \
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
