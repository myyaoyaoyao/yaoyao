#!/usr/bin/env bash
set -eu

if [[ "$#" -ne 4 ]]; then
  echo -e "Usage: $0 Cores Bam Output Region" && exit 1
fi

cores=$1 && shift
bam=$1 && shift
output=$1 && shift
region=$1 && shift

if [[ ! $cores =~ ^[0-9]+$ ]]; then
  echo "ERROR: $cores is not a number" && exit 1
fi

if [[ ! -f $bam ]]; then
  echo "ERROR: $bam not exists" && exit 1
fi

parent_dir=$(dirname $output)
if [[ ! -d $parent_dir ]]; then
  echo "ERROR: $parent_dir not exists" && exit 1
fi

if [[ ! -f $region ]]; then
  echo "ERROR: $region not exists" && exit 1
fi

# log file
log="$output.log"
if [[ -f $log ]]; then rm $log; fi

echo "# call variant starts at $($DATE)"

# freebayes
fb_raw_vcf="$output.FB.raw.vcf"
cmd="cat $region | parallel -k -j $cores $FREEBAYES -m 30 -q 20 -R 0 -S 0 --strict-vcf
  -f $REF --region {} $bam 2>>$log |
  $VCFFIRSTHEADER | $VCFSTREAMSORT | $VCFUNIQ >$fb_raw_vcf"
echo $cmd && eval $cmd

# GATK
gatk_raw_vcf="$output.GATK.raw.vcf"
if [[ $PCR_FREE = true ]]; then
cmd="cat $region | parallel -k -j $(($cores / 2)) $GATK -T HaplotypeCaller
  --pcr_indel_model NONE --max_alternate_alleles 3 -R $REF -L {} -I $bam 2>>$log |
  $VCFFIRSTHEADER | $VCFSTREAMSORT | $VCFUNIQ >$gatk_raw_vcf"
else
cmd="cat $region | parallel -k -j $(($cores / 2)) $GATK -T HaplotypeCaller
  --max_alternate_alleles 3 -R $REF -L {} -I $bam 2>>$log |
  $VCFFIRSTHEADER | $VCFSTREAMSORT | $VCFUNIQ >$gatk_raw_vcf"
fi
echo $cmd && eval $cmd

fb_vcf="$output.FB.vcf"
gatk_vcf="$output.GATK.vcf"
cmd="parallel -j 2 :::
  '$GATK -T SelectVariants -select \"vc.getGenotype(0).isCalled() && QUAL > 10\" -R $REF
    -V $fb_raw_vcf -o $fb_vcf 2>>$log'
  '$GATK -T SelectVariants -select \"vc.getGenotype(0).isCalled() && QD > 2.0 && FS < 200.0\" -R $REF
    -V $gatk_raw_vcf -o $gatk_vcf 2>>$log'"
echo $cmd && eval $cmd


cmd="parallel -j 2 ::: '$BGZIP -f $fb_vcf' '$BGZIP -f $gatk_vcf'"
echo $cmd && eval $cmd

cmd="parallel -j 2 ::: '$TABIX -f $fb_vcf.gz' '$TABIX -f $gatk_vcf.gz'"
echo $cmd && eval $cmd

cmd="parallel -j 2 :::
  '$BCFTOOLS norm -m-both -f $REF -o $fb_vcf $fb_vcf.gz 2>>$log'
  '$BCFTOOLS norm -m-both -f $REF -o $gatk_vcf $gatk_vcf.gz 2>>$log'"
echo $cmd && eval $cmd

cmd="parallel -j 2 ::: '$BGZIP -f $fb_vcf' '$BGZIP -f $gatk_vcf'"
echo $cmd && eval $cmd

cmd="parallel -j 2 ::: '$TABIX -f $fb_vcf.gz' '$TABIX -f $gatk_vcf.gz'"
echo $cmd && eval $cmd

merged_vcf="$output.merged.vcf"
cmd="$BCFTOOLS merge --force-samples -m none $fb_vcf.gz $gatk_vcf.gz >$merged_vcf"
echo $cmd && eval $cmd

echo "# call variant ends at $($DATE)"
