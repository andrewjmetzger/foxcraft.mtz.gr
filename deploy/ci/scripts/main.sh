#!/bin/bash

echo Hopefully, build.sh has been run before this script can take effect.
echo If not, the CI has messed up.

for d in */
do
    if [ -e nobuild.txt ]
    then
        echo "Could not build directory, not permitted."
    else
        echo "Attempting build..."
        safed=${d%"."}
        number=$RANDOM
        cd "$d"
        ls
        java -jar ../launcher-builder-all.jar --version "$number" --input . --output ../upload --manifest-dest "../upload/$safed.json"
        cd ..
        echo "Building directory attempted to complete"
    fi
done