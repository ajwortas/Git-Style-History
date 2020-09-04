#!/bin/bash

repo=$1
dest=$2

cd "${repo}"
mkdir temp
initialRepo=$repo
repo="${repo}/temp"

hashList="$(git log --all --no-merges --pretty=format:'%H')"

let count=0
for githash in $hashList
do
#    git checkout $githash
    filesChanged="$(git show --pretty="" --name-only $githash)"
#    subject="$(git log --pretty=format:'%s')"

    cd "$dest"
    newDir="${count}-${githash}"
    mkdir $newDir
    copyDest="${dest}/${newDir}"
    cd $newDir
    {
        echo "$githash "
#       echo "$subject "
        echo $filesChanged | sed 's/ /:/g'
    }>filesChanged.txt    

    cd $repo
#    cp "$filesChanged" "$copyDest"
    for file in $filesChanged
    do
        if [[ $file == *".java"* ]]
        then 
           fileName="$(echo $file | sed 's!.*/!!')"
           git show "${githash}:${file}">$fileName
           mv $fileName $copyDest
        fi         
    done
    let count++
done

cd $initialRepo
rmdir temp

echo "done"