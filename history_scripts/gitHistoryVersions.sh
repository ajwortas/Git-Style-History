#!/bin/bash

#full file path for repo and dest, 0 to disable 1 to enable the rest, any number above 0 for iterations
repo=$1
dest=$2
release_hashes=$3
checkpoint_iterations=$4
newest_to_oldest=$5 #not implemented
hide_non_java_from_change_list=$6
skip_ignored_file_commits=$7
include_non_java_files=$8

#method for creating checkpoints
makeCheckpoint () {
    currentPos=$(PWD)
    repoPos=$1
    checkpointPos=$2
    versionCount=$3
    versionHash=$4
    checkpointName="$versionCount-$versionHash"

    cd $checkpointPos
    mkdir $checkpointName

    cd $repoPos
    git checkout $versionHash 
    cp -r "$repoPos/." "$checkpointPos/$checkpointName"

    cd $currentPos
}

cd $repo
hashList="$(git log --all --reverse --no-merges --pretty=format:'%H')"
oldest="$(echo $hashList | sed 's/ .*//')"
newest="$(echo $hashList | sed 's/.* //g')"

hashList="$(<$release_hashes)"

makeCheckpoint "$repo" "$dest" "Initial" "$oldest"
makeCheckpoint "$repo" "$dest" "Latest" "$newest"

#creates a history folder to store the commit histories
cd $dest
mkdir "history"
initialDest=$dest
dest="$dest/history"

#arrays for branching
declare -a prevHash
prevHash[0]=$oldest
declare -a tagLog
tagLog[0]="Initial commit,$oldest"


let count=0
for githash in $hashList
do
    #returns to the repo to collect the needed git data
    cd $repo
    
    #deals with the tag tree structure
    fullTag="$(git describe --tags $githash)"
    simpleTag="$(echo "$fullTag"| grep -o -E '[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+')"
    let majorVersion="$(echo $simpleTag | sed 's/\..*//')"
    let prevHashIndex=$majorVersion
    while [ -z ${prevHash[$prevHashIndex]} ]
    do
        let prevHashIndex--
    done
    echo "Tag: $fullTag"
    echo "Simple Tag: $simpleTag"
    echo "Major Version: $majorVersion"
    echo "preHashIndex: $prevHashIndex"
    compareHash=${prevHash[$prevHashIndex]}
    prevHash[$majorVersion]=$githash

    filesChanged="$(git diff --name-only $compareHash $githash)"

    #allows for the option to ignore commits not containing java files
    if [ $skip_ignored_file_commits -eq 1 ] && [[ $filesChanged != *".java"* ]]
    then
        continue
    fi
   
    tagLog[$majorVersion]="${tagLog[$prevHashIndex]}:$fullTag,$githash"

    #check for checkpoint criteria
    let checkForCheckpoint=$count%$checkpoint_iterations
    if ([ $checkForCheckpoint -eq 0 ] && [ ! $checkpoint_iterations -eq 0 ]) || [ ! $majorVersion -eq $prevHashIndex ]
    then
        makeCheckpoint "$repo" "$initialDest" "$count" "$githash"
    fi
  
    #gets additional data not needed to determine skipping this commit
    hashData=`git log -1 --pretty="\"Hash\":\"%H\",%n\"Tree_hash\":\"%T\",%n\"Parent_hashes\":\"%P\",%n\"Author_name\":\"%an\",%n\"Author_date\":\"%ad\",%n\"Committer_name\":\"%cn\",%n\"Committer_date\":\"%cd\",%n\"Subject\":\"%s\",%n\"Commit_Message\":\"%B\",%n\"Commit_notes\":\"%N\"," $githash`
    hashChanges="$(git diff --shortstat $compareHash $githash)"
    
    #creates a commit's directory
    cd $dest
    newDir="${count}-${simpleTag}-${githash}"
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
        fileOutput="$(echo $filesChanged | tr ' ' '\n' | grep '.*\.java' | tr ' ' ':')"
    else
        fileOutput="$(echo $filesChanged | tr ' ' ':')"
    fi

    #parsing stat data
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

    #creating metadata files
    {
        echo $fileOutput | tr ':' '\n'
    }>"${newDir}_filesChanged.txt"
    {
        echo "Files_Changed,$(echo $hashChanges | sed 's/file.*//g')" | tr -d ' '
        echo "Incertions,$incertions"| tr -d ' '
        echo "Deletions,$deletions"| tr -d ' '
    }>"${newDir}_fileChangeDetails.csv"
    {
        echo '{'
        echo $hashData
        echo "\"Number_of_files_changed\":$(echo $hashChanges | sed 's/file.*//g')," | tr -d ' '
        echo "\"Incertions\":$incertions," | tr -d ' '
        echo "\"Deletions\":$deletions,"| tr -d ' '
        echo "\"Files_Changed\":\"$fileOutput\""
        echo '}'
    }>"${newDir}_gitCommitData.json"
    {   
        echo ${tagLog[$majorVersion]} | tr ':' '\n'
    }>"${newDir}_tagLog.csv"

    for file in $filesChanged
    do
        #ignores non java files
        if [ ! $include_non_java_files -eq 1 ] && [[ $file != *".java"* ]]
        then
            continue
        fi

        fileName=$(basename $file)
        filePath=$(dirname $file)

        #creating the file
        cd $repo
        git show "${githash}:${file}">"$initialDest/$fileName"
        cd $initialDest

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
        mv "$initialDest/$fileName" ./       
    done
    let count++
done

echo "done"
