# Hexproof

[English](README.md) | [简体中文](README.zh-CN.md)

[![CI](https://github.com/ClayStan404/hexproof/actions/workflows/ci.yml/badge.svg)](https://github.com/ClayStan404/hexproof/actions/workflows/ci.yml)

Hexproof 是一款原生桌面多人联机《万智牌》虚拟桌面应用。
玩家自行移动卡牌并处理卡牌规则，应用则负责同步共享区域、隐藏信息、
回合、战斗声明和对局状态。

它有意设计为**不包含卡牌规则引擎**。Hexproof 为实体套牌提供快速、
灵活的虚拟桌面，无需账号、匹配系统或浏览器外壳。客户端支持 Linux、
Windows 和 macOS，并提供英语和简体中文界面。

当前版本：**1.0.0**。客户端与服务器的应用版本必须完全一致。

## 已实现功能

### 房间与在线对战

- 通过房间代码加入，或浏览当前所连接中心服务器上的房间。
- 支持通用 1v1、决斗指挥官以及三人或四人指挥官（Commander/EDH）牌桌。
- 在适用的赛制中支持 BO1 和 BO3 对局流程，包括局间换备。
- 单人测试使用与多人游戏相同的权威牌桌流程。
- 支持玩家和旁观者身份、密码保护房间、房主控制、公开聊天/日志，
  以及网络中断后重新连接至原座位。
- 支持内置的命名服务器和用户自定义 WebSocket 服务器。
- 可回放当前中心服务器保留的对局公开日志。

### 手动虚拟桌面

- 可在牌库、手牌、战场、坟墓场、放逐区、堆叠、展示区、统帅区和备牌区之间拖动卡牌。
- 战场会按照地、生物、鹏洛客、结界、神器及其他永久物自动分行；
  可调整卡牌缩放，并为大型多人战场提供聚焦视图。
- 支持横置/重置、牌面朝下、双面牌选面、指示物、生命、统帅税、统帅伤害、
  衍生物、掷骰子、抛硬币和调度。
- 支持多选卡牌、搜索牌库及处理牌库顶 X 张牌、浏览公开区域、洗牌/排序、
  随机或整手弃牌，以及经牌主批准后访问其他玩家的牌库或公开区域卡牌。
- 支持回合/阶段同步、响应信号、攻击/阻挡声明、目标箭头、结附、
  每回合下地记录和可选的原子操作辅助。
- 为高频操作提供右键菜单和易于发现的键盘快捷键。

### 套牌、卡牌数据与牌图

- 支持粘贴或从文件导入常见纯文本及 Moxfield 风格牌表；
  复制或导出到文件时会保留印刷版本标识。
- 提供本地套牌库和编辑器，支持分类布局、主牌/备牌拖动、统帅选择、
  印刷版本选择和套牌专属的首选衍生物。
- 支持自定义、标准、先驱、现代、薪传、特选、平民、决斗指挥官和指挥官套牌赛制。
- 使用 Scryfall 合法性、同名牌数量限制、统帅色组、主牌数量和备牌数量，
  在本地异步提供建议性校验。服务器不强制执行卡牌规则，也不声称提供赛事认证。
- 使用一个有版本控制的 SQLite 卡牌数据库，存储英文元数据、简体中文牌名、
  本地化印刷版本查询、衍生物和离线搜索数据。
- 客户端内置应用与卡牌数据库更新检查。系统会下载当前平台的应用包，
  对照 Release 校验和验证后，再提供下载文件夹的位置。
- 牌图按需加载并优先使用本地缓存。中文模式优先使用真实的简体中文印刷版本，
  并依次回退至 MTGCH 和英文来源；英文模式优先使用 Scryfall 英文牌图。

### 中心服务器赛事

- 在单个中心服务器上举办无需账号的个人 1v1 瑞士轮赛事。
- 支持报名、签到、对阵、私密比赛房间、赛果上报与确认、退赛、轮次计时、
  排名和官方风格的同分比较规则。
- 支持标准、先驱、现代、薪传、特选、平民和决斗指挥官赛事赛制，
  并可使用 BO1 或 BO3 对局。
- 参赛者牌表在赛事期间保持私密，赛事结束后公开查看。

## 产品边界

Hexproof 自动处理共享状态和安全的虚拟桌面操作，而不处理万智牌卡牌规则。
玩家和赛事组织者仍需自行负责卡牌文本、合法目标、触发式异能、优先权、
替代性效应、处罚和特殊互动。项目不包含核心账号系统、天梯、
全局匹配服务、收藏经济系统或 Web 客户端。

套牌校验仅供参考，并依赖已安装的本地卡牌目录。目录缺失或过期时，
系统会返回“未验证”结果，而不会错误地声称套牌合法。自定义套牌仍可用于变体玩法
和不受限制的手动游戏。

## 隐私模型

Hexproof 使用可信服务器模型。房间服务器保存权威游戏状态，
其中包括隐藏卡牌的身份，但只向每个客户端发送符合其身份权限的状态投影：

- 玩家会收到自己获准查看的私有区域卡牌身份；
- 对手只会收到隐藏区域的卡牌数量和牌背；旁观者同样如此，
  除非房间明确启用实时查看当前手牌；
- 公开以及明确展示的卡牌对整个房间可见；
- 对其他玩家的牌库或公开区域卡牌执行远程操作前，
  必须获得一次明确且短时有效的授权。

此模型可避免正常游戏中的意外信息泄露，但无法针对服务器运营者提供密码学隐私。
若此信任边界十分重要，请自行托管服务器。

## 使用客户端

1. 打开**设置**，选择界面/卡牌语言，并安装或导入最新卡牌数据库。
2. 打开**套牌库**，粘贴或加载牌表、选择赛制、处理印刷版本或统帅选择，
   并缓存缺失的牌图。
3. 使用**单人测试**进入私人牌桌；或连接内置/自定义服务器，
   创建、加入、浏览或旁观房间，以及管理赛事。
4. 在等待房间中，选择符合房间赛制的套牌并标记为准备就绪。
   预加载房间会等待所需牌图加载完成；后台加载房间会立即进入牌桌并继续缓存。

大部分区域操作都位于右键菜单中，使战场保持为主要操作界面。
右键单击牌库、手牌背景、战场卡牌、坟墓场、放逐区、统帅区或选中的卡牌组，
即可查看当前来源可用的操作。牌桌内的快捷键帮助列出了对应的键盘操作。

## 从源码构建

### 环境要求

- CMake 3.21 或更高版本，以及支持 C++20 的编译器
- Qt 6.5 或更高版本，并包含 Concurrent、Core、Gui、LinguistTools、Network、
  Quick、QuickTest、SQL、Test 和 WebSockets 模块
- 用于在发行包中支持 WebP 牌图的 Qt Image Formats
- zlib 和 Ninja
- Go 1.26 或 `apps/server/go.mod` 中声明的版本

请从仓库根目录开始构建。先构建服务器可使客户端集成测试找到服务器程序。

### 服务器

```sh
mkdir -p build/server
(cd apps/server && go test ./...)
(cd apps/server && CGO_ENABLED=0 go build \
  -o ../../build/server/hexproof-server ./cmd/hexproof-server)
./build/server/hexproof-server -bind 127.0.0.1 -port 57320
```

向公网开放中心服务器前，请使用 `./build/server/hexproof-server -help`
查看容量、保留期限、速率限制和可信代理选项。对于面向互联网的 `wss://` 服务，
请在仅监听本地主机的服务前放置支持 TLS 的反向代理或隧道。

### 客户端

```sh
cmake -S apps/client-qt -B build/client-qt -G Ninja
cmake --build build/client-qt
ctest --test-dir build/client-qt --output-on-failure
./build/client-qt/hexproof
```

`server-integration` CTest 会查找 `build/server/hexproof-server`
或 `HEXPROOF_SERVER_BINARY` 中指定的路径。仅在有意只运行客户端测试时，
才使用 `ctest -LE integration`。

全新检出的代码会嵌入 `apps/client-qt/config/servers.example.json`
中的非生产环境端点；自定义服务器字段仍可用于本地测试。
如需在打包时加入命名的默认服务器，请将该文件复制到被忽略的
`apps/client-qt/config/servers.json`，或使用以下配置：

```sh
cmake -S apps/client-qt -B build/client-qt -G Ninja \
  -DHEXPROOF_SERVER_DIRECTORY_FILE=/absolute/path/to/servers.json
```

完整的数据结构和发布密钥工作流记录在
[`apps/client-qt/config/README.md`](apps/client-qt/config/README.md) 中。

## 卡牌数据库

应用可以在没有卡牌数据库的情况下运行，但套牌搜索、印刷版本选择、
本地化元数据、衍生物身份识别和命名赛制校验需要最新的 schema-v10 目录。
设置页面可以从稳定的 `card-data` Release 安装预构建数据库，
并显示已安装和可用的构建版本。卡牌图片不会嵌入数据库，而是继续按需缓存在本地。

如需使用当前 Scryfall 和 MTGCH 数据源在本地构建最新发行数据库：

```sh
./tools/card-database-builder/build-latest.sh
```

该脚本每次运行都会下载最新的上游输入，并将数据库、清单、哈希值和压缩发行资源
写入 `build/card-database/`。固定输入和离线导入工作流请参阅
[`tools/card-database-builder/README.md`](tools/card-database-builder/README.md)。

## 验证

使用以下命令运行完整的本地质量和回归测试套件：

```sh
./tools/verify.sh
```

它会检查格式、SPDX 标头、Shell 脚本、QML 文本安全、协议一致性、翻译、
模块大小预算和质量工具测试；运行 Go 格式检查、vet、测试和竞态测试；
执行干净的服务器与客户端构建；验证二进制版本；并运行完整的 CTest 套件。
它不会启动交互式客户端，也不会访问远程服务器。

使用 `./tools/verify.sh --quick` 可跳过竞态测试和 CTest，
使用 `./tools/verify.sh --help` 可查看构建路径和格式比较基准选项。

## 发布自动化

仓库包含三个 GitHub Actions 工作流：

- [`ci.yml`](.github/workflows/ci.yml) 保持推送和拉取请求检查精简：
  静态质量门禁、Go vet/测试/构建以及 Linux Qt 构建/CTest 套件。
  手动运行时还会启用 Go 竞态/模糊测试、Linux ASan/UBSan，
  以及 Windows/macOS 构建和测试任务。
- [`release.yml`](.github/workflows/release.yml) 生成便携式 Windows x64、
  macOS Apple Silicon 和 Intel、Linux x86_64，以及 Linux amd64/arm64
  服务器归档，并将最新官方卡牌数据库打包进同一个版本化 Release。
- [`card-database.yml`](.github/workflows/card-database.yml)
  每周或按需重建并发布官方卡牌数据库。

带标签的版本使用 `vMAJOR.MINOR.PATCH`。发行版客户端会嵌入通过
`HEXPROOF_PUBLIC_SERVERS_JSON` Actions 密钥提供的服务器目录；
普通 CI 和复刻仓库则使用受版本控制的示例目录构建。
平台打包详情请参阅 [`packaging/README.md`](packaging/README.md)。
客户端最多每 24 小时检查一次已发布的稳定版本，
也可以在设置中明确要求刷新。草稿 Release 不会提供给用户。

未签名的 macOS Actions 构建产物仅使用临时签名，未经 Apple 公证。
对于审阅构建，请右键单击 `Hexproof.app`，选择**打开**并确认；
也可在启动前运行 `xattr -cr /path/to/Hexproof.app`。
经过正确签名和公证的发行版不需要此绕过操作。

## 仓库结构

| 路径 | 用途 |
|------|------|
| `apps/client-qt/` | Qt 6/QML/C++20 桌面客户端 |
| `apps/server/` | Go WebSocket 房间与赛事中心服务器 |
| `protocol/v1/` | 规范的 `hexproof.v1` 传输协议结构 |
| `testdata/protocol/v1/` | 客户端/服务器共享协议测试数据 |
| `packaging/` | 客户端、服务器和卡牌数据库发布工具 |
| `tools/` | 验证、代码生成、数据库构建和 UI 测试辅助工具 |

## 参与贡献

请保持变更聚焦，并遵守手动虚拟桌面和隐私边界。
使用 `gofmt` 格式化 Go 代码；遵循现有 Qt 风格；保留 SPDX 标头；
涉及隐藏信息的变更需添加牌主/对手/旁观者测试。

传输协议变更应从 `protocol/v1/wire-schema.json` 开始，然后运行：

```sh
python3 tools/protocol_codegen.py
python3 tools/check-protocol-parity.py
```

请更新 `testdata/protocol/v1/` 下的共享测试数据，并在提交变更前运行
`./tools/verify.sh`。

## 许可证

Hexproof 使用 GPL-2.0-only 许可证；详情请参阅 [`LICENSE`](LICENSE)。
包含第三方作品的文件会保留相应的上游版权声明。
