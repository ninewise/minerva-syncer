#!/bin/bash

# Some constants.
temp1="/tmp/temp1"
temp2="/tmp/temp2"
temptree="/tmp/temptree"
home="https://minerva.ugent.be/"
configdir="$XDG_CONFIG_HOME/minerva-syncer"
dateparam="-d"
if [ "$OSTYPE" == "linux-gnu" ]; then
    dateparam="-d"
elif [[ "$OSTYPE" == "darwin*" ]]; then
    dateparam="-f"
fi

# Checks whether space separated $1 contains $2.
contains() {
    for member in $1; do
        if [ "$member" == "$2" ]; then
            return 0
        fi
    done
    return 1
}

# Ask the user about $1. If $1 is a directory, ask whether to download
# it as a whole, interactive, not at the moment or not ever. If $1 is a
# normal file, ask whether to download it now, later, or never.
ask_download_behaviour() {
    if [ -d "$1" ]; then
        question="Download the directory $1 [C]omplete, [i]nteractive, [l]ater or [n]ever?"
        shorts="c i l n"
    else
        question="Download the file $1 [Y]es, [l]ater or [n]ever?"
        shorts="y l n"
    fi
    read -p "$question " answer
    while ! contains "$shorts" "${answer:0:1}"; do
        read -p "Please reply with any of ($shorts). " answer
    done
    echo ${answer:0:1}
}

# The cookie files. We need two, as curl wants an in and an out cookie.
# I alias the curl method to include a method which swaps the two
# files.
cin="/tmp/cookie1"
cout="/tmp/cookie2"
swap_cookies() {
    ctemp="$cin"
    cin="$cout"
    cout="$ctemp"
}

# Methods to escape file names:
# - Replace slashes and spaces from file names, so they can be used in
#   the urls.
# - Escape slashes to use filenames in sed substitutions.
url_escape() {
    echo "$1" | sed -e 's_/_%2F_g' -e 's/ /%20/g'
}
sed_escape() {
    echo "$1" | sed -e 's_/_\\/_g'
}

# Let's start our main program.

# First, loading the config file.
if test -e "$configdir/config"; then
    # Yes, this is not secure. Don't edit the file, then.
    . "$configdir/config"
else
    # Ask the user some questions.
    echo
    echo "Welcome to minerva-syncer."
    echo
    echo "It seems this is the first time you're running the script."
    echo "Before we start synchronizing with Minerva, I'll need to know"
    echo "you're UGent username."
    echo
    read -p "UGent username: " username
    echo
    echo "Pleased to meet you, $username."
    echo
    echo "If you want, I could remember your password, so that you do"
    echo "not have to enter it every time. However, since I have to"
    echo "pass it to Minerva, I'll have to save it in plain text."
    echo "Hit enter if you don't want your password saved."
    echo
    stty -echo
    read -p "UGent password: " password; echo
    stty echo
    echo
    echo "Now, which folder would you like so synchronize Minerva to?"
    echo "If you're OK with \"~/Minerva\", just hit enter. Otherwise,"
    echo "enter the absolute path to the folder you'd like to use."
    echo
    read -p "Destination directory: " destdir
    echo
    echo "OK, that's it. Let's get synchronizing."

    # Default value.
    if test -z "$destdir"; then
        destdir=~/Minerva
    fi

    # Create the target directory if it does not yet exist.
    if test ! -d "$destdir"; then
        mkdir "$destdir"
    fi
    datafile="$destdir/.mdata"
    date > "$datafile"

    # Create the config directory.
    if test ! -d "$configdir/"; then
        mkdir "$configdir/"
    fi

    {
        # Let's write a new config file.
        echo "username=\"$username\""
        echo "password=\"$password\""
        echo "destdir=\"$destdir\""
    } > "$configdir/config"
fi

if test -z "$password"; then
    stty -echo
    read -p "Password for $username: " password; echo
    stty echo
fi

# Initializing cookies and retrieving authentication salt.
echo -n "Initializing cookies and retrieving salt... "
curl -c "$cout" "https://minerva.ugent.be/secure/index.php?external=true" --output "$temp1" 2> /dev/null
swap_cookies

salt=$(cat "$temp1" | sed '/authentication_salt/!d' | sed 's/.*value="\([^"]*\)".*/\1/')
echo "done."

# Logging in.
echo -n "Logging in as $username... "
curl -b "$cin" -c "$cout" \
    --data "login=$username" \
    --data "password=$password" \
    --data "authentication_salt=$salt" \
    --data "submitAuth=Log in" \
    --location \
    --output "$temp2" \
        "https://minerva.ugent.be/secure/index.php?external=true" 2> /dev/null
swap_cookies
echo "done."

# Retrieving header page to parse.
echo -n "Retrieving minerva home page... "
curl -b "$cin" -c "$cout" "http://minerva.ugent.be/index.php" --output "$temp1" 2> /dev/null
echo "done."

echo -n "Constructing Minerva Document tree"
# Parsing $temp1 and retrieving minerva document tree.
cat "$temp1" | sed '/course_home.php?cidReq=/!d' | # filter lines with a course link on it.
    sed 's/.*course_home\.php?cidReq=\([^"]*\)">\([^<]*\)<.*/\2,\1/' | # separate course name and cidReq with a comma.
    sed 's/ /_/g' | # avod trouble by substituting spaces by underscores.
    cat - > "$temp2"

