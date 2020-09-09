#!/bin/bash

repoList=$(<$1)
dest=$2
fileExtention=$3

tempDir="$dest/temp"
mkdir $tempDir
cd $tempDir

for repo in $repoList
do
    git clone $repo
    repoName=$(ls)
    outputFolder="$dest/$repoName"
    mkdir $outputFolder
    cd $repoName
    nullCommit=$(git hash-object -t tree /dev/null)
    allFiles=$(git diff --name-only $nullCommit)
    for fileName in $allFiles
    do
        if [[ $fileName == *"$fileExtention"* ]]; then
            mv $fileName $outputFolder
        fi
    done
    cd $tempDir 
    rm -rf "$repoName"
done

rmdir $tempDir

