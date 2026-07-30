#!/bin/bash -x
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear

echo "This is testing script for applying patches" >&2

CUSTOM_PATCH_DIR="$1"
MODE="$2"
WORK=$(pwd)

scripts_dir="${CUSTOM_PATCH_DIR}/../../../scripts"
patches_dir="${CUSTOM_PATCH_DIR}"

get_paths_from_patches() {

    prjs_with_patches="$(dirname $(find $patches_dir -name "*.patch") | sort -u | sed "s,$patches_dir/,,g" | xargs)"
    echo "$prjs_with_patches"
}

find_appliable_patches() {

    local patch_dir="$1"
    local prj_dir="$2"

    PRJ_PATCHES="$(ls ${patch_dir}/${prj_dir}/*.patch)"
    for prj_patch in $PRJ_PATCHES
    do
        git -C ${prj_dir} apply --check ${patch_dir}/${$prj_dir}/${prj_patch}
    done
}

try_and_apply() {

    local patch_dir="$1"
    local prj_dir="$2"

    VAR_PRJ="$(echo $prj_dir | sed 's,/,__,g')"
    TOP_COMMIT="$(git -C ${prj_dir} rev-parse HEAD)"
    echo "===Project: $prj_dir == Top commit: $TOP_COMMIT===" >&2

    PRJ_PATCHES="$(ls ${patch_dir}/${prj_dir}/*.patch)"
    ${VAR_PRJ}_total="$(ls ${patch_dir}/${prj_dir}/*.patch | wc -l)"
    ${VAR_PRJ}_success=0
    ${VAR_PRJ}_fail=0
    for prj_patch in $PRJ_PATCHES
    do
        git -C ${prj_dir} apply --check ${patch_dir}/${prj_dir}/${prj_patch}
        if [ $? -eq 0 ]; then
             git -C ${prj_dir} am ${patch_dir}/${prj_dir}/${prj_patch}
             echo "${patch_dir}/${$prj_dir}/${prj_patch} -- Success" >&2 
             FAIL=0
        else
             FAIL=1
             echo "${patch_dir}/${$prj_dir}/${prj_patch} -- Failed" >&2
        fi
        if [ $FAIL -eq 0 ]; then
             ${VAR_PRJ}_success=$(expr ${${prj_dir}_success} + 1)
        else
             ${VAR_PRJ}_fail=$(expr ${${prj_dir}_fail} + 1)
        fi
    done

}

apply_patches() {

    local patch_dir="$1"
    local prj_dir="$2"

    FAIL=0
    TOP_COMMIT="$(git -C ${prj_dir} rev-parse HEAD)"
    echo "===Project: $prj_dir == Top commit: $TOP_COMMIT===" >&2
    if [[ "$prj_dir" == "kernel/msm-5.4" ]]; then
         git -C ${prj_dir} checkout HEAD -- gen_headers_arm64.bp gen_headers_arm.bp >&2
    fi
    if [[ "$prj_dir" == "device/qcom/msmnile_gvmq" ]]; then
         git -C ${prj_dir} checkout HEAD -- system.prop >&2
    fi

    git -C ${prj_dir} am -3 ${WORK}/${patch_dir}/${prj_dir}/*.patch >&2
    if [ $? -ne 0 ]; then
         git -C ${prj_dir} am --abort
         FAIL=1
    fi
}

if [ "$MODE" == "apply" ]; then
    if [ ! -f ${CUSTOM_PATCH_DIR}/patch_applied ]; then
     echo 0 > ${CUSTOM_PATCH_DIR}/apply_status

     cd $WORK

     prjs_patch_dirs="$(get_paths_from_patches)"
     declare -A project_top_commit

     for prj_dir in $prjs_patch_dirs
     do
        if [ ! -e "$prj_dir" ]; then
             continue
        fi
        RESET_PRJS="$RESET_PRJS $prj_dir"
        project_top_commit["$prj_dir"]="$(git -C ${prj_dir} rev-parse HEAD)"
        apply_patches $patches_dir $prj_dir
        if [ $FAIL -eq 1 ]; then
            break
        fi
     done

     if [ $FAIL -eq 1 ]; then
        for reset_prj in $RESET_PRJS
        do
            COMMIT="${project_top_commit["$reset_prj"]}"
            git -C ${reset_prj} reset --hard $COMMIT
        done
        echo $FAIL > ${CUSTOM_PATCH_DIR}/apply_status
        exit $FAIL
      fi

      if [ $FAIL -eq 0 ]; then
           for reset_prj in $RESET_PRJS
           do
              COMMIT="${project_top_commit["$reset_prj"]}"
              echo "${reset_prj}:${COMMIT}" >> ${CUSTOM_PATCH_DIR}/previous_tip_revs
           done
       touch ${CUSTOM_PATCH_DIR}/patch_applied
      fi
    else
      echo "**********Patches already applied*************"
    fi
elif [ "$MODE" == "clean" ]; then
      RESET_BACK="${CUSTOM_PATCH_DIR}/previous_tip_revs"
      for prj_rev in $(cat ${CUSTOM_PATCH_DIR}/previous_tip_revs)
      do
          PRJ="$(echo $prj_rev | awk -F':' {'print $1'})"
          REV="$(echo $prj_rev | awk -F':' {'print $2'})"
          echo "Resetting  $PRJ with $REV" >&2
          git -C $PRJ reset --hard $REV
      done
      rm ${CUSTOM_PATCH_DIR}/patch_applied
fi
