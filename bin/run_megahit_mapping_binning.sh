#!/bin/bash -x

set -euoE pipefail

START_TIME=$SECONDS
#export PATH="/opt/conda/bin:${PATH}"

LOCAL=$(pwd)
DEFAULT=16
coreNum=${coreNum:-$DEFAULT}

if [ -z "${coreNum:-}" ]; then
  echo "coreNum was not set"
fi
# inputs from env variables
#fastq1="${1}"
#fastq2="${2}"

# Setup directory structure
OUTPUTDIR=${LOCAL}/tmp_$( date +"%Y%m%d_%H%M%S" )
RAW_FASTQ="${OUTPUTDIR}/raw_fastq"
QC_FASTQ="${OUTPUTDIR}/trimmed_fastq"
LOCAL_TMP="${OUTPUTDIR}/tmp"

LOCAL_OUTPUT="${OUTPUTDIR}/Sync"
LOG_DIR="${LOCAL_OUTPUT}/Logs"
ASSEMBLY_OUTPUT="${LOCAL_OUTPUT}/megahit"
QUAST_OUTPUT="${LOCAL_OUTPUT}/quast"
#FASTQC_OUTPUT="${LOCAL_OUTPUT}/fastqc"
INDEX_OUTPUT="${LOCAL_OUTPUT}/bowtie2_index"
MAPPING_OUTPUT="${LOCAL_OUTPUT}/mapping"
BINNING_OUTPUT="${LOCAL_OUTPUT}/bins"
#FASTQ_NAME=${fastq1%/*}
#SAMPLE_NAME=$(basename ${FASTQ_NAME})

mkdir -p "${OUTPUTDIR}" "${LOCAL_OUTPUT}" "${LOG_DIR}" "${RAW_FASTQ}" "${QC_FASTQ}" "${BINNING_OUTPUT}"
mkdir -p  "${QUAST_OUTPUT}" "${LOCAL_TMP}" "${MAPPING_OUTPUT}" "${INDEX_OUTPUT}"
trap '{ rm -rf ${OUTPUTDIR} ; exit 255; }' 1

# Copy fastq.gz files from S3, only 2 files per sample
aws s3 cp --quiet ${fastq1} ${RAW_FASTQ}/read1.fastq.gz
aws s3 cp --quiet ${fastq2} ${RAW_FASTQ}/read2.fastq.gz

## Run megahit assembly
megahit \
-t ${coreNum} \
-1 "${RAW_FASTQ}/read1.fastq.gz" \
-2 "${RAW_FASTQ}/read2.fastq.gz" \
-o ${ASSEMBLY_OUTPUT}  |\
tee -a ${LOG_DIR}/megahit_assembly.log.txt


reformat.sh in="${ASSEMBLY_OUTPUT}/final.contigs.fa" out="${ASSEMBLY_OUTPUT}/filtered_contigs_1kb.fasta" minlength=1000
# check continuity information (L50, N50, etc) on contigs
stats.sh in="${ASSEMBLY_OUTPUT}/filtered_contigs_1kb.fasta" > ${LOG_DIR}/contigs_stats.txt
#1. filter assembly contigs by Length - at least 1000
reformat.sh in="${ASSEMBLY_OUTPUT}/final.contigs.fa" out="${RAW_FASTQ}/assembly.fasta" minlength=1000

# 2. Run mapping for short reads
# build database  ( --seed option must be put in the end)

bowtie2-build --threads ${coreNum}  -f "${RAW_FASTQ}/assembly.fasta" "${INDEX_OUTPUT}/database"  --seed 42

# map reads to database
bowtie2 --sensitive-local -p ${coreNum} --seed 42 -x "${INDEX_OUTPUT}/database" \
-1 "${RAW_FASTQ}/read1.fastq.gz" -2 "${RAW_FASTQ}/read2.fastq.gz" | \
samtools view -@ ${coreNum} -bh -o "${LOCAL_TMP}/assembly_aligned.bam" - | \
tee -a ${LOG_DIR}/bowtie2_mapping.log.txt