# Make a hidden file system for the synchronizing.
mkdir -p "$destdir/.minerva"

for course in $(cat "$temp2"); do
    echo -n "."
    name=$(echo "$course" | sed 's/,.*//')
    cidReq=$(echo "$course" | sed 's/.*,//')
    link="http://minerva.ugent.be/main/document/document.php?cidReq=$cidReq"

    # Make a directory for the course.
    mkdir -p "$destdir/.minerva/$name"

    # Retrieving the course documents home.
    curl -b "$cin" -c "$cout" "$link" --output "$temp1" 2> /dev/null
    swap_cookies

    # Parsing the directory structure from the selector.
    folders=$(cat "$temp1" |
        sed '1,/Huidige folder/d' | # Remove everything before the options.
        sed '/_qf__selector/,$d' |  # Remove everything past the options.
        sed '/option/!d' | # Assure only options are left.
        sed 's/.*value="\([^"]*\)".*/\1/' # Filter the directory names.
    )

    # For each directory.
    for folder in $folders; do
        # Make the folder in the hidden files system.
        localdir="$destdir/.minerva/$name/$folder"
        mkdir -p "$localdir"

        # Retrieving directory.
        curl -b "$cin" -c "$cout" "$link&curdirpath=$(url_escape $folder)" --output "$temp1" 2> /dev/null
        swap_cookies

        # Parsing files from the directory.
        files=$(cat "$temp1" |
            # Only lines with a file or a date in. (First match: course site; second match: info site, third: date)
            sed -n -e '/minerva\.ugent\.be\/courses....\/'"$cidReq"'\/document\//p' \
                   -e '/minerva\.ugent\.be\/courses_ext\/'"${cidReq%_*}"'ext\/document\//p' \
                   -e '/[0-9][0-9]\.[0-9][0-9]\.[0-9][0-9][0-9][0-9] [0-9][0-9]:[0-9][0-9]/p' |
            # Extract file url.
            sed 's|.*href="\([^"]*/document'"$folder"'[^"]*?cidReq='"$cidReq"'\)".*|\1|' | 
            # Extract the date.
            sed 's/.*\([0-9][0-9]\)\.\([0-9][0-9]\)\.\([0-9][0-9][0-9][0-9]\) \([0-9][0-9]\):\([0-9][0-9]\).*/\2\/\1_#_\4:\5_#_\3/' |
            # Join each url with the file name and date.
            sed -n '/http:/{N;s/\n/,/p;}' | sed 's/\(.*\)\/\([^\/]*\)?\(.*\)/&,\2/'
        )
        for file in $files; do
            filename=${file#*,*,}
            rest=${file%,*}
            echo "$rest" | sed -e 's/,/\n/' -e 's/_#_/ /g' > "$localdir/$filename.new"
        done
    done
done
echo " done."

# Filtering the list of files to check which are to be updated.
echo "Downloading individual files... "
# Retrieve the last update time.
last=$(date +"%s" $dateparam "$(head -1 "$datafile")")
for file in $(find "$destdir/.minerva/"); do

    localfile=${file/.minerva\//}
    localfile=${localfile%.new}
    name=${file#*.minerva/}
    name=${name/.new/}

    # Do not take any files matching in datafile.
    if grep "$name" "$datafile" > /dev/null 2>&1; then
        continue
    fi

    # Can't download directories, yes?
    if [ "${file:(-4)}" != ".new" ]; then
        mkdir -p "$localfile"
        continue
    fi

    theirs=$(date +"%s" -d "$(cat "$file" | tail -1)")
    answer="n"
    if [ -e "$localfile" ]; then # We have once downloaded the file.
        ours=$(stat -c %Y "$localfile")
        if (( ours > last && theirs > last )); then # Locally modified.
            read -p "$name was updated both local and online. Overwrite? [Y/n] " answer
            while [ "${answer,,}" != "y" ] && [ "${answer,,}" != "n" ] && [ "$answer" != "" ]; do
                read -p "please answer with y or n. [Y/n] " answer
            done
        fi
    else
        read -p "$name was created online. Download? [Y/n/never] " answer
        while [ "${answer,,}" != "y" ] && [ "${answer,,}" != "n" ] && [ "$answer" != "" ] && [ "${answer,,}" != "never" ]; do
            read -p "please answer with y, n or never. [Y/n/never] " answer
        done
    fi

    if [ "${answer,,}" == "y" ] || [ "$answer" == "" ]; then # Download.
        curl -b "$cin" -c "$cout" --output "$temp1" "$(head -1 "$file")"
        swap_cookies
        mv "$temp1" "$localfile"
    else
        if [ "${answer,,}" == "never" ]; then # Add to files not to download.
            echo "$localfile" >> "$datafile"
        fi
    fi
done
echo "Done. Your local folder is now synced with Minerva."

mv "$datafile" "$temp1"
cat "$temp1" | sed "1c $(date)" > "$datafile"
