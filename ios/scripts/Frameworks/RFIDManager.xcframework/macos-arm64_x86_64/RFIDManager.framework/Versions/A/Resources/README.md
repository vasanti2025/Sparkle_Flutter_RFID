## 打包和发布 SDK 流程

1. 先修改对应版本(下方有教程)，关闭 LogUtil 处的日志开关
2. 选择 Archive，然后点击运行即可自动打包 xcframework 文件 和 docc 文档
3. 选择 Release，然后点击运行即可自动发布到 Github


若 Archive 没配置好，请参考教程 `Document/Archive Auto.md`
若 Release 没配置好，请参考教程 `Document/Release Github.md`


## 修改版本号 

点击项目 -> TARGETS -> Build Settings -> 搜索Version -> Versioning栏目  
CURRENT_PROJECT_VERSION 代表了build号  
MARKETING_VERSION 代表了版本号

User Script Sandboxing  -> NO
Skip Install  -> NO
Build Libraries for Distribution  -> YES
Debug Information Format  -> Release 选择 DWARF with dSYM File


## 撤回发布

```
# 假设撤回版本是这个
RELEASE_TAG="v1.2.1"

# 删除 Release 和标签
gh release delete $RELEASE_TAG --yes
git tag -d $RELEASE_TAG
git push origin :refs/tags/$RELEASE_TAG


# 撤销代码修改
git reset --hard HEAD~1
git push origin main --force
```

## 手动打包SDK

首先进入到SDK项目根目录(RFIDManager.xcodeproj同级的目录)

生成模拟器SDK, 可以选择模拟机然后运行，也可执行：  xcodebuild -scheme RFIDManager -sdk iphonesimulator clean build

生成真机SDK, 可以选择真机然后运行，也可执行:  xcodebuild -scheme RFIDManager -sdk iphoneos

命令行进入到Products目录(菜单栏->Product->Show Build Folder in Finder，注意在SDK项目进入，而不是demo项目), 开始合并:
xcodebuild -create-xcframework \
 -framework ./Release-iphonesimulator/RFIDManager.framework \
 -framework ./Release-iphoneos/RFIDManager.framework \
 -output ./RFIDManager.xcframework

Products目录新生成的 RFIDManager.xcframework 即为sdk文件  
此处只展示了生成 IOS 和 模拟器 SDK

**打包静态库时，将不会生成.dSYM文件，若无特殊需求，打包动态库即可（Mach-O Type）**

可参考资料：
<https://juejin.cn/post/7290375566255259687?searchId=20240416162906245D8210C9AE9DC580C2>
<https://www.jianshu.com/p/058517180685>


## 手动生成文档文件

菜单栏 - Product - Build Documentation, 在生成的文档总目录点击导出即可


在命令行 RFIDManager.doccarchive 目录下，生成静态网站到 site 目录：
xcrun docc process-archive transform-for-static-hosting RFIDManager.doccarchive \
  --output-path ./site
  
进入 site 目录，使用 Node 环境运行静态网站：
npx serve -l 8000 -s .

然后访问路径：
http://localhost:8000/documentation/rfidmanager
