# 自动发布Github

⚠️ 注意事项  
 1. 发布前注意确认好版本 (主 Tartget的 Marketing Version)
 2. 请先确保使用 Archive 成功打包 framework 和 docc

## 安装 GitHub CLI

brew install gh  
或者官网下载安装：https://cli.github.com/


## 登录 Github 账户

执行：gh auth login
默认通过基于网页的浏览器进行身份验证，
注意翻墙，可能会超时，多试几次

检查：gh auth status 


## 新建发布脚本

Xcode 中点击项目目录，  
左下角 + (Add a tartget)，选择 Other -> Aggregate，命名为 Release
点击 Release Target，左上角点击 + ，选择 Add User-Defined Setting  
点击 Release Target 的 Build Settings，搜索 User Script Sandboxing，并将其改为 No  
点击 Release Target 的 Build Phases -> Run Script，输入下面的脚本  
然后点击运行即可自动发布版本

```
#!/bin/bash

set -e  # 错误时终止

# --- 变量 ---

MARKETING_VERSION=$(xcodebuild -project "$PROJECT_NAME.xcodeproj" -showBuildSettings | grep "MARKETING_VERSION" | head -1 | awk -F "= " '{print $2}')
CURRENT_PROJECT_VERSION=$(xcodebuild -project "$PROJECT_NAME.xcodeproj" -showBuildSettings | grep "CURRENT_PROJECT_VERSION" | head -1 | awk -F "= " '{print $2}')

FRAMEWORK_NAME="RFIDManager"        # SDK名字
FRAMEWORK_VERSION="${MARKETING_VERSION}_${CURRENT_PROJECT_VERSION}"         # SDK 版本号
ARCHIVE_PATH="${PROJECT_DIR}/build/archive_v${FRAMEWORK_VERSION}"           # SDK 打包路径
FRAMEWORK_PATH="${ARCHIVE_PATH}/${FRAMEWORK_NAME}.xcframework"              # SDK 文件路径
DOCC_PATH="${ARCHIVE_PATH}/DerivedData/Build/Products/Release/${FRAMEWORK_NAME}.doccarchive"     # SDK 文档路径

GITHUB_REPO="https://github.com/zsguang/RFID-IOS-SDK.git"         # Github 仓库路径
RELEASE_TAG="v${MARKETING_VERSION// /}"                           # Release TAG
TEMP_DIR="${PROJECT_DIR}/build/release_${RELEASE_TAG}"            # 临时目录

# --- 验证SDK和文档文件是否存在 ---

if [ ! -d "${FRAMEWORK_PATH}" ]; then
 echo "❌ 错误：${FRAMEWORK_PATH} 不存在，请先构建 ${FRAMEWORK_NAME}.xcframework"
 exit 1
fi

if [ ! -d "${DOCC_PATH}" ]; then
 echo "❌ 错误：${DOCC_PATH} 不存在，请先构建文档${FRAMEWORK_NAME}.doccarchive"
 exit 1
fi

# --- 准备临时目录 ---
rm -rf "${TEMP_DIR}"
mkdir -p "${TEMP_DIR}"
cd "${TEMP_DIR}"

# --- 拷贝并压缩框架 ---
zip -r "${FRAMEWORK_NAME}.xcframework.zip" "${FRAMEWORK_PATH}"
echo "✅ ${FRAMEWORK_NAME}.xcframework.zip生成完毕"

# --- 生成 Package.swift ---
cat > "Package.swift" <<EOF
// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RFID-IOS-SDK",
    platforms: [
        .iOS(.v12),
        .macOS(.v11.5)
    ],
    products: [
        .library(
            name: "${FRAMEWORK_NAME}",
            targets: ["${FRAMEWORK_NAME}"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "${FRAMEWORK_NAME}",
            url: "https://github.com/zsguang/RFID-IOS-SDK/releases/download/${RELEASE_TAG}/${FRAMEWORK_NAME}.xcframework.zip",
            checksum: "$(swift package compute-checksum "${TEMP_DIR}/${FRAMEWORK_NAME}.xcframework.zip")"
        )
    ]
)
EOF
echo "✅ Package.swift 生成完毕"


# --- 检查Release是否已存在 ---
if gh release view "${RELEASE_TAG}" &>/dev/null; then
    echo "❌ 版本 ${RELEASE_TAG} 已存在，请更新版本号"
    exit 1
fi


# --- 推送 Package.swift 到仓库 ---
echo "🔵 开始克隆仓库..."
if ! git clone "${GITHUB_REPO}" "${TEMP_DIR}/RFID-IOS-SDK"; then
    echo "❌ 错误：仓库克隆失败"
    exit 1
fi
echo "✅ 克隆仓库完成"

cd "${TEMP_DIR}/RFID-IOS-SDK" 

# 更新文档目录
mkdir -p docs
rm -rf "docs/${FRAMEWORK_NAME}.doccarchive"
cp -R "${DOCC_PATH}" "docs/${FRAMEWORK_NAME}.doccarchive"

# 更新Package.swift
cp -R "${TEMP_DIR}/Package.swift" .

if ! git diff --quiet; then
    git add .
    git commit -m "Update to ${RELEASE_TAG}"
    git push origin main
    echo "✅ 项目有更新并已推送"
else
    echo "ℹ️ 项目无变化，跳过提交"
fi


# --- 推送到 GitHub Releases ---
# 若提示 /opt/homebrew/bin/gh: No such file or directory
# 使用 which gh 获取 gh 目录，然后替换
echo "🔵 开始发布..."
/opt/homebrew/bin/gh release create "${RELEASE_TAG}" \
    "${TEMP_DIR}/${FRAMEWORK_NAME}.xcframework.zip" \
    --repo "zsguang/RFID-IOS-SDK" \
    --notes "Automatic release "${RELEASE_TAG}""

echo "✅ ${FRAMEWORK_NAME} ${RELEASE_TAG} 发布成功"


```

注意事项，发布脚本最后一个命令使用了 `/opt/homebrew/bin/gh`  
这是 gh 工具路径，可使用命令 `which gh` 获取路径，如果路径不同请进行替换
