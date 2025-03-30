#!/bin/bash
# (c) Joey Rizzoli, 2015
# (c) Paul Keith, 2017
# Released under GPL v2 License

##
# var
#
DATE=$(date -u +%Y%m%d)
export GAPPS_TOP=$(realpath .)
ANDROIDV=$1
SDKV=$2
GARCH=$3
CPUARCH=$GARCH
[ ! -z "$2" ] && CPUARCH=$2
OUT=$GAPPS_TOP/out
BUILD=$GAPPS_TOP/build
METAINF=$BUILD/meta
COMMON=$GAPPS_TOP/common/proprietary
export GLOG=$GAPPS_TOP/gapps_log
ADDOND=$GAPPS_TOP/addond.sh

SIGNAPK=$GAPPS_TOP/build/sign/signapk.jar
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$GAPPS_TOP/build/sign

ZIP_KEY_PK8=$GAPPS_TOP/build/sign/testkey.pk8
ZIP_KEY_PEM=$GAPPS_TOP/build/sign/testkey.x509.pem

##
# functions
#
function clean() {
    echo "Cleaning up..."
    rm -r $OUT/$GARCH
    rm /tmp/$BUILDZIP
    return $?
}

function failed() {
    echo "Build failed, check $GLOG"
    exit 1
}

function overlay() {
    mkdir -pv common/proprietary/product/overlay
    echo "Compiling RROs"
    export PATH="$ANDROID_HOME/build-tools/36.0.0:$PATH"
    cp -vf build/sign/testkey.pk8 cert.pk8
    find overlay -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d '' dir; do
        echo "Building ${dir/overlay\//}"
        aapt p -M "$dir"/AndroidManifest.xml -S "$dir"/res/ -I $ANDROID_HOME/platforms/android-$SDKV/android.jar --min-sdk-version $SDKV --target-sdk-version $SDKV -F "${dir/overlay\//}"-unaligned.apk
        zipalign -pvf 4 "${dir/overlay\//}"-unaligned.apk "${dir/overlay\//}".apk
        apksigner sign --key cert.pk8 --cert build/sign/testkey.x509.pem "${dir/overlay\//}".apk
        mv -vf "${dir/overlay\//}".apk common/proprietary/product/overlay/
    done
    return 0;
}

function create() {
    test -f $GLOG && rm -f $GLOG
    echo "Starting GApps compilation" > $GLOG
    PREBUILT=$GAPPS_TOP/$GARCH/proprietary
    test -d $OUT || mkdir -pv $OUT;
    test -d $OUT/$GARCH || mkdir -pv $OUT/$GARCH
    test -d $OUT/$GARCH/system || mkdir -pv $OUT/$GARCH/system
    echo "Build directories are now ready" >> $GLOG
    echo "Getting prebuilts..."
    echo "Copying stuff" >> $GLOG
    cp -vf $GAPPS_TOP/toybox-$GARCH $OUT/$GARCH/toybox >> $GLOG
    cp -rvf $PREBUILT/* $OUT/$GARCH/system >> $GLOG
    cp -rvf $COMMON/* $OUT/$GARCH/system >> $GLOG
    echo "Generating addon.d script" >> $GLOG
    test -d $OUT/$GARCH/system/addon.d || mkdir -pv $OUT/$GARCH/system/addon.d
    cp -vf addond_head $OUT/$GARCH/system/addon.d
    cp -vf addond_tail $OUT/$GARCH/system/addon.d
    echo "Writing build props..."
    echo "arch=$CPUARCH" > $OUT/$GARCH/build.prop
    echo "version=$SDKV" >> $OUT/$GARCH/build.prop
    echo "version_nice=$ANDROIDV" >> $OUT/$GARCH/build.prop
}

function zipit() {
    BUILDZIP=MindTheGapps-$ANDROIDV-$GARCH-$DATE.zip
    echo "Importing installation scripts..."
    test -d $OUT/$GARCH/META-INF || mkdir -pv $OUT/$GARCH/META-INF;
    cp -rvf $METAINF/* $OUT/$GARCH/META-INF/ && echo "Meta copied" >> $GLOG
    echo "Creating package..."
    cd $OUT/$GARCH
    find -exec touch -amt 200901010000.00 {} \;
    zip -r /tmp/$BUILDZIP . >> $GLOG
    rm -rvf $OUT/tmp >> $GLOG
    cd $GAPPS_TOP
    if [ -f /tmp/$BUILDZIP ]; then
        echo "Signing zip..."
        apksigner sign --cert $ZIP_KEY_PEM --key $GAPPS_TOP/cert.pk8 --min-sdk-version 28 /tmp/$BUILDZIP
        cp -vf /tmp/$BUILDZIP $OUT/$BUILDZIP
    else
        echo "Couldn't zip files!"
        echo "Couldn't find unsigned zip file, aborting" >> $GLOG
        return 1
    fi
}

function getsha256() {
    if [ -x $(which sha256sum) ]; then
        echo "sha256sum is installed, getting sha256..." >> $GLOG
        echo "Getting sha256sum..."
        GSHA256=$(sha256sum $OUT/$BUILDZIP | cut -c-64)
        echo -e "$GSHA256" > $OUT/$BUILDZIP.sha256sum
        echo "sha256 exported at $OUT/$BUILDZIP.sha256sum"
        return 0
    else
        echo "sha256sum is not installed, aborting" >> $GLOG
        return 1
    fi
}

##
# main
#
if [ -x $(which realpath) ]; then
    echo "Realpath found!" >> $GLOG
else
    GAPPS_TOP=$(cd . && pwd) # some darwin love
    echo "No realpath found!" >> $GLOG
fi

for func in overlay create zipit getsha256 clean; do
    $func
    ret=$?
    if [ "$ret" == 0 ]; then
        continue
    else
        failed
    fi
done

echo "Done!" >> $GLOG
echo "Build completed: $BUILDZIP"
exit 0
