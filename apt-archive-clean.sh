#!/bin/bash

#set -x

# depends: bash >= 5.2
benchmark(){
     local -i a="${EPOCHREALTIME/.}-${EPOCHSTARTTIME/.}"
     local    b
    printf -v b %07d "$a" && printf %s "${b/%??????/.&}"
}

EPOCHSTARTTIME=$EPOCHREALTIME

# Depends: flock, dpkg-query, awk, find, sort, xargs, rm

timeout=5
lockfile=lock
apt_cache=/var/cache/apt/archives
flock=/usr/bin/flock

# Keep max <#> versions of any single package.
limit=2

declare -a  a=() b=()
declare -iA A=() B=()

# https://github.com/util-linux/util-linux/commit/8a0dc11a5b204c7d43adae9f42abcebe41c5b66e
exec 3> "$apt_cache/$lockfile" && $flock -x -w $timeout --fcntl 3
if (($? != 0)); then
    echo "Error: Could not obtain a lock."
    exit 1
fi

builtin cd "$apt_cache" || exit 1

# Encode package, version: `_:´ and arch: `_:.´.
while read -r package version arch; do
    A[${package}_${version}_${arch}.deb]=1
done < <( \
    dpkg-query \
        -Wf='${db:Status-Abbrev}${Package} ${Version} ${Architecture}\n' | \
    awk '$1 == "ii" {
        print gensub(/:/, "%3a", "g", gensub(/_/, "%5f", "g", sprintf("%s %s %s", $2, $3, gensub(/\./, "%2e", "g", $4))))
    }' \
)

# URL decode .deb filenames.
# Count all packages both archived and installed.
while IFS= read -rd ''; do
    ((B[${REPLY%%_*}]++)); [[ ${A[$REPLY]} = 1 ]] || a+=("$REPLY")
done < <( \
    find -name '*.deb' -printf %P\\0 | sort -Vz \
)

# Finalize list of all packages to remove.
for deb in "${a[@]}"; do
    ((B[${deb%%_*}]-- > limit)) && b+=("$deb")
done
((${#b[@]} > 0)) && { \
    printf %s\\0 "${b[@]}" | xargs -0 rm -v || exit 0; }

printf '\nBenchmark (%ss).\n' $(benchmark)
