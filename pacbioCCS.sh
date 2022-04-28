#!/bin/bash

#helper function to print usage information
usage () {
  cat << EOF

pacbioCCS.sh v0.0.1 

by Jochen Weile <jochenweile@gmail.com> 2021

Runs parallel CCS analysis on a Pacbio BAM file using a SLURM HPC cluster.
Recommended number of CPUs to run this script: >12
Usage: pacbioCCS.sh [-d|--demuxIndices <FASTAFILE>] [-j|--jobcount <INTEGER>] 
    [-p|--passes <INTEGER>] [--] <BAMFILE>

-d|--demuxIndices : FASTA file containing demultiplexing indices. If none
           is provided, then demultiplexing is skipped.
-j|--jobcount : Number of jobs to run in parallel. Defaults to 100
-p|--passes : Minimum number of CCS passes required to accept read.
<BAMFILE>     : The BAM file to process

EOF
 exit $1
}

#number of jobs to run in parallel
JOBCOUNT=100
#minimum number of CCS passes
MINPASSES=5
#FASTA file with barcode indices
INDICES=""
#Parse Arguments
PARAMS=""
while (( "$#" )); do
  case "$1" in
    -h|--help)
      usage 0
      shift
      ;;
    -d|--demuxIndices)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        INDICES=$2
        shift 2
      else
        echo "ERROR: Argument for $1 is missing" >&2
        usage 1
      fi
      ;;
    -j|--jobcount)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        JOBCOUNT=$2
        shift 2
      else
        echo "ERROR: Argument for $1 is missing" >&2
        usage 1
      fi
      ;;
    -p|--passes)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        MINPASSES=$2
        shift 2
      else
        echo "ERROR: Argument for $1 is missing" >&2
        usage 1
      fi
      ;;
    --) # end of options indicates that the main command follows
      shift
      PARAMS="$PARAMS $@"
      eval set -- ""
      ;;
    -*|--*=) # unsupported flags
      echo "ERROR: Unsupported flag $1" >&2
      usage 1
      ;;
    *) # positional parameter
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done
#reset command arguments as only positional parameters
eval set -- "$PARAMS"

#input BAM file from Pacbio
BAMFILE=$1
#check if it exists
if [ -z "$BAMFILE" ]; then
  echo "Must provide BAM file!"
  usage 1
elif ! [ -r "$BAMFILE" ]; then
  echo "Cannot read BAM file $BAMFILE !"
  exit 1
fi


mkdir -p demux/chunks
# mkdir -p logs

OUTBAM=demux/$(basename "$BAMFILE"|sed -r "s/\\.bam$/_ccsMerged.bam/")
OUTFQ=demux/$(basename "$BAMFILE"|sed -r "s/\\.bam$/_ccsMergedDemuxed.fastq.gz/")

#helper script to schedule a CCS chunk job
scheduleJob() {

  JOBNUM=$1
  JOBCOUNT=$2
  INFILE=$3
  TIME=${4:-"48:00:00"}
  THREADS=${5:-4}
  MEM=${6:-"4GB"}
  OUTFILE=demux/chunks/$(basename "$INFILE"|sed -r "s/\\.bam$/_${JOBNUM}.bam/")

  RETVAL=$(submitjob.sh -n ccs$JOBNUM -t $TIME -c $THREADS -m $MEM \
  ccs --min-passes $MINPASSES --chunk ${JOBNUM}/${JOBCOUNT} \
  --num-threads $THREADS $INFILE $OUTFILE)

  JOBID=${RETVAL##* }
  echo $JOBID
}

# #helper function to wait for the completion of jobs
# waitForJobs() {
#   #first argument should be a comma-separated list of job ids.
#   JOBS=$1
#   echo "Waiting for jobs to finish..."
#   #the number of currently active jobs (with 1 pseudo-job to begin with)
#   CURRJOBNUM=1
#   while (( $CURRJOBNUM > 0 )); do
#     sleep 5
#     if [ -z "$JOBS" ]; then
#       CURRJOBNUM=$(squeue -hu $USER|wc -l)
#     else
#       CURRJOBNUM=$(squeue -hu $USER -j${JOBS}|wc -l)
#     fi
#     echo "$CURRJOBNUM jobs remaining"
#   done
# }


#if necessary, index the bamfile to allow for running CCS in parallel jobs
PBIFILE="${BAMFILE}.pbi"
if ! [ -r "$PBIFILE" ]; then
  echo "Indexing BAM file $BAMFILE ..."
  pbindex $BAMFILE
fi

echo "Scheduling CCS jobs..."
#schedule parallel CCS jobs on cluster
JOBS=""
for (( JOBNUM = 1; JOBNUM <= $JOBCOUNT; JOBNUM++ )); do
  JOBID=$(scheduleJob $JOBNUM $JOBCOUNT $BAMFILE)
  JOBS=${JOBS},$JOBID
done

waitForJobs.sh -v "$JOBS"

# merge the final results
echo "Consolidating job outputs..."
# submitjob.sh -c 4 -m 4G -n pbmerge -- 
pbmerge -o $OUTBAM demux/chunks/*.bam
# merge text reports
tail -n +1 demux/chunks/*report.txt>demux/reports.txt

# echo "Waiting for job to complete..."
# waitForJobs.sh

#if there are no indices provided, no demuxing will happen
if [ -z "$INDICES" ]; then
  # or convert to fastq directoy
  echo "BAM2FASTQ conversion..."
  # submitjob.sh -c 4 -m 4G -n bam2fastq -- 
  bam2fastq -o $OUTFQ -c 6 $OUTBAM 
else 
  # demultiplexing (if applicable)
  echo "Demultiplexing..."
  # submitjob.sh -c 12 -m 4G -n lima -- 
  lima $OUTBAM $INDICES $OUTFQ --same --ccs --min-score 80 --num-threads 12 --split-named
fi

# echo "Waiting for job to complete..."
# waitForJobs.sh

#cleanup
rm demux/chunks/*
rmdir demux/chunks

echo "Success!"

