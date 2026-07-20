# 自动打包 SDK

⚠️ 注意事项  
 1. 打包前注意确认好版本 (主 Tartget的 Marketing Version 和 Current Project Version)
 2. 下方脚本打包后的 SDK 文件位于 项目目录/build/archive_v.../RFIDManager.xcframework

## 新建打包脚本

Xcode 中点击项目目录，  
左下角 + (Add a tartget)，选择 Other -> Aggregate，命名为 Archive
点击 Release Target，左上角点击 + ，选择 Add User-Defined Setting  
点击 Release Target 的 Build Settings，搜索 User Script Sandboxing，并将其改为 No  
点击 Release Target 的 Build Phases -> Run Script，输入下面的脚本  
接着点击运行即可自动打包二进制 xcframework 文件和 docc 文档文件，  
打包后的 SDK 文件位于` 项目目录 /build/archive_v.../RFIDManager.xcframework `  
打包后的 DocC 文件位于` 项目目录 /build/archive_v.../DerivedData/Build/Products/Release/${FRAMEWORK_NAME}.doccarchive `  

### 需要附带dSYM

> dSYM = Debug Symbols (调试符号文件),它是一个包含调试信息的独立文件，扩展名为 .dSYM，内部使用 DWARF 格式存储。
> xcframework库携带dSYM时，能够在调报错时显示完整的函数调用栈和耗时，否则只会显示内存地址

```
#!/bin/bash

FRAMEWORK_NAME=RFIDManager
# FRAMEWORK_VERSION=1.2.0

# 自动获取版本信息
MARKETING_VERSION=$(xcodebuild -project "$PROJECT_NAME.xcodeproj" -showBuildSettings | grep "MARKETING_VERSION" | head -1 | awk -F "= " '{print $2}')
CURRENT_PROJECT_VERSION=$(xcodebuild -project "$PROJECT_NAME.xcodeproj" -showBuildSettings | grep "CURRENT_PROJECT_VERSION" | head -1 | awk -F "= " '{print $2}')

# 版本号
FRAMEWORK_VERSION="${MARKETING_VERSION}_${CURRENT_PROJECT_VERSION}"

if [ -z "$FRAMEWORK_VERSION" ]; then
  echo "❌ 错误: 无法获取项目版本号"
  exit 1
fi
echo "📦 正在打包 $PROJECT_NAME 版本 $FRAMEWORK_VERSION"


ARCHIVE_PATH="${PROJECT_DIR}/build/archive_v${FRAMEWORK_VERSION}"


# 清理构建目录
rm -rf "${ARCHIVE_PATH}"

# 封装校验函数
check_framework_files() {
  local platform=$1
  local framework_path="${ARCHIVE_PATH}/RFIDManager-${platform}.xcarchive/Products/Library/Frameworks/RFIDManager.framework"
  local dsym_path="${ARCHIVE_PATH}/RFIDManager-${platform}.xcarchive/dSYMs/RFIDManager.framework.dSYM"
  
  if [ ! -d "$framework_path" ]; then
    echo "❌ 错误: 未找到 ${platform} 框架文件 $framework_path"
    exit 1
  fi
  
  if [ ! -d "$dsym_path" ]; then
    echo "⚠️ 警告: 未找到 ${platform} dSYM文件 $dsym_path"
    # 非致命错误，继续执行
  fi
}

# 构建并校验每个平台
build_and_check() {
  local platform=$1
  local destination=$2
  
  echo "🔨 构建 ${platform}..."
  xcodebuild archive \
    -project RFIDManager.xcodeproj \
    -scheme RFIDManager \
    -destination "$destination" \
    -archivePath "${ARCHIVE_PATH}/RFIDManager-${platform}" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES || exit $?

  check_framework_files "$platform"
}

# 执行构建
build_and_check "iOS" "generic/platform=iOS"
build_and_check "iOS-Simulator" "generic/platform=iOS Simulator"
build_and_check "macOS" "generic/platform=macOS"
build_and_check "Mac-Catalyst" "generic/platform=macOS,variant=Mac Catalyst"


# 合并为 XCFramework
xcodebuild -create-xcframework \
  -framework "${ARCHIVE_PATH}/RFIDManager-iOS.xcarchive/Products/Library/Frameworks/RFIDManager.framework" \
  -debug-symbols "${ARCHIVE_PATH}/RFIDManager-iOS.xcarchive/dSYMs/RFIDManager.framework.dSYM" \
  \
  -framework "${ARCHIVE_PATH}/RFIDManager-iOS-Simulator.xcarchive/Products/Library/Frameworks/RFIDManager.framework" \
  -debug-symbols "${ARCHIVE_PATH}/RFIDManager-iOS-Simulator.xcarchive/dSYMs/RFIDManager.framework.dSYM" \
  \
  -framework "${ARCHIVE_PATH}/RFIDManager-macOS.xcarchive/Products/Library/Frameworks/RFIDManager.framework" \
  -debug-symbols "${ARCHIVE_PATH}/RFIDManager-macOS.xcarchive/dSYMs/RFIDManager.framework.dSYM" \
  \
  -framework "${ARCHIVE_PATH}/RFIDManager-Mac-Catalyst.xcarchive/Products/Library/Frameworks/RFIDManager.framework" \
  -debug-symbols "${ARCHIVE_PATH}/RFIDManager-Mac-Catalyst.xcarchive/dSYMs/RFIDManager.framework.dSYM" \
  \
  -output "${ARCHIVE_PATH}/${FRAMEWORK_NAME}.xcframework"

echo "✅ ${FRAMEWORK_NAME}生成成功"

# 生成 DocC 文档（添加到脚本末尾）
echo "📚 生成 DocC 文档..."

xcodebuild docbuild \
  -scheme "$FRAMEWORK_NAME" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "${ARCHIVE_PATH}/DerivedData" \
  -configuration Release


# 检查文档是否生成成功
DOC_ARCHIVE_PATH="${ARCHIVE_PATH}/DerivedData/Build/Products/Release/${FRAMEWORK_NAME}.doccarchive"
if [ -d "$DOC_ARCHIVE_PATH" ]; then
  echo "✅ DocC 文档生成成功"
else
  echo "⚠️ DocC 文档生成失败"
fi

```

