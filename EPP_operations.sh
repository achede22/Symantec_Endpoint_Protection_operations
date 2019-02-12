#!/bin/bash

LASTVERSION="14"
INSTALLERPATH="/var/chef/cache"
SYMANTECINSTALLERNAME="SymantecEndpointProtection"
JAVAVERSION="jdk1.8.0_151"


OPTION=$1
TARGETGROUP=$2
FILE_NAME=$3
CMDTARGETGROUP=$TARGETGROUP

KERNELPACKAGES="kernel-3.10.0-327.el7.x86_64 kernel-headers-3.10.0-327.el7.x86_64 kernel-tools-libs-3.10.0-327.el7.x86_64 kernel-tools-3.10.0-327.el7.x86_64"
SUPPORTEDKERNELS="2.6.32-504|3.10.0-123|3.10.0-327|3.10.0-229|2.6.32-642|2.6.32-573|2.6.32-504"


##Check if symantec is installed
check_symantec(){
  if [ -f /opt/Symantec/symantec_antivirus/sav ]; then
    echo "GLOBAL : Symantec is already installed, going to check versions"
    check_version
  else
    echo "GLOBAL : Symantec is not installed, going to configure and install"
    configure_symantec
    #download_symantec
  fi
}

##Check if version is last for AIP
check_version(){
  VERSION=$(/opt/Symantec/symantec_antivirus/sav info -p | awk '{print $1}')
  if [[ "$VERSION" == "$LASTVERSION" ]]; then
    echo "GLOBAL : Last Symantec Version installed. Release $LASTVERSION. Checking Setup used."
    check_proper_setup
  else
    echo "GLOBAL : Another Symantec Version installed, going to reinstall"
    uninstall_symantec
  fi
}

##Uninstall symantec
uninstall_symantec(){
  echo "UNINSTALL : Uninstalling Services"
  service symcfgd stop >/dev/null 2>&1 ##Stop all symantec process
  service rtvscand stop >/dev/null 2>&1 ##Stop all symantec process
  service autoprotect stop >/dev/null 2>&1 ##Stop all symantec process
  /opt/Symantec/symantec_antivirus/uninstall.sh -u >/dev/null 2>&1 ##Stop all symantec process
  echo "UNINSTALL : Cleaning up Directories"
  rm -rf /opt/Symantec >/dev/null 2>&1 ##Cleanup symantec dir
  rm -r /etc/Symantec.conf  >/dev/null 2>&1 ##Cleanup global symantec config
  rm -f /usr/local/etc/aipconfig/symantec.cfg  >/dev/null 2>&1
  echo "UNINSTALL : Clean complete. Please remove from EPP Console Previous to continue. If this step is missing node will be regenerate on same Target Group"
  #configure_symantec
  #download_symantec #Go to startup
}

install_symantec(){
  cd $INSTALLERPATH
  mkdir -p $SYMANTECINSTALLERNAME
  cp -p $FILE_NAME $SYMANTECINSTALLERNAME
  cd $SYMANTECINSTALLERNAME
  unzip -o $FILE_NAME >/dev/null 2>&1
  rm $FILE_NAME
  cd $INSTALLERPATH
  set_clienttargetgroup
  cd $SYMANTECINSTALLERNAME
  yum -y install kernel-devel-$(uname -r) bzip2 gcc glibc.i686
  echo "INSTALL : Starting Installation"
  bash -x install.sh -u >/dev/null 2>&1
  bash -x install.sh -i >/dev/null 2>&1
  copile_kernel
  checkpostinstall
}

copile_kernel(){
	cd $INSTALLERPATH/$SYMANTECINSTALLERNAME/src/ap-kernelmodule-14.0.2332-0100
	bash build.sh
}

