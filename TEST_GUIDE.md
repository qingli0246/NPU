# NPU 顶层集成测试指南

## 📋 当前测试程序说明

### 测试文件
- **测试平台**：`TB/tb_npu_top_test.v`
# NPU 顶层集成测试指南

当前仓库只保留一套仿真入口：`TB/tb_npu_top_test.v` 和 `quick_test.ps1`。

## 当前测试内容

- 测试平台：`TB/tb_npu_top_test.v`
- 测试模式：单 Tile（Tile#0），INDEP 模式
- 矩阵尺寸：`M=8, N=8, K=8`
- 当前测试数据：A 为单位矩阵，B 为全零矩阵

## 推荐运行方式

```powershell
cd f:\complication-6\NPU
.\quick_test.ps1
```

如果你想手动编译运行，就用当前测试平台，不要再切回旧的 `tb_npu_top.v`：

```powershell
cd f:\complication-6\NPU
iverilog -g2012 -I rtl -o TB\npu_top_integrated.vvp TB\tb_npu_top_test.v rtl\npu_top.v rtl\npu_ctrl.v rtl\npu_compute_pool.v rtl\npu_tile.v rtl\npu_dma_rd.v rtl\npu_dma_wr.v rtl\npu_weight_cache.v rtl\npu_axi4_bridge.v
vvp TB\npu_top_integrated.vvp
```

## 结果判断

- 仿真输出应以 `TB/tb_npu_top_test.v` 的内容为准。
- 当前测试数据下，Tile 结果为全零是正常现象，因为 B 矩阵是全零。
- 若要验证非零结果，请把 B 改成非零矩阵或单位矩阵。

## 说明

- 旧的 PowerShell 仿真脚本已经合并或删除。
- 旧的运行说明已经合并到这里。
- 旧的编译产物和波形文件需要在重新运行脚本后再生成，不要依赖历史文件。