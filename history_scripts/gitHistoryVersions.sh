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

#To keep the history in order this formats the chronological count to add leading 0s (currently set to 6 digits of length)
countFormating () {
    formattedCount="$chronologicalCount"
    while [ ${#formattedCount} -lt $history_count_length ]
    do
        formattedCount="0$formattedCount"
    done
}

#turns a github short stat result into global variables: incertions, deletions, numFilesChanged
parseStatsData () {
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

#TODO get diff data:
# git diff <oldhash>..<current hash> -- <file name>
# git diff --shortstat <oldhash>..<current hash> -- <file name>
makeFileAndPath () {
    local currentPos=$(PWD)
    local repo=$1
    local copyDest=$2
    local givenHash=$3
    local holdingLoc=$4
    local file=$5
    local previousCommit=$6
    local previousCommitHash=$7

    local fileName=$(basename $file)
    local filePath=$(dirname $file)
    
    cd $repo

    #mechanism to ignore copying over non-java files into the changed files path. Does however add them to
    #files added, files deleted, and files modified by checking if they exist
    if [ ! $include_non_java_files -eq 1 ] && [[ $file != *".java"* ]]
    then
        local checkIfPresent="$(git show "${givenHash}:${file}"|tr '\0' ' ')" 
        
        if [ -z "$checkIfPresent" ]
        then 
            if [ $previousCommit -eq 0 ]
            then
                filesDeleted="$filesDeleted:$file"
            else
                filesAdded="$filesAdded:$file"
            fi
            filesModified=$(echo $filesModified | sed "s|$file||")
        fi
        return 0 
    fi

    #does not create it in the final location as it needs to test if the file is empty (implying addition or deletion)
    #and thus does not get its path created
    git show "${givenHash}:${file}">"$holdingLoc/$fileName"

    #gets the diff and context from files
    if [ $previousCommit -eq 0 ]
    then
        if [ ! -d "$holdingLoc/file_diffs" ]
        then
            mkdir "$holdingLoc/file_diffs"
        fi
        parseStatsData "$(git diff --shortstat $previousCommitHash..$givenHash -- $file)"
        local gitDiffOutput=$(git diff $previousCommitHash..$givenHash -- $file)
        local gitDiffOutput=${gitDiffOutput//\\/\\\\} # \ 
        local gitDiffOutput=${gitDiffOutput//\//\\\/} # / 
        local gitDiffOutput=${gitDiffOutput//\'/\\\'} # ' 
        local gitDiffOutput=${gitDiffOutput//\"/\\\"} # " 
        local gitDiffOutput=${gitDiffOutput//   /\\t} # \t (tab)
        local gitDiffOutput=${gitDiffOutput//
/\\\n} # \n (newline)
        local gitDiffOutput=${gitDiffOutput//^M/\\\r} # \r (carriage return)
        local gitDiffOutput=${gitDiffOutput//^L/\\\f} # \f (form feed)
        local gitDiffOutput=${gitDiffOutput//^H/\\\b} # \b (backspace)
        
        #fileDiffData="$fileDiffData,\"$file\":[$incertions,$deletions,\"$gitDiffOutput\"]"
        local hashedFileName="$(echo "$file" | sha1sum | sed 's/ .*//').txt"
        git diff $previousCommitHash..$givenHash -- $file > "$holdingLoc/file_diffs/$hashedFileName"
        #fileDiffData="$fileDiffData,\"$file\":[$incertions,$deletions,\"$hashedFileName\"]"
        fileDiffData="$fileDiffData,\"$file\":[$incertions,$deletions,\"$hashedFileName\",\"$gitDiffOutput\"]"
    fi
    
    cd $holdingLoc

    if [ ! -s $fileName ]
    then
        rm $fileName
        if [ $previousCommit -eq 0 ]
        then
            filesDeleted="$filesDeleted:$file"
        else
            filesAdded="$filesAdded:$file"
        fi
        filesModified=$(echo $filesModified | sed "s|$file:\*||")
        
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

makeCommitFolder () {
    local folderDisplayCount=$1
    local version=$2
    local curHash=$3
    local prevHash=$4

    cd $repo
    local filesChanged="$(git diff --name-only $prevHash..$curHash)"
    
    #two determinations to see if the commit should be skipped
    #if there's an empty string for files changes the hash is assumed to be either duplicate or tag addition
    #and the hash is skipped to avoid any potential issues
    #otherwise the skip occurs if skip_ignored_file_commits is enabled in which case if no java files are present this returns
    #the old hash is kept to maintain track of non-java file changed when diff includes java files
    if [ -z "$filesChanged" ]
    then
        compareHash=$commitHash
        functionCheck=1
        return 0
    fi
    if [ $skip_ignored_file_commits -eq 1 ] && [[ $filesChanged != *".java"* ]]
    then
        functionCheck=1
        return 0
    fi

    #should only trigger once on the inital accepted commit when looking through all commits between released versions
    if [ $checkpointRequired -eq 1 ]
    then 
        makeCheckpoint "$repo" "$initialDest" "$folderDisplayCount-$simpleOldTag" "$curHash"
        checkpointRequired=0
    fi

    #gathers general data for later file creation
    local hashData=`git log -1 --pretty="\"Hash\":\"%H\",%n\"Tree_hash\":\"%T\",%n\"Parent_hashes\":\"%P\",%n\"Author_name\":\"%an\",%n\"Author_date\":\"%ad\",%n\"Committer_name\":\"%cn\",%n\"Committer_date\":\"%cd\",%n\"Subject\":\"%s\",%n\"Commit_Message\":\"%B\",%n\"Commit_notes\":\"%N\"," $curHash`
    local hashChanges="$(git diff --shortstat $prevHash..$curHash)"
    
    #creates a commit's directory
    cd $dest
    local newDir="${folderDisplayCount}-${version}-${curHash}"
    mkdir $newDir
    
    local copyDest="${dest}/${newDir}"
    cd $newDir

    #non-meta data file paths and storage
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

    filesDeleted=''
    filesAdded=''
    filesModified="$fileOutput"
    fileDiffData=''

    #Section responsible for recreating file path in the directory. If including the older files (ideal)
    #recreates that path as well.
    #Gathers three key data metrics for metadata:
    #               1) what files were added between the last hash and current 
    #                  (derived from the file not being present in the old commit)
    #               2) what files were deleted between the last hash and the current
    #                  (derived from the file not being present in the current commit)
    #               3) what files were modified between the last hash and the current
    #                  (derived from removing the files from #1 & #2 from whole set)
    for file in $filesChanged
    do
        if [ -z $file ]
        then
            continue
        fi 
        makeFileAndPath $repo $copyDest $curHash "${dest}/${newDir}" $file 0 $prevHash
        if [ $include_compared_files -eq 1 ]
        then
            makeFileAndPath $repo $prevHashCopyDest $prevHash "${dest}/${newDir}" $file 1 "n/a"
        fi  
    done 

    #adjusting or gathering metadata output
    #leading : in filesDeleted and files added.
    parseStatsData "$hashChanges"
    filesDeleted=${filesDeleted#:}
    filesAdded=${filesAdded#:}
    fileDiffData="${fileDiffData#\,}"
    filesModified=$(echo "$filesModified" | sed 's|^:\+||' | sed 's|:\+$||')

    #creating metadata files
    cd "${dest}/${newDir}"
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
        echo "\"Tag_history\":[[\"$(echo ${tagLog[$majorVersion]} | sed 's/,/","/g' | sed 's/:/"],["/g')\"]],"
        echo "\"All_Files_Changed\":[\"$(echo "$fileOutput" | sed 's/:/","/g')\"],"
        if [ $include_compared_files -eq 1 ]
        then
            echo "\"Modified_Files\":[\"$(echo "$filesModified" | sed 's/:\+/","/g')\"],"
            echo "\"Added_Files\":[\"$(echo "$filesAdded" | sed 's/:/","/g')\"],"
        fi
        echo "\"Deleted_Files\":[\"$(echo "$filesDeleted" | sed 's/:/","/g')\"],"
        echo "\"File_Diff_Data\":{$fileDiffData}"
        echo '}'
    }>"${newDir}_gitCommitData.json"
}

#NON FUNCTION CODE STARTS HERE

#gathers needed info then makes initial checkpoints
cd $repo

hashList="$(git log --all --reverse --no-merges --pretty=format:'%H')"
oldest="$(echo $hashList | sed 's/ .*//')"

#makes a checkpoint for the initial commit and latest commit. (Not Needed For Implementation)
#newest="$(echo $hashList | sed 's/.* //g')"
#makeCheckpoint "$repo" "$dest" "Initial" "$oldest"
#makeCheckpoint "$repo" "$dest" "Latest" "$newest"

hashList="$(<$release_hashes)"

#creates a history folder to store the commit histories
cd $dest
mkdir "history"
initialDest=$dest
dest="$dest/history"

#arrays used to determine branching
declare -a prevHash
prevHash[0]=$oldest
declare -a tagLog
tagLog[0]="0.0.0,$oldest"
lastChronologicalMajorVersion=0

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

    #check for checkpoint criteria
    #Three core criteria:  1) if the user imputted iteration number is reached (looks for next minor version release)
    #                      2) if there is a major version update (logically a subset of 3rd criteria)
    #                      3) if the major versions switch (i.e. #2 or support for an older version)
    #Checkpoints must be present in the history. Therefore, to ensure it's checkpointing the propper commit this task is done
    #later after determining if a hash will be in history. 
    checkpointRequired=0
    if ([ $checkpointDeterminerCount -eq $checkpoint_iterations ] && [ ! $checkpoint_iterations -eq 0 ]) || [ $cpNextMinorVersion -eq 1 ]
    then
        if [[ $simpleTag =~ .*[0-9]+\.[0-9]+\.0 ]]
        then
            checkpointRequired=1
            cpNextMinorVersion=0
            checkpointDeterminerCount=0
        else
            cpNextMinorVersion=1
        fi
    fi
    if [ ! $majorVersion -eq $lastChronologicalMajorVersion ] || [ $chronologicalCount -eq 0 ]
    then
        checkpointDeterminerCount=0
        checkpointRequired=1
    fi
    lastChronologicalMajorVersion=$majorVersion
    
    #Determines how to proceed to build history. If looking at all commits and not just releases it gathers tag
    #data from last released version. Tag hashes used in place of actual Tags to avoid issues with releases
    #being improperly tagged
    if [ $include_commits_between_versions -eq 1 ]
    then
        oldTag=''
        simpleOldTag=''
        if [ $chronologicalCount -eq 0 ]
        then
            oldTag="0.0.0"
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
            #Function check should be equal to one after makeCommitFolder is called if commit is faulty 
            #(i.e. no changes between no commit or potentially only non-java changes)
            if [ $functionCheck -eq 0 ]
            then
                compareHash=$commitHash
                let chronologicalCount++
            fi
        done
    else
        countFormating
        makeCommitFolder "$formattedCount" "$simpleTag" "$gitHash" "$compareHash"
        let chronologicalCount++
    fi
    let checkpointDeterminerCount++
done

echo "done"
