#!/bin/bash

dir=$1
fileDest=$2

cd $dir

allDirectories=$(ls | tr -d '/')

compiledSheet="$fileDest/compiledData.csv"
{
    echo "File Name,Base Name,Directory Name,Number of Times Modified,Total Insertions,Total Deletions,Initial Insertion,Subsequent Insertions,Authors,Dates,Date First Modified,Date Last Modified,Chronological order changed,Commit Num first modified,Commit num last modified, Hashes Modified"
}>$compiledSheet

allData="$fileDest/allData.csv"
{
    echo "Count,Hash,File Name,Base Name,Directory Name,Author Name,Date,Insertions,Deletions,Initial Commit"
}>$allData

#number of commits less than 5 lines 
#initial size
#number of insertions does not include initial
#minor/major revision
#files committed together

let folderCount=0
let totalDirectories=$(ls | wc -l)

for directory in $allDirectories
do
    let folderCount++
    echo "Starting on directory $folderCount of $totalDirectories at $(date +"%r")"

    files=$(ls $directory)

    fileName=$(echo "$directory.java" | tr '_' '/')
    baseName=$(basename $fileName)
    dirName=$(dirname $fileName)
    
    numTimesModified=$(echo "$files" | wc -l)
    let totalInsertions=0
    let totalDeletions=0
    let initialInsertion=0
    authors=''
    dates=''
    chronologicalOrder=''
    hashes=''

    allSheet=''
    initial=1
    for file in $files
    do
        count=$(echo $file | sed 's/-.*//')
        gitHash=$(echo $file | sed 's/.*-\(.*\)_.*/\1/')
        data=$(head -4 "$directory/$file")
        author=$(echo "$data" | sed -n 1p)
        date=$(echo "$data" | sed -n 2p)
        insertions=$(echo "$data" | sed -n 3p)
        deletions=$(echo "$data" | sed -n 4p)

        allSheet="${allSheet}Ж$count,$gitHash,$fileName,$baseName,$dirName,$author,$date,$insertions,$deletions,$initial"
        if [ $initial -eq 1 ]
        then
            initial=0;
            initialInsertion=$insertions
        fi
        let totalInsertions+=$insertions
        let totalDeletions+=$deletions
        authors="$authorsЖ$author"
        dates="$datesЖ$date"
        chronologicalOrder="$chronologicalOrderЖ$count"
        hashes="$hashesЖ$gitHash"
    done
    let subsequentInsertions=${totalInsertions}-${initialInsertion}
    authors=${authors#Ж}
    dates=${dates#Ж}
    chronologicalOrder=${chronologicalOrder#Ж}
    hashes=${hashes#Ж}
    allSheet=${allSheet#Ж}
    firstDate=$(echo "$dates" | sed 's/Ж.*//')
    lastDate=$(echo "$dates" | sed 's/.*Ж//')
    firstCommitNum=$(echo "$chronologicalOrder" | sed 's/Ж.*//')
    lastCommitNum=$(echo "$chronologicalOrder" | sed 's/.*Ж//')

    {
        echo "$fileName,$baseName,$dirName,$numTimesModified,$totalInsertions,$totalDeletions,$initialInsertion,$subsequentInsertions,\"$(echo $authors | sed 's|Ж|\n|g' )\",\"$(echo $dates | sed 's|Ж|\n|g' )\",$firstDate,$lastDate,\"$(echo $chronologicalOrder | sed 's|Ж|\n|g' )\",$firstCommitNum,$lastCommitNum,\"$(echo $hashes | sed 's|Ж|\n|g' )\""
    }>>$compiledSheet

    {
        echo "$allSheet" | sed 's|Ж|\n|g'
    }>>$allData

done

echo "done"
