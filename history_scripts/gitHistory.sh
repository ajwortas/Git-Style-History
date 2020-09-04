#!/bin/bash

repo=$1
dest=$2

cd $repo

#creates a temp folder in the repo to store desired files
tempName="tempForHistory"
mkdir $tempName
initialRepo=$repo
repo="${repo}/${tempName}"

#all hashes in the directory
hashList="$(git log --all --no-merges --pretty=format:'%H')"

let count=0
for githash in $hashList
do
    #returns to the repo to collect the needed git data
    cd $repo
    filesChanged="$(git show --pretty="" --name-only $githash)"
    hashData=`git log -1 --pretty="Hash:%H|Tree hash:%T|Parent hashes:%P|Author name:%an|Author date:%ad|Committer name:%cn|Committer date:%cd|Subject:%s|Commit Message:%B|Commit notes:%N" $githash |
       sed 's/\n/ /g'`
    hashChanges="$(git log -1 --shortstat --pretty="" $githash)"
    
    #creates a commit's directory
    cd $dest
    newDir="${count}-${githash}"
    mkdir $newDir
    copyDest="${dest}/${newDir}"
    cd $newDir

    #storage for general collected
    gitData="collectedGitData"
    mkdir $gitData
    cd $gitData

    #stores git data as txt files
    {
        echo $filesChanged | sed 's/ /:/g'
    }>filesChanged.txt   
    {
        echo $hashData|sed 's/|/\n/g'
        
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
        echo "Files changed:$(echo $hashChanges | sed 's/file.*//g')"
        echo "Incertions:$incertions"
        echo "Deletions:$deletions"
    }>gitCommitData.txt
    
    for file in $filesChanged
    do

        #ignores non java files
        if [[ $file == *".java"* ]]
        then 
            fileName=$(basename $file)
            filePath=$(dirname $file)

            #return to temp folder to make the file
            cd $repo
            git show "${githash}:${file}">$fileName
        
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
        fi         
    done
    let count++
done

#clean up of temp folder
cd $initialRepo
rmdir $tempName
echo "done"