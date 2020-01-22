#!/bin/bash

#/* CONST */
NODE_JS="Node.js"
GITHUB="module name"
APTSOURCE=""
NPMJS_URL="https://www.npmjs.com/package/"
GITHUB_URL="https://github.com"
#INPUT_FOLDER="input"
#SOURCE_FOLDER="source"
WORK_DIR=$(pwd)
LOG_DIR="${WORK_DIR}/logs"
RESULT_DIR="${WORK_DIR}/result"
SOURCE_DIR="${WORK_DIR}/source"
INPUT_DIR="${WORK_DIR}/input"
PREUPLOAD_DIR="${WORK_DIR}/pre-upload"
MODULE=""
MODULE_DIR=""
TYPE=""


#COPYRIGHT_PATTERN = 
LICENTSE_PATTERN=(*LI?EN?E* *COPYING* *COPYRIGHT*)


# Preparing the output file with format
# packageName,version,URL
# URL: null, github, downloadable (wget, curl, ...)
preload() {
    # generate standard format: Name | Version | URL

    # verify input pathfile to file in input folder
    if [ "$1" == "" ]; then
        echo "Please input pathfile"
        exit 1
    fi

    file_path=$1
    MODULE=$(basename ${file_path} | cut -d "." -f 1)
    MODULE_DIR="${PREUPLOAD_DIR}/${MODULE}"
    mkdir "$MODULE_DIR"
    output_file="${RESULT_DIR}/$(basename ${file_path})"

    # compare first line with pattern APTSOURCE, NPMJS_URL, GITHUB_URL
    #fisrtline=$(head -n 1 $file_path)
    if head -n 1 $file_path | grep -q "$NODE_JS"; then
        TYPE="NPM"
        while read -r line
        do
            arr=($line)
            checkout=0
            if echo "${arr[0]}" | grep -q "$NPMJS_URL"; then
                url=${arr[0]}
                package_name=$(echo "${arr[0]}" | sed "s#${NPMJS_URL}##g")
                version=$(echo "${arr[1]}" | sed 's/\^//g')
                check=1
            elif echo "${arr[1]}" | grep -q "$NPMJS_URL"; then
                package_name=${arr[0]}
                url=${arr[1]}
                version="NULL"
                check=1
            fi
            #Write Name Version URL into result/$file_path
            if [ "$package_name" != "" ] && [ "$check" == 1 ]; then
                if ! grep -Fxq "$package_name $version $url" "$output_file"; then
                    echo "$package_name $version $url" >> $output_file
                fi
            fi
        done < ${file_path}
    elif head -n 1 $file_path | grep -q "$GITHUB"; then
        TYPE="GIT"
        first="`head -n 1 $file_path`"
        while read -r line
        do
            if [ "$line" != "$first" ]; then
                arr=($line)
                check=0
                if echo "${arr[1]}" | grep -q "$GITHUB_URL"; then
                    url=${arr[1]}
                else
                    url="NULL"
                fi
                package_name=$(echo "${arr[0]}" | grep -o "^.*@"| sed 's/.\{1\}$//' | sed 's|\/|_|g')
                version=$(echo "${arr[0]}" | awk -F"@" '{print $NF}')
                check=1
                #Write Name Version URL into result/$file_path
                if [ "$package_name" != "" ] && [ "$check" == 1 ]; then
                    if grep -Fxq "$package_name $version $url" "$output_file"; then
                        echo "Existed line" 
                    else
                        echo "$package_name $version $url " >> $output_file
                    fi
                fi
            fi
        done < ${file_path}
    else
        TYPE="APT"
        #APT-GET SOURCE case
        while read -r line
        do
            arr=($line)
            url='NULL'
            if [ "${arr[0]}" == "ii" ]; then
                package_name=${arr[1]}
                version=${arr[2]}
            fi
            #Write Name Version URL into result/$file_path
            if [ "$package_name" != "" ] && [ "$version" != "" ]; then
                    if grep -Fxq "$package_name $version $url" "$output_file"; then
                        echo "Existed line" 
                    else               
                        echo "$package_name $version $url" >> $output_file
                    fi
            fi
            #echo "$package_name $version $url"
        done < ${file_path}
    fi
}
# Generate file .tgz import to Fossolosy
generateTAR(){
    dir=$1
    pkgtgz=$2
    listfile=""
    if echo "${package_name}" | grep -q "_"; then
        for i in "${LICENTSE_PATTERN[@]}"
        do
            tmp=`find $dir -maxdepth 1 -type f -iname   "$i"`
            listfile=`echo "$listfile $tmp"`
        done         
    else
        for i in "${LICENTSE_PATTERN[@]}"
        do
            tmp=`find $dir -type f -iname  "$i"`
            listfile=`echo "$listfile $tmp"`
        done
    fi
    if  echo "$listfile" | grep -q "$dir" ; then
        tar -zcf a.tgz $listfile
        mv a.tgz "${pkgtgz}.tgz"
        cp "$pkgtgz.tgz" ${MODULE_DIR}
        rm -f "$pkgtgz.tgz"
        if [ "$note" == "master" ] ; then
            output_log "$package_name $version $url    SUCCESS-master" "${LOG_DIR}/${MODULE}_report.log"
        else
            output_log "$package_name $version $url    SUCCESS" "${LOG_DIR}/${MODULE}_report.log"
        fi
        
    else
        mkdir -p ${LOG_DIR}/notfoundlicense
        tar -zcf a.tgz $dir
        mv a.tgz "${LOG_DIR}/notfoundlicense/${pkgtgz}.tgz"
        #cp -rf "${SOURCE_DIR}/$dir" "${LOG_DIR}/notfoundlicense"
        echo "[ERROR] $package_name $version $url not found LICENSE"  >> ${LOG_DIR}/${MODULE}_error.log
        echo "[ERROR] $package_name $version $url not found LICENSE"  >> ${LOG_DIR}/${MODULE}_license_error.log
        output_log "$package_name $version $url    not found LICENSE" "${LOG_DIR}/${MODULE}_report.log"
    fi

}

