#!/bin/bash
set -x

# 设置benchmark参数，默认为gcc
benchmark=${1:-mcf}

export gem5_home=/home/yang111/Desktop/SuanNeng/GEM5
export gem5=$gem5_home/build/RISCV/gem5.fast

export desc_dir=/home/yang111/Desktop/SuanNeng/workload_lst
export workload_list=$desc_dir/${benchmark}.lst  # 根据参数动态选择.lst文件

export cpt_dir=/home/yang111/Desktop/SuanNeng/NEMU/checkpoint_example_result/${benchmark}/spec-cpt/${benchmark}  # 动态设置检查点路径
export GCBV_REF_SO=/home/yang111/Desktop/SuanNeng/NEMU/build/riscv64-nemu-interpreter-so
export log_file='log.txt'

export ds=$(pwd)
export top_work_dir=$ds/exec-storage/${benchmark}  # 动态设置输出目录
mkdir -p $top_work_dir

export num_threads=4

check() {
    if [ $1 -ne 0 ]; then
        echo FAIL
        touch abort
        exit
    fi
}

run() {
    set -x
    cpt=$1
    dw_len=${2:-50000000}
    total_detail_len=${3:-100000000}
    work_dir=${4:-$PWD}
    arch_db=${5:-0}

    cd $work_dir

    if test -f "completed"; then
        echo "Already completed; skip $cpt"
        return
    fi

    rm -f abort completed
    
    cpt_name=$(basename -- "$cpt")
    extension="${cpt_name##*.}"
    
    cpt_option="--generic-rv-cpt=$cpt --gcpt-restorer /home/yang111/Desktop/SuanNeng/NEMU/resource/gcpt_restore/build/gcpt.bin "

    $gem5 \
        $gem5_home/configs/example/xiangshan.py \
        --cpu-clock=3GHz --cpu-type=DerivO3CPU \
        --xiangshan-system --mem-size=2GB \
        --caches --cacheline_size=64 \
        --l1i_size=64kB --l1i_assoc=8 \
        --l1d_size=64kB --l1d_assoc=8 \
        --l1d-hwp-type=XSCompositePrefetcher \
        --short-stride-thres=0 \
        --l2cache --l2_size=1MB --l2_assoc=8 \
        --l3cache --l3_size=16MB --l3_assoc=16 \
        --l1-to-l2-pf-hint \
        --l2-hwp-type=WorkerPrefetcher \
        --l2-to-l3-pf-hint \
        --l3-hwp-type=WorkerPrefetcher \
        --mem-type=DRAMsim3 \
        --dramsim3-ini=$gem5_home/ext/dramsim3/xiangshan_configs/xiangshan_DDR4_8Gb_x8_3200_2ch.ini \
        --bp-type=DecoupledBPUWithFTB \
        --enable-difftest \
        $cpt_option \
        --warmup-insts-no-switch=$dw_len \
        --maxinsts=$total_detail_len
    check $?

    touch completed
}

prepare_env() {
    set -x
    all_args=("$@")
    task=${all_args[0]}
    task_path=${all_args[1]}  # 例如 "gcc/spec-cpt/gcc/2"

    # 提取检查点编号（如从 "gcc/spec-cpt/gcc/2" 提取 "2"）
    task_id=$(basename "$task_path")

    # 构建检查点文件路径（如 $cpt_dir/2/_2_*.zstd）
    zstd_file=$(find -L "$cpt_dir/$task_id" -name "_${task_id}_*.gz" | head -n 1)

    if [ -z "$zstd_file" ]; then
        echo "Error: Checkpoint file not found for task $task_id in $cpt_dir/$task_id"
        exit 1
    fi

    work_dir=$top_work_dir/$task
    mkdir -p "$work_dir"
}

arg_wrapper() {
    prepare_env $@
    all_args=("$@")
    args=(${all_args[0]})

    k=1000
    M=$((1000 * $k))
    skip=${args[2]}
    fw=${args[3]}
    dw=${args[4]}
    sample=${args[5]}

    total_M=$(( ($dw + $sample)*$M ))
    dw_M=$(( $dw*$M ))

    run $zstd_file $dw_M $total_M $work_dir 0 >$work_dir/$log_file 2>&1
}

single_run() {
    task=$tag
    work_dir=$top_work_dir
    mkdir -p $work_dir

    warmup_inst=$(( 50 * 10**6 ))
    max_inst=$(( 100 * 10**6 ))

    rm -f $work_dir/completed $work_dir/abort
    run $warmup_inst $max_inst $work_dir 1 > $work_dir/$log_file 2>&1
}

export -f check run single_run arg_wrapper prepare_env

parallel_run() {
    cat $workload_list | parallel -a - -j $num_threads arg_wrapper {}
}

parallel_run

