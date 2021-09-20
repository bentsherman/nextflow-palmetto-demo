#!/usr/bin/env nextflow

nextflow.enable.dsl=2



println \
"""
=================================
 K I N C - P Y   P I P E L I N E
=================================

Workflow Information:
---------------------
  Launch Directory:   ${workflow.launchDir}
  Work Directory:     ${workflow.workDir}
  Config Files:       ${workflow.configFiles}
  Profiles:           ${workflow.profile}

Execution Parameters:
---------------------
input:
  n_samples:    ${params.n_samples}
  n_genes:      ${params.n_genes}
  n_classes:    ${params.n_classes}
  emx_file:     ${params.emx_file}

output:
  dir:          ${params.output_dir}

similarity
  clusmethod:   ${params.similarity_clusmethod}
  corrmethod:   ${params.similarity_corrmethod}

threshold:
  method:       ${params.threshold_method}

plots:
  dir:          ${params.plots_dir}
"""



workflow {
	// generate a synthetic dataset
	emx_files = Channel.fromList([ params.emx_file ])

	make_input(emx_files)
	emx_files = make_input.out.emx_files

	// compute similarity matrix
	similarity(emx_files)
	cmx_files = similarity.out.cmx_files

	// compute similarity threshold
	threshold(emx_files, cmx_files)
	rmt_files = threshold.out.rmt_files

	// extract co-expression network
	extract(emx_files, cmx_files, rmt_files)
	net_files = extract.out.net_files

	// visualize pairwise scatter plots
	make_plots(emx_files, net_files)
}



/**
 * The make_input process generates an input expression matrix with
 * random expression values.
 */
process make_input {
	publishDir "${params.output_dir}", mode: "copy"

	input:
		val(emx_file)

	output:
		path(emx_file), emit: emx_files

	script:
		"""
		make-input.py \
			--n-samples ${params.n_samples} \
			--n-genes ${params.n_genes} \
			--n-classes ${params.n_classes} \
			--dataset ${emx_file} \
			--transpose
		"""
}



/**
 * The similiarity process computes a similarity matrix for the input emx file.
 */
process similarity {
	publishDir "${params.output_dir}", mode: "copy"

	input:
		path(emx_file)

	output:
		path(params.cmx_file), emit: cmx_files

	script:
		"""
		kinc-similarity.py \
			--input ${emx_file} \
			--output ${params.cmx_file} \
			--clusmethod ${params.similarity_clusmethod} \
			--corrmethod ${params.similarity_corrmethod} \
			--minexpr=${params.similarity_minexpr} \
			--minclus ${params.similarity_minclus} \
			--maxclus ${params.similarity_maxclus} \
			--criterion ${params.similarity_criterion} \
			${params.similarity_preout ? "--preout" : ""} \
			${params.similarity_postout ? "--postout" : ""} \
			--mincorr ${params.similarity_mincorr} \
			--maxcorr ${params.similarity_maxcorr}
		"""
}



/**
 * The threshold process takes the correlation matrix from similarity
 * and attempts to find a suitable correlation threshold.
 */
process threshold {
	publishDir "${params.output_dir}", mode: "copy"

	input:
		path(emx_file)
		path(cmx_file)

	output:
		path(params.rmt_file), emit: rmt_files

	script:
		"""
		NUM_GENES=`tail -n +1 ${emx_file} | wc -l`

		kinc-threshold.py \
			--input ${cmx_file} \
			--n-genes \${NUM_GENES} \
			--method ${params.threshold_method} \
			--tstart ${params.threshold_tstart} \
			--tstep ${params.threshold_tstep} \
			--tstop ${params.threshold_tstop} \
			&> ${params.rmt_file}
		"""
}



/**
 * The extract process takes the correlation matrix from similarity and
 * extracts a network with a given threshold.
 */
process extract {
	publishDir "${params.output_dir}", mode: "copy"

	input:
		path(emx_file)
		path(cmx_file)
		path(rmt_file)

	output:
		path(params.net_file), emit: net_files

	script:
		"""
		THRESHOLD=`tail -n 1 ${rmt_file}`

		kinc-extract.py \
			--emx ${emx_file} \
			--cmx ${cmx_file} \
			--output ${params.net_file} \
			--mincorr \${THRESHOLD}
		"""
}



/**
 * The make_plots process takes extracted network files and saves the
 * pairwise scatter plots as a directory of images.
 */
process make_plots {
	publishDir "${params.plots_dir}", mode: "copy"

	input:
		path(emx_file)
		path(net_file)

	output:
		path("*.png")

	script:
		"""
		make-plots.py \
			--emx ${emx_file} \
			--netlist ${net_file} \
			--output-dir . \
			--corrdist \
			--pairwise
		"""
}