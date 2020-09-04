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

#method for creating checkpoints
makeCheckpoint () {
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

makeFileAndPath () {
    local currentPos=$(PWD)
    local repo=$1
    local copyDest=$2
    local givenHash=$3
    local holdingLoc=$4
    local file=$5
    local previousCommit=$6

    fileName=$(basename $file)
    filePath=$(dirname $file)
    
    #creating the file
    cd $repo
    git show "${givenHash}:${file}">"$holdingLoc/$fileName"
    cd $holdingLoc

    #this occurs when a file was deleted in the commit
    if [ ! -s $fileName ]
    then
        rm $fileName
        if [ $previousCommit -eq 0 ]
        then
            currentFilesDeleted="$currentFilesDeleted:$fileName"
        else
            oldFilesDeleted="$oldFilesDeleted:$fileName"
        fi
        return 0
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
    mv "$holdingLoc/$fileName" ./ 
    
    cd $currentPos
}

countFormating () {
    if [ $count -lt 10 ]
    then
        formattedCount="00000$count"
        return 0
    fi
    if [ $count -lt 100 ]
    then
        formattedCount="0000$count"
        return 0
    fi
    if [ $count -lt 1000 ]
    then
        formattedCount="000$count"
        return 0
    fi
    if [ $count -lt 10000 ]
    then
        formattedCount="00$count"
        return 0
    fi
    if [ $count -lt 100000 ]
    then
        formattedCount="0$count"
        return 0
    fi
    if [ $count -lt 1000000 ]
    then
        formattedCount="$count"
        return 0
    fi
}

parseStatsData () {
    local hashChanges=$1

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

makeCommitFolder () {
    local count=$1
    local version=$2
    local curHash=$3
    local prevHash=$4

    #gets additional data not needed to determine skipping this commit
    cd $repo
    local filesChanged="$(git diff --name-only $prevHash..$curHash)"
    
    if [ -z "$filesChanged" ] || ([ $skip_ignored_file_commits -eq 1 ] && [[ $filesChanged != *".java"* ]])
    then
        functionCheck=1
        return 0
    fi

    countFormating

    if [ $checkpointRequired -eq 1 ]
    then 
        makeCheckpoint "$repo" "$initialDest" "$formattedCount-$simpleTag" "$gitHash"
        checkpointRequired=0
    fi

    local hashData=`git log -1 --pretty="\"Hash\":\"%H\",%n\"Tree_hash\":\"%T\",%n\"Parent_hashes\":\"%P\",%n\"Author_name\":\"%an\",%n\"Author_date\":\"%ad\",%n\"Committer_name\":\"%cn\",%n\"Committer_date\":\"%cd\",%n\"Subject\":\"%s\",%n\"Commit_Message\":\"%B\",%n\"Commit_notes\":\"%N\"," $curHash`
    local hashChanges="$(git diff --shortstat $prevHash..$curHash)"
    
    #creates a commit's directory
    cd $dest
    local newDir="${$formattedCount}-${version}-${curHash}"
    mkdir $newDir
    local copyDest="${dest}/${newDir}"
    cd $newDir

    #storage for files
    local nonMetaData="commit_changes"
    mkdir $nonMetaData
    local prevHashCopyDest=''
    if [ $include_compared_files -eq 1 ]
    then
        local prevNonMetaData="prev_commit_changes"
        mkdir $prevNonMetaData
        local prevHashCopyDest="$copyDest/$prevNonMetaData"
    fi
    local copyDest="$copyDest/$nonMetaData"

    #Data parsing and storage
    local fileOutput=''
    if [ $hide_non_java_from_change_list -eq 1 ]
    then
        local fileOutput="$(echo $filesChanged | tr ' ' '\n' | grep '.*\.java' | tr '\n' ':')"
    else
        local fileOutput="$(echo $filesChanged | tr ' ' ':')"
    fi

    currentFilesDeleted=''
    oldFilesDeleted=''
    for file in $filesChanged
    do
        #ignores non java files
        if [ ! $include_non_java_files -eq 1 ] && [[ $file != *".java"* ]]
        then
            continue
        fi

        makeFileAndPath $repo $copyDest $curHash $initialDest $file 0
    
        if [ $include_compared_files -eq 1 ]
        then
            makeFileAndPath $repo $prevHashCopyDest $prevHash $initialDest $file 1
        fi  
    done 

    parseStatsData "$hashChanges"
    currentFilesDeleted=${currentFilesDeleted#?}
    oldFilesDeleted=${oldFilesDeleted#?}

    #creating metadata files
    cd $newDir
    {
        echo $fileOutput | tr ':' '\n'
    }>"${newDir}_filesChanged.txt"
#    {
#        echo "Files_Changed,$numFilesChanged" | tr -d ' '
#        echo "Incertions,$incertions" | tr -d ' '
#        echo "Deletions,$deletions" | tr -d ' '
#    }>"${newDir}_fileChangeDetails.csv"
    {
        echo '{'
        echo $hashData
        echo "\"Number_of_files_changed\":$numFilesChanged," | tr -d ' '
        echo "\"Incertions\":$incertions," | tr -d ' '
        echo "\"Deletions\":$deletions," | tr -d ' '
        echo "\"Current_Hash\":\"$curHash\","
        echo "\"Compared_Hash\":\"$prevHash\","
        echo "\"Last_Released_Version\":\"$oldTag\","
        echo "\"Next_Released_Version\":\"$fullTag\","
        echo "\"Tag_history\":[\"$(echo ${tagLog[$majorVersion]} | sed 's/:/","/g')\"],"
        echo "\"All_Files_Changed\":[\"$(echo "$fileOutput" | sed 's/:/","/g')\"],"
        if [ $include_compared_files -eq 1 ]
        then 
            echo "\"Added_Files\":[\"$(echo "$oldFilesDeleted" | sed 's/:/","/g')\"],"
        fi
        echo "\"Deleted_Files\":[\"$(echo "$currentFilesDeleted" | sed 's/:/","/g')\"]"
        echo '}'
    }>"${newDir}_gitCommitData.json"
    {   
        echo ${tagLog[$majorVersion]} | tr ':' '\n'
    }>"${newDir}_tagLog.csv"
}


#gathers needed info then makes initial checkpoints
cd $repo
hashList="$(git log --all --reverse --no-merges --pretty=format:'%H')"
oldest="$(echo $hashList | sed 's/ .*//')"
newest="$(echo $hashList | sed 's/.* //g')"
hashList="$(<$release_hashes)"

#makeCheckpoint "$repo" "$dest" "Initial" "$oldest"
#makeCheckpoint "$repo" "$dest" "Latest" "$newest"

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

let checkpointCount=0
let count=0
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
        let prevHashIndex--
    done
    compareHash=${prevHash[$prevHashIndex]}
    prevHash[$majorVersion]=$gitHash

    filesChanged="$(git diff --name-only $compareHash..$gitHash)"

    #allows for the option to ignore versions not containing java files or are duplicates
    if ([ $skip_ignored_file_commits -eq 1 ] && [[ $filesChanged != *".java"* ]] && [ $include_commits_between_versions -eq 0 ] ) || [ $gitHash == $compareHash ]
    then
        continue
    fi
   
    tagLog[$majorVersion]="${tagLog[$prevHashIndex]}:$fullTag,$gitHash"

    #check for checkpoint criteria
    checkpointRequired=0
    let checkForCheckpoint=$checkpointCount%$checkpoint_iterations
    if ([ $checkForCheckpoint -eq 0 ] && [ ! $checkpoint_iterations -eq 0 ]) || [ ! $majorVersion -eq $prevHashIndex ] || [ $cpNextMinorVersion -eq 1 ] || [ ! $prevHashIndex -eq $majorVersion ]
    then
        if [[ $simpleTag =~ .*[0-9]+\.[0-9]+\.0 ]]
        then
            
            cpNextMinorVersion=0
        else
            cpNextMinorVersion=1
        fi
    fi
    
    #building the history path(s)
    if [ $include_commits_between_versions -eq 1 ]
    then
        #accquires the old tag if we're including the old commit files
        oldTag=''
        simpleOldTag=''
        if [ $count -eq 0 ]
        then
            oldTag=$oldest
            simpleOldTag="0.0.0"
        else
            oldTag="$(git describe --tags $compareHash)"
            simpleOldTag=$(echo "$oldTag"| grep -o -E '[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+')
        fi
        
        #finding the commits between the current version and the previous version
        intraVersionCommits="$(git log --reverse --pretty="%H" $compareHash..$gitHash)"

        for commitHash in $intraVersionCommits
        do
            functionCheck=0
            countFormating
            makeCommitFolder "$formattedCount" "$simpleOldTag" "$commitHash" "$compareHash"
            compareHash=$commitHash
            if [ $functionCheck -eq 0 ]
            then
                let count++
#                let countTest=$count%1000
#                if [ $countTest -eq 0 ]
#                then
#                    $cpNextMinorVersion=1
#                fi
            fi
        done
    else
        countFormating
        makeCommitFolder "$formattedCount" "$simpleTag" "$gitHash" "$compareHash"
        let count++
    fi
    let checkpointCount++
done

echo "done"
