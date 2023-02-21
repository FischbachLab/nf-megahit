#!/usr/bin/env nextflow
nextflow.enable.dsl=1
// If the user uses the --help flag, print the help text below
params.help = false

// Function which prints help message text
def helpMessage() {
    log.info"""
    Run Megahit metagenome assembly pipeline with bowtie2 mapping and metabat2 binning

    Required Arguments:
      --seedfile      file      a file containing sample name, reads1 and reads2
      --output_path   path      output a s3 path

    Options:
      -profile        docker run locally

    """.stripIndent()
}

// Show help message if the user specifies the --help flag at runtime
if (params.help){
    // Invoke the function above which prints the help message
    helpMessage()
    // Exit out and do not run anything else
    exit 0
}

Channel
  .fromPath(params.seedfile)
  .ifEmpty { exit 1, "Cannot find the input seedfile" }


/*
 * Defines the pipeline inputs parameters (giving a default value for each for them)
 * Each of the following parameters can be specified as command line options
 */

//core = params.
//mem =
//srate=

def output_path = "${params.output_path}"
//def output_path = "s3://genomics-workflow-core/Pipeline_Results/NinjaMap/${params.output_prefix}"

//println output_path
/*
 * Given the query parameter creates a channel emitting the query fasta file(s),
 * the file is split in chunks containing as many sequences as defined by the parameter 'chunksize'.
 * Finally assign the result channel to the variable 'fasta_ch'
 */

 Channel
 	.fromPath(params.seedfile)
 	.ifEmpty { exit 1, "Cannot find any seed file matching: ${params.seedfile}." }
  .splitCsv(header: ['sample', 'reads1', 'reads2'], sep: ',', skip: 1)
 	.map{ row -> tuple(row.sample, row.reads1, row.reads2)}
 	.set { seedfile_ch }

seedfile_ch.into { seedfile_ch1; seedfile_ch2 }

/*
 * Run megahit preprocessing
 */
process metagenome_assembly {
    tag "$sample"
    container params.container
    cpus 16
    memory 32.GB
    publishDir "${output_path}", mode:'copy'

    input:
	  tuple val(sample), val(reads1), val(reads2) from seedfile_ch1

    output:
    file "${sample}" into out_ch

    script:
    """
    export fastq1="${reads1}"
    export fastq2="${reads2}"
    export S3OUTPUTPATH="${output_path}/${sample}"
    run_megahit_mapping_binning.sh
    """
}
