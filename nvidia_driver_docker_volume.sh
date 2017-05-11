#!/usr/bin/env bash
#
# Create NVIDIA driver docker volume.

set -e

VOLUME_ROOT="$HOME/.nvidia_docker/volume"
VOLUME_NAME="nvidia_driver"
MOUNT_POINT="/usr/local/nvidia"
MOUNT_OPTIONS="ro"

BIN_DIR="bin"
LIB32_DIR="lib"
LIB64_DIR="lib64"

lib32_files=()
lib64_files=()

NV_BINARIES=(
    # "nvidia-modprobe"       # Kernel module loader
    # "nvidia-settings"       # X server settings
    # "nvidia-xconfig"        # X xorg.conf editor
    "nvidia-cuda-mps-control" # Multi process service CLI
    "nvidia-cuda-mps-server"  # Multi process service server
    "nvidia-debugdump"        # GPU coredump utility
    "nvidia-persistenced"     # Persistence mode utility
    "nvidia-smi"              # System management interface
)

NV_LIBRARIES=(
    # ------- X11 -------

    #"libnvidia-cfg.so"  # GPU configuration (used by nvidia-xconfig)
    #"libnvidia-gtk2.so" # GTK2 (used by nvidia-settings)
    #"libnvidia-gtk3.so" # GTK3 (used by nvidia-settings)
    #"libnvidia-wfb.so"  # Wrapped software rendering module for X server
    #"libglx.so"         # GLX extension module for X server

    # ----- Compute -----

    "libnvidia-ml.so"              # Management library
    "libcuda.so"                   # CUDA driver library
    "libnvidia-ptxjitcompiler.so"  # PTX-SASS JIT compiler (used by libcuda)
    "libnvidia-fatbinaryloader.so" # fatbin loader (used by libcuda)
    "libnvidia-opencl.so"          # NVIDIA OpenCL ICD
    "libnvidia-compiler.so"        # NVVM-PTX compiler for OpenCL (used by libnvidia-opencl)
    #"libOpenCL.so"               # OpenCL ICD loader

    # ------ Video ------

    "libvdpau_nvidia.so"  # NVIDIA VDPAU ICD
    "libnvidia-encode.so" # Video encoder
    "libnvcuvid.so"       # Video decoder
    "libnvidia-fbc.so"    # Framebuffer capture
    "libnvidia-ifr.so"    # OpenGL framebuffer capture

    # ----- Graphic -----

    # XXX In an ideal world we would only mount nvidia_* vendor specific libraries and
    # install ICD loaders inside the container. However, for backward compatibility reason
    # we need to mount everything. This will hopefully change once GLVND is well established.

    "libGL.so"         # OpenGL/GLX legacy _or_ compatibility wrapper (GLVND)
    "libGLX.so"        # GLX ICD loader (GLVND)
    "libOpenGL.so"     # OpenGL ICD loader (GLVND)
    "libGLESv1_CM.so"  # OpenGL ES v1 common profile legacy _or_ ICD loader (GLVND)
    "libGLESv2.so"     # OpenGL ES v2 legacy _or_ ICD loader (GLVND)
    "libEGL.so"        # EGL ICD loader
    "libGLdispatch.so" # OpenGL dispatch (GLVND) (used by libOpenGL, libEGL and libGLES*)

    "libGLX_nvidia.so"         # OpenGL/GLX ICD (GLVND)
    "libEGL_nvidia.so"         # EGL ICD (GLVND)
    "libGLESv2_nvidia.so"      # OpenGL ES v2 ICD (GLVND)
    "libGLESv1_CM_nvidia.so"   # OpenGL ES v1 common profile ICD (GLVND)
    "libnvidia-eglcore.so"     # EGL core (used by libGLES* or libGLES*_nvidia and libEGL_nvidia)
    "libnvidia-egl-wayland.so" # EGL wayland extensions (used by libEGL_nvidia)
    "libnvidia-glcore.so"      # OpenGL core (used by libGL or libGLX_nvidia)
    "libnvidia-tls.so"         # Thread local storage (used by libGL or libGLX_nvidia)
    "libnvidia-glsi.so"        # OpenGL system interaction (used by libEGL_nvidia)
)


##############################################################################
# Nvidia

nvidia::init() {
    export CUDA_DISABLE_UNIFIED_MEMORY=1
    export CUDA_CACHE_DISABLE=1
    unset CUDA_VISIBLE_DEVICES
}

