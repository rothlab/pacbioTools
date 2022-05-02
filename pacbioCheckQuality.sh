#!/bin/bash

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
  RQFILE=$(mktemp)
  samtools view "$BAMFILE"|grep -oP 'rq:f:\K[\S]+'>$RQFILE
  NPFILE=$(mktemp)
  samtools view "$BAMFILE"|grep -oP 'np:i:\K[\S]+'>$NPFILE
  paste $NPFILE $RQFILE
  rm $RQFILE $NPFILE
}
extractNPRQ $BAMFILE >nprq.tsv

Rscript -e '
data <- read.delim("nprq.tsv",header=FALSE)
colnames(data) <- c("np","rq")

png("nprq.png")
plot(jitter(data[,1],amount=.8),data[,2],pch=".",col=yogitools::colAlpha(1,.2),xlab="numPasses",ylab="RQ")
dev.off()

rqsort <- sort(data$rq)
plotidx <- floor(seq(1,length(rqsort),length.out=100))
idxpoints <- seq(0,1,length.out=100)

png("rqcumu.png")
plot(rqsort[plotidx],idxpoints,type="l",xlab="RQ",ylab="cumulative distr.")
dev.off()

'
