#!/bin/bash

dir=$1
output=$2

files=$(ls $dir)
numOfFiles=$(ls $dir | wc -l)
let count=0

data=''

for file in $files
do
let count++
let updateTest=count%250
if [ $updateTest -eq 0 ]
then
    echo "On file $count of $numOfFiles"
fi

data="${data}$file $(grep -o '"Parent_hashes":"[a-z 0-9]*"' "$dir/$file")|" 
done

{
    echo $data | tr '|' '\n'
} > "$output"

echo "done"