# index assembly
#samtools faidx "${RAW_FASTQ}/assembly.fasta"
# create bam file
#samtools import "${RAW_FASTQ}/assembly.fasta.fai" "${LOCAL_TMP}/assembly_aligned.sam" "${LOCAL_TMP}/assembly_aligned.bam"
# sort bam file
samtools sort -@ ${coreNum} "${LOCAL_TMP}/assembly_aligned.bam"  -o "${MAPPING_OUTPUT}/assembly_aligned.sorted.bam"
# index bam
# Version: 1.3.1 (using htslib 1.3.1) no -@ option
samtools index  "${MAPPING_OUTPUT}/assembly_aligned.sorted.bam"
# generate assembly stats
samtools idxstats "${MAPPING_OUTPUT}/assembly_aligned.sorted.bam" > "${LOG_DIR}/assembly_aligned.idxstats.txt"
samtools flagstat "${MAPPING_OUTPUT}/assembly_aligned.sorted.bam" > "${LOG_DIR}/assembly_aligned.flagstat.txt"
# generate count table
#https://github.com/edamame-course/Metagenome/blob/master/get_count_table.py
#get_count_table.py "${LOG_DIR}/assembly_aligned.idxstats.txt" > "${LOG_DIR}/mapping_counts.txt"

# check reads coverage/depth on contigs
#pileup.sh in="${MAPPING_OUTPUT}/assembly_aligned.sorted.bam" covstats="${LOG_DIR}/assembly_aligned.cov_stats.txt" > "${LOG_DIR}/assembly_aligned.stats.txt"
# bam qc
#qualimap bamqc -outdir "${BAMQC_OUTPUT}" -bam "${LOCAL_TMP}/assembly_aligned.sorted.bam"


# 3. Binning
# One step to run MetaBat
#runMetaBat.sh "${RAW_FASTQ}/assembly.fasta" "${LOCAL_TMP}/assembly_aligned.sorted.bam" &
# Summarize BAM depth
jgi_summarize_bam_contig_depths --outputDepth "${LOG_DIR}/contig_depth.txt" "${MAPPING_OUTPUT}/assembly_aligned.sorted.bam" | tee -a ${LOG_DIR}/depth.txt
# Bin Contigs
metabat2 -i "${RAW_FASTQ}/assembly.fasta" -a "${LOG_DIR}/contig_depth.txt" -o "${BINNING_OUTPUT}/bin" -v --seed 42 | tee -a ${LOG_DIR}/metabat2.txt
# Evaluate Bins - Need to install database https://data.ace.uq.edu.au/public/CheckM_databases/
#  lineage_wf   -> Runs tree, lineage_set, analyze, qa
#timem checkm lineage_wf -t ${coreNum} -x fa -f "${STAT_OUTPUT}/checkm_output.txt" ${BINNING_OUTPUT} ${STAT_OUTPUT} | tee -a ${LOG_DIR}/checkm.txt


# 1. Run Quast without reference --rna-finding \ --glimmer \
quast.py \
-t ${coreNum} \
--contig-thresholds 1000,5000,10000,25000,50000,100000,250000,500000,1000000 \
"${RAW_FASTQ}/assembly.fasta" \
-o ${QUAST_OUTPUT} | tee -a ${LOG_DIR}/quast.log.txt


######################### HOUSEKEEPING #############################
DURATION=$((SECONDS - START_TIME))
hrs=$(( DURATION/3600 )); mins=$(( (DURATION-hrs*3600)/60)); secs=$(( DURATION-hrs*3600-mins*60 ))
printf 'This AWSome pipeline took: %02d:%02d:%02d\n' $hrs $mins $secs > ${LOCAL_OUTPUT}/job.complete
echo "Live long and prosper" >> ${LOCAL_OUTPUT}/job.complete
############################ PEACE! ################################
## Sync output

aws s3 sync --quiet "${LOCAL_OUTPUT}" "${S3OUTPUTPATH}"