checkExistPkg() {
    pkgtgz="${1}_${2}"
    PKG=$(find ${PREUPLOAD_DIR} -name "${pkgtgz}.tgz")
    if [ "$PKG" != "" ]; then
        cp "$PKG" "${MODULE_DIR}"
        continue
    fi
}

downloadSourceByNpm() {
    cd $SOURCE_DIR
    while read -r line
    do
        arr=($line)
        # TYPE="${arr[3]}"
        #npm install
        echo "NPM"
        package_name=${arr[0]}
        version=${arr[1]}
        url=${arr[2]}
        package_name_new=$(echo "$package_name" | sed "s#/#-#g")
        # re-check with customer 
        if [ "$version" == "NULL" ]; then
            mkdir "$package_name_new"
            if ! npm v  $package_name dist.tarball | xargs curl | tar -xz -C $package_name_new; then
                rm -r $package_name_new
                output_log "[ERROR] Can not npm get source $package_name $version $url" ${LOG_DIR}/${MODULE}_error.log
                output_log "[ERROR] Can not npm get source $package_name $version $url" ${LOG_DIR}/${MODULE}_npm.log
                output_log "$package_name $version $url    Can not npm" "${LOG_DIR}/${MODULE}_report.log"
                continue
            fi
        else
            package_name_version="${package_name_new}_${version}"
            package_name_new="$package_name_version"
            mkdir "$package_name_version"
            if ! npm v  "$package_name@$version" dist.tarball | xargs curl | tar -xz -C $package_name_version; then
                echo "[ERROR] Can not npm get source $package_name $version $url" >> ${LOG_DIR}/${MODULE}_error.log
                echo "[ERROR] Can not npm get source $package_name $version $url" >> ${LOG_DIR}/${MODULE}_npm.log
                output_log "$package_name $version $url    Can not npm" "${LOG_DIR}/${MODULE}_report.log"
                rm -r $package_name_version
                continue
            fi
        fi
        #copy file to pre-upload
        cd "${SOURCE_DIR}/${package_name_new}"
        pkg=`ls`
        cd "${SOURCE_DIR}/${package_name_new}/${pkg}"
        cp -r * "${SOURCE_DIR}/${package_name_new}"
        cd "${SOURCE_DIR}/${package_name_new}"
        rm -r "$pkg"
        cd "${SOURCE_DIR}"
        ls $package_name_new
        generateTAR  $package_name_new  $package_name_new 
    done < $1
}

