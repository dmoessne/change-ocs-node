#!/bin/bash
function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

function replace_ep()
{
    #echo "now we are in the function replace_ep"
    if [[  "$ACTION" = "dry" ]]; then 
       #echo "modifying ADDR: $ADDRESSES in dry run"
       echo " This is dry run .... check the outputs below and verify, you can as well copy and past the oc line and run the action manually, but set --dry-run to false"
       echo "oc -n $NS patch -o json --dry-run=true ep/${EP_NS[$ENDP_NS]}  -p '{\"subsets\":[{\"addresses\":[$ADDRESSES],\"ports\": [{\"port\": 1,\"protocol\": \"TCP\"}]}]}' "
       oc -n ${NS} patch -o json --dry-run=true ep/${EP_NS[$ENDP_NS]}  -p "{\"subsets\":[{\"addresses\":[${ADDRESSES}],\"ports\": [{\"port\": 1,\"protocol\": \"TCP\"}]}]}"
    else
       #echo "modifying ADDR: $ADDRESSES in final run"
       echo "This is final run, so no watch and pray:)"
       #echo "oc -n $NS patch -o json --dry-run=false ep/${EP_NS[$ENDP_NS]}  -p '{\"subsets\":[{\"addresses\":[$ADDRESSES],\"ports\": [{\"port\": 1,\"protocol\": \"TCP\"}]}]}' "
       oc -n ${NS} patch -o json --dry-run=false ep/${EP_NS[$ENDP_NS]}  -p "{\"subsets\":[{\"addresses\":[${ADDRESSES}],\"ports\": [{\"port\": 1,\"protocol\": \"TCP\"}]}]}"
    fi
}


function change_endpoints ()
{
    echo
    #echo "this is function change_endpoints"
    #echo "handed over parameter is $NS $OLD_IP_FS $NEW_IP_FS"
    #echo
    EP_NS=($(oc get ep -n $NS |grep $OLD_IP_FS:1 |awk '{print $1}'))
###
    for ENDP_NS in ${!EP_NS[@]}
    do
    args=()
       SAVEIFS=$IFS
       IFS=$','
       EP=`oc get ep -n $NS|grep ${EP_NS[$ENDP_NS]}|awk '{print $2}'|sort|uniq|sed 's/:1//g'`
       #echo  this is EP ${EP_NS[$ENDP_NS]}
       EP_A=($EP)
       IFS=$SAVEIFS
       #echo ${EP_A[@]}
       #echo ${!EP_A[@]}
       for IP_NU in ${!EP_A[@]}
       do
        # echo "this is IP ${EP_A[$IP_NU]}"
         if [[ "${EP_A[$IP_NU]}" = "$OLD_IP_FS" ]]; then
            #echo "this is repl ip ${EP_A[$IP_NU]}"
            args+=("${NEW_IP_FS}")
            #echo "***"
            #echo "${args[$IP_NU]}"
            #echo "***"
         else
            #echo "this is same ip ${EP_A[$IP_NU]}"
            args+=("${EP_A[$IP_NU]}")
            #echo "***"
            #echo "${args[$IP_NU]}"
            #echo "***"

         fi
       done
       ADDRESSES=$(echo ${args[@]} |sed "s/ /\"},{\"ip\": \"/g"|sed "s/.*/{\"ip\": \"&\"}/")
       replace_ep "$ADDRESSES" "${NS}" "${EP_NS[$ENDP_NS]}" "$ACTION"
    done

###
}

#########################################################################################################

read -p "Which endpoint do you want to change (old endpoint to be removed)? Enter old IP: "   OLD_IP_FS
read -p "Which is the new address you do want to have configured ?          Enter new IP: "   NEW_IP_FS
echo
echo "You have choosen to replace $OLD_IP_FS by $NEW_IP_FS"
if ! [[ $OLD_IP_FS =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "$OLD_IP_FS seems not to be a valid IP " 
    exit
fi
if ! [[ $NEW_IP_FS =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "$NEW seems not to be a valid IP " 
    exit
fi
if [[ "$OLD_IP_FS" = "$NEW_IP_FS" ]]; then
    echo "same IP twice, exiting"
    exit
fi
read -p "Is that correct ? (yes/no): " CHOICE_IP_FS
if [[ "$CHOICE_IP_FS" = "no" ]] || [[ "$CHOICE_IP_FS" != "yes" ]]; then
   echo "Try again ... good by"
   exit
   
fi
echo

echo -n "Validating if the old ip is used at all...."
oc get ep --all-namespaces|grep $OLD_IP_FS:1 &>/dev/null
if [[ "$?" != "0" ]]; then 
     echo " $OLD_IP_FS seems not to be used ...... exiting"
     echo
     exit
else
     echo
     echo
     oc get ep --all-namespaces|grep $OLD_IP_FS:1 |grep $NEW_IP_FS:1 &>/dev/null
     if [[ "$?" = "0" ]]; then
        echo "$NEW_IP_FS seems to be used already in the endpoint you want to replace and hence the change does not seem to make sense .... bye"
        exit
     else
        #echo " let's go on"
        NAMESPACES=($(oc get ep --all-namespaces|grep $OLD_IP_FS:1| grep -v $NEW_IP_FS:1|awk '{print $1}' |sort|uniq))
        echo "The following namespaces contain endpoints to change:"
        for i in ${!NAMESPACES[@]}; do 
           echo -e "\t\t\t -  ${NAMESPACES[${i}]}"
           done
        read -p "Do you want to change all endpoints, or just in a single namespace ? (all/namespace): "  NAMESP_NAME
              if [[ "$NAMESP_NAME" = "all" ]]; then 
                 echo "checking all above namespaces for endpoints to change"
                 echo
                 echo "-------------------------------------------------------------------------------------------"
                 echo
                 echo "The following endpoints are to change:"
                 for NS in ${NAMESPACES[@]}; do
                     echo $NS
                     echo "**********"
                     oc get -n $NS ep |grep "$OLD_IP_FS:1"
                     echo -----
                     done
                     echo
                     echo "changing EPs"
                     read -p " Do you want to run a dry run (dry) of final changing run (final)? "  ACTION
                     if { [ "$ACTION" != "dry" ] &&  [ "$ACTION" != "final" ];} then
                        echo " did not get your choice ...... exit"
                        exit 
                     fi
                     for NS in ${NAMESPACES[@]}; do
                     change_endpoints "$NS" "$OLD_IP_FS" "$NEW_IP_FS" "$ACTION"
                     done
                 else
                     echo "Checking  $NAMESP_NAME for endpoints to change"
                     NS=$NAMESP_NAME
                     oc get -n $NAMESP_NAME ep |grep "$OLD_IP_FS:1"           
                     echo
                     echo "changing EPs"
                     read -p " Do you want to run a dry run (dry) of final changing run (final)? "  ACTION
                     if { [ "$ACTION" != "dry" ] &&  [ "$ACTION" != "final" ];} then
                           echo " did not get your choice ...... exit"
                           exit
                     fi
                     change_endpoints "$NS" "$OLD_IP_FS" "$NEW_IP_FS" "$ACTION"
                 fi 
     fi
    
fi
