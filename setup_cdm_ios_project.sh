#!/bin/bash

###
### Shell script intended for external partners to run that will download
### and setup the iOS CDM Reference project using OEMCrypto TFIT Dylib.
###

set -e

# Only support OSX
if [[ "$OSTYPE" != "darwin"* ]]; then
  echo "Only OSX is supported."
  exit 1
fi

# Check input args
while (($#)); do
  ## Looks for matching string in args and strips remaining text
  if [[ $1 == --oec_url* ]]; then
    OEC_URL=${1:10}
  fi
  shift
done

# Static Links to download external projects
COCOAHTTP_URL="https://github.com/robbiehanson/CocoaHTTPServer/archive/master.zip"
TBXML_URL="https://github.com/71squared/TBXML/archive/master.zip"

echo
echo

#########################
# Start of Function declarations. (Alphabetical)

# Check if folder has already been created (skip extraction).
check_folder() {
  if [ "${1:0:9}" == "oemcrypto" ]; then
    FOLDER=${1:0:24}
    TAR_PARAM="--strip-components=1"
  else
    FOLDER=${1}
  fi
  if [ -d ${FOLDER} ] || [ -d ${FOLDER}-master ]; then
    read -p  "Directory Already Created, extract again? [y/n] " y
    case $y in
      [Yy]* ) extract_file ${1} ${2} ${FOLDER} ${TAR_PARAM};;
      * ) echo "Using existing folder. Continuing...";;
    esac
  else
    extract_file ${1} ${2} ${FOLDER} ${TAR_PARAM}
  fi
}

# Look for folder, if not found, download using provided link.
download_file() {
  if [ -f ${1} ]; then
    echo "File Already Downloaded, Extracting..."
  else
     curl -L -o ${1} ${2}
  fi
}

# Using tar or zip to extract packages based on extension.
extract_file() {
  if [ ${2} == "zip" ]; then
    unzip ${1}.zip
  else
    mkdir -p ${3}
    tar -pxzvf ${1}.${2} -C ${3} ${4}
    echo "${3} Extracted."
  fi
}

# Check if files exist or if they need to be downloaded.
find_files() {
  FOLDER=`find . -type d -name "*${1}*" -maxdepth 1 | sed 's|./||'`
  FILES="$(find . -type f -name "*${1}*" -maxdepth 1 | sed 's|./||')"
  if [ -n "${FOLDER}" ]; then
    if [ "${FOLDER}" == "${1}" ]; then
      echo "$FOLDER already extracted. Continuing..."
    else
      echo "Folder Found: Renaming ${FOLDER} to ${1}."
      mv -f ${FOLDER} ${1}
    fi
  elif [ -n "${FILES}" ]; then
    for file in ${FILES}
    do
      if [ "${file: -7:4}" == ".tar" ]; then
        check_folder ${file%.*.*} tar.gz
      else
        echo "File is not an archive, expected tar. Exiting."
        break
      fi
    done
  fi
}

# Determine if files exists or need to be downloaded. Provide prompts to user.
handle_files() {
  if [ -n "${3}" ]; then
    echo "${1} Ready"
  else
    echo "${1} File or Folder was NOT Found."
    if [ -n "${2}" ]; then
      echo "Download Link: ${2}"
      download_file ${1}.tar.gz ${2}
    else
      read -p "Would you like to download and extract the ${1}? [y/n] " yn
      case $yn in
        [Yy]* ) read -p "Please paste the ${1} Download link: ";
          echo "Downloading Link: ${REPLY}";
          if [[ "${REPLY}" =~ ".tar." ]]; then
            download_file ${1}.tar.gz ${REPLY}
          else
            echo "Expecting tar file, exiting."
            break;
          fi
          find_files ${1};;
        [Nn]* ) echo "Please download the URL manually and re-run."; break;;
        * ) echo "Please answer yes or no.";;
      esac
    fi
  fi

}

# Checks that the file download correctly.
verify_download() {
  if [ -f ${1} ]; then
    echo "Download Completed Successfully."
  else
    echo "=============================================================="
    echo "Download Failed."
    echo "Try downloading the file manually and store in template folder."
    echo "And run the script again."
    echo "=============================================================="
    exit 1
  fi
}

#########################
# Script Start

TBXML="TBXML"
echo "=============================================================="
echo "          Preparing ${TBXML} ... [4/5]"
echo "=============================================================="
download_file ${TBXML}.zip ${TBXML_URL}
extract_file ${TBXML} zip

COCOAHTTP="CocoaHTTPServer"
echo "=============================================================="
echo "          Preparing ${COCOAHTTP} ... [5/5]"
echo "=============================================================="
download_file ${COCOAHTTP}.zip ${COCOAHTTP_URL}
extract_file ${COCOAHTTP} zip

echo "=============================================================="
echo "          Setup Complete."
echo "=============================================================="

if [ -d "/Applications/XCode.app" ]; then
  echo
  read -p "Open XCode Project? [y/n] " y
  echo
  case $y in
    [Yy]* ) open cdm_player_ios.xcodeproj;;
    * ) echo "Install Complete. Open Project: cdm_player_ios.xcodeproj";;
 esac
 else
   echo "XCode was not detected, unable to open automatically."
fi

