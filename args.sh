
#!/usr/bin/env bash
set -eu

# get parameters
if [[ "$#" -ne 3 ]]; then
  echo -e "Usage: $0 Cores FastqFilesDir OutputDir" && exit 1
fi

export CORES=$1 && shift
export FASTQ_DIR=$(readlink -f $1) && shift
export OUTPUT_DIR=$(readlink -f $1) && shift

# validate parameters
if [[ ! -d $FASTQ_DIR ]]; then
  echo "ERROR: $FASTQ_DIR not exists" && exit 1
fi

if [[ ! $CORES =~ ^[0-9]+$ ]]; then
  echo "ERROR: $CORES is not a number" && exit 1
fi

echo "CORES: $CORES"
echo "FASTQ_DIR: $FASTQ_DIR"
echo "OUTPUT_DIR: $OUTPUT_DIR"
echo

# get sample list
export samples=($(ls -1 $FASTQ_DIR/*.fastq* | xargs -n 1 basename | \
  awk -F '_R[0-9]+' '{print $1}' | sort -u))
printf '%s\n' "${samples[@]}"
echo

# calculate cores
export SC=$(( $CORES / ${#samples[@]} ))
if [[ "$SC" -lt 4 ]]; then export SC=4; fi
export JN=$(( $CORES / $SC ))

# log dir
export LOG_DIR="$OUTPUT_DIR/log"
if [[ -d $LOG_DIR ]]; then rm -r $LOG_DIR; fi
mkdir -p $LOG_DIR
