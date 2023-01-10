#!/bin/bash
# deepcons_shard.sh
set -euo pipefail -o history -o histexpand

ISHARD=$1
NUMSHARDS=$2
SUBREADS_BAM=$3
OUTDIR=$4
MODEL=$5
MINRQ=${6:-0.998}

SHARD_ID=$(printf "%05g" "${ISHARD}")-of-$(printf "%05g" "${NUMSHARDS}")

echo "Running CCS"

ccs --min-rq=$MINRQ --num-threads "$(nproc)" \
  --chunk="${ISHARD}/${NUMSHARDS}" \
  ${SUBREADS_BAM} \
  "${OUTDIR}/${SHARD_ID}.ccs.bam"
  
# bam2fastq -o "${OUTDIR}/${SHARD_ID}.ccs"\
#   -c $(nproc) "${OUTDIR}/${SHARD_ID}.ccs.bam" 

echo "Aligning subreads to CCS"

actc --num-threads "$(nproc)" \
  ${SUBREADS_BAM} \
  "${OUTDIR}/${SHARD_ID}.ccs.bam" \
  "${OUTDIR}/${SHARD_ID}.subreads_to_ccs.bam"

echo "Running DeepConsensus"

deepconsensus run \
  --subreads_to_ccs="${OUTDIR}/${SHARD_ID}.subreads_to_ccs.bam"  \
  --ccs_bam="${OUTDIR}/${SHARD_ID}.ccs.bam" \
  --checkpoint=${MODEL} \
  --output="${OUTDIR}/${SHARD_ID}.deep.fastq"

echo "Compressing results"
gzip "${OUTDIR}/${SHARD_ID}.deep.fastq"
#delete the subreads to bam mapping, since it's very large and no longer needed.
rm "${OUTDIR}/${SHARD_ID}.subreads_to_ccs."*

echo "Done!"