checkpostinstall(){
  VERSION=$(/opt/Symantec/symantec_antivirus/sav info -p | awk '{print $1}')
  AUTOPROTECT=$(/opt/Symantec/symantec_antivirus/sav info -a | awk '{print $1}')
    if [[ "$VERSION" == "$LASTVERSION" ]]; then
      echo "COMPLETE : Last Symantec Version installed."
      if [[ "$AUTOPROTECT" == "Enabled" ]]; then
        echo "COMPLETE : Autoprotect module is on status enabled."
        #lockversion
        exit 0
      elif [[ "$AUTOPROTECT" == "Malfunctioning" ]]; then
        echo "COMPLETE : Autoprotect looks into malfunction status, probably require restart or update virus definitions"
        #lockversion
        exit 0
      else
        echo "WARNING : Autoprotect module seems invalid. Please restart. Status $AUTOPROTECT"
        shutdown -r +5 "AIP:
        System is going to be reboot due to Symantec update process.
        In case of any request or problem found after this reboot in
        the normal use of the system please contact:
        aip.support@accenture.com

        Regards,
        AIP Engineering Support"
        exit 0
      fi
    else
      echo "ERROR : Error during post instalation. Symantec release returns in error."
      exit 1
    fi

}

##Change TargetGroup
set_clienttargetgroup(){
  sed -i "s/AIP-DOCP/$TARGETGROUP/" $INSTALLERPATH/$SYMANTECINSTALLERNAME/Configuration/sylink.xml
  if [ $? -ne 0 ]; then
    echo "CONFIGURATION : Error during setup of Targetgroup on Configuration File"
    exit 1
  fi
}

##Check for proper setup for symantec
check_proper_setup(){
  if [ ! -f /usr/local/etc/aipconfig/symantec.cfg ]; then
    echo "CONFIGURATION : Creating Configuration File"
    echo "### BEGIN SYMANTEC OPTIONS
# TARGETGROUP=MYCLIENT                  : Set the client target group for new installatinos
# SYMANTECENABLE=yes                    : Set if symantec should be install or not
TARGETGROUP=$CMDTARGETGROUP
SYMANTECENABLE=yes
### END SYMANTEC OPTIONS" > /usr/local/etc/aipconfig/symantec.cfg
    echo "CONFIGURATION : Configuration mismatch. Going to remove. Please reinstall"
    uninstall_symantec ##Call to uninstall as current version were install from another way
    #install_symantec
  else ##Check if installation  is correct
    echo "CONFIGURATION : Using previous configuration file"
    source /usr/local/etc/aipconfig/symantec.cfg
    if [[ "$TARGETGROUP" != "$CMDTARGETGROUP" ]]; then ##Check if targetgroup from config match with the one from command line
      echo "CONFIGURATION : Target group differs. Need to uninstall"
      uninstall_symantec
      #install_symantec
    elif [[ "$SYMANTECENABLE" != "yes" ]]; then
      echo "CONFIGURATION : Symantec requested to be disable per command line config"
      uninstall_symantec
    else
      echo "COMPLETE : Not going to do any, all seems ok"
      echo "COMPLETE : Current version does not verify for malfunction of services"
    fi
  fi
}

##Download symantec
#download_symantec(){
#  DOWNLOADFILE="RHEL_Symantec_$LASTVERSION.zip"
#  curl -O https://s3.amazonaws.com/software-installable-bin/EPP_Linux/$DOWNLOADFILE > /dev/null 2>&1
#    if [ $? -ne 0 ]; then
#      echo "Canceling as download of last symantec fail"
#      exit 1
#    else
#      uncompress_symantec $DOWNLOADFILE
#    fi
#}

##Uncompress symantec
#uncompress_symantec(){
#DOWNLOADFILE=$1
#  unzip -o $DOWNLOADFILE >/dev/null 2>&1
#    if [ $? -ne 0 ]; then
#      echo "Canceling as cannot uncompress symantec"
#      exit 1
#    else
#      configure_symantec
#    fi
#}

##Do initial configuration for symantec
configure_symantec(){
  mkdir -p /opt/Symantec
  touch /etc/Symantec.conf
  echo "[Symantec Shared]" > /etc/Symantec.conf
  echo "BaseDir=/opt/Symantec" >> /etc/Symantec.conf
  #echo "JAVA_HOME=/opt/Symantec/$JAVAVERSION/jre/bin/" >> /etc/Symantec.conf
}

