#!/bin/bash

VERSION="0.0.2"
NUMSHARDS=30
OUTDIR=./
MODEL=/home/rothlab/common/deepconsensus/model/checkpoint
MINRQ=0.998
BLACKLIST="galen1,galen2,galen3,galen4,galen5,galen6,galen7,galen8,galen9,galen10,galen11,galen13,galen14,galen15,galen16,galen17,galen20,galen22,galen23,galen24,galen25,galen26,galen27,galen28,galen29,galen30,galen31,galen32,galen34,galen35,galen36,galen37,galen38,galen40,galen41,galen42,galen43,galen44,galen45,galen46,galen68"

#helper function to print usage information
usage () {
  cat << EOF

deepcons.sh v$VERSION

by Jochen Weile <jochenweile@gmail.com> 2023

Runs parallel CCS and DeepConsensus analysis on a Pacbio BAM file using a HPC cluster.
Recommended number of CPUs to run this script: >12

Usage: deepcons.sh [-j|--jobs <INTEGER>] [-o|--outdir <PATH>] 
    [-m|--modelpath <PATH>] [-q|--minRQ <FLOAT>] [-b|--blacklist <NODES>]
    [--] <BAMFILE>

-j|--jobs     : Number of jobs to run in parallel. Defaults to $NUMSHARDS
-o|--outdir   : Path to output directory. Defaults to $OUTDIR
-m|--modelpath: Path to DeepConsensus Model. Defaults to $MODEL
-q|--minRQ    : Minimum read accuracy (RQ). Default $MINRQ
-b|--blacklist: Blacklist of nodes without AVX support. Default: $BLACKLIST
<BAMFILE>     : The Pacbio BAM file to process

EOF
 exit $1
}


echo "deepcons.sh v$VERSION"

#tokenize command line arguments
PARAMS=$(getopt -u -n "deepcons.sh" -o "j:o:m:q:b:h" -l "jobs:,outdir:,modelpath:,minRQ:,blacklist:,help" -- "$@")
#parse parameter tokens
eval set -- "$PARAMS"
PARAMS=""
NUMRX='^[0-9]+$'
FLOATRX='^0\.[0-9]+$'
while (( "$#" )); do
  case "$1" in
    -j|--jobs)
      if ! [[ $2 =~ $NUMRX ]]; then
        echo "Error: jobs must be an integer number!">&2
        usage 1
      elif (( $2 < 1 )); then
        echo "Error: jobs must be at least 1">&2
        usage 1
      fi
      NUMSHARDS=$2
      shift 2
      ;;
    -o|--outdir)
      OUTDIR=$2
      shift 2
      ;;
    -m|--modelpath)
      MODEL=$2
      shift 2
      ;;
    -q|--minRQ)
      if ! [[ $2 =~ $FLOATRX ]]; then
        echo "Error: minRQ must be a number!">&2
        usage 1
      elif (( $2 < 0 || $2 > 1 )); then
        echo "Error: minRQ must be between 0 and 1">&2
        usage 1
      fi
      MINRQ=$2
      shift 2
      ;;
    -b|--blacklist)
      BLACKLIST=$2
      shift 2
      ;;
    -h|--help)
      usage 0
      shift
      ;;
    --) #end of options. dump the rest into PARAMS
      shift
      PARAMS="$@"
      eval set -- ""
  esac
done
eval set -- "$PARAMS"

SUBREADS_BAM=$1
if ! [[ $SUBREADS_BAM == *.bam ]]; then
  echo "Error: Must provide a BAM file!"
  usage 1
fi

mkdir -p "${OUTDIR}/shards/"
if [[ ! -r "${SUBREADS_BAM}.pbi" ]]; then
  echo "Building BAM index..."
  pbindex "${SUBREADS_BAM}"
fi

echo "Launching jobs..."
for (( ISHARD = 1; ISHARD <= $NUMSHARDS; ISHARD++ )); do
  SHARD_ID=$(printf "%05g" "${ISHARD}")-of-$(printf "%05g" "${NUMSHARDS}")
  # peak RAM usage: 4.3GB + ncores * 430MB . At 12 cores => ~9.5GB
  RETVAL=$(submitjob.sh -n "deepconsensus$ISHARD" -t "2-00:00:00" \
    -b "$BLACKLIST" -c 12 -m 20GB \
    -l "${OUTDIR}/shards/${SHARD_ID}.log" -e "${OUTDIR}/shards/${SHARD_ID}.log" -- \
    deepcons_shard.sh "$ISHARD" "$NUMSHARDS" "$SUBREADS_BAM" \
    "${OUTDIR}/shards/" "$MODEL" "$MINRQ")
  JOBID=${RETVAL##* }
    if [ -z "$JOBS" ]; then
      JOBS=$JOBID
    else
      JOBS=${JOBS},$JOBID
    fi
done

echo "Waiting for jobs..."
waitForJobs.sh -v "$JOBS"

FAILEDJOBS=0
for (( ISHARD = 1; ISHARD <= $NUMSHARDS; ISHARD++ )); do
  SHARD_ID=$(printf "%05g" "${ISHARD}")-of-$(printf "%05g" "${NUMSHARDS}")
  LOG="${OUTDIR}/shards/${SHARD_ID}.log"
  if tail -2 "$LOG"|grep -q 'Done!'; then
    echo "Shard $SHARD_ID completed successfully!"
  else
    echo "Shard $SHARD_ID failed!"
    ((FAILEDJOBS++))
  fi
done

if [[ $FAILEDJOBS -gt 0 ]]; then
  exit 1;
fi

#CONSOLIDATE RESULTS
echo "Consolidating results..."
BAMNAME=$(basename $SUBREADS_BAM)
OUTNAME=${BAMNAME%.bam}
OUTNAME=${OUTNAME%.subreads}
#gzip files can be directly concatenated
cat "${OUTDIR}/shards/"*.deep.fastq.gz>"${OUTDIR}/${OUTNAME}".deep.fastq.gz
#bam files use samtools cat
samtools cat "${OUTDIR}/shards/"*.ccs.bam -o "${OUTDIR}/${OUTNAME}.ccs.bam"
pbindex "${OUTDIR}/${OUTNAME}.ccs.bam"
bam2fastq -o "${OUTDIR}/${OUTNAME}.ccs" -c 8 "${OUTDIR}/${OUTNAME}.ccs.bam" 
#collate reports and logs
tar czf "${OUTDIR}/${OUTNAME}_ccs_reports.tgz" "${OUTDIR}/shards/"*ccs_report.txt
tar cf "${OUTDIR}/${OUTNAME}_zmw_metrics.tar" "${OUTDIR}/shards/"*zmw_metrics.json.gz
tar czf "${OUTDIR}/${OUTNAME}_logs.tgz" "${OUTDIR}/shards/"*.log
#delete shards
rm -r "${OUTDIR}/shards"

echo "Done!"
