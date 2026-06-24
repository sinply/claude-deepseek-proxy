# Claude 模型名重写代理

本地 HTTP 代理，让 Claude Code（以及其他 Anthropic 兼容客户端）继续使用**官方 Claude 模型名**，同时将请求路由到多个第三方 Anthropic 兼容上游（DeepSeek、火山引擎 Ark / 方舟 code plan 等）。

Claude Code 客户端已变得更加严格，要求模型列表中必须是真实的 `claude-*` 模型名。本代理在客户端侧保留这些官方名，在转发前按 provider 将 `model` 字段重写成上游实际模型名。

看门狗（watchdog）会让代理生命周期与 Claude Code 客户端保持同步：Claude 启动时代理自动启动，Claude 退出后不久代理自动停止。无需手动管理。

## 默认映射（`config/proxy-config.json`）

```text
# deepseek provider
claude-sonnet-4.6 -> deepseek-v4-flash
claude-opus-4.6  -> deepseek-v4-pro

# ark provider（火山引擎 Ark code plan）
claude-sonnet-4.6 -> kimi-k2.7-code
claude-opus-4.6  -> doubao-seed-2.0-pro
claude-opus-4.7  -> glm-5.2
```

同一个 Claude 模型名在不同 provider 会映射到不同的真实模型。

## 路由

单个代理监听 `http://127.0.0.1:8787`。路径的第一段选择 provider：

```text
http://127.0.0.1:8787/deepseek/   -> https://api.deepseek.com/anthropic
http://127.0.0.1:8787/ark/        -> https://ark.cn-beijing.volces.com/api/coding
```

将 Claude Code 的 base URL 设为其中之一（注意保留末尾斜杠）。剩余路径会原样转发给上游。

`GET /<provider>/v1/models` 会被拦截，并返回由 provider 的 map keys 合成的 Anthropic 格式响应。这样即使上游 `/v1/models` 不存在或返回非 Claude 模型名，也能满足 Claude Code 的模型发现检查。

## 看门狗（自动随 Claude Code 启停）

`scripts/proxy-watchdog.ps1` 作为隐藏后台进程运行（通过 `scripts/install-autostart.ps1` 安装为登录计划任务）。每 5 秒轮询一次 `Claude.exe`：

- Claude 在运行 + 代理已停止 → 启动代理
- Claude 已退出 15 秒 → 停止代理

因此你只需像往常一样启动 Claude Code（开始菜单、快捷方式等），代理会在 5 秒内自动拉起。退出 Claude Code，代理会在 15 秒宽限期后停止。无需包装脚本，无需手动启停。

通过命名互斥锁（mutex）保证只有一个看门狗实例在运行。

## 使用方法

### 1. 安装看门狗（一次性）

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-autostart.ps1
```

这会安装一个名为 `ClaudeModelRewriteProxyWatchdog` 的登录计划任务，并立即启动。之后只要你登录，看门狗就会运行。

### 2. 配置 Claude Code

通过 `ANTHROPIC_BASE_URL`（或 Claude-3p 网关配置）将 Claude Code 指向对应的 provider：

```text
http://127.0.0.1:8787/deepseek/   # DeepSeek
http://127.0.0.1:8787/ark/        # 火山引擎 Ark
```

模型列表中保留官方 Claude 模型名：

```json
[
  { "name": "claude-sonnet-4.6" },
  { "name": "claude-opus-4.6" },
  { "name": "claude-opus-4.7" }
]
```

API key 不存储在本项目中。Claude Code 在请求头中发送配置好的 API key，代理原样转发。

### 3. 正常启动 Claude Code

像平时一样启动 Claude Code。看门狗会在 5 秒内检测到并启动代理。退出 Claude Code 后，代理会在 15 秒宽限期后停止。

### 4. 验证

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\status.ps1
```

或直接双击 `bat\status.bat`。或直接查看日志：

```powershell
Get-Content .\logs\watchdog.log -Tail 10
Get-Content .\logs\proxy-*.log -Tail 10
```

每条请求会记录 `[provider] original -> mapped`，例如 `[deepseek] claude-sonnet-4.6 -> deepseek-v4-flash`。

## 配置文件

`config/proxy-config.json` 定义 provider：

```json
{
  "nodePath": "D:\\Program Files\\nodejs\\node.exe",
  "providers": {
    "deepseek": {
      "upstream": "https://api.deepseek.com/anthropic",
      "map": {
        "claude-sonnet-4.6": "deepseek-v4-flash",
        "claude-opus-4.6":  "deepseek-v4-pro"
      }
    },
    "ark": {
      "upstream": "https://ark.cn-beijing.volces.com/api/coding",
      "map": {
        "claude-sonnet-4.6": "kimi-k2.7-code",
        "claude-opus-4.6":  "doubao-seed-2.0-pro",
        "claude-opus-4.7":  "glm-5.2"
      }
    }
  }
}
```

### `nodePath`（可选）

