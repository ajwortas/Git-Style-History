#!/bin/bash

#full file path for repo and dest, 0 to disable 1 to enable the rest, any number above 0 for iterations
repo=$1
dest=$2
release_hashes=$3 #enter blank to skip
checkpoint_iterations=$4
hide_non_java_from_change_list=$5
skip_ignored_file_commits=$6
include_non_java_files=$7
include_compared_files=$8

#important global variables
readonly history_count_length=6
let chronologicalCount=0
nullCommit=$(git hash-object -t tree /dev/null)
compareHash="$nullCommit"
formattedCount=''


#method for creating checkpoints
makeCheckpoints () {
    #check for checkpoint criteria
    #Three core criteria:  1) if the user inputted iteration number is reached (looks for next minor version release)
    #                      2) if there is a major version update 
    #                      3) if the major version downgrades switch (i.e. 1.x --> 0.x)
    #Checkpoints must be present in the history. Therefore, to ensure it's checkpointing the propper commit this task is done
    #later after determining if a hash will be in history. 
    cd $repo
    fileNames=$(ls $historyLocation | tr -d '/')
    
    lastCommitTag=''
    discoveredVersions='-1'
    let versionCount='1'
    for commit in $fileNames
    do
        tag=$(echo $commit | tr '-' '\n' | sed -n 2,2p)

        if [ "$tag" == "$lastCommitTag" ]
        then
            continue
        fi 

        majorVersion=$(echo $tag | sed 's/\..*//')
        lastMajorVersion=$(echo $lastCommitTag | sed 's/\..*//')
        lastCommitTag=$tag
        if [ $majorVersion -gt $discoveredVersions ] || [ $majorVersion -lt $lastMajorVersion ] || [ $versionCount -eq $checkpoint_iterations ]
        then
            if [ $majorVersion -gt $discoveredVersions ]
            then
                let discoveredVersions++
            fi
            mkdir "$checkpointLocation/$commit"
            git checkout $(echo $commit | tr '-' '\n' | sed -n 3,3p)
            cp -r "$repo/." "$checkpointLocation/$commit"
            let versionCount='1'
            continue
        fi
        let versionCount++
    done
}

