#!/bin/bash

repo=$1
dest=$2
newest_to_oldest=$3
hide_non_java_from_change_list=$4
skip_ignored_file_commits=$5
include_non_java_files=$6

cd $repo

#Finds creates a list of all the hashes then finds the oldest and newest hashes
hashList=''
oldest=''
newest=''
if [ $newest_to_oldest -eq 1 ]
then
    hashList="$(git log --all --no-merges --pretty=format:'%H')"
    newest="$(echo $hashList | sed 's/ .*//')"
    oldest="$(echo $hashList | sed 's/.* //g')"
else
    hashList="$(git log --all --reverse --no-merges --pretty=format:'%H')"
    oldest="$(echo $hashList | sed 's/ .*//')"
    newest="$(echo $hashList | sed 's/.* //g')"
fi

#checks out the master and oldest branch to add to general folder
git checkout $oldest
cd $dest 
mkdir "Oldest-$oldest"
mkdir "Newest-$newest"
cp -r "$repo/." "Oldest-$oldest"

cd $repo
git checkout master
cp -r "$repo/." "$dest/Newest-$newest"

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
for githash in $hashList
do
    #returns to the repo to collect the needed git data
    cd $repo
    filesChanged="$(git show --pretty="" --name-only $githash)"

    #allows for the option to ignore commits not containing java files
    if [ $skip_ignored_file_commits -eq 1 ] && [[ $filesChanged != *".java"* ]]
    then
        continue
    fi
   
    #gets additional data not needed to determine skipping this commit
    hashData=`git log -1 --pretty="\"Hash\":\"%H\",%n\"Tree_hash\":\"%T\",%n\"Parent_hashes\":\"%P\",%n\"Author_name\":\"%an\",%n\"Author_date\":\"%ad\",%n\"Committer_name\":\"%cn\",%n\"Committer_date\":\"%cd\",%n\"Subject\":\"%s\",%n\"Commit_Message\":\"%B\",%n\"Commit_notes\":\"%N\"," $githash`
    hashChanges="$(git log -1 --shortstat --pretty="" $githash)"
    
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
    {
        echo $fileOutput
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
done

#clean up of temp folder
cd $initialRepo
rmdir $tempName
echo "done"
