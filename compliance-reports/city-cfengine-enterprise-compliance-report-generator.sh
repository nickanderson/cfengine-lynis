# Note: This scripts content is authored inside of README.org, it's tangled from
# it. If you want to make an update, please update the code block inside
# README.org

exec 2>&1
echo "Checking for latest lynis version..."
LATEST_LYNIS_VERSION=$(curl -s https://cisofy.com/downloads/lynis/  | pandoc -f html -t plain  | awk '/Version/ {print $3}')
LATEST_LYNIS_VERSION_DIGEST=$(curl -s https://cisofy.com/downloads/lynis/  | pandoc -f html -t plain | grep "SHA256 hash" -A1 | tail -n 1 | sed 's/ //g')
TMPDIR=$(mktemp --directory lynis-compliance-report-generator.XXX.d)
STARTDIR="$(pwd)"
cd $TMPDIR
curl --silent --remote-name "https://downloads.cisofy.com/lynis/lynis-${LATEST_LYNIS_VERSION}.tar.gz";
tar zxf lynis-${LATEST_LYNIS_VERSION}.tar.gz
echo Generating CFEngine Enterprise Compliance Report for Lynis $LATEST_LYNIS_VERSION
cd "$STARTDIR"
TestDB="$TMPDIR/lynis/db/tests.db"
TMPFILE=$(mktemp compliance_report.XXX.json)
> $TMPFILE
echo "{" >> $TMPFILE
echo "\"reports\": {" >> $TMPFILE
echo "\"cisofy-lynis\": {" >> $TMPFILE
echo "\"id\": \"cisofy-lynis\"," >> $TMPFILE
echo "\"type\": \"compliance\"," >> $TMPFILE
echo "\"title\": \"CISOfy Lynis ($LATEST_LYNIS_VERSION)\"," >> $TMPFILE
echo "\"conditions\": [" >> $TMPFILE

#MAX_CHECKS=30
MAX_CHECKS=1000
CONDITION_COUNTER=0
LynisControlIdAllowListFile="./LynisControlIdAllowList.txt"
if [ -f "${LynisControlIdAllowListFile}" ]; then
    echo "Found Lynis Control ID Allow List ${LynisControlIdAllowListFile}, minimizing generated compliance report"
else
    echo "Lynis Control ID Allow List ${LynisControlIdAllowListFile} not found, generating compliance report with all available Lynis Controls"
fi

while read line; do
    if echo "$line" | grep -P "^\s*#.*" > /dev/null; then
        # Do nothing with comments
        # echo "$line matched comment"
        :
    else
        #ID=$(echo "$line" | awk -F: '{print $1}') # TODO REDACT
        LynisControlId=$(echo "$line" | awk -F: '{print $1}')
        ConditionId="lynis:$(echo $LynisControlId | tr '[:upper:]' '[:lower:]' )"
        if [ -f "${LynisControlIdAllowListFile}" ]; then
            if grep --ignore-case --silent "${LynisControlId}" "${LynisControlIdAllowListFile}"; then
                echo "\"${ConditionId}\"," >> $TMPFILE
            fi
        else
            echo "\"${ConditionId}\"," >> $TMPFILE
        fi
    fi
    CONDITION_COUNTER=$((CONDITION_COUNTER+1))
    if [ "$CONDITION_COUNTER" = "$MAX_CHECKS" ]; then
        break
    fi
done < $TestDB
truncate -s -2 $TMPFILE
echo ']}},' >> $TMPFILE

echo '"conditions": {' >> $TMPFILE

CONDITION_COUNTER=0
while read line; do

    if echo "$line" | grep -P "^\s*#.*" > /dev/null; then
        # Do nothing with comments
        # echo "$line matched comment"
        :
    else

        LynisControlId=$(echo "$line" | awk -F: '{print $1}')
        # ID=$(echo "$line" | awk -F: '{print $1}') # TODO REDACT
        LynisType=$(echo "$line" | awk -F: '{print $2}')
        LynisCategory=$(echo "$line" | awk -F: '{print $3}')
        LynisGroup=$(echo "$line" | awk -F: '{print $4}')
        LynisOperatingSystem=$(echo "$line" | awk -F: '{print $5}')
        LynisDescription=$(echo "$line" | awk -F: '{print $6}')
        CFEngineClassForLynisOperatingSystem="";

        case $LynisOperatingSystem in
            "")
                CFEngineClassForLynisOperatingSystem="lynis:lynis_supported_platform"
                ;;
            Linux)
                CFEngineClassForLynisOperatingSystem="linux"
                ;;
            FreeBSD)
                CFEngineClassForLynisOperatingSystem="freebsd"
                ;;
            OpenBSD)
                CFEngineClassForLynisOperatingSystem="openbsd"
                ;;
            NetBSD)
                CFEngineClassForLynisOperatingSystem="netbsd"
                ;;
            DragonFly)
                CFEngineClassForLynisOperatingSystem="dragonfly"
                ;;
            Solaris)
                CFEngineClassForLynisOperatingSystem="solaris"
                ;;
            MacOS)
                CFEngineClassForLynisOperatingSystem="darwin"
                ;;
            HP-UX)
                CFEngineClassForLynisOperatingSystem="hpux"
                ;;
            AIX)
                CFEngineClassForLynisOperatingSystem="aix"
                ;;
            *)
                CFEngineClassForLynisOperatingSystem="UNKNOWN"
                ;;
        esac

        # @ole wants the compliance report to show human readable description of check (without requiring the hover js, so that it works in pdf too)
        ConditionId="lynis:$(echo $LynisControlId | tr '[:upper:]' '[:lower:]' )"
        ConditionName="Lynis:${LynisControlId}"
        ConditionCategory="${LynisGroup}-${LynisCategory}"

        case $CFEngineClassForLynisOperatingSystem in
            "lynis_supported_platform")
                ConditionDescriptionOsPhrase="any Lynis supported Operating system"
                ;;
            *)
                ConditionDescriptionOsPhrase="the $LynisOperatingSystem operating system"
                ;;
        esac
        CheckDescription="${LynisDescription}.\\\\n\\\\nConsidered part of ${LynisGroup} ${LynisCategory} by CISOfy.\\\\nThis condition applies to ${LynisOperatingSystem} which CFEngine identifies by the class ${CFEngineClassForLynisOperatingSystem}.\\\\nMore information about this Lynis control may be found on CISOfy's website (https://cisofy.com/lynis/controls/${LynisControlId}/)."

        #echo $LynisControlId $LynisType $LynisCategory $LynisGroup $LynisOperatingSystem $CFEngineClassForLynisOperatingSystem $LynisDescription
        ConditionId="lynis:$(echo $LynisControlId | tr '[:upper:]' '[:lower:]' )"


        if [ -f "${LynisControlIdAllowListFile}" ]; then
            if grep --ignore-case --silent "${LynisControlId}" "${LynisControlIdAllowListFile}"; then
                echo "\"${ConditionId}\": {" >> $TMPFILE
                echo "\"id\": \"${ConditionId}\"," >> $TMPFILE
                #echo "\"name\": \"Lynis:${LynisControlId}\"," >> $TMPFILE
                echo "\"name\": \"${ConditionName}\"," >> $TMPFILE
                echo "\"description\": \"${CheckDescription}\"," >> $TMPFILE
                echo "\"type\": \"inventory\"," >> $TMPFILE
                echo "\"condition_for\": \"passing\"," >> $TMPFILE
                echo "\"rules\": [" >> $TMPFILE
                echo "{" >> $TMPFILE
                echo "\"attribute\": \"CISOfy Lynis Control ID findings\"," >> $TMPFILE
                echo "\"operator\": \"not_contain\"," >> $TMPFILE
                echo "\"value\": \"$LynisControlId\"" >> $TMPFILE
                echo "}" >> $TMPFILE
                echo "]," >> $TMPFILE
                echo "\"category\": \"$ConditionCategory\"," >> $TMPFILE
                echo "\"severity\": \"medium\"," >> $TMPFILE
                echo "\"host_filter\": \"$CFEngineClassForLynisOperatingSystem\"" >> $TMPFILE
                echo "}," >> $TMPFILE
            fi
        else
                echo "\"${ConditionId}\": {" >> $TMPFILE
                echo "\"id\": \"${ConditionId}\"," >> $TMPFILE
                echo "\"name\": \"${ConditionName}\"," >> $TMPFILE
                echo "\"description\": \"${CheckDescription}\"," >> $TMPFILE
                echo "\"type\": \"inventory\"," >> $TMPFILE
                echo "\"condition_for\": \"passing\"," >> $TMPFILE
                echo "\"rules\": [" >> $TMPFILE
                echo "{" >> $TMPFILE
                echo "\"attribute\": \"CISOfy Lynis Control ID findings\"," >> $TMPFILE
                echo "\"operator\": \"not_contain\"," >> $TMPFILE
                echo "\"value\": \"$LynisControlId\"" >> $TMPFILE
                echo "}" >> $TMPFILE
                echo "]," >> $TMPFILE
                echo "\"category\": \"$ConditionCategory\"," >> $TMPFILE
                echo "\"severity\": \"medium\"," >> $TMPFILE
                echo "\"host_filter\": \"$CFEngineClassForLynisOperatingSystem\"" >> $TMPFILE
                echo "}," >> $TMPFILE
        fi
    fi
    CONDITION_COUNTER=$((CONDITION_COUNTER+1))
    if [ "$CONDITION_COUNTER" = "$MAX_CHECKS" ]; then
        break
    fi
done < $TestDB
truncate -s -2 $TMPFILE
echo '}}' >> $TMPFILE
cat $TMPFILE | jq > generated-compliance-report.json
rm $TMPFILE
rm -rf $TMPDIR
echo "DONE generating CFEngine Enterprise Compliance report (generated-compliance-report.json)."
:
