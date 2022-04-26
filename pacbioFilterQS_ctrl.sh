#!/bin/bash

# BAMS=$(ls VIOZRM9/COT18646.20211024/*/*bam)
BAMS="$@"
JOBS=""
for INBAM in $BAMS; do
  #submit filter job
  echo "Processing $INBAM"
  RETVAL=$(submitjob.sh -c 4 -m 4G -- pacbioFilterQS.sh "$INBAM")
  JOBID=${RETVAL##* }
    if [ -z "$JOBS" ]; then
      #if jobs is empty, set it to the new ID
      JOBS=$JOBID
    else
      #otherwise append the id to the list
      JOBS=${JOBS},$JOBID
    fi
done

waitForJobs.sh -v "$JOBS"

