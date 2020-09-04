#!/bin/bash
repo=$1

data="$(PWD)/branchDataRN.csv"
cd $repo

hashList=$(git log --all --reverse --first-parent --pretty="%H")
echo $(git log --all --first-parent --pretty="%H" | wc -l)

{
    echo "Order,Hash,Subject,Branches,Num Branches,Name-Rev"
}>$data

let count=0

for gitHash in $hashList
do
    let count++
    {
        echo "$count,$gitHash,\"$(git log -1 --pretty="%s" $gitHash|tr '"' "'")\",\"$(git branch -a --remotes --contains $gitHash)\",\"$(git branch -a --remotes --contains $gitHash | wc -l)\",\"$(git name-rev --name-only $gitHash)\""
    }>>$data
done

echo "done"
