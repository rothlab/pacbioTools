#!/bin/bash

INBAM="$1"
#infer output file names
OUTBAM=$(dirname $INBAM|sed -r "s/.*\///g")_minPass5.bam
OUTFQ=$(echo $OUTBAM|sed -r "s/\.bam//")

#create a temporary files with values 5 through 1000
TMPFILE=$(mktemp)
for i in {5..100}; do echo $i>>$TMPFILE; done

#filter by number of passes, index and convert to fastq
samtools view -D np:$TMPFILE -o "$OUTBAM" -O BAM -h "$INBAM" &&\
pbindex $OUTBAM &&\
bam2fastq -o $OUTFQ -c 6 $OUTBAM 
#delete tempfile
rm $TMPFILE 