nvidia::driver_version() {
    local v
    v="$(nvidia-smi --query-gpu=driver_version --format="csv,noheader" | head -1)"
    echo $v
}

nvidia::load_uvm() {
    nvidia-modprobe -u -c=0
}

nvidia::device_count() {
    local c
    c="$(nvidia-smi --query-gpu=count --format="csv,noheader" | head -1)"
    echo $c
}

nvidia::control_device_paths() {
    NV_CTL_DEVICES=("/dev/nvidiactl" "/dev/nvidia-uvm")

    if [[ -e "/dev/nvidia-uvm-tools" ]]; then
        NV_CTL_DEVICES+=("/dev/nvidia-uvm-tools")
    fi
}

nvidia::device_paths() {
    NV_DEVICES=()
    local da=$(nvidia-smi --query-gpu=index --format="csv,noheader")
    for i in ${da[@]}; do
        local device="/dev/nvidia$i"
        if [[ -e "$device" ]]; then
            NV_DEVICES+=("$device")
        fi
    done
}

nvidia::debug_info() {
    nvidia::device_paths
    nvidia::control_device_paths

    for i in ${NV_DEVICES[@]}; do
        echo $i ...
    done

    for i in ${NV_CTL_DEVICES[@]}; do
        echo $i ---
    done
}

##############################################################################
# CUDA

cuda::driver_version() {
    local v
    v="$(nvcc --version | grep "release" | awk '{print $5}' | cut -d',' -f1 2>/dev/null)"
    echo $v
}

##############################################################################
# Volume

volume::path() {
    local nv_version
    if [[ -n "$1" ]]; then
        nv_version="$1"
    else
        nv_version=$(nvidia::driver_version)
    fi

    echo "$VOLUME_ROOT/$VOLUME_NAME/$nv_version"
}

volume::clone_binaries() {
    local vpath="$1"
    local bpath="$vpath/$BIN_DIR"

    [[  -d "$bpath" ]] || mkdir -p $bpath

    local i
    for i in ${NV_BINARIES[@]}; do
        local b=$(which $i)
        if [[ -e "$b" ]]; then
            cp -f $b $bpath/$i
        fi
    done
}

volume::lookup_lib32() {
    local lib="$1"
    local l32=$(ldconfig -p | grep -v "x86-64" | grep "$lib" | awk -F' => ' '{print $2}' 2>/dev/null)
    for i in ${l32[@]}; do
        local l="$i"
        if [[ -n "$l" ]]; then
            local real_l32=$(readlink -f $l 2>/dev/null)
            if [[ -n "$real_l32" && -z "$(echo "${lib32_files[*]}" | grep $real_l32 2>/dev/null)" ]]; then
                lib32_files+=( $real_l32 )
            fi
        fi
    done
}

volume::lookup_lib64() {
    local lib="$1"
    local l64=$(ldconfig -p | grep "x86-64" | grep "$lib" | awk -F' => ' '{print $2}' 2>/dev/null)
    for i in ${l64[@]}; do
        local l="$i"
        if [[ -n "$l" ]]; then
            local real_l64=$(readlink -f $l 2>/dev/null)
            if [[ -n "$real_l64" && -z "$(echo "${lib64_files[*]}" | grep $real_l64 2>/dev/null)" ]]; then
                lib64_files+=( $real_l64 )
            fi
        fi
    done
}

volume::show_lib_files() {
    echo "===> lib32"
    for i in ${lib32_files[@]}; do
        echo $i
    done

    echo "===> lib64"

    for i in ${lib64_files[@]}; do
        echo $i
    done
}

volume::blacklisted() {
    local l="$1"
    lib_regex='^.*/lib([A-Za-z0-9_-]+)\.so[0-9.]*$'
    glcore_regex='libnvidia-e?glcore\.so'
    gldispatch='libGLdispatch\.so'

    if [[ "$l" =~ $lib_regex ]]; then
        local m1="${BASH_REMATCH[1]}"

        case $m1 in
            # Blacklist EGL/OpenGL libraries issued by other vendors
            EGL|GLESv1_CM|GLESv2|GL)
                local deps=$(objdump -p $l | grep "NEEDED" | awk '{print $2} 2>/dev/null')
                for i in ${deps[@]}; do
                    local d="$i"
                    if [[ "$d" =~ $glcore_regex || "$d" =~ $gldispatch ]]; then
                        return 1
                    fi
                done

                return 0
                ;;
            # Blacklist TLS libraries using the old ABI (!= 2.3.99)
            nvidia-tls)
                local abi="$(readelf -n $l | grep "ABI:" | awk '{print $4}' 2>/dev/null)"
                if [[ "$abi" != "2.3.99" ]]; then
                    return 1
                else
                    return 0
                fi
                ;;
        esac
    fi

    return 1
}

