#!/bin/bash

repo=$1
output=$2

cd $repo
commits="$(git log --reverse --pretty="%H" --first-parent)"

{
    echo "count,hash,message,author date,commit date,merge type"
}>$output

let count=0

for commit in $commits
do
    classification='normal commit'
    message=$(git log -1 --pretty="%B" $commit | tr '"' "'")
    authorDate=$(git log -1 --pretty="%ad" $commit)
    commitDate=$(git log -1 --pretty="%cd" $commit)

    if [ "$commit" == "$(git log -1 --pretty="%H" --merges $commit)" ]
    then
        classification="Explicit Merge"
    elif [[ $message == *Squashed\ commit\ of\ the\ following* ]]   
    then
        classification="Squash Merge"
    elif [ "$authorDate" != "$commitDate" ]
    then
        classification="Rebase"
    fi

    {
        echo "$count,$commit,\"$message\",$authorDate,$commitDate,$classification"
    }>>$output

    let count++
done



