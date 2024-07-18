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
MAX_CHECKS=9000
CONDITION_COUNTER=0
# With CFEngine Enterprise 3.24.0 compliance report speed is dramatically improved, we can handle all the checks, no need to filter down to a subset
#LynisControlIdAllowListFile="./LynisControlIdAllowList.txt"
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
                # If no platform is specified then it should be checked on all
                # supported platforms. The lynis policy defines the
                # lynis:lynis_supported_platform class which tells us the lynis
                # policy is running, so we target that so that we don't run
                # checks against hosts that aren't reporting lynis inventory.
                CFEngineClassForLynisOperatingSystem="lynis:lynis_supported_platform"
                ;;
            Linux)
                # If a check targets a specific OS we target the relevant class
                # plus the lynis:lynis_supported_platform class so that we only
                # consider the check on hosts that have that platform AND are
                # running and reporting lynis policy.
                CFEngineClassForLynisOperatingSystem="linux.lynis:lynis_supported_platform"
                ;;
            FreeBSD)
                CFEngineClassForLynisOperatingSystem="freebsd.lynis:lynis_supported_platform"
                ;;
            OpenBSD)
                CFEngineClassForLynisOperatingSystem="openbsd.lynis:lynis_supported_platform"
                ;;
            NetBSD)
                CFEngineClassForLynisOperatingSystem="netbsd.lynis:lynis_supported_platform"
                ;;
            DragonFly)
                CFEngineClassForLynisOperatingSystem="dragonfly.lynis:lynis_supported_platform"
                ;;
            Solaris)
                CFEngineClassForLynisOperatingSystem="solaris.lynis:lynis_supported_platform"
                ;;
            MacOS)
                CFEngineClassForLynisOperatingSystem="darwin.lynis:lynis_supported_platform"
                ;;
            HP-UX)
                CFEngineClassForLynisOperatingSystem="hpux.lynis:lynis_supported_platform"
                ;;
            AIX)
                CFEngineClassForLynisOperatingSystem="aix.lynis:lynis_supported_platform"
                ;;
            *)
                # If it's not one of these that are know, we don't target on any hosts
                # We really shouldn't have any of these.
                CFEngineClassForLynisOperatingSystem="!cfengine"
                ;;
        esac

        # @ole wants the compliance report to show human readable description of check (without requiring the hover js, so that it works in pdf too)
        ConditionId="lynis:$(echo $LynisControlId | tr '[:upper:]' '[:lower:]' )"
        # Let's use the lynis check description for the name by default
        ConditionName="Lynis:${LynisControlId} - ${LynisDescription}"
        ConditionCategory="${LynisGroup}-${LynisCategory}"

        case $CFEngineClassForLynisOperatingSystem in
            "lynis_supported_platform")
                ConditionDescriptionOsPhrase="any Lynis supported Operating system"
                ;;
            *)
                ConditionDescriptionOsPhrase="the $LynisOperatingSystem operating system"
                ;;
        esac
        CheckDescription="${LynisDescription}.\\n\\nConsidered part of ${LynisGroup} ${LynisCategory} by CISOfy.\\nThis condition applies to ${LynisOperatingSystem} which CFEngine identifies by the class ${CFEngineClassForLynisOperatingSystem}.\\nMore information about this Lynis control may be found on CISOfy's website (https://cisofy.com/lynis/controls/${LynisControlId}/)."

        #echo $LynisControlId $LynisType $LynisCategory $LynisGroup $LynisOperatingSystem $CFEngineClassForLynisOperatingSystem $LynisDescription
        ConditionId="lynis:$(echo $LynisControlId | tr '[:upper:]' '[:lower:]' )"

        case $LynisCategory in
            "basics")
                ConditionSeverity="low"
                ;;
            "performance")
                          ConditionSeverity="medium"
                          ;;

            "security")
                ConditionSeverity="high"
                ;;
            *)
                ConditionSeverity="low"
                ;;
        esac

        # Herman hand categorized the checks, so here we follow those categorizations automatically.

        case $ConditionCategory in
            "accounting-security"|"logging-security")
                ConditionCategory="Logging"
                ;;
            "authentication-security")
                ConditionCategory="Authentication"
                ;;
            "banners-security"|"mail_messaging-security")
                ConditionCategory="Banners"
                ;;
            "boot_services-security"|"mac_frameworks-security"|"memory_processes-security"|"system_integrity-security"|"system_integrity-performance")
                ConditionCategory="System integrity"
                ;;
            "containers-security"|"containers-performance")
                ConditionCategory="Containers"
                ;;
            "tooling-security"|"ssh-security"|"squid-security"|"shells-security"|"databases-security"|"webservers-security"|"insecure_services-security"|"malware-security"|"php-security"|"ports_packages-security"|"printers_spools-security"|"scheduling-security"|"crypto-security")
                ConditionCategory="Software"
                case $ConditionName in
                    "Lynis:CRYP-8002")
                      ConditionCategory="Kernel"
                      ;;
                esac
                ;;
            "dns-security"|"firewalls-security"|"nameservices-security"|"networking-basics"|"networking-security"|"snmp-security")
                ConditionCategory="Networking"
                ;;
            "filesystems-security"|"homedirs-security"|"file_permissions-security"|"file_integrity-security")
                ConditionCategory="Files, directories & permissions"
                ;;
            "filesystems-performance"|"storage_nfs-security"|"storage-security")
                ConditionCategory="Storage"
                ;;
            "kernel-security"|"kernel_hardening-security")
                ConditionCategory="Kernel"
                ;;
            "time-security"|"time-performance")
                ConditionCategory="Time"
                ;;
        esac
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
                echo "\"severity\": \"$ConditionSeverity\"," >> $TMPFILE
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
                echo "\"severity\": \"$ConditionSeverity\"," >> $TMPFILE
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
# Don't separate fields so we loop over each line
# If we have defined a pretty name for a check let's use that instead of the lynis description
if [ -e "pretty-names.txt" ]; then
   echo "Found ./pretty-names.txt, re-writing names in generated-compliance-report.json"
  cat pretty-names.txt | while read -r each; do
      generated_name=$(echo "${each}" | awk -F " - " '{print $1}')
      pretty_name=$each
      sed -i "s|${generated_name}.*|${pretty_name}\",|g" generated-compliance-report.json
  done
fi
echo "DONE generating CFEngine Enterprise Compliance report (generated-compliance-report.json)."
if grep '!cfengine' generated-compliacne-report.json; then
    echo "TODO Fix OS classification. At least one check is targeting !cfengine, probably because it is targeting an OS that is not known by this script."
else
    echo "Sanity checks passed, look good to go."
fi
:
