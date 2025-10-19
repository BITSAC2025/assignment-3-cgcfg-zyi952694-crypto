#include "CFGA.h"
#include "SVF/Util/GraphIterator.h"
#include <vector>
#include <unordered_set>

using namespace SVF;
using namespace llvm;
using namespace std;

// CFGAnalysis类构造函数：初始化ICFG指针和源/汇节点
CFGAnalysis::CFGAnalysis(ICFG* icfg) : icfg(icfg) {
    // 这里可以根据需求初始化sources和sinks（示例中假设外部已设置）
    // 实际场景中可能需要从ICFG中提取特定节点作为源/汇（如函数入口/出口）
}

// 主分析函数：遍历所有源-汇对，启动DFS搜索路径
void CFGAnalysis::analyze(ICFG* icfg) {
    // 遍历每个源节点到每个汇节点的路径
    for (ICFGNode* src : sources) {
        for (ICFGNode* snk : sinks) {
            vector<ICFGNode*> currentPath;  // 存储当前搜索路径
            unordered_set<ICFGNode*> visited;  // 标记已访问节点（防循环）
            dfs(src, snk, currentPath, visited);  // 启动DFS
        }
    }
}

// DFS辅助函数：递归搜索从当前节点到目标汇节点的路径
void CFGAnalysis::dfs(ICFGNode* currentNode, ICFGNode* targetSink,
                     vector<ICFGNode*>& currentPath,
                     unordered_set<ICFGNode*>& visited) {
    // 1. 标记当前节点为已访问，并加入当前路径
    visited.insert(currentNode);
    currentPath.push_back(currentNode);

    // 2. 若当前节点是目标汇节点，记录路径
    if (currentNode == targetSink) {
        recordPath(currentPath);
    }
    // 3. 否则，遍历所有后继节点继续搜索
    else {
        // 获取当前节点的所有出边（ICFGEdge是控制流边）
        for (ICFGEdge* edge : currentNode->getOutEdges()) {
            ICFGNode* succNode = edge->getDstNode();  // 后继节点（边的终点）
            // 若后继节点未被访问过，递归DFS
            if (visited.find(succNode) == visited.end()) {
                dfs(succNode, targetSink, currentPath, visited);
            }
        }
    }

    // 4. 回溯：移除当前节点，允许其他路径复用该节点
    currentPath.pop_back();
    visited.erase(currentNode);
}

// 记录路径到结果集合
void CFGAnalysis::recordPath(const vector<ICFGNode*>& path) {
    paths.push_back(path);
}

// 打印所有记录的路径（节点ID序列）
void CFGAnalysis::dumpPaths() {
    errs() << "\nTotal paths found: " << paths.size() << "\n";
    for (size_t i = 0; i < paths.size(); ++i) {
        errs() << "Path " << i + 1 << ": ";
        for (ICFGNode* node : paths[i]) {
            errs() << node->getId() << " -> ";  // 输出节点ID
        }
        errs() << "END\n";
    }
}

// 主函数：初始化并启动分析
int main(int argc, char **argv) {
    // 解析命令行参数，获取输入的LLVM bitcode文件
    auto moduleNameVec = OptionBase::parseOptions(
        argc, argv, "ICFG Path Analysis", "[options] <input-bitcode...>"
    );

    // 构建SVF模块（加载bitcode并初始化IR）
    LLVMModuleSet::buildSVFModule(moduleNameVec);

    // 构建SVFIR（静态单赋值形式的中间表示）和ICFG（ interprocedural CFG）
    SVFIRBuilder builder;
    auto pag = builder.build();
    auto icfg = pag->getICFG();

    // 初始化分析器并启动分析
    CFGAnalysis analyzer(icfg);
        if (!icfg->getICFGNodes().empty()) {
        analyzer.sources.push_back(*icfg->getICFGNodes().begin());
        analyzer.sinks.push_back(*icfg->getICFGNodes().rbegin());
    }
    analyzer.analyze(icfg);

    // 输出所有检测到的路径
    analyzer.dumpPaths();

    // 释放资源
    LLVMModuleSet::releaseLLVMModuleSet();
    return 0;
}