#To keep the history in order this formats the chronological count to add leading 0s (currently set to 6 digits of length)
countFormating () {
    formattedCount="$chronologicalCount"
    while [ ${#formattedCount} -lt $history_count_length ]
    do
        formattedCount="0$formattedCount"
    done
}

#turns a github short stat result into global variables: insertions, deletions, numFilesChanged
parseStatsData () {
    local hashChanges=$1

    #there are instances where there are no additions xor deletions in which case the hash changes variable
    #does not acknowledge them with a 0 instead leaving it blank. 

    insertions=''
    if [[ $hashChanges == *"(+)"* ]]
	then
        insertions="$(echo $hashChanges | grep -o -P '(?<=changed, ).*(?=insertion)')"
    else
        insertions='0'
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

#interacts specifically with each file
#codes for isPreviousCommit
# [0] = is the current commit the program is on
# [1] = is the compared commit to the current
# [2] = is a branched path that caused merge errors
makeFileAndPath () {
    local numberAndHash=$1
    local copyDest=$2
    local givenHash=$3
    local holdingLoc=$4
    local file=$5
    local isPreviousCommit=$6
    local previousCommitHash=$7

    local currentPos=$(PWD)
    local fileName=$(basename $file)
    local filePath=$(dirname $file)
    
    cd $repo

    #mechanism to ignore copying over non-java files into the changed files path. Does however add them to
    #files added, files deleted, and files modified by checking if they exist
    if [ $include_non_java_files -eq 0 ] && [[ $file != *".java"* ]]
    then
        local checkIfPresent='0'
        git cat-file -e "${givenHash}:${file}" && local checkIfPresent='1' 
        if [ "$checkIfPresent" -eq 0 ]
        then 
            if [ $isPreviousCommit -eq 0 ]
            then
                filesDeleted="$filesDeleted:$file"
            else
                filesAdded="$filesAdded:$file"
            fi
            filesModified=$(echo $filesModified | sed "s|$file||")
        fi
        return 0 
    fi

    #gets the diff and context from files
    if [ $isPreviousCommit -eq 0 ]
    then
        local diffPath="$(echo $file | tr '/' '_' | sed 's/\.java//g')"
        if [ ! -d "$fileDiffsLocation/$diffPath" ]
        then
            mkdir "$fileDiffsLocation/$diffPath"
        fi
        local txtFileName=$(echo $fileName | sed 's/java/txt/')
        parseStatsData "$(git diff --shortstat $previousCommitHash..$givenHash -- $file)"
        {
            echo $authorName
            echo $authorTime
            echo $insertions
            echo $deletions
            git diff $previousCommitHash..$givenHash -- $file 
        }> "$fileDiffsLocation/$diffPath/${numberAndHash}_$txtFileName"
        fileDiffData="$fileDiffData,\"$file\":[\"$authorName\",\"$authorTime\",$insertions,$deletions,\"$diffPath/${numberAndHash}_${txtFileName}\"]"
    fi
    
    #does not create it in the final location as it needs to test if the file is empty (implying addition or deletion)
    #and thus does not get its path created
    git show "${givenHash}:${file}">"$holdingLoc/$fileName"
    if [ ! -s "$holdingLoc/$fileName" ]
    then
        rm "$holdingLoc/$fileName"
        if [ $isPreviousCommit -eq 0 ]
        then
            filesDeleted="$filesDeleted:$file"
        elif [ $isPreviousCommit -eq 1 ]
            filesAdded="$filesAdded:$file"
        fi
        filesModified=$(echo $filesModified | sed "s|$file:\*||")
        return 0
    fi

    #recreating the path in the commit's directory
    if [ ! -d "$copyDest/$filePath" ]
    then
        mkdir -p "$copyDest/$filePath"
    fi

    #finally moving the file to it's desired location
    mv "$holdingLoc/$fileName" "$copyDest/$filePath"
    cd $currentPos
}

#interacts with the commits
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
    if [ -z "$filesChanged" ] || ([ $skip_ignored_file_commits -eq 1 ] && [[ $filesChanged != *".java"* ]])
    then
        if [ -z "$filesChanged" ]
        then
            compareHash=$commitHash
        fi
        functionCheck=1
        return 0
    fi

    local numTestFiles=$(echo "$filesChanged" | grep "*test*" | wc -l)
    local numMergeTestFiles=0
    local hasMergeConflict=0
    local altBranchNumCommits=0
   
    if [ $isMergeCommit -eq 1 ]
    then
        #test to see if there is a merge conflict. In the diff between the share ancestor of the two parents of the merge commit should be the same.
        #unless work is done in the merge commit which we can speculate that there was a merge error and work (further diffs) were needed to resolve it. 
        if [ "$(git diff -U0 $curHash^1...$curHash^2)" != "$(git diff -U0 $curHash^1...$curHash)" ] 
        then
            local hasMergeConflict=1
        fi 
        local altPathFiles=$(git diff --name-only $curHash^1...$curHash^2)
        local numMergeTestFiles=$(echo "$altPathFiles" | grep "test" | wc -l)
        local altBranchNumCommits=$(git log --pretty="%H" $commitHash^1..$commitHash^2 | wc -l)
    fi

   

    #gathers general data for later file creation
    authorName=$(git log -1 --pretty="%an" $curHash)
    authorTime=$(git log -1 --pretty="%aI" $curHash)
    local hashData=$(git log -1 --pretty="ѪHashѪ:Ѫ%HѪ,ѪTree_hashѪ:Ѫ%TѪ,ѪParent_hashesѪ:Ѫ%PѪ,ѪAuthor_nameѪ:Ѫ%anѪ,ѪAuthor_dateѪ:Ѫ%aIѪ,ѪCommitter_nameѪ:Ѫ%cnѪ,ѪCommitter_dateѪ:Ѫ%cdѪ,ѪSubjectѪ:Ѫ%sѪ,ѪCommit_MessageѪ:Ѫ%BѪ,ѪCommit_notesѪ:Ѫ%NѪ," $curHash | 
                                                                sed 's/"/\\"/g' |
                                                                tr '\t' ' ' |
                                                                tr '\n' ' ' |
                                                                sed 's/\\/\\\\/g' |
                                                                tr '\r' ' ' |
                                                                sed  's|Ѫ|"|g')
    local hashDataCSV=$(git log -1 --pretty="Ѫ%anѪ,Ѫ%aIѪ,Ѫ%asѪ,Ѫ%sѪ,Ѫ%BѪ" $curHash | sed "s|\"|''|g" | sed 's/Ѫ/"/g')
    local hashChanges="$(git diff --shortstat $prevHash..$curHash)"
    
    #creates a commit's directory
    local newDir="${folderDisplayCount}-${version}-${curHash}"
    local copyDest="${historyLocation}/${newDir}/commit_changes"
    mkdir -p $copyDest
    if [ $include_compared_files -eq 1 ]
    then
        local prevHashCopyDest="${historyLocation}/${newDir}/prev_commit_changes"
        mkdir $prevHashCopyDest
    fi

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
        makeFileAndPath "${folderDisplayCount}-${curHash}" $copyDest $curHash "${historyLocation}/${newDir}" $file 0 $prevHash 
        if [ $include_compared_files -eq 1 ]
        then
            makeFileAndPath "${folderDisplayCount}-${curHash}" $prevHashCopyDest $prevHash "${historyLocation}/${newDir}" $file 1 "n/a"
        fi  
    done 

    #for use when there has been a merge error.
    if [ $hasMergeConflict -eq 1 ]
    then
       
        local parentHash=$(git log -1 --pretty="%H" $curHash^2)
        local altBranchDest="${historyLocation}/${newDir}/alt_commit_changes"
        mkdir $altBranchDest
        local altConflictBranchDest="${historyLocation}/${newDir}/alt_conflict_commit_changes"
        mkdir $altConflictBranchDest

        for file in $altPathFiles
        do
            if [ "$(git diff -U0 $curHash^1...$curHash^2 -- $file)" != "$(git diff -U0 $curHash^1...$curHash -- $file)" ]
            then
                makeFileAndPath "${folderDisplayCount}-${curHash}" $altConflictBranchDest $parentHash "${historyLocation}/${newDir}" $file 2 "n/a"
            fi
            makeFileAndPath "${folderDisplayCount}-${curHash}" $altBranchDest $parentHash "${historyLocation}/${newDir}" $file 2 "n/a"
        done
    fi

    #adjusting or gathering metadata output
    #leading : in filesDeleted and files added.
    parseStatsData "$hashChanges"
    filesDeleted=${filesDeleted#:}
    filesAdded=${filesAdded#:}
    fileDiffData="${fileDiffData#\,}"
    filesModified=$(echo "$filesModified" | sed 's|^:\+||' | sed 's|:\+$||')

    #creating metadata files
    {
        echo '{'
        echo $hashData
        echo "\"Number_of_files_changed\":$numFilesChanged," | tr -d ' '
        echo "\"Insertions\":$insertions," | tr -d ' '
        echo "\"Deletions\":$deletions," | tr -d ' '
        echo "\"Current_Hash\":\"$curHash\","
        echo "\"Compared_Hash\":\"$prevHash\","
        echo "\"Is_Merge_Commit\":$isMergeCommit,\"Has_Merge_Conflict\":$hasMergeConflict,\"Num_test_files\":$numTestFiles,\"Num_merge_test_files\":$numMergeTestFiles,"
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
    }>"${jsonLocation}/${newDir}_gitCommitData.json"

    #first 15 java files (sample)
    local sampleFiles=$(echo "$fileOutput" | tr ':' '\n' | grep '.*\.java' | sed -n 1,15p | tr '\n' ' ' )
    local sampleModified=$(echo "$filesModified" | tr ':' '\n' | grep '.*\.java' | sed -n 1,15p | tr '\n' ' ' )
    local sampleAdded=$(echo "$filesAdded" | tr ':' '\n' | grep '.*\.java' | sed -n 1,15p | tr '\n' ' ' )
    local sampleDeleted=$(echo "$filesDeleted" | tr ':' '\n' | grep '.*\.java' | sed -n 1,15p | tr '\n' ' ' )
    { 
        #"Count,Hash,Compared Hash,Last Release,Next Release,Author's Name,Author's Date,Subject,Files Changed,Insertions,Deletions,Sample Files,Sample Modified,Sample Added,Sample Deleted"
        echo "$chronologicalCount,$curHash,$prevHash,$oldTag,$fullTag,$hashDataCSV,$isMergeCommit,$hasMergeConflict,$numFilesChanged,$insertions,$deletions,$numTestFiles,$numMergeTestFiles\"$sampleFiles\",\"$sampleModified\",\"$sampleAdded\",\"$sampleDeleted\""
    }>>$spreadsheetLocation
}

mergeCommitHandler() {
    local mergeCommitHash=$1
    local version=$2
    local sidebranchHashes="$(git log --pretty="%H" $mergeCommitHash^1..$mergeCommitHash^2)"



}

hashRangeHandler(){
    local firstHash=$1
    local secondHash=$2
    local tagData=$3
    local commitHash
    local commitHashList="$(git log --reverse --first-parent --pretty="%H" $firstHash..$secondHash)"

    #finding the commits between the current version and the previous version
    for commitHash in $commitHashList
    do
        functionCheck=0
        countFormating
        if [[ "$(git log --pretty="%P" $commitHash)" == * * ]]
        then
            isMergeCommit=1
            mergeCommitHandler $commitHash $tagData
        else
            isMergeCommit=0
        fi
        makeCommitFolder "$formattedCount" "$tagData" "$commitHash" "$compareHash"
        #Function check should be equal to one after makeCommitFolder is called if commit is faulty 
        #(i.e. no changes between commits or potentially only non-java changes)
        if [ $functionCheck -eq 0 ]
        then
            compareHash=$commitHash
            let chronologicalCount++
        fi
    done
}

releaseVersionHandler(){
    local versionHashList=$1

    oldest="$(git log --reverse --pretty="%H" $(echo "$versionHashList" | sed -n 1p) | sed -n 1p)"
    #arrays used to determine branching
    declare -a prevHash
    declare -a tagLog
    declare -a prevReleaseHash
    prevHash[0]=$nullCommit
    prevReleaseHash[0]=$oldest
    tagLog[0]="0.0.0,$oldest"

    for gitHash in $versionHashList
    do
        #returns to the repo to collect the needed git data
        cd $repo
    
        #deals with the tag versioning tree structure
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
        releaseCompareHash=${prevReleaseHash[$prevHashIndex]}
        prevReleaseHash[$majorVersion]=$gitHash

        #Duplicate Hashes are sometimes an issue as they can get tagged differently, sorting based on time puts them together
        #as they were released at the same time
        if [ $gitHash == $releaseCompareHash ]
        then
            continue
        fi
    
        tagLog[$majorVersion]="${tagLog[$prevHashIndex]}:$fullTag,$gitHash"
        
        oldTag=''
        simpleOldTag=''
        if [ $chronologicalCount -eq 0 ]
        then
            oldTag="0.0.0"
            simpleOldTag="0.0.0"
        else
            oldTag="$(git describe --tags $releaseCompareHash)"
            simpleOldTag=$(echo "$oldTag"| grep -o -E '[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+')
        fi

        if [[ $chronologicalCount -eq 0 ]]; then
            hashRangeHandler $oldest $gitHash $simpleOldTag
        else
            hashRangeHandler $compareHash $gitHash $simpleOldTag
        fi
        prevHash[$majorVersion]=$compareHash
    done
}

#NON FUNCTION CODE STARTS HERE
#creates general folder structure
cd $dest
mkdir "history"
historyLocation="$dest/history"
mkdir "metadata"
jsonLocation="$dest/metadata"
mkdir "fileDiffs"
fileDiffsLocation="$dest/fileDiffs"
mkdir "checkpoints"
checkpointLocation="$dest/checkpoints"
mkdir "conflicts"
conflictLocation="$dest/conflicts"

#logging files
spreadsheetLocation="$dest/general_data.csv"
{
    echo "Count,Hash,Compared Hash,Last Release,Next Release,Author's Name,Author's Date,Author's Date Short,Subject,Commit Message,Merge Commit,Merge Conflict,Files Changed,Insertions,Deletions,Num Test Files,Num Merge Branch Test Files,Sample Files,Sample Modified,Sample Added,Sample Deleted"
}>$spreadsheetLocation

cd $repo

#making sure the latest commit is the head
#git checkout $(echo $(git log -1 --all --pretty="%H"))

if [ -z "$release_hashes" ]
then
    hashRangeHandler "$(git log  --all --reverse --pretty="%H"|sed -n 1p)" "$(git log --all -1 --pretty="%H")"
else
    releaseVersionHandler "$(<$release_hashes)"
fi

makeCheckpoints
echo "done"
