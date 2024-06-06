#!/bin/bash
#
# addfou.sh
# version 0.2
# by Joe1962
#
# Updates 'department' attribute from the top OU of each user,
# in a samba 4 AD DC.
#
# Change the following variables for your use case:
# LDAP_SERVER, LDAP_BIND_DN, LDAP_BIND_PW, BASE_DN, EXCLUDED_OUS
#
# set DOECHO to 0 or 1 as desired (note: does not seem 
# to significantly change speed in my tests).
#
# Search for comment: "Enable following line for more security",
# enable following commands to delete temporary files.
#
# Search for comment: "Filter out some stuff", 
# enable following command block and edit the OU names 
# to disallow some OUs from the jabber groups.
#

# LDAP connection settings
LDAP_SERVER="ldap://your.ldap.server"
LDAP_BIND_DN="cn=Administrator,cn=Users,dc=cenpalab,dc=cu"
LDAP_BIND_PW="your_password"

# Base DN for users
BASE_DN="OU=MYOU,DC=MYDC,DC=cu"

# Temp files
export TEMP_USERS="/tmp/users.lst"
export TEMP_UPDATE="/tmp/update.ldif"

# Excluded OUs (comma separated list):
EXCLUDED_OUS="BAJAS,Correos,Invitados"

# cursor up???:
UP='\033[1A'

# echo operations: 0 = false, 1 = true:
DOECHO=1

# Retrieve all users in the domain:
ldapsearch -x -H "$LDAP_SERVER" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PW" -b "$BASE_DN" -o ldif-wrap=no "(objectClass=person)" dn | grep "^dn:" | perl -MMIME::Base64 -Mutf8 -pe 's/^([-a-zA-Z0-9;]+):(:\s+)(\S+)$/$1.$2.&decode_base64($3)/e' > $TEMP_USERS

# Retrieve all users in the domain:
while IFS= read -r line; do

	# Extract the user's DN
	USER_DN=$(echo "$line" | cut -d' ' -f2-)

	# Extract the CN from the user's DN
	USER_CN=$(echo "$USER_DN" | grep -oP 'CN=[^,]+' | cut -d'=' -f2-)

	# Remove the base DN from the user's DN
	USER_DN_WITHOUT_BASE=$(echo "$USER_DN" | sed "s/,$BASE_DN//")

	# Extract the last OU component from the remaining DN
	TOP_LEVEL_OU=$(echo "$USER_DN_WITHOUT_BASE" | grep -oP 'OU=[^,]+' | tail -n 1 | cut -d'=' -f2-)


	# Filter out some stuff:
	IFSBAK=$IFS
	IFS=,
	for EXCLUDED in ${EXCLUDED_OUS} ; do
		if [[ $TOP_LEVEL_OU == $EXCLUDED ]]; then
			TOP_LEVEL_OU=""
		fi
	done
	IFS=IFSBAK


	if [ -n "$TOP_LEVEL_OU" ]; then
		# Prepare the LDIF for updating the department field:
		LDIF_DATA=$(cat <<EOL
dn: $USER_DN
changetype: modify
replace: department
department: $TOP_LEVEL_OU
EOL
)

		# Update the user's department field using ldapmodify:
		if [ $DOECHO == 1 ]; then
			echo
			echo "$LDIF_DATA" | ldapmodify -x -H "$LDAP_SERVER" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PW"
			printf "$UP"
			echo "Updated $USER_CN ($USER_DN): department set to $TOP_LEVEL_OU"
		else
			echo "$LDIF_DATA" | ldapmodify -x -H "$LDAP_SERVER" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PW" &> /dev/null
		fi
	else
		#echo
		#echo "Could not determine top-level OU for $USER_CN ($USER_DN)"
		#echo
		
		# Prepare the LDIF for emptying the department field
		LDIF_DATA=$(cat <<EOL
dn: $USER_DN
changetype: modify
replace: department
-
EOL
)

		# Empty the user's department field using ldapmodify:
		if [ $DOECHO == 1 ]; then
				echo
			echo "$LDIF_DATA" | ldapmodify -x -H "$LDAP_SERVER" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PW"
				printf "$UP"
			echo "Updated $USER_CN ($USER_DN): department set to $TOP_LEVEL_OU"
		else
			echo "$LDIF_DATA" | ldapmodify -x -H "$LDAP_SERVER" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PW" &> /dev/null
		fi

	fi

done < $TEMP_USERS

# Enable following lines for more security:
#rm $TEMP_USERS
#rm $TEMP_UPDATE

echo "Finished updating 'department' attributes."

