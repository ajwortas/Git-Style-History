Example input:
[use exact pathing]

./repoMiner.sh $(PWD)/repoTestList.txt $(PWD)/output .txt

This looks in the file repoTestList.txt to find all the repo urls
It then makes a work directory in the output called temp where it 
clones the repos one at a time (deleting them as it goes) where it
gets of all the files in the repo and moves the specified type over
to a secondary folder in the output. 
