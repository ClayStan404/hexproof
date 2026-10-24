# Hexproof — 文档索引

实现前阅读根目录 [AGENTS.md](../AGENTS.md)。按任务选择英文规格；当前状态和
历史记录不替代行为约定。开发、PR、审核、合并与发版都使用公开仓库
`ClayStan404/hexproof`；业主笔记和真实运维配置保留在仓库外。

| 目的 | 入口 |
| --- | --- |
| 恢复当前工作与未解决事项 | [开发交接](development-handoff.md) |
| 找到某个功能的英文约定 | [规格导航](implementation-plan.md)、[产品范围](product-brief.md) |
| 选择本地检查、GUI 验证与 CI 范围 | [开发策略](development-policy.md) |
| 了解架构选择、模块边界 | [工程决策](decisions.md)、[模块职责](module-boundaries.md) |
| 公共反馈与 AI 开发 | [整体架构](autonomous-development.md)、[反馈 V2](public-feedback-v2.md) |
| Multica 操作、恢复、发版和移除 | [原生操作入口](multica-operations.md) |
| 反馈服务部署与排障 | [反馈运维](feedback-operations.md) |
| 生产服务器安装与升级 | [部署规程](../deploy/home/README.md) |
| Forge 运行时、对应源码与重建 | [运行时指南](../third_party/forge-runtime/README.md) |
| 用户操作说明 | [英文](user-guide.md)、[简体中文](user-guide.zh-CN.md) |

技术栈保持 Qt 6 / QML / C++20 客户端与 Go 房间中枢。默认是手动桌面；
可选 Forge 规则模式由外部进程托管。许可证见 [LICENSE](../LICENSE)。

部署与原生操作状态以[外置配置](multica-operations.md#operator-configuration)
和实际读回为准。任务过程、测试日志和截图保存在私有原生任务或本机
`build/`，不要提交运行证据、真实节点清单或凭据。

当前场景与 fixture 命令见 [场景指南](ai-verification.md)、
[生命周期场景](ai-verification-lifecycle.md)和[多客户端指南](multi-client-testing.md)。
完成的试验与迁移记录不是永久流程，也不要求重复验收。
