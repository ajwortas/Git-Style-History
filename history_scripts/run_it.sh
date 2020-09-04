#!/bin/bash

repo="$(PWD)/RxJava"
dest="$(PWD)/output"
file_loc="$(PWD)/RxJava_versions.txt"
curPos="$(PWD)"

echo "Starting log: $(date)">timelog.txt

echo "Running script, making checkpoint from releases every 50 releases getting old files: $(date)">>timelog.txt
./gitHistoryVersions_10.sh $repo $dest $file_loc 25 0 1 0 1 1

cd $curPos
echo "Main Script Finished at: $(date)">>timelog.txt

./fileDiffDataCompiler.sh "$dest/fileDiffs" "$dest"

cd $curPos
echo "Compiler Script Finished at: $(date)">>timelog.txt
