#!/bin/bash

#Default Quality score cutoff = 16 (i.e. accept 17 and above)
QS=16

#helper function to print usage information
usage () {
  cat << EOF

pacbioFilterQS.sh v0.0.1 

by Jochen Weile <jochenweile@gmail.com> 2021

Filter BAM files by quality score
Usage: pacbioFilterQS.sh [-q|--qualityCutoff <INTEGER>] <BAM>

<BAM>        : The input BAM file
-q|--qualityCutoff : Only allow reads with QS greater than this. Default: $QS

EOF
 exit $1
}

set -euo pipefail


#tokenize parameters
PARAMS=$(getopt -u -n "pacbioFilterQS.sh" -o "q:h" -l "qualityCutoff:,help" -- "$@")
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
      QS=$2
      shift 2
      ;;
    -h|--help)
      usage 0
      shift
      ;;
    --) #end of options
    PARAMS="$@"
  esac
done
eval set -- "$PARAMS"

BAMFILE=$1
BAMRX='\.bam$'
if [[ -z $BAMFILE ]]; then
  echo "Error: No BAM file provided!">&2
  usage 1;
elif ! [[ $BAMFILE =~ $BAMRX ]]; then
  echo "Error: File is not a .bam file!">&2
  usage 1;
elif ! [[ -r $BAMFILE ]]; then
  echo "Error: BAMFILE does not exist or cannot be read!">&2
  usage 1;
fi


OUTFILE=${BAMFILE%.bam}_QS${QS}.bam

#Filter file will contain all values of QS to be filtered
FILTERFILE=$(mktemp)
#write numbers 0 through QS into filterfile, separated by newlines
eval echo "{0..${QS}}"|sed -r "s/ /\n/g">$FILTERFILE

echo "Filtering..."
#invert filter by writing to "unoutput" and discarding main output
samtools view $BAMFILE -b -D "qs:${FILTERFILE}" -U $OUTFILE >/dev/null

echo "Done!"
#delete temp file
rm $FILTERFILE

echo "Calculating distribution of remaining QS scores..."
#print distribution of remaining Q-scores
samtools view $OUTFILE|grep -oP 'qs:i:\K[0-9]+'|sort -n|uniq -c

echo "Done!"
