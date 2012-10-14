
# CONFIG OPTIONS
# TODO: enable choosing the following at first use and by command line parameters.
DESTDIR=./Minerva


cout="/tmp/cookie1"
cin="/tmp/cookie2"
temp1="/tmp/temp1"
temp2="/tmp/temp2"
temptree="/tmp/tree"

swap_cookies() {
    ctemp="$cout"
    cout="$cin"
    cin="$ctemp"
}

html_escape() {
    # No more is needed, I think. Unless some scumbag teacher names his
    # directories with weird characters...
    echo "$1" | sed -e 's_/_%2F_g' -e 's/ /%20/g'
}

sed_escape() {
    echo "$1" | sed -e 's_/_\\/_g'
}

# Reading username and password.
read -p "Username: " username
stty -echo
read -p "Password: " password; echo
stty echo

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

echo -n "Constructing Minerva Document tree... "
# Parsing $temp1 and retrieving minerva document tree.
cat "$temp1" | sed '/course_home.php?cidReq=/!d' | # filter lines with a course link on it.
    sed 's/.*course_home\.php?cidReq=\([^"]*\)">\([^<]*\)<.*/\2,\1/' | # separate course name and cidReq with a comma.
    sed 's/ /_/g' | # avod trouble by substituting spaces by underscores.
    cat - > "$temp2"

touch "$temptree"
{
    # Make a hidden file system for the synchronizing.
    mkdir -p "$DESTDIR/.minerva"

    for course in $(cat "$temp2"); do
        name=$(echo "$course" | sed 's/,.*//')
        cidReq=$(echo "$course" | sed 's/.*,//')
        link="http://minerva.ugent.be/main/document/document.php?cidReq=$cidReq"

        # Make a directory for the course.
        mkdir -p "$DESTDIR/.minerva/$name"

        # Retrieving the course documents home.
        echo "$name ($link)"
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
            localdir="$DESTDIR/.minerva/$name/$folder"
            mkdir -p "$localdir"

            # Retrieving directory.
            curl -b "$cin" -c "$cout" "$link&curdirpath=$(html_escape $folder)" --output "$temp1" 2> /dev/null
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
                # TODO check if file exists, if so, check date.
                echo "$rest" | sed -e 's/,/\n/' -e 's/_#_/ /g' > "$localdir/$filename.new"
            done
        done

        echo
    done
} > "$temptree"

echo "done."

cat "$temptree"
