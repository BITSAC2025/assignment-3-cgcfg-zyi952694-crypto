#!/bin/bash

# ==============================================
# 配置区域（请根据实际环境修改以下路径）
# ==============================================
TEST_CASES_DIR="./Test-Cases"               # .c测试用例目录
BITCODE_DIR="./Test-Cases-BC"               # 生成的.bc文件存放目录
RESULT_DIR="./Test-Cases-Results"           # 分析结果存放目录（含图片）
CFGA_BIN="./cfga"                           # cfga可执行文件路径
SVF_LIB_DIR="$HOME/SVF/Debug-build/lib"     # SVF共享库目录（根据实际修改）
# ==============================================

# 颜色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 检查工具依赖（新增graphviz的dot工具检查）
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}错误：未找到工具 $1，请先安装。${NC}"
        if [ "$1" = "dot" ]; then
            echo -e "${YELLOW}安装命令：sudo apt install graphviz -y${NC}"
        fi
        exit 1
    fi
}

# 检查环境是否就绪
check_environment() {
    # 检查测试用例目录
    if [ ! -d "$TEST_CASES_DIR" ]; then
        echo -e "${RED}错误：测试用例目录 $TEST_CASES_DIR 不存在。${NC}"
        exit 1
    fi

    # 检查cfga可执行文件
    if [ ! -x "$CFGA_BIN" ]; then
        echo -e "${RED}错误：cfga程序 $CFGA_BIN 不存在或不可执行，请先编译。${NC}"
        exit 1
    fi

    # 检查SVF共享库
    if [ ! -d "$SVF_LIB_DIR" ] || [ ! -f "$SVF_LIB_DIR/libSvfLLVM.so.3" ]; then
        echo -e "${RED}错误：未找到SVF共享库 libSvfLLVM.so.3，请修改SVF_LIB_DIR。${NC}"
        exit 1
    fi

    # 创建输出目录（含图片子目录）
    mkdir -p "$BITCODE_DIR" "$RESULT_DIR" "$RESULT_DIR/icfg_images"
    echo -e "${GREEN}环境检查通过，输出目录：${NC}"
    echo "  - Bitcode：$BITCODE_DIR"
    echo "  - 结果文件：$RESULT_DIR"
    echo "  - ICFG图片：$RESULT_DIR/icfg_images"
}

# 编译.c文件为LLVM bitcode
compile_to_bc() {
    local c_file="$1"
    local bc_file="$2"
    local compile_log="$RESULT_DIR/compile_$(basename "$c_file").log"

    echo -e "\n${YELLOW}编译：$(basename "$c_file")${NC}"
    clang -O0 -emit-llvm -c "$c_file" -o "$bc_file" 2> "$compile_log"
    if [ $? -ne 0 ]; then
        echo -e "${RED}编译失败！日志：$compile_log${NC}"
        return 1
    fi
    echo -e "${GREEN}生成bitcode：$bc_file${NC}"
    return 0
}

# 将.dot文件转换为PNG图片
convert_dot_to_png() {
    local dot_file="$1"
    local png_file="$2"
    local convert_log="$RESULT_DIR/convert_$(basename "$dot_file").log"

    echo -e "${YELLOW}转换ICFG图形：$(basename "$dot_file")${NC}"
    dot -Tpng "$dot_file" -o "$png_file" 2> "$convert_log"
    if [ $? -ne 0 ]; then
        echo -e "${RED}图片转换失败！日志：$convert_log${NC}"
        return 1
    fi
    echo -e "${GREEN}生成图片：$png_file${NC}"
    return 0
}

# 运行路径分析 + 处理ICFG可视化
run_analysis() {
    local bc_file="$1"
    local result_file="$2"
    local analysis_log="$RESULT_DIR/analysis_$(basename "$bc_file").log"
    local filename=$(basename "$bc_file" .bc)  # 提取文件名（不含.bc）
    local dot_file="$BITCODE_DIR/$filename.bc.icfg.dot"  # cfga生成的.dot文件路径
    local png_file="$RESULT_DIR/icfg_images/$filename_icfg.png"  # 转换后的图片路径

    echo -e "${YELLOW}分析：$(basename "$bc_file")${NC}"
    # 运行cfga，设置共享库路径
    LD_LIBRARY_PATH="$SVF_LIB_DIR:$LD_LIBRARY_PATH" "$CFGA_BIN" "$bc_file" > "$result_file" 2> "$analysis_log"
    if [ $? -ne 0 ]; then
        echo -e "${RED}分析失败！日志：$analysis_log${NC}"
        return 1
    fi

    # 检查是否生成了.dot文件
    if [ ! -f "$dot_file" ]; then
        echo -e "${YELLOW}警告：未找到ICFG.dot文件 $dot_file，跳过图片转换。${NC}"
    else
        # 转换.dot为PNG
        if ! convert_dot_to_png "$dot_file" "$png_file"; then
            echo -e "${YELLOW}警告：图片转换失败，不影响路径分析结果。${NC}"
        fi
    fi

    echo -e "${GREEN}分析完成，结果：$result_file${NC}"
    return 0
}

# 主函数
main() {
    # 检查必要工具（新增dot工具）
    check_dependency "clang"
    check_dependency "llvm-dis-16"
    check_dependency "dot"  # graphviz的转换工具

    # 检查环境
    check_environment

    local total=0
    local success=0
    local failed=0

    # 遍历所有.c测试用例
    for c_file in "$TEST_CASES_DIR"/*.c; do
        [ -f "$c_file" ] || continue  # 跳过非文件

        total=$((total + 1))
        local filename=$(basename "$c_file" .c)
        local bc_file="$BITCODE_DIR/$filename.bc"
        local result_file="$RESULT_DIR/$filename_result.txt"

        echo -e "\n====================================="
        echo -e "测试用例 $total：$filename.c"
        echo -e "====================================="

        # 编译
        if ! compile_to_bc "$c_file" "$bc_file"; then
            failed=$((failed + 1))
            continue
        fi

        # 分析 + 可视化
        if ! run_analysis "$bc_file" "$result_file"; then
            failed=$((failed + 1))
            continue
        fi

        success=$((success + 1))
    done

    # 汇总结果
    echo -e "\n====================================="
    echo -e "测试汇总"
    echo -e "====================================="
    echo -e "总用例数：$total"
    echo -e "${GREEN}成功：$success${NC}"
    echo -e "${RED}失败：$failed${NC}"
    echo -e "结果文件：$RESULT_DIR"
    echo -e "ICFG图片：$RESULT_DIR/icfg_images"
    echo -e "查看图片示例：eog $RESULT_DIR/icfg_images/[文件名]_icfg.png${NC}"
    echo -e "====================================="
}

# 启动主函数
main