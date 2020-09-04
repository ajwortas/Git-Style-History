#!/bin/bash

#full file path for repo and dest, 0 to disable 1 to enable the rest, any number above 0 for iterations
repo=$1
dest=$2
release_hashes=$3
checkpoint_iterations=$4
hide_non_java_from_change_list=$5
skip_ignored_file_commits=$6
include_non_java_files=$7
include_compared_files=$8
include_commits_between_versions=$9

let history_count_length=6

#method for creating checkpoints
function makeCheckpoint () {
    local currentPos=$(PWD)
    local repoPos=$1
    local checkpointPos=$2
    local versionCount=$3
    local versionHash=$4
    local checkpointName="$versionCount-$versionHash"

    cd $checkpointPos
    mkdir $checkpointName

    cd $repoPos
    git checkout $versionHash 
    cp -r "$repoPos/." "$checkpointPos/$checkpointName"

    cd $currentPos
}

function jsonFormating () {
    jsonFormatted=$1
        jsonFormatted=${jsonFormatted//\\/\\\\} # \ 
        jsonFormatted=${jsonFormatted//\//\\\/} # / 
        jsonFormatted=${jsonFormatted//\'/\\\'} # ' 
        jsonFormatted=${jsonFormatted//\"/\\\"} # " 
        jsonFormatted=${jsonFormatted//   /\\t} # \t (tab)
        jsonFormatted=${jsonFormatted//
/\\\n} # \n (newline)
        jsonFormatted=${jsonFormatted//^M/\\\r} # \r (carriage return)
        jsonFormatted=${jsonFormatted//^L/\\\f} # \f (form feed)
        jsonFormatted=${jsonFormatted//^H/\\\b} # \b (backspace)
}

#To keep the history in order this formats the chronological count to add leading 0s (currently set to 6 digits of length)
function countFormating () {
    formattedCount="$chronologicalCount"
    while [ ${#formattedCount} -lt $history_count_length ]
    do
        formattedCount="0$formattedCount"
    done
}

#turns a github short stat result into global variables: incertions, deletions, numFilesChanged
function parseStatsData () {
    local hashChanges=$1

    #there are instances where there are no additions xor deletions in which case the hash changes variable
    #does not acknowledge them with a 0 instead leaving it blank. 

    incertions=''
    if [[ $hashChanges == *"(+)"* ]]
	then
        incertions="$(echo $hashChanges | grep -o -P '(?<=changed, ).*(?=insertion)')"
    else
        incertions='0'
    fi
    deletions=''
    if [[ $hashChanges == *"(-)"* ]]
	then
		if [[ $hashChanges == *"(+)"* ]]
		then
			deletions="$(echo $hashChanges | sed 's/(+), /add/' |
				grep -o -P '(?<=add).*(?=deletion)')"
		else
			deletions="$(echo $hashChanges | sed 's/changed, /add/' |
				grep -o -P '(?<=add).*(?=deletion)')"
		fi
	else
		deletions="0"
	fi

    numFilesChanged="$(echo $hashChanges | sed 's/file.*//g')" 
}

function fileSpecific () {

}

function commitSpecific (){

}

function main () {
    cd $repo

    local hashList="$(git log --all --reverse --no-merges --pretty=format:'%H')"
    local oldest="$(echo $hashList | sed 's/ .*//')"
    local hashList="$(<$release_hashes)"

    #initial structure, all variables global:
    {
        cd $dest
        mkdir "history"
        historyLocation="$dest/history"
        mkdir "metadata"
        jsonLocation="$dest/metadata"
        mkdir "fileDiffs"
        fileDiffsLocation="$dest/fileDiffs"
        mkdir "checkpoints"
        checkpointLocation="$dest/checkpoints"
        {
            echo "Count,Hash,Compared Hash,Last Release,Next Release,Author's Name,Author's Date,Subject,Files Changed,Incertions,Deletions,Sample Files,Sample Modified,Sample Added,Sample Deleted"
        }>general_data.csv
        spreadsheetLocation="$dest/general_data.csv"
    }

    #arrays used to determine branching
    declare -a prevHash
    prevHash[0]=$oldest
    declare -a tagLog
    tagLog[0]="0.0.0,$oldest"
    local lastChronologicalMajorVersion=0

    let checkpointDeterminerCount=0
    let chronologicalCount=0
    let cpNextMinorVersion=0

    for gitHash in $hashList
    do
        #returns to the repo to collect the needed git data
        cd $repo
    
        #deals with the tag tree structure
        fullTag="$(git describe --tags $gitHash)"
        simpleTag="$(echo "$fullTag"| grep -o -E '[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+')"
        let majorVersion="$(echo $simpleTag | sed 's/\..*//')"
        let prevHashIndex=$majorVersion
        while [ -z ${prevHash[$prevHashIndex]} ]
        do
            newMajorVersion=1
            let prevHashIndex--
        done
        compareHash=${prevHash[$prevHashIndex]}
        prevHash[$majorVersion]=$gitHash

        #Duplicate Hashes are sometimes an issue
        if [ $gitHash == $compareHash ]
        then
            continue
        fi

        #Used when just comparing released versions, determines if given version meets criteria to proceed
        if [ $include_commits_between_versions -eq 0 ]
        then
            filesChanged="$(git diff --name-only $compareHash..$gitHash)"
            if [ $skip_ignored_file_commits -eq 1 ] && [[ $filesChanged != *".java"* ]]
            then
                continue
            fi
        fi
        tagLog[$majorVersion]="${tagLog[$prevHashIndex]}:$fullTag,$gitHash"

    done
}

main
echo "done"