volume::clone_lib() {
    local l="$1"
    local lpath="$2"
    local bname="$(basename $l)"

    if volume::blacklisted "$l"; then
        return
    fi

    cp -f $l $lpath/$bname

    local soname="$(objdump -p $l | grep "SONAME" | awk '{print $2}')"
    ln -s $bname $lpath/$soname 2>/dev/null || true

    # If the soname start with libcuda then remove the end number
    # Eg. libcudaxxx.so.1  -> libcudaxxx.so
    if [[ -n "$(echo $soname | grep '^libcuda')" ]]; then
        soname="$(echo $soname | sed 's/\(.*\)[.][0-9]/\1/' )"
        ln -s $bname $lpath/$soname 2>/dev/null || true
    fi

    # If the soname start with libGLX_nvidia, use the GLX_indirect instead of GLX_nvidia
    if [[ -n "$(echo $soname | grep '^libGLX_nvidia')" ]]; then
        soname="$(echo $soname | sed 's/GLX_nvidia/GLX_indirect/' )"
        ln -s $bname $lpath/$soname 2>/dev/null || true
    fi
}

volume::clone_libraries() {
    local vpath="$1"
    local l32path="$vpath/$LIB32_DIR"
    local l64path="$vpath/$LIB64_DIR"

    [[ -d "$l32path" ]] || mkdir -p $l32path
    [[ -d "$l64path" ]] || mkdir -p $l64path

    for i in ${NV_LIBRARIES[@]}; do
        local l="$i"
        volume::lookup_lib32 "$l"
        volume::lookup_lib64 "$l"
    done

    # lib32
    for i in ${lib32_files[@]}; do
        local l="$i"
        volume::clone_lib "$l" "$l32path"
    done

    # lib64
    for i in ${lib64_files[@]}; do
        local l="$i"
        volume::clone_lib "$l" "$l64path"
    done
}

volume::create() {
    local vpath=$(volume::path)
    [[ -d $vpath ]] || mkdir -p $vpath

    volume::clone_binaries "$vpath"
    volume::clone_libraries "$vpath"
}

volume::exist() {
    local vpath=$(volume::path)
    [[ -d "$vpath" ]]
}

volume::clean() {
    if [[ -d "$VOLUME_ROOT" ]]; then
        echo "Deleting $VOLUME_ROOT ..."
        rm -rf $VOLUME_ROOT
    fi
}

volume::remove() {
    if [[ -z "$1" ]]; then
        return
    fi

    vpath=$(volume::path "$1")

    if [[ -d "$vpath" ]]; then
        echo "Deleting $vpath ..."
        rm -rf $vpath
    fi
}


##############################################################################
# Docker

docker::device_opts() {
    nvidia::device_paths
    nvidia::control_device_paths
    local dstr
    for d in ${NV_DEVICES[@]} ${NV_CTL_DEVICES[@]}; do
        dstr="$dstr --device=$d"
    done

    echo $dstr
}

docker::volume_opts() {
    local vstr
    local vpath
    vpath=$(volume::path)
    vstr="--volume=$vpath:$MOUNT_POINT:$MOUNT_OPTIONS"

    echo $vstr
}

docker::opts() {
    local device_opts=$(docker::device_opts)
    local volume_opts=$(docker::volume_opts)

    echo "$device_opts $volume_opts"
}

##############################################################################
# Main

f_force=false
f_remove=false
while getopts ":fr" opt; do
    case $opt in
        f)
            f_force=true
            ;;
        r)
            f_remove=true
            ;;
        \?)
            help
            ;;
    esac
done

if [[ "$f_remove" == "true" ]]; then
    volume::clean
    exit
fi

if [[ "$f_force" == "true" ]] || ! volume::exist; then
    nvidia::init
    volume::create
fi

docker::opts