##Copy java
copyjava(){
  cd $INSTALLERPATH
  unzip -o $JAVAVERSION.zip >/dev/null 2>&1
  if [ ! -f /opt/Symantec/$JAVAVERSION ]; then
    cp -rp $INSTALLERPATH/$JAVAVERSION /opt/Symantec/
	chmod +x /opt/Symantec/$JAVAVERSION/jre/bin/java
    if [ $? -ne 0 ]; then
      echo "INSTALL : Incorrect copy for java on Symantec dir"
      exit 1
    else
      echo "INSTALL : Java were copy to symantec directory"
    fi
  fi
}

##Check that kernel version matchs
check_kernel_version(){
  CURRENTVERSION=$(uname -r | sed 's/.el7.x86_64//' | sed 's/.el6.x86_64//') ##Remove release versions
  ISLASTSUPPORTED=$(echo $CURRENTVERSION | egrep  "$SUPPORTEDKERNELS")
  if [[ "$ISLASTSUPPORTED" == "" ]]; then ##If version is not supported
    remove_supplementary_kernel_packages
    install_correctkernel_version ##Install proper kernel
    echo "KERNEL CONFIG : In order to proceed it's require to restart"
    shutdown -r +5 "AIP:
    System is going to be reboot due to kernel update process.
    In case of any request or problem found after this reboot in
    the normal use of the system please contact:
    aip.support@accenture.com

    Regards,
    AIP Engineering Support"
    exit 0
  else
    install_correctkernel_version
  fi
}

##Remove supplementary kernel packages
remove_supplementary_kernel_packages(){
  for i in $(rpm -qa | grep kernel- | egrep -v "$SUPPORTEDKERNELS"); do ##Loop into any kernel that is not supported
    echo "PACKAGE : Removing $i"
    sleep 1
    rpm -e $i >/dev/null 2>&1 ##Remove each kernel package that is not supported, avoiding errors
  done
}

##Install correct kernel verion. only for el7 yet
install_correctkernel_version(){
  for i in $KERNELPACKAGES; do
    ISINSTALL=$(rpm -q $i | grep "is not installed") ##Filter to see if package is not installed
    if [[ "$ISINSTALL" != "" ]]; then #If string is not null assume its not install per rpm query
      yum install -y $i >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        echo "ERROR: Error during installation of $i"
      else
        echo "KERNEL CONFIG : Package $i installed"
      fi
    fi
  done
}

##Lock kernel version ##Should also review on grub config file that it-s properly set
lockversion(){
    echo "KERNEL CONFIG : Setting Version lock for kernel packages"
    yum versionlock kernel-3.10.0-327.el7 >/dev/null 2>&1
    yum versionlock kernel-headers-3.10.0-327.el7.x86_64 >/dev/null 2>&1
    yum versionlock kernel-tools-3.10.0-327.el7.x86_64 >/dev/null 2>&1
    yum versionlock kernel-tools-libs-3.10.0-327.el7.x86_64 >/dev/null 2>&1
}

help(){
  echo "Incorrect usage. Please correct:
  $0 --forceinstall <TARGETGROUP> <FILE_NAME>     : Force install
  $0 --install <TARGETGROUP> <FILE_NAME>          : Install
  $0 --uninstall                                  : Uninstall complete
  $0 --lockversions                               : Lock Kernel Verrsions
  "
}

###########################################
## BEGIN
###########################################

if [ $# -eq 3 ]; then
  if [[ "$1" == "--forceinstall" ]]; then
    rm -f /usr/local/etc/aipconfig/symantec.cfg  >/dev/null 2>&1
    check_proper_setup
    #check_kernel_version
    #install_correctkernel_version
    #remove_supplementary_kernel_packages
    configure_symantec
    #copyjava
    install_symantec
  elif [[ "$1" == "--install" ]]; then
    #check_kernel_version
    #install_correctkernel_version
    #remove_supplementary_kernel_packages
    configure_symantec
    #copyjava
    install_symantec
  else
    help
  fi
elif [ $# -eq 1 ]; then
  if [[ "$1" == "--uninstall" ]]; then
    uninstall_symantec
  elif [[ "$1" == "--setproperkernel" ]]; then
    install_correctkernel_version
    remove_supplementary_kernel_packages
  elif [[ "$1" == "--lockversions" ]]; then
    lockversion
  else
    echo "Incorrect first option"
    help
  fi
else
 help
fi

