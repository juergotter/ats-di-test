#! /bin/bash
#
# ats-codesign-all-fileextensions.sh [DIRECTORY] [FILEEXTENSION 1] [FILEEXTENSION 2]...

CODESIGN_DIRECTORY=$1

CODESIGN_FILEEXTENSIONS=("$@")
CODESIGN_FILEEXTENSIONS=("${CODESIGN_FILEEXTENSIONS[@]:1}")

echo "Setting up Environment"

AZURE_JSON="/etc/ats-codesign/azure.json"
ACS_JSON="/etc/ats-codesign/acs.json"

if [ -z "${AZURE_TENANT_ID}" ]; then
	AZURE_TENANT_ID=$( [ -f ${AZURE_JSON} ] && cat ${AZURE_JSON} | jq -r '.TenantId')
fi
if [ -z "${AZURE_CLIENT_ID}" ]; then
	AZURE_CLIENT_ID=$( [ -f ${AZURE_JSON} ] && cat ${AZURE_JSON} | jq -r '.ClientId')
fi
if [ -z "${AZURE_CLIENT_SECRET}" ]; then
	AZURE_CLIENT_SECRET=$( [ -f ${AZURE_JSON} ] && cat ${AZURE_JSON} | jq -r '.ClientSecret')
fi
if [ -z "${ACS_ACCOUNT_NAME}" ]; then
	ACS_ACCOUNT_NAME=$( [ -f ${ACS_JSON} ] && cat ${ACS_JSON} | jq -r '.CodeSigningAccountName')
fi
if [ -z "${ACS_CERTIFICATE_PROFILE_NAME}" ]; then
	ACS_CERTIFICATE_PROFILE_NAME=$( [ -f ${ACS_JSON} ] && cat ${ACS_JSON} | jq -r '.CertificateProfileName')
fi
if [ -z "${ACS_ENDPOINT}" ]; then
	ACS_ENDPOINT=$( [ -f ${ACS_JSON} ] && cat ${ACS_JSON} | jq -r '.Endpoint')
fi

JSIGN_TSAURL=
if [ ! -z "${TIMESTAMP_SERVER}" ]; then
	JSIGN_TSAURL="--tsaurl ${TIMESTAMP_SERVER}"
fi

JSIGN_TSMODE=
if [ ! -z "${TIMESTAMP_MODE}" ]; then
	JSIGN_TSMODE="--tsmode ${TIMESTAMP_MODE}"
fi

echo "Checking Environment"

ENV_CHECK=1
if [ -z "${AZURE_TENANT_ID}" ] || [ -z "${AZURE_CLIENT_ID}" ] || [ -z "${AZURE_CLIENT_SECRET}" ]; then
	echo "Environment variables not set: AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET"
	if [ ! -f /etc/ats-codesign/azure.json ]; then
		echo "File is not mounted: /etc/ats-codesign/azure.json"
	fi
	ENV_CHECK=0
fi
if [ -z "${ACS_ACCOUNT_NAME}" ] || [ -z "${ACS_CERTIFICATE_PROFILE_NAME}" ] || [ -z "${ACS_ENDPOINT}" ]; then
	echo "Environment variables not set: ACS_ACCOUNT_NAME, ACS_CERTIFICATE_PROFILE_NAME, ACS_ENDPOINT"
	if [ ! -f /etc/ats-codesign/acs.json ]; then
		echo "File is not mounted: /etc/ats-codesign/acs.json"
	fi
	ENV_CHECK=0
fi

echo "Checking Parameters"

if [ -z "${CODESIGN_DIRECTORY}" ]; then
    echo "Parameter [DIRECTORY] is empty"
	ENV_CHECK=0
fi
if [ ${ENV_CHECK} -eq 1 ] && [ ! -d "${CODESIGN_DIRECTORY}" ]; then
    echo "Directory '${CODESIGN_DIRECTORY}' not found"
	ENV_CHECK=0
fi

if [ ${#CODESIGN_FILEEXTENSIONS[@]} -eq 0 ]; then
    echo "Parameter [FILEEXTENSION 1] [FILEEXTENSION 2]... is empty"
	ENV_CHECK=0
fi

FIND_SEPARATOR="\|"
FIND_REGEX="$( printf "${FIND_SEPARATOR}%s" "${CODESIGN_FILEEXTENSIONS[@]}" )"
FIND_REGEX="${FIND_REGEX:${#FIND_SEPARATOR}}" # remove leading separator

readarray -d '' CODESIGN_FILES < <(find "${CODESIGN_DIRECTORY}" -iregex ".*\.\(${FIND_REGEX}\)" -print0)

if [ ${#CODESIGN_FILES[@]} -lt 1 ]; then
	SEPARATOREXTENSIONS=" "
	JOINEXTENSIONS="$( printf "${SEPARATOREXTENSIONS}%s" "${CODESIGN_FILEEXTENSIONS[@]}" )"
	JOINEXTENSIONS="${JOINEXTENSIONS:${#SEPARATOREXTENSIONS}}" # remove leading separator
    echo "No matching files with extension(s) '${JOINEXTENSIONS}' found"
	ENV_CHECK=0
fi

if [ ${ENV_CHECK} -ne 1 ]; then
	echo ""
	echo "Usage: ats-codesign-all-fileextensions.sh [DIRECTORY] [FILEEXTENSION 1] [FILEEXTENSION 2]..."
	exit 10
fi

#####################
# Start Codesigning #
#####################

echo "Fetching AZURE_ACCESS_TOKEN"

AZURE_ACCESS_TOKEN=$( curl -X POST -d "grant_type=client_credentials&client_id=${AZURE_CLIENT_ID}&client_secret=${AZURE_CLIENT_SECRET}&resource=https%3A%2F%2Fcodesigning.azure.net" https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/token | jq -r '.access_token' )

retVal=$?
if [ $retVal -ne 0 ]; then
	echo "Error Fetching AZURE_ACCESS_TOKEN"
	exit $retVal
fi

echo "Codesign using jsing"

for CODESIGN_FILE in "${CODESIGN_FILES[@]}"
do
	jsign	--storetype TRUSTEDSIGNING \
			--keystore ${ACS_ENDPOINT} \
			--storepass ${AZURE_ACCESS_TOKEN} \
			--alias ${ACS_ACCOUNT_NAME}/${ACS_CERTIFICATE_PROFILE_NAME} \
			${JSIGN_TSAURL} ${JSIGN_TSMODE} \
			--replace \
			"${CODESIGN_FILE}"

	retVal=$?
	if [ $retVal -ne 0 ]; then
		echo "ats-codesign [jsign]: Error occurred during codesigning file '${CODESIGN_FILE}'"
		exit $retVal
	fi
done

exit 0