`node.exe` 的绝对路径。所有 PowerShell 脚本（`scripts/proxy-watchdog.ps1`、`scripts/start-claude-deepseek-proxy.ps1`、`scripts/start-claude.ps1`）都读取此字段来启动代理。如果未设置或路径不存在，会按以下顺序自动探测：`C:\Program Files\nodejs\node.exe`、`D:\Program Files\nodejs\node.exe`，然后是 `PATH` 中的 `node.exe`。

当 Node.js 安装在非默认位置时，设置此字段可避免在脚本中硬编码路径。

如需自定义配置路径，可通过环境变量 `PROXY_CONFIG_PATH` 覆盖。

新增 provider：在 `providers` 下添加条目，然后将 Claude Code 指向 `http://127.0.0.1:8787/<name>/`。`/v1/models` 响应会自动根据该 provider 的 map keys 生成。

## 如何修改模型映射

要修改某个 Claude 名对应的真实模型，编辑 `config/proxy-config.json`：

1. 打开 `config/proxy-config.json`。
2. 在目标 `providers.<name>.map` 下，修改官方 Claude 模型名对应的值。
   - Key（如 `claude-sonnet-4.6`、`claude-opus-4.6`）是 Claude Code 看到并发送的名称。
   - Value 是上游 provider 期望的真实模型 ID。
3. 保存文件。
4. 重启代理以加载新配置：
   - 如果看门狗正在运行：结束代理进程（或运行 `bat\stop.bat` 再 `bat\restart-wd.bat`），看门狗会在几秒内重新拉起它。
   - 如果手动运行：结束当前 `node` 进程，然后重新运行 `scripts\start-claude-deepseek-proxy.ps1`。
5. 可选：如果你使用 Claude-3p，同步更新对应 configLibrary 条目中的 `labelOverride` 字段，让 UI 显示标签与真实模型一致。

你也可以新增 provider 或新增 Claude 名到真实模型的映射。每个 provider 的 `/v1/models` 响应都会根据 map keys 自动生成，因此 Claude Code 在代理重启后会立即看到新的官方 Claude 模型名。

## TLS 说明

DeepSeek 的服务器发送的证书链不完整。Node.js（与 Windows/.NET 不同）不会通过 AIA 获取缺失的中间证书，因此代理会为上游连接设置 `NODE_TLS_REJECT_UNAUTHORIZED=0`。这只影响本地代理进程对外到上游的 TLS，不影响 Claude Code 到代理的回环连接。

## 手动操作

```powershell
# 安装看门狗（登录时自动启动）
powershell -ExecutionPolicy Bypass -File .\scripts\install-autostart.ps1

# 查看状态
powershell -ExecutionPolicy Bypass -File .\scripts\status.ps1

# 卸载（停止看门狗、结束代理、移除计划任务）
powershell -ExecutionPolicy Bypass -File .\scripts\uninstall-autostart.ps1

# 手动启动代理，不看门狗（旧方式）
powershell -ExecutionPolicy Bypass -File .\scripts\start-claude-deepseek-proxy.ps1
```

或使用 `bat\` 下的便捷启动器：

| 批处理文件 | 作用 |
|---|---|
| `bat\start.bat` | 启动代理（无看门狗） |
| `bat\stop.bat` | 停止代理 + 看门狗进程 |
| `bat\status.bat` | 查看代理 + 看门狗状态及模型列表 |
| `bat\restart-wd.bat` | 重启看门狗计划任务 |

## 文件说明

```
src/model-rewrite-proxy.cjs              代理实现：按 provider 路由、模型名重写、/v1/models 拦截
config/proxy-config.json                 provider 定义（上游 URL + 模型映射）
scripts/proxy-watchdog.ps1               后台看门狗，同步代理与 Claude Code 的生命周期
scripts/install-autostart.ps1            安装看门狗计划任务
scripts/uninstall-autostart.ps1          卸载看门狗计划任务
scripts/start-claude-deepseek-proxy.ps1  独立启动代理（无看门狗），手动使用
scripts/start-claude.ps1                 包装脚本：启动代理 + Claude，Claude 退出时停止代理
scripts/status.ps1                       查看计划任务 / 看门狗 / 代理 / Claude 状态
bat/start.bat                            启动代理
bat/stop.bat                             停止代理 + 看门狗
bat/status.bat                           查看代理 + 看门狗状态及模型列表
bat/restart-wd.bat                       重启看门狗计划任务
logs/                                    所有代理与看门狗日志（已 Git 忽略）
docs/index.html                          静态 HTML 使用说明
```

## 注意事项

- 这不是系统代理。
- 只有显式配置为使用 `http://127.0.0.1:8787/<provider>/` 的软件才会受影响。
- 未知模型名会原样转发（不做重写）。代理不会发明映射。
- 日志：`logs/watchdog.log` 记录看门狗动作，每次代理启动会生成一个 `logs/proxy-<timestamp>.log`。所有日志文件已被 Git 忽略。
- 不要向 Git 提交私钥、Claude Code 配置文件、`logs/` 下的日志。

## 许可证

MIT。详见 `LICENSE`。
