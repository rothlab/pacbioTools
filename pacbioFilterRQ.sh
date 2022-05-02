#!/bin/bash

#Default Quality score cutoff = 16 (i.e. accept 17 and above)
RQ=0.998
OUTFILE=""

#helper function to print usage information
usage () {
  cat << EOF

pacbioFilterQS.sh v0.0.1 

by Jochen Weile <jochenweile@gmail.com> 2021

Filter BAM files by quality score
Usage: pacbioFilterQS.sh [-q|--qualityCutoff <INTEGER>] [-o|--outfile <OUTBAM>] <BAM>

<BAM>              : The input BAM file
-o|--outfile       : The output BAM file. <BAM>_RQ<RQ>.bam in current folder.
-q|--qualityCutoff : Only allow reads with RQ greater than this. Default: $RQ

EOF
 exit $1
}

set -euo pipefail

echo "pacbioFilterRQ.sh v0.0.1"

#tokenize command line arguments
PARAMS=$(getopt -u -n "pacbioFilterRQ.sh" -o "q:h" -l "qualityCutoff:,help" -- "$@")
#parse parameter tokens
eval set -- "$PARAMS"
PARAMS=""
NUMRX='^[0-9]+$'
while (( "$#" )); do
  case "$1" in
    -q|--qualityCutoff)
      if ! [[ $2 =~ $NUMRX ]]; then
        echo "Error: qualityCutoff must be an integer number!">&2
        usage 1
      elif [[ $2 < 0 || $2 > 20 ]]; then
        echo "Error: qualityCutoff must be between 0 and 20"
      fi
      RQ=$2
      shift 2
      ;;
    -o|--outfile)
      OUTFILE=$2
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

BAMFILE=$1
BAMRX='\.bam$'
if [[ -z $BAMFILE ]]; then
  echo "Error: No BAM file provided!">&2
  usage 1;
elif ! [[ $BAMFILE =~ $BAMRX ]]; then
  echo "Error: $BAMFILE is not a .bam file!">&2
  usage 1;
elif ! [[ -r $BAMFILE ]]; then
  echo "Error: BAMFILE does not exist or cannot be read!">&2
  usage 1;
fi

if [[ -z "$OUTFILE" ]]; then
  OUTFILE=$(basename "${BAMFILE%.bam}_RQ${RQ}.bam")
elif [[ ! -d $(dirname $OUTFILE) ]]; then
  echo "Error: Path to outfile $OUTFILE does not exist!"
  usage 1;
fi

echo "Output will be written to ${OUTFILE}"
echo "Filtering for RQ=${RQ} ..."

# #Filter file will contain all values of QS to be filtered
# FILTERFILE=$(mktemp)
# #write numbers 0 through QS into filterfile, separated by newlines
# eval echo "{0..${QS}}"|sed -r "s/ /\n/g">$FILTERFILE

# echo "Filtering..."
# #invert filter by writing to "unoutput" and discarding main output
# samtools view $BAMFILE -b -D "qs:${FILTERFILE}" -U $OUTFILE >/dev/null

# echo "Done!"
# #delete temp file
# rm $FILTERFILE

function filterByRQ_slow() {
  BAMFILE=$1
  RQCUTOFF=${2:-0.95}
  samtools view -H $BAMFILE
  samtools view "$BAMFILE"|while IFS="" read -r SAMLINE; do
    RQVAL=$(echo $SAMLINE|grep -oP 'rq:f:\K[\S]+')
    if (( $(echo "$RQVAL > $RQCUTOFF"|bc -l) )); then
      printf "%s\n" "$SAMLINE"
    fi
  done
}

function filterByRQ() {
  BAMFILE=$1
  samtools view -H $BAMFILE
  samtools view "$BAMFILE"|python3  -c '
import sys
import re
# cutoff = float(sys.argv[0])
cutoff = 0.999
with sys.stdin as stream:
  for line in stream:
    line = line.rstrip()
    matchObj = re.search(r"rq:f:(\S+)", line)
    if matchObj:
      rq = matchObj.group(1)
      if (float(rq) > cutoff):
        print(line)
'
}
filterByRQ "$BAMFILE" "$RQ"|samtools view -b -o $OUTFILE




echo "Done!"


# cat test.sam|head -2|while IFS= read -r SAMLINE; do
#   # RQVAL=$(echo $SAMLINE|grep -oP 'rq:f:\K[\S]+')
#   # echo "$RQVAL"
#   printf "%s\n" "$SAMLINE"
# done
