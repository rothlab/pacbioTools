#!/bin/bash

set -euo pipefail

#helper function to print usage information
usage () {
  cat << EOF

pacbioCheckQuality.sh v0.0.1 

by Jochen Weile <jochenweile@gmail.com> 2021

Check distribution of RQ qualties
Usage: pacbioCheckQuality.sh <BAM>

<BAM>              : The input BAM file

EOF
 exit $1
}


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


function extractNPRQ() {
  BAMFILE=$1
  # RQFILE=$(mktemp)
  # samtools view "$BAMFILE"|grep -oP 'rq:f:\K[\S]+'>$RQFILE
  # NPFILE=$(mktemp)
  # samtools view "$BAMFILE"|grep -oP 'np:i:\K[\S]+'>$NPFILE
  # paste $NPFILE $RQFILE
  # rm $RQFILE $NPFILE
  paste <(samtools view "$BAMFILE"|grep -oP 'rq:f:\K[\S]+') \
        <(samtools view "$BAMFILE"|grep -oP 'np:i:\K[\S]+')
}
extractNPRQ $BAMFILE >nprq.tsv

Rscript -e '
data <- read.delim("nprq.tsv",header=FALSE)
colnames(data) <- c("rq","np")

cat(sprintf("Raw: %d, RQ>.998: %d (=%.01f)",
  nrow(data),
  sum(data$rq>.998,na.rm=TRUE),
  100*sum(data$rq>.998,na.rm=TRUE)/nrow(data)
),file="readCounts.txt")

if (any(data$rq < 0)) {
  png("invalidReads.png")
  barplot(
    c(
      `CCS failed`=100*sum(data$rq < 0)/nrow(data),
      `CCS success`=100*sum(data$rq > 0)/nrow(data)
    ),
    col=c("firebrick3","darkolivegreen3"),
    border=NA, ylab="% reads"
  )
  dev.off()
  data <- data[data$rq > 0,]
}

png("nprq.png")
plot(jitter(data$np,amount=.8),data$rq,pch=".",col=yogitools::colAlpha(1,.2),xlab="numPasses",ylab="RQ")
dev.off()

rqsort <- sort(data$rq)
plotidx <- floor(seq(1,length(rqsort),length.out=100))
idxpoints <- seq(0,1,length.out=100)

png("rqcumu.png")
plot(rqsort[plotidx],idxpoints,type="l",xlab="RQ",ylab="cumulative distr.")
dev.off()

'

echo "Done!"