downloadSourceByGit() {
    #time=$(date +"%Y%m%d%H%M")
    # error_log_file="${LOG_DIR}/${MODULE}_report_$(date +"%Y%m%d%H%M").log"
    # echo "ERROR LOG FOR " > $error_log_file
    while read -r line
    do
        cd $SOURCE_DIR

        arr=($line)
        package_name=${arr[0]}
        version=${arr[1]}
        url=${arr[2]}
        note=""

        echo "===================${package_name} ${version}============================"

        if [ "$url" == "NULL" ]; then
            output_log "[ERROR] Can not clone $package_name $version $url" "${LOG_DIR}/${MODULE}_error.log"
            output_log "[ERROR] Can not clone $package_name $version $url" "${LOG_DIR}/${MODULE}_clone_error.log"
            output_log "$package_name $version $url    Can not clone" "${LOG_DIR}/${MODULE}_report.log"
            continue
        fi

        # check error 404
        if curl -L --head "$url" | grep "HTTP/1.1 404 Not Found" &> /dev/null; then
            output_log "[ERROR] 404 Can not clone $package_name $version $url" "${LOG_DIR}/${MODULE}_error.log"
            output_log "[ERROR] 404 Can not clone $package_name $version $url" "${LOG_DIR}/${MODULE}_clone_error.log"
            output_log "$package_name $version $url    Can not clone" "${LOG_DIR}/${MODULE}_report.log"
            continue
        fi

        # check package folder existed or not
        dir=$(basename "$url" .git)
        echo $url >> "${LOG_DIR}/${MODULE}/listurl.txt"
        dir_ver=$(echo $(basename "$url" .git)_${version})

        if ! git clone $url --branch $version; then
            if ! git clone $url --branch "v${version}" ; then
                if git clone $url ; then
                    cd $dir
                    if git tag | grep "$version" ; then
                        new_version=`git tag | grep "$version"`
                        if [ $(echo $new_version | wc -w ) == 1 ] ; then
                            git checkout $new_version
                        else
                            output_log "$package_name $version $url    check tags $new_version" "${LOG_DIR}/${MODULE}_checktags.log"
                            continue
                        fi
                    else
                        if  git checkout master ; then                           
                            output_log "$package_name $version $url    clone branch master" "${LOG_DIR}/${MODULE}_info.log"
                            note="master"
                        else
                            output_log "[ERROR] Can't checkout master $package_name $version $url" "${LOG_DIR}/${MODULE}_error.log"
                            output_log "[ERROR] Can't checkout master $package_name $version $url" "${LOG_DIR}/${MODULE}_notcheckoutmaster_error.log"
                            output_log "$package_name $version $url    Can not clone" "${LOG_DIR}/${MODULE}_report.log"
                            continue
                        fi
                    fi
                else
                    output_log "[ERROR] Can not clone $package_name $version $url" "${LOG_DIR}/${MODULE}_error.log"
                    output_log "[ERROR] Can not clone $package_name $version $url" "${LOG_DIR}/${MODULE}_clone_error.log"
                    output_log "$package_name $version $url    Can not clone" "${LOG_DIR}/${MODULE}_report.log"
                    continue
                fi
            fi
        fi


        #######################
        # if [ -d "$dir_ver" ];then
        #     cd $dir_ver
        #     if [ "$version" = "$(git describe --tags)" -o "v$version" = "$(git describe --tags)" ] ; then
        #         echo "[INFO] Existed a package name $package_name with same version $version" >> ${LOG_DIR}/${MODULE}_info.log
        #         pkgtgz="${package_name}_${version}"
        #         cd $SOURCE_DIR
        #         generateTAR $dir $pkgtgz
        #         continue
        #     fi
        #     echo "[INFO] Existed package name $package_name, checkout to version $version" >> ${LOG_DIR}/${MODULE}_info.log
        #     git pull
        #     if ! git checkout $version; then
        #         if ! git checkout "v${version}" ; then
        #             if ! git checkout master ; then
        #                 output_log "[ERROR] Can not clone $package_name $version $url" "${LOG_DIR}/${MODULE}_error.log"
        #                 output_log "[ERROR] Can not clone $package_name $version $url" "${LOG_DIR}/${MODULE}_clone_error.log"
        #                 output_log "$package_name $version $url    Can not clone" "${LOG_DIR}/${MODULE}_report.log"
        #                 continue
        #             else
        #                 output_log "$package_name $version $url    clone branch master" "${LOG_DIR}/${MODULE}_info.log"
        #                 note="master"
        #             fi
        #         fi
        #     fi
        # else
        #     if ! git clone $url --branch $version; then
        #         if ! git clone $url --branch "v${version}" ; then
        #             if ! git clone $url && ! git checkout master ; then
        #                 output_log "[ERROR] Can not clone $package_name $version $url" "${LOG_DIR}/${MODULE}_error.log"
        #                 output_log "[ERROR] Can not clone $package_name $version $url" "${LOG_DIR}/${MODULE}_clone_error.log"
        #                 output_log "$package_name $version $url    Can not clone" "${LOG_DIR}/${MODULE}_report.log"
        #                 continue
        #             else
        #                 output_log "$package_name $version $url    clone branch master" "${LOG_DIR}/${MODULE}_info.log"
        #                 note="master"
        #             fi 
        #         fi
        #     fi
        #fi
        cd $SOURCE_DIR

        mv $dir $dir_ver 

        #copy file to pre-upload/
        cd $SOURCE_DIR
        pkgtgz="${package_name}_${version}"
        generateTAR $dir_ver $pkgtgz
    done < $1
}

output_log() {
    echo "$1" >> "$2"
}

generate_Report() {
    list_pkg=`wc -l $output_file | cut -d " " -f 1`
    version_null=`grep -rn "NULL" $output_file | wc -l`
    tar_success=`ls $MODULE_DIR | wc -l | cut -d " " -f 1`
    can_not_get_source=`wc -l ${LOG_DIR}/${MODULE}_clone_error.log | cut -d " " -f 1`
    not_license=`wc -l ${LOG_DIR}/${MODULE}_license_error.log | cut -d " " -f 1`
    echo -e "Package:    ${list_pkg} \nVersion NULL:    ${version_null} \nSuccess:    ${tar_success} \nCan not get source:    ${can_not_get_source} \nNot license:    ${not_license}" > ${LOG_DIR}/${MODULE}_result.log
}
#main
for filename in `find $INPUT_DIR -type f`
do
    preload $filename
    output_file="${RESULT_DIR}/$(basename ${filename})"
    if [ "$TYPE" == "NPM" ]; then
        downloadSourceByNpm $output_file
        generate_Report
    elif [ "$TYPE" == "GIT" ]; then
        downloadSourceByGit $output_file
        generate_Report
    else
        downloadSourceByApt $output_file
    fi
done
