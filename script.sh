
cout="/tmp/cookie1"
cin="/tmp/cookie2"
temp1="/tmp/temp1"
temp1="/tmp/temp1"

swap_cookies() {
    ctemp="$cout"
    cout="$cin"
    cin="$ctemp"
}

# Reading username and password.
read -p "Username: " username
stty -echo
read -p "Password: " password; echo
stty echo

# Initializing cookies and retrieving authentication salt.
echo -n "Initializing cookies and retrieving salt... "
curl --cookie-jar "$cout" "https://minerva.ugent.be/secure/index.php?external=true" --output "$temp1" 2> /dev/null
swap_cookies

salt=$(cat "$temp1" | sed '/authentication_salt/!d' | sed 's/.*value="\([^"]*\)".*/\1/')
echo "done."

# Logging in.
echo -n "Logging in as $username... "
curl --cookie "$cin" --cookie-jar "$cout" \
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
curl --cookie "$cin" --cookie-jar "$cout" "http://minerva.ugent.be/index.php" --output "$temp1" 2> /dev/null
echo "done."

# Parsing $temp1 and retrieving minerva document tree.
cat "$temp1" | sed '/course_home.php?cidReq=/!d' | # filter lines with a course link on it.
    sed 's/.*course_home\.php?cidReq=\([^"]*\)">\([^<]*\)<.*/\2,\1/'