### 不需要附带dSYM：

```
#!/bin/bash

FRAMEWORK_NAME=RFIDManager

# 自动获取版本信息
MARKETING_VERSION=$(xcodebuild -project "$PROJECT_NAME.xcodeproj" -showBuildSettings | grep "MARKETING_VERSION" | head -1 | awk -F "= " '{print $2}')
CURRENT_PROJECT_VERSION=$(xcodebuild -project "$PROJECT_NAME.xcodeproj" -showBuildSettings | grep "CURRENT_PROJECT_VERSION" | head -1 | awk -F "= " '{print $2}')

# 版本号
FRAMEWORK_VERSION="${MARKETING_VERSION}_${CURRENT_PROJECT_VERSION}"

if [ -z "$FRAMEWORK_VERSION" ]; then
  echo "❌ 错误: 无法获取项目版本号"
  exit 1
fi
echo "📦 正在打包 $PROJECT_NAME 版本 $FRAMEWORK_VERSION"


ARCHIVE_PATH="${PROJECT_DIR}/build/archive_v${FRAMEWORK_VERSION}"


# 清理构建目录
rm -rf "${ARCHIVE_PATH}"

# 封装校验函数
check_framework_files() {
  local platform=$1
  local framework_path="${ARCHIVE_PATH}/${FRAMEWORK_NAME}-${platform}.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework"
  local dsym_path="${ARCHIVE_PATH}/${FRAMEWORK_NAME}-${platform}.xcarchive/dSYMs/${FRAMEWORK_NAME}.framework.dSYM"
  
  if [ ! -d "$framework_path" ]; then
    echo "❌ 错误: 未找到 ${platform} 框架文件 $framework_path"
    exit 1
  fi
  
  if [ ! -d "$dsym_path" ]; then
    echo "⚠️ 警告: 未找到 ${platform} dSYM文件 $dsym_path"
    # 非致命错误，继续执行
  fi
}

# 构建并校验每个平台
build_and_check() {
  local platform=$1
  local destination=$2
  
  echo "🔨 构建 ${platform}..."
  xcodebuild archive \
    -project "${FRAMEWORK_NAME}.xcodeproj" \
    -scheme "${FRAMEWORK_NAME}" \
    -destination "$destination" \
    -archivePath "${ARCHIVE_PATH}/${FRAMEWORK_NAME}-${platform}" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES || exit $?

  check_framework_files "$platform"
}

# 执行构建
build_and_check "iOS" "generic/platform=iOS"
build_and_check "iOS-Simulator" "generic/platform=iOS Simulator"
build_and_check "macOS" "generic/platform=macOS"
build_and_check "Mac-Catalyst" "generic/platform=macOS,variant=Mac Catalyst"


# 合并为 XCFramework
xcodebuild -create-xcframework \
  -framework "${ARCHIVE_PATH}/${FRAMEWORK_NAME}-iOS.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
  -framework "${ARCHIVE_PATH}/${FRAMEWORK_NAME}-iOS-Simulator.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
  -framework "${ARCHIVE_PATH}/${FRAMEWORK_NAME}-macOS.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
  -framework "${ARCHIVE_PATH}/${FRAMEWORK_NAME}-Mac-Catalyst.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
  -output "${ARCHIVE_PATH}/${FRAMEWORK_NAME}.xcframework"

echo "✅ ${FRAMEWORK_NAME} SDK 生成成功"

# 生成 DocC 文档（添加到脚本末尾）
echo "📚 生成 DocC 文档..."

xcodebuild docbuild \
  -scheme "${FRAMEWORK_NAME}" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "${ARCHIVE_PATH}/DerivedData" \
  -configuration Release


# 检查文档是否生成成功
DOC_ARCHIVE_PATH="${ARCHIVE_PATH}/DerivedData/Build/Products/Release/${FRAMEWORK_NAME}.doccarchive"
if [ -d "$DOC_ARCHIVE_PATH" ]; then
  echo "✅ DocC 文档生成成功"
  cp -R "${DOC_ARCHIVE_PATH}" "${ARCHIVE_PATH}/${FRAMEWORK_NAME}.doccarchive"
else
  echo "⚠️ DocC 文档生成失败"
fi

```
