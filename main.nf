println """\
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



/**
 * The make_input process generates an input expression matrix with
 * random expression values.
 */
process make_input {
	publishDir "${params.output_dir}"

	input:
		val(emx_file) from Channel.value(params.emx_file)

	output:
		file(emx_file) into EMX_FILES_FROM_MAKE_INPUT

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
 * Send emx file to each process that uses it.
 */
EMX_FILES_FROM_MAKE_INPUT
	.into {
		EMX_FILES_FOR_SIMILARITY;
		EMX_FILES_FOR_THRESHOLD;
		EMX_FILES_FOR_EXTRACT;
		EMX_FILES_FOR_VISUALIZE
	}



/**
 * The similiarity process computes a similarity matrix for the input emx file.
 */
process similarity {
	publishDir "${params.output_dir}"

	input:
		file(emx_file) from EMX_FILES_FROM_MAKE_INPUT

	output:
		file(params.cmx_file) into CMX_FILES_FROM_SIMILARITY

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
 * Send cmx file to all processes that use it.
 */
CMX_FILES_FROM_SIMILARITY
	.into {
		CMX_FILES_FOR_THRESHOLD;
		CMX_FILES_FOR_EXTRACT
	}



/**
 * The threshold process takes the correlation matrix from similarity
 * and attempts to find a suitable correlation threshold.
 */
process threshold {
	publishDir "${params.output_dir}"

	input:
		file(emx_file) from EMX_FILES_FOR_THRESHOLD
		file(cmx_file) from CMX_FILES_FOR_THRESHOLD

	output:
		file(params.rmt_file) into RMT_FILES_FOR_EXTRACT

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
	publishDir "${params.output_dir}"

	input:
		file(emx_file) from EMX_FILES_FOR_EXTRACT
		file(cmx_file) from CMX_FILES_FOR_EXTRACT
		file(rmt_file) from RMT_FILES_FOR_EXTRACT

	output:
		file(params.net_file) into NET_FILES_FROM_EXTRACT

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
 * The visualize process takes extracted network files and saves the
 * pairwise scatter plots as a directory of images.
 */
process visualize {
	publishDir "${params.plots_dir}"

	input:
		file(emx_file) from EMX_FILES_FOR_VISUALIZE
		file(net_file) from NET_FILES_FROM_EXTRACT

	output:
		file("*.png")

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