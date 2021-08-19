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
  n_samples:    ${params.input.n_samples}
  n_genes:      ${params.input.n_genes}
  n_classes:    ${params.input.n_classes}
  emx_file:     ${params.input.emx_file}
output:
  dir:          ${params.output.dir}
similarity
  clus_method:  ${params.similarity.clus_method}
  corr_method:  ${params.similarity.corr_method}
threshold:
  method:       ${params.threshold.method}
extract:
  threshold:    ${params.extract.threshold}
visualize:
  output_dir:   ${params.visualize.output_dir}
"""



/**
 * The make_input process generates an input expression matrix with
 * random expression values.
 */
process make_input {
	publishDir "${params.output.dir}"

	input:
		val(emx_file) from Channel.value(params.input.emx_file)

	output:
		file(emx_file) into EMX_FILES_FROM_MAKE_INPUT

	script:
		"""
		make-input.py \
			--n-samples ${params.input.n_samples} \
			--n-genes ${params.input.n_genes} \
			--n-classes ${params.input.n_classes} \
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
	publishDir "${params.output.dir}"

	input:
		file(emx_file) from EMX_FILES_FROM_MAKE_INPUT

	output:
		file(params.output.cmx_file) into CMX_FILES_FROM_SIMILARITY

	script:
		"""
		kinc-similarity.py \
			--input ${emx_file} \
			--output ${params.output.cmx_file} \
			--clusmethod ${params.similarity.clus_method} \
			--corrmethod ${params.similarity.corr_method} \
			--minexpr=${params.similarity.min_expr} \
			--minclus ${params.similarity.min_clus} \
			--maxclus ${params.similarity.max_clus} \
			--criterion ${params.similarity.criterion} \
			${params.similarity.preout ? "--preout" : ""} \
			${params.similarity.postout ? "--postout" : ""} \
			--mincorr ${params.similarity.min_corr} \
			--maxcorr ${params.similarity.max_corr}
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
	publishDir "${params.output.dir}"

	input:
		file(emx_file) from EMX_FILES_FOR_THRESHOLD
		file(cmx_file) from CMX_FILES_FOR_THRESHOLD

	output:
		file(params.output.rmt_file) into RMT_FILES_FOR_EXTRACT

	script:
		"""
		NUM_GENES=\$(expr \$(cat ${emx_file} | wc -l) - 1)

		kinc-threshold.py \
			--input ${cmx_file} \
			--n-genes \${NUM_GENES} \
			--method ${params.threshold.method} \
			--tstart ${params.threshold.tstart} \
			--tstep ${params.threshold.tstep} \
			--tstop ${params.threshold.tstop} \
			&> ${params.output.rmt_file}
		"""
}



/**
 * The extract process takes the correlation matrix from similarity and
 * extracts a network with a given threshold.
 */
process extract {
	publishDir "${params.output.dir}"

	input:
		file(emx_file) from EMX_FILES_FOR_EXTRACT
		file(cmx_file) from CMX_FILES_FOR_EXTRACT
		file(rmt_file) from RMT_FILES_FOR_EXTRACT

	output:
		file(params.output.net_file) into NET_FILES_FROM_EXTRACT

	script:
		"""
		THRESHOLD=`tail -n 1 ${rmt_file}`

		kinc-extract.py \
			--emx ${emx_file} \
			--cmx ${cmx_file} \
			--output ${params.output.net_file} \
			--mincorr \${THRESHOLD}
		"""
}



/**
 * The visualize process takes extracted network files and saves the
 * pairwise scatter plots as a directory of images.
 */
process visualize {
	publishDir "${params.output.dir}/${params.visualize.output_dir}"

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