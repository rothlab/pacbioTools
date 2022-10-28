#!/bin/bash
NUMSHARDS=$1
SUBREADS_BAM=$2
OUTDIR=$3
MODEL=${4:-/home/rothlab/common/deepconsensus/model/checkpoint}
MINRQ=${5:-0.998}
BLACKLIST=${6:-galen1,galen2,galen3,galen4,galen5,galen6,galen7,galen8,galen9,galen10,galen11,galen13,galen14,galen15,galen16,galen17,galen20,galen22,galen23,galen24,galen25,galen26,galen27,galen28,galen30,galen31,galen32,galen34,galen35,galen36,galen37,galen38,galen40,galen41,galen42,galen43,galen44,galen45,galen46,galen68}

mkdir -p "${OUTDIR}/shards/"
if [[ ! -r "${SUBREADS_BAM}.pbi" ]]; then
  pbindex "${SUBREADS_BAM}"
fi

for (( ISHARD = 1; ISHARD <= $NUMSHARDS; ISHARD++ )); do
  SHARD_ID=$(printf "%05g" "${ISHARD}")-of-$(printf "%05g" "${NUMSHARDS}")
  # peak RAM usage: 4.3GB + ncores * 430MB . At 12 cores => ~9.5GB
  RETVAL=$(submitjob.sh -n "deepconsensus$ISHARD" -t "2-00:00:00" \
    -c 12 -m 20GB -l "${OUTDIR}/shards/${SHARD_ID}.log" -e "${OUTDIR}/shards/${SHARD_ID}.log" -- \
    deepcons_shard.sh "$ISHARD" "$NUMSHARDS" "$SUBREADS_BAM" \
    "${OUTDIR}/shards/" "$MODEL" "$MINRQ")
  JOBID=${RETVAL##* }
    if [ -z "$JOBS" ]; then
      JOBS=$JOBID
    else
      JOBS=${JOBS},$JOBID
    fi
done

waitForJobs -v "$JOBS"

#CONSOLIDATE RESULTS
BAMNAME=$(basename $SUBREADS_BAM)
OUTNAME=${BAMNAME%.bam}
#gzip files can be directly concatenated
cat "${OUTDIR}/shards/"*.deep.fastq.gz>"${OUTDIR}/${OUTNAME}".deep.fastq.gz
#bam files use samtools cat
samtools cat "${OUTDIR}/shards/"*.ccs.bam -o "${OUTDIR}/${OUTNAME}".ccs.bam
#collate reports and logs
tar czf "${OUTDIR}/${OUTNAME}_ccs_reports.tgz" "${OUTDIR}/shards/"*ccs_report.txt
tar cf "${OUTDIR}/${OUTNAME}_zmw_metrics.tar" "${OUTDIR}/shards/"*zmw_metrics.json.gz
tar czf "${OUTDIR}/${OUTNAME}_logs.tgz" "${OUTDIR}/shards/"*.log
#delete shards
rm -r "${OUTDIR}/shards"
