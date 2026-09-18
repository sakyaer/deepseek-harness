#!/bin/zsh
# DeepSeek Harness 桌面版一键更新脚本（个人分支专用）
# 用法（在仓库根目录执行）:
#   ./local/rebuild-dsh-desktop.sh          # 同步上游 + 重新打包 + ad-hoc 重签名
#   ./local/rebuild-dsh-desktop.sh --launch # 打包后自动启动 App
#
# 说明:
#   - 上游自 0.1.6 起从 apps/desktop/.env.macos 读取发布配置，并且会剥离 shell 里
#     DSH_DESKTOP_*/APPLE_*/CSC_* 变量。所以本脚本改为写入该文件（已 gitignore），
#     不再用 export 传参。
#   - 使用 ad-hoc 签名（identity "-"），无 Apple 开发者证书，产物仅限本机使用。
#     上游的打包前置校验已按 ad-hoc 放行：不要求 p12（CSC_LINK）、不要求公证凭据。
#   - 手动整体重签名仍是必需步骤：electron-builder 跳过签名后，Apple Silicon 上必须
#     `codesign --force --deep --sign -` 才能启动。
#   - 分支上只保留两处本地补丁：ad-hoc 打包放行 + dev 模式 Dock 图标。

set -e

# 脚本位于仓库的 local/ 下，仓库根目录即其上一级
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# pnpm 目录按本机布局放在仓库的上一级
WORKSPACE="$(dirname "$REPO")"
APP="$REPO/apps/desktop/.desktop-build/targets/mac-arm64/artifacts/mac-arm64/DeepSeek Harness.app"
ENV_FILE="$REPO/apps/desktop/.env.macos"

export PATH="/Users/sakyaer/.workbuddy/binaries/node/versions/22.22.2-3/bin:$PATH"
export PNPM_HOME="$WORKSPACE/.pnpm-home"
export npm_config_store_dir="$WORKSPACE/.pnpm-store"
export ELECTRON_MIRROR="https://npmmirror.com/mirrors/electron/"
# WorkBuddy 环境泄漏防护（普通终端下无副作用）
unset ELECTRON_RUN_AS_NODE

echo "==> [0/6] 准备本地发布配置"
if [[ -f "$ENV_FILE" ]]; then
  echo "    已存在 $ENV_FILE，保持不变（如需重置请先删除该文件）"
else
  cat > "$ENV_FILE" <<'ENVEOF'
# 个人本地构建配置（Git 忽略）。由 local/rebuild-dsh-desktop.sh 生成。
DSH_DESKTOP_APP_ID=local.deepseek.harness
DSH_DESKTOP_AUTO_UPDATE_ENV=test

# ad-hoc 签名：没有开发者证书，团队 ID 仅用于通过格式校验（10 位大写字母/数字）
DSH_DESKTOP_MACOS_SIGNING_IDENTITY=-
DSH_DESKTOP_MACOS_TEAM_ID=AAAAAAAAAA

# 注意：刻意不设置 CSC_LINK / CSC_KEY_PASSWORD / APPLE_* 与强制更新策略来源。
# ad-hoc 模式下打包脚本会跳过公证凭据、p12 与强制更新策略的校验。
ENVEOF
  echo "    已生成 $ENV_FILE"
fi

cd "$REPO"

echo "==> [1/6] 同步上游并变基当前分支"
git fetch upstream
git rebase upstream/master

echo "==> [2/6] 安装依赖（如 lockfile 无变化会很快）"
pnpm install

echo "==> [3/6] 打包桌面 App（含构建，约数分钟）"
pnpm package:desktop:mac:arm64:dir

echo "==> [4/6] 整体 ad-hoc 签名"
codesign --force --deep --sign - "$APP"
codesign --verify --strict "$APP"

if [[ "$1" == "--launch" ]]; then
  echo "==> [5/6] 启动 App"
  open -a "$APP"
else
  echo "==> [5/6] 跳过启动（加 --launch 参数可自动启动）"
fi

# 同步到 ~/Applications（可点击启动的安装副本）
echo "==> [6/6] 同步安装到 ~/Applications"
ditto "$APP" "$HOME/Applications/DeepSeek Harness.app"

echo "✅ 完成: $APP"
