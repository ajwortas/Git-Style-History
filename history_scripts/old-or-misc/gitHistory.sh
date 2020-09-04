#!/bin/bash

repo=$1
dest=$2
release_hashes=$3
newest_to_oldest=$4 #not implemented
hide_non_java_from_change_list=$5
skip_ignored_file_commits=$6
include_non_java_files=$7

cd $repo

#Finds creates a list of all the hashes then finds the oldest and newest hashes
hashList="$(<$release_hashes)"

#creates a history folder to store the commit histories
cd $dest
mkdir "history"
initialdest=$dest
dest="$dest/history"

#creates a temp folder in the repo to store desired files before their location is created
cd $repo
tempName="tempForHistory"
mkdir $tempName
initialRepo=$repo
repo="${repo}/${tempName}"

let count=0
prevHash=''
for githash in $hashList
do
    if [ $count -eq 0 ]
    then
        prevHash=$githash
        let count++
        continue
    fi

    #returns to the repo to collect the needed git data
    cd $repo
    filesChanged="$(git diff --name-only $prevHash $githash)"

    #allows for the option to ignore commits not containing java files
    if [ $skip_ignored_file_commits -eq 1 ] && [[ $filesChanged != *".java"* ]]
    then
        continue
    fi
   
    #creates a commit's directory
    cd $dest
    newDir="${count}-${githash}"
    mkdir $newDir
    copyDest="${dest}/${newDir}"
    cd $newDir

    #storage for files
    nonMetaData="commit_changes"
    mkdir $nonMetaData
    copyDest="$copyDest/$nonMetaData"

    #Data parsing and storage
    fileOutput=''
    if [ $hide_non_java_from_change_list -eq 1 ]
    then
        fileOutput="$(echo $filesChanged | sed 's/ /\n/g' | grep '.*\.java' | tr '\n' ':')"
    else
        fileOutput="$(echo $filesChanged | sed 's/ /:/g')"
    fi

    {
        echo $fileOutput
    }>"${newDir}_filesChanged.txt"
    
    for file in $filesChanged
    do
        #ignores non java files
        if [ ! $include_non_java_files -eq 1 ] && [[ $file != *".java"* ]]
        then
            continue
        fi

        fileName=$(basename $file)
        filePath=$(dirname $file)

        #return to temp folder to make the file
        cd $repo
        git show "${githash}:${file}">$fileName
        
        #this occurs when a file was deleted in the commit
        if [ ! -s $fileName ]
        then
            rm $fileName
            continue
        fi

        #recreating the path in the commit's directory
        cd $copyDest
        tempIFS=$IFS
        IFS='/'
        for directory in $filePath
        do
            if [ ! -d $directory ]
            then
                mkdir $directory
            fi
            cd $directory
        done
        IFS=$tempIFS

        #finally moving the file to it's desired location
        mv "$repo/$fileName" ./       
    done
    let count++
    prevHash=$githash
done

#clean up of temp folder
cd $initialRepo
rmdir $tempName
echo "done"
